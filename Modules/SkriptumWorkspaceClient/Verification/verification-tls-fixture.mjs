import https from "node:https";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const root = process.argv[2];
if (!root?.startsWith("/private/tmp/ScriptumVerificationTLS-")) throw new Error("owned root required");
const info = fs.lstatSync(root);
if (!info.isDirectory() || info.isSymbolicLink() || (info.mode & 0o077) !== 0) throw new Error("private directory required");
process.umask(0o077);
for (const name of ["server-root", "wrong"]) {
  execFileSync("/opt/homebrew/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=Owned verification CA", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign", "-keyout", path.join(root, name + ".key"), "-out", path.join(root, name + ".pem")], { stdio: "ignore", timeout: 10000 });
  execFileSync("/opt/homebrew/bin/openssl", ["x509", "-in", path.join(root, name + ".pem"), "-outform", "DER", "-out", path.join(root, name === "server-root" ? "server.der" : "wrong.der")], { stdio: "ignore", timeout: 5000 });
}
execFileSync("/opt/homebrew/bin/openssl", ["req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=127.0.0.1", "-keyout", path.join(root, "server.key"), "-out", path.join(root, "server.csr")], { stdio: "ignore", timeout: 10000 });
fs.writeFileSync(path.join(root, "server.ext"), "subjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n", { mode: 0o600 });
execFileSync("/opt/homebrew/bin/openssl", ["x509", "-req", "-in", path.join(root, "server.csr"), "-CA", path.join(root, "server-root.pem"), "-CAkey", path.join(root, "server-root.key"), "-CAcreateserial", "-days", "1", "-extfile", path.join(root, "server.ext"), "-out", path.join(root, "server.pem")], { stdio: "ignore", timeout: 5000 });
const server = https.createServer({ key: fs.readFileSync(path.join(root, "server.key")), cert: fs.readFileSync(path.join(root, "server.pem")) }, (request, response) => {
  if (request.url === "/redirect") { response.writeHead(302, { location: "/ok" }); response.end(); return; }
  if (request.url === "/oversized") { response.writeHead(200, { "content-type": "application/json" }); response.end("x".repeat(65537)); return; }
  if (request.url === "/credential") { response.writeHead(401, { "www-authenticate": "Basic realm=owned" }); response.end(); return; }
  response.writeHead(200, { "content-type": "application/json" }); response.end('{"ready":true}');
});
server.on("tlsClientError", () => {});
server.listen(0, "127.0.0.1", () => {
  const pending = path.join(root, "ready.json.pending");
  fs.writeFileSync(pending, JSON.stringify({ port: server.address().port }), { mode: 0o600 });
  fs.renameSync(pending, path.join(root, "ready.json"));
});
const stop = () => {
  server.closeAllConnections();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 1000).unref();
};
process.on("SIGTERM", stop); process.on("SIGINT", stop);
