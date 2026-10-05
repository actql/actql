// Public same-Run acceptance through the real installed Model/Core driver,
// signed Checkpoint API, SQLite journal and encrypted publication Store.
// Every phase runs in a fresh process. Expected sends and rows are authored
// here, independently of the product's journal/settlement implementation.
import assert from 'node:assert/strict';
import {spawnSync, execFileSync} from 'node:child_process';
import {createDecipheriv, createHash} from 'node:crypto';
import {existsSync, readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {setTimeout as pause} from 'node:timers/promises';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {scopedModelHolding} from '../../scripts/fixtures/model-custody-fixture.mjs';
const packedInputs = process.env.ACTQL_MODEL_ACCEPTANCE_INPUTS;
const acceptance = packedInputs === undefined ? {
  runtime: {
    client: new URL('../../packages/node/index.mjs', import.meta.url).href,
    httpHost: new URL('./embedded-local.mjs', import.meta.url).href,
    inferFixture: new URL('../../scripts/fixtures/installed-infer-fixture.mjs', import.meta.url).href,
    providerFixture: new URL('../../scripts/fixtures/model-provider-binding-fixture.mjs', import.meta.url).href,
    environment: fileURLToPath(new URL('../../spec/local-check-environment.json', import.meta.url)),
    sourceObserver: new URL('../../scripts/fixtures/two-source-public-query.mjs', import.meta.url).href,
    sourceEnvironment: fileURLToPath(new URL('./fixtures/query-amount-environment.json', import.meta.url)),
    duckdbPackage: new URL('../connectors/duckdb/node/package.json', import.meta.url).href,
  },
} : JSON.parse(readFileSync(packedInputs, 'utf8'));
if (packedInputs === undefined) {
  // Prepare only the source installation. Packed acceptance has its own fresh
  // npm installation and must never repair it with checkout dependency links.
  const {prepareSourceNodeClient} = await import('./fixtures/source-node-client.mjs');
  await prepareSourceNodeClient({assemble: true});
}

const processFixture = fileURLToPath(new URL('./fixtures/model-resume-public-process.mjs', import.meta.url));
const expectedRows = (count = 1, acquired = false) => [
  {id: acquired ? 1 : '1', outcome: 'ok', value: {reason: null, risk: 'high'}},
  {id: acquired ? 2 : '2', outcome: 'ok', value: {reason: null, risk: 'low'}},
  {id: acquired ? 3 : '3', outcome: 'ok', value: {reason: null, risk: 'medium'}},
].slice(0, count);

async function fixture(t, options = {}) {
  const root = await mkdtemp(join(acceptance.scratch ?? tmpdir(), 'actql-public-model-resume-'));
  if (acceptance.preserveArtifacts === true) t.diagnostic(`Model recovery artifacts: ${root}`);
  else t.after(() => rm(root, {recursive: true, force: true}));
  if (options.transport === 'https') execFileSync('openssl', [
    'req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'host.key',
    '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
  ], {cwd: root, stdio: 'ignore'});
  const read = name => JSON.parse(readFileSync(join(root, name), 'utf8'));
  const lines = name => existsSync(join(root, name))
    ? readFileSync(join(root, name), 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
  return {root, read, lines,
    phase(phase, changes = {}, expectedExit = 0) {
      const env = {...process.env};
      for (const name of ['ACTQL_LOCAL_STATE_DIR', 'ACTQL_LOCAL_SOURCE_PROFILE',
        'ACTQL_LOCAL_EFFECT_PROFILE']) delete env[name];
      const result = spawnSync(process.execPath, [processFixture], {
        input: JSON.stringify({...options, runtime: acceptance.runtime, root, phase, ...changes}),
        encoding: 'utf8', timeout: 45_000, maxBuffer: 4 * 1024 * 1024,
        env,
      });
      const reportPath = join(root, `${phase}-result.json`);
      const report = existsSync(reportPath) ? read(`${phase}-result.json`) : undefined;
      assert.equal(result.error, undefined, `Process error: ${result.error}`);
      assert.equal(result.status, expectedExit,
        `${phase}: ${JSON.stringify(report)}\n${result.stderr}\n${result.stdout}`);
      assert.ok(report, `Missing independent process report: ${phase}`);
      assert.equal(report.error, undefined, JSON.stringify(report));
      return report;
    },
    journal() {
      const database = new DatabaseSync(join(root, 'host', 'checkpoints', 'journal',
        'checkpoint-journal.sqlite3'), {readOnly: true});
      try {
        const query = sql => database.prepare(sql).all().map(row => ({...row}));
        return {
          scopes: query('SELECT run_id, scope_cid, checkpoint_cid, inventory_json, originals_json FROM resume_model_scopes'),
          slots: query('SELECT ordinal, state, attempt_index FROM resume_model_slots ORDER BY ordinal'),
          attempts: query('SELECT ordinal, state, entry_json, settlement_json FROM resume_model_attempts ORDER BY ordinal'),
          checkpoints: query('SELECT checkpoint_cid, closure, checkpoint_wire FROM checkpoints ORDER BY persisted_at'),
          fences: query('SELECT run_id FROM run_cancellation_fences'),
        };
      } finally { database.close(); }
    },
  };
}
const slotStates = journal => journal.slots.map(row => row.state);
const assertSameRun = (first, second) => {
  assert.deepEqual(second.ref, first.ref);
  if (second.runId !== undefined) assert.equal(second.runId, first.runId);
};
const assertSends = (f, expected) => {
  assert.deepEqual(f.lines('provider-calls.jsonl').map(value => value.text), expected);
};

// Verify the independently observed saved record is backed by encrypted
// physical Store bytes. Read-only inspection never repairs/creates evidence.
function savedEvidence(f, ordinal, role, expectedState = 'SavedSuccess') {
  const attempt = f.journal().attempts.find(value => value.ordinal === ordinal);
  assert.ok(attempt, `No recorded attempt for slot ${ordinal}`);
  assert.equal(attempt.state, expectedState);
  const evidence = JSON.parse(attempt.settlement_json).evidence[role];
  assert.ok(evidence, `Missing original ${role}`);
  const entry = JSON.parse(attempt.entry_json);
  const storeCid = `sha256:${createHash('sha256').update(JSON.stringify({
    version: 'actql-local-store-owner/0.1', root: join(f.root, 'host'),
    principalId: JSON.parse(f.journal().scopes[0].originals_json).expectedBoundary.principal,
  })).digest('hex')}`;
  assert.equal(evidence.holdingCid, scopedModelHolding(join(f.root, 'host'),
    entry.runDefinitionCid, storeCid, role, ordinal));
  const holding = f.read(`host/publication/physical-holdings/${evidence.holdingCid.slice(7)}.json`);
  assert.equal(holding.holding_cid, evidence.holdingCid);
  assert.equal(holding.manifest_cid, evidence.cid);
  assert.equal(holding.namespace, 'publication-private');
  assert.equal(holding.objects.length, 1);
  const object = holding.objects[0];
  const bytes = readFileSync(join(f.root, 'host/publication/objects', object.cid.slice(7)));
  assert.equal(bytes.byteLength, object.byte_count);
  assert.equal(`sha256:${createHash('sha256').update(bytes).digest('hex')}`, object.cid);
  const envelope = JSON.parse(bytes);
  assert.equal(envelope.version, 'actql-private-publication-evidence/0.1');
  const key = readFileSync(join(f.root, 'host/checkpoints/private-evidence.key'));
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.nonce, 'base64'));
    decipher.setAAD(Buffer.from(`actql-private-publication-evidence/0.1\0${role}\0${holding.manifest_cid}`));
    decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
    return JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]));
  } finally { key.fill(0); }
}

