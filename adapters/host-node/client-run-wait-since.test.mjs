import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {installedRunWaitDecision} from '../host-common/run-state-observation.mjs';

test('actual Common wait uses state revision and retains Unknown and checkpoint readiness', () => {
  const state = {version:'actql-run-state/0.1', run_id:'original', status:'needs_reconciliation',
    revision:7, updated_at:'2026-10-16T00:00:00.000Z', result_available:false,
    result_availability:{}, next_action:{kind:'reconcile_run', reason:'execution_unknown'},
    control:{revision:99, cancellation_requested:true, physical_stop:'unknown'}};
  assert.equal(installedRunWaitDecision(moon, state, null), 'ready');
  assert.equal(installedRunWaitDecision(moon, state, 6), 'ready');
  assert.equal(installedRunWaitDecision(moon, state, 7), 'pending');
  assert.equal(installedRunWaitDecision(moon, state, 8), 'InvalidWaitRevision');
  assert.equal(installedRunWaitDecision(moon, {...state, revision:null}, null), 'InvalidRunWaitState');
  const checkpoint = {...state, status:'waiting_checkpoint',
    checkpoint:{checkpoint_id:'original', checkpoint_cid:`sha256:${'a'.repeat(64)}`, kind:'run_scope'},
    next_action:{kind:'resolve_checkpoint', checkpoint_id:'original'}};
  assert.equal(installedRunWaitDecision(moon, checkpoint, 6), 'ready');
  assert.equal(installedRunWaitDecision(moon, checkpoint, 7), 'pending');
});

test('actual Local wait since observes the same saved Run, times out without revision or work fabrication', async t => {
  const scratch = await createOwnedScratch({parent:tmpdir(), prefix:'actql-a-wait-original-',
    label:'actual Local original Run wait since'});
  t.diagnostic(`Disposable actual Host retained on failure: ${scratch.path}`);
  const keys = generateKeyPairSync('ed25519');
  let computations = 0;
  const installation = {directory:scratch.path, authorization:{
    accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',
      account_id:'wait-state', entries:[{entry_id:'write', outcome:'allow',
        principal:{all:true}, connection:{all:true}, resource:{all:true},
        operation:{any_of:['write']}, exclusions:[]}]}),
    reviewers:[{keyId:'reviewer', reviewerId:'reviewer', principalId:userInfo().username,
      publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
    hostKey:{keyId:'host', privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
    observe(name) {if (name === 'computed') computations++;},
  }};
  const options = {mode:'local', owner:'local', installation};
  const client = await connectEmbeddedLocal(options);
  let reopened;
  t.after(async () => {await client.close(); await reopened?.close();});
  const text = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8');
  const run = await client.startSource(text, {format:'json', submissionRef:client.newSubmission({nonce:'wait-state'})});
  const completed = await run.wait({signal:AbortSignal.timeout(15000)});
  assert.equal(completed.status, 'succeeded');
  const current = await run.status();
  await assert.rejects(run.wait({since:current.revision, signal:AbortSignal.timeout(250)}),
    {code:'WaitTimeout'});
  assert.equal((await run.status()).revision, current.revision,
    'Read time and timeout cannot invent a state change');
  await assert.rejects(run.wait({since:current.revision+1, signal:AbortSignal.timeout(5000)}),
    {code:'InvalidWaitRevision'});
  const abort = new AbortController();
  const waiting = run.wait({since:current.revision, signal:abort.signal});
  const rejected = assert.rejects(waiting, {code:'WaitAborted'});
  abort.abort(); await rejected;
  assert.equal((await run.wait()).revision, current.revision);
  assert.deepEqual(await run.result('answer').all(), [{id:1},{id:2}]);
  await client.close();
  reopened = await connectEmbeddedLocal(options);
  const attached = await reopened.attach(run.ref);
  const restored = await attached.wait({signal:AbortSignal.timeout(5000)});
  assert.equal(restored.run_id, completed.run_id);
  assert.equal(restored.revision, current.revision);
  await assert.rejects(attached.wait({since:restored.revision, signal:AbortSignal.timeout(200)}),
    {code:'WaitTimeout'});
  assert.equal(computations, 1, 'No wait, timeout or attach reacquires execution');
  await reopened.close();
  scratch.passed();
});
