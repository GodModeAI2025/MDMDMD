// Controlled HTTP lifecycle contract fixture only, not an identity authority.
import {createServer} from 'node:http';
import {randomBytes,randomUUID} from 'node:crypto';
import {writeFile,rename} from 'node:fs/promises';
const file=process.argv[2]; if(!file)throw Error('Owned fixture path required');
const accountID=randomUUID(),sessionID=randomUUID(),oldToken=randomBytes(32).toString('base64url'),token=randomBytes(32).toString('base64url'),random=()=>randomBytes(32).toString('base64url');
const challenge={challengeID:randomUUID(),challengeSecret:random(),nonce:random(),state:random(),expiresAt:new Date(Date.now()+300000).toISOString()};
let pending401,pendingEnroll,logoutCount=0,accountDeleteCount=0,failLogout=false;
function reply(res,status,body){res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'});res.end(body===undefined?undefined:JSON.stringify(body));}
const server=createServer((req,res)=>{
 if(req.url==='/control/failLogout'){failLogout=true;reply(res,200,{});return;}
 if(req.url==='/control/state'){reply(res,200,{pending401:!!pending401,pendingEnroll:!!pendingEnroll,logoutCount,accountDeleteCount});return;}
 if(req.url==='/control/release401'){if(pending401){reply(pending401,401,{error:'unauthenticated'});pending401=undefined;}reply(res,200,{});return;}
 if(req.url==='/control/releaseEnrollment'){if(pendingEnroll){reply(pendingEnroll,201,{sessionToken:token,sessionID,accountID,expiresAt:new Date(Date.now()+28800000).toISOString(),reauthenticationReceipt:random()});pendingEnroll=undefined;}reply(res,200,{});return;}
 if(req.url==='/identity/challenges'){reply(res,201,challenge);return;}
 if(req.url==='/identity/enroll'){let size=0;req.on('data',chunk=>{size+=chunk.length;if(size>24576)req.destroy();});req.on('end',()=>{pendingEnroll=res;});return;}
 if(req.url==='/session' && req.headers.authorization==='Bearer '+oldToken){pending401=res;return;}
 if(req.url==='/session'){reply(res,200,{sessionID,accountID,expiresAt:new Date(Date.now()+28800000).toISOString()});return;}
 if(req.url==='/session/logout' || req.url==='/session/logout-all'){logoutCount++;reply(res,failLogout?503:204,failLogout?{error:'unavailable'}:undefined);return;}
 if(req.url==='/account'){accountDeleteCount++;reply(res,204);return;}
 reply(res,404,{error:'not_found'});
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
await writeFile(file+'.pending',JSON.stringify({origin:'http://127.0.0.1:'+server.address().port,accountID,oldToken}),{mode:0o600});
await rename(file+'.pending',file);
process.stdin.resume();process.stdin.on('end',()=>server.close());
process.on('SIGTERM',()=>{server.closeAllConnections();server.close(()=>process.exit(0));});
setTimeout(()=>{server.closeAllConnections();server.close(()=>process.exit(1));},15000).unref();
