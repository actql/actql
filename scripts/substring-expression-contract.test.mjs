import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {updateSubstringContracts, substringLaw} from './substring-expression-contract.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const bodies = () => ['actql-expressions','actql-protocol-schemas','actql-production-profile-schemas'].map(name => read(`spec/contracts/${name}.json`));
const shape = expression => expression.schemas.expression.$defs.expression.oneOf.find(x => x.required?.[0] === 'substring');

test('substring current schemas preserve optional named length and local references', () => {
  const input = bodies();
  updateSubstringContracts(...input, true);
  updateSubstringContracts(...input);
  const prepared = structuredClone(input);
  updateSubstringContracts(...input, true);
  assert.deepEqual(input, prepared, 'owner update must be idempotent');
  assert.deepEqual(shape(input[0]).properties.substring, {
    type:'object',additionalProperties:false,required:['value','start'],properties:{
      value:{$ref:'#/$defs/expression'},start:{$ref:'#/$defs/expression'},length:{$ref:'#/$defs/expression'},
    },
  });
  assert.deepEqual(input[0].laws.substring, substringLaw);
});

test('substring owner rejects stale shape semantics profile membership and identity pins', () => {
  for (const mutate of [
    ([e]) => {shape(e).properties.substring.required.push('length');},
    ([e]) => {shape(e).additionalProperties = true;},
    ([e]) => {shape(e).properties.substring.properties.value.$ref = '#/$defs/other';},
    ([e]) => {shape(e).properties.substring.additionalProperties = true;},
    ([e]) => {shape(e).properties.substring.properties.length = {type:'number'};},
    ([e]) => {e.laws.substring.value = 'old interval intersection';},
    ([e]) => {e.laws.substring.admission = 'ignore resource obligations';},
    ([e]) => {e.schemas.evaluation_envelope.properties.operation.enum.push('substring');},
    ([,p]) => {p.artifact_registry_cid = 'sha256:'+'0'.repeat(64);},
    ([,,p]) => {p.schemas.text_time_expression.oneOf.push({required:['substring']});},
    ([,,p]) => {p.schemas.text_time_evaluation_envelope.properties.operation.enum.push('substring');},
    ([,,p]) => {p.schemas.text_time_evaluation_barrier.properties.evaluations.items.properties.operation.enum.push('substring');},
    ([,,p]) => {p.schema_cids.text_time_expression = 'sha256:'+'0'.repeat(64);},
    ([,,p]) => {p.registry_cid = 'sha256:'+'0'.repeat(64);},
  ]) {
    const input=bodies(); updateSubstringContracts(...input,true); mutate(input);
    assert.throws(()=>updateSubstringContracts(...input));
  }
});

test('substring preserves inherited fixed-arity semantics through the Content descriptor migration', () => {
  const retained=JSON.parse(gunzipSync(readFileSync(
    'scripts/fixtures/native-local-scalar-reviewed-current.json.gz'))).bodies;
  const base=retained['text-time'];
  const current=retained.expression;
  assert.equal(cid(read('spec/dependencies/actql-text-time-base.json')),
    read('spec/contracts/actql-expressions.json').inherited_text_time_profile_cid);
  // The merged Content contract intentionally changes one embedded value
  // descriptor, not SUBSTRING's inherited interval or fixed arity. Project
  // exactly that reviewed change back and check the complete original pin.
  // This is a data-only oracle, not an old runtime reader or a mutable fixture.
  const original = structuredClone(base);
  const refs = original.barrier_schema.$defs.value_contract.oneOf.filter(
    item => item.properties?.type?.const === 'content_ref');
  assert.equal(refs.length, 1);
  refs[0].properties.type.const = 'artifact_ref';
  original.barrier_schema_cid = cid(original.barrier_schema);
  assert.equal(original.barrier_schema_cid,
    'sha256:e1f3e142a17b9ef081e76d7d038da645ce17a5a7fe37624fcc0ab4f60563de28');
  assert.equal(cid(original),
    'sha256:2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc');
  assert.equal(cid(base), current.inherited_text_time_profile_cid);
  assert.deepEqual(base.source_schema, original.source_schema);
  assert.deepEqual(base.bound_derivation, original.bound_derivation);
  const source=base.source_schema.oneOf.find(x=>x.required?.[0]==='substring');
  assert.deepEqual(source.properties.substring.required,['value','start','length']);
  assert.ok(base.evaluation_envelope_schema.properties.operation.enum.includes('substring'));
  assert.match(JSON.stringify(base.bound_derivation.substring),/length/);
});

