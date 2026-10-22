// Private lookup/claim metadata of the existing exclusively owned Store.
// Rows locate admitted originals; they do not authorize Result access.
import {DatabaseSync} from 'node:sqlite';
import {chmod} from 'node:fs/promises';
import {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';

const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const version = 9;
const physicalObjectsTable = `CREATE TABLE physical_objects (
  cid TEXT PRIMARY KEY, byte_count INTEGER NOT NULL CHECK(byte_count>=0),
  device TEXT NOT NULL, inode TEXT NOT NULL
) WITHOUT ROWID`;
const physicalPreparationsTable = `CREATE TABLE physical_object_preparations (
  cid TEXT NOT NULL, byte_count INTEGER NOT NULL CHECK(byte_count>=0),
  device TEXT NOT NULL, inode TEXT NOT NULL,
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
  receipt_cid TEXT NOT NULL UNIQUE, receipt_wire TEXT NOT NULL,
  ack_revision INTEGER NOT NULL CHECK(ack_revision>=1 AND ack_revision<=9007199254740991)
) WITHOUT ROWID`;

export async function openDeliveryAttemptIndex(path, {create, maxEntries, maxWireBytes}) {
  const database = new DatabaseSync(path, {__proto__: null, open: false,
    readOnly: false, enableForeignKeyConstraints: true, allowExtension: false});
  let closeOriginal, isOpenOriginal, execOriginal, prepareOriginal, transactionState;
  let closed = false, closing = false, mutating = false, sealPhysicalLifetime,
    sealPublicationFinishes, retirePublicationFinishReferences, publicationFinishClosing = false;
  const exec = sql => Reflect.apply(execOriginal,database,[sql]);
  const prepare = sql => {
    const original = Reflect.apply(prepareOriginal,database,[sql]);
    const get = original.get, run = original.run, all = original.all;
    return Object.freeze({get: (...args) => Reflect.apply(get,original,args),
      run: (...args) => Reflect.apply(run,original,args),
      all: (...args) => Reflect.apply(all,original,args)});
  };
  const captureClose = () => {
    closeOriginal ??= database.close;
    isOpenOriginal ??= Object.getOwnPropertyDescriptor(database, 'isOpen')?.get;
    if (typeof closeOriginal !== 'function' || typeof isOpenOriginal !== 'function') {
      fail('DeliveryAttemptIndexCleanupUnavailable');
    }
  };
  const close = () => {
    if (closed) return true;
    if (closing || mutating) fail('DeliveryAttemptIndexCleanupPending');
    sealPhysicalLifetime?.();
    sealPublicationFinishes?.();
    closing = true;
    try {
      captureClose();
      const opened = Reflect.apply(isOpenOriginal, database, []);
      if (typeof opened !== 'boolean') fail('DeliveryAttemptIndexCleanupPending');
      if (opened && (Reflect.apply(closeOriginal, database, []) !== undefined ||
          Reflect.apply(isOpenOriginal, database, []) !== false)) {
        fail('DeliveryAttemptIndexCleanupPending');
      }
      closed = true;
      retirePublicationFinishReferences?.();
      return true;
    } finally { closing = false; }
  };
  const retainFailure = primary => {
    try { close(); } catch {}
    if (closed) return primary;
    // Opening can also hold a payload/reader duty. Neither close depends on
    // the other; retaining this native wrapper must not hide the first child.
    const child = primary?.cleanupHandle;
    const childStatus = child?.status, childRetry = child?.retry;
    let childPending = child !== undefined, flight;
    const failure = Object.assign(new Error('DeliveryAttemptIndexCleanupPending', {cause: primary}),
      {code: 'DeliveryAttemptIndexCleanupPending', primaryFailure: primary, cleanupPending: true});
    const status = () => Object.freeze({pending: !closed || childPending});
    const retry = () => {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(async () => {
        let firstFailure;
        if (childPending) {
          try {
            if (typeof childStatus !== 'function' || typeof childRetry !== 'function') {
              fail('DeliveryAttemptIndexCleanupPending');
            }
            let observation = await Reflect.apply(childStatus,child,[]);
            if (observation?.pending !== false) {
              await Reflect.apply(childRetry,child,[]);
              observation = await Reflect.apply(childStatus,child,[]);
            }
            const pending = observation !== null && typeof observation === 'object'
              ? Object.getOwnPropertyDescriptor(observation,'pending') : undefined;
            if (pending?.value !== false) fail('DeliveryAttemptIndexCleanupPending');
            childPending = false;
          } catch (error) { firstFailure = {error}; }
        }
        try { close(); } catch (error) { firstFailure ??= {error}; }
        failure.cleanupPending = status().pending;
        if (firstFailure !== undefined) throw firstFailure.error;
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    };
    failure.cleanupHandle = Object.freeze({status, retry});
    return failure;
  };
  try {
    captureClose();
    execOriginal = database.exec;
    prepareOriginal = database.prepare;
    transactionState = Object.getOwnPropertyDescriptor(database,'isTransaction')?.get;
    if (typeof transactionState !== 'function') fail('DeliveryAttemptIndexUnavailable');
    database.open();
    if (create) await chmod(path, 0o600);
    // Match the Store's original durable synchronization boundary on Darwin;
    // FULL alone is not the same as libuv's fullfsync selection there.
    if (create) exec('PRAGMA journal_mode=WAL');
    const mode = prepare('PRAGMA journal_mode').get().journal_mode;
    if (mode !== 'wal') fail('DeliveryAttemptIndexUnavailable');
    exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; PRAGMA checkpoint_fullfsync=ON; PRAGMA mmap_size=0; PRAGMA cache_size=-64; PRAGMA temp_store=MEMORY');
    const transaction = createSqliteTransaction({exec,
      get isTransaction() { return Reflect.apply(transactionState,database,[]); }},
    'DeliveryAttemptIndex');
    const initialize = create && prepare(
      "SELECT name FROM sqlite_schema WHERE type='table' LIMIT 1").get() === undefined;
    if (initialize) transaction.run(() => {
      exec(`CREATE TABLE coverage (
        id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL,
        complete INTEGER NOT NULL CHECK(complete IN (0,1)), entries INTEGER NOT NULL);
        INSERT INTO coverage VALUES(1,9,0,0);
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
        ${completionTable}; ${publicationTable}; ${publicationUsageTable};
        ${publicationRecoveryTable}; ${pendingPublicationTable};
        ${nativeInventoryTable}; ${nativeInventoryUsageTable};
        ${metadataFenceTable}; ${metadataFenceCoverageTable};
        ${physicalObjectsTable}; ${physicalUsageTable}; ${physicalPreparationsTable};
        INSERT INTO physical_object_usage VALUES(1,0,0,0,1);
        CREATE INDEX metadata_deletion_runs ON metadata_deletion_fences(run_cid);
        INSERT INTO metadata_deletion_fence_coverage VALUES(1,0,1);
        INSERT INTO native_publication_inventory_usage VALUES(1,0,1);
        INSERT INTO publication_recovery VALUES(1,0,0,1);
        INSERT INTO publication_usage VALUES(1,0,0,1);`);
    });
    const state = prepare('SELECT version,complete,entries FROM coverage WHERE id=1');
    const selected = state.get();
    if (![1,2,3,4,5,6,7,8,version].includes(selected?.version) || ![0,1].includes(selected.complete) ||
        !Number.isSafeInteger(selected.entries) || selected.entries < 0 || selected.entries > maxEntries) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    // Additive private progress metadata. Old attempts retain their original
    // pending/ready protocol; a joint START stores its initial record in the
    // SAME claim transaction, not a second progress-only COMMIT after files.
    const initialTable = prepare(
      "SELECT name FROM sqlite_schema WHERE type='table' AND name='initial_records'").get();
    if (selected.version === 1) transaction.run(() => {
      if (initialTable !== undefined) fail('DeliveryAttemptIndexUnavailable');
      exec(`CREATE TABLE initial_records (
        attempt_cid TEXT PRIMARY KEY REFERENCES attempts(attempt_cid) ON DELETE CASCADE,
        initial_wire TEXT NOT NULL) WITHOUT ROWID;
        UPDATE coverage SET version=2 WHERE id=1;`);
    });
    else if (initialTable === undefined) fail('DeliveryAttemptIndexUnavailable');
    // New joint START bodies are native originals. Null preserves the older
    // file-backed protocol without scanning or parsing historical rows here.
    if (selected.version < 3) transaction.run(() => {
      exec(`ALTER TABLE initial_records ADD COLUMN initial_cid TEXT;
        CREATE UNIQUE INDEX initial_record_identity ON initial_records(initial_cid);
        UPDATE coverage SET version=3 WHERE id=1;`);
    });
    else if (!prepare("PRAGMA table_info(initial_records)").all().some(row=>row.name==='initial_cid') ||
        prepare("SELECT name FROM sqlite_schema WHERE type='index' AND name='initial_record_identity'").get() === undefined) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    if(selected.version<4) transaction.run(()=>exec(`ALTER TABLE initial_records ADD COLUMN
      ack_revision INTEGER NOT NULL DEFAULT 1 CHECK(ack_revision>=1 AND ack_revision<=9007199254740991);
      ${completionTable}; UPDATE coverage SET version=4 WHERE id=1;`));
    else if(prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name='completions'").get()?.sql!==completionTable) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    if(!prepare('PRAGMA table_info(initial_records)').all().some(row=>row.name==='ack_revision')) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    if (selected.version < 5) transaction.run(() => {
      // Only the old version permits first adoption. Missing adopted metadata
      // is never repaired by resetting its capacity counters or originals.
      exec(`${publicationTable}; ${publicationUsageTable};
        INSERT INTO publication_usage VALUES(1,0,0,1);
        UPDATE coverage SET version=5 WHERE id=1;`);
    });
    for (const [name, sql] of [['publication_contracts', publicationTable],
      ['publication_usage', publicationUsageTable]]) {
      if (prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name=?").get(name)?.sql !== sql) {
        fail('DeliveryAttemptIndexUnavailable');
      }
    }
    if (selected.version < 6) transaction.run(() => {
      // Atomic private-format adoption. An adopted missing table is refusal,
      // never permission to reconstruct coverage from historical state again.
      exec(`${publicationRecoveryTable}; ${pendingPublicationTable};
        INSERT INTO publication_recovery VALUES(1,0,0,1);
        UPDATE coverage SET version=6 WHERE id=1;`);
    });
    for (const [name,sql] of [['publication_recovery',publicationRecoveryTable],
      ['pending_publications',pendingPublicationTable]]) {
      if (prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name=?").get(name)?.sql !== sql) {
        fail('DeliveryAttemptIndexUnavailable');
      }
    }
    if (selected.version < 7) transaction.run(() => {
      exec(`${nativeInventoryTable}; ${nativeInventoryUsageTable};
        INSERT INTO native_publication_inventory_usage VALUES(1,0,1);
        UPDATE coverage SET version=7 WHERE id=1;`);
    });
    for (const [name,sql] of [['native_publication_inventories',nativeInventoryTable],
      ['native_publication_inventory_usage',nativeInventoryUsageTable]]) {
      if (prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name=?").get(name)?.sql !== sql) {
        fail('DeliveryAttemptIndexUnavailable');
      }
    }
    if (selected.version < 8) transaction.run(() => {
      exec(`${metadataFenceTable}; ${metadataFenceCoverageTable};
        CREATE INDEX metadata_deletion_runs ON metadata_deletion_fences(run_cid);
        INSERT INTO metadata_deletion_fence_coverage VALUES(1,0,1);
        UPDATE coverage SET version=8 WHERE id=1;`);
    });
    for (const [name,sql] of [['metadata_deletion_fences',metadataFenceTable],
      ['metadata_deletion_fence_coverage',metadataFenceCoverageTable]]) {
      if (prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name=?").get(name)?.sql !== sql) {
        fail('DeliveryAttemptIndexUnavailable');
      }
    }
    if (prepare("SELECT sql FROM sqlite_schema WHERE type='index' AND name='metadata_deletion_runs'").get()?.sql !==
        'CREATE INDEX metadata_deletion_runs ON metadata_deletion_fences(run_cid)') fail('DeliveryAttemptIndexUnavailable');
    if (selected.version < 9) transaction.run(() => {
      exec(`${physicalObjectsTable}; ${physicalUsageTable}; ${physicalPreparationsTable};
        INSERT INTO physical_object_usage VALUES(1,0,0,0,1);
        UPDATE coverage SET version=9 WHERE id=1;`);
    });
    for (const [name,sql] of [['physical_objects',physicalObjectsTable],
      ['physical_object_usage',physicalUsageTable], ['physical_object_preparations',physicalPreparationsTable]]) {
      if (prepare("SELECT sql FROM sqlite_schema WHERE type='table' AND name=?").get(name)?.sql !== sql) {
        fail('DeliveryAttemptIndexUnavailable');
      }
    }
    // This database's previously unused SQLite header field records only
    // derived physical-quota cleanliness, not a Run/Account or file ACK.
    const physicalHeader = prepare('PRAGMA user_version').get().user_version;
    if (![0,1].includes(physicalHeader)) fail('DeliveryAttemptIndexUnavailable');
    let physicalRecoveryRequired = physicalHeader === 1, physicalLifetime;
    let complete = selected.complete === 1;
    const metadataFence = prepare('SELECT * FROM metadata_deletion_fences WHERE metadata_key=?');
    const physicalObject = prepare('SELECT * FROM physical_objects WHERE cid=?');
    const physicalPreparation = prepare('SELECT * FROM physical_object_preparations WHERE cid=? AND device=? AND inode=?');
    const insertPhysicalPreparation = prepare('INSERT INTO physical_object_preparations VALUES(?,?,?,?)');
    const deletePhysicalPreparation = prepare('DELETE FROM physical_object_preparations WHERE cid=? AND device=? AND inode=?');
    const insertPhysicalObject = prepare('INSERT INTO physical_objects VALUES(?,?,?,?)');
    const deletePhysicalObject = prepare('DELETE FROM physical_objects WHERE cid=?');
    const physicalUsage = prepare('SELECT * FROM physical_object_usage WHERE id=1');
    const updatePhysicalUsage = prepare(`UPDATE physical_object_usage SET objects=objects+?,
      bytes=bytes+?,ack_revision=ack_revision+1 WHERE id=1`);
    const runMetadataFence = prepare('SELECT * FROM metadata_deletion_fences WHERE run_cid=? LIMIT 1');
    const insertMetadataFence = prepare('INSERT INTO metadata_deletion_fences VALUES(?,?,?)');
    const retireMetadataFence = prepare('UPDATE metadata_deletion_fences SET retired=1 WHERE metadata_key=? AND run_cid=?');
    const metadataFenceCoverage = prepare('SELECT complete,ack_revision FROM metadata_deletion_fence_coverage WHERE id=1');
    const acknowledgeMetadataFences = prepare('UPDATE metadata_deletion_fence_coverage SET ack_revision=ack_revision+1 WHERE id=1');
    const nativeInventory = prepare('SELECT * FROM native_publication_inventories WHERE public_index_cid=?');
    const nativeInventories = prepare('SELECT * FROM native_publication_inventories ORDER BY public_index_cid LIMIT ?');
    const insertNativeInventory = prepare('INSERT INTO native_publication_inventories VALUES(?,?)');
    const removeNativeInventory = prepare('DELETE FROM native_publication_inventories WHERE public_index_cid=?');
    const nativeInventoryUsage = prepare('SELECT entries,ack_revision FROM native_publication_inventory_usage WHERE id=1');
    const updateNativeInventoryUsage = prepare(`UPDATE native_publication_inventory_usage SET entries=entries+?,
      ack_revision=ack_revision+1 WHERE id=1`);
    const publicationRecovery = prepare('SELECT complete,entries,ack_revision FROM publication_recovery WHERE id=1');
    const pendingPublication = prepare('SELECT * FROM pending_publications WHERE public_index_cid=?');
    const pendingPublications = prepare('SELECT * FROM pending_publications ORDER BY public_index_cid LIMIT ?');
    const insertPendingPublication = prepare('INSERT INTO pending_publications VALUES(?,?)');
    const removePendingPublication = prepare('DELETE FROM pending_publications WHERE public_index_cid=?');
    const updatePublicationRecovery = prepare(`UPDATE publication_recovery SET entries=entries+?,
      ack_revision=ack_revision+1 WHERE id=1`);
    const lookup = prepare(`SELECT attempts.*,initial_records.initial_wire,initial_records.initial_cid FROM attempts
      LEFT JOIN initial_records USING(attempt_cid) WHERE logical_key=?`);
    const byAttempt = prepare(`SELECT attempts.*,initial_records.initial_wire,initial_records.initial_cid FROM attempts
      LEFT JOIN initial_records USING(attempt_cid) WHERE attempt_cid=?`);
    const nativeContract = prepare(`SELECT 'delivery_attempt' AS name,attempt_wire AS wire
      FROM attempts JOIN initial_records USING(attempt_cid) WHERE attempt_cid=? AND initial_cid IS NOT NULL
      UNION ALL SELECT 'result_read_grant',grant_wire FROM attempts JOIN initial_records USING(attempt_cid)
      WHERE grant_cid=? AND initial_cid IS NOT NULL
      UNION ALL SELECT 'delivery_record',initial_wire FROM initial_records WHERE initial_cid=?
      UNION ALL SELECT 'delivery_record',record_wire FROM completions WHERE record_cid=?
      UNION ALL SELECT 'result_delivery_receipt',receipt_wire FROM completions WHERE receipt_cid=? LIMIT 1`);
    const publication = prepare('SELECT * FROM publication_contracts WHERE semantic_cid=?');
    const publicationUsage = prepare('SELECT objects,bytes,ack_revision FROM publication_usage WHERE id=1');
    const insertPublication = prepare('INSERT INTO publication_contracts VALUES(?,?,?,?)');
    const removePublication = prepare('DELETE FROM publication_contracts WHERE semantic_cid=?');
    const updatePublicationUsage = prepare(`UPDATE publication_usage SET objects=objects+?,bytes=bytes+?,
      ack_revision=ack_revision+1 WHERE id=1`);
    const completion = prepare('SELECT * FROM completions WHERE attempt_cid=?');
    const initialRecord = prepare('SELECT * FROM initial_records WHERE attempt_cid=?');
    const confirmInitial = prepare('UPDATE initial_records SET ack_revision=ack_revision+1 WHERE attempt_cid=? AND initial_cid=?');
    const insertCompletion = prepare('INSERT INTO completions VALUES(?,?,?,?,?,1)');
    const confirmCompletion = prepare('UPDATE completions SET ack_revision=ack_revision+1 WHERE attempt_cid=? AND record_cid=?');
    const byRun = prepare(`SELECT attempts.*,initial_records.initial_wire,initial_records.initial_cid FROM attempts
      LEFT JOIN initial_records USING(attempt_cid) WHERE run_cid=? LIMIT ?`);
    const pending = prepare('SELECT * FROM attempts WHERE ready=0 LIMIT ?');
    const insert = prepare('INSERT INTO attempts VALUES(?,?,?,?,?,?,?)');
    const insertInitial = prepare('INSERT INTO initial_records VALUES(?,?,?,1)');
    const uses = prepare('SELECT uses FROM grant_uses WHERE grant_cid=?');
    const addUse = prepare('INSERT INTO grant_uses VALUES(?,1) ON CONFLICT(grant_cid) DO UPDATE SET uses=uses+1');
    const removeUses = prepare('UPDATE grant_uses SET uses=uses-? WHERE grant_cid=?');
    const runUses = prepare('SELECT grant_cid,count(*) AS uses FROM attempts WHERE run_cid=? GROUP BY grant_cid');
    const ready = prepare('UPDATE attempts SET ready=1 WHERE logical_key=? AND attempt_cid=?');
    const remove = prepare('DELETE FROM attempts WHERE run_cid=?');
    const updateCount = prepare('UPDATE coverage SET entries=entries+? WHERE id=1');
    let uncertain = false, uncertainRemoval, uncertainCompletion, uncertainInitial, confirmedRecord,
      uncertainPublication, uncertainPublicationRecovery, uncertainMetadataFence, uncertainPhysical,
      uncertainPhysicalPreparation, uncertainPhysicalSeal = false, uncertainPublicationFinishSeal = false;
    const retainedPublicationFinishes = new Map();
    let flushPublicationFinishes = () => [];
    const run = body => {
      if (mutating) fail('DeliveryAttemptIndexBusy');
      mutating = true;
      try {
        let finished;
        const result = transaction.run(() => {
          const value = body();
          finished = flushPublicationFinishes();
          return value;
        });
        // Only this transaction's real COMMIT retires retained completion
        // originals. A thrown/lost reply keeps them for the SAME retry.
        for (const original of finished) {
          if (retainedPublicationFinishes.get(original.public_index_cid) === original) {
            retainedPublicationFinishes.delete(original.public_index_cid);
          }
        }
        return result;
      }
      catch (error) {
        if (error?.outcome === 'unknown') uncertain = true;
        throw error;
      } finally { mutating = false; }
    };
    const requireOpen = () => {
      if (closed || closing) fail('DeliveryAttemptIndexClosed');
      if (physicalLifetime?.sealing || publicationFinishClosing) fail('DeliveryAttemptIndexCleanupPending');
      if (mutating) fail('DeliveryAttemptIndexBusy');
      if (uncertain) fail('DeliveryAttemptIndexCommitOutcomeUnknown');
      transaction.assertUsable();
    };
    const requireComplete = () => {
      requireOpen();
      if (!complete) fail('DeliveryAttemptIndexUnavailable');
    };
    const storedPhysicalState = () => {
      const row = physicalUsage.get();
      if (!row || ![0,1].includes(row.complete) ||
          ![row.objects,row.bytes,row.ack_revision].every(Number.isSafeInteger) ||
          row.objects<0 || row.objects>maxEntries || row.bytes<0 || row.ack_revision<1 ||
          row.complete===0 && (row.objects!==0 || row.bytes!==0)) {
        fail('DeliveryAttemptIndexUnavailable');
      }
      return Object.freeze({...row});
    };
    const physicalState = () => physicalLifetime === undefined ? storedPhysicalState() :
      Object.freeze({...physicalLifetime.base,objects:physicalLifetime.objects,bytes:physicalLifetime.bytes});
    const physicalOriginal = row => {
      if (!row || !cid(row.cid) || !Number.isSafeInteger(row.byte_count) ||
          row.byte_count<0 || row.byte_count>maxWireBytes ||
          typeof row.device!=='string' || !/^(0|[1-9][0-9]*)$/u.test(row.device) ||
          typeof row.inode!=='string' || !/^(0|[1-9][0-9]*)$/u.test(row.inode)) {
        fail('InvalidDeliveryAttemptIndex');
      }
      return Object.freeze({cid:row.cid,byte_count:row.byte_count,device:row.device,inode:row.inode});
    };
    const samePhysical = (a,b) => a!==undefined && b!==undefined &&
      ['cid','byte_count','device','inode'].every(key=>a[key]===b[key]);
    const sameOptionalPhysical = (a,b) => a===undefined ? b===undefined : samePhysical(a,b);
    const selectedPhysical = key => {
      const change=physicalLifetime?.changes.get(key);
      if(change!==undefined)return change.after;
      const row=physicalObject.get(key);return row===undefined?undefined:physicalOriginal(row);
    };
    const preparationKey = row => row.cid+'\0'+row.device+'\0'+row.inode;
    const mutateLifetimePhysical = (kind,originals) => {
      requireComplete();
      const updates=[];let count=0,bytes=0;
      for(const row of originals){
        const current=selectedPhysical(row.cid);
        const retiring=physicalLifetime.retiring.get(preparationKey(row));
        if(kind==='remove'&&retiring!==undefined&&!samePhysical(current,row)){
          if(!samePhysical(retiring,row))fail('PublicationObjectAccountingMismatch');
          updates.push({retire:preparationKey(row)});count--;bytes-=row.byte_count;continue;
        }
        if(current!==undefined&&!samePhysical(current,row)&&
            !(kind==='record'&&physicalLifetime.retiring.has(preparationKey(current))))fail('PublicationObjectAccountingMismatch');
        if(kind==='record'?!samePhysical(current,row):current!==undefined){
          count+=kind==='record'?1:-1;bytes+=kind==='record'?row.byte_count:-row.byte_count;
          const previous=physicalLifetime.changes.get(row.cid);
          const before=previous===undefined?current:previous.before;
          updates.push({key:row.cid,before,after:kind==='record'?row:undefined});
        }
      }
      const objects=physicalLifetime.objects+count,total=physicalLifetime.bytes+bytes;
      if(!Number.isSafeInteger(total)||total<0||objects<0||objects>maxEntries)fail('DeliveryAttemptIndexLimit');
      for(const change of updates){
        if(change.retire!==undefined){physicalLifetime.retiring.delete(change.retire);continue;}
        if(sameOptionalPhysical(change.before,change.after))physicalLifetime.changes.delete(change.key);
        else physicalLifetime.changes.set(change.key,Object.freeze(change));
      }
      if(kind==='record')for(const row of originals)physicalLifetime.preparations.delete(preparationKey(row));
      else for(const row of originals)physicalLifetime.retiring.delete(preparationKey(row));
      physicalLifetime.objects=objects;physicalLifetime.bytes=total;
      return physicalState();
    };
    sealPhysicalLifetime = () => {
      if(physicalLifetime===undefined||physicalLifetime.sealed)return;
      // An unrelated unknown business mutation may close its real database
      // without inventing a clean quota seal. Restart then audits actual files.
      if((uncertain&&!uncertainPhysicalSeal)||!transaction.connectionUsable)return;
      if(physicalLifetime.preparations.size!==0||physicalLifetime.retiring.size!==0)fail('DeliveryAttemptIndexCleanupPending');
      const original=physicalLifetime.seal??=Object.freeze({
        changes:Object.freeze([...physicalLifetime.changes.values()]),
        objects:physicalLifetime.objects,bytes:physicalLifetime.bytes});
      physicalLifetime.sealing=true;
      try{
        run(()=>{
          const persisted=storedPhysicalState();
          const sameBase=persisted.objects===physicalLifetime.base.objects&&persisted.bytes===physicalLifetime.base.bytes;
          const sameSealed=persisted.objects===original.objects&&persisted.bytes===original.bytes;
          if(!sameBase&&!(uncertainPhysicalSeal&&sameSealed))fail('PublicationObjectAccountingMismatch');
          for(const change of original.changes){
            const value=physicalObject.get(change.key),current=value===undefined?undefined:physicalOriginal(value);
            if(!sameOptionalPhysical(current,change.before)&&
                !(uncertainPhysicalSeal&&sameOptionalPhysical(current,change.after)))fail('PublicationObjectAccountingMismatch');
            deletePhysicalObject.run(change.key);
            if(change.after!==undefined){const row=change.after;insertPhysicalObject.run(row.cid,row.byte_count,row.device,row.inode);}
          }
          if(prepare(`UPDATE physical_object_usage SET objects=?,bytes=?,ack_revision=ack_revision+1 WHERE id=1 AND complete=1`)
            .run(original.objects,original.bytes).changes!==1)fail('DeliveryAttemptIndexUnavailable');
          exec('PRAGMA user_version=0');
        });
        physicalLifetime.sealed=true;uncertainPhysicalSeal=false;uncertain=false;
      }catch(error){if(error?.outcome==='unknown')uncertainPhysicalSeal=true;throw error;}
    };
    const mutatePhysical = (kind,values) => {
      if (!Array.isArray(values) || values.length>maxEntries) fail('DeliveryAttemptIndexLimit');
      const originals=values.map(physicalOriginal);
      if (new Set(originals.map(row=>row.cid)).size!==originals.length) fail('InvalidDeliveryAttemptIndex');
      if(physicalLifetime!==undefined)return mutateLifetimePhysical(kind,originals);
      const sameOriginals = prior => prior?.length===originals.length &&
        prior.every((row,index)=>samePhysical(row,originals[index]));
      // Physical cleanup may settle the SAME uncertain installation only
      // after its caller has observed unlink/directory ACK. Other work stays
      // blocked; neither a read nor process exit confirms the lost COMMIT.
      const retry=uncertain && sameOriginals(uncertainPhysical?.originals) &&
        (uncertainPhysical.kind===kind || uncertainPhysical.kind==='record' && kind==='remove');
      if (retry) {
        if (closed||closing||mutating||!complete) fail('DeliveryAttemptIndexCleanupPending');
        transaction.assertUsable();
      } else requireComplete();
      const before=physicalState();
      if (before.complete!==1) fail('DeliveryAttemptIndexUnavailable');
      let objects=0,bytes=0;
      const changes=originals.filter(row=>{
        const retained=physicalObject.get(row.cid);
        if (retained!==undefined && !samePhysical(physicalOriginal(retained),row)) {
          fail('PublicationObjectAccountingMismatch');
        }
        const change=kind==='record'?retained===undefined:retained!==undefined;
        if(change){objects++;bytes+=row.byte_count;}
        return change;
      });
      if (!Number.isSafeInteger(bytes) || kind==='record' &&
          (before.objects+objects>maxEntries || !Number.isSafeInteger(before.bytes+bytes))) {
        fail('DeliveryAttemptIndexLimit');
      }
      const prepared = kind==='record' ? originals.filter(row=>{
        const retained=physicalPreparation.get(row.cid,row.device,row.inode);
        if(retained!==undefined&&!samePhysical(physicalOriginal(retained),row))fail('PublicationObjectAccountingMismatch');
        return retained!==undefined;
      }) : [];
      if (changes.length===0 && prepared.length===0 && !retry) return before;
      try {
        run(()=>{
          for(const row of changes) {
            if(kind==='record') insertPhysicalObject.run(row.cid,row.byte_count,row.device,row.inode);
            else deletePhysicalObject.run(row.cid);
          }
          for(const row of prepared)deletePhysicalPreparation.run(row.cid,row.device,row.inode);
          const sign=kind==='record'?1:-1;
          updatePhysicalUsage.run(sign*objects,sign*bytes);
        });
        if(retry){uncertain=false;uncertainPhysical=undefined;}
        return physicalState();
      } catch(error) {
        if(error?.outcome==='unknown') uncertainPhysical={kind,originals};
        throw error;
      }
    };
    const mutatePhysicalPreparation = (kind,values) => {
      if(!Array.isArray(values)||values.length>maxEntries)fail('DeliveryAttemptIndexLimit');
      const originals=values.map(physicalOriginal);
      if(new Set(originals.map(row=>row.cid)).size!==originals.length)fail('InvalidDeliveryAttemptIndex');
      if(physicalLifetime!==undefined){
        requireComplete();
        const changes=originals.filter(row=>{
          const retained=physicalLifetime.preparations.get(preparationKey(row));
          if(retained!==undefined&&!samePhysical(retained,row))fail('PublicationObjectAccountingMismatch');
          return kind==='stage'?retained===undefined:retained!==undefined;
        });
        if(kind==='stage'&&physicalLifetime.preparations.size+changes.length>maxEntries)fail('DeliveryAttemptIndexLimit');
        for(const row of changes){
          if(kind==='stage')physicalLifetime.preparations.set(preparationKey(row),row);
          else physicalLifetime.preparations.delete(preparationKey(row));
        }
        return;
      }
      const retry=uncertain && uncertainPhysicalPreparation?.originals.length===originals.length &&
        uncertainPhysicalPreparation.originals.every((row,index)=>samePhysical(row,originals[index])) &&
        (uncertainPhysicalPreparation.kind===kind ||
          uncertainPhysicalPreparation.kind==='stage' && kind==='finish');
      if(retry){
        if(closed||closing||mutating||!complete)fail('DeliveryAttemptIndexCleanupPending');
        transaction.assertUsable();
      }else requireComplete();
      if(physicalState().complete!==1)fail('DeliveryAttemptIndexUnavailable');
      const changes=originals.filter(row=>{
        const retained=physicalPreparation.get(row.cid,row.device,row.inode);
        if(retained!==undefined&&!samePhysical(physicalOriginal(retained),row))fail('PublicationObjectAccountingMismatch');
        return kind==='stage'?retained===undefined:retained!==undefined;
      });
      if(kind==='stage' && prepare('SELECT count(*) AS n FROM physical_object_preparations').get().n+
          changes.length>maxEntries)fail('DeliveryAttemptIndexLimit');
      if(changes.length===0&&!retry)return;
      try{
        run(()=>{
          for(const row of changes) {
            if(kind==='stage')insertPhysicalPreparation.run(row.cid,row.byte_count,row.device,row.inode);
            else deletePhysicalPreparation.run(row.cid,row.device,row.inode);
          }
          // A real write also confirms an idempotent retry after lost COMMIT.
          updatePhysicalUsage.run(0,0);
        });
        if(retry){uncertain=false;uncertainPhysicalPreparation=undefined;}
      }catch(error){
        if(error?.outcome==='unknown')uncertainPhysicalPreparation={kind,originals};
        throw error;
      }
    };
    const validate = row => {
      if (!row || typeof row.logical_key !== 'string' ||
          Buffer.byteLength(row.logical_key, 'utf8') > 2 * maxWireBytes ||
          ![row.attempt_cid,row.grant_cid,row.run_cid].every(cid) ||
          row.ready !== undefined && ![0,1].includes(row.ready) ||
          ![row.attempt_wire,row.grant_wire].every(wire => typeof wire === 'string' &&
            Buffer.byteLength(wire,'utf8') <= maxWireBytes) ||
          row.initial_wire != null && (typeof row.initial_wire !== 'string' ||
            Buffer.byteLength(row.initial_wire,'utf8') > maxWireBytes) ||
          row.initial_cid != null && (!cid(row.initial_cid) || row.initial_wire == null)) fail('InvalidDeliveryAttemptIndex');
      return row;
    };
    const copy = row => row === undefined ? undefined : Object.freeze({...validate(row)});
    const completionCopy = row => {
      if(row===undefined) return undefined;
      if(![row.attempt_cid,row.record_cid,row.receipt_cid].every(cid) ||
          ![row.record_wire,row.receipt_wire].every(wire=>typeof wire==='string'&&Buffer.byteLength(wire,'utf8')<=maxWireBytes) ||
          !Number.isSafeInteger(row.ack_revision) || row.ack_revision<1) fail('InvalidDeliveryAttemptIndex');
      return Object.freeze({...row});
    };
    const sameCompletion = (left,right) => left!==undefined && right!==undefined &&
      ['attempt_cid','record_cid','record_wire','receipt_cid','receipt_wire','prior_cid'].every(key=>left[key]===right[key]);
    const add = (row, isReady, initialWire, initialCid) => {
      validate(row);
      insert.run(row.logical_key,row.attempt_cid,row.grant_cid,row.run_cid,
        row.attempt_wire,row.grant_wire,isReady);
      if (initialWire !== undefined) insertInitial.run(row.attempt_cid,initialWire,initialCid??null);
      updateCount.run(1);
      addUse.run(row.grant_cid);
    };
    const usage = () => {
      const row = publicationUsage.get();
      if (!row || ![row.objects,row.bytes,row.ack_revision].every(Number.isSafeInteger) ||
          row.objects < 0 || row.objects > maxEntries || row.bytes < 0 || row.ack_revision < 1) {
        fail('InvalidDeliveryAttemptIndex');
      }
      return Object.freeze({...row});
    };
    const publicationCopy = row => {
      if (row === undefined) return undefined;
      if (!cid(row.semantic_cid) || typeof row.name !== 'string' || row.name.length === 0 ||
          Buffer.byteLength(row.name,'utf8') > maxWireBytes ||
          typeof row.wire !== 'string' || !Number.isSafeInteger(row.byte_count) ||
          row.byte_count < 0 || row.byte_count > maxWireBytes ||
          Buffer.byteLength(row.wire,'utf8') !== row.byte_count) fail('InvalidDeliveryAttemptIndex');
      return Object.freeze({...row});
    };
    const samePublication = (left,right) => left !== undefined && right !== undefined &&
      ['semantic_cid','name','wire','byte_count'].every(key => left[key] === right[key]);
    const recoveryState = () => {
      const row=publicationRecovery.get();
      if (!row || ![0,1].includes(row.complete) ||
          !Number.isSafeInteger(row.entries) || row.entries<0 || row.entries>maxEntries ||
          !Number.isSafeInteger(row.ack_revision) || row.ack_revision<1 ||
          row.complete===0 && row.entries!==0) fail('DeliveryAttemptIndexUnavailable');
      return row;
    };
    const recoveryOriginal = row => {
      if (!row || !cid(row.public_index_cid) || typeof row.inventory_wire!=='string' ||
          Buffer.byteLength(row.inventory_wire,'utf8')>maxWireBytes) fail('InvalidDeliveryAttemptIndex');
      return Object.freeze({public_index_cid:row.public_index_cid,inventory_wire:row.inventory_wire});
    };
    const sameRecoveryOriginal = (left,right) => left!==undefined && right!==undefined &&
      left.public_index_cid===right.public_index_cid && left.inventory_wire===right.inventory_wire;
    flushPublicationFinishes = () => {
      if (retainedPublicationFinishes.size === 0) return [];
      const originals = [...retainedPublicationFinishes.values()];
      if (recoveryState().complete !== 1) fail('DeliveryAttemptIndexUnavailable');
      let removed = 0;
      for (const original of originals) {
        const row = pendingPublication.get(original.public_index_cid);
        if (row !== undefined) {
          if (!sameRecoveryOriginal(recoveryOriginal(row), original)) fail('PublicationMetadataInventoryConflict');
          removed += removePendingPublication.run(original.public_index_cid).changes;
        }
      }
      // Even an already-removed original needs a real write to confirm an
      // earlier lost COMMIT. Presence or absence is not an ACK.
      if (updatePublicationRecovery.run(-removed).changes !== 1) fail('DeliveryAttemptIndexUnavailable');
      return originals;
    };
    sealPublicationFinishes = () => {
      if (retainedPublicationFinishes.size === 0) return;
      // Preserve the existing ability to close an unrelated uncertain native
      // mutation without pretending to settle it. Its durable pending rows
      // remain available to the existing targeted restart recovery.
      if ((uncertain && !uncertainPublicationFinishSeal) || !transaction.connectionUsable) return;
      publicationFinishClosing = true;
      try {
        run(() => {});
        uncertainPublicationFinishSeal = false; uncertain = false;
      } catch (error) {
        if (error?.outcome === 'unknown') uncertainPublicationFinishSeal = true;
        throw error;
      }
    };
    retirePublicationFinishReferences = () => retainedPublicationFinishes.clear();
    const inventoryUsage = () => {
      const row=nativeInventoryUsage.get();
      if (!row || !Number.isSafeInteger(row.entries) || row.entries<0 || row.entries>maxEntries ||
          !Number.isSafeInteger(row.ack_revision) || row.ack_revision<1) fail('DeliveryAttemptIndexUnavailable');
      return row;
    };
    const fenceOriginal = value => {
      if (!value || typeof value.metadata_key !== 'string' || !/^[0-9a-f]{64}$/u.test(value.metadata_key) ||
          !cid(value.run_cid)) fail('InvalidDeliveryAttemptIndex');
      return Object.freeze({metadata_key:value.metadata_key,run_cid:value.run_cid});
    };
    const sameFence = (left,right) => left === undefined ? right === undefined :
      right !== undefined && left.metadata_key === right.metadata_key && left.run_cid === right.run_cid;
    const fenceCopy = value => {
      if (value === undefined) return undefined;
      const original = fenceOriginal(value);
      if (![0,1].includes(value.retired)) fail('InvalidDeliveryAttemptIndex');
      return Object.freeze({...original,retired:value.retired});
    };
    const fenceState = (ready = true) => {
      const row = metadataFenceCoverage.get();
      if (!row || ![0,1].includes(row.complete) || !Number.isSafeInteger(row.ack_revision) ||
          row.ack_revision < 1 || ready && row.complete !== 1) fail('DeliveryAttemptIndexUnavailable');
      return row;
    };
    const checkFence = original => {
      const existing = fenceCopy(metadataFence.get(original.metadata_key));
      if (existing !== undefined && !sameFence(existing,original)) fail('PublicationMetadataDeletionConflict');
      return existing;
    };
    const mutatePublicationRecovery = (kind,value,suppliedFence) => {
      const fence = suppliedFence === undefined ? undefined : fenceOriginal(suppliedFence);
      const original = value === undefined && kind === 'retire-native' && fence !== undefined
        ? undefined : recoveryOriginal(value);
      const retry=uncertain && uncertainPublicationRecovery?.kind===kind &&
        (original === undefined ? uncertainPublicationRecovery.original === undefined :
          sameRecoveryOriginal(uncertainPublicationRecovery.original,original)) &&
        sameFence(uncertainPublicationRecovery.fence,fence);
      if (retry) {
        if (closed||closing||mutating||!complete) fail('DeliveryAttemptIndexCleanupPending');
        transaction.assertUsable();
      } else requireComplete();
      const state=recoveryState();
      if (state.complete!==1) fail('DeliveryAttemptIndexUnavailable');
      const priorFence = fence === undefined ? undefined : (fenceState(),checkFence(fence));
      const existing=original === undefined ? undefined : pendingPublication.get(original.public_index_cid);
      if (existing!==undefined && !sameRecoveryOriginal(recoveryOriginal(existing),original)) {
        fail('PublicationMetadataInventoryConflict');
      }
      const native=original === undefined ? undefined : nativeInventory.get(original.public_index_cid);
      if (native!==undefined && !sameRecoveryOriginal(recoveryOriginal(native),original)) {
        fail('PublicationMetadataInventoryConflict');
      }
      const stage=kind==='stage'||kind==='stage-native',retire=kind==='retire-native';
      const usage=inventoryUsage();
      if (!retry && (stage ? existing!==undefined && (kind!=='stage-native'||native!==undefined)
          : existing===undefined && (!retire||native===undefined)) &&
          (fence === undefined || priorFence !== undefined)) return original;
      if (stage && existing===undefined && state.entries>=maxEntries ||
          kind==='stage-native' && native===undefined && usage.entries>=maxEntries) fail('DeliveryAttemptIndexLimit');
      try {
        run(()=>{
          let change=0;
          if (stage && existing===undefined) {
            insertPendingPublication.run(original.public_index_cid,original.inventory_wire);change=1;
          } else if (!stage && original !== undefined) change=-removePendingPublication.run(original.public_index_cid).changes;
          let nativeChange=0;
          if (kind==='stage-native' && native===undefined) {
            insertNativeInventory.run(original.public_index_cid,original.inventory_wire);nativeChange=1;
          } else if (retire && original !== undefined) nativeChange=-removeNativeInventory.run(original.public_index_cid).changes;
          if (fence !== undefined && priorFence === undefined) insertMetadataFence.run(fence.metadata_key,fence.run_cid,0);
          if ((kind==='stage-native'||retire) && updateNativeInventoryUsage.run(nativeChange).changes!==1) {
            fail('DeliveryAttemptIndexUnavailable');
          }
          // A same-original Unknown retry performs a real write even if its
          // previous COMMIT already installed/removed the pending row.
          if (updatePublicationRecovery.run(change).changes!==1) fail('DeliveryAttemptIndexUnavailable');
        });
        if (retry) {uncertain=false;uncertainPublicationRecovery=undefined;}
      } catch (error) {
        if (error?.outcome==='unknown') uncertainPublicationRecovery=Object.freeze({kind,original,fence});
        throw error;
      }
      return original;
    };
    const publicationMutation = (kind, entries, allowance) => {
      if (!Array.isArray(entries) || entries.length > maxEntries) fail('DeliveryAttemptIndexLimit');
      const retry = uncertain && uncertainPublication?.kind === kind &&
        entries.length === uncertainPublication.entries.length &&
        entries.every((entry,i) => samePublication(entry,uncertainPublication.entries[i]));
      if (retry) {
        if (closed || closing || mutating || !complete) fail('DeliveryAttemptIndexCleanupPending');
        transaction.assertUsable();
      } else requireComplete();
      const originals = Object.freeze(entries.map(entry => publicationCopy(entry)));
      const before = usage();
      const additions = [], removals = [];
      const keys = new Set();
      let bytes = 0;
      for (const entry of originals) {
        if (entry === undefined || keys.has(entry.semantic_cid)) fail('InvalidDeliveryAttemptIndex');
        keys.add(entry.semantic_cid);
        const current = publicationCopy(publication.get(entry.semantic_cid));
        if (current !== undefined && !samePublication(current,entry)) fail('PublicationSemanticIdentityConflict');
        if (kind === 'put' && current === undefined) { additions.push(entry); bytes += entry.byte_count; }
        if (kind === 'remove' && current !== undefined) { removals.push(entry); bytes -= entry.byte_count; }
      }
      const objects = additions.length - removals.length;
      if (!Number.isSafeInteger(bytes) || !Number.isSafeInteger(before.bytes + bytes) ||
          before.objects + objects > maxEntries) fail('DeliveryAttemptIndexLimit');
      if (kind === 'put' && (!allowance || !Number.isSafeInteger(allowance.bytes) || allowance.bytes < bytes ||
          !Number.isSafeInteger(allowance.objects) || allowance.objects < objects)) fail('PublicationStoreCapacity');
      if (objects !== 0 || retry) {
        try {
          run(() => {
            for (const entry of additions) insertPublication.run(entry.semantic_cid,entry.name,entry.wire,entry.byte_count);
            for (const entry of removals) removePublication.run(entry.semantic_cid);
            // A real same-database write confirms a lost COMMIT, even when
            // the original transaction already installed/removed every row.
            if (updatePublicationUsage.run(objects,bytes).changes !== 1) fail('InvalidDeliveryAttemptIndex');
          });
          if (retry) { uncertain = false; uncertainPublication = undefined; }
        } catch (error) {
          if (error?.outcome === 'unknown') uncertainPublication = Object.freeze({kind,entries:originals});
          throw error;
        }
      }
      return usage();
    };
    usage();recoveryState();inventoryUsage();physicalState();
    return Object.freeze({
      physicalObjectUsage() {requireOpen();return physicalState();},
      physicalObjectRecoveryRequired() {requireOpen();return physicalRecoveryRequired;},
      recoverPhysicalObjects(values) {
        requireComplete();if(!physicalRecoveryRequired||physicalLifetime!==undefined)fail('DeliveryAttemptIndexAlreadyComplete');
        if(!Array.isArray(values)||values.length>maxEntries)fail('DeliveryAttemptIndexLimit');
        const originals=values.map(physicalOriginal),bytes=originals.reduce((sum,row)=>sum+row.byte_count,0);
        if(!Number.isSafeInteger(bytes)||new Set(originals.map(row=>row.cid)).size!==originals.length)fail('InvalidDeliveryAttemptIndex');
        run(()=>{
          exec('DELETE FROM physical_objects; DELETE FROM physical_object_preparations');
          for(const row of originals)insertPhysicalObject.run(row.cid,row.byte_count,row.device,row.inode);
          if(prepare(`UPDATE physical_object_usage SET objects=?,bytes=?,ack_revision=ack_revision+1 WHERE id=1 AND complete=1`)
            .run(originals.length,bytes).changes!==1)fail('DeliveryAttemptIndexUnavailable');
          exec('PRAGMA user_version=0');
        });
        physicalRecoveryRequired=false;return physicalState();
      },
      beginPhysicalObjectLifetime() {
        requireComplete();if(physicalLifetime!==undefined)return;
        const base=storedPhysicalState();
        if(physicalRecoveryRequired||base.complete!==1||
            prepare('SELECT cid FROM physical_object_preparations LIMIT 1').get()!==undefined)fail('DeliveryAttemptIndexUnavailable');
        run(()=>exec('PRAGMA user_version=1'));
        physicalLifetime={base,objects:base.objects,bytes:base.bytes,changes:new Map(),preparations:new Map(),retiring:new Map(),sealing:false,sealed:false};
      },
      retainPhysicalRemoval(value) {
        requireComplete();const original=physicalOriginal(value);
        if(physicalLifetime===undefined||!samePhysical(selectedPhysical(original.cid),original))fail('PublicationObjectAccountingMismatch');
        physicalLifetime.retiring.set(preparationKey(original),original);
      },
      physicalObject(cidValue) {
        requireComplete();if(!cid(cidValue))fail('InvalidDeliveryAttemptIndex');
        return selectedPhysical(cidValue);
      },
      migratePhysicalObjects(values) {
        requireOpen();if(physicalState().complete!==0)fail('DeliveryAttemptIndexAlreadyComplete');
        if(!Array.isArray(values)||values.length>maxEntries)fail('DeliveryAttemptIndexLimit');
        const originals=values.map(physicalOriginal),bytes=originals.reduce((sum,row)=>sum+row.byte_count,0);
        if(!Number.isSafeInteger(bytes)||new Set(originals.map(row=>row.cid)).size!==originals.length) {
          fail('InvalidDeliveryAttemptIndex');
        }
        run(()=>{
          for(const row of originals)insertPhysicalObject.run(row.cid,row.byte_count,row.device,row.inode);
          prepare(`UPDATE physical_object_usage SET complete=1,objects=?,bytes=?,
            ack_revision=ack_revision+1 WHERE id=1 AND complete=0`).run(originals.length,bytes);
        });
        return physicalState();
      },
      recordPhysicalObjects(values) {return mutatePhysical('record',values);},
      removePhysicalObjects(values) {return mutatePhysical('remove',values);},
      stagePhysicalObjects(values) {return mutatePhysicalPreparation('stage',values);},
      finishPhysicalPreparations(values) {return mutatePhysicalPreparation('finish',values);},
      pendingPhysicalObjects() {
        requireComplete();
        if(physicalLifetime!==undefined)return Object.freeze([...physicalLifetime.preparations.values()]);
        const rows=prepare('SELECT * FROM physical_object_preparations LIMIT ?').all(maxEntries+1);
        if(rows.length>maxEntries)fail('DeliveryAttemptIndexLimit');
        return Object.freeze(rows.map(physicalOriginal));
      },
      nativePublicationInventory(publicIndexCid) {
        requireComplete();if(!cid(publicIndexCid))fail('InvalidDeliveryAttemptIndex');
        inventoryUsage();const row=nativeInventory.get(publicIndexCid);
        return row===undefined?undefined:recoveryOriginal(row);
      },
      nativePublicationInventories() {
        requireComplete();const usage=inventoryUsage(),rows=nativeInventories.all(maxEntries+1);
        if(rows.length!==usage.entries)fail('DeliveryAttemptIndexUnavailable');
        return Object.freeze(rows.map(recoveryOriginal));
      },
      needsPublicationRecoveryMigration() { requireComplete();return recoveryState().complete===0; },
      migratePublicationRecovery(values) {
        requireComplete();
        if (recoveryState().complete!==0 || pendingPublications.all(1).length!==0) fail('DeliveryAttemptIndexAlreadyComplete');
        if (!Array.isArray(values)||values.length>maxEntries) fail('DeliveryAttemptIndexLimit');
        const originals=values.map(recoveryOriginal),keys=new Set(originals.map(row=>row.public_index_cid));
        if (keys.size!==originals.length) fail('PublicationMetadataInventoryConflict');
        run(()=>{
          for(const row of originals) insertPendingPublication.run(row.public_index_cid,row.inventory_wire);
          const finish=prepare('UPDATE publication_recovery SET complete=1,entries=?,ack_revision=ack_revision+1 WHERE id=1 AND complete=0');
          if(finish.run(originals.length).changes!==1) fail('DeliveryAttemptIndexUnavailable');
        });
      },
      pendingPublications() {
        requireComplete();const state=recoveryState();
        if(state.complete!==1)fail('DeliveryAttemptIndexUnavailable');
        const rows=pendingPublications.all(maxEntries+1);
        if(rows.length!==state.entries)fail('DeliveryAttemptIndexUnavailable');
        return Object.freeze(rows.map(recoveryOriginal));
      },
      pendingPublication(publicIndexCid) {
        requireComplete();if(!cid(publicIndexCid))fail('InvalidDeliveryAttemptIndex');
        if(recoveryState().complete!==1)fail('DeliveryAttemptIndexUnavailable');
        const row=pendingPublication.get(publicIndexCid);
        return row===undefined?undefined:recoveryOriginal(row);
      },
      stagePublicationInventory(value) { return mutatePublicationRecovery('stage',value); },
      stageNativePublicationInventory(value) { return mutatePublicationRecovery('stage-native',value); },
      finishPublicationInventory(value) { return mutatePublicationRecovery('finish',value); },
      retainPublicationInventoryFinish(value) {
        requireComplete();
        const original = recoveryOriginal(value);
        if (recoveryState().complete !== 1) fail('DeliveryAttemptIndexUnavailable');
        const row = pendingPublication.get(original.public_index_cid);
        if (row === undefined) return;
        if (!sameRecoveryOriginal(recoveryOriginal(row), original)) fail('PublicationMetadataInventoryConflict');
        if (!retainedPublicationFinishes.has(original.public_index_cid) && retainedPublicationFinishes.size >= maxEntries) {
          fail('DeliveryAttemptIndexLimit');
        }
        // Store invokes this only after the real Index ACK and schema
        // adoption. It retains derived recovery work, not an ACK or authority.
        retainedPublicationFinishes.set(original.public_index_cid, original);
      },
      retireNativePublicationInventory(value,fence) { return mutatePublicationRecovery('retire-native',value,fence); },
      needsMetadataDeletionFenceMigration() { requireComplete();return fenceState(false).complete===0; },
      migrateMetadataDeletionFences(values,finished=false) {
        requireComplete();
        if (fenceState(false).complete !== 0) fail('DeliveryAttemptIndexAlreadyComplete');
        if (!Array.isArray(values) || values.length > Math.max(1,maxEntries) || typeof finished !== 'boolean') {
          fail('DeliveryAttemptIndexLimit');
        }
        const rows=values.map(fenceCopy),keys=new Set(rows.map(row=>row?.metadata_key));
        if(rows.some(row=>row===undefined)||keys.size!==rows.length) fail('InvalidDeliveryAttemptIndex');
        run(()=>{
          for(const row of rows) {
            const prior=checkFence(row);
            if(prior===undefined)insertMetadataFence.run(row.metadata_key,row.run_cid,row.retired);
            else if(row.retired===1)retireMetadataFence.run(row.metadata_key,row.run_cid);
          }
          if(finished) {
            if(prepare('UPDATE metadata_deletion_fence_coverage SET complete=1,ack_revision=ack_revision+1 WHERE id=1 AND complete=0')
              .run().changes!==1)fail('DeliveryAttemptIndexUnavailable');
          } else if(acknowledgeMetadataFences.run().changes!==1)fail('DeliveryAttemptIndexUnavailable');
        });
      },
      metadataDeletionFence(key) {
        requireComplete();fenceState();
        if(typeof key!=='string'||!/^[0-9a-f]{64}$/u.test(key))fail('InvalidDeliveryAttemptIndex');
        return fenceCopy(metadataFence.get(key));
      },
      hasRunMetadataDeletionFence(runCid) {
        requireComplete();fenceState();
        if(!cid(runCid))fail('InvalidDeliveryAttemptIndex');
        const row=fenceCopy(runMetadataFence.get(runCid));
        if(row!==undefined&&row.run_cid!==runCid)fail('InvalidDeliveryAttemptIndex');
        return row!==undefined;
      },
      finishMetadataDeletionFence(value) {
        const original=fenceOriginal(value);
        const retry=uncertain&&sameFence(uncertainMetadataFence,original);
        if(retry) {
          if(closed||closing||mutating||!complete)fail('DeliveryAttemptIndexCleanupPending');
          transaction.assertUsable();
        } else requireComplete();
        fenceState();const before=checkFence(original);
        if(before===undefined)fail('PublicationMetadataDeletionConflict');
        if(!retry&&before.retired===1)return;
        try {
          run(()=>{
            if(retireMetadataFence.run(original.metadata_key,original.run_cid).changes!==1 ||
                acknowledgeMetadataFences.run().changes!==1)fail('DeliveryAttemptIndexUnavailable');
          });
          if(retry){uncertain=false;uncertainMetadataFence=undefined;}
        } catch(error) {
          if(error?.outcome==='unknown')uncertainMetadataFence=original;
          throw error;
        }
      },
      publicationUsage() { requireComplete(); return usage(); },
      publicationContract(semanticCid) { requireComplete(); return publicationCopy(publication.get(semanticCid)); },
      putPublicationContracts(entries, allowance) { return publicationMutation('put',entries,allowance); },
      removePublicationContract(entry) { return publicationMutation('remove',[entry]); },
      needsMigration() { requireOpen(); return !complete; },
      migrate(rows) {
        requireOpen();
        if (complete) fail('DeliveryAttemptIndexAlreadyComplete');
        if (rows.length > maxEntries) fail('DeliveryAttemptIndexLimit');
        run(() => {
          exec('DELETE FROM initial_records; DELETE FROM attempts; DELETE FROM grant_uses; UPDATE coverage SET entries=0 WHERE id=1');
          const keys = new Set();
          for (const row of rows) {
            if (keys.has(row.logical_key)) fail('AmbiguousDeliveryAttemptLookup');
            keys.add(row.logical_key);
            add(row,1);
          }
          exec('UPDATE coverage SET complete=1 WHERE id=1');
        });
        complete = true;
      },
      lookup(key) { requireComplete(); return copy(lookup.get(key)); },
      attempt(attemptCid) { requireComplete(); return copy(byAttempt.get(attemptCid)); },
      run(runCid) { requireComplete(); return Object.freeze(byRun.all(runCid,maxEntries+1).map(copy)); },
      completion(attemptCid) {requireComplete();return completionCopy(completion.get(attemptCid));},
      contract(semanticCid) {
        requireComplete();
        const metadata = publicationCopy(publication.get(semanticCid));
        if (metadata !== undefined) return Object.freeze({name:metadata.name,wire:metadata.wire,publication:true});
        const row=nativeContract.get(semanticCid,semanticCid,semanticCid,semanticCid,semanticCid);
        if(row===undefined) return undefined;
        const {name,wire}=row;
        if(typeof wire!=='string' || Buffer.byteLength(wire,'utf8')>maxWireBytes) fail('InvalidDeliveryAttemptIndex');
        return Object.freeze({name,wire});
      },
      pending() { requireComplete(); return Object.freeze(pending.all(maxEntries + 1).map(copy)); },
      complete(entry) {
        const retry=uncertain && sameCompletion(uncertainCompletion,entry);
        if(retry) {
          if(closed||closing||mutating||!complete) fail('DeliveryAttemptIndexCleanupPending');
          transaction.assertUsable();
        } else requireComplete();
        completionCopy({...entry,ack_revision:1});
        if(!cid(entry.prior_cid)) fail('InvalidDeliveryAttemptIndex');
        const original=Object.freeze({...entry});
        try {
          run(()=>{
            const attempt=byAttempt.get(entry.attempt_cid);
            if(attempt?.ready!==1 || attempt.initial_cid!==entry.prior_cid) fail('DeliveryRecordConflict');
            const retained=completionCopy(completion.get(entry.attempt_cid));
            if(retained===undefined) insertCompletion.run(entry.attempt_cid,entry.record_cid,entry.record_wire,entry.receipt_cid,entry.receipt_wire);
            else {
              if(!sameCompletion({...retained,prior_cid:entry.prior_cid},entry)) fail('DeliveryRecordConflict');
              // A real write in the SAME database confirms a lost earlier
              // COMMIT reply. A visible row or read-only COMMIT is not an ACK.
              if(confirmCompletion.run(entry.attempt_cid,entry.record_cid).changes!==1) fail('DeliveryRecordConflict');
            }
          });
          if(retry) {uncertain=false;uncertainCompletion=undefined;}
          confirmedRecord=entry.record_cid;
        } catch(error) {
          if(error?.outcome==='unknown') uncertainCompletion=original;
          throw error;
        }
      },
      confirmRecord(attemptCid,recordCid,wire) {
        const retryInitial=uncertain && uncertainInitial?.attemptCid===attemptCid &&
          uncertainInitial.recordCid===recordCid && uncertainInitial.wire===wire;
        const retry=retryInitial || uncertain && uncertainCompletion?.attempt_cid===attemptCid &&
          uncertainCompletion.record_cid===recordCid && uncertainCompletion.record_wire===wire;
        if(retry) {
          if(closed||closing||mutating||!complete) fail('DeliveryAttemptIndexCleanupPending');
          transaction.assertUsable();
        } else requireComplete();
        const initial=initialRecord.get(attemptCid);
        const isInitial=initial?.initial_cid===recordCid;
        const retained=isInitial ? undefined : completionCopy(completion.get(attemptCid));
        if(!isInitial && retained?.record_cid!==recordCid) return false;
        if(isInitial ? initial.initial_wire!==wire || !Number.isSafeInteger(initial.ack_revision) || initial.ack_revision<1
          : retained.record_wire!==wire) fail('DeliveryRecordConflict');
        if(confirmedRecord===recordCid && !retry) return true;
        const priorCid=byAttempt.get(attemptCid)?.initial_cid;
        try {
          run(()=>{if((isInitial?confirmInitial:confirmCompletion).run(attemptCid,recordCid).changes!==1) fail('DeliveryRecordConflict');});
          if(retry) {uncertain=false;uncertainCompletion=undefined;uncertainInitial=undefined;}
          confirmedRecord=recordCid;
          return true;
        } catch(error) {
          if(error?.outcome==='unknown') {
            if(isInitial) uncertainInitial=Object.freeze({attemptCid,recordCid,wire});
            else uncertainCompletion=Object.freeze({...retained,prior_cid:priorCid});
          }
          throw error;
        }
      },
      claim(row,maxUses,initialWire,initialCid) {
        requireComplete();
        validate({...row,initial_wire:initialWire,initial_cid:initialCid});
        const retained = lookup.get(row.logical_key);
        if (retained !== undefined) return Object.freeze({row: copy(retained), created: false});
        const result=run(() => {
          if ((uses.get(row.grant_cid)?.uses ?? 0) >= maxUses) fail('DeliveryGrantUseLimit');
          if (state.get().entries >= maxEntries) fail('DeliveryAttemptIndexLimit');
          // For a joint START this is a complete durable logical claim, not
          // a file ACK. A supplied initial CID selects the native metadata
          // representation; legacy null retains its separate file protocol.
          const isReady = initialWire === undefined ? 0 : 1;
          add(row,isReady,initialWire,initialCid);
          return Object.freeze({row: copy({...row,ready:isReady,initial_wire:initialWire,initial_cid:initialCid}), created:true});
        });
        if(initialCid!==undefined) confirmedRecord=initialCid;
        return result;
      },
      finish(key,attemptCid) {
        requireComplete();
        const row = lookup.get(key);
        if (row === undefined || row.attempt_cid !== attemptCid) fail('DeliveryAttemptConflict');
        if (row.ready === 1) return;
        run(() => {
          if (ready.run(key,attemptCid).changes !== 1) fail('DeliveryAttemptConflict');
        });
      },
      forgetRun(runCid) {
        if (uncertain && uncertainRemoval === runCid) {
          if (closed || closing || mutating || !complete) fail('DeliveryAttemptIndexCleanupPending');
          transaction.assertUsable();
        } else requireComplete();
        try {
          // Retry only this original idempotent metadata removal. A previous
          // COMMIT may already have removed the rows: decrement only the uses
          // still present, never replay a claim or refund an unknown stream.
          run(() => {
            for (const row of runUses.all(runCid)) removeUses.run(row.uses,row.grant_cid);
            updateCount.run(-remove.run(runCid).changes);
          });
          if (uncertainRemoval === runCid) {
            uncertainRemoval = undefined;
            uncertain = false;
          }
        } catch (error) {
          if (error?.outcome === 'unknown') uncertainRemoval = runCid;
          throw error;
        }
      },
      close, retainFailure,
    });
  } catch (primary) { throw retainFailure(primary); }
}