for (const transport of ['local', 'https']) {
  test(`public Model ${transport}: cancellation retains a sent unknown across restart`, async t => {
    const f = await fixture(t, {transport, count: 3});
    const waiting = f.phase('wait');
    f.phase('approve-crash-unknown', {}, 77);
    assertSends(f, ['alpha', 'bravo']);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'EnteredUnknown', 'Unsent']);
    await pause(1100);
    const cancelled = f.phase('cancel-unknown');
    assertSameRun(waiting, cancelled);
    assert.equal(cancelled.status, 'needs_reconciliation');
    assertSends(f, ['alpha', 'bravo']);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'EnteredUnknown', 'Unsent']);
    assert.equal(savedEvidence(f, 0, 'model_slot_capture').outcome, 'ok');
    const replay = f.phase('resume');
    assertSameRun(waiting, replay);
    assert.equal(replay.status, 'needs_reconciliation');
    assertSends(f, ['alpha', 'bravo']);
    assert.equal(f.journal().fences.length, 1);
  });

  test(`public Model ${transport}: immediate Allow finishes once across process restart`, async t => {
    const f = await fixture(t, {transport, immediate: true});
    const finished = f.phase('immediate');
    assert.equal(finished.status, 'succeeded', JSON.stringify(finished));
    assert.deepEqual(finished.rows, expectedRows());
    assertSends(f, ['alpha']);
    assert.equal(f.journal().checkpoints.length, 0);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess']);
    const replay = f.phase('resume');
    assertSameRun(finished, replay);
    assert.equal(replay.status, 'succeeded');
    assert.deepEqual(replay.rows, expectedRows());
    assertSends(f, ['alpha']);
  });

  test(`public Model ${transport}: approval and process restart retain one Run and physical calls 0→1→1`, async t => {
    const f = await fixture(t, {transport});
    const waiting = f.phase('wait');
    assert.equal(waiting.status, 'waiting_checkpoint');
    assertSends(f, []);
    const before = f.journal();
    assert.deepEqual(slotStates(before), ['Unsent']);
    assert.equal(before.scopes.length, 1);
    assert.equal(before.scopes[0].run_id, waiting.summary.subject.runId);
    assert.equal(before.attempts.length, 0);
    const finished = f.phase('approve');
    assertSameRun(waiting, finished);
    assert.equal(finished.status, 'succeeded', JSON.stringify(finished));
    assert.deepEqual(finished.rows, expectedRows());
    assertSends(f, ['alpha']);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess']);
    assert.equal(f.journal().scopes[0].run_id, waiting.summary.subject.runId);
    const replay = f.phase('duplicate');
    assertSameRun(waiting, replay);
    assert.equal(replay.status, 'succeeded');
    assert.deepEqual(replay.rows, expectedRows());
    assertSends(f, ['alpha']);
    assert.equal(savedEvidence(f, 0, 'model_slot_capture').outcome, 'ok');
    const accounting = savedEvidence(f, 0, 'model_attempt_accounting');
    assert.equal(accounting.input_tokens, 1);
    assert.equal(accounting.output_tokens, 2);
  });

  test(`public Model ${transport}: saved partial process crash resumes only unsent calls`, async t => {
    const f = await fixture(t, {transport, count: 3});
    const waiting = f.phase('wait');
    const crash = f.phase('approve-crash-saved', {}, 77);
    assertSameRun(waiting, crash);
    assert.equal(crash.boundary, 'infer_model_settlement_committed');
    assertSends(f, ['alpha']);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'Unsent', 'Unsent']);
    assert.equal(savedEvidence(f, 0, 'model_slot_capture').outcome, 'ok');
    await pause(1100); // Let the crashed process's real one-second lease expire.
    const replay = f.phase('resume');
    assertSameRun(waiting, replay);
    assert.equal(replay.status, 'succeeded');
    assert.deepEqual(replay.rows, expectedRows(3));
    assertSends(f, ['alpha', 'bravo', 'charlie']);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'SavedSuccess', 'SavedSuccess']);
  });

  test(`public Model ${transport}: stored response before journal acknowledgement is observed without resend`, async t => {
    const f = await fixture(t, {transport, count: 3});
    const waiting = f.phase('wait');
    f.phase('approve-crash-response', {}, 77);
    assertSends(f, ['alpha']);
    assert.deepEqual(slotStates(f.journal()), ['EnteredUnknown', 'Unsent', 'Unsent']);
    await pause(1100);
    const replay = f.phase('resume');
    assertSameRun(waiting, replay);
    assert.equal(replay.status, 'succeeded');
    assert.deepEqual(replay.rows, expectedRows(3));
    assertSends(f, ['alpha', 'bravo', 'charlie']);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'SavedSuccess', 'SavedSuccess']);
  });
}

