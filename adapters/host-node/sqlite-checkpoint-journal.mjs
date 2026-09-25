// Durable Checkpoint lifecycle journal for a Node Host.
//
// Semantics (artifact shape and identity, Resolution admission, transition
// table, commit decisions, resume fencing and Run-state projections) are owned
// by the portable MoonBit core in src/checkpoint_runtime and reached through
// src/checkpoint_runtime_node. This adapter owns only storage, the clock, and
// the Host authorization and attestation ports.
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

// Safe inspection view: identities, the review subject reference, and the
// non-restricted metadata sealed in the Checkpoint. No review projection
// contents, evidence, or Host authority configuration are returned.
function checkpointView(wire, row) {
  const artifact = JSON.parse(wire);
  return Object.freeze({
    checkpointCid: artifact.checkpoint_cid,
    checkpointId: artifact.checkpoint_id,
    runId: artifact.run_id,
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
    closure: row.closure,
    resolutionCid: row.resolution_cid === '' ? null : row.resolution_cid,
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
      CREATE TABLE IF NOT EXISTS checkpoints (
        checkpoint_cid TEXT PRIMARY KEY NOT NULL,
        checkpoint_id TEXT NOT NULL,
        run_id TEXT NOT NULL REFERENCES runs (run_id),
        checkpoint_wire TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        authorities_json TEXT NOT NULL,
        binding_json TEXT NOT NULL,
        closure TEXT NOT NULL
          CHECK (closure IN ('open', 'resolved', 'expired')),
        resolution_cid TEXT NOT NULL DEFAULT '',
        persisted_at TEXT NOT NULL,
        closed_at TEXT NOT NULL DEFAULT '',
        UNIQUE (run_id, checkpoint_id)
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
        run_id TEXT NOT NULL REFERENCES runs (run_id),
        state TEXT NOT NULL CHECK (state IN ('pending', 'claimed', 'completed')),
        generation INTEGER NOT NULL CHECK (generation >= 0),
        claimant TEXT NOT NULL DEFAULT '',
        lease_expires_ms INTEGER NOT NULL DEFAULT 0,
        outcome_status TEXT NOT NULL DEFAULT '',
        completed_at TEXT NOT NULL DEFAULT ''
      ) STRICT;
    `);
    transaction(database, () => {
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
      VALUES (?, 'waiting_checkpoint', 1, ?, ?, ?)`),
    // Compare-and-swap on the Run version and prior status.
    moveRun: database.prepare(`
      UPDATE runs SET status = ?, version = version + 1, updated_at = ?,
        checkpoint_cid = ?, run_state_wire = ?
      WHERE run_id = ? AND version = ? AND status = ?`),
    checkpoint: database.prepare(
      'SELECT * FROM checkpoints WHERE checkpoint_cid = ?'),
    checkpointById: database.prepare(
      'SELECT * FROM checkpoints WHERE checkpoint_id = ? ORDER BY persisted_at'),
    insertCheckpoint: database.prepare(`
      INSERT INTO checkpoints (checkpoint_cid, checkpoint_id, run_id,
        checkpoint_wire, expires_at, authorities_json, binding_json, closure,
        persisted_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?)`),
    closeCheckpoint: database.prepare(`
      UPDATE checkpoints SET closure = ?, resolution_cid = ?, closed_at = ?
      WHERE checkpoint_cid = ? AND closure = 'open'`),
    pending: database.prepare(`
      SELECT c.* FROM checkpoints c JOIN runs r
        ON r.run_id = c.run_id AND r.checkpoint_cid = c.checkpoint_cid
      WHERE c.closure = 'open' AND r.status = 'waiting_checkpoint'
      ORDER BY c.persisted_at, c.checkpoint_cid`),
    resolution: database.prepare(
      'SELECT * FROM resolutions WHERE checkpoint_cid = ?'),
    insertResolution: database.prepare(`
      INSERT INTO resolutions (resolution_cid, checkpoint_cid, decision,
        verified_resolution_cid, verified_resolution_wire, committed_at)
      VALUES (?, ?, ?, ?, ?, ?)`),
    intent: database.prepare('SELECT * FROM resume_intents WHERE run_id = ?'),
    intentById: database.prepare(
      'SELECT * FROM resume_intents WHERE intent_id = ?'),
    insertIntent: database.prepare(`
      INSERT INTO resume_intents (intent_id, checkpoint_cid, resolution_cid,
        run_id, state, generation)
      VALUES (?, ?, ?, ?, 'pending', 0)`),
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

  function sealBody(body) {
    const bodyWire = typeof body === 'string' ? body : JSON.stringify(body);
    return core(runtime.checkpointSealBody(bodyWire), 'InvalidCheckpoint');
  }

  function insertCheckpoint(sealed, authorities, binding, at) {
    statements.insertCheckpoint.run(
      sealed.checkpoint_cid, sealed.checkpoint_id, sealed.run_id,
      sealed.checkpoint_wire, sealed.expires_at, authorities, binding, at,
    );
  }

  // After commit: the waiting projection is issued only from the exact wire
  // read back from the committed row.
  function waitingAfterCommit(sealed) {
    const row = statements.checkpoint.get(sealed.checkpoint_cid);
    const run = statements.run.get(sealed.run_id);
    if (row === undefined || run === undefined) fail('CheckpointNotPersisted');
    if (run.status !== 'waiting_checkpoint' ||
        run.checkpoint_cid !== sealed.checkpoint_cid) {
      // Idempotent retry of an already answered Checkpoint: report the
      // current committed state, never a stale waiting claim.
      const current = projectRunState(sealed.run_id);
      return Object.freeze({
        checkpointCid: sealed.checkpoint_cid,
        checkpointId: sealed.checkpoint_id,
        runId: sealed.run_id,
        runStateWire: current.runStateWire,
        runState: current.runState,
      });
    }
    const wire = core(runtime.checkpointWaitingState(
      sealed.checkpoint_wire, row.checkpoint_wire, run.updated_at,
      run.declared_results_json,
    ), 'CheckpointNotPersisted').run_state_wire;
    return Object.freeze({
      checkpointCid: sealed.checkpoint_cid,
      checkpointId: sealed.checkpoint_id,
      runId: sealed.run_id,
      runStateWire: wire,
      runState: JSON.parse(wire),
    });
  }

  function expireLocked(row, at) {
    const run = statements.run.get(row.run_id);
    changed(statements.closeCheckpoint.run('expired', '', at,
      row.checkpoint_cid), 'CheckpointAlreadyClosed');
    if (run?.status === 'waiting_checkpoint' &&
        run.checkpoint_cid === row.checkpoint_cid) {
      transitionAllowed('waiting_checkpoint', 'cancelled');
      changed(statements.moveRun.run('cancelled', at, '', '', run.run_id,
        run.version, 'waiting_checkpoint'), 'RunStateConflict');
    }
  }

  return Object.freeze({
    path,

    // Seal and durably persist a deferred decision. The caller may report
    // a waiting Checkpoint only from the returned projection, which exists
    // only after the transaction committed.
    persistCheckpoint({
      body, priorStatus, declaredResults, authorities, binding,
    }) {
      alive();
      if (priorStatus !== 'preparing' && priorStatus !== 'running') {
        fail('RunTransitionRejected');
      }
      transitionAllowed(priorStatus, 'waiting_checkpoint');
      const sealed = sealBody(body);
      const reviewers = authoritiesJson(authorities);
      const bound = bindingJson(binding);
      const declared = declaredJson(declaredResults);
      const at = iso(now());
      transaction(database, () => {
        const existing = statements.checkpoint.get(sealed.checkpoint_cid);
        if (existing !== undefined) {
          if (existing.checkpoint_wire !== sealed.checkpoint_wire ||
              existing.authorities_json !== reviewers ||
              existing.binding_json !== bound) {
            fail('CheckpointConflict');
          }
          return;
        }
        if (statements.run.get(sealed.run_id) !== undefined) {
          fail('RunAlreadyTracked');
        }
        statements.insertRun.run(sealed.run_id, at, declared,
          sealed.checkpoint_cid);
        insertCheckpoint(sealed, reviewers, bound, at);
        fault('persistCheckpoint');
      });
      return waitingAfterCommit(sealed);
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
      if (!text(reference)) fail('InvalidCheckpointReference');
      let row = statements.checkpoint.get(reference);
      if (row === undefined) {
        const rows = statements.checkpointById.all(reference);
        if (rows.length > 1) fail('AmbiguousCheckpointReference');
        row = rows[0];
      }
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

    // Admit, attest, and commit one Resolution. Resolution storage,
    // Checkpoint closure, the Run transition and the unique resume intent
    // commit in one transaction.
    async submitResolution({
      checkpointCid, resolutionWire, approvalEvidenceWire = '',
    }) {
      alive();
      if (!text(checkpointCid) || !text(resolutionWire) ||
          typeof approvalEvidenceWire !== 'string') {
        fail('InvalidResolutionSubmission');
      }
      const row = statements.checkpoint.get(checkpointCid);
      if (row === undefined) fail('CheckpointNotFound');
      const verifiedAt = iso(now());
      let authentication;
      try {
        authentication = await authorizeResolution(Object.freeze({
          checkpointWire: row.checkpoint_wire,
          resolutionWire,
          approvalEvidenceWire,
        }));
      } catch (error) {
        fail('ResolutionAuthenticationFailed', error);
      }
      if (!text(authentication?.keyId) || !text(authentication?.reviewerId) ||
          !text(authentication?.authorityContextCid) ||
          !text(authentication?.policyCid)) {
        fail('ResolutionAuthenticationFailed');
      }
      const authJson = JSON.stringify({
        key_id: authentication.keyId,
        reviewer_id: authentication.reviewerId,
        authority_context_cid: authentication.authorityContextCid,
        policy_cid: authentication.policyCid,
      });
      const admitted = core(runtime.resolutionAdmit(
        row.checkpoint_wire, resolutionWire, approvalEvidenceWire, authJson,
        row.authorities_json, verifiedAt,
      ), 'InvalidResolution');
      const attestation = await attestResolution(admitted.attestation_preimage);
      if (!text(attestation?.hostKeyId) || !text(attestation?.signature)) {
        fail('InvalidHostAttestation');
      }
      alive();
      const outcome = transaction(database, () => {
        const current = statements.checkpoint.get(checkpointCid);
        const decided = core(runtime.resolutionDecide(
          current.checkpoint_wire, resolutionWire, approvalEvidenceWire,
          authJson, current.authorities_json, verifiedAt,
          attestation.hostKeyId, attestation.signature, current.closure,
          current.resolution_cid,
        ), 'InvalidResolution');
        if (decided.action === 'duplicate') {
          const stored = statements.resolution.get(checkpointCid);
          return {kind: 'duplicate', decided, stored};
        }
        if (decided.action === 'conflict') {
          return {kind: 'conflict'};
        }
        if (decided.action === 'expired') {
          if (current.closure === 'open') expireLocked(current, verifiedAt);
          return {kind: 'expired'};
        }
        const run = statements.run.get(current.run_id);
        if (run?.status !== 'waiting_checkpoint' ||
            run.checkpoint_cid !== checkpointCid) {
          fail('RunStateConflict');
        }
        transitionAllowed('waiting_checkpoint', decided.run_status);
        statements.insertResolution.run(
          decided.resolution_cid, checkpointCid, decided.decision,
          decided.verified_resolution_cid, decided.verified_resolution_wire,
          verifiedAt,
        );
        changed(statements.closeCheckpoint.run('resolved',
          decided.resolution_cid, verifiedAt, checkpointCid),
        'CheckpointAlreadyClosed');
        changed(statements.moveRun.run(decided.run_status, verifiedAt, '', '',
          run.run_id, run.version, 'waiting_checkpoint'), 'RunStateConflict');
        if (decided.decision === 'approved') {
          statements.insertIntent.run(decided.resume_intent_id,
            checkpointCid, decided.resolution_cid, run.run_id);
        }
        fault('submitResolution');
        return {kind: 'committed', decided};
      });
      if (outcome.kind === 'conflict') fail('CheckpointResolutionConflict');
      if (outcome.kind === 'expired') fail('CheckpointExpired');
      const stored = statements.resolution.get(checkpointCid);
      const intent = statements.intent.get(row.run_id);
      return Object.freeze({
        outcome: outcome.kind,
        decision: stored.decision,
        resolutionCid: stored.resolution_cid,
        verifiedResolutionCid: stored.verified_resolution_cid,
        verifiedResolutionWire: stored.verified_resolution_wire,
        resumeIntentId: stored.decision === 'approved' ?
          intent?.intent_id ?? null : null,
        runState: projectRunState(row.run_id),
      });
    },

    // Claim the unique resume intent of a Run with a strictly higher fencing
    // generation. Bound authorization-context and environment-binding CIDs
    // are revalidated here, before any continuation dispatch.
    claimResume(runId, {claimant, leaseMs, binding}) {
      alive();
      if (!text(runId)) fail('InvalidRunId');
      const current = bindingJson(binding);
      const at = now();
      return transaction(database, () => {
        const intent = statements.intent.get(runId);
        if (intent === undefined) fail('ResumeIntentNotFound');
        const checkpoint = statements.checkpoint.get(intent.checkpoint_cid);
        const decided = core(runtime.resumeClaimDecide(
          intentView(intent), claimant, at, leaseMs, checkpoint.binding_json,
          current,
        ), 'InvalidResumeClaim');
        if (decided.action === 'busy' || decided.action === 'completed') {
          return Object.freeze({action: decided.action});
        }
        const run = statements.run.get(runId);
        if (run?.status !== 'resuming') fail('RunStateConflict');
        if (decided.action === 'invalidated') {
          transitionAllowed('resuming', 'failed');
          changed(statements.completeIntent.run(decided.generation, claimant,
            'failed', iso(at), intent.intent_id, intent.generation),
          'ResumeClaimStale');
          changed(statements.moveRun.run('failed', iso(at), '', '', runId,
            run.version, 'resuming'), 'RunStateConflict');
          fault('claimResume');
          return Object.freeze({action: 'invalidated', runStatus: 'failed'});
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

    // Complete the resume intent together with the resumed Run's transition.
    // Outcome is one of: {runStateWire} for a continuation-issued state,
    // {status: 'failed' | 'cancelled'}, or {checkpoint: {...}} for the next
    // Checkpoint of the same Run.
    completeResume(claim, outcome) {
      alive();
      if (!text(claim?.intentId) || !text(claim?.claimant) ||
          !Number.isSafeInteger(claim?.generation)) {
        fail('ResumeClaimStale');
      }
      let target;
      let runStateWire = '';
      let next;
      if (outcome?.checkpoint !== undefined) {
        next = {
          sealed: sealBody(outcome.checkpoint.body),
          reviewers: authoritiesJson(outcome.checkpoint.authorities),
          bound: bindingJson(outcome.checkpoint.binding),
        };
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
        const intent = statements.intentById.get(claim.intentId);
        if (intent === undefined) fail('ResumeClaimStale');
        const fence = core(runtime.resumeFenceDecide(intentView(intent),
          claim.claimant, claim.generation, at), 'ResumeClaimStale');
        if (fence.action !== 'current') fail('ResumeClaimStale');
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
          insertCheckpoint(next.sealed, next.reviewers, next.bound, atIso);
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

    // Close every open Checkpoint whose expiration has been reached and
    // cancel its waiting Run without dispatch.
    expire() {
      alive();
      const at = iso(now());
      return transaction(database, () => {
        const expired = [];
        for (const row of statements.pending.all()) {
          const result = core(runtime.checkpointExpiredAt(row.checkpoint_wire,
            at), 'CheckpointJournalCorrupt');
          if (result.expired) {
            expireLocked(row, at);
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
}
