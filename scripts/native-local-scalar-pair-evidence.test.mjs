import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {canonicalText} from './check-canonical-json.mjs';
import {loadScalarPairBodies, verifyScalarPairBodies, scalarPairEvidence, scalarPairSource} from './native-local-scalar-pair-evidence.mjs';

const original = loadScalarPairBodies();

test('authentic complete predecessor bodies and inherited dependencies explain exactly the finite pair', () => {
  assert.equal(verifyScalarPairBodies(original).length, 11);
  const evidence = scalarPairEvidence();
  assert.equal(evidence.predecessor_source_sha, '109564ef9a4f8241096292843b875d4c81fbb6f3');
  assert.deepEqual(evidence.reachable_operations, ['REL.values', 'REL.derive', 'REL.where', 'REL.select']);
  assert.equal(evidence.asset_pairs.length, 6);
  assert(Buffer.byteLength(canonicalText(evidence)) <= 8192);
  // All original complete CIDs remain present, including excluded Ref branches.
  assert.equal(evidence.body_pairs.find(x => x.role === 'values').original_cid,
    'sha256:9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b');
});

test('unknown scalar law, schema, inherited pin and external dependency changes refuse', () => {
  for (const change of [
    x => { x.current.values.semantics.row_order = 'sorted'; },
    x => { x.current['value-contract'].$defs.value_contract.oneOf[0].properties.scale.maximum = 39; },
    x => { x.current.expression.inherited_text_time_profile_cid = 'sha256:' + '0'.repeat(64); },
    x => { x.current['text-time-dependencies'].unexpected = true; },
    x => { x.current['unicode-data'].expansion.nfkc_max_decomposed_codepoints_per_input = 19; },
    x => { x.current['derive-binding'].additionalProperties = true; },
    x => { x.current.registry['REL.where'].unexpected = 'permission'; },
  ]) {
    const pair = structuredClone(original);
    change(pair);
    assert.throws(() => verifyScalarPairBodies(pair), /Unknown current body/);
  }
});

test('missing, relabelled or unknown predecessor material is not repaired from current bodies', () => {
  for (const change of [
    x => { delete x.old['text-time']; },
    x => { x.old.values = x.current.values; },
    x => { x.old.expression.profile_id = 'unknown-profile'; },
    x => { x.old.registry['REL.values'].execution_contract.cid = x.current.registry['REL.values'].execution_contract.cid; },
  ]) {
    const pair = structuredClone(original);
    change(pair);
    assert.throws(() => verifyScalarPairBodies(pair));
  }
});

test('generated bounded evidence stays tied to reviewed source inputs without a Git checkout of old109', () => {
  assert.equal(readFileSync('src/run_publication_host/client_native_local_scalar_pair_evidence.generated.mbt', 'utf8'), scalarPairSource());
  assert(Object.keys(original.old).every(role => original.current[role]));
});
