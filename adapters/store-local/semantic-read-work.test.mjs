import assert from 'node:assert/strict';
import test from 'node:test';
import crypto from 'node:crypto';
import {syncBuiltinESMExports} from 'node:module';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

test('semantic Store reads hash the acquired original once, with no cross-read cache', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-semantic-work-'));
  const digest = value => 'sha256:' + crypto.createHash('sha256').update(value).digest('hex');
  const control = createPublicationContractControlFixture();
  const store = await openLocalPublicationStore({directory, storeAuthorityCid: digest('authority'),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 16,
    maxContractNodes: 4096, maxContractDepth: 64}, control);
  t.after(async () => {await store.close(); await rm(directory, {recursive: true});});
  const contract = control.seal('run_invocation', JSON.stringify({
    version: 'actql-run-invocation/0.1', invocation_template_cid: digest('template'),
    observation_set_cid: digest('observations'),
  }), {maxWireBytes: 4096, maxNodes: 4096, maxDepth: 64});
  const stored = await store.putPublicationContract('run_invocation', contract.wire);
  const expected = Buffer.from(stored.contract.wire);
  const original = crypto.createHash;
  let fullBodyHashes = 0;
  crypto.createHash = function(...args) {
    const hash = Reflect.apply(original, this, args);
    const update = hash.update, finish = hash.digest;
    const chunks = [];
    hash.update = function(value, encoding) {
      chunks.push(Buffer.from(value, encoding));
      return Reflect.apply(update, this, [value, encoding]);
    };
    hash.digest = function(...values) {
      if (Buffer.concat(chunks).equals(expected)) fullBodyHashes++;
      return Reflect.apply(finish, this, values);
    };
    return hash;
  };
  syncBuiltinESMExports();
  try {
    assert.equal((await store.readPublicationContract(stored.semanticCid, 'run_invocation')).wire,
      stored.contract.wire);
    assert.equal(fullBodyHashes, 1, 'the semantic FD already hashes the same hard-linked allocation');
    await store.readPublicationContract(stored.semanticCid, 'run_invocation');
    assert.equal(fullBodyHashes, 2, 'a new read validates its acquired original independently');
    // New test-owned bytes only. This changes both hard links; a subsequent
    // read cannot reuse the former successful digest or return corrupt wire.
    await writeFile(join(directory, 'objects', stored.physical.cid.slice(7)),
      Buffer.alloc(expected.byteLength, 0x78));
    await assert.rejects(store.readPublicationContract(stored.semanticCid, 'run_invocation'));
  } finally {crypto.createHash = original; syncBuiltinESMExports();}
});
