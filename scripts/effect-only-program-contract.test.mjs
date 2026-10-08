import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkEffectOnlyProgramContract, effectRootRule, tableWriteSchema,
  withEffectOnlyProgramContract} from './effect-only-program-contract.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
const stages = JSON.parse(readFileSync('spec/contracts/actql-stage-contracts.json', 'utf8'));

test('empty Result inventories require Effects independently of Table and Connector names', () => {
  checkEffectOnlyProgramContract(registry, stages);
  assert.deepEqual(effectRootRule, {
    if: {required: ['results'], properties: {results: {maxProperties: 0}}},
    then: {required: ['effects'], properties: {effects: {minProperties: 1}}},
  });
  for (const program of parameterPrograms(registry)) {
    assert.equal(program.properties.results.minProperties, undefined);
    assert.deepEqual(program.allOf, [effectRootRule]);
    // Ordinary named definitions still require explicit fields and from.
    assert.deepEqual(program.properties.results.additionalProperties.required, ['from', 'fields']);
    assert.equal(program.properties.results.additionalProperties.properties.fields.minItems, 1);
    const store = program.properties.effects.additionalProperties.oneOf.find(member => member.properties?.store).properties.store;
    assert.deepEqual(store.properties.from.oneOf.map(body => body.required), [['result'], ['table_input']]);
    assert.deepEqual(store.properties.table_write, tableWriteSchema);
  }
});

test('fixed write bindings retain exact operation and physical identity constraints', () => {
  assert.equal(tableWriteSchema.additionalProperties, false);
  assert.deepEqual(tableWriteSchema.required, ['intent', 'action', 'expected_table',
    'mapping_cid', 'capability_cid', 'installation_binding_cid']);
  assert.deepEqual(tableWriteSchema.properties.intent.enum, ['create', 'create_or_replace']);
  assert.deepEqual(tableWriteSchema.properties.action.enum, ['create', 'replace']);
  assert.deepEqual(tableWriteSchema.allOf[0].then, {properties: {expected_table: {type: 'null'}}});
  assert.deepEqual(tableWriteSchema.allOf[1].then, {properties: {
    intent: {const: 'create_or_replace'}, expected_table: {type: 'object'}}});
  assert.deepEqual(tableWriteSchema.properties.expected_table.oneOf[1].required,
    ['table_uuid', 'generation_cid']);
});

test('contract generator does not replace unrelated future root constraints', () => {
  const changed = structuredClone(registry);
  parameterPrograms(changed)[0].allOf.push({required: ['future_obligation']});
  assert.throws(() => withEffectOnlyProgramContract(changed, stages),
    /Unreviewed Program root constraints/);
});
