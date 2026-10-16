import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {parameterPrograms} from './parameter-schema.mjs';
import {createValuesSchemas, createValuesSchema, withoutCreateValuesSchema,
  checkCreateValuesVectors} from './create-values.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const protocol = read('spec/contracts/actql-protocol-schemas.json');
const vectors = read('portability/corpus/create-values.json');
const create = program => program.properties.effects.additionalProperties.oneOf
  .find(member => member.properties?.create).properties.create;

test('both actual Program schemas add only the adopted closed values alternative and retain original create preimages', () => {
  createValuesSchemas(protocol);
  const original = JSON.parse(execFileSync('git', ['show',
    vectors.previous_source + ':spec/contracts/actql-protocol-schemas.json'],
  {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024})).artifact_schemas.executable_plan
    .properties.execution_material.properties.program;
  assert.equal(machineCid(original), vectors.previous_program_grammar_cid);
  assert.deepEqual(create(original), vectors.previous_create_body);
  for (const program of parameterPrograms(protocol)) {
    assert.equal(machineCid(program), vectors.program_grammar_cid);
    assert.equal(machineCid(create(program)), vectors.create_body_cid);
    assert.deepEqual(create(program), vectors.create_body);
    assert.deepEqual(withoutCreateValuesSchema(program), original,
      'No unrelated field/legacy alternative or identity changed');
    assert.deepEqual(create(program).properties.values, createValuesSchema());
    assert.equal(Object.hasOwn(create(program).properties.values, 'minProperties'), false,
      'Mapping requirements own empty-map admission');
  }
});

test('normal schema gate refuses absent values, missing source relationship, weakened shape and changed old payload', () => {
  for (const mutate of [
    p => { delete create(p).properties.values; },
    p => { delete create(p).dependentRequired; },
    p => { create(p).dependentRequired.values = []; },
    p => { create(p).properties.values.type = ['object', 'null']; },
    p => { create(p).properties.values.minProperties = 1; },
    p => { create(p).properties.values.additionalProperties.oneOf[0].additionalProperties = true; },
    p => { create(p).properties.values.additionalProperties.oneOf[1].properties.field.minLength = 0; },
    p => { create(p).properties.payload = {}; },
    p => { create(p).allOf[1].oneOf = []; },
  ]) {
    const changed = structuredClone(protocol);
    mutate(parameterPrograms(changed)[0]);
    assert.throws(() => createValuesSchemas(changed));
  }
});

test('independent input-wire and actual emitted header preimages preserve legacy raw business objects', () => {
  const text = checkCreateValuesVectors(vectors);
  assert.equal(readFileSync('src/stage_syntax/create_values.generated_test.mbt', 'utf8'), text);
  assert.equal(vectors.programs.length, 12);
  const legacy = vectors.programs.filter(value => value.legacy);
  assert.equal(legacy.length, 2);
  for (const value of legacy) assert.equal(Object.hasOwn(value.program.stages[0].effects.save.create, 'values'), false);
  const raw = legacy.find(value => value.name === 'legacy_raw_payload').program.stages[0].effects.save.create.payload;
  assert.deepEqual(raw.Name, {$param: 'business_data'});
  assert.deepEqual(raw.values, {field: 'opaque_business'});
  assert.notEqual(vectors.programs.find(value => value.name === 'legacy_from').input_wire_cid,
    vectors.programs.find(value => value.name === 'field_subset').input_wire_cid);
  assert.equal(vectors.programs.find(value => value.name === 'raw_payload_conflict').header_issue, 'InvalidSourceResult');
});
