import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';
import {checkLocalInputSchemas} from './local-input-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {scoreContractSchema, vectorSchemas} from './vector-schema.mjs';

test('Local input score assertions and fusion use the same closed contract', () => {
  const snapshot = JSON.parse(readFileSync('spec/contracts/actql-local-relation-snapshot.json','utf8'));
  assert.deepEqual(snapshot.schema.properties.score_contracts.additionalProperties, scoreContractSchema());
  for (const policy of vectorSchemas().merge_rankings.oneOf.slice(0,2)) {
    assert.deepEqual(policy.properties.score_contract, scoreContractSchema());
  }
});

test('Local interpretation roots match pinned snapshot dependencies', () => {
  const snapshot = JSON.parse(readFileSync('spec/contracts/actql-local-relation-snapshot.json','utf8'));
  const reference = JSON.parse(readFileSync('spec/contracts/actql-local-source-reference.json','utf8'));
  const source = readFileSync('src/pipeline_check_context/core_contracts.mbt','utf8').replace(/\s+/g,' ');
  assert.deepEqual(snapshot.dependencies, {
    checked_type: {path:'spec/contracts/actql-protocol-schemas.json',pointer:'/schemas/canonical_value_contract',cid:machineCid(registry.schemas.canonical_value_contract)},
    source_reference: {path:'spec/contracts/actql-local-source-reference.json',pointer:'',cid:machineCid(reference)},
  });
  assert.ok(source.includes(`LocalSnapshotRules => "${machineCid(snapshot)}"`));
  assert.ok(source.includes(`LocalSourceReferenceRules => "${machineCid(reference)}"`));
  assert.equal(reference.dependencies,undefined);
});

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
test('both embedded Program input contracts exclude schema_ref', () => {
  checkLocalInputSchemas(registry);
  assert.equal(parameterPrograms(registry).length, 2);
});
test('each embedded input remains closed and cannot restore schema_ref', () => {
  for (let i = 0; i < 2; i++) {
    for (const mutate of [
      s => { s.properties.schema_ref = {type: 'string'}; },
      s => { s.additionalProperties = true; },
      s => { delete s.properties.schema; },
    ]) {
      const copy = structuredClone(registry);
      mutate(parameterPrograms(copy)[i].properties.inputs.additionalProperties.oneOf.find(s => s.properties?.carrier));
      assert.throws(() => checkLocalInputSchemas(copy));
    }
  }
});
