// Independent connector declarations enter the actual Common owners. These
// tests do not synthesize approval or replace Common execution with a mock.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import test from 'node:test';
import {checked} from '../adapters/host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../adapters/host-node/installed-row-source.mjs';
import {installedConnectors} from '../adapters/connectors-builtin/installations.generated.mjs';
import {contentCommandFixture, moon} from '../adapters/host-node/fixtures/content-command.fixture.mjs';

const baseWire = (await readFile(new URL('../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const environment = wire => moon.clientProgramCheckEnvironment(wire,
  JSON.parse(wire).evidence_bundle_cid, false, false, true, false, false, false, false);
const prepare = (program, env) => moon.clientProgramPrepareEffectComputationWithParameters(
  JSON.stringify(program), 'json', env, undefined, []);

test('independent Source and Command are absent from the product table and admitted only by explicit declarations', () => {
  assert.equal(installedConnectors.some(entry => entry.registration === 'fixture'), false);
  const fixture = contentCommandFixture();
  const absent = prepare(fixture.program, environment(baseWire));
  assert.equal(moon.clientProgramEffectPreparationReady(absent), undefined);
  const sourceOnly = rowSourceCheckEnvironment(baseWire, fixture.declared);
  const noCommand = prepare(fixture.program, environment(sourceOnly.wire));
  assert.equal(moon.clientProgramEffectPreparationReady(noCommand), undefined);
  assert.notEqual(moon.clientProgramEffectPreparationIssue(noCommand), undefined);
  const complete = prepare(fixture.program, fixture.environment);
  const prepared = moon.clientProgramEffectPreparationReady(complete);
  assert.ok(prepared, inspect(moon.clientProgramEffectPreparationIssue(complete), {depth: 6}));
  const compiled = checked(moon.clientProgramCompileLocalEffects(prepared));
  const plan = JSON.parse(moon.clientProgramEffectCompilationPlanWire(compiled));
  assert.deepEqual(plan.execution_material.program, fixture.program);
  assert.equal(Object.hasOwn(fixture.command, 'minimum_approval'), false);
  assert.equal(fixture.command.idempotency.support, 'unsupported');
  assert.deepEqual(moon.clientProgramEffectCompilationResultNames(compiled), ['r']);
});

test('independent Source uses the original acquisition owner and exact bounded capture rather than a connector evaluator', async () => {
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'independent-data', 'reference_source', 'reference_source/0.1', JSON.stringify({views: [{
      resource: 'records', resource_kind: 'reference_record',
      fields: [{name: 'name', type: 'string', nullable: false}]}]}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const sourceEnvironment = rowSourceCheckEnvironment(baseWire, declared);
  // Select only an ordinary scalar from the independently registered Source.
  // No invented Ref or successful permission double is needed for this owner
  // test; real current Ref/approval/dispatch are exercised by the public cases.
  const program = {version: 'actql/0.1', id: 'independent-source-addition', stages: [{
    id: 'read', inputs: {remote: {connector: 'independent-data', resource: 'records'}},
    steps: [{filter: 'true', as: 'all_rows'}, {select: ['name'], as: 'out'}],
    results: {r: {from: 'out', fields: ['name']}}}],
    results: {r: {from: {stage: 'read', result: 'r'}}}};
  const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
    JSON.stringify(program), 'json', environment(sourceEnvironment.wire), undefined);
  const prepared = moon.clientProgramPreparationReady(outcome);
  assert.ok(prepared, inspect(moon.clientProgramPreparationIssue(outcome), {depth: 6}));
  const read = path => readFile(new URL(`../spec/${path}`, import.meta.url), 'utf8');
  const [registryWire, aoa, query, evidence] = await Promise.all([
    read('dependencies/aoa-pipeline-registry.json'), read('contracts/actql-aoa.json').then(JSON.parse),
    read('contracts/actql-query-acquisition.json'), read('contracts/actql-query-process-evidence.json')]);
  const values = JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment = JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered = JSON.stringify(aoa.execution_contracts['REL.derive.ordered']);
  // Retain the same original contract owner for requirement and acquisition;
  // registry wire is constructor input, never the already-admitted selection.
  const registry = checked(moon.clientPrepareInstalledSequenceContracts(registryWire, values, fragment, ordered));
  const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(prepared, 0, 0,
    registry, values, fragment, ordered));
  const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(
    declaration, requirement, query, evidence));
  assert.equal(checked(moon.clientProgramRowSourceRequestWire(acquisition)), '{}');
  const expected = ['{"name":"é\\r\\n"}', '{"name":"é\\r\\n"}'];
  const bytes = Buffer.from('[{"name":"é\\r\\n"},{"name":"é\\r\\n"}]');
  for (const [name, ceiling] of [['exact', 2], ['one-short', 1]]) {
    const run = checked(moon.clientProgramRowSourceStart(acquisition, name, () => true));
    try {
      checked(moon.clientProgramRowSourceBegin(run, bytes.length, 2, ceiling));
      if (ceiling === 1) {
        assert.throws(() => checked(moon.clientProgramRowSourceAcceptPage(run, bytes)),
          {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(moon.clientProgramRowSourceCapture(run)),
          {code: 'MoonBitHostFailure'});
        continue;
      }
      assert.equal(checked(moon.clientProgramRowSourceAcceptPage(run, bytes)), 2);
      checked(moon.clientProgramRowSourceFinish(run));
      const captured = checked(moon.clientProgramRowSourceCapture(run));
      const source = checked(moon.clientProgramRowSourceCaptureSource(captured));
      const exported = checked(moon.clientProgramExportSourceCapture(
        source, requirement, 'independent-source/original/task-0/input-0'));
      assert.deepEqual(moon.clientProgramSourceCaptureExportRows(exported), expected);
    } finally { moon.clientProgramRowSourceClose(run); }
  }
});
