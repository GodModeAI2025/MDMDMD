import type { IncomingMessage, ServerResponse } from "node:http";
import { IdentityError } from "./identity-config.ts";
import type { IdentityStore, EnrollmentDTO } from "./identity-store.ts";
import { HTTPError, requireFields } from "./http-wire.ts";

export interface IdentityHTTPHelpers {
  body(
    request: IncomingMessage,
    limit: number,
    bounds: { maximumDepth: number; maximumNodes: number },
  ): Promise<Record<string, unknown>>;
  noBody(request: IncomingMessage): void;
  bearer(request: IncomingMessage): string;
  allowed(
    method: string | undefined,
    methods: string[],
    response: ServerResponse,
  ): void;
  send(response: ServerResponse, status: number, value?: unknown): void;
}
export async function identityHTTP(
  store: IdentityStore | undefined,
  request: IncomingMessage,
  response: ServerResponse,
  path: string,
  helpers: IdentityHTTPHelpers,
): Promise<boolean> {
  if (
    ![
      "/identity/challenges",
      "/identity/enroll",
      "/identity/apple/events",
      "/session",
      "/session/logout-all",
      "/account",
    ].includes(path)
  )
    return false;
  if (!store) throw new HTTPError(404, "not_found");
  const origin = request.socket.remoteAddress;
  if (!origin) throw new IdentityError("invalid");
  const parse = () =>
    helpers.body(request, 24576, { maximumDepth: 8, maximumNodes: 32 });
  if (path === "/identity/challenges") {
    helpers.allowed(request.method, ["POST"], response);
    const value = await parse();
    requireFields(value, ["profileID", "consentVersion"]);
    if (
      typeof value.profileID !== "string" ||
      typeof value.consentVersion !== "string"
    )
      throw new IdentityError("invalid");
    helpers.send(
      response,
      201,
      await store.challenge(value.profileID, value.consentVersion, origin),
    );
    return true;
  }
  if (path === "/identity/enroll") {
    helpers.allowed(request.method, ["POST"], response);
    const value = await parse();
    requireFields(value, [
      "challengeID",
      "challengeSecret",
      "state",
      "identityToken",
      "authorizationCode",
    ]);
    for (const field of Object.keys(value))
      if (typeof value[field] !== "string") throw new IdentityError("invalid");
    if (
      Buffer.byteLength(String(value.identityToken)) > 16384 ||
      Buffer.byteLength(String(value.authorizationCode)) > 4096
    )
      throw new HTTPError(413, "body_too_large");
    helpers.send(
      response,
      201,
      await store.enroll(value as unknown as EnrollmentDTO, origin),
    );
    return true;
  }
  if (path === "/identity/apple/events") {
    helpers.allowed(request.method, ["POST"], response);
    const value = await parse();
    requireFields(value, ["payload"]);
    if (
      typeof value.payload !== "string" ||
      Buffer.byteLength(value.payload) > 16384
    )
      throw new IdentityError("invalid");
    await store.notification(value.payload);
    helpers.send(response, 204);
    return true;
  }
  const token = helpers.bearer(request);
  if (path === "/session") {
    helpers.allowed(request.method, ["GET"], response);
    helpers.noBody(request);
    helpers.send(response, 200, await store.session(token));
    return true;
  }
  if (path === "/session/logout-all") {
    helpers.allowed(request.method, ["POST"], response);
    helpers.noBody(request);
    await store.logoutAll(token);
    helpers.send(response, 204);
    return true;
  }
  helpers.allowed(request.method, ["DELETE"], response);
  const value = await parse();
  requireFields(value, ["reauthenticationReceipt", "retentionConfirmation"]);
  if (
    typeof value.reauthenticationReceipt !== "string" ||
    typeof value.retentionConfirmation !== "string"
  )
    throw new IdentityError("invalid");
  await store.deleteAccount(
    token,
    value.reauthenticationReceipt,
    value.retentionConfirmation,
  );
  helpers.send(response, 204);
  return true;
}
