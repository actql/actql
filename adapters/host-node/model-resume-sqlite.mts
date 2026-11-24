import type {DatabaseSync, SQLInputValue, StatementSync} from 'node:sqlite';

type SlotState = 'Unsent' | AttemptState;
type AttemptState = 'EnteredUnknown' | 'SavedSuccess' | 'SavedFailure';
type ScopeRow = Readonly<{
  checkpoint_cid: string | null;
  run_id: string; scope_cid: string; task_index: number; strategy_revision: number;
  inventory_json: string; originals_json: string; slot_count: number; registered_at: string;
  registration_kind: 'immediate' | 'deferred';
  checkpoint_inventory_json: string; checkpoint_originals_json: string;
  current_cut_link_json: string | null; current_cut_invalidation_json: string | null;
}>;
type SlotRow = Readonly<{
  scope_cid: string; ordinal: number; slot_cid: string; binding_json: string;
  state: SlotState; attempt_index: number;
}>;
type AttemptRow = Readonly<{
  scope_cid: string; ordinal: number; attempt_index: number; attempt_cid: string; entry_json: string;
  attempt_wire: string; authority_wire: string; state: AttemptState; settlement_json: string;
  entered_at: string; settled_at: string;
}>;
type CancellationRow = Readonly<{
  run_id: string; owner_json: string; original_run_wire: string; cancelled_at: string;
}>;
type SqliteRow = NonNullable<ReturnType<StatementSync['get']>>;
// These reads project fixed columns from the STRICT tables on this connection.
type One<Row, Keys extends readonly SQLInputValue[]> = Readonly<{get(...keys: Keys): (Row & SqliteRow) | undefined}> & StatementSync;
type Many<Row> = Readonly<{all(scopeCid: string): (Row & SqliteRow)[]}> & StatementSync;

