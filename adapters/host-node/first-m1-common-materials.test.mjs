import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {readInstalledModelExecution, readInstalledModelDependencies} from './installed-model.mjs';
import {canonical, identity, program, input, output, prompt, task, execution,
  instructions, configuration} from '../../scripts/fixtures/first-m1-common-materials.mjs';

const base = JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url)));
const payloadWire = '{"format":"actql.openai_chat_prompt/0.1","instructions":"Original é\\r\\n"}';
function prepare() {
  const installation = configuration(base);
  const environment = moon.clientProgramCheckEnvironment(installation.environmentWire,
    JSON.parse(installation.environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment, 'The actual Common environment must admit the original Task');
  const prepared = installNodeClientProgramPreparation({moon, environment})({
    kind: 'program', input: program, parameters: null,
  });
  const selected = readInstalledModelExecution(moon, prepared, installation);
  assert.equal(selected.step, 2);
  return {installation, prepared, execution: selected.execution};
}
function provider(connector = 'models/fixture') {
  // Actual async registration has no invocation callback at all. The static
  // reader cannot dispatch; no physical port or Entry is installed here.
  const value = moon.clientProgramInstallAsyncModelProvider(connector);
  assert.ok(value);
  return {value};
}

test('first M1 originals retain the exact input and independently fixed canonical identities', () => {
  assert.equal(createHash('sha256').update(JSON.stringify(program)).digest('hex'),
    'd184b5e6e2744c54091263947055d0dc29d1a81071f3fe4fc7f671925ed8a116');
  assert.equal(identity(input), 'sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7');
  assert.equal(identity(output), 'sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3');
  assert.equal(identity(prompt), 'sha256:6510cda280e9beee95537f359641df15e566d5abf101c85bf3e6a77eba7b3240');
  assert.equal(identity(task), 'sha256:96ac9b2a06dae7a547aba6db6011d92bf6649a8832f65b1b986068b9561c8b31');
  assert.equal(identity(execution), 'sha256:b7feb240420f15786b76167ee8bba0b0ba699e3c1fdab575071d74433c4d1698');
  assert.equal(canonical(prompt.payload), payloadWire);
  assert.equal(instructions, 'Original e\u0301\r\n');
  assert.equal(task.max_items, 2);
  assert.deepEqual(task.generation_config,
    {max_output_tokens: 32, seed_requested: -7, temperature: 0, top_p: 1});
  assert.equal(execution.max_total_duration_ms, 500);
  assert.equal(execution.max_total_token_reservation, 33);
  // These fixture amounts and the unbound historical policy are not live fees.
  assert.equal(task.data_handling.allowed_regions[0], 'fixture-region');
});

test('first M1 actual Common admits the same Program Task prompt and asynchronous provider with invoke zero', () => {
  const selected = prepare();
  const dependencies = readInstalledModelDependencies(moon, selected.execution, selected.installation);
  const physical = provider();
  let validations = 0;
  const admitted = checked(moon.clientProgramAdmitModelProvider(physical.value,
    selected.execution, dependencies, (taskCid, selector, wire) => {
      validations++;
      assert.equal(taskCid, identity(task));
      assert.equal(selector, 'fixture-risk-model');
      assert.equal(wire, payloadWire);
      return true;
    }));
  assert.strictEqual(moon.clientProgramAdmittedModelProvider(admitted, selected.execution), physical.value);
  assert.equal(validations, 1);
});

test('first M1 actual dependency reader refuses missing and changed prompt originals before provider admission', () => {
  const selected = prepare();
  for (const change of ['missing', 'changed', 'extra']) {
    const installation = structuredClone(selected.installation);
    if (change === 'missing') installation.dependencyBodies.shift();
    else {
      const body = JSON.parse(installation.dependencyBodies[0].bodyWire);
      if (change === 'changed') body.payload.instructions = 'Original é\n';
      else body.payload.extra = true;
      installation.dependencyBodies[0].bodyWire = canonical(body);
    }
    assert.throws(() => readInstalledModelDependencies(moon, selected.execution, installation),
      error => error.code === 'MoonBitHostFailure' &&
        moon.clientProgramInferModelDependencyIssueKind(error.cause) ===
          (change === 'missing' ? 'missing_body' : 'identity_mismatch'));
  }
});

test('first M1 actual provider admission refuses foreign connector and rejected interpretation with invoke zero', () => {
  const selected = prepare();
  const dependencies = readInstalledModelDependencies(moon, selected.execution, selected.installation);
  for (const [connector, accept, expected] of [
    ['models/foreign', true, 'foreign_provider'],
    ['models/fixture', false, 'unsupported_prompt'],
  ]) {
    const physical = provider(connector);
    const result = moon.clientProgramAdmitModelProvider(physical.value, selected.execution,
      dependencies, () => accept);
    assert.equal(result.$tag, 0);
    assert.equal(moon.clientProgramModelProviderAdmissionIssueKind(result._0), expected);
  }
});

test('first M1 actual execution reader refuses foreign Task binding and changed self CID', () => {
  const selected = prepare();
  for (const change of ['foreign_task', 'changed_cid']) {
    const installation = structuredClone(selected.installation);
    const entry = installation.executionContracts[0];
    const body = JSON.parse(entry.bodyWire);
    if (change === 'foreign_task') {
      body.model_task_contract_cid = `sha256:${'b'.repeat(64)}`;
      const {self_cid: ignored, ...original} = body;
      void ignored;
      entry.cid = body.self_cid = identity(original);
    } else body.self_cid = `sha256:${'b'.repeat(64)}`;
    entry.bodyWire = canonical(body);
    assert.throws(() => readInstalledModelExecution(moon, selected.prepared, installation),
      error => error.code === 'MoonBitHostFailure' &&
        moon.clientProgramInferModelExecutionIssueKind(error.cause) ===
          (change === 'foreign_task' ? 'reference_mismatch' : 'identity_mismatch'));
  }
});

test('first M1 actual checker refuses a changed Task body under the original Task CID', () => {
  const installation = configuration(base);
  const document = JSON.parse(installation.environmentWire);
  document.model_task_contracts[0].generation_config.max_output_tokens = 31;
  const {evidence_bundle_cid: ignored, ...original} = document;
  void ignored;
  document.evidence_bundle_cid = identity(original);
  const environment = moon.clientProgramCheckEnvironment(canonical(document),
    document.evidence_bundle_cid, false, false, true, false, false, false, false);
  // The outer environment is well formed, but cannot turn a changed inner
  // Task under an old identity into a prepared Program or provider authority.
  if (environment !== undefined) {
    assert.throws(() => installNodeClientProgramPreparation({moon, environment})({
      kind: 'program', input: program, parameters: null,
    }));
  }
});
