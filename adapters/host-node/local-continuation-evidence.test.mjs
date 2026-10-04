import assert from 'node:assert/strict';
import {chmod, mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {ensureAuthorizationRuntime, ensureCheckpointRuntime} from './authorization-fixture.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey,
  openContinuationEvidence} from './local-continuation-evidence.mjs';

import {loadCheckpointRuntime, openSqliteCheckpointJournal} from
  './sqlite-checkpoint-journal.mjs';

ensureAuthorizationRuntime();
ensureCheckpointRuntime();
const runtime = await loadCheckpointRuntime();
function classifier(t, state, observed = []) {
  const journal = openSqliteCheckpointJournal(join(state, 'journal'), {
    runtime: {...runtime, runOutcomeTerminal(status) {
      observed.push(status);
      return runtime.runOutcomeTerminal(status);
    }},
    expectedAuthorityScopeCid: `sha256:${'5'.repeat(64)}`,
    authorizeResolution() { throw new Error('not used'); },
    attestResolution() { throw new Error('not used'); },
  });
  t.after(() => journal.close());
  return journal.isTerminalRunOutcome;
}
const moon = await import(new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);

test('a retained Source capture survives restart with exact bytes and terminal custody',
  async t => {
    const state = await mkdtemp(join(tmpdir(), 'actql-source-evidence-'));
    t.after(() => rm(state, {recursive: true, force: true}));
    await createPrivateEvidenceKey(state);
    const key = await loadPrivateEvidenceKey(state);
    const isTerminalRunOutcome = classifier(t, state);
    let status = 'waiting_checkpoint';
    const open = () => openContinuationEvidence({stateDirectory: state,
      ...key, isTerminalRunOutcome, contractControl: runtimeCore(moon).publicationControl,
      preparation: () => ({status: 'run_created', runStatus: status})});
    let evidence = open();
    t.after(() => evidence.close());
    // Authored independently: source text preserves distinct Unicode bytes,
    // a null scalar, and a typed integer representation through the Store.
    const wire = '{"occurrence":0,"rows":[["é",null,"17"],["é",true,"-4"]]}';
    const [captureCid] = await evidence.hold('effect-source-run',
      `sha256:${'2'.repeat(64)}`, [{name: 'source_capture', wire}]);
    await evidence.close();
    evidence = open();
    const opened = await evidence.open('effect-source-run');
    assert.deepEqual(opened.held('source_capture'), [captureCid]);
    assert.deepEqual(opened.held('captured_input'), []);
    assert.equal((await opened.bytes('source_capture', captureCid,
      {maxBytes: 4096})).toString('utf8'), wire);
    for (status of ['waiting_checkpoint', 'resuming', 'needs_reconciliation']) {
      await evidence.settle();
      assert.equal((await opened.bytes('source_capture', captureCid)).toString('utf8'), wire);
    }
    status = 'cancelled';
    await evidence.settle();
    await assert.rejects(opened.bytes('source_capture', captureCid),
      {code: 'ContinuationEvidenceRetired'});
  });

test('a bounded evidence read refuses by recorded size before loading bytes',
  async t => {
    const state = await mkdtemp(join(tmpdir(), 'actql-evidence-bound-'));
    t.after(() => rm(state, {recursive: true, force: true}));
    await createPrivateEvidenceKey(state);
    const key = await loadPrivateEvidenceKey(state);
    const isTerminalRunOutcome = classifier(t, state);
    const evidence = openContinuationEvidence({stateDirectory: state,
      ...key, isTerminalRunOutcome, contractControl: runtimeCore(moon).publicationControl,
      preparation: () => ({status: 'waiting_checkpoint'})});
    t.after(() => evidence.close());
    const small = JSON.stringify({kind: 'review', text: 'x'.repeat(100)});
    const large = JSON.stringify({kind: 'review', text: 'y'.repeat(20_000)});
    const [smallCid, largeCid] = await evidence.hold('attempt-1',
      `sha256:${'1'.repeat(64)}`, [
        {name: 'review_projection', wire: small},
        {name: 'captured_input', wire: large},
      ]);
    const opened = await evidence.open('attempt-1');
    assert.deepEqual(opened.held('review_projection'), [smallCid]);
    assert.deepEqual(opened.held('continuation_record'), []);
    // Within the bound: the exact bytes, verified against their CID.
    assert.equal((await opened.bytes('review_projection', smallCid,
      {maxBytes: 4096})).toString('utf8'), small);
    // The recorded envelope size already exceeds the bound: refused before
    // the object is consumed.
    await assert.rejects(opened.bytes('captured_input', largeCid,
      {maxBytes: 1024}), {code: 'EvidenceReadLimitExceeded'});
    // A plaintext just over the bound whose envelope fits the size
    // allowance is still refused after decryption, never returned.
    await assert.rejects(opened.bytes('review_projection', smallCid,
      {maxBytes: small.length - 1}), {code: 'EvidenceReadLimitExceeded'});
    for (const maxBytes of [0, -1, 1.5]) {
      await assert.rejects(opened.bytes('review_projection', smallCid,
        {maxBytes}), {code: 'InvalidEvidenceReadLimit'});
    }
    // Only an exact held reference is readable.
    await assert.rejects(opened.bytes('review_projection', largeCid,
      {maxBytes: 1_000_000}), {code: 'ContinuationEvidenceNotHeld'});
  });

