import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {residentEffectSourceEnvironment} from './fixtures/resident-effect-computation.mjs';

test('Native Effect fixture declares two receipts without replacing its original Source or policies', async () => {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const original = JSON.parse(await readFile(new URL(
    '../packages/run-host-core/fixtures/source-compute-effect.environment.json', import.meta.url), 'utf8'));
  const wire = await residentEffectSourceEnvironment(repository);
  const actual = JSON.parse(wire);
  assert.deepEqual(actual.connector_capabilities[0].capability_contract_cids, [
    'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8',
    'sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929',
  ]);
  assert.notEqual(actual.evidence_bundle_cid, original.evidence_bundle_cid);
  const {evidence_bundle_cid: identity, ...body} = actual;
  assert.equal(identity, 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex'));
  assert.equal(wire, canonicalText(actual));
  // Every Catalog, schema, authority, Mapping, policy and other capability
  // remains the independently authored shared fixture, including Source CID.
  actual.connector_capabilities = original.connector_capabilities;
  actual.evidence_bundle_cid = original.evidence_bundle_cid;
  assert.deepEqual(actual, original);
});
