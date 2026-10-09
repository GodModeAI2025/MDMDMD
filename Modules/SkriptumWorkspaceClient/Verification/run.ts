import {readFile,writeFile,unlink,mkdtemp,symlink,stat,rm} from 'node:fs/promises';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {spawn,execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const baseline='78f879f7fe96bac2b637ba7fdc31aa0a7b5c6713';
const tree='2e8e9400b80bc52cc5f7a363ce2c8653ad68d083';
const gatewayDigest='51f845d8e5ed08ffa22843a283a51347ac27c9e8ad63406c54b77d3cf97ae5b7';
async function main(){
 if(process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA!=='YES'||!process.env.SCRIPTUM_CLIENT_VERIFICATION_PG_CONFIG)throw Error('Explicit verification opt-in/config required');
 const repo=fileURLToPath(new URL('../../../',import.meta.url));
 const configFile=process.env.SCRIPTUM_CLIENT_VERIFICATION_PG_CONFIG;
 const info=await stat(configFile);if(!info.isFile()||(info.mode&0o077)!==0)throw Error('Private config required');
 const config=JSON.parse(await readFile(configFile,'utf8'));
 const snapshot=await mkdtemp(join(tmpdir(),'scriptum-workspace-client-'));
 try{
  if(execFileSync('git',['-C',repo,'rev-parse',baseline+':Server/WorkspaceService'],{encoding:'utf8'}).trim()!==tree)throw Error('Baseline tree mismatch');
  const archive=execFileSync('git',['-C',repo,'archive',baseline,'Server/WorkspaceService'],{maxBuffer:16*1024*1024});
  execFileSync('tar',['-x','-C',snapshot],{input:archive});
  const service=join(snapshot,'Server/WorkspaceService');
  if(createHash('sha256').update(await readFile(join(service,'src/http-gateway.ts'))).digest('hex')!==gatewayDigest)throw Error('Gateway hash mismatch');
  const dependencies=join(repo,'Server/WorkspaceService/node_modules');
  const pgPackage=JSON.parse(await readFile(join(dependencies,'pg/package.json'),'utf8'));if(pgPackage.version!=='8.23.1')throw Error('Exact PG dependency required');
  await symlink(dependencies,join(service,'node_modules'));
  const {default: pg}=await import(pathToFileURL(join(dependencies,'pg/lib/index.js')).href);
  const {Pool}=pg;
  const {WorkspaceStore,sessionDigest}=await import(pathToFileURL(join(service,'src/workspace-store.ts')).href);
  const {migrate}=await import(pathToFileURL(join(service,'src/migrate.ts')).href);
  const {schemaIdentifier}=await import(pathToFileURL(join(service,'src/validation.ts')).href);
  const {createGateway,listenGateway}=await import(pathToFileURL(join(service,'src/http-gateway.ts')).href);
  const {verificationURL}=await import(pathToFileURL(join(service,'test/verification.ts')).href);
const pool=new Pool({connectionString:verificationURL(config.url,'YES'),max:8,connectionTimeoutMillis:3000,statement_timeout:5000,query_timeout:6000});
const schema='wsverify_client_'+randomUUID().replaceAll('-','');
const identifier=schemaIdentifier(schema);
const lock=await pool.connect().catch(async error=>{await pool.end();throw error;});
let owned=false,attackHits=0;
const servers=[];
let slowArrivals=0; const slowPending=new Set();
let admitted=false, delayedCount=0; const delayedPending=[];
const file=join(snapshot,'private-fixture.json');
async function fixtureServer(kind){
 const server=createServer((req,res)=>{
  res.setHeader('content-type','application/json');
  if(kind==='redirect'){
   if(req.url==='/forbidden'){attackHits++;res.end('{"ready":true}');return;}
   res.writeHead(302,{location:'/forbidden'});res.end();
  }else if(kind==='slow'){
   if(req.url==='/control/arrivals'){res.end(JSON.stringify({count:slowArrivals}));return;}
   if(req.url==='/control/release'){for(const pending of slowPending)pending.end('{"ready":true}');slowPending.clear();res.end('{}');return;}
   slowArrivals++;slowPending.add(res);res.on('close',()=>slowPending.delete(res));
  }
  else if(kind==='oversized'){res.writeHead(200);res.write('{"ready":"');for(let i=0;i<100;i++)res.write('x'.repeat(1024));res.end('"}');}
  else res.end('{"ready":1}');
 });servers.push(server);return await listenGateway(server);
}
try{
 const version=await pool.query('SHOW server_version_num');if(Math.floor(Number(version.rows[0].server_version_num)/10000)!==18)throw Error('PG18 required');
 await lock.query('SELECT pg_advisory_lock(hashtextextended($1,0))',['scriptum:client-verification:'+schema]);
 await pool.query('CREATE SCHEMA '+identifier);owned=true;await migrate(pool,schema);
 async function identity(){const id=randomUUID(),token=randomBytes(32).toString('base64url');await pool.query(`INSERT INTO ${identifier}.accounts(id,identity_issuer,identity_subject) VALUES($1,'synthetic-client',$2)`,[id,id]);await pool.query(`INSERT INTO ${identifier}.server_sessions(id,account_id,token_digest,expires_at) VALUES($1,$2,$3,clock_timestamp()+interval '1 hour')`,[randomUUID(),id,sessionDigest(token)]);return{id,token};}
 const owner=await identity(),viewer=await identity(),delayed=await identity();const store=new WorkspaceStore(pool,schema);
 const libraryID=await store.createLibrary(owner.token,'Client fixture'),spaceID=await store.createSpace(owner.token,libraryID,'Client fixture');
 const keyReference='synthetic:client:'+randomUUID();await pool.query(`INSERT INTO ${identifier}.encryption_keys(reference,library_id) VALUES($1,$2)`,[keyReference,libraryID]);
 const pageID=randomUUID();await store.createPage(owner.token,{libraryID,spaceID,pageID},{ciphertext:randomBytes(64),nonce:randomBytes(12),digest:randomBytes(32),keyReference,version:1});
 await store.setMembership(owner.token,{libraryID,kind:'library'},viewer.id,1);await store.setMembership(owner.token,{libraryID,kind:'library'},delayed.id,1);
 const gateway=createGateway(store);servers.push(gateway);const origin=await listenGateway(gateway);
 const delayedServer=createServer(async(req,res)=>{
  if(req.url==='/control/admitted'){res.setHeader('content-type','application/json');res.end(JSON.stringify({admitted,count:delayedCount}));return;}
  if(req.url==='/control/release'){for(const pending of delayedPending){pending.response.writeHead(pending.status,pending.headers);pending.response.end(pending.bytes);}delayedPending.length=0;res.setHeader('content-type','application/json');res.end('{}');return;}
  if(req.url==='/session/logout'){
   const reply=await fetch(origin+req.url,{method:'POST',headers:{authorization:req.headers.authorization??''}});res.writeHead(reply.status,Object.fromEntries(reply.headers));res.end(Buffer.from(await reply.arrayBuffer()));return;
  }
  delayedCount++;
  const reply=await fetch(origin+req.url,{headers:{authorization:req.headers.authorization??''}});
  const bytes=Buffer.from(await reply.arrayBuffer());
  delayedPending.push({response:res,status:reply.status,headers:Object.fromEntries(reply.headers),bytes});admitted=true;
 });servers.push(delayedServer);const delayedOrigin=await listenGateway(delayedServer);
 const fixture={origin,delayedOrigin,delayedToken:delayed.token,delayedID:delayed.id,ownerID:owner.id,ownerToken:owner.token,viewerID:viewer.id,viewerToken:viewer.token,libraryID,spaceID,pageID,keyReference,redirectOrigin:await fixtureServer('redirect'),oversizedOrigin:await fixtureServer('oversized'),malformedOrigin:await fixtureServer('malformed'),slowOrigin:await fixtureServer('slow')};
 await writeFile(file,JSON.stringify(fixture),{mode:0o600});
 const exit=await new Promise(resolve=>{const process=spawn('/usr/bin/swift',['test','--package-path',join(repo,'Modules/SkriptumWorkspaceClient'),'--disable-sandbox','--scratch-path',join(snapshot,'SwiftBuild')],{env:{...globalThis.process.env,SCRIPTUM_CLIENT_VERIFICATION_FIXTURE:file},stdio:'inherit'});const timer=setTimeout(()=>process.kill('SIGTERM'),30000);process.on('exit',code=>{clearTimeout(timer);resolve(code);});});
 if(exit!==0)throw Error('Swift client verification failed');
 if(attackHits!==0)throw Error('Redirect followed');
 const receipts=await pool.query(`SELECT count(*)::int AS count FROM ${identifier}.page_revisions`);if(receipts.rows[0].count!==1)throw Error('Unexpected history count');
 console.log('Real Swift/HTTP/PG18 verification passed; redirect target untouched; one CAS history row.');
}finally{
 for(const server of servers){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
 try{if(owned)await pool.query('DROP SCHEMA '+identifier+' CASCADE');}finally{await lock.query('SELECT pg_advisory_unlock(hashtextextended($1,0))',['scriptum:client-verification:'+schema]);lock.release();await pool.end();await unlink(file).catch(()=>{});}
}

 }finally{await rm(snapshot,{recursive:true,force:true});}
}
main().catch(()=>{console.error('Workspace client verification failed (details redacted).');process.exitCode=1;});
