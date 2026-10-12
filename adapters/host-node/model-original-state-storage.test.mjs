import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmod, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {loadCheckpointRuntime} from './sqlite-checkpoint-journal.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey,
  openContinuationEvidence} from './local-continuation-evidence.mjs';

const runtime = await loadCheckpointRuntime();
const role = 'original_model_state';
const owner = 'model-state-run';
const requestCid = `sha256:${'2'.repeat(64)}`;
const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
// Independently authored existing document bytes. Storage does not admit a
// Ledger or derive a new token, current cut, response or dispatch grant.
const wire = '["actql-original-ledger-state/0.1",["17","2","3","11","7003","3002"],["17","0","0","0","0","0","0","7003","3002","7003"],["0","0","0"],null,[["0","0","0"],["0","0","0"],["0","0","0"]],"-3",["1","0","0",true,true,false,"reading",true],["-1","0","3","2",true,false,null,null,[false,false,false],null],[["-2","0","7000","3000",true,false,null,null,[false,false,false],null]],[],[]]';
const fixedStateCid = 'sha256:e6c6b87dc82a5b9e10b90e5546e57cf6d805587584df7cd796f8a61608350967';
const fixedHoldingPreimage = '{"version":"actql-local-continuation-holding/0.1","prepare_attempt_id":"model-state-run","name":"original_model_state","semantic_cid":"sha256:e6c6b87dc82a5b9e10b90e5546e57cf6d805587584df7cd796f8a61608350967"}';
const fixedHoldingCid = 'sha256:9cf4de8dda4f475089dd5ec49b8a0b588683c958f3d61f25202288de7fe9dbd3';

async function fixture(t, {current = {status: 'waiting_checkpoint'}} = {}) {
  const state = await mkdtemp(join(tmpdir(), 'actql-model-state-storage-'));
  t.after(() => rm(state, {recursive: true, force: true}));
  await createPrivateEvidenceKey(state);
  const key = await loadPrivateEvidenceKey(state);
  const observations = {current};
  const open = (selected = key) => openContinuationEvidence({stateDirectory: state,
    ...selected, contractControl: runtimeCore(moon).publicationControl,
    preparation: () => observations.current,
    isTerminalRunOutcome: runtime.runOutcomeTerminal});
  let evidence = open();
  t.after(() => evidence.close());
  return {state, key, observations, get evidence() { return evidence; },
    async restart(selected) { await evidence.close(); evidence = open(selected); },
    ledgerPath: id => join(state, 'attempts', `${id}.json`)};
}

test('Original Model state role stores exact bytes in its own encrypted holding', async t => {
  const f = await fixture(t);
  const [cid] = await f.evidence.hold(owner, requestCid, [{name: role, wire}]);
  assert.equal(digest(wire), fixedStateCid);
  assert.equal(digest(fixedHoldingPreimage), fixedHoldingCid);
  assert.equal(cid, fixedStateCid);
  const ledger = JSON.parse(await readFile(f.ledgerPath(owner), 'utf8'));
  assert.equal(ledger.request_cid, requestCid);
  assert.equal(ledger.holdings.length, 1);
  assert.deepEqual(ledger.holdings[0], {name: role, semantic_cid: cid,
    holding_cid: fixedHoldingCid, key_id: f.key.keyId, state: 'held'});
  const held = await f.evidence.open(owner);
  assert.equal(held.requestCid, requestCid);
  assert.deepEqual(held.held(role), [cid]);
  assert.deepEqual(held.held('captured_input'), []);
  assert.equal((await held.bytes(role, cid, {maxBytes: 4096})).toString('utf8'), wire);
  const objects = join(f.state, 'private-store', 'objects');
  for (const path of await readdir(objects)) {
    // Physical bytes are encrypted, not an alleged Result/Source object.
    assert.equal((await readFile(join(objects, path))).includes(Buffer.from(wire)), false);
  }
  await f.restart();
  const reopened = await f.evidence.open(owner);
  assert.equal((await reopened.bytes(role, cid, {maxBytes: 4096})).toString('utf8'), wire);
  assert.equal((await readdir(join(f.state, 'private-store', 'physical-holdings'))).length, 1);
});

test('Original Model state role preserves custody without exact release evidence', async t => {
  const f = await fixture(t);
  const [cid] = await f.evidence.hold(owner, requestCid, [{name: role, wire}]);
  for (const status of ['running', 'waiting_checkpoint', 'resuming',
    'needs_reconciliation', 'succeeded', 'failed', 'cancelled', 'unknown']) {
    f.observations.current = {status: 'run_created', runStatus: status};
    const result = await f.evidence.settle();
    assert.deepEqual(result, {retired: [], pending: []});
    assert.equal((await (await f.evidence.open(owner)).bytes(role, cid)).toString(), wire);
  }
  // Missing observation after restart or an abandoned preparation is not an
  // original Model/token release acknowledgement.
  f.observations.current = undefined;
  await f.evidence.abandon(owner);
  await f.restart();
  assert.deepEqual(await f.evidence.settle(), {retired: [], pending: []});
  assert.equal((await (await f.evidence.open(owner)).bytes(role, cid)).toString(), wire);
});

