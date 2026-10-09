import { createHash, randomUUID } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import { transaction } from './transaction.ts';
import { boundedTitle, effectiveRole, parseUUID, validateEnvelope, WorkspaceError } from './validation.ts';
import type { EncryptedEnvelope, RoleRank } from './validation.ts';
export interface PageAddress { libraryID: string; spaceID: string; pageID: string }
export type MembershipAddress = {libraryID: string; kind: 'library'; spaceID?: never; pageID?: never} | {libraryID: string; kind: 'space'; spaceID: string; pageID?: never} | {libraryID: string; kind: 'page'; spaceID: string; pageID: string};
interface VerifiedSession { accountID: string; sessionID: string }
export function sessionDigest(token: string): Buffer {
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43,128}$/.test(token)) throw new WorkspaceError('unauthenticated');
  return createHash('sha256').update(token).digest();
}
async function authenticate(client: PoolClient, token: string, lock: 'FOR SHARE' | 'FOR UPDATE' = 'FOR SHARE'): Promise<VerifiedSession> {
  const session = await client.query<{id: string; account_id: string}>('SELECT id, account_id FROM server_sessions WHERE token_digest=$1 AND revoked_at IS NULL AND expires_at > clock_timestamp() ' + lock, [sessionDigest(token)]);
  const row = session.rows[0]; if (!row) throw new WorkspaceError('unauthenticated');
  return {accountID: row.account_id, sessionID: row.id};
}
async function lockLibrary(client: PoolClient, libraryID: string): Promise<{owner_account_id: string; delegation_ceiling: RoleRank}> {
  const library = await client.query<{owner_account_id: string; delegation_ceiling: RoleRank}>('SELECT owner_account_id, delegation_ceiling FROM libraries WHERE id=$1 FOR UPDATE', [parseUUID(libraryID)]);
  const row = library.rows[0]; if (!row) throw new WorkspaceError('missing'); return row;
}
function membershipAddress(value: MembershipAddress): MembershipAddress {
  const libraryID = parseUUID(value.libraryID);
  if (value.kind === 'library') return {libraryID,kind:'library'};
  const spaceID = parseUUID(value.spaceID);
  if (value.kind === 'space') return {libraryID,spaceID,kind:'space'};
  return {libraryID,spaceID,pageID:parseUUID(value.pageID),kind:'page'};
}
async function rank(client: PoolClient, session: VerifiedSession, address: MembershipAddress): Promise<RoleRank> {
  const library = await lockLibrary(client, address.libraryID);
  const current = await client.query('SELECT id FROM server_sessions WHERE id=$1 AND account_id=$2 AND revoked_at IS NULL AND expires_at>clock_timestamp()', [session.sessionID,session.accountID]);
  if (current.rowCount !== 1) throw new WorkspaceError('unauthenticated');
  const isOwner = library.owner_account_id === session.accountID;
  const memberships = await client.query<{resource_kind: string; space_id: string | null; page_id: string | null; role_rank: RoleRank}>('SELECT resource_kind, space_id, page_id, role_rank FROM memberships WHERE library_id=$1 AND account_id=$2', [address.libraryID, session.accountID]);
  const inherited = memberships.rows.find(row => row.resource_kind === 'library')?.role_rank ?? 0;
  let value: RoleRank = isOwner ? 3 : effectiveRole(inherited, undefined, library.delegation_ceiling);
  if (address.kind !== 'library') {
    const space = await client.query<{delegation_ceiling: RoleRank}>('SELECT delegation_ceiling FROM spaces WHERE library_id=$1 AND id=$2', [address.libraryID, parseUUID(address.spaceID)]);
    if (!space.rows[0]) throw new WorkspaceError('missing');
    const override = memberships.rows.find(row => row.resource_kind === 'space' && row.space_id === address.spaceID)?.role_rank;
    if (!isOwner) value = effectiveRole(value, override, space.rows[0].delegation_ceiling);
  }
  if (address.kind === 'page') {
    const page = await client.query<{delegation_ceiling: RoleRank}>('SELECT delegation_ceiling FROM pages WHERE library_id=$1 AND space_id=$2 AND id=$3', [address.libraryID, address.spaceID, parseUUID(address.pageID)]);
    if (!page.rows[0]) throw new WorkspaceError('missing');
    const override = memberships.rows.find(row => row.resource_kind === 'page' && row.space_id === address.spaceID && row.page_id === address.pageID)?.role_rank;
    if (!isOwner) value = effectiveRole(value, override, page.rows[0].delegation_ceiling);
  }
  return value;
}
async function audit(client: PoolClient, session: VerifiedSession, libraryID: string, event: string, resourceID: string): Promise<void> { await client.query('INSERT INTO audit(library_id, account_id, event, resource_id) VALUES($1,$2,$3,$4)', [libraryID, session.accountID, event, resourceID]); }
function address(value: PageAddress): PageAddress { return {libraryID: parseUUID(value.libraryID), spaceID: parseUUID(value.spaceID), pageID: parseUUID(value.pageID)}; }
export class WorkspaceStore {
  readonly pool: Pool; readonly schema: string;
  constructor(pool: Pool, schema: string) {
    // pg-pool's own acquisition timer bounds queued work; no Promise.race leaves
    // an uncounted acquire/query running after a synthetic deadline.
    const timeout = pool.options.connectionTimeoutMillis;
    pool.options.connectionTimeoutMillis = timeout && timeout > 0 ? Math.min(timeout, 5000) : 5000;
    this.pool = pool; this.schema = schema;
  }
  async validateSession(token: string): Promise<void> {
    await transaction(this.pool, this.schema, async client => { await authenticate(client, token); });
  }
  async revokeSession(token: string): Promise<void> {
    await transaction(this.pool, this.schema, async client => {
      const session = await authenticate(client, token, 'FOR UPDATE');
      await client.query('UPDATE server_sessions SET revoked_at=clock_timestamp() WHERE id=$1', [session.sessionID]);
    });
  }
  async isReady(): Promise<boolean> {
    try {
      return await transaction(this.pool, this.schema, async client => {
        const result = await client.query<{count:string; maximum:number}>('SELECT count(*) AS count,max(version) AS maximum FROM schema_migrations');
        return Number(result.rows[0]?.count) === 2 && result.rows[0]?.maximum === 2;
      });
    } catch { return false; }
  }
  async createLibrary(token: string, title: string): Promise<string> {
    boundedTitle(title);
    return transaction(this.pool, this.schema, async client => { const session = await authenticate(client, token), id = randomUUID(); await client.query('INSERT INTO libraries(id,owner_account_id,title) VALUES($1,$2,$3)', [id,session.accountID,title]); await audit(client,session,id,'library.create',id); return id; });
  }
  async createSpace(token: string, libraryID: string, title: string, spaceID: string = randomUUID()): Promise<string> {
    boundedTitle(title); libraryID = parseUUID(libraryID); spaceID = parseUUID(spaceID);
    return transaction(this.pool, this.schema, async client => { const session = await authenticate(client,token); if (await rank(client,session,{libraryID,kind:'library'}) < 3) throw new WorkspaceError('forbidden'); await client.query('INSERT INTO spaces(library_id,id,title,delegation_ceiling) SELECT id,$2,$3,delegation_ceiling FROM libraries WHERE id=$1', [libraryID,spaceID,title]); await audit(client,session,libraryID,'space.create',spaceID); return spaceID; });
  }
  async createPage(token: string, target: PageAddress, envelope: EncryptedEnvelope): Promise<string> {
    target = address(target); validateEnvelope(envelope);
    return transaction(this.pool, this.schema, async client => { const session = await authenticate(client,token); if (await rank(client,session,{libraryID:target.libraryID,kind:'space',spaceID:target.spaceID}) < 2) throw new WorkspaceError('forbidden'); const revision = randomUUID(); await client.query('INSERT INTO pages(library_id,space_id,id,revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version,delegation_ceiling) SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,LEAST(s.delegation_ceiling,l.delegation_ceiling) FROM spaces s JOIN libraries l ON l.id=s.library_id WHERE s.library_id=$1 AND s.id=$2', [target.libraryID,target.spaceID,target.pageID,revision,envelope.ciphertext,envelope.nonce,envelope.digest,envelope.keyReference,envelope.version]); await audit(client,session,target.libraryID,'page.create',target.pageID); return revision; });
  }
  async readPage(token: string, target: PageAddress): Promise<{revision: string; envelope: EncryptedEnvelope}> {
    target = address(target);
    return transaction(this.pool,this.schema,async client => { const session = await authenticate(client,token); if (await rank(client,session,{...target,kind:'page'}) < 1) throw new WorkspaceError('forbidden'); const result = await client.query<{revision:string;source_ciphertext:Buffer;source_nonce:Buffer;source_digest:Buffer;key_reference:string;envelope_version:1}>('SELECT revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version FROM pages WHERE library_id=$1 AND space_id=$2 AND id=$3',[target.libraryID,target.spaceID,target.pageID]); const row=result.rows[0]; if(!row)throw new WorkspaceError('missing'); return {revision:row.revision,envelope:{ciphertext:row.source_ciphertext,nonce:row.source_nonce,digest:row.source_digest,keyReference:row.key_reference,version:row.envelope_version}}; });
  }
  async writePage(token: string, target: PageAddress, expectedRevision: string, envelope: EncryptedEnvelope): Promise<string> {
    target=address(target); parseUUID(expectedRevision); validateEnvelope(envelope);
    return transaction(this.pool,this.schema,async client => { const session=await authenticate(client,token); if(await rank(client,session,{...target,kind:'page'}) < 2)throw new WorkspaceError('forbidden'); const revision=randomUUID(); await client.query('INSERT INTO page_revisions(library_id,space_id,page_id,revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version) SELECT library_id,space_id,id,revision,source_ciphertext,source_nonce,source_digest,key_reference,envelope_version FROM pages WHERE library_id=$1 AND space_id=$2 AND id=$3 AND revision=$4 AND trashed_at IS NULL', [target.libraryID,target.spaceID,target.pageID,expectedRevision]); const update=await client.query('UPDATE pages SET revision=$4,source_ciphertext=$5,source_nonce=$6,source_digest=$7,key_reference=$8,envelope_version=$9,modified_at=clock_timestamp() WHERE library_id=$1 AND space_id=$2 AND id=$3 AND revision=$10 AND trashed_at IS NULL',[target.libraryID,target.spaceID,target.pageID,revision,envelope.ciphertext,envelope.nonce,envelope.digest,envelope.keyReference,envelope.version,expectedRevision]); if(update.rowCount!==1)throw new WorkspaceError('conflict'); await audit(client,session,target.libraryID,'page.write',target.pageID);return revision; });
  }
  async setMembership(token: string, target: MembershipAddress, accountID: string, role: RoleRank): Promise<void> {
    accountID = parseUUID(accountID); target = membershipAddress(target); if(!Number.isInteger(role)||role<0||role>3)throw new WorkspaceError('invalid');
    return transaction(this.pool,this.schema,async client => { const session=await authenticate(client,token); const manager=await rank(client,session,target); if(manager<3)throw new WorkspaceError('forbidden'); const library=await lockLibrary(client,target.libraryID); let ceiling=library.delegation_ceiling;
      if(target.kind!=='library'){const space=await client.query<{delegation_ceiling:RoleRank}>('SELECT delegation_ceiling FROM spaces WHERE library_id=$1 AND id=$2',[target.libraryID,target.spaceID]);ceiling=effectiveRole(ceiling,undefined,space.rows[0]!.delegation_ceiling);}
      if(target.kind==='page'){const page=await client.query<{delegation_ceiling:RoleRank}>('SELECT delegation_ceiling FROM pages WHERE library_id=$1 AND space_id=$2 AND id=$3',[target.libraryID,target.spaceID,target.pageID]);ceiling=effectiveRole(ceiling,undefined,page.rows[0]!.delegation_ceiling);}
      if(role>ceiling||role>manager||accountID===library.owner_account_id)throw new WorkspaceError('forbidden');
      await client.query('INSERT INTO memberships(id,library_id,account_id,resource_kind,space_id,page_id,role_rank) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(library_id,account_id,resource_kind,space_id,page_id) DO UPDATE SET role_rank=EXCLUDED.role_rank',[randomUUID(),target.libraryID,accountID,target.kind,target.kind==='library'?null:target.spaceID,target.kind==='page'?target.pageID:null,role]);await audit(client,session,target.libraryID,'membership.set',accountID); });
  }
  async revokeMembership(token: string, target: MembershipAddress, accountID: string): Promise<void> {
    accountID = parseUUID(accountID); target = membershipAddress(target);
    return transaction(this.pool,this.schema,async client => {const session=await authenticate(client,token);if(await rank(client,session,target)<3)throw new WorkspaceError('forbidden');await client.query('DELETE FROM memberships WHERE library_id=$1 AND account_id=$2 AND resource_kind=$3 AND space_id IS NOT DISTINCT FROM $4 AND page_id IS NOT DISTINCT FROM $5',[target.libraryID,accountID,target.kind,target.kind==='library'?null:target.spaceID,target.kind==='page'?target.pageID:null]);await audit(client,session,target.libraryID,'membership.revoke',accountID);});
  }
}
