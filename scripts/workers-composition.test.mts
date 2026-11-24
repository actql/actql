import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {siteControl} from '../adapters/host-common/site-control.mjs';
import {remoteSiteControl} from '../adapters/host-common/remote-site-control.mjs';

type SiteBindings = Parameters<typeof siteControl>[0];
type SiteControls = ReturnType<typeof siteControl>;
type RemoteBindings = Parameters<typeof remoteSiteControl>[0];
type RemoteControls = ReturnType<typeof remoteSiteControl>;
const ok = (value: object) => Object.freeze({$tag: 1, _0: value});

test('historical holding controller forwards the original Site token and exact bytes', () => {
  const site = Object.freeze({originalSite: true}) as unknown as
    Parameters<SiteControls['prepareHoldingRestoration']>[0];
  const restoration = Object.freeze({originalRestoration: true}) as unknown as
    Parameters<SiteControls['acquireRestoredHolding']>[0];
  const holding = Object.freeze({originalHolding: true}) as unknown as
    ReturnType<SiteControls['acquireRestoredHolding']>;
  const calls: unknown[][] = [];
  const moon = {
    strategySitePrepareHoldingRestoration(actualSite, bytes) {
      calls.push(['prepare', actualSite, bytes]); return restoration;
    },
    strategySiteAcquireRestoredHolding(actualRestoration) {
      calls.push(['acquire', actualRestoration]); return holding;
    },
    strategySiteRetainHolding() { assert.fail('Normal retention cannot restore historical debt'); },
  } satisfies Pick<SiteBindings, 'strategySitePrepareHoldingRestoration' |
    'strategySiteAcquireRestoredHolding' | 'strategySiteRetainHolding'>;
  // This fixture supplies the concrete restoration ports on its own runtime.
  const fixtureRuntime = moon as unknown as SiteBindings;
  const control = siteControl(fixtureRuntime);
  assert.equal(siteControl(fixtureRuntime), control);
  assert.equal(control.prepareHoldingRestoration(site, 31n), restoration);
  assert.equal(control.acquireRestoredHolding(restoration), holding);
  assert.deepEqual(calls, [['prepare', site, 31n], ['acquire', restoration]]);
});

test('failed partial controller forwards the same original physical tuple without creating another custody', () => {
  const original = Object.freeze({record: Object.freeze({originalRecord: true}),
    revision: 7, requestCid: 'original-source-request', sourceWire: 'original-source-metadata',
    material: 'original-material-generation', measurementCid: 'original-measurement-cid',
    measurement: Object.freeze({originalMeasurement: true}),
    owner: 'original-worker-owner', generation: 'original-worker-generation'});
  const args: Parameters<RemoteControls['restoreFailedPartialRuntimeCustody']> = [
    original.record, original.revision, original.requestCid, original.sourceWire,
    original.material, original.measurementCid, original.measurement, original.owner,
    original.generation, original.requestCid, original.material, original.owner, original.generation];
  const custody = Object.freeze({originalCustody: true}), result = ok(custody);
  let calls = 0, fresh = 0;
  const moon: Pick<RemoteBindings, 'strategyRemoteRuntimeCustodyCreate' |
    'strategyRemoteManagedOutputEvidenceKind' | 'strategyRemoteRuntimeRestoreFailedPartialCustody'> = {
    strategyRemoteRuntimeCustodyCreate() {fresh++;},
    strategyRemoteManagedOutputEvidenceKind: () => 'actql.remote.managed-output/0.1',
    strategyRemoteRuntimeRestoreFailedPartialCustody(...actual) {
      assert.equal(this, moon); assert.deepEqual(actual, args); calls++; return result;
    },
  };
  const control = remoteSiteControl(moon as unknown as RemoteBindings);
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
  const record = Object.freeze({}), evidence = Object.freeze({}), subject = Object.freeze({}), measurement = Object.freeze({});
  const custody = Object.freeze({}), result = ok(custody), step = Object.freeze({}), calls: string[] = [];
  const moon: Pick<RemoteBindings, 'strategyRemoteManagedOutputEvidenceKind' |
    'strategyRemoteRuntimeCustodyCreate' | 'strategyRemoteRuntimeRestoreCompletedCleanupCustody' |
    'strategyRemoteRuntimeOwnedCleanupPlan'> = {
    strategyRemoteManagedOutputEvidenceKind: () => 'actql.remote.managed-output/0.1',
    strategyRemoteRuntimeCustodyCreate() {assert.fail('A fresh custody cannot replace the original completion');},
    strategyRemoteRuntimeRestoreCompletedCleanupCustody(...args) {
      assert.equal(this, moon); assert.deepEqual(args, [record,evidence,subject,measurement]); calls.push('restore'); return result;
    },
    strategyRemoteRuntimeOwnedCleanupPlan(...args) {
      assert.equal(this, moon); assert.deepEqual(args, [record,custody]); calls.push('plan'); return ok(step);
    },
  };
  const control = remoteSiteControl(moon as unknown as RemoteBindings);
  assert.equal(control.restoreCompletedCleanupRuntimeCustody(record,evidence,subject,measurement),custody);
  assert.equal(control.prepareOwnedRuntimeCleanup(record,custody),step);
  assert.deepEqual(calls,['restore','plan']);
  const failure = Object.freeze({originalFailure:true});
  moon.strategyRemoteRuntimeRestoreCompletedCleanupCustody=()=>{throw failure;};
  assert.throws(()=>control.restoreCompletedCleanupRuntimeCustody(record,evidence,subject,measurement),cause=>cause===failure);
});

for (const path of sources) {
  const source = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  const declaration = (name: string) => {
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
