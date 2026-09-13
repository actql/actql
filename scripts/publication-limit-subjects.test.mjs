import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
const vectors = read('../portability/corpus/publication-limit-subjects.json');
const policyContract = read('../spec/contracts/actql-capacity-host-policy.json');
// This oracle uses Node's serializer and crypto, not a compiler/lowerer emitter.
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}
const cid = (value) => `sha256:${createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex')}`;

test('publication subjects and Host-only resolved-limit identities are fixed independently', () => {
  const policy = Object.fromEntries(policyContract.schema.required
    .filter((key) => key !== 'version').map((key) => [key, vectors.host_policy_all_limits]));
  policy.version = 'actql-capacity-host-policy/0.1';
  assert.equal(cid(policy), vectors.expected_policy_cid);
  const witness = {
    dependencies: [cid(policy)], derivation: { op: 'source' },
    law_id: 'actql.host.artifact-rows', role: 'host_ceiling',
    source: { field: 'max_artifact_rows', kind: 'host_policy', policy_cid: cid(policy) },
    unit: 'rows', value: 1000, version: 'actql-bound-witness/0.1',
  };
  assert.equal(cid(witness), vectors.expected_host_witness_cid);
  witness.witness_cid = cid(witness);
  for (const vector of vectors.cases) {
    const token = vector.result_name.replaceAll('~', '~0').replaceAll('/', '~1');
    assert.equal(token, vector.token);
    const body = {
      author_guard_binding: 'absent', breach: 'fail', candidates: [witness],
      effective_max: 1000, enforcement: 'engine_atomic',
      subject_ref: `unit:${vectors.unit_definition_cid}#/results/${token}/rows`,
      unit: 'rows', version: 'actql-resolved-limit/0.1',
    };
    assert.equal(cid(body), vector.expected_limit_cid);
    assert.notEqual(cid({ ...body, subject_ref: body.subject_ref.replace('/rows', '/bytes') }), cid(body));
  }
});