const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');

test('substring freezes predecessor profiles and complete identity preimages before scalar migration', () => {
  const history = read('portability/corpus/historical/pre-substring-contract-identities.json');
  assert.equal(history.source_revision, '28450a2a2cb9a3db371eeec8590b15595280e5cf');
  assert.equal(cid(history), 'sha256:25ca64907d69703a78e0ff85fbbf35c68a226992fbc7805b5bd161ed6da18cc7');
  const expected = {
  "scalar_law_manifest": "sha256:c1da16b95664cf0d466102f988c2c6b7119ca651bf03df89373b2fbeda7cfafd",
  "expression_contract": "sha256:fec9ffe5df68248b60591c4d61d4e01e55582a5dd23471831634773b07a8a2c6",
  "program_schema": "sha256:59de4954c4291b2999792c96ddf3d0b576aaaebfabeece8f17de87b3bd8795a8",
  "pipeline_registry": "sha256:752a1cf12a3bf5e71f7fdf6b8e4b314a9df0623933671ef8729010ef48178081",
  "ordered_derive_contract": "sha256:bcfd4a48b923d0d81814740d2d0ce7d5a6d3e7276c2c6b4725df0d1d1e459115",
  "fragment_execution_contract": "sha256:204eca2e915fdc22b2ac2f13451ee2de0cb6f62483b02ebc35d6c03c84fdf0bf",
  "check_environment_contract": "sha256:239edcc1918da1cae4566df59aa45eb253cbc3550d6cc3b0fe38a362ce98d3aa",
  "aoa_contract": "sha256:f4367116dba3df8d0a584418c7056e50d12f26054fae3f9600f2f5d0d438f73f",
  "production_profile_registry": "sha256:5292f70196ff83eb6a87d4df5ef26e5ffdda5f1b3df58f972815245ae7a8a1df",
  "barrier_manifest": "sha256:8d2b0da02c425402474f281cbe9ab15d5bdc6fed061e40005d2ebc13353904c7"
};
  assert.deepEqual(history.contracts.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of history.contracts) {
    assert.equal(item.cid, expected[item.id]);
    assert.equal(cid(item.body), item.cid);
  }
  const earlier = Object.fromEntries(history.contracts.map(item => [item.id, item.body]));
  assert.deepEqual(shape(earlier.expression_contract).properties.substring.required, ['value', 'start', 'length']);
  assert.ok(earlier.expression_contract.schemas.evaluation_envelope.properties.operation.enum.includes('substring'));
  assert.ok(earlier.production_profile_registry.schemas.text_time_expression.oneOf.some(item => item.required?.[0] === 'substring'));
  assert.match(earlier.expression_contract.laws.envelopes, /substring tightens input bytes/);
  // This transition compares with its exact adopted successor, not later scalar extensions.
  const adopted = Object.fromEntries(read('portability/corpus/historical/pre-safe-arithmetic-contract-identities.json').contracts.map(item => [item.id, item.body]));
  const current = [adopted.expression_contract, null, adopted.production_profile_registry];
  assert.notEqual(cid(current[0]), expected.expression_contract);
  assert.notEqual(cid(current[2]), expected.production_profile_registry);
  assert.equal(cid(adopted.scalar_law_manifest), expected.scalar_law_manifest);
  assert.notEqual(cid(adopted.barrier_manifest), expected.barrier_manifest);
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
  const preimages = read('portability/corpus/historical/pre-substring-preimages.json');
  assert.equal(preimages.source_revision, history.source_revision);
  assert.equal(preimages.expression_contract_cid, expected.expression_contract);
  assert.equal(cid(preimages), 'sha256:64a4524999dbf72b48b365f31f4f99da321585fdfa8f6140b981cd352a29cda1');
  assert.equal(preimages.sources.length, 17);
  assert.equal(new Set(preimages.sources.map(entry => entry.source)).size, 17);
  for (const entry of preimages.sources) assert.equal(cid(entry.body), entry.cid, entry.source);
  assert.equal(preimages.identity_envelopes.length, 21);
  for (const entry of preimages.identity_envelopes) {
    assert.equal(canonical(entry.envelope), entry.canonical);
    assert.equal(cid(entry.envelope), entry.expected_cid);
  }
});
