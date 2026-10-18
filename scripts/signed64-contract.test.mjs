import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
import {signed64Body} from './protocol-value-contracts.mjs';
import {parameterSchema} from './parameter-schema.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const prior = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/pre-signed64-type-closure.json.gz'))).records;
const vectors = read('portability/corpus/signed64-identities.json');
const protocol = read('spec/contracts/actql-protocol-schemas.json');
const leaf = {type:'object', required:['type','nullable'], additionalProperties:false,
  properties:{type:{const:'int64'},nullable:{type:'boolean'}}};

test('signed64 adds one type branch while every original checked and authored alternative stays exact', () => {
  let copies = 0;
  const inspect = (current, previous) => {
    if (!current || typeof current !== 'object' || !previous || typeof previous !== 'object') return;
    if (previous.$defs?.value_contract) {
      const before = previous.$defs.value_contract.oneOf;
      const after = current.$defs.value_contract.oneOf;
      assert.deepEqual(after, [...before, leaf]);
      copies++;
    }
    for (const [key, value] of Object.entries(previous)) inspect(current[key], value);
  };
  for (const [path, previous] of Object.entries(prior)) inspect(read(path), previous);
  assert(copies >= 20, 'actual containing schema copies were inspected');
  const before = prior['spec/contracts/actql-protocol-schemas.json'];
  for (const name of ['author_value_contract', 'canonical_value_contract']) {
    const expected = structuredClone(before.schemas[name]);
    expected.$defs.value_contract.oneOf.push(leaf);
    assert.deepEqual(protocol.schemas[name], expected);
  }
  assert.deepEqual(signed64Body(protocol).grammar, leaf);
});

test('signed64 inherited barrier changes only its type declaration and original dependency edge', () => {
  const expected = structuredClone(prior['spec/dependencies/actql-text-time-base.json']);
  assert.equal(machineCid(expected), vectors.inheritedBarrier.priorCid);
  expected.barrier_schema.$defs.value_contract.oneOf.push(leaf);
  expected.barrier_schema_cid = machineCid(expected.barrier_schema);
  const current = read('spec/dependencies/actql-text-time-base.json');
  assert.deepEqual(current, expected);
  verifyIdentity(current, vectors.inheritedBarrier.currentCid, vectors.inheritedBarrier.canonicalPreimage);
  assert.equal(read('spec/contracts/actql-expressions.json').inherited_text_time_profile_cid,
    vectors.inheritedBarrier.currentCid);
});

test('signed64 and legacy Contract preimages remain distinct with independently authored exact bytes', () => {
  const identities = new Set();
  for (const value of vectors.contracts) {
    verifyIdentity(value.contract, value.cid, value.canonicalPreimage);
    identities.add(value.cid);
  }
  assert.equal(identities.size, vectors.contracts.length);
  verifyIdentity(protocol.schemas.canonical_value_contract,
    vectors.canonicalGrammar.cid, vectors.canonicalGrammar.canonicalPreimage);
  const expected = vectors.valuesExecution;
  verifyIdentity(read('spec/contracts/actql-aoa.json').execution_contracts['REL.values'],
    expected.cid, expected.canonicalPreimage);
  const legacy = read('portability/corpus/text-enumeration-identities.json').valuesExecution;
  verifyIdentity(legacy.body, legacy.cid, legacy.canonicalPreimage);
  assert.notEqual(expected.cid, legacy.cid);
  assert.equal(expected.body.semantics.text_enumeration, legacy.body.semantics.text_enumeration);
});

test('Parameter int64 keeps its own closed shape and root declaration metadata', () => {
  for (const declaration of [false, true]) {
    const branch = parameterSchema(declaration).oneOf.filter(value => value.properties.type.const === 'int64');
    assert.equal(branch.length, 1);
    assert.deepEqual(branch[0], {type:'object',additionalProperties:false,required:['type'],
      properties:{type:{const:'int64'},nullable:{type:'boolean',default:false},
        ...(declaration ? {default:{},meta:{$ref:'#/$defs/meta'}} : {})}});
  }
  assert.deepEqual(parameterSchema().oneOf.find(value => value.properties.type.const === 'number').properties,
    {type:{const:'number'},nullable:{type:'boolean',default:false},integer:{type:'boolean'},minimum:{type:'number'},maximum:{type:'number'}});
});
