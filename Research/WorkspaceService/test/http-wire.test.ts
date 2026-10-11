import test from "node:test";
import assert from "node:assert/strict";
import {
  parseJSON,
  decodeEnvelope,
  parseIfMatch,
  requireFields,
} from "../src/http-wire.ts";
test("strict JSON detects duplicate escaped keys, trailing bytes and depth", () => {
  assert.throws(() => parseJSON('{"title":"a","\\u0074itle":"b"}'));
  assert.throws(() => parseJSON('{"title":"a"} false'));
  assert.throws(() => parseJSON("[".repeat(20) + "0" + "]".repeat(20)));
  assert.throws(() => parseJSON('{"title":"\\ud800"}'));
  assert.throws(() =>
    requireFields(parseJSON('{"title":"a","role":"owner"}'), ["title"]),
  );
  assert.equal(parseJSON('{"title":"😀"}').title, "😀");
});
test("canonical base64 and strong quoted revision are exact", () => {
  const fields = {
    ciphertext: Buffer.alloc(17).toString("base64"),
    nonce: Buffer.alloc(12).toString("base64"),
    digest: Buffer.alloc(32).toString("base64"),
    keyReference: "k",
    version: 1,
  };
  assert.equal(decodeEnvelope(fields).ciphertext.length, 17);
  assert.throws(() => decodeEnvelope({ ...fields, nonce: "AB==============" }));
  assert.throws(() =>
    decodeEnvelope({ ...fields, ciphertext: fields.ciphertext + "\n" }),
  );
  assert.throws(() => parseIfMatch('W/"00000000-0000-4000-8000-000000000001"'));
  assert.equal(
    parseIfMatch('"00000000-0000-4000-8000-000000000001"'),
    "00000000-0000-4000-8000-000000000001",
  );
});

test("verification gates reject remote endpoints and absent opt-in before connection", async () => {
  const { verificationURL } = await import("./verification.ts");
  assert.throws(() =>
    verificationURL("postgres://user@remote.invalid/db", "YES"),
  );
  assert.throws(() =>
    verificationURL("postgres://user@127.0.0.1/db", undefined),
  );
  assert.equal(
    verificationURL("postgres://user@127.0.0.1/db", "YES"),
    "postgres://user@127.0.0.1/db",
  );
});
