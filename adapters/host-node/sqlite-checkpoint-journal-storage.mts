// DatabaseSync retains these statements on the Checkpoint Journal's original
// connection. The admitted STRICT layout and exact SELECT lists define rows.
import {createModelResumeTables} from './model-resume-sqlite.mjs';

import type {DatabaseSync, SQLInputValue, StatementSync} from 'node:sqlite';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';

type RunRow = Readonly<{
  run_id: string; status: string; version: number; updated_at: string;
  declared_results_json: string; checkpoint_cid: string; run_state_wire: string;
}>;
export type PreparationRow = Readonly<{
  prepare_attempt_id: string; status: 'waiting_checkpoint' | 'resuming' | 'run_created' | 'ended';
  version: number; updated_at: string; declared_results_json: string; checkpoint_cid: string;
  run_id: string; end_reason: string; terminal_error_code: string; cancel_requested: 0 | 1;
}>;
export type CheckpointRow = Readonly<{
  checkpoint_id: string; checkpoint_cid: string; run_id: string | null; prepare_attempt_id: string | null;
  checkpoint_wire: string; expires_at: string; authorities_json: string; binding_json: string;
  decision_subject_cid: string; requested_claims_json: string; configuration_cid: string;
  closure: 'open' | 'resolved' | 'expired' | 'cancelled'; resolution_cid: string;
  persisted_at: string; closed_at: string;
}>;
type ResolutionRow = Readonly<{
  resolution_cid: string; checkpoint_cid: string; decision: 'approved' | 'rejected';
  verified_resolution_cid: string; verified_resolution_wire: string; committed_at: string;
}>;
type IntentRow = Readonly<{
  intent_id: string; checkpoint_cid: string; resolution_cid: string; run_id: string | null;
  prepare_attempt_id: string | null; state: 'pending' | 'claimed' | 'completed';
  generation: number; claimant: string; lease_expires_ms: number;
  outcome_status: string; completed_at: string;
}>;
export type AdmissionRow = Readonly<{
  generation: number; claimant: string; admitted_at: string; dispatch_identity: string;
}>;
type SettlementRow = Readonly<{
  intent_id: string; generation: number; refusal_code: 'ACTQL_E_RESUME_REVALIDATION_FAILED';
}>;
type SqliteRow = NonNullable<ReturnType<StatementSync['get']>>;
type One<Row, Keys extends readonly SQLInputValue[]> =
  Readonly<{get(...keys: Keys): (Row & SqliteRow) | undefined}> & StatementSync;
type Many<Row, Keys extends readonly SQLInputValue[]> =
  Readonly<{all(...keys: Keys): (Row & SqliteRow)[]}> & StatementSync;

// Private SQLite layout discriminator, not a public artifact version. Upgrade
// only after all Hosts using this root have stopped and closed their journals.
// Incompatible records are refused in place; this owner never clears/migrates them.
const PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT =
  'actql-checkpoint-journal/0.1;model-call-provenance=1';
const EFFECT_SETTLEMENT_JOURNAL_LAYOUT =
  'actql-checkpoint-journal/0.1;model-call-provenance=1;effect-settlement=1';
export const MODEL_CURRENT_CUT_JOURNAL_LAYOUT =
  EFFECT_SETTLEMENT_JOURNAL_LAYOUT + ';model-current-cut-link=1';
const MODEL_CURRENT_CUT_INVALIDATION_JOURNAL_LAYOUT =
  MODEL_CURRENT_CUT_JOURNAL_LAYOUT + ';model-current-cut-invalidation=1';
const SCHEMA_VERSION = MODEL_CURRENT_CUT_INVALIDATION_JOURNAL_LAYOUT;
const EFFECT_SETTLEMENT_TABLE_SQL = `
  CREATE TABLE resume_effect_settlements (
    intent_id TEXT PRIMARY KEY NOT NULL REFERENCES resume_intents (intent_id),
    generation INTEGER NOT NULL CHECK (generation >= 1),
    refusal_code TEXT NOT NULL
      CHECK (refusal_code = 'ACTQL_E_RESUME_REVALIDATION_FAILED')
  ) STRICT;`;

