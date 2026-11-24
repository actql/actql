import type {SQLInputValue, SQLOutputValue} from 'node:sqlite';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';

type SqlRow = Record<string, SQLOutputValue>;
type Prepare = (sql: string) => Readonly<{
  get(...args: SQLInputValue[]): SqlRow | undefined;
  all(...args: SQLInputValue[]): SqlRow[];
}>;
type Refuse = (code: string) => never;
type ResultRecovery = Readonly<{dirty: 0 | 1; ack_revision: number}>;

const version = 15;
const resultRecoveryTable = `CREATE TABLE result_deletion_recovery (
  id INTEGER PRIMARY KEY CHECK(id=1), dirty INTEGER NOT NULL CHECK(dirty IN (0,1)),
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
)`;
const publicationAttemptsTable = `CREATE TABLE publication_attempts (
  attempt_cid TEXT PRIMARY KEY, run_cid TEXT NOT NULL
) WITHOUT ROWID`;
const publicationRecordsTable = `CREATE TABLE publication_records (
  attempt_cid TEXT NOT NULL REFERENCES publication_attempts(attempt_cid) ON DELETE CASCADE,
  sequence INTEGER NOT NULL CHECK(sequence>=0), record_cid TEXT NOT NULL UNIQUE,
  PRIMARY KEY(attempt_cid,sequence)
) WITHOUT ROWID`;
const publicationAttemptRunIndex = 'CREATE INDEX publication_attempt_runs ON publication_attempts(run_cid)';
const physicalObjectsTable = `CREATE TABLE physical_objects (
  cid TEXT PRIMARY KEY, byte_count INTEGER NOT NULL CHECK(byte_count>=0),
  device TEXT NOT NULL, inode TEXT NOT NULL
) WITHOUT ROWID`;
const physicalPreparationsTable = `CREATE TABLE physical_object_preparations (
  cid TEXT NOT NULL, byte_count INTEGER NOT NULL CHECK(byte_count>=0),
  device TEXT NOT NULL, inode TEXT NOT NULL, semantic_cid TEXT,
  PRIMARY KEY(cid,device,inode)
) WITHOUT ROWID`;
const physicalUsageTable = `CREATE TABLE physical_object_usage (
  id INTEGER PRIMARY KEY CHECK(id=1), complete INTEGER NOT NULL CHECK(complete IN (0,1)),
  objects INTEGER NOT NULL CHECK(objects>=0), bytes INTEGER NOT NULL CHECK(bytes>=0),
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
)`;
const metadataFenceTable = `CREATE TABLE metadata_deletion_fences (
  metadata_key TEXT PRIMARY KEY, run_cid TEXT NOT NULL,
  retired INTEGER NOT NULL CHECK(retired IN (0,1))
) WITHOUT ROWID`;
const metadataFenceCoverageTable = `CREATE TABLE metadata_deletion_fence_coverage (
  id INTEGER PRIMARY KEY CHECK(id=1), complete INTEGER NOT NULL CHECK(complete IN (0,1)),
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
)`;
const nativeInventoryTable = `CREATE TABLE native_publication_inventories (
  public_index_cid TEXT PRIMARY KEY, inventory_wire TEXT NOT NULL
) WITHOUT ROWID`;
const nativeInventoryUsageTable = `CREATE TABLE native_publication_inventory_usage (
  id INTEGER PRIMARY KEY CHECK(id=1), entries INTEGER NOT NULL CHECK(entries>=0),
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
)`;
const nativeReferencesTable = `CREATE TABLE native_publication_references (
  public_index_cid TEXT NOT NULL REFERENCES native_publication_inventories(public_index_cid) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK(kind IN ('contract','holding')),
  reference_cid TEXT NOT NULL CHECK(length(reference_cid)=71 AND reference_cid GLOB 'sha256:*'
    AND substr(reference_cid,8) NOT GLOB '*[^0-9a-f]*'),
  PRIMARY KEY(kind,reference_cid,public_index_cid)
) WITHOUT ROWID`;
const nativeReferenceOwnerIndex = 'CREATE INDEX native_publication_reference_owners ON native_publication_references(public_index_cid)';
const nativeReferenceInsert = `CREATE TRIGGER native_publication_references_insert
  AFTER INSERT ON native_publication_inventories BEGIN
  INSERT INTO native_publication_references
    SELECT new.public_index_cid,'contract',json_extract(value,'$.semantic_cid')
      FROM json_each(new.inventory_wire,'$.contract_objects')
    UNION SELECT new.public_index_cid,'holding',value
      FROM json_each(new.inventory_wire,'$.physical_holding_cids');
END`;
const nativeReferenceUpdate = `CREATE TRIGGER native_publication_references_update
  AFTER UPDATE OF inventory_wire ON native_publication_inventories BEGIN
  DELETE FROM native_publication_references WHERE public_index_cid=old.public_index_cid;
  INSERT INTO native_publication_references
    SELECT new.public_index_cid,'contract',json_extract(value,'$.semantic_cid')
      FROM json_each(new.inventory_wire,'$.contract_objects')
    UNION SELECT new.public_index_cid,'holding',value
      FROM json_each(new.inventory_wire,'$.physical_holding_cids');
END`;
const nativeIndexTable = `CREATE TABLE native_publication_indexes (
  metadata_key TEXT PRIMARY KEY, namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL, run_cid TEXT NOT NULL,
  public_index_cid TEXT NOT NULL UNIQUE REFERENCES native_publication_inventories(public_index_cid) ON DELETE CASCADE,
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991),
  UNIQUE(namespace_id,authority_scope_cid,run_cid),
  FOREIGN KEY(public_index_cid) REFERENCES publication_contracts(semantic_cid)
) WITHOUT ROWID`;
const nativeIndexMaterialsTable = `CREATE TABLE native_publication_materials (
  public_index_cid TEXT NOT NULL REFERENCES native_publication_indexes(public_index_cid) ON DELETE CASCADE,
  result_definition_cid TEXT NOT NULL, binding_cid TEXT NOT NULL, material_cid TEXT NOT NULL,
  PRIMARY KEY(material_cid,public_index_cid,result_definition_cid),
  UNIQUE(public_index_cid,result_definition_cid)
) WITHOUT ROWID`;
const publicationRecoveryTable = `CREATE TABLE publication_recovery (
  id INTEGER PRIMARY KEY CHECK(id=1), complete INTEGER NOT NULL CHECK(complete IN (0,1)),
  entries INTEGER NOT NULL CHECK(entries>=0),
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
)`;
const pendingPublicationTable = `CREATE TABLE pending_publications (
  public_index_cid TEXT PRIMARY KEY, inventory_wire TEXT NOT NULL
) WITHOUT ROWID`;
const publicationTable = `CREATE TABLE publication_contracts (
  semantic_cid TEXT PRIMARY KEY, name TEXT NOT NULL, wire TEXT NOT NULL,
  byte_count INTEGER NOT NULL CHECK(byte_count>=0)
) WITHOUT ROWID`;
const publicationUsageTable = `CREATE TABLE publication_usage (
  id INTEGER PRIMARY KEY CHECK(id=1), objects INTEGER NOT NULL CHECK(objects>=0),
  bytes INTEGER NOT NULL CHECK(bytes>=0),
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
)`;
const completionTable = `CREATE TABLE completions (
  attempt_cid TEXT PRIMARY KEY REFERENCES attempts(attempt_cid) ON DELETE CASCADE,
  record_cid TEXT NOT NULL UNIQUE, record_wire TEXT NOT NULL,
  receipt_cid TEXT NOT NULL, receipt_wire TEXT NOT NULL,
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
) WITHOUT ROWID`;
// Receipt identity excludes the attempt. Equal immutable receipts may be
// referenced by distinct attempt-owned completions, never merged into one ACK.
const completionReceiptIndex = 'CREATE INDEX completion_receipts ON completions(receipt_cid)';

