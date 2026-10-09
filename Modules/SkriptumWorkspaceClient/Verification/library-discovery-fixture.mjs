// Owned loopback transport fixture only; not a production identity authority.
import {createServer} from 'node:http';
import {randomBytes, randomUUID} from 'node:crypto';
import {writeFile, rename} from 'node:fs/promises';

const file = process.argv[2];
if (!file) throw new Error('Missing owned output path');
const token = randomBytes(32).toString('base64url');
const accountID = randomUUID();
const libraryID = '00000000-0000-4000-8000-000000000001';
let pending;
function reply(response, code, body) {
  response.writeHead(code, {'content-type':'application/json', 'cache-control':'no-store'});
  response.end(body === undefined ? undefined : JSON.stringify(body));
}
const server = createServer((request, response) => {
  if (request.url === '/control/state') { reply(response, 200, {pending: Boolean(pending)}); return; }
  if (request.url === '/control/release') {
    if (pending) { reply(pending.response, 200, pending.body); pending = undefined; }
    reply(response, 200, {}); return;
  }
  if (request.headers.authorization !== 'Bearer ' + token) { reply(response, 401, {error:'unauthenticated'}); return; }
  if (request.method === 'POST' && request.url === '/session/logout') { reply(response, 204); return; }
  const row = {libraryID, title:'e\u0301\r\n🦊', role:'viewer'};
  if (request.method === 'GET' && (request.url === '/libraries' || request.url === '/libraries/' + libraryID)) {
    if (pending) { reply(response, 503, {error:'unavailable'}); return; }
    pending = {response, body:request.url === '/libraries' ? {libraries:[row], nextAfter:null} : row};
    return;
  }
  reply(response, 404, {error:'not_found'});
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
await writeFile(file + '.pending', JSON.stringify({origin:'http://127.0.0.1:' + server.address().port, accountID, token}), {mode:0o600});
await rename(file + '.pending', file);
process.stdin.resume();
