import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from './runtime-core.mjs';

const ok = value => ({$tag: 1, _0: value});

test('checked Infer dispatch retains its owner-issued admission', () => {
  const prepared = {};
  const graph = {};
  const execution = {};
  const definitionToken = {};
  const compiledToken = {};
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
    clientProgramCompiledRunTemplate: () => ({}),
    clientProgramCompiledRunPlan: () => ({}),
    clientProgramCompiledRunPrepared: () => ({}),
    clientProgramCompiledRunAuthorization: () => ({}),
    clientProgramCompiledRunAdmission: () => ({}),
    strategyPublicationAdmit: () => ok(definitionToken),
    strategyPublicationContractName: () => 'run_definition',
    strategyPublicationContractIdentityField: () => 'run_definition_cid',
    strategyPublicationContractIdentity: () => 'sha256:' + 'a'.repeat(64),
    strategyPublicationContractJson: () => '{}',
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
