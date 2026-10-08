// Optional telemetry custody shares the request journal's database, but not
// its semantic transactions or identities. Missing/corrupt custody disables
// additional observations; it never resets an admitted Run's consumption.
import {snapshotObservationContext} from '../host-common/observation.mjs';

const version = 'actql-client-observation-custody/0.1';
const columns = ['namespace_id', 'authority_scope_cid', 'run_definition_cid',
  'caller_request_id', 'scope', 'configuration_revision', 'context_json',
  'records', 'bytes'].sort();
const safe = value => Number.isSafeInteger(value) && value >= 0;
const cid = value => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/u.test(value);
const label = value => typeof value === 'string' && /^[a-zA-Z0-9._/-]{1,64}$/u.test(value);
const validRef = ref => typeof ref?.namespaceId === 'string' &&
  ref.namespaceId.length <= 256 && cid(ref.authorityScopeCid) && cid(ref.runDefinitionCid);
const fail = () => { throw new Error('ObservationBudgetUnavailable'); };

export function openClientObservationStorage(database, transaction) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE
    type = 'table' AND name IN ('client_observation_format', 'client_observation_runs')`).all();
  if (tables.length === 0) {
    transaction.run(() => database.exec(`
      CREATE TABLE client_observation_format (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        version TEXT NOT NULL
      ) STRICT;
      INSERT INTO client_observation_format VALUES (1, '${version}');
      CREATE TABLE client_observation_runs (
        namespace_id TEXT NOT NULL, authority_scope_cid TEXT NOT NULL,
        run_definition_cid TEXT NOT NULL, caller_request_id TEXT NOT NULL,
        scope TEXT NOT NULL, configuration_revision TEXT NOT NULL,
        context_json TEXT, records INTEGER NOT NULL CHECK (records >= 0),
        bytes INTEGER NOT NULL CHECK (bytes >= 0),
        PRIMARY KEY (namespace_id, authority_scope_cid, run_definition_cid)
      ) STRICT;
    `));
  } else if (tables.length !== 2) fail();
  if (JSON.stringify(database.prepare('PRAGMA table_info(client_observation_runs)')
    .all().map(x => x.name).sort()) !== JSON.stringify(columns)) fail();
  const formats = database.prepare('SELECT * FROM client_observation_format').all();
  if (formats.length !== 1 || formats[0].singleton !== 1 || formats[0].version !== version ||
    Object.keys(formats[0]).sort().join(',') !== 'singleton,version') fail();
  const retained = database.prepare(`SELECT caller_request_id FROM client_requests
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`);
  const select = database.prepare(`SELECT namespace_id, authority_scope_cid,
    run_definition_cid, caller_request_id, scope, configuration_revision,
    CASE WHEN length(context_json) <= 256 THEN context_json
      WHEN context_json IS NULL THEN NULL ELSE 'invalid' END AS context_json,
    records, bytes FROM client_observation_runs
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`);
  const args = ref => [ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid];
  return Object.freeze({
    // Call only after the existing acceptDefinition owner reports inserted.
    // An old Run or an idempotent acceptance cannot manufacture fresh custody.
    initialize({ref, requestId, scope, revision, context, maxRuns = 1024}) {
      if (!validRef(ref) || typeof requestId !== 'string' || requestId.length > 256 ||
        !safe(maxRuns) || maxRuns < 1 || maxRuns > 1024 ||
        !label(scope) || !label(revision)) fail();
      return transaction.run(() => {
        const original = retained.get(...args(ref));
        if (original?.caller_request_id !== requestId || select.get(...args(ref))) fail();
        if (database.prepare('SELECT count(*) AS n FROM client_observation_runs').get().n >= maxRuns) fail();
        const observed = snapshotObservationContext(context);
        database.prepare(`INSERT INTO client_observation_runs VALUES
          (?, ?, ?, ?, ?, ?, ?, 0, 0)`).run(...args(ref), requestId, scope,
          revision, observed === undefined ? null : JSON.stringify(observed));
      });
    },
    consume({ref, scope, revision, bytes, maxRecords, maxBytes}) {
      if (!validRef(ref) || !label(scope) || !label(revision) || !safe(bytes) ||
        !safe(maxRecords) || !safe(maxBytes)) fail();
      return transaction.run(() => {
        const row = select.get(...args(ref));
        const original = retained.get(...args(ref));
        if (!row || row.caller_request_id !== original?.caller_request_id ||
          row.scope !== scope || row.configuration_revision !== revision ||
          !safe(row.records) || !safe(row.bytes)) return undefined;
        let context;
        if (row.context_json !== null) {
          try {
            const stored = JSON.parse(row.context_json);
            context = snapshotObservationContext(stored);
            if (context === undefined || JSON.stringify(context) !== row.context_json) return undefined;
          } catch { return undefined; }
        }
        if (row.records >= maxRecords || bytes > maxBytes - row.bytes) {
          return Object.freeze({accepted: false});
        }
        database.prepare(`UPDATE client_observation_runs SET records = records + 1,
          bytes = bytes + ? WHERE namespace_id = ? AND authority_scope_cid = ?
          AND run_definition_cid = ?`).run(bytes, ...args(ref));
        return Object.freeze({accepted: true, context});
      });
    },
  });
}
