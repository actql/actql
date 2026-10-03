import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, open, readFile, readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {nodeTestArguments} from './test-execution.mjs';
import * as moon from '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../adapters/store-local/publication-store.mjs';
import {recoverCompletedEffectfulComputation, retireCompletedEffectfulCapture,
  releaseCompletedRunPreparedPayloads}
  from '../adapters/host-common/completed-run-publication.mjs';

const scratch = new URL('../_build/effect-capture-crash/', import.meta.url);
await mkdir(scratch, {recursive: true});
const root = await mkdtemp(join(scratch.pathname, 'run-'));
const boundary = process.argv[2] ?? 'effect-capture';
const savedPath = join(root, 'capture.json');
const child = spawnSync(process.execPath, nodeTestArguments([
  '--experimental-test-module-mocks', '--import',
  new URL('./fixtures/effect-capture-crash-preload.mjs', import.meta.url).href,
  '--test', '--test-name-pattern',
  '^one acquired Effect Program captures and computes from its owner$',
  'adapters/host-node/client-program-bridge.test.mjs',
]), {cwd: new URL('../', import.meta.url), encoding: 'utf8', timeout: 120_000,
  env: {...process.env, ACTQL_TEST_CAPTURE_CRASH_RECORD: savedPath,
    ACTQL_TEST_CAPTURE_CRASH_BOUNDARY: boundary}});
// Node's test runner maps the killed test worker's exit to its own failure.
assert.notEqual(child.status, 0, 'the process must stop before normal cleanup');
assert.match(child.stdout + child.stderr, /77/, 'verify the intentional stop');
const saved = JSON.parse(await readFile(savedPath, 'utf8'));
assert.equal(saved.boundary, boundary, 'the selected Store boundary must be captured');
assert.equal(saved.holding.namespace, boundary,
  'the captured holding must belong to the selected Store boundary');
saved.configuration.privateEvidenceKey = Buffer.from(
  saved.configuration.privateEvidenceKey.data);
const control = runtimeCore(moon).publicationControl;
let failObjectSync = false;
const store = await openLocalPublicationStore(saved.configuration, control, {
  async syncDirectory(path) {
    if (failObjectSync && path === join(saved.configuration.directory, 'objects')) {
      failObjectSync = false;
      throw Object.assign(new Error('injected retirement directory sync'), {code: 'EIO'});
    }
    const directory = await open(path, 'r');
    try { await directory.sync(); } finally { await directory.close(); }
  },
});
const options = {store, control, runDefinition: saved.runDefinition,
  contractLimits: saved.contractLimits};
const observed = {boundary};
try {
  const sharedCid = `sha256:${createHash('sha256').update('unrelated holding').digest('hex')}`;
  // Another owner uses the same physical payload. Capture cleanup may not
  // delete that allocation merely because its own inventory is incomplete.
  const shared = {...saved.holding, holding_cid: sharedCid};
  await store.sharePhysicalHolding(saved.holding.holding_cid, shared);
  try {
    const recovered = await recoverCompletedEffectfulComputation(options);
    observed.recovery = 'completed';
    // Recovery acquires real prepared owners. Release them before testing
    // durable retirement; leaving this custody open would be a harness leak.
    await releaseCompletedRunPreparedPayloads(recovered.storedResults, control);
  }
  catch (error) { observed.recovery = error.code ?? error.message; }
  try { observed.retired = await retireCompletedEffectfulCapture(options); }
  catch (error) { observed.retirementError = error.code ?? error.message; }
  assert.deepEqual(await store.inspectPhysicalHolding(sharedCid), shared,
    'unrelated holding and shared payload must remain valid');
  // The last owner exercises the real deletion retry, not a fake close.
  failObjectSync = true;
  const deletion = await store.retirePhysicalHolding(sharedCid);
  assert.equal(deletion.cleanup.status().pending, true);
  await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
  await deletion.cleanup.retry();
  assert.equal(deletion.cleanup.status().pending, false);
  observed.holdings = (await readdir(join(saved.configuration.directory,
    'physical-holdings'))).length;
  observed.objects = (await readdir(join(saved.configuration.directory, 'objects'))).length;
  console.log(JSON.stringify(observed));
  if (boundary !== 'publication-private') {
    assert.notEqual(observed.recovery, 'completed',
      'an incomplete capture must not become an executable completed input');
  }
  assert.equal(observed.retirementError, undefined,
    'partial durable capture must retain recoverable cleanup responsibility');
  assert.equal(observed.holdings, 0, 'all unshared test holdings must retire');
  assert.equal(observed.objects, 0, 'all unshared test payloads must retire');
  assert.equal(await store.readEffectCaptureCustody(saved.runDefinition), undefined,
    'completed retirement must discharge its durable custody inventory');
} finally { await store.close(); }
