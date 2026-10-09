// Permanent real identity fixture. No production bootstrap or mutable source.
import {readFile,writeFile,mkdtemp,symlink,stat,rm,mkdir,readdir,chmod} from 'node:fs/promises';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {spawn,execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const baseline='b22f734c897710d5f0ffdbc72bd214fb81c17e04';
const tree='20c99e117ce456f22cc54300a0bb9fa756842168';
const digest='cc62c57cba4f4683ff2d2ccdbedb56c5ade8638845c3b787cc71b45a1b467499';
let stage='configuration';
async function main(){
 if(process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA!=='YES'||!process.env.SCRIPTUM_CLIENT_VERIFICATION_PG_CONFIG)throw Error('Explicit config/opt-in required');
 const repo=fileURLToPath(new URL('../../../',import.meta.url)),module=fileURLToPath(new URL('../',import.meta.url));
 const configPath=process.env.SCRIPTUM_CLIENT_VERIFICATION_PG_CONFIG;
 const info=await stat(configPath);if(!info.isFile()||(info.mode&0o077)!==0)throw Error('Private config required');
 const config=JSON.parse(await readFile(configPath,'utf8'));
 const root=await mkdtemp(join(tmpdir(),'scriptum-native-identity-'));
 try{
  stage='snapshot';
  if(execFileSync('git',['-C',repo,'rev-parse',baseline+':Server/WorkspaceService'],{encoding:'utf8'}).trim()!==tree)throw Error('Wrong pinned tree');
  execFileSync('tar',['-x','-C',root],{input:execFileSync('git',['-C',repo,'archive',baseline,'Server/WorkspaceService'],{maxBuffer:16*1024*1024})});
  const service=join(root,'Server/WorkspaceService'),evidence=JSON.parse(await readFile(join(module,'Verification/identity-service-discovery-evidence.json'),'utf8'));
  if(evidence.sourceCommit!==baseline||evidence.gitTree!==tree)throw Error('Wrong discovery manifest scope');
  const hash=createHash('sha256');
  for(const path of evidence.files){if(typeof path!=='string'||path.startsWith('/')||path.includes('..')||path.includes('\\'))throw Error('Invalid manifest');hash.update(path).update('\0').update(await readFile(join(service,path))).update('\0');}
  if(hash.digest('hex')!==digest||evidence.treeSHA256!==digest)throw Error('Manifest mismatch');
  const dependencies=join(repo,'Server/WorkspaceService/node_modules');
  for(const [name,version] of [['pg','8.23.1'],['jose','6.2.12']])if(JSON.parse(await readFile(join(dependencies,name,'package.json'),'utf8')).version!==version)throw Error('Exact dependency required');
  await symlink(dependencies,join(service,'node_modules'));
  const {default:pg}=await import(pathToFileURL(join(dependencies,'pg/lib/index.js')).href);
  const {WorkspaceStore}=await import(pathToFileURL(join(service,'src/workspace-store.ts')).href);
  const {IdentityStore}=await import(pathToFileURL(join(service,'src/identity-store.ts')).href);
  const {migrate}=await import(pathToFileURL(join(service,'src/migrate.ts')).href);
  const {schemaIdentifier}=await import(pathToFileURL(join(service,'src/validation.ts')).href);
  const {createGateway,listenGateway}=await import(pathToFileURL(join(service,'src/http-gateway.ts')).href);
  const {verificationURL}=await import(pathToFileURL(join(service,'test/verification.ts')).href);
  const {ownedIssuer}=await import(pathToFileURL(join(service,'test/helpers/identity-issuer.ts')).href);
  const tls=join(root,'tls');await mkdir(tls,{mode:0o700});
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',join(tls,'key.pem'),'-out',join(tls,'cert.pem'),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],{stdio:'ignore'});
  await chmod(join(tls,'key.pem'),0o600);process.env.SCRIPTUM_TEST_TLS_DIRECTORY=tls;
  stage='database';
  const pool=new pg.Pool({connectionString:verificationURL(config.url,'YES'),max:8,connectionTimeoutMillis:3000,statement_timeout:5000,query_timeout:6000});
  const schema='wsverify_native_identity_'+randomUUID().replaceAll('-',''),identifier=schemaIdentifier(schema);
  const lock=await pool.connect().catch(async error=>{await pool.end();throw error;});
  let owned=false,issuer,gateway,controller;
  try{
   const version=await pool.query('SHOW server_version_num');if(Math.floor(Number(version.rows[0].server_version_num)/10000)!==18)throw Error('PG18 required');
   await lock.query('SELECT pg_advisory_lock(hashtextextended($1,0))',['scriptum:native-identity:'+schema]);
   await pool.query('CREATE SCHEMA '+identifier);owned=true;await migrate(pool,schema);
   issuer=await ownedIssuer(join(root,'vault'));
   const identity=new IdentityStore(pool,schema,[issuer]),workspace=new WorkspaceStore(pool,schema);
   gateway=createGateway(workspace,{identity});const origin=await listenGateway(gateway);
   const controlSecret=randomBytes(32).toString('base64url'),subjects={owner:'native-owner-'+randomUUID(),viewer:'native-viewer-'+randomUUID()};
   controller=createServer((req,res)=>{
    void(async()=>{
     if(req.headers.authorization!=='Bearer '+controlSecret){res.writeHead(401);res.end();return;}
     if(req.method!=='POST'){res.writeHead(405);res.end();return;}
     const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>1024)throw Error('Bound');chunks.push(chunk);}
     const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));let result;
     if(req.url==='/authorize'){
      if(!['owner','viewer'].includes(body.account)||typeof body.nonce!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(body.nonce))throw Error('Invalid fixture request');
      const proof=await issuer.authorize(body.nonce,subjects[body.account]);result={identityToken:proof.identityToken,authorizationCode:proof.authorizationCode};
     }else if(req.url==='/key'){
      if(typeof body.libraryID!=='string'||!/^[0-9a-f-]{36}$/i.test(body.libraryID))throw Error('Invalid fixture scope');
      const keyReference='synthetic:native:'+randomUUID();await pool.query(`INSERT INTO ${identifier}.encryption_keys(reference,library_id) VALUES($1,$2)`,[keyReference,body.libraryID]);result={keyReference};
     }else{res.writeHead(404);res.end();return;}
     res.writeHead(200,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(result));
    })().catch(()=>{if(!res.writableEnded){res.writeHead(400);res.end();}});
   });
   const controlOrigin=await listenGateway(controller),file=join(root,'private-fixture.json');
   await writeFile(file,JSON.stringify({origin,controlOrigin,controlSecret,profileID:issuer.profile.profileID,consentVersion:issuer.profile.consentVersion}),{mode:0o600});
   stage='compile';
   const source=join(module,'Sources/SkriptumWorkspaceClient'),files=(await readdir(source)).filter(name=>name.endsWith('.swift')).sort().map(name=>join(source,name));
   execFileSync('xcrun',['swiftc','-swift-version','6','-parse-as-library',...files,join(module,'Verification/IdentityServerProbe.swift'),'-o',join(root,'probe')],{timeout:30000,stdio:'inherit'});
   stage='Swift identity flow';
   const exit=await new Promise(resolve=>{const child=spawn(join(root,'probe'),[file],{stdio:'inherit'});const timer=setTimeout(()=>child.kill('SIGTERM'),30000);child.on('exit',code=>{clearTimeout(timer);resolve(code);});});
   if(exit!==0)throw Error('Identity probe failed');
   stage='durable readback';
   const rows=await pool.query(`SELECT (SELECT count(*) FROM ${identifier}.accounts WHERE tombstoned_at IS NOT NULL)::int AS deleted,(SELECT count(*) FROM ${identifier}.pages)::int AS pages,(SELECT count(*) FROM ${identifier}.libraries)::int AS libraries,(SELECT count(*) FROM ${identifier}.server_sessions WHERE revoked_at IS NULL AND expires_at>clock_timestamp())::int AS live`);
   const row=rows.rows[0];if(row.deleted!==1||row.pages!==1||row.libraries!==1||row.live!==1)throw Error('Unexpected durable result');
   if(issuer.state.jwksRequests<1||issuer.state.tokenRequests!==4)throw Error('Signed exchange not executed');
   const revoked=await identity.compensate(10);if(revoked<1||issuer.state.revokeRequests<1)throw Error('Provider revocation not dispatched');
   console.log('Pinned signed HTTPS/HTTP/PG18 identity verification PASS; exact library/page retained; logout-all sessions revoked; provider revocation dispatched.');
  }finally{
   for(const server of [controller,gateway])if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
   if(issuer)await issuer.close();
   try{if(owned)await pool.query('DROP SCHEMA '+identifier+' CASCADE');}finally{await lock.query('SELECT pg_advisory_unlock(hashtextextended($1,0))',['scriptum:native-identity:'+schema]);lock.release();await pool.end();}
  }
 }finally{await rm(root,{recursive:true,force:true});}
}
main().catch(()=>{console.error('Identity verification failed at '+stage+' (details redacted).');process.exitCode=1;});
