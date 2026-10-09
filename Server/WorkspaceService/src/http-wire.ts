import { parseUUID, validateEnvelope, WorkspaceError } from './validation.ts';
import type { EncryptedEnvelope } from './validation.ts';

export class HTTPError extends Error {
  readonly status: number;
  readonly publicCode: string;
  constructor(status: number, publicCode: string) {
    super(publicCode);
    this.status = status;
    this.publicCode = publicCode;
  }
}

/** Bounded JSON grammar preserving duplicate-key evidence before constructing objects. */
export function parseJSON(text: string): Record<string, unknown> {
  let position = 0;
  let nodes = 0;
  function invalid(): never { throw new HTTPError(400, 'invalid_request'); }
  function whitespace(): void { while (/[\x20\t\n\r]/.test(text[position] ?? '') && position < text.length) position++; }
  function string(): string {
    const start = position++;
    let escaped = false;
    while (position < text.length) {
      const char = text[position++];
      if (char === '"' && !escaped) {
        let value: string;
        try { value = JSON.parse(text.slice(start, position)) as string; } catch { return invalid(); }
        for (let index = 0; index < value.length; index++) {
          const code = value.charCodeAt(index);
          if (code >= 0xd800 && code <= 0xdbff) {
            const next = value.charCodeAt(++index);
            if (!(next >= 0xdc00 && next <= 0xdfff)) return invalid();
          } else if (code >= 0xdc00 && code <= 0xdfff) return invalid();
        }
        return value;
      }
      if (char === '\\' && !escaped) escaped = true;
      else escaped = false;
    }
    return invalid();
  }
  function value(depth: number): unknown {
    if (depth > 16 || ++nodes > 512) return invalid();
    whitespace();
    const char = text[position];
    if (char === '"') return string();
    if (char === '{') {
      position++; whitespace();
      const result = Object.create(null) as Record<string, unknown>;
      const keys = new Set<string>();
      if (text[position] === '}') { position++; return result; }
      while (position < text.length) {
        whitespace(); if (text[position] !== '"') return invalid();
        const key = string(); if (keys.has(key)) return invalid(); keys.add(key);
        whitespace(); if (text[position++] !== ':') return invalid();
        result[key] = value(depth + 1); whitespace();
        const delimiter = text[position++];
        if (delimiter === '}') return result;
        if (delimiter !== ',') return invalid();
      }
      return invalid();
    }
    if (char === '[') {
      position++; whitespace(); const result: unknown[] = [];
      if (text[position] === ']') { position++; return result; }
      while (position < text.length) {
        result.push(value(depth + 1)); whitespace();
        const delimiter = text[position++];
        if (delimiter === ']') return result;
        if (delimiter !== ',') return invalid();
      }
      return invalid();
    }
    for (const [literal, result] of [['true', true], ['false', false], ['null', null]] as const) {
      if (text.startsWith(literal, position)) { position += literal.length; return result; }
    }
    const number = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(text.slice(position));
    if (!number) return invalid();
    position += number[0].length; const result = Number(number[0]);
    if (!Number.isFinite(result)) return invalid(); return result;
  }
  const parsed = value(0); whitespace();
  if (position !== text.length || !parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return invalid();
  return parsed as Record<string, unknown>;
}

export function requireFields(value: Record<string, unknown>, fields: readonly string[]): void {
  const actual = Object.keys(value);
  if (actual.length !== fields.length || actual.some(key => !fields.includes(key))) throw new HTTPError(400, 'invalid_request');
}
function base64(value: unknown, minimum: number, maximum: number): Buffer {
  if (typeof value !== 'string' || value.length % 4 !== 0 || value.length > Math.ceil(maximum / 3) * 4) throw new HTTPError(400, 'invalid_request');
  const padding = value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0;
  for (let index = 0; index < value.length - padding; index++) {
    const code = value.charCodeAt(index);
    if (!((code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code === 43 || code === 47)) throw new HTTPError(400, 'invalid_request');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length < minimum || bytes.length > maximum || bytes.toString('base64') !== value) throw new HTTPError(400, 'invalid_request');
  return bytes;
}
export function decodeEnvelope(value: Record<string, unknown>): EncryptedEnvelope {
  requireFields(value, ['ciphertext', 'nonce', 'digest', 'keyReference', 'version']);
  if (typeof value.keyReference !== 'string' || value.version !== 1) throw new HTTPError(400, 'invalid_request');
  const envelope: EncryptedEnvelope = {
    ciphertext: base64(value.ciphertext, 17, 2 * 1024 * 1024 + 16),
    nonce: base64(value.nonce, 12, 12), digest: base64(value.digest, 32, 32),
    keyReference: value.keyReference, version: 1,
  };
  validateEnvelope(envelope); return envelope;
}
export function encodeEnvelope(value: EncryptedEnvelope): Record<string, unknown> {
  return { ciphertext: value.ciphertext.toString('base64'), nonce: value.nonce.toString('base64'), digest: value.digest.toString('base64'), keyReference: value.keyReference, version: value.version };
}
export function parseIfMatch(value: string | undefined): string {
  if (!value || value.length !== 38 || value[0] !== '"' || value.at(-1) !== '"') throw new HTTPError(400, 'invalid_request');
  try { return parseUUID(value.slice(1, -1)); } catch { throw new HTTPError(400, 'invalid_request'); }
}
export function publicError(error: unknown): { status: number; code: string } {
  if (error instanceof HTTPError) return { status: error.status, code: error.publicCode };
  if (error instanceof WorkspaceError) {
    switch (error.code) {
      case 'unauthenticated': return { status: 401, code: 'unauthenticated' };
      case 'forbidden': case 'missing': return { status: 404, code: 'not_found' };
      case 'invalid': return { status: 400, code: 'invalid_request' };
      case 'conflict': return { status: 409, code: 'conflict' };
    }
  }
  const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
  if (code === '23505') return { status: 409, code: 'conflict' };
  if (['23503', '23514', '22P02', '55000'].includes(code)) return { status: 400, code: 'invalid_request' };
  return { status: 503, code: 'unavailable' };
}
