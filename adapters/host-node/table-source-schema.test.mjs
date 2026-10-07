// The real checked SourceView -> selected acquisition -> row admission path.
// This is preparation for installed Table I/O, not its public packed acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';

const schemaWire = '{"id":{"nullable":false,"type":"number"},"p":{"contract":{"max_utf8_bytes":32,"nullable":true,"type":"string"},"presence":"conditional"}}';
// Independent fixed preimage, never a product-generated expected identity.
const schemaCid = 'sha256:326b7ad79f0904551619945e3eef1915cd61ac943ee05bb8e74f2ef61eea9ee5';
const views = {views: [{resource: 'rows', resource_kind: 'table',
  schema_wire: schemaWire, schema_cid: schemaCid}]};
const read = name => readFile(new URL(`../../${name}`, import.meta.url), 'utf8');

async function fixture() {
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    'table-local', 'table', 'table/0.1', JSON.stringify(views), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  assert.deepEqual(declared.views[0].fields, ['id', 'p']);
  const body = declared.contracts.map(JSON.parse).find(c => c.kind === 'carrier_schema').body;
  assert.deepEqual(body, {version: 'actql-relation-schema/0.1', fields: JSON.parse(schemaWire)});
  const environment = rowSourceCheckEnvironment((await read('spec/local-check-environment.json')).trimEnd(), declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire,
    environment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(checkedEnvironment);
  const document = steps => JSON.stringify({version: 'actql/0.1', id: 'table-read',
    stages: [{id: 'read', inputs: {table: {connector: 'table-local', resource: 'rows'}},
      steps, results: {rows: {from: 'output', fields: ['id']}}}],
    results: {rows: {from: {stage: 'read', result: 'rows'}}}});
  const prepared = moon.clientProgramPrepareEffectFree(document([
    {filter: 'id >= 0', as: 'retained'}, {select: ['id'], as: 'output'},
  ]), 'json', checkedEnvironment);
  assert.ok(prepared);
  // Both references in a dormant branch remain statically unguaranteed.
  for (const expression of ['p IS NOT NULL', 'false AND p = "unused"']) {
    assert.equal(moon.clientProgramPrepareEffectFree(document([
      {filter: expression, as: 'retained'}, {select: ['id'], as: 'output'},
    ]), 'json', checkedEnvironment), undefined);
  }
  const [registry, aoa, queryContract, evidenceContract] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'),
    read('spec/contracts/actql-aoa.json').then(JSON.parse),
    read('spec/contracts/actql-query-acquisition.json'),
    read('spec/contracts/actql-query-process-evidence.json'),
  ]);
  const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
    prepared, 0, 0, registry, JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
  const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(
    declaration, requirement, queryContract, evidenceContract));
  assert.deepEqual(moon.clientProgramRowSourceColumns(acquisition), ['id', 'p']);
  return {acquisition, declaration, declared};
}

test('saved Table schema reaches actual checked Source row admission for missing NULL and value', async () => {
  const {acquisition} = await fixture();
  for (const rows of [[{id: 1, p: 'value'}, {id: 2, p: null}, {id: 3}], []]) {
    const run = checked(moon.clientProgramRowSourceStart(acquisition, 'bounded', () => true));
    try {
      checked(moon.clientProgramRowSourceBegin(run, 4096, 10, 10));
      assert.equal(checked(moon.clientProgramRowSourceAcceptPage(run,
        Buffer.from(JSON.stringify(rows)))), rows.length);
      checked(moon.clientProgramRowSourceFinish(run));
      const capture = checked(moon.clientProgramRowSourceCapture(run));
      const source = checked(moon.clientProgramRowSourceCaptureSource(capture));
      const identity = checked(moon.clientProgramIdentifyCapturedSourceRelation(source));
      assert.equal(moon.clientProgramCapturedSourceRowCount(identity), rows.length);
      // The residual projection's schema is the independently authored id map,
      // while admission above still enforced the whole original sparse input.
      assert.equal(moon.clientProgramCapturedSourceSchemaCid(identity),
        'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513');
    } finally { moon.clientProgramRowSourceClose(run); }
  }
});

test('saved Table schema rejects required omission type and extent violations before capture', async () => {
  const {acquisition} = await fixture();
  for (const row of [{p: 'value'}, {id: '1'}, {id: 1, p: 7},
    {id: 1, p: 'x'.repeat(33)}, {id: 1, extra: true}]) {
    const run = checked(moon.clientProgramRowSourceStart(acquisition, 'invalid', () => true));
    try {
      checked(moon.clientProgramRowSourceBegin(run, 4096, 10, 10));
      assert.throws(() => checked(moon.clientProgramRowSourceAcceptPage(run,
        Buffer.from(JSON.stringify([{id: 0}, row])))));
      assert.throws(() => checked(moon.clientProgramRowSourceFinish(run)));
      assert.throws(() => checked(moon.clientProgramRowSourceCapture(run)));
    } finally { moon.clientProgramRowSourceClose(run); }
  }
});
