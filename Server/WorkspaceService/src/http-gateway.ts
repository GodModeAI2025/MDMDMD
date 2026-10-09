import { createServer } from "node:http";
import type { IncomingMessage, Server, ServerResponse } from "node:http";
import type {
  WorkspaceStore,
  MembershipAddress,
  PageAddress,
} from "./workspace-store.ts";
import { parseUUID } from "./validation.ts";
import type { RoleRank } from "./validation.ts";
import { identityHTTP } from "./identity-http.ts";
import type { IdentityStore } from "./identity-store.ts";
import {
  HTTPError,
  parseJSON,
  requireFields,
  decodeEnvelope,
  encodeEnvelope,
  parseIfMatch,
  publicError,
} from "./http-wire.ts";

export interface GatewayOptions {
  identity?: IdentityStore;
  maximumBodyBytes?: number;
  maximumConcurrentRequests?: number;
}
function header(request: IncomingMessage, name: string): string | undefined {
  const values: string[] = [];
  for (let index = 0; index < request.rawHeaders.length; index += 2) {
    if (request.rawHeaders[index]?.toLowerCase() === name)
      values.push(request.rawHeaders[index + 1] ?? "");
  }
  if (values.length > 1) throw new HTTPError(400, "invalid_request");
  return values[0];
}
function bearer(request: IncomingMessage): string {
  const value = header(request, "authorization");
  const match = value && /^Bearer ([A-Za-z0-9_-]{43,128})$/.exec(value);
  if (!match?.[1]) throw new HTTPError(401, "unauthenticated");
  return match[1];
}
function noBody(request: IncomingMessage): void {
  const length = header(request, "content-length");
  if (
    header(request, "transfer-encoding") ||
    (length !== undefined && length !== "0")
  )
    throw new HTTPError(400, "invalid_request");
}
function body(
  request: IncomingMessage,
  limit: number,
  bounds: { maximumDepth?: number; maximumNodes?: number } = {},
): Promise<Record<string, unknown>> {
  const media = header(request, "content-type")
    ?.toLowerCase()
    .replaceAll(/\s+/g, "");
  if (
    media !== "application/json" &&
    media !== "application/json;charset=utf-8"
  )
    throw new HTTPError(415, "unsupported_media");
  if (header(request, "content-encoding"))
    throw new HTTPError(415, "unsupported_media");
  const declared = header(request, "content-length");
  if (declared !== undefined) {
    if (!/^[0-9]+$/.test(declared) || !Number.isSafeInteger(Number(declared)))
      throw new HTTPError(400, "invalid_request");
    if (Number(declared) > limit) throw new HTTPError(413, "body_too_large");
  }
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0,
      settled = false;
    const timer = setTimeout(
      () => finish(new HTTPError(408, "request_timeout")),
      5000,
    );
    function clean(): void {
      clearTimeout(timer);
      request.off("data", data);
      request.off("end", end);
      request.off("aborted", aborted);
      request.off("error", failed);
    }
    function finish(error?: unknown, value?: Record<string, unknown>): void {
      if (settled) return;
      settled = true;
      clean();
      if (error) {
        request.pause();
        reject(error);
      } else resolve(value!);
    }
    function data(chunk: Buffer): void {
      if (chunk.length > limit - size) {
        finish(new HTTPError(413, "body_too_large"));
        return;
      }
      size += chunk.length;
      chunks.push(chunk);
    }
    function end(): void {
      try {
        const text = new TextDecoder("utf-8", { fatal: true }).decode(
          Buffer.concat(chunks, size),
        );
        finish(undefined, parseJSON(text, bounds));
      } catch (error) {
        finish(
          error instanceof HTTPError
            ? error
            : new HTTPError(400, "invalid_request"),
        );
      }
    }
    function aborted(): void {
      finish(new HTTPError(400, "invalid_request"));
    }
    function failed(): void {
      finish(new HTTPError(400, "invalid_request"));
    }
    request.on("data", data);
    request.once("end", end);
    request.once("aborted", aborted);
    request.once("error", failed);
  });
}
function send(response: ServerResponse, status: number, value?: unknown): void {
  if (response.destroyed || response.writableEnded) return;
  response.statusCode = status;
  response.setHeader("cache-control", "no-store");
  response.setHeader("x-content-type-options", "nosniff");
  if (value === undefined) {
    response.end();
    return;
  }
  const text = JSON.stringify(value);
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("content-length", Buffer.byteLength(text));
  response.end(text);
}
function allowed(
  method: string | undefined,
  methods: string[],
  response: ServerResponse,
): void {
  if (!method || !methods.includes(method)) {
    response.setHeader("allow", methods.join(", "));
    throw new HTTPError(405, "method_not_allowed");
  }
}
export function createGateway(
  store: WorkspaceStore,
  options: GatewayOptions = {},
): Server {
  const limit = options.maximumBodyBytes ?? 3 * 1024 * 1024;
  const concurrency = options.maximumConcurrentRequests ?? 8;
  if (
    !Number.isInteger(limit) ||
    limit < 64 ||
    limit > 3 * 1024 * 1024 ||
    !Number.isInteger(concurrency) ||
    concurrency < 1 ||
    concurrency > 32
  )
    throw new Error("Invalid gateway bounds");
  let active = 0;
  const server = createServer(
    {
      maxHeaderSize: 8192,
      headersTimeout: 5000,
      requestTimeout: 10000,
      keepAliveTimeout: 1000,
      connectionsCheckingInterval: 1000,
    },
    (request, response) => {
      if (active >= concurrency) {
        response.setHeader("connection", "close");
        send(response, 503, { error: "unavailable" });
        return;
      }
      active++;
      let released = false,
        responseSettled = false,
        handlerSettled = false;
      function release(): void {
        if (!released && responseSettled && handlerSettled) {
          released = true;
          active--;
        }
      }
      function responseFinished(): void {
        responseSettled = true;
        release();
      }
      response.once("finish", responseFinished);
      response.once("close", responseFinished);
      void route(request, response)
        .catch((error) => {
          if (response.destroyed || response.writableEnded) return;
          const mapped = publicError(error);
          response.setHeader("connection", "close");
          response.once("finish", () => request.destroy());
          send(response, mapped.status, { error: mapped.code });
        })
        .finally(() => {
          handlerSettled = true;
          release();
        });
    },
  );
  // Do not truncate duplicate headers before our strict count/duplicate checks.
  server.maxHeadersCount = 0;
  server.maxConnections = 64;
  server.maxRequestsPerSocket = 100;
  server.setTimeout(10000);
  server.on("clientError", (error, socket) => {
    const status =
      "code" in error && error.code === "HPE_HEADER_OVERFLOW"
        ? "431 Request Header Fields Too Large"
        : "400 Bad Request";
    if (socket.writable)
      socket.end(
        `HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`,
      );
    else socket.destroy();
  });
  server.on("upgrade", (_request, socket) =>
    socket.end(
      "HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n",
    ),
  );
  async function route(
    request: IncomingMessage,
    response: ServerResponse,
  ): Promise<void> {
    const path = request.url;
    if (
      !path ||
      !path.startsWith("/") ||
      path.includes("?") ||
      path.includes("#") ||
      path.includes("%") ||
      request.rawHeaders.length > 64
    )
      throw new HTTPError(400, "invalid_request");
    if (path === "/health" || path === "/ready") {
      allowed(request.method, ["GET"], response);
      noBody(request);
      if (path === "/health") send(response, 200, { status: "ok" });
      else {
        const ready = await store.isReady();
        send(response, ready ? 200 : 503, { ready });
      }
      return;
    }
    if (
      await identityHTTP(options.identity, request, response, path, {
        body,
        noBody,
        bearer,
        allowed,
        send,
      })
    )
      return;
    const token = bearer(request);
    await store.validateSession(token);
    if (request.aborted || response.destroyed)
      throw new HTTPError(400, "invalid_request");
    if (path === "/session/logout") {
      allowed(request.method, ["POST"], response);
      noBody(request);
      await store.revokeSession(token);
      send(response, 204);
      return;
    }
    const pieces = path.split("/").slice(1);
    if (path === "/libraries") {
      allowed(request.method, ["POST"], response);
      const value = await body(request, limit);
      requireFields(value, ["title"]);
      if (typeof value.title !== "string")
        throw new HTTPError(400, "invalid_request");
      if (request.aborted || response.destroyed)
        throw new HTTPError(400, "invalid_request");
      send(response, 201, {
        libraryID: await store.createLibrary(token, value.title),
      });
      return;
    }
    if (pieces[0] !== "libraries" || !pieces[1])
      throw new HTTPError(404, "not_found");
    const libraryID = parseUUID(pieces[1]);
    if (pieces.length === 3 && pieces[2] === "spaces") {
      allowed(request.method, ["POST"], response);
      const value = await body(request, limit);
      requireFields(value, ["title"]);
      if (typeof value.title !== "string")
        throw new HTTPError(400, "invalid_request");
      if (request.aborted || response.destroyed)
        throw new HTTPError(400, "invalid_request");
      send(response, 201, {
        spaceID: await store.createSpace(token, libraryID, value.title),
      });
      return;
    }
    const pageRoute =
      pieces.length === 6 && pieces[2] === "spaces" && pieces[4] === "pages";
    if (pageRoute) {
      allowed(request.method, ["GET", "POST", "PUT"], response);
      const target: PageAddress = {
        libraryID,
        spaceID: parseUUID(pieces[3]!),
        pageID: parseUUID(pieces[5]!),
      };
      if (request.method === "GET") {
        noBody(request);
        const page = await store.readPage(token, target);
        response.setHeader("etag", `"${page.revision}"`);
        send(response, 200, {
          revision: page.revision,
          envelope: encodeEnvelope(page.envelope),
        });
        return;
      }
      const expected =
        request.method === "PUT"
          ? parseIfMatch(header(request, "if-match"))
          : undefined;
      const envelope = decodeEnvelope(await body(request, limit));
      if (request.aborted || response.destroyed)
        throw new HTTPError(400, "invalid_request");
      const revision =
        expected === undefined
          ? await store.createPage(token, target, envelope)
          : await store.writePage(token, target, expected, envelope);
      response.setHeader("etag", `"${revision}"`);
      send(response, expected === undefined ? 201 : 200, { revision });
      return;
    }
    let target: MembershipAddress | undefined, accountID: string | undefined;
    if (pieces.length === 4 && pieces[2] === "memberships") {
      target = { libraryID, kind: "library" };
      accountID = parseUUID(pieces[3]!);
    } else if (
      pieces.length === 6 &&
      pieces[2] === "spaces" &&
      pieces[4] === "memberships"
    ) {
      target = { libraryID, kind: "space", spaceID: parseUUID(pieces[3]!) };
      accountID = parseUUID(pieces[5]!);
    } else if (
      pieces.length === 8 &&
      pieces[2] === "spaces" &&
      pieces[4] === "pages" &&
      pieces[6] === "memberships"
    ) {
      target = {
        libraryID,
        kind: "page",
        spaceID: parseUUID(pieces[3]!),
        pageID: parseUUID(pieces[5]!),
      };
      accountID = parseUUID(pieces[7]!);
    }
    if (target && accountID) {
      allowed(request.method, ["PUT", "DELETE"], response);
      if (request.method === "DELETE") {
        noBody(request);
        await store.revokeMembership(token, target, accountID);
        send(response, 204);
        return;
      }
      const value = await body(request, limit);
      requireFields(value, ["role"]);
      const roles: Record<string, RoleRank> = {
        none: 0,
        viewer: 1,
        editor: 2,
        owner: 3,
      };
      if (typeof value.role !== "string" || !Object.hasOwn(roles, value.role))
        throw new HTTPError(400, "invalid_request");
      await store.setMembership(token, target, accountID, roles[value.role]!);
      send(response, 204);
      return;
    }
    throw new HTTPError(404, "not_found");
  }
  return server;
}
export async function listenGateway(
  server: Server,
  options: { host?: string; port?: number; allowExternalBind?: boolean } = {},
): Promise<string> {
  const host = options.host ?? "127.0.0.1",
    port = options.port ?? 0;
  if (
    !["127.0.0.1", "::1", "localhost"].includes(host) &&
    options.allowExternalBind !== true
  )
    throw new Error(
      "Explicit deployment authorization/configuration required for non-loopback binding",
    );
  if (!Number.isInteger(port) || port < 0 || port > 65535)
    throw new Error("Invalid listener port");
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  const address = server.address();
  if (!address || typeof address === "string")
    throw new Error("Listener missing");
  return `http://${host.includes(":") ? "[" + host + "]" : host}:${address.port}`;
}
