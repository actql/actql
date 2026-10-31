import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {parse} from 'acorn';
import test from 'node:test';

test('historical holding controller forwards the original Site token and exact bytes', () => {
  const source = readFileSync(new URL('../adapters/host-common/runtime-core.mjs', import.meta.url), 'utf8');
  const declaration = parse(source, {sourceType: 'module', ecmaVersion: 'latest'}).body
    .find(value => value.type === 'FunctionDeclaration' && value.id.name === 'siteControl');
  assert(declaration);
  const site = Object.freeze({originalSite: true});
  const restoration = Object.freeze({originalRestoration: true});
  const holding = Object.freeze({originalHolding: true});
  const calls = [];
  const moon = {
    strategySitePrepareHoldingRestoration(actualSite, bytes) {
      calls.push(['prepare', actualSite, bytes]); return restoration;
    },
    strategySiteAcquireRestoredHolding(actualRestoration) {
      calls.push(['acquire', actualRestoration]); return holding;
    },
    strategySiteRetainHolding() { assert.fail('Normal retention cannot restore historical debt'); },
  };
  const factory = runInNewContext(`(${source.slice(declaration.start, declaration.end)})`, {
    siteControls: new WeakMap(),
  });
  const control = factory(moon);
  assert.equal(factory(moon), control);
  assert.equal(control.prepareHoldingRestoration(site, 31n), restoration);
  assert.equal(control.acquireRestoredHolding(restoration), holding);
  assert.deepEqual(calls, [['prepare', site, 31n], ['acquire', restoration]]);
});

test('failed partial controller forwards the same original physical tuple without creating another custody', () => {
  const source = readFileSync(new URL('../adapters/host-common/runtime-core.mjs', import.meta.url), 'utf8');
  const declaration = parse(source, {sourceType: 'module', ecmaVersion: 'latest'}).body
    .find(value => value.type === 'FunctionDeclaration' && value.id.name === 'remoteSiteControl');
  assert(declaration);
  const original = Object.freeze({record: Object.freeze({originalRecord: true}),
    revision: 7, requestCid: 'original-source-request', sourceWire: 'original-source-metadata',
    material: 'original-material-generation', measurementCid: 'original-measurement-cid',
    measurement: Object.freeze({originalMeasurement: true}),
    owner: 'original-worker-owner', generation: 'original-worker-generation'});
  const args = [original.record, original.revision, original.requestCid, original.sourceWire,
    original.material, original.measurementCid, original.measurement, original.owner,
    original.generation, original.requestCid, original.material, original.owner, original.generation];
  const result = Object.freeze({originalResult: true}), custody = Object.freeze({originalCustody: true});
  let calls = 0, fresh = 0;
  const moon = {strategyRemoteRuntimeCustodyCreate() {fresh++;},
    strategyRemoteManagedOutputEvidenceKind: () => 'actql.remote.managed-output/0.1',
    strategyRemoteRuntimeRestoreFailedPartialCustody(...actual) {
      assert.equal(this, moon); assert.deepEqual(actual, args); calls++; return result;
    }};
  const control = runInNewContext(`(${source.slice(declaration.start, declaration.end)})`, {
    remoteSiteControls: new WeakMap(), checked(value) {assert.equal(value, result); return custody;},
  })(moon);
  assert.equal(control.restoreFailedPartialRuntimeCustody(...args), custody);
  assert.equal(calls, 1); assert.equal(fresh, 0);
  const failure = Object.freeze({originalFailure: true});
  moon.strategyRemoteRuntimeRestoreFailedPartialCustody = () => {throw failure;};
  assert.throws(() => control.restoreFailedPartialRuntimeCustody(...args), error => error === failure);
});

const sources = [
  'scripts/templates/strategy-node.mbt',
  'src/connectors_builtin_node/bridge.generated.mbt',
  'src/connectors_builtin_node_rela/bridge.generated.mbt',
  'src/connectors_workers_bridge/bridge.generated.mbt',
  'src/connectors_workers_async_bridge/bridge.generated.mbt',
];

test('completed cleanup controller retains the exact original completion tuple and existing cleanup planner', () => {
  const source = readFileSync(new URL('../adapters/host-common/runtime-core.mjs', import.meta.url), 'utf8');
  const declaration = parse(source, {sourceType: 'module', ecmaVersion: 'latest'}).body
    .find(value => value.type === 'FunctionDeclaration' && value.id.name === 'remoteSiteControl');
  assert(declaration);
  const record = Object.freeze({}), evidence = Object.freeze({}), subject = Object.freeze({}), measurement = Object.freeze({});
  const result = Object.freeze({}), custody = Object.freeze({}), step = Object.freeze({}), calls = [];
  const moon = {strategyRemoteManagedOutputEvidenceKind: () => 'actql.remote.managed-output/0.1',
    strategyRemoteRuntimeCustodyCreate() {assert.fail('A fresh custody cannot replace the original completion');},
    strategyRemoteRuntimeRestoreCompletedCleanupCustody(...args) {
      assert.equal(this, moon);assert.deepEqual(args, [record,evidence,subject,measurement]);calls.push('restore');return result;
    },strategyRemoteRuntimeOwnedCleanupPlan(...args) {
      assert.equal(this,moon);assert.deepEqual(args,[record,custody]);calls.push('plan');return step;
    }};
  const control = runInNewContext(`(${source.slice(declaration.start, declaration.end)})`, {
    remoteSiteControls:new WeakMap(), checked(value) {return value===result?custody:value;},
  })(moon);
  assert.equal(control.restoreCompletedCleanupRuntimeCustody(record,evidence,subject,measurement),custody);
  assert.equal(control.prepareOwnedRuntimeCleanup(record,custody),step);
  assert.deepEqual(calls,['restore','plan']);
  const failure=Object.freeze({originalFailure:true});
  moon.strategyRemoteRuntimeRestoreCompletedCleanupCustody=()=>{throw failure;};
  assert.throws(()=>control.restoreCompletedCleanupRuntimeCustody(record,evidence,subject,measurement),cause=>cause===failure);
});

for (const path of sources) {
  const source = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  const declaration = name => {
    const block = source.split('///|').find(value =>
      value.includes(`pub fn ${name}(`));
    assert.ok(block, `Missing ${name} in ${path}`);
    return block;
  };

  test(`${path}: completion includes the checked source-free root`, () => {
    const body = declaration('strategy_host_finished');
    assert.match(body, /let first = @strategy\.captured_compute_first_task\(run\)/);
    assert.match(body, /for task in first\.\.<strategy_host_count\(host\)/);
  });

  test(`${path}: cleanup closes all Compute outputs and preserves captures`, () => {
    const body = declaration('strategy_host_close_outputs');
    assert.match(body, /let first = @strategy\.captured_compute_first_task\(run\)/);
    assert.match(body,
      /for task = strategy_host_count\(host\) - 1; task >= first; task = task - 1/);
    assert.match(body, /@strategy\.close_captured_task_output\(run, task\)/);
  });
}