for (const transport of ['local', 'https']) {
  for (const onNonSuccess of ['outcomes', 'fail']) {
    test(`public Model ${transport}: saved/unknown/unsent crash preserves uncertainty under ${onNonSuccess}`, async t => {
      const f = await fixture(t, {transport, count: 3, onNonSuccess});
      const waiting = f.phase('wait');
      f.phase('approve-crash-unknown', {}, 77);
      assertSends(f, ['alpha', 'bravo']);
      assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'EnteredUnknown', 'Unsent']);
      await pause(1100);
      const replay = f.phase('resume');
      assertSameRun(waiting, replay);
      assert.equal(replay.status, 'needs_reconciliation');
      assert.equal(replay.rows, undefined);
      assertSends(f, onNonSuccess === 'outcomes' ? ['alpha', 'bravo', 'charlie'] : ['alpha', 'bravo']);
      assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'EnteredUnknown',
        onNonSuccess === 'outcomes' ? 'SavedSuccess' : 'Unsent']);
      const again = f.phase('resume-again');
      assertSameRun(waiting, again);
      assert.equal(again.status, 'needs_reconciliation');
      assertSends(f, onNonSuccess === 'outcomes' ? ['alpha', 'bravo', 'charlie'] : ['alpha', 'bravo']);
    });
  }

  test(`public Model ${transport}: cancellation of a waiting Run fences all sends across restart`, async t => {
    const f = await fixture(t, {transport});
    const waiting = f.phase('wait');
    const cancelled = f.phase('cancel');
    assertSameRun(waiting, cancelled);
    assert.equal(cancelled.status, 'cancelled');
    assertSends(f, []);
    const replay = f.phase('resume');
    assertSameRun(waiting, replay);
    assert.equal(replay.status, 'cancelled');
    assertSends(f, []);
    assert.equal(f.journal().fences.length, 1);
  });

  test(`public Model ${transport}: cancellation after one saved response retains it and prevents later sends`, async t => {
    const f = await fixture(t, {transport, count: 3});
    const waiting = f.phase('wait');
    const cancelled = f.phase('approve-cancel-saved');
    assertSameRun(waiting, cancelled);
    assert.equal(cancelled.status, 'cancelled');
    assertSends(f, ['alpha']);
    assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'Unsent', 'Unsent']);
    assert.equal(savedEvidence(f, 0, 'model_slot_capture').outcome, 'ok');
    assert.equal(f.phase('resume').status, 'cancelled');
    assertSends(f, ['alpha']);
  });

  test(`public Model ${transport}: expired Checkpoint cannot cause a provider send after restart`, async t => {
    const f = await fixture(t, {transport, checkpointTtlMs: 1000});
    const waiting = f.phase('wait');
    await pause(1100);
    const replay = f.phase('probe');
    assertSameRun(waiting, replay);
    assert.notEqual(replay.status, 'succeeded');
    assertSends(f, []);
    assert.deepEqual(slotStates(f.journal()), ['Unsent']);
    assert.equal(f.journal().checkpoints[0].closure, 'expired');
  });

  test(`public Model ${transport}: approving an old provider scope never authorizes a replacement binding`, async t => {
    const f = await fixture(t, {transport});
    const waiting = f.phase('wait');
    const original = f.journal().scopes[0];
    const replay = f.phase('approve-replacement-probe', {providerRevision: 'public-model-fixture-2'});
    assertSameRun(waiting, replay);
    assert.notEqual(replay.status, 'succeeded');
    assertSends(f, []);
    assert.deepEqual(slotStates(f.journal()), ['Unsent']);
    assert.equal(f.journal().scopes[0].scope_cid, original.scope_cid);
    assert.equal(f.journal().scopes[0].originals_json, original.originals_json);
  });

}