export function selectDeliveryIndexCreation(create: boolean, prepare: Prepare, fail: Refuse) {
  const initialize = create && prepare(
    "SELECT name FROM sqlite_schema WHERE type='table' LIMIT 1").get() === undefined;
  // Private format 15 is intentionally breaking. Refuse old stores before
  // any persistent PRAGMA, DDL, permission change, or original-row mutation.
  if (!initialize && prepare('SELECT version FROM coverage WHERE id=1').get()?.version !== version) {
    fail('DeliveryAttemptIndexUnavailable');
  }
  return initialize;
}

export function admitDeliveryIndexSchema(
  initialize: boolean,
  initializeEmpty: boolean,
  maxEntries: number,
  prepare: Prepare,
  exec: (sql: string) => void,
  transaction: ReturnType<typeof createSqliteTransaction>,
  fail: Refuse,
) {
  // Only the Store's actual first format creation selects empty coverage.
  // An interrupted current-format initialization retains its coverage.
  if (initializeEmpty && !initialize) fail('DeliveryAttemptIndexUnavailable');
  const initialComplete = initializeEmpty ? 1 : 0;
  if (initialize) transaction.run(() => {
    exec(`CREATE TABLE coverage (
        id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL,
        complete INTEGER NOT NULL CHECK(complete IN (0,1)), entries INTEGER NOT NULL);
        INSERT INTO coverage VALUES(1,${version},${initialComplete},0);
        CREATE TABLE attempts (
          logical_key TEXT PRIMARY KEY, attempt_cid TEXT NOT NULL UNIQUE,
          grant_cid TEXT NOT NULL, run_cid TEXT NOT NULL,
          attempt_wire TEXT NOT NULL, grant_wire TEXT NOT NULL,
          ready INTEGER NOT NULL CHECK(ready IN (0,1))) WITHOUT ROWID;
        CREATE INDEX grant_attempts ON attempts(grant_cid);
        CREATE INDEX pending_attempts ON attempts(ready);
        CREATE INDEX run_attempts ON attempts(run_cid);
        CREATE TABLE grant_uses(grant_cid TEXT PRIMARY KEY, uses INTEGER NOT NULL CHECK(uses>=0)) WITHOUT ROWID;
        CREATE TABLE initial_records (
          attempt_cid TEXT PRIMARY KEY REFERENCES attempts(attempt_cid) ON DELETE CASCADE,
          initial_wire TEXT NOT NULL, initial_cid TEXT,
          ack_revision INTEGER NOT NULL DEFAULT 1 CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)) WITHOUT ROWID;
        CREATE UNIQUE INDEX initial_record_identity ON initial_records(initial_cid);
        ${completionTable}; ${completionReceiptIndex}; ${publicationTable}; ${publicationUsageTable};
        ${publicationAttemptsTable}; ${publicationRecordsTable}; ${publicationAttemptRunIndex};
        ${publicationRecoveryTable}; ${pendingPublicationTable};
        ${nativeInventoryTable}; ${nativeInventoryUsageTable};
        ${nativeReferencesTable}; ${nativeReferenceOwnerIndex}; ${nativeReferenceInsert}; ${nativeReferenceUpdate};
        ${nativeIndexTable}; ${nativeIndexMaterialsTable};
        ${metadataFenceTable}; ${metadataFenceCoverageTable};
        ${physicalObjectsTable}; ${physicalUsageTable}; ${physicalPreparationsTable};
        ${resultRecoveryTable}; INSERT INTO result_deletion_recovery VALUES(1,0,1);
        INSERT INTO physical_object_usage VALUES(1,${initialComplete},0,0,1);
        CREATE INDEX metadata_deletion_runs ON metadata_deletion_fences(run_cid);
        INSERT INTO metadata_deletion_fence_coverage VALUES(1,${initialComplete},1);
        INSERT INTO native_publication_inventory_usage VALUES(1,0,1);
        INSERT INTO publication_recovery VALUES(1,${initialComplete},0,1);
        INSERT INTO publication_usage VALUES(1,0,0,1);`);
  });
  const state = prepare('SELECT version,complete,entries FROM coverage WHERE id=1');
  const selected = state.get();
  if (selected?.version !== version || ![0,1].includes(selected.complete as number) ||
      !Number.isSafeInteger(selected.entries) || (selected.entries as number) < 0 || (selected.entries as number) > maxEntries) {
    fail('DeliveryAttemptIndexUnavailable');
  }
  const initialColumns = prepare('PRAGMA table_info(initial_records)').all();
  if (!['initial_cid','ack_revision'].every(name => initialColumns.some(row => row.name === name)) ||
      prepare("SELECT name FROM sqlite_schema WHERE type='index' AND name='initial_record_identity'").get() === undefined) {
    fail('DeliveryAttemptIndexUnavailable');
  }
  // Current-format metadata is admitted exactly, never repaired or upgraded.
  {
    // Reuse this connection's statement, not any schema row or admission.
    const schemaDefinition = prepare('SELECT sql FROM sqlite_schema WHERE type=? AND name=?');
    for (const [type,name,sql] of [
      ['table','completions',completionTable],
      ['index','completion_receipts',completionReceiptIndex],
      ['table','publication_contracts',publicationTable],
      ['table','publication_usage',publicationUsageTable],
      ['table','publication_recovery',publicationRecoveryTable],
      ['table','pending_publications',pendingPublicationTable],
      ['table','native_publication_inventories',nativeInventoryTable],
      ['table','native_publication_inventory_usage',nativeInventoryUsageTable],
      ['table','metadata_deletion_fences',metadataFenceTable],
      ['table','metadata_deletion_fence_coverage',metadataFenceCoverageTable],
      ['index','metadata_deletion_runs','CREATE INDEX metadata_deletion_runs ON metadata_deletion_fences(run_cid)'],
      ['table','physical_objects',physicalObjectsTable],
      ['table','physical_object_usage',physicalUsageTable],
      ['table','physical_object_preparations',physicalPreparationsTable],
      ['table','publication_attempts',publicationAttemptsTable],
      ['table','publication_records',publicationRecordsTable],
      ['index','publication_attempt_runs',publicationAttemptRunIndex],
      ['table','result_deletion_recovery',resultRecoveryTable],
      ['table','native_publication_references',nativeReferencesTable],
      ['index','native_publication_reference_owners',nativeReferenceOwnerIndex],
      ['trigger','native_publication_references_insert',nativeReferenceInsert],
      ['trigger','native_publication_references_update',nativeReferenceUpdate],
      ['table','native_publication_indexes',nativeIndexTable],
      ['table','native_publication_materials',nativeIndexMaterialsTable],
    ]) {
      if (schemaDefinition.get(type,name)?.sql !== sql) {
        fail('DeliveryAttemptIndexUnavailable');
      }
    }
  }
  const resultRecoveryRow = prepare('SELECT dirty,ack_revision FROM result_deletion_recovery WHERE id=1');
  const readResultRecovery = () => {
    const row = resultRecoveryRow.get();
    if (![0,1].includes(row?.dirty as number) || !Number.isSafeInteger(row!.ack_revision) || (row!.ack_revision as number) < 1) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    return Object.freeze({...row}) as ResultRecovery;
  };
  const resultRecovery = readResultRecovery();
  // This database's previously unused SQLite header field records only
  // derived physical-quota cleanliness, not a Run/Account or file ACK.
  if (prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name='physical_object_preparations'")
    .get()?.sql !== physicalPreparationsTable) fail('DeliveryAttemptIndexUnavailable');
  const physicalHeader = prepare('PRAGMA user_version').get()!.user_version;
  if (![0,1].includes(physicalHeader as number)) fail('DeliveryAttemptIndexUnavailable');
  return {state, selected, readResultRecovery, resultRecovery, physicalHeader};
}
