'use strict';

// Exact native schema SQL emitted by this Journal's fixed authored DDL on the
// selected SQLite implementation. A support boundary before cold native schema
// construction, not a SQL parser, format authority or operational issuer.
// Automatic native indexes have NULL SQL and are checked separately.
const sql = Object.freeze([
  "CREATE TABLE client_local_execution_owners (\n  namespace_id TEXT NOT NULL,\n  authority_scope_cid TEXT NOT NULL,\n  run_definition_cid TEXT PRIMARY KEY REFERENCES client_requests(run_definition_cid) ON DELETE CASCADE,\n  owner_token TEXT NOT NULL CHECK (length(owner_token) = 36),\n  anchor_identity TEXT NOT NULL CHECK (length(anchor_identity) = 36),\n  anchor_device TEXT NOT NULL CHECK (length(anchor_device) BETWEEN 1 AND 32),\n  anchor_inode TEXT NOT NULL CHECK (length(anchor_inode) BETWEEN 1 AND 32)\n) STRICT",
  "CREATE TABLE client_cancellation_custody (\n          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)\n        ) STRICT",
  "CREATE TABLE client_cancellation_operations (\n          namespace_id TEXT NOT NULL,\n          authority_scope_cid TEXT NOT NULL,\n          cancel_id TEXT NOT NULL,\n          run_definition_cid TEXT NOT NULL REFERENCES client_requests(run_definition_cid),\n          expected_revision INTEGER NOT NULL CHECK (expected_revision >= 0),\n          intent_fingerprint_cid TEXT NOT NULL,\n          outcome_wire TEXT,\n          outcome_cid TEXT,\n          CHECK ((outcome_wire IS NULL) = (outcome_cid IS NULL)),\n          PRIMARY KEY (namespace_id, authority_scope_cid, cancel_id)\n        ) STRICT",
  "CREATE TABLE client_observation_format (\n        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n        version TEXT NOT NULL\n      ) STRICT",
  "CREATE TABLE client_observation_runs (\n        namespace_id TEXT NOT NULL, authority_scope_cid TEXT NOT NULL,\n        run_definition_cid TEXT NOT NULL, caller_request_id TEXT NOT NULL,\n        scope TEXT NOT NULL, configuration_revision TEXT NOT NULL,\n        context_json TEXT, records INTEGER NOT NULL CHECK (records >= 0),\n        bytes INTEGER NOT NULL CHECK (bytes >= 0), owner_fact_key TEXT,\n        PRIMARY KEY (namespace_id, authority_scope_cid, run_definition_cid)\n      ) STRICT",
  "CREATE TABLE client_requests (\n        authority_scope_cid TEXT NOT NULL,\n        caller_request_id TEXT NOT NULL,\n        logical_request_scope_cid TEXT NOT NULL UNIQUE,\n        intent_fingerprint_cid TEXT NOT NULL,\n        program_definition_cid TEXT NOT NULL,\n        parameter_values_cid TEXT NOT NULL,\n        caller_input_intent_cid TEXT NOT NULL,\n        namespace_id TEXT NOT NULL,\n        run_definition_cid TEXT NOT NULL UNIQUE,\n        run_definition_wire TEXT,\n        run_admission_evidence_json TEXT,\n        revision INTEGER NOT NULL CHECK (revision >= 0),\n        state_revision INTEGER NOT NULL DEFAULT 0\n          CHECK (state_revision >= 0 AND state_revision <= 9007199254740991),\n        state_observation_key TEXT,\n        lookup_expires_at TEXT NOT NULL,\n        result_names_json TEXT,\n        dispatch_reserved INTEGER NOT NULL DEFAULT 0\n          CHECK (dispatch_reserved IN (0, 1)),\n        pre_dispatch_failure_confirmed INTEGER NOT NULL DEFAULT 0\n          CHECK (pre_dispatch_failure_confirmed IN (0, 1)),\n        physical_start_reserved INTEGER NOT NULL DEFAULT 0\n          CHECK (physical_start_reserved IN (0, 1)),\n        cancellation_requested INTEGER NOT NULL DEFAULT 0\n          CHECK (cancellation_requested IN (0, 1)),\n        physical_close_confirmed INTEGER NOT NULL DEFAULT 0\n          CHECK (physical_close_confirmed IN (0, 1)),\n        observed_terminal_outcome TEXT\n          CHECK (observed_terminal_outcome IN ('failed', 'cancelled')),\n        reconciliation_state_wire TEXT,\n        PRIMARY KEY (authority_scope_cid, caller_request_id)\n      ) STRICT",
  "CREATE TABLE client_source_operation_originals (\n  namespace_id TEXT NOT NULL,\n  authority_scope_cid TEXT NOT NULL,\n  run_definition_cid TEXT NOT NULL REFERENCES client_requests(run_definition_cid),\n  stage INTEGER NOT NULL CHECK (stage >= 0),\n  input_index INTEGER NOT NULL CHECK (input_index >= 0),\n  task INTEGER NOT NULL CHECK (task >= 0),\n  source_attempt_id TEXT NOT NULL,\n  run_invocation_cid TEXT NOT NULL,\n  dispatch_request_cid TEXT NOT NULL,\n  original_wire TEXT NOT NULL,\n  PRIMARY KEY (namespace_id, authority_scope_cid, run_definition_cid, stage, input_index, task)\n) STRICT",
  "CREATE TABLE client_submission_custody (\n          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)\n        ) STRICT",
  "CREATE TABLE client_submission_epoch_authority (\n          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n          authentication_key TEXT NOT NULL,\n          observed_at INTEGER NOT NULL CHECK (observed_at >= 0)\n        ) STRICT",
  "CREATE TABLE client_submission_name_custody (\n          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n          issued_count INTEGER NOT NULL CHECK (issued_count >= 0),\n          retained_count INTEGER NOT NULL CHECK (retained_count >= 0)\n        ) STRICT",
  "CREATE TRIGGER client_submission_name_delete_count\n    AFTER DELETE ON client_submission_names BEGIN\n      UPDATE client_submission_name_custody SET retained_count = retained_count - 1 WHERE singleton = 1;\n    END",
  "CREATE TRIGGER client_submission_name_insert_count\n    AFTER INSERT ON client_submission_names BEGIN\n      UPDATE client_submission_name_custody SET retained_count = retained_count + 1 WHERE singleton = 1;\n    END",
  "CREATE TABLE client_submission_names (\n          namespace_id TEXT NOT NULL,\n          actor_id TEXT NOT NULL,\n          name TEXT NOT NULL,\n          authority_scope_cid TEXT NOT NULL,\n          submission_id TEXT NOT NULL UNIQUE,\n          intent_cid TEXT NOT NULL,\n          binding_authenticator TEXT NOT NULL,\n          PRIMARY KEY (namespace_id, actor_id, name)\n        ) STRICT",
  "CREATE TABLE client_submission_restart_custody (\n          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)\n        ) STRICT",
  "CREATE TABLE client_submission_restarts (\n          fresh_submission_id TEXT PRIMARY KEY,\n          original_submission_id TEXT NOT NULL,\n          link_wire TEXT NOT NULL\n        ) STRICT",
  "CREATE TABLE client_submitted_intent_custody (\n          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)\n        ) STRICT",
  "CREATE TABLE client_submitted_intent_retirement (\n          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),\n          retired_count INTEGER NOT NULL CHECK (retired_count >= 0)\n        ) STRICT",
  "CREATE TABLE client_submitted_intents (\n          submission_id TEXT PRIMARY KEY,\n          authority_scope_cid TEXT NOT NULL,\n          nonce TEXT NOT NULL,\n          epoch_wire TEXT NOT NULL,\n          intent_cid TEXT NOT NULL,\n          intent_wire TEXT NOT NULL,\n          accepted_at INTEGER NOT NULL,\n          phase TEXT NOT NULL CHECK (phase IN ('preparing', 'not_accepted', 'preparation_failed', 'ready', 'held')),\n          outcome_wire TEXT,\n          revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0)\n        ) STRICT"
  ,`CREATE TABLE client_submitted_intent_usage (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991),
    retained_bytes INTEGER NOT NULL CHECK (retained_bytes >= 0 AND retained_bytes <= 67108864),
    revision INTEGER NOT NULL CHECK (revision >= 0 AND revision <= 9007199254740991)
  ) STRICT`,
  `CREATE TABLE client_submission_restart_usage (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991),
    retained_bytes INTEGER NOT NULL CHECK (retained_bytes >= 0 AND retained_bytes <= 67108864),
    revision INTEGER NOT NULL CHECK (revision >= 0 AND revision <= 9007199254740991)
  ) STRICT`,
  `CREATE TRIGGER client_submitted_intent_usage_insert AFTER INSERT ON client_submitted_intents BEGIN
    UPDATE client_submitted_intent_usage SET retained_count = retained_count + 1,
      retained_bytes = retained_bytes + length(CAST(NEW.intent_wire AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_submitted_intent_usage_delete AFTER DELETE ON client_submitted_intents BEGIN
    UPDATE client_submitted_intent_usage SET retained_count = retained_count - 1,
      retained_bytes = retained_bytes - length(CAST(OLD.intent_wire AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_submitted_intent_usage_update AFTER UPDATE OF intent_wire ON client_submitted_intents BEGIN
    UPDATE client_submitted_intent_usage SET retained_bytes = retained_bytes
      - length(CAST(OLD.intent_wire AS BLOB)) + length(CAST(NEW.intent_wire AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_submission_restart_usage_insert AFTER INSERT ON client_submission_restarts BEGIN
    UPDATE client_submission_restart_usage SET retained_count = retained_count + 1,
      retained_bytes = retained_bytes + length(CAST(NEW.link_wire AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_submission_restart_usage_delete AFTER DELETE ON client_submission_restarts BEGIN
    UPDATE client_submission_restart_usage SET retained_count = retained_count - 1,
      retained_bytes = retained_bytes - length(CAST(OLD.link_wire AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_submission_restart_usage_update AFTER UPDATE OF link_wire ON client_submission_restarts BEGIN
    UPDATE client_submission_restart_usage SET retained_bytes = retained_bytes
      - length(CAST(OLD.link_wire AS BLOB)) + length(CAST(NEW.link_wire AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`,
  `CREATE TABLE client_request_row_usage (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991)
) STRICT`,
  `CREATE TABLE client_cancellation_row_usage (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991)
) STRICT`,
  `CREATE TRIGGER client_request_row_usage_insert AFTER INSERT ON client_requests BEGIN
    UPDATE client_request_row_usage SET retained_count = retained_count + 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_request_row_usage_delete AFTER DELETE ON client_requests BEGIN
    UPDATE client_request_row_usage SET retained_count = retained_count - 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_cancellation_row_usage_insert AFTER INSERT ON client_cancellation_operations BEGIN
    UPDATE client_cancellation_row_usage SET retained_count = retained_count + 1 WHERE singleton = 1;
  END`,
  `CREATE TRIGGER client_cancellation_row_usage_delete AFTER DELETE ON client_cancellation_operations BEGIN
    UPDATE client_cancellation_row_usage SET retained_count = retained_count - 1 WHERE singleton = 1;
  END`
]);
module.exports = Object.freeze({sql});
