import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
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
import {admitEnvironment as admitStandaloneEnvironment,
  prepare as prepareStandalone, compileValues as compileStandaloneValues,
  compileTasks as compileStandaloneTasks, compiledPlanCid,
  privateTaskCompilationWires} from '../../packages/run-host-core/index.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const hash = body => `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`;
// Compatibility snapshots from the standalone compiler under this checkout's
// pins (the Check Environment contract pin included).
// These supplement,
// not replace, the independent logical-plan vectors in run-host-core tests.
const planCids = {
  values: 'sha256:41a2171a7444034d81ab545ac20bd21f7806c821ab077565b8ec7e0ab8228c81',
  tasks: 'sha256:a9a4fabb9455df6f32a226c69e36650f82f6c971c8852c6bbd46d8d6136d6905',
};
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
      // The separate runtime is test-only. Both compilers use this checkout's
      // Frontend pins, so this comparison isolates the owner consolidation.
      const standaloneEnvironment = admitStandaloneEnvironment(
        canonicalText(JSON.parse(environmentWire)),
        JSON.parse(environmentWire).evidence_bundle_cid, {rela: true});
      const standalonePrepared = prepareStandalone(document, 'json',
        standaloneEnvironment, parameters === null
          ? undefined : canonicalText(parameters));
      const standaloneCompilation = acquired
        ? compileStandaloneTasks(standalonePrepared)
        : compileStandaloneValues(standalonePrepared);
      const standalonePlanCid = acquired
        ? JSON.parse(privateTaskCompilationWires(standaloneCompilation)
          .compiledPlan).compiled_plan_cid
        : compiledPlanCid(standaloneCompilation);
      assert.equal(compiled.compiledPlan.identity, standalonePlanCid);
      const grammar = JSON.parse(await read(
        '../../spec/manifests/actql-grammar-0.1.json'));
      const barriers = JSON.parse(await read(
        '../../spec/manifests/actql-barrier-contracts-0.1.json'));
      // Assemble the expected envelope from fixture inputs and pinned
      // manifests, not by removing the self CID from the issued envelope.
      const templateBody = {
        version: 'actql-bound-invocation-template/0.1',
        program_definition_cid: moon.clientProgramDefinitionCid(preparedProgram),
        parameter_values_cid: hash({version: 'actql-parameter-values/0.1',
          values: parameters ?? {}}),
        invocation_bindings_cid: hash({
          version: 'actql-invocation-bindings/0.1', bindings: {}}),
        check_environment_cid: JSON.parse(environmentWire).evidence_bundle_cid,
        grammar_manifest_cid: grammar.grammar_manifest_cid,
        barrier_contract_manifest_cid: barriers.barrier_contract_manifest_cid,
        required_profile_contracts: [], source_evidence: 'unbound',
      };
      assert.deepEqual(JSON.parse(compiled.template.wire), {...templateBody,
        bound_invocation_template_cid: hash(templateBody)});
      assert.equal(compiled.compiledPlan.identity, planCids[kind]);
      const definitionBody = {
        version: 'actql-run-definition/0.1',
        authorization_context_cid: policy.executionContextCid,
        compiled_plan_cid: planCids[kind],
        invocation_template_cid: hash(templateBody),
        input_artifact_set_cid: hash({
          version: 'actql-initial-input-artifact-set/0.1',
          captured_artifact_cids: []}),
        scope_id: 'local', run_id: `fixed-${kind}-run`,
        created_at: '2026-09-27T00:00:00.000Z',
        valid_until: policy.expiresAt,
      };
      const definition = control.defineCheckedClientCompiledRun(compiled, {
        tenantId: definitionBody.scope_id, runId: definitionBody.run_id,
        createdAt: definitionBody.created_at,
        validUntil: definitionBody.valid_until,
      });
      assert.deepEqual(JSON.parse(definition.wire), {...definitionBody,
        run_definition_cid: hash(definitionBody)});
      const restore = wire => control.defineCheckedClientCompiledRun(compiled,
        {retainedDefinitionWire: wire});
      assert.equal(restore(definition.wire).identity, definition.identity);
      const substituted = {...definitionBody, compiled_plan_cid: cid('0')};
      assert.throws(() => restore(canonicalText({...substituted,
        run_definition_cid: hash(substituted)})));
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