test('Original Model state role does not replace terminal Source retirement', async t => {
  const f = await fixture(t, {current: {status: 'run_created', runStatus: 'succeeded'}});
  const [stateCid, sourceCid] = await f.evidence.hold(owner, requestCid,
    [{name: role, wire}, {name: 'source_capture', wire: '{"rows":[1]}'}]);
  const retired = await f.evidence.settle();
  assert.equal(retired.retired.length, 1);
  assert.deepEqual(retired.pending, []);
  const held = await f.evidence.open(owner);
  assert.equal((await held.bytes(role, stateCid)).toString(), wire);
  await assert.rejects(held.bytes('source_capture', sourceCid),
    {code: 'ContinuationEvidenceRetired'});
});

test('Original Model state role refuses foreign Run custody and key generation', async t => {
  const f = await fixture(t);
  const [cid] = await f.evidence.hold(owner, requestCid, [{name: role, wire}]);
  await assert.rejects(f.evidence.hold(owner, `sha256:${'3'.repeat(64)}`,
    [{name: role, wire}]), {code: 'ContinuationRequestMismatch'});
  const [otherCid] = await f.evidence.hold('model-other-run', requestCid, [{name: role, wire}]);
  assert.equal(otherCid, cid, 'equal bytes do not combine Run custody');
  const otherPath = f.ledgerPath('model-other-run');
  const other = JSON.parse(await readFile(otherPath, 'utf8'));
  const own = JSON.parse(await readFile(f.ledgerPath(owner), 'utf8'));
  const originalOther = JSON.stringify(other);
  other.holdings[0].holding_cid = own.holdings[0].holding_cid;
  await writeFile(otherPath, JSON.stringify(other));
  await assert.rejects((await f.evidence.open('model-other-run')).bytes(role, cid),
    {code: 'ContinuationEvidenceNotHeld'});
  await writeFile(otherPath, originalOther);
  await f.restart({key: Buffer.alloc(32, 1), keyId: `sha256:${'4'.repeat(64)}`});
  await assert.rejects(f.evidence.open(owner), {code: 'PrivateEvidenceKeyMismatch'});
  await f.restart(f.key);
  assert.equal((await (await f.evidence.open(owner)).bytes(role, cid)).toString(), wire);
});

test('Original Model state role checks bounds and rejects body or role substitution', async t => {
  const f = await fixture(t);
  const [cid] = await f.evidence.hold(owner, requestCid, [{name: role, wire}]);
  const held = await f.evidence.open(owner);
  await assert.rejects(held.bytes(role, cid, {maxBytes: 1}), {code: 'EvidenceReadLimitExceeded'});
  await assert.rejects(held.bytes('captured_input', cid), {code: 'ContinuationEvidenceNotHeld'});
  await assert.rejects(held.bytes(role, digest(`${wire} `)), {code: 'ContinuationEvidenceNotHeld'});
  await assert.rejects(f.evidence.hold(owner, requestCid,
    [{name: 'original_resource_state', wire}]), {code: 'InvalidContinuationEvidence'});
  const ledger = JSON.parse(await readFile(f.ledgerPath(owner), 'utf8'));
  const holding = JSON.parse(await readFile(join(f.state, 'private-store',
    'physical-holdings', `${ledger.holdings[0].holding_cid.slice(7)}.json`), 'utf8'));
  const objectPath = join(f.state, 'private-store', 'objects', holding.objects[0].cid.slice(7));
  const original = await readFile(objectPath);
  const changed = Buffer.from(original);
  changed[changed.length - 1] ^= 1;
  await writeFile(objectPath, changed);
  await assert.rejects(held.bytes(role, cid));
  await writeFile(objectPath, original);
  assert.equal((await held.bytes(role, cid)).toString(), wire);
});

test('Original Model state role stays held through retryable sibling cleanup failure', async t => {
  const f = await fixture(t, {current: {status: 'run_created', runStatus: 'cancelled'}});
  const [cid] = await f.evidence.hold(owner, requestCid,
    [{name: role, wire}, {name: 'source_capture', wire: '{"rows":[1]}'}]);
  const path = join(f.state, 'private-store', 'physical-holdings');
  await chmod(path, 0o500);
  t.after(() => chmod(path, 0o700).catch(() => {}));
  const failed = await f.evidence.settle();
  assert.equal(failed.retired.length, 0);
  assert.equal(failed.pending.length, 1);
  assert.equal(failed.pending[0].code, 'EACCES');
  const pending = JSON.parse(await readFile(f.ledgerPath(owner), 'utf8'));
  assert.equal(pending.holdings[0].state, 'held');
  assert.equal(pending.holdings[1].state, 'retiring');
  await chmod(path, 0o700);
  const retried = await f.evidence.settle();
  assert.equal(retried.retired.length, 1);
  assert.deepEqual(retried.pending, []);
  assert.equal((await (await f.evidence.open(owner)).bytes(role, cid)).toString(), wire);
  assert.equal((await readdir(path)).length, 1);
});
