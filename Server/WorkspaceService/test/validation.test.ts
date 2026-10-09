import test from 'node:test';
import assert from 'node:assert/strict';
import { parseUUID, validateEnvelope, effectiveRole } from '../src/validation.ts';
test('strict namespace UUID and encrypted payload bounds', () => {
  assert.equal(parseUUID('00000000-0000-4000-8000-000000000001'), '00000000-0000-4000-8000-000000000001');
  assert.throws(() => parseUUID('../00000000-0000-4000-8000-000000000001'));
  assert.throws(() => validateEnvelope({ciphertext:Buffer.alloc(17),nonce:Buffer.alloc(11),digest:Buffer.alloc(32),keyReference:'vault:key',version:1}));
});
test('explicit child overrides never elevate or revive revoked parent access', () => {
  assert.equal(effectiveRole(1,3,3),1);
  assert.equal(effectiveRole(0,3,3),0);
  assert.equal(effectiveRole(2,1,3),1);
  assert.equal(effectiveRole(3,undefined,2),2);
});
