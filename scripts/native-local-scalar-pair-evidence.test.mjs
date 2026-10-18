import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {tmpdir} from 'node:os';
import {canonicalText} from './check-canonical-json.mjs';
import {loadHistoricalScalarPairBodies, loadScalarPairBodies, verifyScalarPairBodies, scalarPairEvidence, scalarPairSource, assertScalarPairEvidenceFresh} from './native-local-scalar-pair-evidence.mjs';

const original = loadHistoricalScalarPairBodies();

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

test('later expression grammar is not certified by the retained reviewed pair', () => {
  const changed = structuredClone(original);
  changed.current.expression.grammar_sha256 = '0'.repeat(64);
  assert.throws(() => verifyScalarPairBodies(changed), /Unknown current body: expression/);
  assert.equal(scalarPairEvidence().body_pairs.find(row => row.role === 'expression').current_cid,
    'sha256:e4b8431ae81884a1e198420dcbd08d6b12ef4dca4bd9b7b8ffa4cd45db887289');
});

test('retaining reviewed bodies does not snapshot away current implementation equality', () => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-scalar-pair-implementation-'));
  const fixture = 'scripts/fixtures/native-local-scalar-predecessor';
  const index = JSON.parse(readFileSync(fixture + '/manifest.json'));
  const first = index.implementation_records[0];
  try {
    for (const path of [fixture + '/manifest.json', fixture + '/' + first.fixture,
      'scripts/fixtures/native-local-scalar-reviewed-current.json.gz', first.path]) {
      mkdirSync(dirname(join(directory, path)), {recursive: true});
      copyFileSync(path, join(directory, path));
    }
    writeFileSync(join(directory, first.path), readFileSync(first.path, 'utf8') + '\n// changed implementation\n');
    assert.throws(() => loadScalarPairBodies(directory),
      error => error.message === 'Unknown scalar implementation change: ' + first.path);
  } finally { rmSync(directory, {recursive: true, force: true}); }
});

test('generated bounded evidence stays tied to reviewed source inputs without a Git checkout of old109', () => {
  assert.equal(readFileSync('src/run_publication_host/client_native_local_scalar_pair_evidence.generated.mbt', 'utf8'), scalarPairSource());
  assert(Object.keys(original.old).every(role => original.current[role]));
});

const vector = JSON.parse(readFileSync('reviews/2026-10-12-d-native-local-expiry-1701/scalar-runtime-pair-vector.json'));
test('independent Python full-body oracle agrees with bounded source evidence identity', async () => {
  const {machineCid} = await import('./actql-spec-family.mjs');
  const evidence = scalarPairEvidence();
  assert.equal(machineCid(evidence), vector.evidence_cid);
  assert.equal(evidence.exact_difference_cid, vector.exact_difference_cid);
  assert.equal(Buffer.byteLength(canonicalText(evidence)), vector.evidence_bytes);
  assertScalarPairEvidenceFresh();
});

test('closed pair vector preserves distinct complete manifest and source identities', async () => {
  const {createHash} = await import('node:crypto');
  const shape = JSON.parse(readFileSync('spec/contracts/actql-native-local-scalar-runtime-pair.schema.json'));
  const body = JSON.parse(vector.body);
  const valid = value => typeof value === 'object' && value !== null && !Array.isArray(value)
    && shape.required.every(k => Object.hasOwn(value, k))
    && Object.entries(value).every(([k,v]) => Object.hasOwn(shape.properties, k)
      && (Object.hasOwn(shape.properties[k], 'const') ? v === shape.properties[k].const
        : typeof v === 'string' && new RegExp(shape.properties[k].pattern).test(v)));
  assert.equal('sha256:' + createHash('sha256').update(vector.body).digest('hex'),
    'sha256:00df605c2c1173cdbd982bd7b54107df020de33f57b28d121c58c7daccc67090');
  assert.equal(vector.cid, 'sha256:00df605c2c1173cdbd982bd7b54107df020de33f57b28d121c58c7daccc67090');
  assert.equal(valid(body), true);
  assert.notEqual(body.current_source_sha, body.original_source_sha);
  assert.notEqual(body.current_manifest_sha256, body.original_manifest_sha256);
  for (const k of shape.required) {
    const missing = {...body}; delete missing[k]; assert.equal(valid(missing), false);
    assert.equal(valid({...body, [k]: null}), false);
  }
  for (const change of [{...body, permit: true}, {...body, profile: 'all-values'},
    {...body, evidence_cid: true}, {...body, platform: 'linux-x64-gnu'}]) assert.equal(valid(change), false);
});


test('current implementation changes cannot use the frozen historical proof operationally', () => {
  assert.throws(() => loadScalarPairBodies(), /Unknown scalar implementation change: /u);
  assertScalarPairEvidenceFresh();
});
