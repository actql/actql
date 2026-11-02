// This exercises the raw Common checker, not ordinary Request admission or provider I/O.
// The fixture collection has no row identity. Its declared read view remains
// the existing row-keyed GitHub view; write support cannot relax read keys.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment, rowSourceMapping} from
  './installed-row-source.mjs';

const read = path => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
const [views, baseWire] = await Promise.all([
  read('src/connectors/github/source-views.json'),
  read('spec/local-check-environment.json').then(wire => wire.trimEnd()),
]);
const restore = () => checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
  'fixture', 'github', 'github/0.1', views, undefined));
const writes = JSON.stringify({writes: [{resource: 'entries',
  resource_kind: 'collection', primary_identity: null,
  collection_identity: {container: 'weekly', partition: 7},
  fields: [{name: 'text', type: 'string', nullable: false}],
  create: {fields: ['text'], required: ['text'],
    permission: 'fixture:append', approval: 'required'}}]});
const mappingFor = declaration => rowSourceMapping(moon, declaration,
  writes, 'entries', [{target: 'text', field: 'text', null_behavior: 'reject'}]);
const prepareWith = (declaration, bodies) => {
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(baseWire, declared, bodies);
  const owner = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(owner);
  // These authored JSON-only vectors test Mapping/type admission directly.
  // A raw checked token is never presented as a funded Request or send permit.
  return request => moon.clientProgramEffectPreparationReady(
    moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(request.input), 'json', owner, undefined, []));
};
const program = (mapping, operation = 'create') => ({version: 'actql/0.1',
  id: 'collection-create', stages: [{id: 'produce', inputs: {},
    steps: [{values: {schema: {text: {type: 'string', nullable: false}},
      rows: [{text: 'literal e\u0301\r\n'}]}, as: 'values'}],
    results: {rows: {from: 'values', fields: ['text']}},
    effects: {append: {[operation]: {target: mapping.target,
      mapping: mapping.mappingRef, from: {result: 'rows'}}}}}],
  results: {answer: {from: {stage: 'produce', result: 'rows'}}}});
const request = input => ({kind: 'program', input, parameters: null});

test('an explicit collection-only create reaches raw Common Effect preparation', () => {
  const declaration = restore(), mapping = mappingFor(declaration);
  const body = JSON.parse(mapping.body);
  assert.equal(body.primary_identity, null);
  assert.deepEqual(Object.keys(body.target_schema.fields), ['text']);
  assert.deepEqual(body.permission_rules, [{effect_kind: 'create',
    selector_class: 'none', permissions: ['fixture:append'], write_fields: ['text']}]);
  assert.ok(prepareWith(declaration, [mapping.body])(request(program(mapping))));

  // A fresh declaration/Mapping owner reconstructs the exact same binding.
  const restored = restore(), again = mappingFor(restored);
  assert.equal(again.body, mapping.body);
  assert.equal(again.mappingCid, mapping.mappingCid);
  assert.equal(again.mappingRef, mapping.mappingRef);
  assert.ok(prepareWith(restored, [again.body])(request(program(again))));
});

test('collection omission, row addressing and modified collection bindings are refused', () => {
  const declaration = restore(), mapping = mappingFor(declaration);
  for (const operation of ['update', 'upsert', 'delete']) {
    assert.equal(prepareWith(declaration, [mapping.body])(
      request(program(mapping, operation))), undefined);
  }
  const selected = program(mapping);
  selected.stages[0].effects.append.create.selector = {id: 'invented-row'};
  assert.equal(prepareWith(declaration, [mapping.body])(request(selected)), undefined);
  const changed = {...JSON.parse(mapping.body),
    resource_identity_cid: `sha256:${'0'.repeat(64)}`};
  assert.equal(prepareWith(declaration, [JSON.stringify(changed)])(
    request(program(mapping))), undefined);
  for (const bad of [writes.replace('"primary_identity":null,', ''),
    writes.replace('"collection_identity":{"container":"weekly","partition":7},', '')]) {
    assert.throws(() => rowSourceMapping(moon, declaration, bad,
      'entries', [{target: 'text', field: 'text', null_behavior: 'reject'}]),
    {code: 'RowSourceMappingInvalidSpecification'});
  }
});