export function createModelResumeTables(database: Pick<DatabaseSync, 'exec'>) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS run_cancellation_fences (
      run_id TEXT PRIMARY KEY NOT NULL,
      owner_json TEXT NOT NULL,
      original_run_wire TEXT NOT NULL,
      cancelled_at TEXT NOT NULL
    ) STRICT;
    CREATE TABLE IF NOT EXISTS resume_model_scopes (
      checkpoint_cid TEXT UNIQUE REFERENCES checkpoints (checkpoint_cid),
      run_id TEXT NOT NULL REFERENCES runs (run_id),
      scope_cid TEXT PRIMARY KEY NOT NULL,
      task_index INTEGER NOT NULL CHECK (task_index >= 0),
      strategy_revision INTEGER NOT NULL CHECK (strategy_revision >= 0),
      inventory_json TEXT NOT NULL,
      originals_json TEXT NOT NULL,
      slot_count INTEGER NOT NULL CHECK (slot_count >= 0),
      registered_at TEXT NOT NULL,
      registration_kind TEXT NOT NULL CHECK (registration_kind IN ('immediate', 'deferred')),
      checkpoint_inventory_json TEXT NOT NULL DEFAULT '',
      checkpoint_originals_json TEXT NOT NULL DEFAULT '',
      current_cut_link_json TEXT DEFAULT NULL,
      current_cut_invalidation_json TEXT DEFAULT NULL,
      CHECK (registration_kind != 'deferred' OR checkpoint_cid IS NOT NULL),
      UNIQUE (run_id, task_index)
    ) STRICT;
    CREATE TABLE IF NOT EXISTS resume_model_slots (
      scope_cid TEXT NOT NULL REFERENCES resume_model_scopes (scope_cid),
      ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
      slot_cid TEXT NOT NULL,
      binding_json TEXT NOT NULL,
      state TEXT NOT NULL CHECK (state IN
        ('Unsent', 'EnteredUnknown', 'SavedSuccess', 'SavedFailure')),
      attempt_index INTEGER NOT NULL CHECK (attempt_index >= 0),
      PRIMARY KEY (scope_cid, ordinal),
      UNIQUE (scope_cid, slot_cid),
      CHECK ((state = 'Unsent') = (attempt_index = 0))
    ) STRICT;
    CREATE TABLE IF NOT EXISTS resume_model_attempts (
      scope_cid TEXT NOT NULL,
      ordinal INTEGER NOT NULL,
      attempt_index INTEGER NOT NULL CHECK (attempt_index >= 1),
      attempt_cid TEXT NOT NULL UNIQUE,
      entry_json TEXT NOT NULL,
      attempt_wire TEXT NOT NULL,
      authority_wire TEXT NOT NULL,
      state TEXT NOT NULL CHECK (state IN
        ('EnteredUnknown', 'SavedSuccess', 'SavedFailure')),
      settlement_json TEXT NOT NULL DEFAULT '',
      entered_at TEXT NOT NULL,
      settled_at TEXT NOT NULL DEFAULT '',
      PRIMARY KEY (scope_cid, ordinal, attempt_index),
      FOREIGN KEY (scope_cid, ordinal) REFERENCES resume_model_slots (scope_cid, ordinal),
      CHECK ((state = 'EnteredUnknown') = (settlement_json = ''))
    ) STRICT;
  `);
}

// The checkpoint journal owns the connection and the transactions. Retain
// each native statement and its receiver on this same connection.
export function prepareModelResumeStatements(database: Pick<DatabaseSync, 'prepare'>) {
  return {
    scope: database.prepare('SELECT * FROM resume_model_scopes WHERE checkpoint_cid = ?') as One<ScopeRow, [checkpointCid: string]>,
    scopeByCid: database.prepare('SELECT * FROM resume_model_scopes WHERE scope_cid = ?') as One<ScopeRow, [scopeCid: string]>,
    linkCut: database.prepare('UPDATE resume_model_scopes SET current_cut_link_json = ?, current_cut_invalidation_json = ? WHERE scope_cid = ? AND current_cut_link_json IS NULL AND current_cut_invalidation_json IS NULL'),
    cutRecords: database.prepare(`SELECT * FROM resume_model_scopes
      WHERE (current_cut_link_json IS NOT NULL OR current_cut_invalidation_json IS NOT NULL)
        AND (? IS NULL OR (run_id, task_index, scope_cid) > (?, ?, ?))
      ORDER BY run_id, task_index, scope_cid LIMIT 1`) as One<ScopeRow, [afterRunId: string | null, runId: string | null, taskIndex: number, scopeCid: string]>,
    updateCutInvalidation: database.prepare('UPDATE resume_model_scopes SET current_cut_invalidation_json = ? WHERE scope_cid = ? AND current_cut_link_json = ? AND current_cut_invalidation_json = ?'),
    invalidateCut: database.prepare('UPDATE resume_model_scopes SET current_cut_link_json = NULL, current_cut_invalidation_json = ? WHERE scope_cid = ? AND current_cut_link_json = ? AND current_cut_invalidation_json = ?'),
    slots: database.prepare('SELECT * FROM resume_model_slots WHERE scope_cid = ? ORDER BY ordinal') as Many<SlotRow>,
    attempts: database.prepare('SELECT * FROM resume_model_attempts WHERE scope_cid = ? ORDER BY ordinal, attempt_index') as Many<AttemptRow>,
    cancelled: database.prepare('SELECT * FROM run_cancellation_fences WHERE run_id = ?') as One<CancellationRow, [runId: string]>,
    insertCancel: database.prepare('INSERT INTO run_cancellation_fences VALUES (?, ?, ?, ?)'),
    insertScope: database.prepare(`INSERT INTO resume_model_scopes
      (checkpoint_cid, run_id, scope_cid, task_index, strategy_revision,
       inventory_json, originals_json, slot_count, registered_at, registration_kind)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`),
    attachCheckpoint: database.prepare(`UPDATE resume_model_scopes SET checkpoint_cid = ?,
      checkpoint_inventory_json = ?, checkpoint_originals_json = ?
      WHERE scope_cid = ? AND checkpoint_cid IS NULL AND registration_kind = 'immediate'`),
    insertSlot: database.prepare("INSERT INTO resume_model_slots VALUES (?, ?, ?, ?, 'Unsent', 0)"),
    insertAttempt: database.prepare(`INSERT INTO resume_model_attempts
      VALUES (?, ?, ?, ?, ?, ?, ?, 'EnteredUnknown', '', ?, '')`),
    advanceSlot: database.prepare(`UPDATE resume_model_slots
      SET state = 'EnteredUnknown', attempt_index = ?
      WHERE scope_cid = ? AND ordinal = ? AND state = ? AND attempt_index = ?`),
    settleAttempt: database.prepare(`UPDATE resume_model_attempts
      SET state = ?, settlement_json = ?, settled_at = ?
      WHERE scope_cid = ? AND ordinal = ? AND attempt_index = ?
        AND state = 'EnteredUnknown'`),
    settleSlot: database.prepare(`UPDATE resume_model_slots SET state = ?
      WHERE scope_cid = ? AND ordinal = ? AND attempt_index = ?
        AND state = 'EnteredUnknown'`),
  };
}
