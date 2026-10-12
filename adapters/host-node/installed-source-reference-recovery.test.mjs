// Source completion bytes are not reference authority. Recovery must use the
// current installed issuer and keep the original checked capture and identity.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {inspect} from 'node:util';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {canonical, cid, resource} from './fixtures/file-listing-source.fixture.mjs';

test('Source reference recovery requires current issuer and preserves original captured bytes', async () => {
  const read = path => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
  const schema = {resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
    name: {type: 'string', nullable: false}};
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    'fixture', 'fixture', 'fixture/0.1', canonical({views: [{resource: 'files',
      resource_kind: 'file', schema_wire: canonical(schema), schema_cid: cid(schema),
      facts_wire: '{}'}]}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const sourceEnvironment = rowSourceCheckEnvironment(
    (await read('spec/local-check-environment.json')).trimEnd(), declared);
  const environment = moon.clientProgramCheckEnvironment(sourceEnvironment.wire,
    sourceEnvironment.evidenceCid, false, false, true, false, false, false, false);
  assert.ok(environment);
  const program = {version: 'actql/0.1', id: 'source-reference-recovery', stages: [{
    id: 'capture', inputs: {remote: {connector: 'fixture', resource: 'files', view: 'records'}},
    steps: [{from: 'remote', filter: 'name IS NOT NULL', as: 'selected'},
      {from: 'selected', select: ['resource', 'name'], as: 'rows'}],
    results: {r: {from: 'rows', fields: ['resource', 'name']}},
  }], results: {r: {from: {stage: 'capture', result: 'r'}}}};
  const prepared = moon.clientProgramPrepareEffectFree(canonical(program), 'json', environment);
  assert.ok(prepared);
  const aoa = JSON.parse(await read('spec/contracts/actql-aoa.json'));
  const required = moon.clientProgramPrepareLocalQueryRequirement(prepared, 0, 0,
    await read('spec/dependencies/aoa-pipeline-registry.json'),
    JSON.stringify(aoa.execution_contracts['REL.values']),
    JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    JSON.stringify(aoa.execution_contracts['REL.derive.ordered']));
  assert.equal(required.$tag, 1, inspect(required, {depth: 12}));
  const requirement = checked(required);
  const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(declaration,
    requirement, await read('spec/contracts/actql-query-acquisition.json'),
    await read('spec/contracts/actql-query-process-evidence.json')));
  const originalRow = {resource: resource('d'), name: 'original.pdf'};
  const issuer = moon.clientProgramResourceReferenceIssuer((kind, wire) =>
    kind === 'file' && wire === canonical(originalRow.resource), () => true);
  const physical = checked(moon.clientProgramRowSourceStart(
    acquisition, 'original-reference-capture', () => true));
  const binding = 'original-run/task-0/input-0/reference-capture';
  let exported;
  try {
    checked(moon.clientProgramRowSourceBegin(physical, 8192, 1, 1, issuer));
    assert.equal(checked(moon.clientProgramRowSourceAcceptPage(physical,
      Buffer.from(canonical([originalRow])))), 1);
    checked(moon.clientProgramRowSourceFinish(physical));
    const captured = checked(moon.clientProgramRowSourceCapture(physical));
    const source = checked(moon.clientProgramRowSourceCaptureSource(captured));
    exported = checked(moon.clientProgramExportSourceCapture(source, requirement, binding));
  } finally { moon.clientProgramRowSourceClose(physical); }
  const capacity = moon.clientProgramInstalledRowCaptureCapacity(acquisition);
  assert.ok(capacity);
  const descriptor = moon.clientProgramSourceCaptureExportDescriptor(exported);
  const rows = moon.clientProgramSourceCaptureExportRows(exported);
  assert.deepEqual(rows, [canonical(originalRow)]);
  const savedRequirement = moon.clientProgramSourceCaptureExportRequirement(exported);
  const restore = issuer => checked(moon.clientProgramRestoreSourceCapture(requirement,
    savedRequirement, binding, binding, descriptor, rows, undefined, capacity, () => true, issuer));
  assert.throws(() => restore(undefined), {code: 'MoonBitHostFailure'},
    'stored envelopes alone cannot issue references');
  const denied = moon.clientProgramResourceReferenceIssuer(() => false, () => false);
  assert.throws(() => restore(denied), {code: 'MoonBitHostFailure'},
    'a current issuer refusing the original reference cannot restore it');
  let authorized = true, admissions = 0;
  const current = moon.clientProgramResourceReferenceIssuer((kind, wire) => {
    admissions++;
    return authorized && kind === 'file' && wire === canonical(originalRow.resource);
  }, wire => authorized && wire === canonical(originalRow.resource));
  const restored = restore(current);
  try {
    assert.ok(admissions > 0, 'restoration consults current reference authority');
    const source = moon.clientProgramSourceCaptureSource(restored);
    assert.ok(source);
    const again = checked(moon.clientProgramExportSourceCapture(source, requirement, binding));
    assert.deepEqual(moon.clientProgramSourceCaptureExportRows(again), rows);
    assert.equal(moon.clientProgramSourceCaptureExportDescriptor(again), descriptor);
    authorized = false;
    assert.throws(() => restore(current), {code: 'MoonBitHostFailure'},
      'a later restore does not retain a previous authorization decision');
  } finally { assert.equal(moon.clientProgramCloseSourceCapture(restored), true); }
  assert.equal(moon.clientProgramSourceCaptureCleanupPending(restored), false);
  assert.deepEqual(moon.clientProgramSourceCaptureUsage(restored), [0n, 0n, 0n]);
  assert.equal(moon.clientProgramSourceCaptureSource(restored), undefined);
});
