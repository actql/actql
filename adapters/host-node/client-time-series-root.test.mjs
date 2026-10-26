import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {timeSeriesPrimarySuccesses} from
  '../../scripts/fixtures/time-series-primary-source-input.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {installClientStaticPlan} from './client-interactive-plan.mjs';
import {sourceFreeTaskPlan} from './local-values-plan.mjs';
import {runCapturedStrategy} from './entry.mjs';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const [environmentWire, registry, aoaWire, valuesDocument] = await Promise.all([
  read('../../packages/sdk/fixtures/values.environment.json'),
  read('../../spec/dependencies/aoa-pipeline-registry.json'),
  read('../../spec/contracts/actql-aoa.json'),
  read('../../packages/sdk/fixtures/values.json'),
]);
const environmentBody = JSON.parse(environmentWire);
const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
  environmentBody.evidence_bundle_cid, false, false, true, false, true, false, false);
assert.ok(environment);
const valuesContract = JSON.stringify(JSON.parse(aoaWire).execution_contracts['REL.values']);
const installedContracts = checked(moon.clientPrepareInstalledSequenceContracts(
  registry, valuesContract, undefined, undefined));
const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

for (const name of ['json', 'empty-json', 'parameters-json']) {
  const fixture = timeSeriesPrimarySuccesses.find(value =>
    value.name === `time-series-primary-${name}`);
  test(`checked TimeSeries root uses one task and the installed provider: ${name}`, async () => {
    if (name === 'json') assert.equal(createHash('sha256').update(fixture.text).digest('hex'),
      '691fb26d1338c28b5fe357087468d563563f52cd9c3d5b35f88877434d6238c6');
    const prepare = installNodeClientProgramPreparation({moon, environment});
    const request = {kind: 'aql', input: {text: fixture.text, format: 'json'},
      parameters: fixture.parameters ?? null, maxWireBytes: 65536,
      maxNodes: 4096, maxDepth: 64};
    const prepared = prepare(request);
    assert.equal(moon.clientProgramTaskCount(prepared), 1);
    assert.equal(moon.clientProgramRequiresTaskCompilation(prepared), true);
    assert.equal(moon.clientProgramWithValuesRowLimit(prepared, 100), undefined);
    // A TimeSeries root must not masquerade as a Values fragment.
    assert.throws(() => checked(moon.clientProgramCompileLocalValues(prepared)));
    const compiled = checked(moon.clientProgramCompileLocalTasks(prepared));
    const service = installClientStaticPlan({moon, control,
      prepare: Object.assign(() => prepared, {assertOwned: prepare.assertOwned,
        kindOf: prepare.kindOf}), authorize: () => true});
    const view = await service(request);
    assert.equal(view.observation, 'static');
    assert.equal(view.provider_io, 0);
    const plan = sourceFreeTaskPlan({moon, control, preparedProgram: prepared,
      authorityScopeCid: cid('a'), namespaceId: 'time-series-root',
      storeAuthorityCid: cid('b'), now: () => '2026-10-14T00:00:00.000Z'});
    assert.equal(plan.results.length, 1);
    assert.deepEqual(plan.receiptEvidence.sourceEvidence, []);
    const other = prepare(request);
    assert.throws(() => checked(moon.clientProgramTaskStaticPlanView(
      other, compiled, 65536, 4096, 64)));
    const setup = moon.clientProgramOpenSourceFreeLocalHost(prepared,
      installedContracts, valuesContract, 1n, 0n, 0n, 0n);
    assert.ok(setup);
    const execution = await runCapturedStrategy(setup);
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.deepEqual(execution.resultInventory.map(value => value.name), ['answer']);
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].outputRows, fixture.results.answer.rows.length);
    } finally {
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });
}

test('Values keeps its direct compiler and its existing row ceiling', () => {
  const prepare = installNodeClientProgramPreparation({moon, environment});
  const prepared = prepare({kind: 'aql', input: {text: valuesDocument, format: 'json'},
    parameters: null});
  assert.equal(moon.clientProgramTaskCount(prepared), 1);
  assert.equal(moon.clientProgramRequiresTaskCompilation(prepared), false);
  checked(moon.clientProgramCompileLocalValues(prepared));
  assert.ok(moon.clientProgramWithValuesRowLimit(prepared, 100));
  assert.equal(moon.clientProgramWithValuesRowLimit(prepared, 10001), undefined);
});
