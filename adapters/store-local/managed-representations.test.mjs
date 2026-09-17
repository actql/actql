import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createLocalRetainedStore} from './files.mjs';
import {managedPhysicalRepresentation} from
  './managed-physical-representation.mjs';
import {
  managedInputPhysicalManifestCid,
  registerManagedInput,
  withManagedInputFiles,
} from './managed-representations.mjs';

const codec = `sha256:${'1'.repeat(64)}`;
const fields = JSON.stringify([['id', 'DOUBLE', null, null]]);

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-managed-registry-'));
  const store = await createLocalRetainedStore({
    parentDirectory: directory,
    capacityBytes: 100,
    maxFrameBytes: 16,
  });
  t.after(async () => {
    store.close();
    await store.cleanup();
    await rmdir(directory);
  });
  const writer = store.reserve(100);
  await writer.start();
  await writer.appendBytes(Buffer.from('stored rows'));
  return {store, body: await writer.sealPhysical()};
}

test('managed registry binds exact manifest interpretation and generation', async t => {
  const {store, body} = await fixture(t);
  const material = {}, input = {};
  const representation = managedPhysicalRepresentation(
    body, 2, codec, fields, [0],
  );
  const admitted = registerManagedInput(
    material, value => value === input, store, body, codec,
    representation.manifest,
  );
  assert.equal(managedInputPhysicalManifestCid(material), admitted.cid);
  assert.equal(admitted.manifest.row_count, 2);
  const observed = await withManagedInputFiles([
    {material, input, codecContractCid: codec},
    {material, input, codecContractCid: codec},
  ], () => true, files => files.map(file => file.path));
  assert.equal(observed[0], observed[1]);

  const changedSchema = managedPhysicalRepresentation(
    body,
    2,
    codec,
    JSON.stringify([['other', 'DOUBLE', null, null]]),
    [0],
  );
  assert.notEqual(changedSchema.manifest.schema_contract_cid,
    representation.manifest.schema_contract_cid);
  assert.notEqual(changedSchema.cid, representation.cid);
});

test('managed registry rejects mismatched row, codec and chunk identity', async t => {
  const {store, body} = await fixture(t);
  const base = managedPhysicalRepresentation(body, 2, codec, fields, [0]);
  for (const manifest of [
    {...base.manifest, row_count: 3},
    {...base.manifest, codec_contract_cid: `sha256:${'2'.repeat(64)}`},
    {...base.manifest, chunks: [{
      ...base.manifest.chunks[0],
      cid: `sha256:${'3'.repeat(64)}`,
    }]},
  ]) {
    assert.throws(() => registerManagedInput(
      {}, () => true, store, body, codec, manifest,
    ), {code: 'InvalidManagedInputRegistration'});
  }
});
