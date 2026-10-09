import type { IdentityStore } from "./identity-store.ts";

/** Persistent SQL queue is truth; this bounded non-overlapping pump is only wakeup. */
export class IdentityRevocationWorker {
  readonly #identity: IdentityStore;
  readonly #interval: number;
  readonly #maximum: number;
  readonly #controller = new AbortController();
  #timer?: ReturnType<typeof setTimeout>;
  #active?: Promise<void>;
  #stopped = false;
  #started = false;
  #cycles = 0;
  #lastOutcome: "idle" | "drained" | "failed" = "idle";
  constructor(
    identity: IdentityStore,
    options: { intervalMS?: number; maximumJobs?: number } = {},
  ) {
    this.#identity = identity;
    this.#interval = options.intervalMS ?? 30000;
    this.#maximum = options.maximumJobs ?? 10;
    if (
      !Number.isInteger(this.#interval) ||
      this.#interval < 10 ||
      this.#interval > 300000 ||
      !Number.isInteger(this.#maximum) ||
      this.#maximum < 1 ||
      this.#maximum > 32
    )
      throw new Error("Invalid revocation worker bounds");
  }
  get status() {
    return {
      running: !!this.#active,
      cycles: this.#cycles,
      lastOutcome: this.#lastOutcome,
    };
  }
  start(): void {
    if (this.#started || this.#stopped) return;
    this.#started = true;
    this.#schedule(0);
  }
  #schedule(delay: number): void {
    if (this.#stopped) return;
    this.#timer = setTimeout(() => {
      this.#timer = undefined;
      this.#active = this.#drain();
    }, delay);
  }
  async #drain(): Promise<void> {
    try {
      await this.#identity.compensate(this.#maximum, this.#controller.signal);
      this.#lastOutcome = "drained";
    } catch {
      this.#lastOutcome = "failed";
    } finally {
      this.#cycles++;
      this.#active = undefined;
      this.#schedule(this.#interval);
    }
  }
  async stop(): Promise<void> {
    this.#stopped = true;
    if (this.#timer) clearTimeout(this.#timer);
    this.#timer = undefined;
    this.#controller.abort();
    await this.#active;
  }
}
