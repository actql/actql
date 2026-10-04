import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from './runtime-core.mjs';

const ok = value => ({$tag: 1, _0: value});

test('checked Infer dispatch retains its owner-issued admission', () => {
  const prepared = {};
  const graph = {};
  const execution = {};
  const definitionToken = {};
  const otherDefinitionToken = {};
  const compiledToken = {};
  const templateToken = {};
  const planToken = {};
  const preparedToken = {};
  const authorizationToken = {};
  const admission = {};
  const account = {};
  const delegated = {};
  const observeAccount = () => account;
  const observeAt = () => 'now';
  const calls = [];
  const overrides = {
    clientProgramCompileLocalInfer(actualPrepared, actualGraph) {
      assert.equal(actualPrepared, prepared);
      assert.equal(actualGraph, graph);
      return ok({});
    },
    clientProgramIssueTaskCompiledRun: () => ok(compiledToken),
    clientProgramCompiledRunTemplate: () => templateToken,
    clientProgramCompiledRunPlan: () => planToken,
    clientProgramCompiledRunPrepared: () => preparedToken,
    clientProgramCompiledRunAuthorization: () => authorizationToken,
    clientProgramCompiledRunAdmission: () => ({}),
    strategyPublicationAdmit: (_name, wire) => ok(wire === 'other definition'
      ? otherDefinitionToken : definitionToken),
    strategyPublicationContractName: () => 'run_definition',
    strategyPublicationContractIdentityField: () => 'run_definition_cid',
    strategyPublicationContractIdentity: () => 'sha256:' + 'a'.repeat(64),
    strategyPublicationContractJson: value => value === planToken
      ? 'compiled plan' : 'run definition',
    strategyRunEvidenceJson: value => value === templateToken
      ? 'bound template' : value === preparedToken
        ? 'prepared invocation' : 'run authorization',
    clientProgramCheckCompiledRunDefinition: (compiled, definition) =>
      compiled === compiledToken && definition === definitionToken,
    clientProgramIssueInferDispatchAdmission(...args) {
      assert.deepEqual(args, [compiledToken, definitionToken, account,
        'principal', 'now', delegated, observeAccount, observeAt]);
      calls.push('issue');
      return ok(admission);
    },
    clientProgramBindInferDispatchAdmission(actualExecution, actualAdmission) {
      assert.equal(actualExecution, execution);
      assert.equal(actualAdmission, admission);
      calls.push('bind');
      return ok(undefined);
    },
  };
  const moon = new Proxy(overrides, {get(target, name) {
    return target[name] ?? (() => 0);
  }});
  const control = runtimeCore(moon).publicationControl;
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', {
    executionContextCid: 'context', hostPolicyCid: 'policy', expiresAt: 'later',
  }, graph);
  const definition = control.admit('run_definition', '{}', {
    maxWireBytes: 128, maxNodes: 8, maxDepth: 4,
  });
  assert.deepEqual(JSON.parse(control.compiledInferOriginalRunWire(compiled,
    definition)), {
    boundInvocationTemplateWire: 'bound template',
    compiledPlanWire: 'compiled plan',
    preparedInvocationWire: 'prepared invocation',
    runAuthorizationWire: 'run authorization',
    runDefinitionWire: 'run definition',
  });
  assert.throws(() => control.compiledInferOriginalRunWire({}, definition),
    /Foreign Client compiled Infer Run/u);
  assert.throws(() => control.compiledInferOriginalRunWire(compiled, {}),
    /Foreign publication contract/u);
  const otherDefinition = control.admit('run_definition', 'other definition', {
    maxWireBytes: 128, maxNodes: 8, maxDepth: 4,
  });
  assert.throws(() => control.compiledInferOriginalRunWire(compiled,
    otherDefinition), /Foreign Client compiled Infer Run/u);
  const observation = {account, principalId: 'principal', at: 'now', delegated,
    observeAccount, observeAt};
  const returned = control.issueCheckedClientInferDispatch(compiled,
    definition, observation);
  assert.equal(returned, admission);
  assert.deepEqual(calls, ['issue']);
  assert.equal(control.bindCheckedClientInferDispatch(compiled, execution,
    definition, observation), undefined);
  assert.deepEqual(calls, ['issue', 'issue', 'bind']);
  assert.throws(() => control.issueCheckedClientInferDispatch({}, definition,
    observation), {name: 'TypeError'});
  assert.deepEqual(calls, ['issue', 'issue', 'bind']);
});
