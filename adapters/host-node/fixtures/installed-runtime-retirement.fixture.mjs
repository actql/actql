// Actual Host/Common/SQLite/Store when reached. Only the explicit cleanup
// fault and startup-association counter are doubles, never capability proofs.
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {mock} from 'node:test';
import {createOwnedScratch} from '../../../scripts/owned-scratch.mjs';
import * as actual from '../infer-trusted-runtime-view.mjs';

const mode = process.argv[2];
assert(['frozen-primary', 'readonly-handle', 'partial-finalization'].includes(mode));
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-a-runtime-retirement-',
  label: 'installed Host runtime retirement counter'});
const originals = [];
const counts = {registration: 0, startupRetire: 0, runtimeRetire: 0, childRetry: 0};
let childPending = true, blockRuntime = mode === 'partial-finalization';
let startupRetired = false, pendingFailure, host, outcome;
let observedFailure;
const startup = {};
const primary = Object.assign(new Error('OriginalInstallationFailure'), {code: 'OriginalInstallationFailure'});
const closeFault = Object.assign(new Error('OriginalRuntimeRetirementFailure'), {code: 'OriginalRuntimeRetirementFailure'});
const child = Object.freeze({status: () => ({pending: childPending}), async retry() {
  counts.childRetry++;
  return this.status();
}});
Object.defineProperties(primary, {
  cleanupPending: {value: true, enumerable: true},
  cleanupHandle: {value: child, enumerable: true},
});
if (mode === 'frozen-primary') Object.freeze(primary);
const modelView = mock.module(new URL('../infer-trusted-runtime-view.mjs', import.meta.url), {namedExports: {
  ...actual,
  issueInferTrustedRuntimeView(original) {
    const view = actual.issueInferTrustedRuntimeView(original);
    originals.push({view, original});
    return view;
  },
  associateInferTrustedStartupView(view, original) {
    if (mode !== 'partial-finalization') return actual.associateInferTrustedStartupView(view, original);
    assert.equal(originals[0].view, view);
    // Fault-double association: no selected physical startup or native grant.
    return startup;
  },
  requireInferTrustedStartupView(view, original) {
    if (view !== startup) return actual.requireInferTrustedStartupView(view, original);
    assert.equal(startupRetired, false);
    assert.equal(original.host, originals[0].original.host);
  },
  forgetInferTrustedStartupView(view, owner, generation) {
    if (view !== startup) return actual.forgetInferTrustedStartupView(view, owner, generation);
    assert.equal(startupRetired, false, 'the same retired association is not forgotten twice');
    assert.equal(owner, originals[0].original.host);
    assert.equal(generation, originals[0].original.generation);
    startupRetired = true;
    counts.startupRetire++;
  },
  forgetInferTrustedRuntimeView(view, owner, generation) {
    counts.runtimeRetire++;
    if (blockRuntime) throw closeFault;
    return actual.forgetInferTrustedRuntimeView(view, owner, generation);
  },
}});
try {
  const {openInstalledRemoteHttpHost} = await import('../embedded-local.mjs');
  const options = {directory: join(scratch.path, 'host'), authenticate: () => 'fixture-owner',
    registerModelProviders() {
      counts.registration++;
      if (mode !== 'partial-finalization') throw primary;
      return [];
    }};
  if (mode !== 'partial-finalization') {
    await assert.rejects(openInstalledRemoteHttpHost(options), error => {
      pendingFailure = error;
      observedFailure = {name: error.name, code: error.code ?? null, message: error.message,
        samePrimary: error.primaryFailure === primary, pending: error.cleanupPending ?? null,
        hasHandle: typeof error.cleanupHandle?.retry === 'function', counts: {...counts}};
      console.error(JSON.stringify({mode, observedFailure}));
      assert.equal(error.primaryFailure, primary);
      assert.equal(error.code, primary.code);
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle.status().pending, true);
      return true;
    });
    assert.equal(primary.cleanupHandle, child);
    assert.equal(counts.childRetry, 0, 'wrapping the failure does not retry its physical work');
    assert.equal(counts.runtimeRetire, 0);
    const originalHandle = pendingFailure.cleanupHandle;
    const first = originalHandle.retry(), concurrent = originalHandle.retry();
    assert.equal(first, concurrent, 'one outstanding cleanup operation belongs to the same failure');
    await first;
    assert.equal(counts.childRetry, 1);
    assert.equal(originalHandle.status().pending, true);
    assert.equal(counts.runtimeRetire, 0);
    childPending = false;
    assert.equal((await originalHandle.retry()).pending, false);
    assert.equal(counts.runtimeRetire, originals.length);
    assert.equal(pendingFailure.cleanupPending, false);
    await originalHandle.retry();
    assert.equal(counts.runtimeRetire, originals.length);
    assert.equal(counts.registration, 1, 'cleanup never reopens registration or the Host');
  } else {
    host = await openInstalledRemoteHttpHost(options);
    assert.equal(originals.length, 1, 'this focused counter uses the selected runtime-view branch');
    await assert.rejects(host.close(), error => {
      pendingFailure = error;
      observedFailure = {name: error.name, code: error.code ?? null, message: error.message,
        samePrimary: error.primaryFailure === closeFault, pending: error.cleanupPending ?? null,
        hasHandle: typeof error.cleanupHandle?.retry === 'function', counts: {...counts}};
      console.error(JSON.stringify({mode, observedFailure}));
      assert.equal(error.primaryFailure, closeFault);
      assert.equal(error.cleanupPending, true);
      assert.ok(error.cleanupHandle.status().pending.includes('finalize'));
      return true;
    });
    assert.equal(counts.startupRetire, 1);
    assert.equal(counts.runtimeRetire, 1);
    blockRuntime = false;
    await pendingFailure.cleanupHandle.retry();
    await host.close();
    assert.equal(counts.startupRetire, 1);
    assert.equal(counts.runtimeRetire, 2);
    assert.equal(pendingFailure.cleanupHandle.status().pending.length, 0);
    host = undefined;
  }
  outcome = {mode, checked: true, counts, scratch: scratch.path,
    providerCalls: 0, commonScopes: 0, publicE2E: 0,
    qualification: 'Actual Host caller and existing runtime-view Owner; startup association and failed cleanup ports are explicit fault doubles.'};
  scratch.passed();
  console.log(JSON.stringify(outcome));
} finally {
  childPending = false;
  blockRuntime = false;
  // Close only this fresh fixture's original duties, even on a red assertion.
  // This teardown does not turn that failed product assertion into a pass.
  try { await pendingFailure?.cleanupHandle?.retry(); } catch {}
  try { await host?.close(); } catch {}
  for (const {view, original} of originals) {
    try { actual.forgetInferTrustedRuntimeView(view, original.host, original.generation); }
    catch (error) { if (error.code !== 'InferTrustedRuntimeViewRetired') throw error; }
  }
  modelView.restore();
  await writeFile(join(scratch.path, 'counter.json'), JSON.stringify({mode, counts, observedFailure,
    checked: outcome?.checked ?? false, scratch: scratch.path,
    qualification: 'Original red/green counter state; not a physical startup, scope funding or Model send proof.'}, null, 2) + '\n', {flag: 'wx'});
}
