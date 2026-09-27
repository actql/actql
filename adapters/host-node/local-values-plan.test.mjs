import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import * as runtime from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {sourceFreeValuesPlan, acquiredTaskRunAdmission} from
  './local-values-plan.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const policy = Object.freeze({executionContextCid: cid('a'),
  hostPolicyCid: cid('b'), expiresAt: '2027-01-01T00:00:00.000Z'});

for (const kind of ['values', 'tasks']) {
  test(`Local ${kind} prepares and compiles once with exact owner custody`,
    async () => {
      const acquired = kind === 'tasks';
      const environmentWire = await read(acquired
        ? './fixtures/query-amount-environment.json'
        : '../../packages/sdk/fixtures/values.environment.json');
      const document = await read(acquired
        ? '../connectors/duckdb/node/examples/program.json'
        : '../../packages/sdk/fixtures/values.json');
      const parameters = acquired ? JSON.parse(await read(
        '../connectors/duckdb/node/examples/parameters.json')) : null;
      const calls = {prepare: 0, values: 0, tasks: 0};
      const moon = {...runtime,
        clientProgramPrepareEffectFreeWithParameters(...args) {
          calls.prepare++;
          return runtime.clientProgramPrepareEffectFreeWithParameters(...args);
        },
        clientProgramCompileLocalValues(...args) {
          calls.values++;
          return runtime.clientProgramCompileLocalValues(...args);
        },
        clientProgramCompileLocalTasks(...args) {
          calls.tasks++;
          return runtime.clientProgramCompileLocalTasks(...args);
        },
      };
      const environment = moon.clientProgramCheckEnvironment(
        canonicalText(JSON.parse(environmentWire)),
        JSON.parse(environmentWire).evidence_bundle_cid,
        false, false, true, false, false, false, false);
      assert.ok(environment);
      const prepare = installNodeClientProgramPreparation({moon, environment});
      const request = {kind: 'aql', input: {text: document, format: 'json'},
        parameters};
      const preparedProgram = prepare(request);
      prepare.assertOwned(preparedProgram);
      const control = runtimeCore(moon).publicationControl;
      const plan = (acquired ? acquiredTaskRunAdmission : sourceFreeValuesPlan)({
        moon, control, preparedProgram, authorityScopeCid: cid('a'),
        tenantId: 'local', storeAuthorityCid: cid('c'),
        now: () => '2026-09-27T00:00:00.000Z',
      });
      assert.match(plan.runDefinition.identity, /^sha256:[0-9a-f]{64}$/u);
      assert.deepEqual(calls,
        {prepare: 1, values: acquired ? 0 : 1, tasks: acquired ? 1 : 0});

      const otherInstallation = installNodeClientProgramPreparation({moon,
        environment});
      const foreign = otherInstallation(request);
      assert.throws(() => prepare.assertOwned(foreign),
        /Foreign Client preparation/);
      assert.throws(() => prepare.assertOwned({...preparedProgram}),
        /Foreign Client preparation/);

      const compiled = control.prepareCheckedClientCompiledRun(
        preparedProgram, kind, policy);
      control.checkClientCompiledRunOwner(compiled, preparedProgram);
      assert.throws(() => control.checkClientCompiledRunOwner(compiled,
        foreign), /Foreign Client compiled Run/);
      assert.throws(() => control.checkClientCompiledRunOwner({...compiled},
        preparedProgram), /Foreign Client compiled Run/);
      const otherControl = runtimeCore({...moon}).publicationControl;
      assert.throws(() => otherControl.checkClientCompiledRunOwner(compiled,
        preparedProgram), /Foreign Client compiled Run/);

      // Exercise the common MoonBit owner directly, not just a JS map guard.
      const compilation = checked(acquired
        ? moon.clientProgramCompileLocalTasks(preparedProgram)
        : moon.clientProgramCompileLocalValues(preparedProgram));
      const issue = acquired ? moon.clientProgramIssueTaskCompiledRun
        : moon.clientProgramIssueValuesCompiledRun;
      assert.throws(() => checked(issue(foreign, compilation,
        policy.executionContextCid, policy.hostPolicyCid, policy.expiresAt)));
      assert.doesNotThrow(() => checked(issue(preparedProgram, compilation,
        policy.executionContextCid, policy.hostPolicyCid, policy.expiresAt)));
    });
}
