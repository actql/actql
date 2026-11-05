// The only test port observes a real registered Local material and opens an
// additional real scoped read. No cleanup result, lock, or release is mocked.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {tmpdir} from 'node:os';
import {promisify} from 'node:util';
import {mock} from 'node:test';
import {createOwnedScratch} from '../../../scripts/owned-scratch.mjs';
import * as memory from '../../../packages/local-node/adapters/store-local/managed-memory-representations.mjs';

const exec = promisify(execFile);
const entry = new URL('../../../packages/node/index.mjs', import.meta.url).href;
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-values-contention-',
  label: 'original Values pending cleanup contention'});
let releaseRead, readEntered;
const blocked = new Promise(resolve => {releaseRead = resolve;});
const entered = new Promise(resolve => {readEntered = resolve;});
let heldRead, owner, registrationCount = 0, readRows = 0;
const registration = mock.module(new URL(
  '../../../packages/local-node/adapters/store-local/managed-memory-representations.mjs', import.meta.url), {
  namedExports: {...memory, registerManagedMemoryInput(...args) {
    const original = memory.registerManagedMemoryInput(...args);
    registrationCount++;
    assert.equal(owner, undefined, 'only the original finite output is registered');
    owner = original;
    heldRead = memory.withManagedOutputRows(args[0], async () => {
      readRows++;
      if (readRows === 1) {readEntered(); await blocked;}
    }, undefined, () => undefined);
    heldRead.catch(() => {});
    return original;
  }},
});
let client, closing, closed = false;
try {
  const {open} = await import(entry);
  client = await open({stateDir: scratch.path, installation: {valuesMaxRows: 2000}});
  const rows = Array.from({length: 500}, (_, id) => ({id}));
  const run = await client.start({version: 'actql/0.1', id: 'pending-output-contention',
    stages: [{id: 'main', inputs: {}, steps: [{values: {
      schema: {id: {type: 'number', nullable: false}}, rows}, as: 'v'}],
      results: {rows: {from: 'v', fields: ['id']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}});
  await entered;
  assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
  assert.deepEqual(await run.result('answer').all(), rows);
  assert.equal(owner.status().readers, 1, 'the original physical read is still pinned');
  closing = client.close();
  closing.then(() => {closed = true;}, () => {});
  assert.equal(client.close(), closing, 'concurrent close shares the original owner');
  // The independent process loads no test port. Busy must come from actual
  // publication-store exclusion while this original read has not retired.
  const busy = await exec(process.execPath, ['--input-type=module', '--eval', `
    import assert from 'node:assert/strict';
    import {open} from ${JSON.stringify(entry)};
    let reopened;
    try {
      await assert.rejects(async () => {reopened = await open({stateDir: process.env.CLEANUP_STATE, installation: {valuesMaxRows: 2000}});},
        error => error.code === 'PublicationStoreBusy');
      console.log('PublicationStoreBusy');
    } finally {await reopened?.close();}
  `], {env: {...process.env, CLEANUP_STATE: scratch.path}, timeout: 15000});
  assert.equal(busy.stdout.trim(), 'PublicationStoreBusy');
  assert.equal(closed, false, 'terminal success is not physical release');
  assert.equal(owner.status().readers, 1);
  assert.equal(owner.status().released, false);
  assert.equal(owner.status().releaseRequested, true, 'the original close is awaiting its real reader');
  assert.equal(owner.status().releaseAttempted, false, 'active use prevents physical retirement');
  releaseRead();
  // The last real reader may complete retirement, or expose the same original
  // finite-scratch cleanup child. No failure is injected here: require actual
  // release on success, and authenticate any failure against this exact owner.
  // The Host owns retry; this observer never acknowledges or replaces it.
  const readFailure = await heldRead.then(() => undefined, error => error);
  let originalCleanup;
  if (readFailure !== undefined) {
    assert.equal(readFailure.code, 'ManagedInputReleaseFailed');
    assert.equal(memory.managedMemoryReleaseFailureMatches(owner, readFailure), true);
    originalCleanup = readFailure.cleanupHandle;
    assert.equal(typeof originalCleanup?.retry, 'function');
  } else {
    assert.equal(owner.status().releaseAttempted, true);
    assert.equal(owner.status().released, true);
  }
  await closing;
  if (originalCleanup !== undefined) assert.equal(originalCleanup.status().pending, false);
  await client.close();
  assert.equal(owner.status().readers, 0);
  assert.equal(owner.status().released, true);
  assert.equal(readRows, rows.length);
  assert.equal(registrationCount, 1, 'cleanup does not repeat Compute');
  const reopened = await exec(process.execPath, ['--input-type=module', '--eval', `
    import assert from 'node:assert/strict';
    import {open} from ${JSON.stringify(entry)};
    const client = await open({stateDir: process.env.CLEANUP_STATE, installation: {valuesMaxRows: 2000}});
    try {
      const ref = JSON.parse(process.env.CLEANUP_REF), run = await client.attach(ref);
      assert.deepEqual(run.ref, ref);
      assert.deepEqual(await run.result('answer').all(),
        Array.from({length: 500}, (_, id) => ({id})));
      console.log('same-original-run:500');
    } finally {await client.close();}
  `], {env: {...process.env, CLEANUP_STATE: scratch.path,
    CLEANUP_REF: JSON.stringify(run.ref)}, timeout: 15000});
  assert.equal(reopened.stdout.trim(), 'same-original-run:500');
  console.log(JSON.stringify({pendingRead: true, busy: true, originalReleased: true,
    reopenedOriginalRows: 500, registrations: registrationCount}));
  scratch.passed();
} finally {
  releaseRead();
  await heldRead?.catch(() => {});
  await closing?.catch(() => {});
  await client?.close().catch(() => {});
  registration.restore();
}
