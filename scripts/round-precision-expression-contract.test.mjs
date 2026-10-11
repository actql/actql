import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';

const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('decimal-position ROUND/TRUNC retain exact predecessor bodies and complete identity preimages', () => {
  const history = read('portability/corpus/historical/pre-round-precision-contract-identities.json');
  assert.equal(history.source_revision, '0a561739e64ed93d647c24219225ea6e41e4d1f6');
  assert.equal(cid(history), 'sha256:9958e6628fc73b337d45f596223f6983e0672ae62300548cf4fe3b39177c4a80');
  const expected = {
  "scalar_law_manifest": "sha256:17cd0ac4d8948b61f661772f76fcae31d64d84adc25167578e3a117b0a77d31f",
  "expression_contract": "sha256:e54333eb86d263a364eb5a106775e34815de5c59c128995469af218911bbfbdd",
  "program_schema": "sha256:9996b5ecd898044665b6d113ef4636b5a56f27fe3321ba278ad5ad6983700fb6",
  "pipeline_registry": "sha256:1f3403ff9d4e9bc8e1dfab4da754564038bc63f985e2bf139d4d32b46db03c78",
  "ordered_derive_contract": "sha256:a3537565b4e6d2b8f476ff2a8a478075ec1f4aee1a5942d491ac74794e06239d",
  "fragment_execution_contract": "sha256:f118f134f4bb40fdee3b37f5ce89c93f3206b81b764b1636bfd34674b8eee394",
  "check_environment_contract": "sha256:955731071e31bc92d17644be84dae7d7506b1eedaf2b3de365e0f1c7662e8d22",
  "aoa_contract": "sha256:55d0202bf89438490a27b7cc7f5996c096e0fbe879e3c4868b81de81edf13e53",
  "production_profile_registry": "sha256:1dff615a5fe4a44f10ea2ff8be8069516c76071581c8b0df2bd53eac1da04110",
  "barrier_manifest": "sha256:98cabab7effed19178941d006ff89d3d6c08da0ebbc721d0a975058b4762d67c"
};
  assert.deepEqual(history.contracts.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of history.contracts) {
    assert.equal(item.cid, expected[item.id]);
    assert.equal(cid(item.body), item.cid);
  }
  const earlier = Object.fromEntries(history.contracts.map(item => [item.id, item.body]));
  // Freeze the adopted ROUND side as later scalar increments extend current bodies.
  const adopted = Object.fromEntries(read('portability/corpus/historical/pre-finite-math-contract-identities.json').contracts.map(item => [item.id, item.body]));
  const expression = adopted.expression_contract;
  const program = adopted.program_schema;
  // The predecessor above is captured from the actual published parent. This
  // comparison only verifies the narrow extension; it never invents that body.
  const counts = {round: 0, trunc: 0};
  function unaryOnly(value) {
    if (Array.isArray(value)) return value.map(unaryOnly);
    if (value === null || typeof value !== 'object') return value;
    const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, unaryOnly(item)]));
    const name = result.properties?.op?.const ?? (result.required?.length === 1 ? result.required[0] : null);
    if (name === 'round' || name === 'trunc') {
      const key = result.properties?.op ? 'body' : name;
      const shape = result.properties[key];
      assert.equal(shape.oneOf.length, 2);
      const unary = shape.oneOf[0];
      assert.deepEqual(Object.keys(unary), ['$ref']);
      assert.deepEqual(shape.oneOf[1], {type: 'array', minItems: 2, maxItems: 2, items: unary});
      result.properties[key] = unary;
      counts[name]++;
    }
    return result;
  }
  const predecessor = unaryOnly(expression);
  for (const name of ['round', 'trunc']) {
    predecessor.laws[name] = earlier.expression_contract.laws[name];
    assert.notDeepEqual(expression.laws[name], predecessor.laws[name]);
  }
  predecessor.grammar_sha256 = earlier.expression_contract.grammar_sha256;
  assert.deepEqual(predecessor, earlier.expression_contract);
  assert.deepEqual(unaryOnly(program), earlier.program_schema);
  assert.ok(counts.round > 0 && counts.trunc > 0);
  assert.notEqual(cid(expression), expected.expression_contract);
  assert.notEqual(cid(program), expected.program_schema);
  // These owners do not acquire a new scalar representation or exception rule.
  assert.deepEqual(adopted.scalar_law_manifest, earlier.scalar_law_manifest);
  assert.deepEqual(adopted.production_profile_registry, earlier.production_profile_registry);
  assert.deepEqual(adopted.barrier_manifest, earlier.barrier_manifest);
  for (const entry of history.expression_fragments.cases) {
    assert.equal(canonical(entry.body), entry.canonical);
    assert.equal(cid(entry.body), entry.cid);
    assert.equal(Buffer.byteLength(entry.canonical), entry.bytes);
  }
  for (const entry of history.ordered_fragment.preimages) {
    assert.equal(canonical(history.ordered_fragment[entry.id]), entry.canonical);
    assert.equal(cid(history.ordered_fragment[entry.id]), entry.cid);
  }
  assert.equal(cid(history.policy_candidates.body), history.policy_candidates.expected_cid);
  const preimages = read('portability/corpus/historical/pre-round-precision-preimages.json');
  assert.equal(preimages.source_revision, history.source_revision);
  assert.equal(preimages.expression_contract_cid, expected.expression_contract);
  assert.equal(cid(preimages), 'sha256:f701c4995deba728254b09575ba512c78b93302fcf102284eec1d39758cbcf69');
  assert.equal(preimages.sources.length, 17);
  assert.equal(new Set(preimages.sources.map(entry => entry.source)).size, 17);
  for (const entry of preimages.sources) assert.equal(cid(entry.body), entry.cid, entry.source);
  assert.equal(preimages.identity_envelopes.length, 21);
  for (const entry of preimages.identity_envelopes) {
    assert.equal(canonical(entry.envelope), entry.canonical);
    assert.equal(cid(entry.envelope), entry.expected_cid);
  }
});