test('public Model: immediate Allow partial crash uses the same journal and never repeats its saved send', async t => {
  const f = await fixture(t, {immediate: true, count: 3});
  f.phase('immediate-crash-saved', {}, 77);
  assertSends(f, ['alpha']);
  assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'Unsent', 'Unsent']);
  assert.equal(f.journal().checkpoints.length, 0);
  const replay = f.phase('resume');
  assert.equal(replay.status, 'succeeded');
  assert.deepEqual(replay.rows, expectedRows(3));
  assertSends(f, ['alpha', 'bravo', 'charlie']);
});

test('public acquired Model: Source approval and frozen input remain separate from Model approval', async t => {
  const f = await fixture(t, {acquired: true, sourceDelegate: true, transport: 'https'});
  const source = f.phase('wait-source');
  assert.equal(source.summary.kind, 'read_access');
  assertSends(f, []);
  assert.equal(source.source.sourceReadSessions, 0);
  assert.equal(source.source.sourceReads, 0);
  const model = f.phase('approve-source');
  assert.equal(model.summary.kind, 'model_invocation');
  assert.notEqual(model.summary.checkpointCid, source.summary.checkpointCid);
  assert.notEqual(model.summary.requiredArtifact.cid, source.summary.requiredArtifact.cid);
  assert.equal(model.source.sourceReadSessions, 1);
  assert.ok(model.source.sourceReads >= 1);
  assertSends(f, []);
  const completed = f.phase('approve', {changeSource: true});
  assertSameRun(model, completed);
  assert.equal(completed.status, 'succeeded');
  assert.deepEqual(completed.rows, expectedRows(1, true));
  assertSends(f, ['alpha']);
  assert.equal(completed.source.sourceReadSessions, 0,
    'Model recovery must consume fixed input rather than reacquire a changed Source');
  assert.equal(completed.source.sourceReads, 0);
});


