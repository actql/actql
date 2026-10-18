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

test('signed64 preserves legacy alternatives and refreshes the five original constructor/row-kernel type copies', () => {
  let copies = 0, refreshed = 0;
  const inspect = (current, previous, path) => {
    if (!current || typeof current !== 'object' || !previous || typeof previous !== 'object') return;
    if (previous.$defs?.value_contract) {
      const before = previous.$defs.value_contract.oneOf;
      const after = current.$defs.value_contract.oneOf;
      const original = structuredClone(before);
      const text = original.find(value => value.properties.type.const === 'string');
      if (text && text.properties.enum === undefined) {
        const complete = prior['spec/contracts/actql-protocol-schemas.json'].schemas.canonical_value_contract.$defs.value_contract.oneOf;
        text.properties.enum = complete.find(value => value.properties.type.const === 'string').properties.enum;
        assert.deepEqual(original, complete, 'only the already-owned Text enum copy was stale: '+path);
        assert.deepEqual(after, [...complete, leaf]);
        refreshed++;
      } else assert.deepEqual(after, [...before, leaf], path);
      copies++;
    }
    for (const [key, value] of Object.entries(previous)) inspect(current[key], value, path+'/'+key);
  };
  for (const [path, previous] of Object.entries(prior)) inspect(read(path), previous, path);
  assert(copies >= 24, 'actual containing schema copies were inspected');
  assert.equal(refreshed, 5, 'existing complete canonical copies now retain their original Text constraint');
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

test('query fixture migration changes only declared type-dependent owner and evidence edges', () => {
  const previous = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/pre-signed64-query-identities.json.gz')));
  const restore = (current, original, paths) => {
    const value = structuredClone(current);
    for (const path of paths) {
      const keys = path.split('/');
      let target = value, old = original;
      for (const key of keys.slice(0, -1)) { target = target[key]; old = old[key]; }
      target[keys.at(-1)] = structuredClone(old[keys.at(-1)]);
    }
    assert.deepEqual(value, original);
  };
  const oldOwner = previous['query-acquisition-owner'];
  const owner = read('portability/corpus/query-acquisition-owner.json');
  restore(owner, oldOwner, ['stage_semantics/expression_contract_cid',
    'program_semantics/expression_contract_cid',
    'program_semantics/program_template/stages/0/stage_semantics_cid',
    'program_semantics_cid', 'program_definition/program_semantics_cid',
    'program_definition_cid', 'owner/program_source_cid']);
  const oldAcquisition = previous['query-acquisition-identities'];
  const acquisition = read('portability/corpus/query-acquisition-identities.json');
  const slots = [['owner/program_source_cid'],
    ['owner/program_source_cid','requirement_cid','actual_access/scope_cid'],
    ['owner/program_source_cid','requirement_cid','actual_access/scope_cid'], [],
    ['requirement_cid'], ['requirement_cid'], ['expression_contract_cid'],
    ['expression_contract_cid','program_template/stages/0/stage_semantics_cid'], ['program_semantics_cid']];
  assert.equal(acquisition.length, slots.length);
  for (const [i, vector] of acquisition.entries()) {
    verifyIdentity(vector.body, vector.cid);
    verifyIdentity(oldAcquisition[i].body, oldAcquisition[i].cid);
    restore(vector.body, oldAcquisition[i].body, slots[i]);
  }
  for (const [i, vector] of read('portability/corpus/query-process-evidence.json').entries()) {
    verifyIdentity(vector.body, vector.cid);
    restore(vector.body, previous['query-process-evidence'][i].body,
      ['requirement_cid','actual_access/scope_cid']);
  }
  const two = read('portability/corpus/query-two-receipt.json'), oldTwo = previous['query-two-receipt'];
  restore(two.requirement.body, oldTwo.requirement.body, ['owner/program_source_cid']);
  for (const [i, vector] of two.receipts.entries()) {
    verifyIdentity(vector.body, vector.cid);
    restore(vector.body, oldTwo.receipts[i].body, ['requirement_cid']);
  }
  for (const [i, vector] of two.records.entries()) {
    verifyIdentity(vector.body, vector.cid);
    restore(vector.body, oldTwo.records[i].body, ['requirement_cid','accesses']);
  }
  verifyIdentity(two.observation.body, two.observation.cid);
  restore(two.observation.body, oldTwo.observation.body, ['requirement_cid',
    'owner/program_source_cid','accesses','evidence_contract_cid',
    'coverage/source_validation_evidence_cid','coverage/filter_evidence_cid','coverage/select_evidence_cid']);
});
