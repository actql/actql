import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {updateGoogleScalarContracts, updateSafeArithmeticScalarLaw} from './google-scalar-expression-contract.mjs';

const binary = ['safe_add', 'safe_subtract', 'safe_multiply', 'safe_divide'];
const names = [...binary, 'safe_negate'];
function fixtures() {
  const source = {oneOf: ['contains', 'abs', 'safe_div'].map(name => ({type: 'object', additionalProperties: false,
    required: [name], properties: {[name]: name === 'abs' ? {$ref: '#/$defs/source_expression'}
      : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/source_expression'}}}}))};
  const node = {oneOf: ['contains', 'abs', 'safe_div'].map(name => ({type: 'object', additionalProperties: false,
    required: ['op', 'body'], properties: {op: {const: name}, body: name === 'abs' ? {$ref: '#/$defs/machine_expression'}
      : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/machine_expression'}}}}))};
  return [{schemas: {source, node}, laws: {}}, {artifact_schemas: {program: structuredClone(source)}, artifact_schema_cids: {}}];
}
const grammar = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');

test('SAFE contract source and machine shapes have exact arity and preserve legacy safe_div', () => {
  const [expression, protocol] = fixtures();
  const legacy = [structuredClone(expression.schemas.source.oneOf[2]), structuredClone(expression.schemas.node.oneOf[2])];
  const counts = updateGoogleScalarContracts(expression, protocol, grammar, true);
  for (const name of names) {
    assert.deepEqual(counts[name], {source: 2, node: 1});
    const source = expression.schemas.source.oneOf.find(shape => shape.required[0] === name);
    const node = expression.schemas.node.oneOf.find(shape => shape.properties.op.const === name);
    assert.deepEqual(source.properties[name], name === 'safe_negate' ? {$ref: '#/$defs/source_expression'}
      : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/source_expression'}});
    assert.deepEqual(node.properties.body, name === 'safe_negate' ? {$ref: '#/$defs/machine_expression'}
      : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/machine_expression'}});
  }
  assert.deepEqual(expression.schemas.source.oneOf.find(shape => shape.required[0] === 'safe_div'), legacy[0]);
  assert.deepEqual(expression.schemas.node.oneOf.find(shape => shape.properties.op.const === 'safe_div'), legacy[1]);
  assert.equal(expression.laws.safe_div, undefined);
  updateGoogleScalarContracts(expression, protocol, grammar);
  const prepared = structuredClone([expression, protocol]);
  updateGoogleScalarContracts(expression, protocol, grammar, true);
  assert.deepEqual([expression, protocol], prepared);
});

test('SAFE contract verification rejects changed exception domains arities and predecessor meanings', () => {
  for (const mutate of [
    body => { body.laws.safe_divide.value = 'zero divisor only'; },
    body => { body.laws.safe_negate.signature = 'always nullable'; },
    body => { body.laws.safe_add.evaluation = 'catch every error'; },
    body => { body.laws.safe_multiply.signature = 'NUMERIC'; },
    body => { body.schemas.source.oneOf.find(s => s.required[0] === 'safe_subtract').properties.safe_subtract.maxItems = 3; },
    body => { body.schemas.node.oneOf.find(s => s.properties.op.const === 'safe_negate').properties.body = {type: 'array'}; },
  ]) {
    const [expression, protocol] = fixtures();
    updateGoogleScalarContracts(expression, protocol, grammar, true);
    mutate(expression);
    assert.throws(() => updateGoogleScalarContracts(expression, protocol, grammar));
  }
  const scalar = {number: {non_finite_result: 'failure', safe_divide_by_zero: 'null'}};
  updateSafeArithmeticScalarLaw(scalar, true);
  assert.deepEqual(scalar.number.safe_arithmetic, {
    domain: 'finite-ieee754-binary64-only', safe_add: 'overflow-null', safe_subtract: 'overflow-null',
    safe_multiply: 'overflow-null', safe_divide: 'zero-divisor-or-overflow-null', safe_negate: 'finite-negation-cannot-overflow',
    legacy_safe_div: 'zero-divisor-null-overflow-failure', underflow: 'finite-rounded-result-including-canonical-positive-zero',
    boundary: 'only-own-arithmetic-errors-after-once-only-eager-children',
  });
  assert.equal(scalar.number.non_finite_result, 'failure');
  assert.equal(scalar.number.safe_divide_by_zero, 'null');
  updateSafeArithmeticScalarLaw(scalar);
  scalar.number.safe_arithmetic.legacy_safe_div = 'overflow-null';
  assert.throws(() => updateSafeArithmeticScalarLaw(scalar));
});

const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('SAFE arithmetic retains exact predecessor contracts and complete identity preimages', () => {
  const history = read('portability/corpus/historical/pre-safe-arithmetic-contract-identities.json');
  assert.equal(history.source_revision, '747900d13d4bea8e54ef2e9d3f1a75d1ac3a1572');
  assert.equal(cid(history), 'sha256:3b03fe185695512bbf8ce7fdfda336a6a32d719d57e72e8288a73b5332a3b99b');
  const expected = {
  "scalar_law_manifest": "sha256:c1da16b95664cf0d466102f988c2c6b7119ca651bf03df89373b2fbeda7cfafd",
  "expression_contract": "sha256:a23cd070a4f1c2ee0c29d0badba3fd512ad50d073cbf2eef1a0373fe5186cb9a",
  "program_schema": "sha256:e8bcb79ad08efc425c52e38bcdcb30eebe19f1b2687af2bca68350ada5d75ef9",
  "pipeline_registry": "sha256:da4fee3d61e052daec966c67a64ca8902a8a3883c5133f040583b84498f241c9",
  "ordered_derive_contract": "sha256:a3985a87c4adee45b7924e5c6134d0f741750bb65b4e547ce45bb2532ea3ee61",
  "fragment_execution_contract": "sha256:8c71a3136f1ef823e7b241032b085bb8e1541829861d610c97967cb6620ecc22",
  "check_environment_contract": "sha256:4bf739ebe5e9a769a780b474ff5d3d44026283a4ace50cb64cfa574a0f3ad045",
  "aoa_contract": "sha256:6bcbd8e694cd666405cf97ad9aea06a9e60aa980940e5ed35905b88b2564c948",
  "production_profile_registry": "sha256:1dff615a5fe4a44f10ea2ff8be8069516c76071581c8b0df2bd53eac1da04110",
  "barrier_manifest": "sha256:98cabab7effed19178941d006ff89d3d6c08da0ebbc721d0a975058b4762d67c"
};
  assert.deepEqual(history.contracts.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of history.contracts) {
    assert.equal(item.cid, expected[item.id]);
    assert.equal(cid(item.body), item.cid);
  }
  const earlier = Object.fromEntries(history.contracts.map(item => [item.id, item.body]));
  // Freeze this transition's exact adopted successor before later scalar extensions.
  const adopted = Object.fromEntries(read('portability/corpus/historical/pre-round-precision-contract-identities.json').contracts.map(item => [item.id, item.body]));
  const expression = adopted.expression_contract;
  const program = adopted.program_schema;
  function withoutSafe(value) {
    if (Array.isArray(value)) return value.map(withoutSafe);
    if (value === null || typeof value !== 'object') return value;
    const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, withoutSafe(item)]));
    if (result.oneOf) result.oneOf = result.oneOf.filter(item => !names.includes(item.properties?.op?.const ?? item.required?.[0]));
    return result;
  }
  const predecessor = withoutSafe(expression);
  for (const name of names) delete predecessor.laws[name];
  predecessor.grammar_sha256 = earlier.expression_contract.grammar_sha256;
  assert.deepEqual(predecessor, earlier.expression_contract);
  assert.deepEqual(withoutSafe(program), earlier.program_schema);
  assert.notEqual(cid(expression), expected.expression_contract);
  assert.notEqual(cid(program), expected.program_schema);
  const scalar = adopted.scalar_law_manifest;
  updateSafeArithmeticScalarLaw(scalar);
  const priorScalar = structuredClone(scalar);
  delete priorScalar.number.safe_arithmetic;
  assert.deepEqual(priorScalar, earlier.scalar_law_manifest);
  assert.notEqual(cid(scalar), expected.scalar_law_manifest);
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
  const preimages = read('portability/corpus/historical/pre-safe-arithmetic-preimages.json');
  assert.equal(preimages.source_revision, history.source_revision);
  assert.equal(preimages.expression_contract_cid, expected.expression_contract);
  assert.equal(cid(preimages), 'sha256:3f14b29b37bf8e2c4e34c4f0738a7002a410e883b4372e706c70b4a30295fc80');
  assert.equal(preimages.sources.length, 17);
  assert.equal(new Set(preimages.sources.map(entry => entry.source)).size, 17);
  for (const entry of preimages.sources) assert.equal(cid(entry.body), entry.cid, entry.source);
  assert.equal(preimages.identity_envelopes.length, 21);
  for (const entry of preimages.identity_envelopes) {
    assert.equal(canonical(entry.envelope), entry.canonical);
    assert.equal(cid(entry.envelope), entry.expected_cid);
  }
});
