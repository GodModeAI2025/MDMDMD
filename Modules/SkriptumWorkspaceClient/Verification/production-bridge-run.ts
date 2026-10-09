// Owned HTTPS/PG fixture for the production-adapter bridge. Execution requires
// the signed enrollment/list/binding assertions, not merely startup construction.
import { readFile, writeFile, mkdtemp, mkdir, chmod, symlink, stat, rm, rename } from "node:fs/promises";
import { randomUUID, randomBytes, createHash } from "node:crypto";
import { execFileSync, spawn } from "node:child_process";
import { createServer as httpsServer } from "node:https";
import { createServer as httpServer, request as httpRequest } from "node:http";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import { join } from "node:path";

const baseline = "b22f734c897710d5f0ffdbc72bd214fb81c17e04";
const tree = "20c99e117ce456f22cc54300a0bb9fa756842168";
const digest = "cc62c57cba4f4683ff2d2ccdbedb56c5ade8638845c3b787cc71b45a1b467499";
const filter = "pickerProductionBridgeFactoryPreservesExactRegistryAndOwnedDocuments";
let stage = "configuration";

async function main() {
  if (process.env.SCRIPTUM_ALLOW_VERIFICATION_SCHEMA !== "YES" || !process.env.SCRIPTUM_CLIENT_VERIFICATION_PG_CONFIG)
    throw Error("Explicit owned fixture opt-in required");
  const repo = fileURLToPath(new URL("../../../", import.meta.url));
  const module = fileURLToPath(new URL("../", import.meta.url));
  const configPath = process.env.SCRIPTUM_CLIENT_VERIFICATION_PG_CONFIG;
  const configInfo = await stat(configPath);
  if (!configInfo.isFile() || (configInfo.mode & 0o077) !== 0 || configInfo.size > 16384)
    throw Error("Private bounded configuration required");
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const root = await mkdtemp(join(tmpdir(), "scriptum-production-bridge-"));
  await chmod(root, 0o700);
  const previousTLSDirectory = process.env.SCRIPTUM_TEST_TLS_DIRECTORY;
  try {
    stage = "immutable snapshot";
    if (execFileSync("git", ["-C", repo, "rev-parse", baseline + ":Server/WorkspaceService"], { encoding: "utf8" }).trim() !== tree)
      throw Error("Wrong service tree");
    execFileSync("tar", ["-x", "-C", root], { input: execFileSync("git", ["-C", repo, "archive", baseline, "Server/WorkspaceService"], { maxBuffer: 16 * 1024 * 1024 }) });
    const service = join(root, "Server/WorkspaceService");
    const evidence = JSON.parse(await readFile(join(module, "Verification/identity-service-discovery-evidence.json"), "utf8"));
    if (evidence.sourceCommit !== baseline || evidence.gitTree !== tree || !Array.isArray(evidence.files) || evidence.files.length !== 43)
      throw Error("Wrong manifest scope");
    const hash = createHash("sha256"), seen = new Set();
    for (const path of evidence.files) {
      if (typeof path !== "string" || path.startsWith("/") || path.includes("..") || path.includes("\\") || seen.has(path))
        throw Error("Invalid manifest path");
      seen.add(path);
      hash.update(path).update("\0").update(await readFile(join(service, path))).update("\0");
    }
    if (hash.digest("hex") !== digest || evidence.treeSHA256 !== digest) throw Error("Manifest mismatch");
    const dependencies = join(repo, "Server/WorkspaceService/node_modules");
    for (const [name, version] of [["pg", "8.23.1"], ["jose", "6.2.12"]])
      if (JSON.parse(await readFile(join(dependencies, name, "package.json"), "utf8")).version !== version) throw Error("Pinned dependency required");
    await symlink(dependencies, join(service, "node_modules"));
    const { default: pg } = await import(pathToFileURL(join(dependencies, "pg/lib/index.js")).href);
    const { WorkspaceStore } = await import(pathToFileURL(join(service, "src/workspace-store.ts")).href);
    const { IdentityStore } = await import(pathToFileURL(join(service, "src/identity-store.ts")).href);
    const { migrate } = await import(pathToFileURL(join(service, "src/migrate.ts")).href);
    const { schemaIdentifier } = await import(pathToFileURL(join(service, "src/validation.ts")).href);
    const { createGateway, listenGateway } = await import(pathToFileURL(join(service, "src/http-gateway.ts")).href);
    const { verificationURL } = await import(pathToFileURL(join(service, "test/verification.ts")).href);
    const { ownedIssuer } = await import(pathToFileURL(join(service, "test/helpers/identity-issuer.ts")).href);

    stage = "owned CA and signed leaf";
    const tls = join(root, "tls");
    await mkdir(tls, { mode: 0o700 });
    const openssl = (args: string[]) => execFileSync("openssl", args, { timeout: 15000, stdio: "ignore" });
    openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=Scriptum Owned Verification CA", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign", "-keyout", join(tls, "ca.key"), "-out", join(tls, "ca.pem")]);
    openssl(["req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=localhost", "-keyout", join(tls, "key.pem"), "-out", join(tls, "server.csr")]);
    const extensions = join(tls, "leaf.ext");
    await writeFile(extensions, "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n", { mode: 0o600 });
    openssl(["x509", "-req", "-in", join(tls, "server.csr"), "-CA", join(tls, "ca.pem"), "-CAkey", join(tls, "ca.key"), "-CAcreateserial", "-days", "1", "-extfile", extensions, "-out", join(tls, "cert.pem")]);
    openssl(["x509", "-in", join(tls, "ca.pem"), "-outform", "DER", "-out", join(tls, "ca.der")]);
    openssl(["verify", "-CAfile", join(tls, "ca.pem"), "-purpose", "sslserver", join(tls, "cert.pem")]);
    // The archived owned-issuer helper uses this explicit PEM as its local test
    // trust input as well as its server chain. Include the actual signing root.
    await writeFile(join(tls, "cert.pem"), Buffer.concat([await readFile(join(tls, "cert.pem")), await readFile(join(tls, "ca.pem"))]), { mode: 0o600 });
    await chmod(join(tls, "ca.key"), 0o600); await chmod(join(tls, "key.pem"), 0o600);
    process.env.SCRIPTUM_TEST_TLS_DIRECTORY = tls;

    stage = "owned database and HTTPS relay";
    const pool = new pg.Pool({ connectionString: verificationURL(config.url, "YES"), max: 8, connectionTimeoutMillis: 3000, statement_timeout: 5000, query_timeout: 6000 });
    const schema = "wsverify_production_bridge_" + randomUUID().replaceAll("-", ""), identifier = schemaIdentifier(schema);
    const lock = await pool.connect().catch(async error => { await pool.end(); throw error; });
    let owned = false, issuer, gateway, relay, controller;
    try {
      const version = await pool.query("SHOW server_version_num");
      if (Math.floor(Number(version.rows[0].server_version_num) / 10000) !== 18) throw Error("PG18 required");
      await lock.query("SELECT pg_advisory_lock(hashtextextended($1,0))", ["scriptum:production-bridge:" + schema]);
      await pool.query("CREATE SCHEMA " + identifier); owned = true; await migrate(pool, schema);
      issuer = await ownedIssuer(join(root, "vault"));
      gateway = createGateway(new WorkspaceStore(pool, schema), { identity: new IdentityStore(pool, schema, [issuer]) });
      const upstreamOrigin = await listenGateway(gateway);
      relay = httpsServer({ key: await readFile(join(tls, "key.pem")), cert: await readFile(join(tls, "cert.pem")) }, (request, response) => {
        // Actual TLS socket and exact logical origin, never synthetic URLProtocol
        // replies or HTTP responses relabelled as HTTPS inside the SDK.
        if (!request.url?.startsWith("/") || request.url.startsWith("//")) { response.writeHead(400); response.end(); return; }
        const headers = { ...request.headers }; delete headers.host;
        const upstream = httpRequest(upstreamOrigin + request.url, { method: request.method, headers }, reply => {
          response.writeHead(reply.statusCode ?? 502, reply.headers);
          let bytes = 0;
          reply.on("data", chunk => { bytes += chunk.length; if (bytes > 256 * 1024) { reply.destroy(); response.destroy(); } else response.write(chunk); });
          reply.on("end", () => response.end()); reply.on("error", () => response.destroy());
        });
        upstream.setTimeout(10000, () => upstream.destroy());
        upstream.on("error", () => { if (!response.headersSent) { response.writeHead(502); response.end(); } else response.destroy(); });
        let bytes = 0;
        request.on("data", chunk => { bytes += chunk.length; if (bytes > 24576) { request.destroy(); upstream.destroy(); } else upstream.write(chunk); });
        request.on("end", () => upstream.end()); request.on("aborted", () => upstream.destroy());
        response.on("close", () => upstream.destroy());
      });
      relay.on("tlsClientError", () => {});
      await listenGateway(relay);
      const relayAddress = relay.address();
      if (!relayAddress || typeof relayAddress === "string") throw Error("Missing owned TLS listener");
      const origin = "https://127.0.0.1:" + relayAddress.port;
      const controlSecret = randomBytes(32).toString("base64url"), subjects = { owner: "owned-bridge-owner-" + randomUUID(), viewer: "owned-bridge-viewer-" + randomUUID() };
      const libraryID = randomUUID(), title = "Owned remote library";
      controller = httpServer((request, response) => {
        void (async () => {
          if (request.method !== "POST" || request.headers.authorization !== "Bearer " + controlSecret) { response.writeHead(401); response.end(); return; }
          const chunks = []; let bytes = 0;
          for await (const chunk of request) { bytes += chunk.length; if (bytes > 1024) throw Error("Bound"); chunks.push(chunk); }
          const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          let result;
          if (request.url === "/authorize") {
            if (Object.keys(body).sort().join(",") !== "account,nonce" || !["owner", "viewer"].includes(body.account) || typeof body.nonce !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(body.nonce)) { response.writeHead(400); response.end(); return; }
            const proof = await issuer.authorize(body.nonce, subjects[body.account]);
            result = { identityToken: proof.identityToken, authorizationCode: proof.authorizationCode };
          } else if (request.url === "/bootstrap") {
            if (Object.keys(body).join(",") !== "accountID" || typeof body.accountID !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.accountID)) throw Error("Invalid bootstrap");
            const admitted = await pool.query(`SELECT a.id FROM ${identifier}.accounts a WHERE a.id=$1 AND a.identity_subject=$2 AND a.disabled_at IS NULL AND EXISTS(SELECT 1 FROM ${identifier}.server_sessions s WHERE s.account_id=a.id AND s.auth_epoch=a.auth_epoch AND s.identity_profile_id=$3 AND s.revoked_at IS NULL AND s.expires_at>clock_timestamp())`, [body.accountID, subjects.owner, issuer.profile.profileID]);
            if (admitted.rowCount !== 1) throw Error("No live signed fixture owner");
            // Fixture seeding only; this does not claim native remote creation.
            await pool.query(`INSERT INTO ${identifier}.libraries(id,owner_account_id,title) VALUES($1,$2,$3) ON CONFLICT(id) DO NOTHING`, [libraryID, body.accountID, title]);
            result = { libraryID, title };
          } else { response.writeHead(404); response.end(); return; }
          response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
          response.end(JSON.stringify(result));
        })().catch(() => { if (!response.writableEnded) { response.writeHead(400); response.end(); } });
      });
      controller.setTimeout(5000);
      const controlOrigin = await listenGateway(controller);
      const file = join(root, "private-fixture.json"), pending = file + ".pending";
      await writeFile(pending, JSON.stringify({ origin, certificatePath: join(tls, "ca.der"), profileID: issuer.profile.profileID, consentVersion: issuer.profile.consentVersion, controlOrigin, controlSecret }), { mode: 0o600 });
      await rename(pending, file);

      stage = "compile production bridge spec";
      const scratch = join(root, "SwiftBuild");
      execFileSync("/usr/bin/swift", ["build", "--build-tests", "--build-system", "native", "--disable-sandbox", "--package-path", repo, "--scratch-path", scratch], { timeout: 120000, stdio: "inherit" });
      stage = "execute production bridge spec";
      const output: Buffer[] = []; let outputBytes = 0;
      const exit = await new Promise(resolve => {
        const child = spawn("/usr/bin/swift", ["test", "--skip-build", "--build-system", "native", "--disable-sandbox", "--package-path", repo, "--scratch-path", scratch, "--filter", filter], { env: { ...process.env, SCRIPTUM_PICKER_BRIDGE_FIXTURE: file }, stdio: ["ignore", "pipe", "pipe"] });
        const timer = setTimeout(() => child.kill("SIGTERM"), 30000);
        const collect = (chunk: Buffer) => { outputBytes += chunk.length; if (outputBytes > 4 * 1024 * 1024) { child.kill("SIGTERM"); return; } output.push(chunk); process.stdout.write(chunk); };
        child.stdout.on("data", collect); child.stderr.on("data", collect);
        child.on("error", () => { clearTimeout(timer); resolve(1); });
        child.on("exit", code => { clearTimeout(timer); resolve(code); });
      });
      if (exit !== 0 || !/Test run with 1 test\b/.test(Buffer.concat(output).toString("utf8"))) throw Error("Bridge spec did not execute exactly once");
      const result = await pool.query(`SELECT (SELECT count(*) FROM ${identifier}.libraries)::int AS libraries,(SELECT count(*) FROM ${identifier}.server_sessions WHERE revoked_at IS NULL AND expires_at>clock_timestamp())::int AS live`);
      if (result.rows[0].libraries !== 1 || result.rows[0].live !== 0 || issuer.state.tokenRequests < 1 || issuer.state.jwksRequests < 1) throw Error("Actual signed bridge durable proof missing");
      console.log("Owned production adapter HTTPS/signed issuer/PG bridge: 1 executed spec PASS; fixture library retained and live sessions fenced. Native creation/deployment/Apple not asserted.");
    } finally {
      await Promise.allSettled([controller, relay, gateway].filter(Boolean).map(async server => {
        server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
      }));
      try { if (issuer) await issuer.close(); }
      finally {
        try { if (owned) await pool.query("DROP SCHEMA " + identifier + " CASCADE"); }
        finally {
          try { await lock.query("SELECT pg_advisory_unlock(hashtextextended($1,0))", ["scriptum:production-bridge:" + schema]); }
          finally { lock.release(); await pool.end(); }
        }
      }
    }
  } finally {
    if (previousTLSDirectory === undefined) delete process.env.SCRIPTUM_TEST_TLS_DIRECTORY;
    else process.env.SCRIPTUM_TEST_TLS_DIRECTORY = previousTLSDirectory;
    await rm(root, { recursive: true, force: true });
  }
}
main().catch(() => { console.error("Owned production bridge failed at " + stage + " (details redacted)."); process.exitCode = 1; });
