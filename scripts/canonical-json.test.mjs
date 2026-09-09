import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { canonicalText, generateTests, resolvePointer, verifyIdentity } from './check-canonical-json.mjs';

test('canonical reference normalizes text, sorts UTF16 keys and rejects collisions', () => {
  assert.equal(canonicalText({ '\ue000': 1, '😀': 2, a: 'e\u0301\r\n' }), '{"a":"é\\n","😀":2,"":1}');
  assert.throws(() => canonicalText({ é: 1, 'e\u0301': 2 }));
  assert.throws(() => canonicalText({ 'a\r': 1, 'a\n': 2 }));
  for (const invalid of [NaN, Infinity, -Infinity, -0, '\ud800', '\udfff']) {
    assert.throws(() => canonicalText(invalid));
  }
});

test('identity checking rejects altered bytes or CID without rewriting either', () => {
  const cid = 'sha256:efbd0040190fb0871831e606c581f8a66db79d8e2bb836745a70051306956070';
  verifyIdentity({ b: [2, 3], a: 1 }, cid, '{"a":1,"b":[2,3]}');
  assert.throws(() => verifyIdentity({ a: 2, b: [2, 3] }, cid));
  assert.throws(() => verifyIdentity({ a: 1, b: [2, 3] }, cid, '{"b":[2,3],"a":1}'));
  assert.throws(() => verifyIdentity({}, 'sha256:bad'));
});

test('contract pointers resolve exact bodies including escaped member names', () => {
  const body = { 'a/b': { '~': 7 } };
  assert.equal(resolvePointer(body, '/a~1b/~0'), 7);
  assert.equal(resolvePointer(body, ''), body);
  for (const pointer of ['/missing', '/toString', 'a/b', '/a~2b']) {
    assert.throws(() => resolvePointer(body, pointer));
  }
});

test('generated tests require fixed identities and reject duplicate cases', () => {
  const fixture = {
    id: 'null',
    value: null,
    text: 'null',
    cid: 'sha256:74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b',
  };
  const generated = generateTests([fixture]);
  assert.equal(generateTests([fixture]), generated);
  assert.match(generated, /from_json\(input, 1, 0, 4\)/);
  assert.throws(() => generateTests([]));
  assert.throws(() => generateTests([fixture, fixture]));
  assert.throws(() => generateTests([{ ...fixture, text: ' null' }]));
});

test('large fixture strings are split without breaking supplementary scalars', () => {
  const value = 'a'.repeat(1023) + '😀' + 'b'.repeat(70000);
  const text = canonicalText(value);
  const fixture = { id: 'long', value, cid: 'sha256:' + createHash('sha256').update(text).digest('hex') };
  const generated = generateTests([fixture]);
  assert.match(generated, /\\u\{1f600\}/);
  assert.ok(generated.split('\n').every(line => line.length < 2000));
});
