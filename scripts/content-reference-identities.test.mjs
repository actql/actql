import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent ASCII canonical preimages, not the product encoder or issuer.
// Synthetic scopes below are key-encoding fixtures, never live byte authority.
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const without = (value, field) => {
  const body = {...value}; delete body[field]; return cid(body);
};
const vector = read('spec/lookup-key-encoding-vector.json');
const historical = read('portability/corpus/historical/pre-contentref-lookup-encoding.json');

test('prior lookup preimage retains its identity without authorizing old wire', () => {
  assert.equal(historical.expected_cid,
    'sha256:8bf8ef10683de366b0b2d9614c6cd808376e36dd1154605ecb0fddb21c15ec04');
  assert.equal(cid(historical.expected_body), historical.expected_cid);
  assert.equal(canonical(historical.expected_body), historical.expected_canonical_bytes);
  const old = historical.input_rows[0][1];
  assert.equal(old.version, 'actql-artifact-ref/0.1');
  assert.equal(without(old, 'artifact_ref_cid'), old.artifact_ref_cid);
});

test('current lookup binds independently fixed ContentRef and issuer preimages', () => {
  const expectedRef = 'sha256:6a3061840640f9359bdfee29c33e46f12594a5afa8293c6e1f9bcbb0883be3ed';
  for (const row of vector.input_rows) {
    const ref = row[1], evidence = ref.metadata.issuer_evidence;
    assert.equal(ref.$actql_ref, 'content');
    assert.equal(ref.version, 'actql-content-ref/0.1');
    assert.equal(ref.content_ref_cid, expectedRef);
    assert.equal(without(ref, 'content_ref_cid'), expectedRef);
    assert.equal(evidence.version, 'actql-content-issuer-evidence/0.1');
    assert.equal(without(evidence, 'evidence_cid'), evidence.evidence_cid);
    assert.equal(Object.hasOwn(ref, 'artifact_ref_cid'), false);
    assert.equal(Object.hasOwn(ref.metadata, 'artifact_store_id'), false);
  }
  assert.notEqual(expectedRef, historical.input_rows[0][1].artifact_ref_cid);
  assert.equal(vector.expected_body.key_roles[1].value_contract.type, 'content_ref');
  assert.deepEqual(vector.expected_body.tuples.map(tuple => tuple[1]), [expectedRef, expectedRef]);
  assert.deepEqual(vector.expected_body.tuples.map(tuple => tuple[0]), ['2.00', '10.00']);
  assert.equal(canonical(vector.expected_body), vector.expected_canonical_bytes);
  assert.equal(cid(vector.expected_body),
    'sha256:6169a0954828906a188a182921d010102502919b3af22089f9e38ec0383eb3df');
  assert.equal(vector.expected_cid, cid(vector.expected_body));
});

test('equal content bytes do not make distinct store scope or policy references equal', () => {
  const ref = vector.input_rows[0][1];
  for (const mutate of [
    body => { body.metadata.content_store_id = 'other-store'; },
    body => { body.metadata.storage_scope = 'other-workspace'; },
    body => { body.metadata.effective_data_policy_cid = 'sha256:' + '9'.repeat(64); },
    body => { body.metadata.retention_class = 'other-retention'; },
  ]) {
    const changed = structuredClone(ref); mutate(changed);
    assert.equal(changed.metadata.content_cid, ref.metadata.content_cid);
    assert.notEqual(without(changed, 'content_ref_cid'), ref.content_ref_cid);
  }
});