// These expectations are authored independently of the Core implementation.
for (const [status, terminal] of [
  ['preparing', false], ['running', false], ['waiting_checkpoint', false],
  ['resuming', false], ['needs_reconciliation', false], ['succeeded', true],
  ['failed', true], ['cancelled', true], ['unknown', false], ['', false],
  ['Succeeded', false], ['succeeded ', false], [undefined, false], [null, false],
  [{status: 'succeeded'}, false],
]) {
  test(`retention consumes the shared outcome classifier for ${JSON.stringify(status)}`,
    async t => {
      const state = await mkdtemp(join(tmpdir(), 'actql-terminal-evidence-'));
      t.after(() => rm(state, {recursive: true, force: true}));
      await createPrivateEvidenceKey(state);
      const key = await loadPrivateEvidenceKey(state);
      const calls = [];
      const isTerminalRunOutcome = classifier(t, state, calls);
      const evidence = openContinuationEvidence({stateDirectory: state, ...key,
        contractControl: runtimeCore(moon).publicationControl,
        isTerminalRunOutcome,
        preparation: () => ({status: 'run_created', runStatus: status})});
      t.after(() => evidence.close());
      const [capture, request] = await evidence.hold('attempt',
        `sha256:${'2'.repeat(64)}`, [
          {name: 'source_capture', wire: '{"rows":[1]}'},
          {name: 'invocation_request', wire: '{"request":"identity"}'},
        ]);
      const result = await evidence.settle();
      assert.equal(result.retired.length, terminal ? 1 : 0);
      assert.deepEqual(result.pending, []);
      assert.deepEqual(calls, typeof status === 'string' ? [status] : []);
      const opened = await evidence.open('attempt');
      if (terminal) await assert.rejects(opened.bytes('source_capture', capture),
        {code: 'ContinuationEvidenceRetired'});
      else assert.equal((await opened.bytes('source_capture', capture)).toString(),
        '{"rows":[1]}');
      assert.equal((await opened.bytes('invocation_request', request)).toString(),
        '{"request":"identity"}', 'terminality does not retire request identity');
    });
}

test('terminal outcome leaves failed physical retirement pending until cleanup succeeds',
  async t => {
    const state = await mkdtemp(join(tmpdir(), 'actql-terminal-cleanup-'));
    t.after(() => rm(state, {recursive: true, force: true}));
    await createPrivateEvidenceKey(state);
    const key = await loadPrivateEvidenceKey(state);
    const isTerminalRunOutcome = classifier(t, state);
    const evidence = openContinuationEvidence({stateDirectory: state, ...key,
      contractControl: runtimeCore(moon).publicationControl, isTerminalRunOutcome,
      preparation: () => ({status: 'run_created', runStatus: 'succeeded'})});
    t.after(() => evidence.close());
    await evidence.hold('attempt', `sha256:${'2'.repeat(64)}`,
      [{name: 'source_capture', wire: '{"rows":[1]}'}]);
    const holdings = join(state, 'private-store', 'physical-holdings');
    await chmod(holdings, 0o500);
    t.after(() => chmod(holdings, 0o700).catch(() => {}));
    const pending = await evidence.settle();
    assert.equal(pending.retired.length, 0);
    assert.equal(pending.pending.length, 1);
    assert.equal(pending.pending[0].code, 'EACCES');
    const ledger = () => readFile(join(state, 'attempts', 'attempt.json'), 'utf8')
      .then(JSON.parse);
    assert.equal((await ledger()).holdings[0].state, 'retiring');
    assert.equal((await readdir(holdings)).length, 1);
    await chmod(holdings, 0o700);
    const settled = await evidence.settle();
    assert.equal(settled.retired.length, 1);
    assert.deepEqual(settled.pending, []);
    assert.equal((await ledger()).holdings[0].state, 'retired');
    assert.deepEqual(await readdir(holdings), []);
  });

for (const [current, abandoned, retired] of [
  [undefined, false, false], [undefined, true, true],
  [{status: 'ended'}, false, true],
  [{status: 'waiting_checkpoint'}, false, false],
  [{status: 'resuming'}, false, false],
  [{status: 'unknown'}, false, false],
]) {
  test(`non-Run retention keeps its own obligation for ${current?.status}, abandoned=${abandoned}`,
    async t => {
      const state = await mkdtemp(join(tmpdir(), 'actql-retention-branch-'));
      t.after(() => rm(state, {recursive: true, force: true}));
      await createPrivateEvidenceKey(state);
      const key = await loadPrivateEvidenceKey(state);
      const calls = [];
      const evidence = openContinuationEvidence({stateDirectory: state, ...key,
        contractControl: runtimeCore(moon).publicationControl,
        isTerminalRunOutcome: classifier(t, state, calls),
        preparation: () => current});
      t.after(() => evidence.close());
      await evidence.hold('attempt', `sha256:${'2'.repeat(64)}`,
        [{name: 'source_capture', wire: '{"rows":[1]}'}]);
      if (abandoned) await evidence.abandon('attempt');
      const result = await evidence.settle();
      assert.equal(result.retired.length, retired ? 1 : 0);
      assert.deepEqual(result.pending, []);
      assert.deepEqual(calls, [], 'non-Run branches do not consult outcome classification');
    });
}

test('evidence requires the owned outcome classifier port', () => {
  for (const isTerminalRunOutcome of [undefined, null, true, 'succeeded']) {
    assert.throws(() => openContinuationEvidence({stateDirectory: '/unused',
      key: Buffer.alloc(32), keyId: 'key', preparation: () => undefined,
      contractControl: runtimeCore(moon).publicationControl,
      isTerminalRunOutcome}), {code: 'InvalidContinuationEvidencePort'});
  }
});
