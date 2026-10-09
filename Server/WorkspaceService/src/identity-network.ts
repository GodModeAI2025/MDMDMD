import { request } from "node:https";
import { IdentityError } from "./identity-config.ts";

export class IdentityNetwork {
  readonly #allowed: ReadonlySet<string>;
  readonly #ca?: Buffer;
  constructor(allowedURLs: readonly string[], testCA?: Buffer) {
    this.#allowed = new Set(allowedURLs);
    this.#ca = testCA && Buffer.from(testCA);
  }
  async fetch(
    url: string,
    options: {
      method?: "GET" | "POST";
      body?: string;
      signal?: AbortSignal;
      timeout: number;
      maximumBytes: number;
    },
  ): Promise<Response> {
    if (!this.#allowed.has(url)) throw new IdentityError("unavailable");
    if (options.signal?.aborted) throw new IdentityError("unavailable");
    return new Promise((resolve, reject) => {
      let settled = false;
      const finish = (error?: unknown, response?: Response): void => {
        if (settled) return;
        settled = true;
        clearTimeout(deadline);
        if (error) reject(new IdentityError("unavailable"));
        else resolve(response!);
      };
      const outbound = request(
        url,
        {
          method: options.method ?? "GET",
          signal: options.signal,
          ...(this.#ca ? { ca: this.#ca } : {}),
          headers: {
            accept: "application/json",
            ...(options.body === undefined
              ? {}
              : {
                  "content-type": "application/x-www-form-urlencoded",
                  "content-length": Buffer.byteLength(options.body),
                }),
          },
        },
        (incoming) => {
          if (incoming.statusCode !== 200) {
            incoming.destroy();
            outbound.destroy();
            finish(new IdentityError("unavailable"));
            return;
          }
          const declared = incoming.headers["content-length"];
          if (
            declared &&
            (!/^[0-9]+$/.test(declared) ||
              Number(declared) > options.maximumBytes)
          ) {
            incoming.destroy();
            outbound.destroy();
            finish(new IdentityError("unavailable"));
            return;
          }
          const chunks: Buffer[] = [];
          let bytes = 0;
          incoming.on("data", (chunk: Buffer) => {
            if (chunk.length > options.maximumBytes - bytes) {
              incoming.destroy();
              outbound.destroy();
              finish(new IdentityError("unavailable"));
              return;
            }
            bytes += chunk.length;
            chunks.push(chunk);
          });
          incoming.once("end", () =>
            finish(
              undefined,
              new Response(Buffer.concat(chunks, bytes), {
                status: 200,
                headers: { "content-type": "application/json" },
              }),
            ),
          );
          incoming.once("error", () =>
            finish(new IdentityError("unavailable")),
          );
          incoming.once("aborted", () =>
            finish(new IdentityError("unavailable")),
          );
        },
      );
      const deadline = setTimeout(() => {
        outbound.destroy();
        finish(new IdentityError("unavailable"));
      }, options.timeout);
      outbound.once("error", () => finish(new IdentityError("unavailable")));
      outbound.end(options.body);
    });
  }
}
