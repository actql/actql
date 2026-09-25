// Durable Checkpoint lifecycle journal for a Node Host.
//
// Semantics (artifact shape and identity, Resolution admission, signature
// preimages, transition table, commit decisions, resume fencing and Run-state
// projections) are owned by the portable MoonBit core in src/checkpoint_runtime
// and reached through src/checkpoint_runtime_node. This adapter owns only
// storage, the clock, and the Host authorization and attestation ports, which
// verify and produce Ed25519 signatures over the core-computed preimages.
//
// A Run-unit Checkpoint belongs to a Run row. A preparation Checkpoint
// precedes its Run: it belongs to a preparation row, and a Run row exists only
// once the resumed preparation continuation creates it.
import {DatabaseSync} from 'node:sqlite';
import {mkdirSync, realpathSync} from 'node:fs';
import {join} from 'node:path';

const runtimeUrl = new URL(
  '../../_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js',
  import.meta.url,
);

const SCHEMA_VERSION = 'actql-checkpoint-journal/0.1';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;

export async function loadCheckpointRuntime() {
  return import(runtimeUrl.href);
}

function core(result, code) {
  const value = JSON.parse(result);
  if (value.ok !== true) fail(code, value.issue);
  return value;
}

function iso(ms) {
  if (!Number.isSafeInteger(ms) || ms < 0) fail('InvalidJournalClock');
  return new Date(ms).toISOString();
}

function transaction(database, body) {
  database.exec('BEGIN IMMEDIATE');
  try {
    const value = body();
    database.exec('COMMIT');
    return value;
  } catch (error) {
    try { database.exec('ROLLBACK'); }
    catch (rollback) { fail('CheckpointJournalRollbackFailed', rollback); }
    throw error;
  }
}

function authoritiesJson(authorities) {
  if (!Array.isArray(authorities) || authorities.length === 0) {
    fail('InvalidReviewerAuthorities');
  }
  return JSON.stringify(authorities.map(authority => {
    if (!text(authority?.keyId) || !text(authority?.reviewerId)) {
      fail('InvalidReviewerAuthorities');
    }
    return {key_id: authority.keyId, reviewer_id: authority.reviewerId};
  }));
}

function bindingJson(binding) {
  if (!text(binding?.authorizationContextCid) ||
      !text(binding?.environmentBindingCid)) {
    fail('InvalidResumeBinding');
  }
  return JSON.stringify({
    authorization_context_cid: binding.authorizationContextCid,
    environment_binding_cid: binding.environmentBindingCid,
  });
}

function declaredJson(results) {
  if (!Array.isArray(results) || results.length === 0 ||
      !results.every(text)) {
    fail('InvalidDeclaredResults');
  }
  return JSON.stringify(results);
}

function effectsJson(effects) {
  if (!Array.isArray(effects) || !effects.every(text) ||
      new Set(effects).size !== effects.length) {
    fail('InvalidUnknownEffects');
  }
  return JSON.stringify(effects);
}

// Exact decision-subject binding stored next to a Checkpoint (for example
// the gate's digest of the ten-field decision subject). Optional: '' when the
// Checkpoint was persisted without one.
function subjectBinding(value) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/.test(value)) {
    fail('InvalidDecisionSubjectBinding');
  }
  return value;
}

// Safe inspection view: identities, the review subject reference, and the
// non-restricted metadata sealed in the Checkpoint. No review projection
// contents, evidence, or Host authority configuration are returned.
function checkpointView(wire, row) {
  const artifact = JSON.parse(wire);
  return Object.freeze({
    checkpointCid: artifact.checkpoint_cid,
    checkpointId: artifact.checkpoint_id,
    runId: artifact.run_id ?? null,
    runDefinitionCid: artifact.run_definition_cid ?? null,
    prepareAttemptId: artifact.subject.prepare_attempt_id ?? null,
    subject: Object.freeze({...artifact.subject}),
    phase: artifact.phase,
    kind: artifact.kind,
    requiredArtifact: Object.freeze({
      type: artifact.required_artifact.artifact_type,
      cid: artifact.required_artifact.artifact_cid,
    }),
    reviewProjectionCid: artifact.review_projection_cid,
    requirements: Object.freeze([...artifact.requirements]),
    reasonCode: artifact.reason_code,
    humanSummary: artifact.human_summary,
    createdAt: artifact.created_at,
    expiresAt: artifact.expires_at,
    decisionSubjectCid: row.decision_subject_cid === '' ? null :
      row.decision_subject_cid,
    closure: row.closure,
    resolutionCid: row.resolution_cid === '' ? null : row.resolution_cid,
  });
}

function preparationView(row) {
  return Object.freeze({
    prepareAttemptId: row.prepare_attempt_id,
    status: row.status,
    version: Number(row.version),
    checkpointCid: row.checkpoint_cid === '' ? null : row.checkpoint_cid,
    runId: row.run_id === '' ? null : row.run_id,
    endReason: row.end_reason === '' ? null : row.end_reason,
    terminalErrorCode: row.terminal_error_code === '' ? null :
      row.terminal_error_code,
  });
}