for (const refusal of ['denyInfer', 'denyEgress']) {
  test(`public Model: current ${refusal} fences an approved unsent scope on restart`, async t => {
    const f = await fixture(t);
    const waiting = f.phase('wait');
    const before = f.journal().scopes[0];
    const replay = f.phase('approve-refused-probe', {[refusal]: true});
    assertSameRun(waiting, replay);
    assert.notEqual(replay.status, 'succeeded');
    assertSends(f, []);
    assert.deepEqual(slotStates(f.journal()), ['Unsent']);
    assert.equal(f.journal().scopes[0].originals_json, before.originals_json);
  });
}

test('public Model: a real Checkpoint attaches to an immediate partially saved inventory unchanged', async t => {
  const f = await fixture(t, {count: 3});
  f.phase('immediate-crash-saved', {permitModel: true}, 77);
  assertSends(f, ['alpha']);
  const original = f.journal().scopes[0];
  assert.equal(original.checkpoint_cid, null);
  const waiting = f.phase('wait', {expectedPriorCalls: 1});
  assert.equal(waiting.status, 'waiting_checkpoint');
  const attached = f.journal().scopes[0];
  assert.notEqual(attached.checkpoint_cid, null);
  assert.equal(attached.scope_cid, original.scope_cid);
  assert.equal(attached.originals_json, original.originals_json);
  assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'Unsent', 'Unsent']);
  const finished = f.phase('approve');
  assertSameRun(waiting, finished);
  assert.equal(finished.status, 'succeeded', JSON.stringify(finished));
  assert.deepEqual(finished.rows, expectedRows(3));
  assertSends(f, ['alpha', 'bravo', 'charlie']);
});


test('public Model: a durable terminal contract violation fails the Run without a fabricated slot or resend', async t => {
  const f = await fixture(t, {immediate: true, count: 3, usageOverflow: true});
  const failed = f.phase('immediate');
  assert.equal(failed.status, 'failed', JSON.stringify(failed));
  assertSends(f, ['alpha']);
  assert.deepEqual(slotStates(f.journal()), ['SavedFailure', 'Unsent', 'Unsent']);
  const proof = savedEvidence(f, 0, 'model_attempt_outcome', 'SavedFailure');
  assert.equal(proof.category, 'contract_violation');
  assert.equal(proof.failure, 'budget_exceeded');
  const settlement = JSON.parse(f.journal().attempts[0].settlement_json);
  assert.equal(settlement.evidence.terminalFailure, true);
  assert.equal(settlement.evidence.model_slot_capture, undefined);
  const replay = f.phase('resume');
  assertSameRun(failed, replay);
  assert.equal(replay.status, 'failed');
  assertSends(f, ['alpha']);
});


test('public Model: immediate running cancellation waits for stop and retains the saved response across restart', async t => {
  const f = await fixture(t, {immediate: true, count: 3});
  const cancelled = f.phase('immediate-cancel-saved');
  assert.equal(cancelled.status, 'cancelled', JSON.stringify(cancelled));
  assertSends(f, ['alpha']);
  assert.deepEqual(slotStates(f.journal()), ['SavedSuccess', 'Unsent', 'Unsent']);
  assert.equal(f.journal().fences.length, 1);
  assert.equal(f.journal().checkpoints.length, 0);
  assert.equal(savedEvidence(f, 0, 'model_slot_capture').outcome, 'ok');
  const replay = f.phase('resume');
  assertSameRun(cancelled, replay);
  assert.equal(replay.status, 'cancelled');
  assertSends(f, ['alpha']);
});
