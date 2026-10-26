import {checked} from '../host-common/runtime-result.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createNodeHostEntry} from './entry.mjs';
import {installStrategyContributions} from '../connectors-builtin/strategy.generated.mjs';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
function capturedValues() {
  const environment = moon.clientProgramCheckEnvironment(
    read('../../packages/sdk/fixtures/values.environment.json').trimEnd(),
    'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
    false, false, true, false, false, false, false,
  );
  assert.ok(environment);
  const prepared = moon.clientProgramPrepareEffectFree(
    read('../../packages/sdk/fixtures/values.json'), 'json', environment);
  assert.ok(prepared);
  const contract = JSON.parse(read('../../spec/contracts/actql-aoa.json'));
  const values = JSON.stringify(contract.execution_contracts['REL.values']);
  const installedContracts = checked(moon.clientPrepareInstalledSequenceContracts(
    read('../../spec/dependencies/aoa-pipeline-registry.json'), values, undefined, undefined));
  const setup = moon.clientProgramOpenSourceFreeLocalHost(prepared,
    installedContracts, values, 1n, 0n, 0n, 0n);
  assert.ok(setup);
  return setup;
}

test('public Node options cannot substitute internal composition or admission callbacks', async () => {
  let loads = 0, installs = 0;
  const poison = () => assert.fail('caller options replaced installed composition');
  const entry = createNodeHostEntry(async () => { loads++; return moon; }, async (...args) => {
    installs++;
    assert.equal(args[0], moon);
    return installStrategyContributions(...args);
  });
  const options = {
    runtime: poison, core: poison, loadRuntime: poison, install: poison,
    beforeCompute: poison, approve: poison, verify: poison,
    composition: {loadRuntime: poison, install: poison},
    publication: {beforeCompute: poison}, cleanup: {retainPreflightCleanup: poison},
  };
  const execution = await entry.runCapturedStrategy(capturedValues(), options);
  try {
    assert.equal(execution.status, 'host-tasks-completed');
    assert.deepEqual(execution.resultInventory.map(result => result.name), ['answer']);
    assert.equal(execution.completed[0].outputRows, 2);
    assert.equal(loads, 1);
    assert.equal(installs, 1);
  } finally {
    await execution.close();
    assert.equal(execution.cleanupPending(), false);
  }
});

test('aborted public Node entry does not load or install a replacement runtime', async () => {
  let loads = 0, installs = 0;
  const entry = createNodeHostEntry(async () => { loads++; return moon; }, async () => { installs++; });
  const controller = new AbortController();
  const reason = new Error('already cancelled');
  controller.abort(reason);
  await assert.rejects(entry.runCapturedStrategy({}, {}, controller.signal), error => error === reason);
  assert.deepEqual({loads, installs}, {loads: 0, installs: 0});
});

test('public Node entry rejects accessor configurations before loading runtime', async () => {
  let loads = 0;
  const entry = createNodeHostEntry(async () => { loads++; return moon; }, () => []);
  await assert.rejects(entry.runCapturedStrategy({}, {
    get composition() { assert.fail('accessor was evaluated'); },
  }), /Configuration handles must be data properties/);
  assert.equal(loads, 0);
});