export function initializeCheckpointJournal(database: Pick<DatabaseSync, 'exec' | 'prepare'>,
  transaction: Pick<ReturnType<typeof createSqliteTransaction>, 'run'>,
  fail: (code: string) => never): void {
  // Several Host processes (run, approve, resume) share one journal; a
  // writer waits for the current transaction instead of failing.
  database.exec('PRAGMA busy_timeout = 10000');
  // Refuse an old or unmarked layout before any schema DDL or record write.
  // This startup gate cannot revoke a connection another process already holds.
  const hasCurrentLayout = () => {
    // Take one schema snapshot, so another initializer's atomic commit
    // cannot look like unmarked tables between two separate queries.
    const tables = database.prepare(
      "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").all();
    if (!tables.some(table => table.name === 'journal_metadata')) {
      if (tables.length !== 0) fail('UnsupportedCheckpointJournal');
      return false;
    }
    const version = database.prepare('SELECT value FROM journal_metadata WHERE key = ?').get('schema_version');
    if (version?.value !== SCHEMA_VERSION) fail('UnsupportedCheckpointJournal');
    // Never repair a recognized journal by recreating a missing refusal
    // marker table: it may have held a still-unsettled no-send decision.
    database.prepare('SELECT intent_id, generation, refusal_code FROM resume_effect_settlements LIMIT 0');
    database.prepare('SELECT current_cut_link_json, current_cut_invalidation_json FROM resume_model_scopes LIMIT 0');
    return true;
  };
  const initialized = hasCurrentLayout();
  database.exec('PRAGMA journal_mode = WAL');
  database.exec('PRAGMA synchronous = FULL');
  // A recognized layout is opened as-is. Missing columns/tables are damage,
  // not a request to recreate storage that may have held entered attempts.
  if (!initialized) transaction.run(() => {
    // A competing Host may have finished initialization while this one
    // waited for the writer. Validate its finished layout instead of
    // recreating any table that could already contain refusal evidence.
    if (hasCurrentLayout()) return;
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
        terminal_error_code TEXT NOT NULL DEFAULT '',
        cancel_requested INTEGER NOT NULL DEFAULT 0
          CHECK (cancel_requested IN (0, 1))
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
        configuration_cid TEXT NOT NULL DEFAULT '',
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
      ${EFFECT_SETTLEMENT_TABLE_SQL}
      `);
    createModelResumeTables(database);
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
}

export function prepareCheckpointJournalStatements(database: Pick<DatabaseSync, 'prepare'>) {
  return {
    localSigning: database.prepare(
      'SELECT value FROM journal_metadata WHERE key = ?') as One<{value: string}, [key: string]>,
    insertLocalSigning: database.prepare(
      'INSERT INTO journal_metadata (key, value) VALUES (?, ?)'),
    updateLocalSigning: database.prepare(
      'UPDATE journal_metadata SET value = ? WHERE key = ? AND value = ?'),
    run: database.prepare('SELECT * FROM runs WHERE run_id = ?') as One<RunRow, [runId: string]>,
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
      'SELECT * FROM preparations WHERE prepare_attempt_id = ?') as One<PreparationRow, [prepareAttemptId: string]>,
    insertPreparation: database.prepare(`
      INSERT INTO preparations (prepare_attempt_id, status, version,
        updated_at, declared_results_json, checkpoint_cid)
      VALUES (?, 'waiting_checkpoint', 1, ?, ?, ?)`),
    // Compare-and-swap on the preparation version and prior status.
    requestPreparationCancel: database.prepare(`
      UPDATE preparations SET cancel_requested = 1, version = version + 1,
        updated_at = ?
      WHERE prepare_attempt_id = ? AND version = ? AND cancel_requested = 0`),
    movePreparation: database.prepare(`
      UPDATE preparations SET status = ?, version = version + 1,
        updated_at = ?, checkpoint_cid = ?, run_id = ?, end_reason = ?,
        terminal_error_code = ?
      WHERE prepare_attempt_id = ? AND version = ? AND status = ?`),
    checkpoint: database.prepare(
      'SELECT * FROM checkpoints WHERE checkpoint_cid = ?') as One<CheckpointRow, [checkpointCid: string]>,
    checkpointById: database.prepare(
      'SELECT * FROM checkpoints WHERE checkpoint_id = ? ORDER BY persisted_at') as Many<CheckpointRow, [checkpointId: string]>,
    insertCheckpoint: database.prepare(`
      INSERT INTO checkpoints (checkpoint_cid, checkpoint_id, run_id,
        prepare_attempt_id, checkpoint_wire, expires_at, authorities_json,
        binding_json, decision_subject_cid, requested_claims_json,
        configuration_cid, closure, persisted_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?)`),
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
      ORDER BY c.persisted_at, c.checkpoint_cid`) as Many<CheckpointRow, []>,
    // One page of the same pending set, after a (persisted_at,
    // checkpoint_cid) cursor.
    pendingPage: database.prepare(`
      SELECT c.* FROM checkpoints c
        LEFT JOIN runs r
          ON r.run_id = c.run_id AND r.checkpoint_cid = c.checkpoint_cid
        LEFT JOIN preparations p
          ON p.prepare_attempt_id = c.prepare_attempt_id
          AND p.checkpoint_cid = c.checkpoint_cid
      WHERE c.closure = 'open' AND (r.status = 'waiting_checkpoint'
        OR p.status = 'waiting_checkpoint')
        AND (c.persisted_at > ? OR c.persisted_at = ? AND c.checkpoint_cid > ?)
      ORDER BY c.persisted_at, c.checkpoint_cid LIMIT ?`) as Many<CheckpointRow, [afterAt: string, sameAt: string, afterCid: string, limit: number]>,
    // Preparations whose current resume intent is not completed: an
    // approved continuation a Host start or answer sweep must continue.
    resumablePreparations: database.prepare(`
      SELECT i.prepare_attempt_id FROM resume_intents i
        JOIN preparations p ON p.prepare_attempt_id = i.prepare_attempt_id
      WHERE i.state != 'completed' AND p.status = 'resuming'
        AND i.rowid = (SELECT MAX(rowid) FROM resume_intents
          WHERE prepare_attempt_id = i.prepare_attempt_id)
        AND i.prepare_attempt_id > ?
      ORDER BY i.prepare_attempt_id LIMIT ?`) as Many<{prepare_attempt_id: string}, [after: string, limit: number]>,
    // Runs created by an approved preparation that are still `running`:
    // the Run-side execution duty a Host start must carry on after the
    // preparation's resume intent completed.
    preparationRuns: database.prepare(`
      SELECT p.prepare_attempt_id, p.run_id FROM preparations p
        JOIN runs r ON r.run_id = p.run_id
      WHERE p.status = 'run_created' AND r.status = 'running'
        AND p.prepare_attempt_id > ?
      ORDER BY p.prepare_attempt_id LIMIT ?`) as Many<{prepare_attempt_id: string; run_id: string}, [after: string, limit: number]>,
    resolution: database.prepare(
      'SELECT * FROM resolutions WHERE checkpoint_cid = ?') as One<ResolutionRow, [checkpointCid: string]>,
    insertResolution: database.prepare(`
      INSERT INTO resolutions (resolution_cid, checkpoint_cid, decision,
        verified_resolution_cid, verified_resolution_wire, committed_at)
      VALUES (?, ?, ?, ?, ?, ?)`),
    // A Run or preparation may resume more than once; the latest intent is
    // the current one.
    intent: database.prepare(`
      SELECT * FROM resume_intents WHERE run_id = ?
      ORDER BY rowid DESC LIMIT 1`) as One<IntentRow, [runId: string]>,
    activeRunIntents: database.prepare(`
      SELECT * FROM resume_intents WHERE run_id = ? AND state != 'completed'`) as Many<IntentRow, [runId: string]>,
    preparationIntent: database.prepare(`
      SELECT * FROM resume_intents WHERE prepare_attempt_id = ?
      ORDER BY rowid DESC LIMIT 1`) as One<IntentRow, [prepareAttemptId: string]>,
    intentByCheckpoint: database.prepare(
      'SELECT * FROM resume_intents WHERE checkpoint_cid = ?') as One<IntentRow, [checkpointCid: string]>,
    intentById: database.prepare(
      'SELECT * FROM resume_intents WHERE intent_id = ?') as One<IntentRow, [intentId: string]>,
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
      ORDER BY generation LIMIT 1`) as One<AdmissionRow, [intentId: string, beforeGeneration: number]>,
    startedAdmission: database.prepare(`
      SELECT generation FROM resume_admissions
      WHERE intent_id = ? AND mode = 'start' LIMIT 1`) as One<Pick<AdmissionRow, "generation">, [intentId: string]>,
    effectSettlement: database.prepare(
      'SELECT * FROM resume_effect_settlements WHERE intent_id = ?') as One<SettlementRow, [intentId: string]>,
    recordEffectSettlement: database.prepare(`
      INSERT INTO resume_effect_settlements (intent_id, generation, refusal_code)
      VALUES (?, ?, 'ACTQL_E_RESUME_REVALIDATION_FAILED')
      ON CONFLICT(intent_id) DO UPDATE SET generation = excluded.generation`),
  };
}
