// Actual Store/crypto allocation witness, not a complete capacity profile.
// The existing portable contract-control fixture is explicitly a double.
import assert from 'node:assert/strict';
import test from 'node:test';
import crypto from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const cid = bytes => `sha256:${crypto.createHash('sha256').update(bytes).digest('hex')}`;

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-wire-backing-'));
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('wire backing authority'), privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 1048576, maxObjectBytes: 16384, maxObjects: 32,
    maxContractNodes: 4096, maxContractDepth: 64},
  createPublicationContractControlFixture());
  const prepared = [];
  let passed = false;
  t.after(async () => {
    for (const object of prepared) await object.prepared.release();
    assert.equal(await store.close(), true);
    if (passed) await rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved original wire-backing failure: ${directory}`);
  });
  return {store, prepared, pass() { passed = true; }};
}

function observeCryptoInput(t) {
  const original = crypto.createCipheriv;
  const observed = [];
  crypto.createCipheriv = (...args) => {
    const cipher = Reflect.apply(original, crypto, args);
    const update = cipher.update;
    cipher.update = function(input, ...rest) {
      observed.push(input);
      return Reflect.apply(update, this, [input, ...rest]);
    };
    return cipher;
  };
  syncBuiltinESMExports();
  const restore = () => { crypto.createCipheriv = original; syncBuiltinESMExports(); };
  t.after(restore);
  return {observed, restore};
}

test('private wire plaintext uses one exact dedicated backing before crypto', async t => {
  const f = await fixture(t);
  const probe = observeCryptoInput(t);
  try {
    for (const wire of ['', 'a', 'ab', 'abc', '{"p":null,"text":"é/e\u0301"}\r\n',
      'x'.repeat(12192)]) {
      const object = await f.store.preparePrivateEvidence(
        'model_invocation_evidence', wire, cid(wire));
      f.prepared.push(object);
      const input = probe.observed.at(-1);
      const length = Buffer.byteLength(wire, 'utf8');
      assert.equal(input.byteLength, length);
      assert.equal(input.byteOffset, 0, 'the original input must not borrow a pool slice');
      assert.equal(input.buffer.byteLength, length, 'price the actual dedicated backing, not a view');
      assert.deepEqual(input, Buffer.from(wire, 'utf8'));
      assert.equal(object.bytes, 128 + 4 * Math.ceil(length / 3));
    }
    const before = probe.observed.length;
    await assert.rejects(f.store.preparePrivateEvidence(
      'model_invocation_evidence', 'x'.repeat(12193), cid('one too many')),
    {code: 'PublicationObjectLimit'});
    assert.equal(probe.observed.length, before, 'extent refusal precedes crypto');
  } finally { probe.restore(); }
  f.pass();
  // This diagnostic retains observed inputs until test completion. Their
  // lifetimes do not establish production GC, FD ACK or a whole-phase grant.
});

test('private raw bytes still borrow the same original view without a wire snapshot', async t => {
  const f = await fixture(t);
  const original = Buffer.alloc(8192, 88);
  const bytes = original.subarray(20, 23);
  bytes.set([0, 255, 13]);
  const binding = {semanticCid: cid('borrowed wire-backing raw'),
    holdingCid: cid('borrowed wire-backing holding'), wire: '',
    byteCount: 3, contentCid: cid(bytes)};
  const probe = observeCryptoInput(t);
  try {
    f.prepared.push(...await f.store.prepareModelRawEvidence(binding, bytes));
    assert.equal(probe.observed.length, 2);
    assert.equal(probe.observed[0], bytes);
    assert.equal(probe.observed[0].buffer, original.buffer);
    assert.equal(probe.observed[0].buffer.byteLength, 8192);
    assert.equal(probe.observed[1].byteLength, 0);
  } finally { probe.restore(); }
  f.pass();
});