export function openSqliteCheckpointJournal(root, {
  runtime,
  authorizeResolution,
  attestResolution,
  now = () => Date.now(),
  faults = {},
} = {}) {
  if (!text(root) || runtime === null || typeof runtime !== 'object' ||
      typeof runtime.checkpointSealBody !== 'function' ||
      typeof authorizeResolution !== 'function' ||
      typeof attestResolution !== 'function' || typeof now !== 'function') {
    fail('InvalidCheckpointJournalConfiguration');
  }
  const fault = step => {
    if (typeof faults.beforeCommit === 'function') faults.beforeCommit(step);
  };
  mkdirSync(root, {recursive: true, mode: 0o700});
  const path = join(realpathSync(root), 'checkpoint-journal.sqlite3');
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  let closed = false;
  try {
    // Several Host processes (run, approve, resume) share one journal; a
    // writer waits for the current transaction instead of failing.
    database.exec('PRAGMA busy_timeout = 10000');
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
    database.exec(`
      CREATE TABLE IF NOT EXISTS journal_metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS runs (
        run_id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL,
        version INTEGER NOT NULL CHECK (version >= 1),
        updated_at TEXT NOT NULL,
        declared_results_json TEXT NOT NULL,
        checkpoint_cid TEXT NOT NULL DEFAULT '',
        run_state_wire TEXT NOT NULL DEFAULT ''
      ) STRICT;
      CREATE TABLE IF NOT EXISTS preparations (
        prepare_attempt_id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL CHECK (status IN
          ('waiting_checkpoint', 'resuming', 'run_created', 'ended')),
        version INTEGER NOT NULL CHECK (version >= 1),
        updated_at TEXT NOT NULL,
        declared_results_json TEXT NOT NULL,
        checkpoint_cid TEXT NOT NULL DEFAULT '',
        run_id TEXT NOT NULL DEFAULT '',
        end_reason TEXT NOT NULL DEFAULT '',
        terminal_error_code TEXT NOT NULL DEFAULT ''
      ) STRICT;
      CREATE TABLE IF NOT EXISTS checkpoints (
        checkpoint_cid TEXT PRIMARY KEY NOT NULL,
        checkpoint_id TEXT NOT NULL,
        run_id TEXT REFERENCES runs (run_id),
        prepare_attempt_id TEXT REFERENCES preparations (prepare_attempt_id),
        checkpoint_wire TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        authorities_json TEXT NOT NULL,
        binding_json TEXT NOT NULL,
        decision_subject_cid TEXT NOT NULL DEFAULT '',
        closure TEXT NOT NULL
          CHECK (closure IN ('open', 'resolved', 'expired', 'cancelled')),
        resolution_cid TEXT NOT NULL DEFAULT '',
        persisted_at TEXT NOT NULL,
        closed_at TEXT NOT NULL DEFAULT '',
        CHECK ((run_id IS NULL) != (prepare_attempt_id IS NULL)),
        UNIQUE (run_id, checkpoint_id),
        UNIQUE (prepare_attempt_id, checkpoint_id)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS resolutions (
        resolution_cid TEXT PRIMARY KEY NOT NULL,
        checkpoint_cid TEXT NOT NULL UNIQUE
          REFERENCES checkpoints (checkpoint_cid),
        decision TEXT NOT NULL CHECK (decision IN ('approved', 'rejected')),
        verified_resolution_cid TEXT NOT NULL UNIQUE,
        verified_resolution_wire TEXT NOT NULL,
        committed_at TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS resume_intents (
        intent_id TEXT PRIMARY KEY NOT NULL,
        checkpoint_cid TEXT NOT NULL UNIQUE
          REFERENCES checkpoints (checkpoint_cid),
        resolution_cid TEXT NOT NULL UNIQUE
          REFERENCES resolutions (resolution_cid),
        run_id TEXT REFERENCES runs (run_id),
        prepare_attempt_id TEXT REFERENCES preparations (prepare_attempt_id),
        state TEXT NOT NULL CHECK (state IN ('pending', 'claimed', 'completed')),
        generation INTEGER NOT NULL CHECK (generation >= 0),
        claimant TEXT NOT NULL DEFAULT '',
        lease_expires_ms INTEGER NOT NULL DEFAULT 0,
        outcome_status TEXT NOT NULL DEFAULT '',
        completed_at TEXT NOT NULL DEFAULT '',
        CHECK ((run_id IS NULL) != (prepare_attempt_id IS NULL))
      ) STRICT;
    `);
    transaction(database, () => {
      // A journal created before the decision-subject binding column gains
      // it with the empty (unbound) value.
      const columns = database.prepare('PRAGMA table_info(checkpoints)').all();
      if (!columns.some(column => column.name === 'decision_subject_cid')) {
        database.exec(`ALTER TABLE checkpoints ADD COLUMN
          decision_subject_cid TEXT NOT NULL DEFAULT ''`);
      }
      const row = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (row === undefined) {
        database.prepare(
          'INSERT INTO journal_metadata (key, value) VALUES (?, ?)',
        ).run('schema_version', SCHEMA_VERSION);
      } else if (row.value !== SCHEMA_VERSION) {
        fail('UnsupportedCheckpointJournal');
      }
    });
  } catch (error) {
    database.close();
    throw error;
  }

  const statements = {
    run: database.prepare('SELECT * FROM runs WHERE run_id = ?'),
    insertRun: database.prepare(`
      INSERT INTO runs (run_id, status, version, updated_at,
        declared_results_json, checkpoint_cid)
      VALUES (?, ?, 1, ?, ?, ?)`),
    // Compare-and-swap on the Run version and prior status.
    moveRun: database.prepare(`
      UPDATE runs SET status = ?, version = version + 1, updated_at = ?,
        checkpoint_cid = ?, run_state_wire = ?
      WHERE run_id = ? AND version = ? AND status = ?`),
    preparation: database.prepare(
      'SELECT * FROM preparations WHERE prepare_attempt_id = ?'),
    insertPreparation: database.prepare(`
      INSERT INTO preparations (prepare_attempt_id, status, version,
        updated_at, declared_results_json, checkpoint_cid)
      VALUES (?, 'waiting_checkpoint', 1, ?, ?, ?)`),
    // Compare-and-swap on the preparation version and prior status.
    movePreparation: database.prepare(`
      UPDATE preparations SET status = ?, version = version + 1,
        updated_at = ?, checkpoint_cid = ?, run_id = ?, end_reason = ?,
        terminal_error_code = ?
      WHERE prepare_attempt_id = ? AND version = ? AND status = ?`),
    checkpoint: database.prepare(
      'SELECT * FROM checkpoints WHERE checkpoint_cid = ?'),
    checkpointById: database.prepare(
      'SELECT * FROM checkpoints WHERE checkpoint_id = ? ORDER BY persisted_at'),
    insertCheckpoint: database.prepare(`
      INSERT INTO checkpoints (checkpoint_cid, checkpoint_id, run_id,
        prepare_attempt_id, checkpoint_wire, expires_at, authorities_json,
        binding_json, decision_subject_cid, closure, persisted_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?)`),
    closeCheckpoint: database.prepare(`
      UPDATE checkpoints SET closure = ?, resolution_cid = ?, closed_at = ?
      WHERE checkpoint_cid = ? AND closure = 'open'`),
    pending: database.prepare(`
      SELECT c.* FROM checkpoints c
        LEFT JOIN runs r
          ON r.run_id = c.run_id AND r.checkpoint_cid = c.checkpoint_cid
        LEFT JOIN preparations p
          ON p.prepare_attempt_id = c.prepare_attempt_id
          AND p.checkpoint_cid = c.checkpoint_cid
      WHERE c.closure = 'open' AND (r.status = 'waiting_checkpoint'
        OR p.status = 'waiting_checkpoint')
      ORDER BY c.persisted_at, c.checkpoint_cid`),
    resolution: database.prepare(
      'SELECT * FROM resolutions WHERE checkpoint_cid = ?'),
    insertResolution: database.prepare(`
      INSERT INTO resolutions (resolution_cid, checkpoint_cid, decision,
        verified_resolution_cid, verified_resolution_wire, committed_at)
      VALUES (?, ?, ?, ?, ?, ?)`),
    // A Run or preparation may resume more than once; the latest intent is
    // the current one.
    intent: database.prepare(`
      SELECT * FROM resume_intents WHERE run_id = ?
      ORDER BY rowid DESC LIMIT 1`),
    preparationIntent: database.prepare(`
      SELECT * FROM resume_intents WHERE prepare_attempt_id = ?
      ORDER BY rowid DESC LIMIT 1`),
    intentByCheckpoint: database.prepare(
      'SELECT * FROM resume_intents WHERE checkpoint_cid = ?'),
    intentById: database.prepare(
      'SELECT * FROM resume_intents WHERE intent_id = ?'),
    insertIntent: database.prepare(`
      INSERT INTO resume_intents (intent_id, checkpoint_cid, resolution_cid,
        run_id, prepare_attempt_id, state, generation)
      VALUES (?, ?, ?, ?, ?, 'pending', 0)`),
    // Fenced by the generation read in the same transaction.
    claimIntent: database.prepare(`
      UPDATE resume_intents SET state = 'claimed', generation = ?,
        claimant = ?, lease_expires_ms = ?
      WHERE intent_id = ? AND generation = ? AND state != 'completed'`),
    renewIntent: database.prepare(`
      UPDATE resume_intents SET lease_expires_ms = ?
      WHERE intent_id = ? AND generation = ? AND claimant = ?
        AND state = 'claimed'`),
    completeIntent: database.prepare(`
      UPDATE resume_intents SET state = 'completed', generation = ?,
        claimant = ?, outcome_status = ?, completed_at = ?
      WHERE intent_id = ? AND generation = ? AND state != 'completed'`),
  };

  const alive = () => { if (closed) fail('CheckpointJournalClosed'); };
  const changed = (result, code) => {
    if (result.changes !== 1) fail(code);
  };
  const transitionAllowed = (from, to) => {
    if (!runtime.runTransitionAllowed(from, to)) fail('RunTransitionRejected');
  };
  const intentView = row => JSON.stringify({
    state: row.state,
    generation: Number(row.generation),
    claimant: row.claimant,
    lease_expires_ms: Number(row.lease_expires_ms),
  });

  // Run-state projection issued by the core from committed rows only.
  function projectRunState(runId) {
    const run = statements.run.get(runId);
    if (run === undefined) return undefined;
    let wire;
    if (run.status === 'waiting_checkpoint') {
      const row = statements.checkpoint.get(run.checkpoint_cid);
      if (row === undefined) fail('CheckpointJournalCorrupt');
      wire = core(runtime.checkpointWaitingState(
        row.checkpoint_wire, row.checkpoint_wire, run.updated_at,
        run.declared_results_json,
      ), 'CheckpointJournalCorrupt').run_state_wire;
    } else if (run.run_state_wire !== '') {
      wire = core(runtime.runStateAdmit(run.run_state_wire),
        'CheckpointJournalCorrupt').run_state_wire;
    } else {
      wire = core(runtime.checkpointLifecycleState(
        run.run_id, run.status, run.updated_at, run.declared_results_json,
      ), 'CheckpointJournalCorrupt').run_state_wire;
    }
    return Object.freeze({
      runId: run.run_id,
      status: run.status,
      version: Number(run.version),
      runStateWire: wire,
      runState: JSON.parse(wire),
    });
  }

  function projectPreparation(prepareAttemptId) {
    const row = statements.preparation.get(prepareAttemptId);
    return row === undefined ? undefined : preparationView(row);
  }

  function sealBody(body) {
    const bodyWire = typeof body === 'string' ? body : JSON.stringify(body);
    return core(runtime.checkpointSealBody(bodyWire), 'InvalidCheckpoint');
  }

  const isPreparation = sealed => sealed.subject_kind === 'prepare_attempt';

  function insertCheckpoint(sealed, authorities, binding, subject, at) {
    statements.insertCheckpoint.run(
      sealed.checkpoint_cid, sealed.checkpoint_id, sealed.run_id,
      sealed.prepare_attempt_id, sealed.checkpoint_wire, sealed.expires_at,
      authorities, binding, subject, at,
    );
  }

  // The next Checkpoint named by a resumed continuation's exit.
  function nextCheckpoint(checkpoint) {
    return {
      sealed: sealBody(checkpoint.body),
      reviewers: authoritiesJson(checkpoint.authorities),
      bound: bindingJson(checkpoint.binding),
      subject: subjectBinding(checkpoint.decisionSubjectCid),
    };
  }

  // Exit of a waiting Run whose Checkpoint was rejected, expired or
  // cancelled without dispatching its continuation: `cancelled`, or
  // `needs_reconciliation` with a `reconcile` action over the earlier Effect
  // outcomes the Run owner still records as unknown.
  function waitingExit(run, unknown, at) {
    const exit = core(runtime.waitingExitState(run.run_id, at,
      run.declared_results_json, unknown), 'InvalidRunState');
    transitionAllowed('waiting_checkpoint', exit.run_status);
    changed(statements.moveRun.run(exit.run_status, at, '',
      exit.run_status === 'cancelled' ? '' : exit.run_state_wire, run.run_id,
      run.version, 'waiting_checkpoint'), 'RunStateConflict');
    return exit.run_status;
  }

  // Unknown Effects of one Run as the Host reports them: an array, or a
  // function or object keyed by Run id (for a sweep over several Runs).
  function unknownOf(unknownEffects, runId) {
    const value = typeof unknownEffects === 'function'
      ? unknownEffects(runId)
      : Array.isArray(unknownEffects) ? unknownEffects
        : unknownEffects?.[runId];
    return effectsJson(value ?? []);
  }

  // After commit: the waiting projection is issued only from the exact wire
  // read back from the committed row. A preparation Checkpoint has no Run
  // state; its waiting state is the committed preparation row.
  function waitingAfterCommit(sealed) {
    const row = statements.checkpoint.get(sealed.checkpoint_cid);
    if (row === undefined) fail('CheckpointNotPersisted');
    const identity = {
      checkpointCid: sealed.checkpoint_cid,
      checkpointId: sealed.checkpoint_id,
      runId: sealed.run_id,
      prepareAttemptId: sealed.prepare_attempt_id,
    };
    if (isPreparation(sealed)) {
      core(runtime.checkpointAdmit(row.checkpoint_wire),
        'CheckpointNotPersisted');
      return Object.freeze({...identity,
        preparation: projectPreparation(sealed.prepare_attempt_id)});
    }
    const run = statements.run.get(sealed.run_id);
    if (run === undefined) fail('CheckpointNotPersisted');
    if (run.status !== 'waiting_checkpoint' ||
        run.checkpoint_cid !== sealed.checkpoint_cid) {
      // Idempotent retry of an already answered Checkpoint: report the
      // current committed state, never a stale waiting claim.
      const current = projectRunState(sealed.run_id);
      return Object.freeze({...identity,
        runStateWire: current.runStateWire, runState: current.runState});
    }
    const wire = core(runtime.checkpointWaitingState(
      sealed.checkpoint_wire, row.checkpoint_wire, run.updated_at,
      run.declared_results_json,
    ), 'CheckpointNotPersisted').run_state_wire;
    return Object.freeze({...identity,
      runStateWire: wire, runState: JSON.parse(wire)});
  }

  function expireLocked(row, at, unknown = '[]') {
    changed(statements.closeCheckpoint.run('expired', '', at,
      row.checkpoint_cid), 'CheckpointAlreadyClosed');
    if (row.prepare_attempt_id !== null) {
      const preparation = statements.preparation.get(row.prepare_attempt_id);
      if (preparation?.status === 'waiting_checkpoint' &&
          preparation.checkpoint_cid === row.checkpoint_cid) {
        changed(statements.movePreparation.run('ended', at, '', '', 'expired',
          '', preparation.prepare_attempt_id, preparation.version,
          'waiting_checkpoint'), 'PreparationStateConflict');
      }
      return;
    }
    const run = statements.run.get(row.run_id);
    if (run?.status === 'waiting_checkpoint' &&
        run.checkpoint_cid === row.checkpoint_cid) {
      waitingExit(run, unknown, at);
    }
  }

  // Host authorization port: it verifies proof.signature (Ed25519) over the
  // core-computed unsigned Resolution CID text with Host-trusted keys and
  // reports the exact text it verified.
  async function authenticate(checkpointWire, resolutionWire,
    approvalEvidenceWire) {
    const {preimage} = core(runtime.resolutionProofPreimage(resolutionWire),
      'InvalidResolution');
    let authentication;
    try {
      authentication = await authorizeResolution(Object.freeze({
        checkpointWire,
        resolutionWire,
        approvalEvidenceWire,
        proofPreimage: preimage,
      }));
    } catch (error) {
      fail('ResolutionAuthenticationFailed', error);
    }
    if (!text(authentication?.keyId) || !text(authentication?.reviewerId) ||
        !text(authentication?.authorityContextCid) ||
        !text(authentication?.policyCid) ||
        !text(authentication?.verifiedPreimage)) {
      fail('ResolutionAuthenticationFailed');
    }
    return JSON.stringify({
      key_id: authentication.keyId,
      reviewer_id: authentication.reviewerId,
      authority_context_cid: authentication.authorityContextCid,
      policy_cid: authentication.policyCid,
      proof_preimage: authentication.verifiedPreimage,
    });
  }

  // Host attestation port: Ed25519 over the unsigned verified-wrapper CID.
  async function attest(preimage) {
    const attestation = await attestResolution(preimage);
    if (!text(attestation?.hostKeyId) || !text(attestation?.signature)) {
      fail('InvalidHostAttestation');
    }
    return attestation;
  }

  function claimLocked(intent, claimant, at, current, leaseMs) {
    const checkpoint = statements.checkpoint.get(intent.checkpoint_cid);
    const decided = core(runtime.resumeClaimDecide(
      intentView(intent), claimant, at, leaseMs, checkpoint.binding_json,
      current,
    ), 'InvalidResumeClaim');
    return {checkpoint, decided};
  }

  return Object.freeze({
    path,

    // Seal and durably persist a deferred decision. The caller may report
    // a waiting Checkpoint only from the returned projection, which exists
    // only after the transaction committed. A Run-unit Checkpoint either
    // creates its Run or moves the tracked Run from `priorStatus`; a
    // preparation Checkpoint creates no Run.
    persistCheckpoint({
      body, priorStatus, declaredResults, authorities, binding,
      decisionSubjectCid,
    }) {
      alive();
      const sealed = sealBody(body);
      if (isPreparation(sealed)) {
        if (priorStatus !== undefined) fail('RunTransitionRejected');
      } else {
        if (priorStatus !== 'preparing' && priorStatus !== 'running') {
          fail('RunTransitionRejected');
        }
        transitionAllowed(priorStatus, 'waiting_checkpoint');
      }
      const reviewers = authoritiesJson(authorities);
      const bound = bindingJson(binding);
      const subject = subjectBinding(decisionSubjectCid);
      const declared = declaredJson(declaredResults);
      const at = iso(now());
      transaction(database, () => {
        const existing = statements.checkpoint.get(sealed.checkpoint_cid);
        if (existing !== undefined) {
          if (existing.checkpoint_wire !== sealed.checkpoint_wire ||
              existing.authorities_json !== reviewers ||
              existing.binding_json !== bound ||
              existing.decision_subject_cid !== subject) {
            fail('CheckpointConflict');
          }
          return;
        }
        if (isPreparation(sealed)) {
          if (statements.preparation.get(sealed.prepare_attempt_id) !==
              undefined) {
            fail('PreparationAlreadyTracked');
          }
          statements.insertPreparation.run(sealed.prepare_attempt_id, at,
            declared, sealed.checkpoint_cid);
        } else {
          const run = statements.run.get(sealed.run_id);
          if (run === undefined) {
            statements.insertRun.run(sealed.run_id, 'waiting_checkpoint', at,
              declared, sealed.checkpoint_cid);
          } else {
            if (run.status !== priorStatus) fail('RunStateConflict');
            changed(statements.moveRun.run('waiting_checkpoint', at,
              sealed.checkpoint_cid, '', run.run_id, run.version,
              priorStatus), 'RunStateConflict');
          }
        }
        insertCheckpoint(sealed, reviewers, bound, subject, at);
        fault('persistCheckpoint');
      });
      return waitingAfterCommit(sealed);
    },

    // Record a Run the Host created directly (for example an allowed
    // invocation). A Run created by a resumed preparation continuation uses
    // completeResume instead.
    createRun({runId, status = 'running', declaredResults}) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      if (status !== 'preparing' && status !== 'running') {
        fail('RunTransitionRejected');
      }
      const declared = declaredJson(declaredResults);
      const at = iso(now());
      transaction(database, () => {
        if (statements.run.get(runId) !== undefined) fail('RunAlreadyTracked');
        statements.insertRun.run(runId, status, at, declared, '');
        fault('createRun');
      });
      return projectRunState(runId);
    },

    // Exit of a Run that is not resuming (a resumed continuation exits
    // through completeResume). Compare-and-swap on the current status. A
    // `succeeded` exit without a continuation-issued state records that no
    // declared Result was published; any issued state is admitted by the core.
    finishRun(runId, {status, from = 'running', runStateWire}) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      if (!['succeeded', 'failed', 'needs_reconciliation', 'cancelled']
        .includes(status) || from === 'resuming') {
        fail('RunTransitionRejected');
      }
      transitionAllowed(from, status);
      const at = iso(now());
      transaction(database, () => {
        const run = statements.run.get(runId);
        if (run === undefined) fail('RunNotFound');
        if (run.status !== from) fail('RunStateConflict');
        let wire = '';
        if (text(runStateWire) || status === 'succeeded' ||
            status === 'needs_reconciliation') {
          let issued = runStateWire;
          if (!text(issued)) {
            if (status !== 'succeeded') fail('InvalidRunState');
            const running = JSON.parse(core(runtime.checkpointLifecycleState(
              runId, 'running', at, run.declared_results_json,
            ), 'InvalidRunState').run_state_wire);
            issued = JSON.stringify({...running, status});
          }
          const view = core(runtime.runStateAdmit(issued), 'InvalidRunState');
          if (view.run_id !== runId || view.status !== status ||
              view.checkpoint_cid !== null) {
            fail('InvalidRunState');
          }
          wire = view.run_state_wire;
        }
        changed(statements.moveRun.run(status, at, '', wire, runId,
          run.version, from), 'RunStateConflict');
        fault('finishRun');
      });
      return projectRunState(runId);
    },

    // Cancel a waiting Checkpoint without dispatching its continuation: the
    // Checkpoint closes as cancelled, a waiting preparation ends without a
    // Run and a waiting Run moves to `cancelled`, or to
    // `needs_reconciliation` over `unknownEffects` (earlier Effect outcomes
    // of the Run the Host still records as unknown). No resume intent exists
    // or is created. Repeating the cancel is idempotent; an answered or
    // expired Checkpoint is not cancelled.
    cancelCheckpoint(reference, {unknownEffects = []} = {}) {
      alive();
      const unknown = effectsJson(unknownEffects);
      const at = iso(now());
      return transaction(database, () => {
        const row = rowFor(reference);
        if (row === undefined) fail('CheckpointNotFound');
        if (row.closure === 'cancelled') {
          return Object.freeze({outcome: 'duplicate', checkpointCid:
            row.checkpoint_cid});
        }
        if (row.closure !== 'open') {
          return Object.freeze({outcome: 'not_open', closure: row.closure,
            checkpointCid: row.checkpoint_cid});
        }
        changed(statements.closeCheckpoint.run('cancelled', '', at,
          row.checkpoint_cid), 'CheckpointAlreadyClosed');
        let runStatus;
        if (row.prepare_attempt_id !== null) {
          // A preparation precedes its Run and has no Effect outcomes.
          if (unknown !== '[]') fail('InvalidUnknownEffects');
          const preparation = statements.preparation.get(row.prepare_attempt_id);
          if (preparation?.status !== 'waiting_checkpoint' ||
              preparation.checkpoint_cid !== row.checkpoint_cid) {
            fail('PreparationStateConflict');
          }
          changed(statements.movePreparation.run('ended', at, '', '',
            'cancelled', '', preparation.prepare_attempt_id,
            preparation.version, 'waiting_checkpoint'),
          'PreparationStateConflict');
        } else {
          const run = statements.run.get(row.run_id);
          if (run?.status !== 'waiting_checkpoint' ||
              run.checkpoint_cid !== row.checkpoint_cid) {
            fail('RunStateConflict');
          }
          runStatus = waitingExit(run, unknown, at);
        }
        fault('cancelCheckpoint');
        return Object.freeze({outcome: 'cancelled',
          checkpointCid: row.checkpoint_cid,
          ...(row.run_id !== null ? {runId: row.run_id, runStatus} :
            {prepareAttemptId: row.prepare_attempt_id})});
      });
    },

    listPending() {
      alive();
      return statements.pending.all().map(row => {
        core(runtime.checkpointAdmit(row.checkpoint_wire),
          'CheckpointJournalCorrupt');
        return checkpointView(row.checkpoint_wire, row);
      });
    },

    inspect(reference) {
      alive();
      const row = rowFor(reference);
      if (row === undefined) return undefined;
      core(runtime.checkpointAdmit(row.checkpoint_wire),
        'CheckpointJournalCorrupt');
      return checkpointView(row.checkpoint_wire, row);
    },

    getRunState(runId) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      return projectRunState(runId);
    },

    // The committed answer of one Checkpoint: decision, actor and the
    // Resolution identities. Evidence and review contents are not returned.
    resolutionOf(reference) {
      alive();
      const row = rowFor(reference);
      if (row === undefined) return undefined;
      const stored = statements.resolution.get(row.checkpoint_cid);
      if (stored === undefined) return undefined;
      const verified = JSON.parse(stored.verified_resolution_wire);
      return Object.freeze({
        checkpointCid: row.checkpoint_cid,
        decision: stored.decision,
        actor: verified.resolution.actor,
        resolutionCid: stored.resolution_cid,
        verifiedResolutionCid: stored.verified_resolution_cid,
      });
    },

    getPreparation(prepareAttemptId) {
      alive();
      if (!text(prepareAttemptId)) fail('InvalidPrepareAttemptId');
      return projectPreparation(prepareAttemptId);
    },

    // Admit, attest, and commit one Resolution. Resolution storage,
    // Checkpoint closure, the Run or preparation transition and the unique
    // resume intent commit in one transaction. `unknownEffects` are the
    // earlier Effect outcomes of the Run the Host still records as unknown:
    // a rejection (or an expiry found here) then moves the waiting Run to
    // `needs_reconciliation` instead of `cancelled`, without a resume intent.
    async submitResolution({
      checkpointCid, resolutionWire, approvalEvidenceWire = '',
      unknownEffects = [],
    }) {
      alive();
      if (!text(checkpointCid) || !text(resolutionWire) ||
          typeof approvalEvidenceWire !== 'string') {
        fail('InvalidResolutionSubmission');
      }
      const unknown = effectsJson(unknownEffects);
      const row = statements.checkpoint.get(checkpointCid);
      if (row === undefined) fail('CheckpointNotFound');
      if (row.prepare_attempt_id !== null && unknown !== '[]') {
        fail('InvalidUnknownEffects');
      }
      const verifiedAt = iso(now());
      const authJson = await authenticate(row.checkpoint_wire, resolutionWire,
        approvalEvidenceWire);
      const admitted = core(runtime.resolutionAdmit(
        row.checkpoint_wire, resolutionWire, approvalEvidenceWire, authJson,
        row.authorities_json, verifiedAt,
      ), 'InvalidResolution');
      const attestation = await attest(admitted.attestation_preimage);
      alive();
      const outcome = transaction(database, () => {
        const current = statements.checkpoint.get(checkpointCid);
        // A cancelled Checkpoint admits no Resolution and no resume intent.
        if (current.closure === 'cancelled') return {kind: 'cancelled'};
        const decided = core(runtime.resolutionDecide(
          current.checkpoint_wire, resolutionWire, approvalEvidenceWire,
          authJson, current.authorities_json, verifiedAt,
          attestation.hostKeyId, attestation.signature, current.closure,
          current.resolution_cid, unknown,
        ), 'InvalidResolution');
        if (decided.action === 'duplicate') {
          return {kind: 'duplicate', decided};
        }
        if (decided.action === 'conflict') {
          return {kind: 'conflict'};
        }
        if (decided.action === 'expired') {
          if (current.closure === 'open') {
            expireLocked(current, verifiedAt, unknown);
          }
          return {kind: 'expired'};
        }
        if (decided.effect === 'move_run') {
          const run = statements.run.get(current.run_id);
          if (run?.status !== 'waiting_checkpoint' ||
              run.checkpoint_cid !== checkpointCid) {
            fail('RunStateConflict');
          }
          if (decided.decision === 'approved') {
            transitionAllowed('waiting_checkpoint', decided.run_status);
            changed(statements.moveRun.run(decided.run_status, verifiedAt, '',
              '', run.run_id, run.version, 'waiting_checkpoint'),
            'RunStateConflict');
          } else if (waitingExit(run, unknown, verifiedAt) !==
              decided.run_status) {
            fail('RunTransitionRejected');
          }
        } else {
          const preparation = statements.preparation.get(
            current.prepare_attempt_id);
          if (preparation?.status !== 'waiting_checkpoint' ||
              preparation.checkpoint_cid !== checkpointCid) {
            fail('PreparationStateConflict');
          }
          // Approval continues the same attempt; rejection ends it and no
          // Run is ever created for it.
          const [status, reason] = decided.effect === 'continue_preparation' ?
            ['resuming', ''] : ['ended', 'rejected'];
          changed(statements.movePreparation.run(status, verifiedAt, '', '',
            reason, '', preparation.prepare_attempt_id, preparation.version,
            'waiting_checkpoint'), 'PreparationStateConflict');
        }
        statements.insertResolution.run(
          decided.resolution_cid, checkpointCid, decided.decision,
          decided.verified_resolution_cid, decided.verified_resolution_wire,
          verifiedAt,
        );
        changed(statements.closeCheckpoint.run('resolved',
          decided.resolution_cid, verifiedAt, checkpointCid),
        'CheckpointAlreadyClosed');
        if (decided.decision === 'approved') {
          statements.insertIntent.run(decided.resume_intent_id,
            checkpointCid, decided.resolution_cid, current.run_id,
            current.prepare_attempt_id);
        }
        fault('submitResolution');
        return {kind: 'committed', decided};
      });
      if (outcome.kind === 'conflict') fail('CheckpointResolutionConflict');
      if (outcome.kind === 'cancelled') fail('CheckpointCancelled');
      if (outcome.kind === 'expired') fail('CheckpointExpired');
      const stored = statements.resolution.get(checkpointCid);
      const intent = statements.intentByCheckpoint.get(checkpointCid);
      return Object.freeze({
        outcome: outcome.kind,
        decision: stored.decision,
        resolutionCid: stored.resolution_cid,
        verifiedResolutionCid: stored.verified_resolution_cid,
        verifiedResolutionWire: stored.verified_resolution_wire,
        resumeIntentId: intent?.intent_id ?? null,
        ...(row.run_id !== null ?
          {runState: projectRunState(row.run_id)} :
          {preparation: projectPreparation(row.prepare_attempt_id)}),
      });
    },

    // Answer several pending Checkpoints in one Host operation. Each item is
    // admitted independently as the answer to its own exact Checkpoint: its
    // own Resolution, authentication, attestation and one atomic commit of
    // Resolution, closure, transition and resume intent. An item never
    // covers another Checkpoint, and an invalid item neither blocks nor alters
    // the others. Results are per item, in input order.
    async submitResolutions(items) {
      alive();
      if (!Array.isArray(items) || items.length === 0) {
        fail('InvalidResolutionSubmission');
      }
      const results = [];
      for (const item of items) {
        const checkpointCid = item?.checkpointCid;
        try {
          const committed = await this.submitResolution(item);
          results.push(Object.freeze({
            checkpointCid,
            status: committed.outcome === 'duplicate' ? 'duplicate' : 'committed',
            decision: committed.decision,
            resolutionCid: committed.resolutionCid,
            resumeIntentId: committed.resumeIntentId,
          }));
        } catch (error) {
          if (error?.code === 'CheckpointJournalClosed') throw error;
          const status = {
            CheckpointResolutionConflict: 'conflicting',
            CheckpointExpired: 'expired',
            CheckpointCancelled: 'cancelled',
          }[error?.code] ?? 'invalid';
          results.push(Object.freeze({
            checkpointCid,
            status,
            reason: String(error?.code ?? 'InvalidResolutionSubmission'),
            ...(error?.cause !== undefined ?
              {detail: String(error.cause?.message ?? error.cause)} : {}),
          }));
        }
      }
      return Object.freeze(results);
    },

    // Admit an immediate delegated permit or reject against the exact
    // Checkpoint body the Host would persist if it deferred. Nothing is
    // persisted: no Checkpoint, no waiting state and no resume intent. The
    // returned verified Resolution is the decision evidence the Host retains
    // with the permitted or rejected unit.
    async admitImmediateResolution({
      body, resolutionWire, approvalEvidenceWire = '', authorities,
    }) {
      alive();
      if (!text(resolutionWire) || typeof approvalEvidenceWire !== 'string') {
        fail('InvalidResolutionSubmission');
      }
      const bodyWire = typeof body === 'string' ? body : JSON.stringify(body);
      const subject = sealBody(bodyWire);
      const reviewers = authoritiesJson(authorities);
      const verifiedAt = iso(now());
      const authJson = await authenticate(subject.checkpoint_wire,
        resolutionWire, approvalEvidenceWire);
      const admitted = core(runtime.resolutionAdmitImmediate(
        bodyWire, resolutionWire, approvalEvidenceWire, authJson, reviewers,
        verifiedAt,
      ), 'InvalidResolution');
      const attestation = await attest(admitted.attestation_preimage);
      const sealed = core(runtime.resolutionSealImmediate(
        bodyWire, resolutionWire, approvalEvidenceWire, authJson, reviewers,
        verifiedAt, attestation.hostKeyId, attestation.signature,
      ), 'InvalidResolution');
      return Object.freeze({
        checkpointCid: sealed.checkpoint_cid,
        decision: sealed.decision,
        resolutionCid: sealed.resolution_cid,
        verifiedResolutionCid: sealed.verified_resolution_cid,
        verifiedResolutionWire: sealed.verified_resolution_wire,
      });
    },

    // Claim the unique resume intent of a Run with a strictly higher fencing
    // generation. Bound authorization-context and environment-binding CIDs
    // are revalidated here, before any continuation dispatch. If they no
    // longer revalidate, nothing is dispatched and the Run exits `resuming`
    // to `failed`, or to `needs_reconciliation` over `unknownEffects`, with
    // terminal_error.code ACTQL_E_RESUME_REVALIDATION_FAILED.
    claimResume(runId, {claimant, leaseMs, binding, unknownEffects = []}) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      const current = bindingJson(binding);
      const unknown = effectsJson(unknownEffects);
      const at = now();
      return transaction(database, () => {
        const intent = statements.intent.get(runId);
        if (intent === undefined) fail('ResumeIntentNotFound');
        const {checkpoint, decided} = claimLocked(intent, claimant, at,
          current, leaseMs);
        if (decided.action === 'busy' || decided.action === 'completed') {
          return Object.freeze({action: decided.action});
        }
        const run = statements.run.get(runId);
        if (run?.status !== 'resuming') fail('RunStateConflict');
        if (decided.action === 'invalidated') {
          const failed = core(runtime.revalidationFailedState(runId, iso(at),
            run.declared_results_json, unknown), 'InvalidResumeClaim');
          transitionAllowed('resuming', failed.run_status);
          changed(statements.completeIntent.run(decided.generation, claimant,
            failed.run_status, iso(at), intent.intent_id, intent.generation),
          'ResumeClaimStale');
          changed(statements.moveRun.run(failed.run_status, iso(at), '',
            failed.run_state_wire, runId, run.version, 'resuming'),
          'RunStateConflict');
          fault('claimResume');
          return Object.freeze({
            action: 'invalidated',
            runStatus: failed.run_status,
            terminalErrorCode: failed.terminal_error_code,
          });
        }
        changed(statements.claimIntent.run(decided.generation, claimant,
          decided.lease_expires_ms, intent.intent_id, intent.generation),
        'ResumeClaimStale');
        fault('claimResume');
        const artifact = JSON.parse(checkpoint.checkpoint_wire);
        return Object.freeze({
          action: 'claimed',
          claim: Object.freeze({
            intentId: intent.intent_id,
            runId,
            claimant,
            generation: decided.generation,
            leaseExpiresMs: decided.lease_expires_ms,
          }),
          checkpointCid: checkpoint.checkpoint_cid,
          continuationStateCid: artifact.continuation_state_cid,
          runDefinitionCid: artifact.run_definition_cid,
          subject: Object.freeze({...artifact.subject}),
        });
      });
    },

    // Claim the resume intent of an approved preparation Checkpoint. A failed
    // revalidation dispatches nothing and ends the preparation without
    // creating a Run.
    claimPreparationResume(prepareAttemptId, {claimant, leaseMs, binding}) {
      alive();
      if (!text(prepareAttemptId)) fail('InvalidPrepareAttemptId');
      const current = bindingJson(binding);
      const at = now();
      return transaction(database, () => {
        const intent = statements.preparationIntent.get(prepareAttemptId);
        if (intent === undefined) fail('ResumeIntentNotFound');
        const {checkpoint, decided} = claimLocked(intent, claimant, at,
          current, leaseMs);
        if (decided.action === 'busy' || decided.action === 'completed') {
          return Object.freeze({action: decided.action});
        }
        const preparation = statements.preparation.get(prepareAttemptId);
        if (preparation?.status !== 'resuming') {
          fail('PreparationStateConflict');
        }
        if (decided.action === 'invalidated') {
          const code = runtime.resumeRevalidationFailedCode();
          changed(statements.completeIntent.run(decided.generation, claimant,
            'revalidation_failed', iso(at), intent.intent_id,
            intent.generation), 'ResumeClaimStale');
          changed(statements.movePreparation.run('ended', iso(at), '', '',
            'revalidation_failed', code, prepareAttemptId, preparation.version,
            'resuming'), 'PreparationStateConflict');
          fault('claimResume');
          return Object.freeze({
            action: 'invalidated',
            runCreated: false,
            terminalErrorCode: code,
          });
        }
        changed(statements.claimIntent.run(decided.generation, claimant,
          decided.lease_expires_ms, intent.intent_id, intent.generation),
        'ResumeClaimStale');
        fault('claimResume');
        const artifact = JSON.parse(checkpoint.checkpoint_wire);
        return Object.freeze({
          action: 'claimed',
          claim: Object.freeze({
            intentId: intent.intent_id,
            prepareAttemptId,
            claimant,
            generation: decided.generation,
            leaseExpiresMs: decided.lease_expires_ms,
          }),
          checkpointCid: checkpoint.checkpoint_cid,
          continuationStateCid: artifact.continuation_state_cid,
          subject: Object.freeze({...artifact.subject}),
        });
      });
    },

    renewResume(claim, leaseMs) {
      alive();
      if (!Number.isSafeInteger(leaseMs) || leaseMs <= 0) fail('InvalidLease');
      const at = now();
      return transaction(database, () => {
        const intent = statements.intentById.get(claim?.intentId ?? '');
        if (intent === undefined) fail('ResumeClaimStale');
        const fence = core(runtime.resumeFenceDecide(intentView(intent),
          claim.claimant, claim.generation, at), 'ResumeClaimStale');
        if (fence.action !== 'current') fail('ResumeClaimStale');
        changed(statements.renewIntent.run(at + leaseMs, intent.intent_id,
          claim.generation, claim.claimant), 'ResumeClaimStale');
        return Object.freeze({...claim, leaseExpiresMs: at + leaseMs});
      });
    },

    // Complete the resume intent together with the resumed continuation's
    // exit. For a Run the outcome is one of: {runStateWire} for a
    // continuation-issued state, {status: 'failed' | 'cancelled'}, or
    // {checkpoint: {...}} for the next Checkpoint of the same Run. For a
    // preparation it is one of: {run: {runId, status}} to create the Run
    // (status 'preparing' or 'running'), {status: 'failed' | 'cancelled'} to
    // end without a Run, or {checkpoint: {...}} for the next preparation
    // Checkpoint of the same attempt.
    completeResume(claim, outcome) {
      alive();
      if (!text(claim?.intentId) || !text(claim?.claimant) ||
          !Number.isSafeInteger(claim?.generation)) {
        fail('ResumeClaimStale');
      }
      if (text(claim.prepareAttemptId)) {
        return completePreparation(claim, outcome);
      }
      let target;
      let runStateWire = '';
      let next;
      if (outcome?.checkpoint !== undefined) {
        next = nextCheckpoint(outcome.checkpoint);
        if (next.sealed.run_id !== claim.runId) fail('CheckpointRunMismatch');
        target = 'waiting_checkpoint';
      } else if (text(outcome?.runStateWire)) {
        const view = core(runtime.runStateAdmit(outcome.runStateWire),
          'InvalidRunState');
        if (view.run_id !== claim.runId || view.checkpoint_cid !== null) {
          fail('InvalidRunState');
        }
        target = view.status;
        runStateWire = view.run_state_wire;
      } else if (outcome?.status === 'failed' ||
          outcome?.status === 'cancelled') {
        target = outcome.status;
      } else {
        fail('InvalidResumeOutcome');
      }
      if (!runtime.resumeCompletionAllowed(target)) {
        fail('RunTransitionRejected');
      }
      const at = now();
      const atIso = iso(at);
      transaction(database, () => {
        const intent = fenced(claim, at);
        const run = statements.run.get(intent.run_id);
        if (run?.status !== 'resuming') fail('RunStateConflict');
        transitionAllowed('resuming', target);
        changed(statements.completeIntent.run(claim.generation,
          claim.claimant, target, atIso, intent.intent_id, claim.generation),
        'ResumeClaimStale');
        let checkpointCid = '';
        if (next !== undefined) {
          if (statements.checkpoint.get(next.sealed.checkpoint_cid) !==
              undefined) {
            fail('CheckpointConflict');
          }
          insertCheckpoint(next.sealed, next.reviewers, next.bound,
            next.subject, atIso);
          checkpointCid = next.sealed.checkpoint_cid;
        }
        changed(statements.moveRun.run(target, atIso, checkpointCid,
          runStateWire, run.run_id, run.version, 'resuming'),
        'RunStateConflict');
        fault('completeResume');
      });
      if (next !== undefined) return waitingAfterCommit(next.sealed);
      return projectRunState(claim.runId);
    },

    // Close every open Checkpoint whose expiration has been reached: a
    // waiting preparation ends and a waiting Run is cancelled, without
    // dispatch, or moves to `needs_reconciliation` when the Host reports
    // unknown earlier Effect outcomes for it. `unknownEffects` is a function
    // of the Run id or an object keyed by Run id.
    expire({unknownEffects} = {}) {
      alive();
      const at = iso(now());
      return transaction(database, () => {
        const expired = [];
        for (const row of statements.pending.all()) {
          const result = core(runtime.checkpointExpiredAt(row.checkpoint_wire,
            at), 'CheckpointJournalCorrupt');
          if (result.expired) {
            expireLocked(row, at, row.run_id === null ? '[]'
              : unknownOf(unknownEffects, row.run_id));
            expired.push(row.checkpoint_cid);
          }
        }
        fault('expire');
        return expired;
      });
    },

    close() {
      if (closed) return;
      closed = true;
      database.close();
    },
  });

  function rowFor(reference) {
    if (!text(reference)) fail('InvalidCheckpointReference');
    let row = statements.checkpoint.get(reference);
    if (row === undefined) {
      const rows = statements.checkpointById.all(reference);
      if (rows.length > 1) fail('AmbiguousCheckpointReference');
      row = rows[0];
    }
    return row;
  }

  // Only the current, unexpired claimant may complete an intent.
  function fenced(claim, at) {
    const intent = statements.intentById.get(claim.intentId);
    if (intent === undefined) fail('ResumeClaimStale');
    const fence = core(runtime.resumeFenceDecide(intentView(intent),
      claim.claimant, claim.generation, at), 'ResumeClaimStale');
    if (fence.action !== 'current') fail('ResumeClaimStale');
    return intent;
  }

  function completePreparation(claim, outcome) {
    let next;
    let run;
    let ended;
    if (outcome?.checkpoint !== undefined) {
      next = nextCheckpoint(outcome.checkpoint);
      if (next.sealed.prepare_attempt_id !== claim.prepareAttemptId) {
        fail('CheckpointPreparationMismatch');
      }
    } else if (outcome?.run !== undefined) {
      if (!text(outcome.run.runId) ||
          !['preparing', 'running'].includes(outcome.run.status)) {
        fail('InvalidResumeOutcome');
      }
      run = outcome.run;
    } else if (outcome?.status === 'failed' ||
        outcome?.status === 'cancelled') {
      ended = outcome.status;
    } else {
      fail('InvalidResumeOutcome');
    }
    const at = now();
    const atIso = iso(at);
    transaction(database, () => {
      const intent = fenced(claim, at);
      const preparation = statements.preparation.get(intent.prepare_attempt_id);
      if (preparation?.status !== 'resuming') fail('PreparationStateConflict');
      const exit = next !== undefined ? 'waiting_checkpoint' :
        run !== undefined ? 'run_created' : ended;
      changed(statements.completeIntent.run(claim.generation, claim.claimant,
        exit, atIso, intent.intent_id, claim.generation), 'ResumeClaimStale');
      const move = (status, checkpointCid, runId, reason) => changed(
        statements.movePreparation.run(status, atIso, checkpointCid, runId,
          reason, '', preparation.prepare_attempt_id, preparation.version,
          'resuming'), 'PreparationStateConflict');
      if (next !== undefined) {
        if (statements.checkpoint.get(next.sealed.checkpoint_cid) !==
            undefined) {
          fail('CheckpointConflict');
        }
        move('waiting_checkpoint', next.sealed.checkpoint_cid, '', '');
        insertCheckpoint(next.sealed, next.reviewers, next.bound, next.subject,
          atIso);
      } else if (run !== undefined) {
        // The approved preparation continuation creates the Run.
        if (statements.run.get(run.runId) !== undefined) {
          fail('RunAlreadyTracked');
        }
        statements.insertRun.run(run.runId, run.status, atIso,
          preparation.declared_results_json, '');
        move('run_created', '', run.runId, '');
      } else {
        move('ended', '', '', ended);
      }
      fault('completeResume');
    });
    if (next !== undefined) return waitingAfterCommit(next.sealed);
    return Object.freeze({
      preparation: projectPreparation(claim.prepareAttemptId),
      ...(run !== undefined ? {runState: projectRunState(run.runId)} : {}),
    });
  }
}
