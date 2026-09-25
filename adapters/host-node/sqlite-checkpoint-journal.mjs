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

// Claims the Host required of the decision when it deferred it, bound next to
// the Checkpoint: the decision request's own claims, never claims an answer
// establishes. Sorted and unique; '[]' when none were requested.
// The durable identity of one protected send, recorded with its admission;
// '' when the send has none.
function admissionIdentity(value) {
  if (value === undefined || value === null) return '';
  if (!text(value)) fail('InvalidDispatchIdentity');
  return value;
}

const priorAdmissionView = row => Object.freeze({
  generation: Number(row.generation),
  claimant: row.claimant,
  admittedAt: row.admitted_at,
  dispatchIdentity: row.dispatch_identity === '' ? null
    : row.dispatch_identity,
});

function requestedClaimsJson(value) {
  if (value === undefined || value === null) return '[]';
  if (!Array.isArray(value) || !value.every(text) ||
      new Set(value).size !== value.length) {
    fail('InvalidRequestedClaims');
  }
  return JSON.stringify([...value].sort());
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
    requestedClaims: Object.freeze(JSON.parse(row.requested_claims_json)),
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
        requested_claims_json TEXT NOT NULL DEFAULT '[]',
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
      CREATE TABLE IF NOT EXISTS resume_admissions (
        intent_id TEXT NOT NULL REFERENCES resume_intents (intent_id),
        generation INTEGER NOT NULL CHECK (generation >= 1),
        claimant TEXT NOT NULL,
        admitted_at TEXT NOT NULL,
        mode TEXT NOT NULL DEFAULT 'start'
          CHECK (mode IN ('start', 'reconcile')),
        dispatch_identity TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (intent_id, generation)
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
      // ... and the requested-claims binding with no requested claim.
      if (!columns.some(column => column.name === 'requested_claims_json')) {
        database.exec(`ALTER TABLE checkpoints ADD COLUMN
          requested_claims_json TEXT NOT NULL DEFAULT '[]'`);
      }
      // A resume admission recorded before the start/reconcile distinction
      // is a fresh start with no recorded dispatch identity.
      const admissionColumns = database.prepare(
        'PRAGMA table_info(resume_admissions)').all();
      if (!admissionColumns.some(column => column.name === 'mode')) {
        database.exec(`ALTER TABLE resume_admissions ADD COLUMN
          mode TEXT NOT NULL DEFAULT 'start'
          CHECK (mode IN ('start', 'reconcile'))`);
      }
      if (!admissionColumns.some(column => column.name ===
          'dispatch_identity')) {
        database.exec(`ALTER TABLE resume_admissions ADD COLUMN
          dispatch_identity TEXT NOT NULL DEFAULT ''`);
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
        binding_json, decision_subject_cid, requested_claims_json, closure,
        persisted_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?)`),
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
    // One protected dispatch admission per claim generation of an intent.
    enterAdmission: database.prepare(`
      INSERT INTO resume_admissions (intent_id, generation, claimant,
        admitted_at, mode, dispatch_identity)
      VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`),
    // The first protected dispatch started by an earlier claim generation of
    // the same intent: its physical outcome is unknown to a later claimant.
    priorAdmission: database.prepare(`
      SELECT generation, claimant, admitted_at, dispatch_identity
      FROM resume_admissions
      WHERE intent_id = ? AND generation < ? AND mode = 'start'
      ORDER BY generation LIMIT 1`),
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

  function insertCheckpoint(sealed, authorities, binding, subject, claims,
    at) {
    statements.insertCheckpoint.run(
      sealed.checkpoint_cid, sealed.checkpoint_id, sealed.run_id,
      sealed.prepare_attempt_id, sealed.checkpoint_wire, sealed.expires_at,
      authorities, binding, subject, claims, at,
    );
  }

  // The next Checkpoint named by a resumed continuation's exit.
  function nextCheckpoint(checkpoint) {
    return {
      sealed: sealBody(checkpoint.body),
      reviewers: authoritiesJson(checkpoint.authorities),
      bound: bindingJson(checkpoint.binding),
      subject: subjectBinding(checkpoint.decisionSubjectCid),
      claims: requestedClaimsJson(checkpoint.requestedClaims),
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
      decisionSubjectCid, requestedClaims,
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
      const claims = requestedClaimsJson(requestedClaims);
      const declared = declaredJson(declaredResults);
      const at = iso(now());
      transaction(database, () => {
        const existing = statements.checkpoint.get(sealed.checkpoint_cid);
        if (existing !== undefined) {
          if (existing.checkpoint_wire !== sealed.checkpoint_wire ||
              existing.authorities_json !== reviewers ||
              existing.binding_json !== bound ||
              existing.decision_subject_cid !== subject ||
              existing.requested_claims_json !== claims) {
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
        insertCheckpoint(sealed, reviewers, bound, subject, claims, at);
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
        // Authentication and attestation are asynchronous Host work: the
        // expiration decision uses the trusted time read again here, at the
        // commit boundary, never the time captured before that work.
        const committedAt = iso(now());
        if (current.closure === 'open' && core(runtime.checkpointExpiredAt(
          current.checkpoint_wire, committedAt), 'CheckpointJournalCorrupt')
          .expired) {
          expireLocked(current, committedAt, unknown);
          return {kind: 'expired'};
        }
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
        // An approval whose own permission already lapsed at the commit
        // boundary authorizes nothing: it is not committed, and the open
        // Checkpoint keeps waiting for an answer within its deadline.
        if (decided.action !== 'expired' && decided.decision === 'approved' &&
            !core(runtime.resumedApprovalAt(decided.verified_resolution_wire,
              committedAt), 'InvalidResolution').current) {
          return {kind: 'approval_expired'};
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
      if (outcome.kind === 'approval_expired') fail('ApprovalExpired');
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

    // Committed resume state of one Checkpoint, read from journal rows only:
    // its current resume intent (state, claimant, generation, lease), the
    // committed Resolution and the requested claims bound when it deferred.
    // Undefined when the Checkpoint has no resume intent.
    currentResume(checkpointCid) {
      alive();
      if (!text(checkpointCid)) fail('InvalidCheckpointReference');
      const intent = statements.intentByCheckpoint.get(checkpointCid);
      if (intent === undefined) return undefined;
      const checkpoint = statements.checkpoint.get(checkpointCid);
      const stored = statements.resolution.get(checkpointCid);
      return Object.freeze({
        checkpointCid,
        intentId: intent.intent_id,
        runId: intent.run_id,
        prepareAttemptId: intent.prepare_attempt_id,
        state: intent.state,
        claimant: intent.claimant,
        generation: Number(intent.generation),
        leaseExpiresMs: Number(intent.lease_expires_ms),
        resolutionCid: intent.resolution_cid,
        decision: stored?.decision ?? null,
        verifiedResolutionCid: stored?.verified_resolution_cid ?? null,
        closure: checkpoint.closure,
        decisionSubjectCid: checkpoint.decision_subject_cid === '' ? null :
          checkpoint.decision_subject_cid,
        requestedClaims: Object.freeze(
          JSON.parse(checkpoint.requested_claims_json)),
      });
    },

    // The committed approval of one resolved Checkpoint and whether its own
    // permission is still current at the Host trusted time. Read from
    // committed rows only; used for approvals an attempt answered earlier
    // than the Checkpoint its current claim resumes (each approval is
    // checked on its own, never through a later one).
    committedApprovalAt(checkpointCid) {
      alive();
      if (!text(checkpointCid)) fail('InvalidCheckpointReference');
      const atIso = iso(now());
      const checkpoint = statements.checkpoint.get(checkpointCid);
      const stored = statements.resolution.get(checkpointCid);
      if (checkpoint?.closure !== 'resolved' || stored?.decision !== 'approved' ||
          checkpoint.resolution_cid !== stored.resolution_cid) {
        fail('ResolutionNotCommitted');
      }
      const approval = core(runtime.resumedApprovalAt(
        stored.verified_resolution_wire, atIso), 'ResolutionNotCommitted');
      if (approval.checkpoint_cid !== checkpointCid ||
          approval.resolution_cid !== stored.resolution_cid) {
        fail('ResolutionNotCommitted');
      }
      return Object.freeze({
        checkpointCid,
        resolutionCid: stored.resolution_cid,
        authority: approval.reviewer_id,
        expiresAt: approval.expires_at,
        current: approval.current === true,
        checkedAt: atIso,
      });
    },

    // Admission of one resumed protected dispatch at the Host trusted time.
    // `claim` names the claim the caller holds ({intentId, claimant,
    // generation}); it is an identity to check, never an authority record.
    // Everything else comes from committed rows: the intent must be the
    // current intent of its Checkpoint (and of its Run or preparation) and
    // the claim must pass the MoonBit fence (current claimant, generation
    // and unexpired lease); the Checkpoint must be resolved by the intent's
    // committed approved Resolution, the Run or preparation `resuming`, and
    // the approval's own permission current. Returns the bound admission;
    // throws a coded error otherwise. Nothing is recorded.
    admitResume(claim, {checkpointCid} = {}) {
      alive();
      const at = now();
      return transaction(database, () => admissionLocked(claim,
        checkpointCid, at));
    },

    // The same admission, taken immediately before the protected send and
    // recorded durably: at most one protected dispatch start per claim
    // generation of an intent. A second entry with the same generation, by
    // this or any other process, is `ResumeAdmissionConsumed`.
    //
    // A lease handoff cannot admit two starts: once an earlier claim
    // generation of this (still uncompleted) intent entered a protected
    // dispatch, its physical outcome is unknown to a later claimant, so a
    // fresh start is refused with `PriorAdmissionUnresolved` (the error
    // carries `priorAdmission`). The later claimant may only take the
    // physical reconciliation path (`enterResumedReconciliation`) or leave
    // the intent to a later completion. `dispatchIdentity` is the durable
    // identity of the protected send when it has one (a remote dispatch the
    // Site deduplicates); it is recorded for reconciliation.
    enterResumedDispatch(claim, {checkpointCid, resolutionCid,
      dispatchIdentity} = {}) {
      alive();
      const identity = admissionIdentity(dispatchIdentity);
      const at = now();
      return transaction(database, () => {
        const admission = enteredLocked(claim, checkpointCid, resolutionCid,
          at);
        const prior = statements.priorAdmission.get(admission.intentId,
          admission.generation);
        if (prior !== undefined) {
          throw Object.assign(new Error('PriorAdmissionUnresolved'), {
            code: 'PriorAdmissionUnresolved',
            priorAdmission: priorAdmissionView(prior),
          });
        }
        changed(statements.enterAdmission.run(admission.intentId,
          admission.generation, admission.claimant, admission.admittedAt,
          'start', identity), 'ResumeAdmissionConsumed');
        fault('enterResumedDispatch');
        return Object.freeze({...admission, mode: 'start',
          dispatchIdentity: identity === '' ? null : identity});
      });
    },

    // Physical reconciliation of an earlier generation's protected dispatch
    // by the current live claim (same fence, approval validity and single
    // entry per generation as `enterResumedDispatch`). Admitted only when an
    // earlier generation started a dispatch with a recorded durable identity
    // and `dispatchIdentity` is exactly that identity: the caller re-sends
    // the same durable dispatch (which the receiver deduplicates), never a
    // second distinct one. A prior start with no durable identity (a Local
    // provider session) cannot be reconciled here: `PriorAdmissionUnresolved`.
    enterResumedReconciliation(claim, {checkpointCid, resolutionCid,
      dispatchIdentity} = {}) {
      alive();
      const identity = admissionIdentity(dispatchIdentity);
      if (identity === '') fail('ReconciliationIdentityRequired');
      const at = now();
      return transaction(database, () => {
        const admission = enteredLocked(claim, checkpointCid, resolutionCid,
          at);
        const prior = statements.priorAdmission.get(admission.intentId,
          admission.generation);
        if (prior === undefined) fail('NoPriorAdmission');
        if (prior.dispatch_identity === '') {
          throw Object.assign(new Error('PriorAdmissionUnresolved'), {
            code: 'PriorAdmissionUnresolved',
            priorAdmission: priorAdmissionView(prior),
          });
        }
        if (prior.dispatch_identity !== identity) {
          fail('ReconciliationIdentityMismatch');
        }
        changed(statements.enterAdmission.run(admission.intentId,
          admission.generation, admission.claimant, admission.admittedAt,
          'reconcile', identity), 'ResumeAdmissionConsumed');
        fault('enterResumedReconciliation');
        return Object.freeze({...admission, mode: 'reconcile',
          dispatchIdentity: identity,
          priorAdmission: priorAdmissionView(prior)});
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
            next.subject, next.claims, atIso);
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

  function enteredLocked(claim, checkpointCid, resolutionCid, at) {
    const admission = admissionLocked(claim, checkpointCid, at);
    if (resolutionCid !== undefined &&
        resolutionCid !== admission.resolutionCid) {
      fail('ResolutionNotCommitted');
    }
    return admission;
  }

  function admissionLocked(claim, checkpointCid, at) {
    if (!text(claim?.intentId) || !text(claim?.claimant) ||
        !Number.isSafeInteger(claim?.generation)) {
      fail('ResumeNotClaimed');
    }
    const intent = statements.intentById.get(claim.intentId);
    if (intent === undefined) fail('ResumeIntentNotFound');
    if (checkpointCid !== undefined && intent.checkpoint_cid !== checkpointCid) {
      fail('ResumeIntentMismatch');
    }
    const latest = intent.run_id !== null
      ? statements.intent.get(intent.run_id)
      : statements.preparationIntent.get(intent.prepare_attempt_id);
    if (latest?.intent_id !== intent.intent_id) fail('ResumeIntentMismatch');
    const fence = core(runtime.resumeFenceDecide(intentView(intent),
      claim.claimant, claim.generation, at), 'ResumeClaimStale');
    if (fence.action !== 'current') fail('ResumeClaimStale');
    const checkpoint = statements.checkpoint.get(intent.checkpoint_cid);
    const stored = statements.resolution.get(intent.checkpoint_cid);
    if (checkpoint?.closure !== 'resolved' || stored?.decision !== 'approved' ||
        checkpoint.resolution_cid !== intent.resolution_cid ||
        stored.resolution_cid !== intent.resolution_cid) {
      fail('ResolutionNotCommitted');
    }
    const owner = intent.run_id !== null
      ? statements.run.get(intent.run_id)
      : statements.preparation.get(intent.prepare_attempt_id);
    if (owner?.status !== 'resuming') fail('RunNotResuming');
    const atIso = iso(at);
    const approval = core(runtime.resumedApprovalAt(
      stored.verified_resolution_wire, atIso), 'ResolutionNotCommitted');
    if (approval.checkpoint_cid !== intent.checkpoint_cid ||
        approval.resolution_cid !== intent.resolution_cid ||
        approval.verified_resolution_cid !== stored.verified_resolution_cid) {
      fail('ResolutionNotCommitted');
    }
    if (approval.current !== true) fail('ApprovalExpired');
    const artifact = JSON.parse(checkpoint.checkpoint_wire);
    return Object.freeze({
      intentId: intent.intent_id,
      checkpointCid: intent.checkpoint_cid,
      runId: intent.run_id,
      prepareAttemptId: intent.prepare_attempt_id,
      resolutionCid: intent.resolution_cid,
      verifiedResolutionCid: stored.verified_resolution_cid,
      claimant: intent.claimant,
      generation: Number(intent.generation),
      leaseExpiresMs: Number(intent.lease_expires_ms),
      kind: artifact.kind,
      requiredArtifactCid: artifact.required_artifact.artifact_cid,
      decisionSubjectCid: checkpoint.decision_subject_cid === '' ? null :
        checkpoint.decision_subject_cid,
      requestedClaims: Object.freeze(
        JSON.parse(checkpoint.requested_claims_json)),
      observedClaims: Object.freeze([...approval.claims]),
      authority: approval.reviewer_id,
      approvalExpiresAt: approval.expires_at,
      admittedAt: atIso,
    });
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
          next.claims, atIso);
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
