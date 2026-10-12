import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import vm from 'node:vm';
import test from 'node:test';

// Source-backed loop regression, not a real filesystem race/public Run test.
// The independently fixed growth pattern must be refused before retention/hash
// of the offending chunk, without relying on the final filesystem stat.
const source = readFileSync(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const start = source.indexOf('  const readSemanticBytes = async cid => {');
const end = source.indexOf('\n  // Private evidence uses', start);
assert.ok(start >= 0 && end > start);
const fragment = source.slice(start, end);

function fixture(chunks, beforeBytes, afterBytes, maximum) {
  const state = {yields: 0, hashBytes: 0, concatenations: 0,
    closed: 0, stats: 0, verified: 0};
  const stat = size => ({isFile: () => true, size, dev: 1, ino: 2, mtimeMs: 3});
  const context = vm.createContext({
    Buffer: {concat(chunks, length) {
      state.concatenations++;
      return Buffer.concat(chunks, length);
    }},
    createHash(name) {
      const hash = createHash(name);
      return {update(chunk) {state.hashBytes += chunk.byteLength; hash.update(chunk);},
        digest: encoding => hash.digest(encoding)};
    },
    configuration: {maxObjectBytes: maximum},
    constants: {O_RDONLY: 0, O_NOFOLLOW: 0},
    contractPath: cid => cid, objectPath: cid => cid,
    fail: code => {throw Object.assign(new Error(code), {code});},
    open: async () => ({
      stat: async () => stat(state.stats++ === 0 ? beforeBytes : afterBytes),
      createReadStream: () => ({async *[Symbol.asyncIterator]() {
        for (const chunk of chunks) {state.yields++; yield chunk;}
      }}),
      close: async () => {state.closed++;},
    }),
    lstat: async () => stat(afterBytes),
    verifyObject: async () => {state.verified++;},
  });
  vm.runInContext(fragment + '\nglobalThis.read = readSemanticBytes;', context,
    {timeout: 1000});
  return {read: context.read, state};
}

test('semantic read accepts the independently bounded stable body', async () => {
  const {read, state} = fixture([Buffer.from('ab'), Buffer.from('cd')], 4, 4, 4);
  assert.equal((await read('fixture')).toString(), 'abcd');
  assert.deepEqual(state, {yields: 2, hashBytes: 4, concatenations: 1,
    closed: 1, stats: 2, verified: 1});
});

test('semantic read refuses growth before retaining or hashing an oversized chunk', async () => {
  for (const maximum of [4, 10]) {
    const {read, state} = fixture([
      Buffer.from('abc'), Buffer.from('def'), Buffer.from('ghi'),
    ], 4, 9, maximum);
    await assert.rejects(read('fixture'), {code: 'PublicationContractCorrupt'});
    assert.deepEqual(state, {yields: 2, hashBytes: 3, concatenations: 0,
      closed: 1, stats: 1, verified: 0});
  }
});
