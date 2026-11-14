// Physical durable storage for an owner-issued Client request and Run ref.
// MoonBit supplies and re-admits the identity and decides intent conflicts.
import {DatabaseSync, StatementSync} from 'node:sqlite';
import * as facilityFs from 'node:fs';
import * as facilityFsPromises from 'node:fs/promises';
import * as facilityCrypto from 'node:crypto';
import facilityFields from './host-journal-facility-fields.cjs';
import {prepareInstalledRunStateObservation, issueInstalledRunControlObservation}
  from '../host-common/run-state-observation.mjs';
import {createHash, createHmac, randomBytes, timingSafeEqual} from 'node:crypto';
import {closeSync, constants, existsSync, fstatSync, fsyncSync, lstatSync,
  mkdirSync, openSync, readSync,
  realpathSync, writeFileSync} from 'node:fs';
import {basename, dirname, isAbsolute, join, resolve} from 'node:path';
import {types as utilTypes} from 'node:util';
import {createSqliteTransaction, throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {inspectSqliteSnapshot, inspectJournalDirectory} from '../host-common/sqlite-format-inspection.mjs';
import {assertHostJournalDirectoryInspector, inspectHostJournalDirectory}
  from './host-journal-directory.mjs';
import {snapshotSqliteSchemaReadLimits, snapshotSqliteSchemaSqlSupport}
  from '../host-common/sqlite-schema-resource-bounds.mjs';
import {assertOriginalPreparedLocalPublicationStoreOwnership,
  captureOriginalLocalExecutionOwner, originalLocalExecutionOwnerStopped}
  from '../store-local/publication-store.mjs';
import {openClientObservationStorage} from './client-observation-journal.mjs';
import {isHostObservationProjection} from '../host-common/observation.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {BOUND_SOURCE_INVENTORY, validBoundSourceOccurrence} from './ordinary-source-binding.mjs';
import {valuesExecutionContextCid} from './local-values-capacity.mjs';
import {sourceOperationTable, inspectClientSourceOperationStorage,
  clientSourceOperationStorage, snapshotClientSourceOperationLimits} from './client-source-operation.mjs';
import {sameSubmissionRef, validSubmissionRef, validSubmissionName, validSubmissionOutcome, validStoredSubmissionOutcome} from '../../packages/client-wire/index.mjs';

// Originals of the existing checked keyed Source on this Request Journal.
// The bound canonical schedule limits each batch; no Scope/Run or physical
// authority is issued by this additive durable index.
const keyedLookupOriginalTable = `CREATE TABLE client_keyed_lookup_originals (
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  run_definition_cid TEXT NOT NULL REFERENCES client_requests(run_definition_cid),
  batch_plan_cid TEXT NOT NULL,
  call_slot_cid TEXT NOT NULL,
  batch_index INTEGER NOT NULL CHECK (batch_index >= 0),
  batch_count INTEGER NOT NULL CHECK (batch_count > 0 AND batch_index < batch_count),
  activation_wire TEXT NOT NULL,
  page_wire TEXT,
  PRIMARY KEY (namespace_id, authority_scope_cid, run_definition_cid, call_slot_cid),
  UNIQUE (namespace_id, authority_scope_cid, run_definition_cid, batch_plan_cid, batch_index)
) STRICT`;

const cid = value => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' &&
  value.length > 0 && value.length <= 256 &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const pathText = value => typeof value === 'string' && value.length > 0;
const instant = value => typeof value === 'string' &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/u.test(value) &&
  Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString() === value;
const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const applyOriginal = Reflect.apply;
const operationDescriptors = Object.getOwnPropertyDescriptors;
const operationDefineProperties = Object.defineProperties;
const operationKeys = Reflect.ownKeys, operationFreeze = Object.freeze;
const originalJournalCustodies = new WeakMap();
const originalJournalCustodyGet = WeakMap.prototype.get;
const originalJournalCustodySet = WeakMap.prototype.set;
const facilityDescriptor = Object.getOwnPropertyDescriptor;
const facilityRealpath = realpathSync;
const facilityNativeRealpath = facilityDescriptor(facilityRealpath, 'native')?.value;
const nativePathOptions = Object.freeze({__proto__: null, encoding: 'utf8'});
const facilityHasOwn = Object.hasOwn, facilityIsProxy = utilTypes.isProxy;
const facilityDatabase = DatabaseSync, facilityStatement = StatementSync;
const facilityIteratorProperty = facilityDescriptor(globalThis, 'Iterator');
// No getter/Proxy is evaluated while capturing this actual namespace. Missing
// or unsupported originals remain absent and the selected fence refuses them.
const facilityIteratorConstructor = facilityIteratorProperty !== undefined &&
  facilityHasOwn(facilityIteratorProperty, 'value') &&
  typeof facilityIteratorProperty.value === 'function' &&
  !facilityIsProxy(facilityIteratorProperty.value) ? facilityIteratorProperty.value : undefined;
const facilityOperations = Object.freeze([
  [facilityDatabase.prototype, 'open'], [facilityDatabase.prototype, 'close'],
  [facilityDatabase.prototype, 'prepare'], [facilityDatabase.prototype, 'exec'],
  [facilityStatement.prototype, 'get'], [facilityStatement.prototype, 'run'],
  [facilityStatement.prototype, 'iterate'],
].map(([receiver, name]) => Object.freeze({receiver, name,
  property: facilityDescriptor(receiver, name)})));
const facilityPlatformOperations = Object.freeze([
  ['fs',facilityFs],['crypto',facilityCrypto],['constants',facilityFs.constants],
  ['promises',facilityFsPromises],
  ['iteratorGlobal',globalThis],['iteratorConstructor',facilityIteratorConstructor],
  ['directory',facilityFs.Dir.prototype],['hash',facilityCrypto.Hash.prototype],
  ['hmac',facilityCrypto.Hmac.prototype],['realpath',facilityRealpath],
].flatMap(([group,receiver]) => facilityFields[group].map(name => Object.freeze({
  group,receiver,name,property:receiver === undefined ? undefined : facilityDescriptor(receiver,name),
}))));

function originalJournalFacilityField(value, name) {
  if (value === null || typeof value !== 'object' || facilityIsProxy(value)) {
    fail('ClientRequestJournalFacilityUnavailable');
  }
  const property = facilityDescriptor(value,name);
  if (property === undefined || !facilityHasOwn(property,'value')) {
    fail('ClientRequestJournalFacilityUnavailable');
  }
  return property.value;
}

// Fixed namespace forwarder for the selected startup's actual node:sqlite
// originals. This observes correspondence/currentness, not capacity, a new
// installation or authority. No caller callback or equal label is a native
// constructor, and restoration after a detected change cannot revive it.
let facilityChanged = false;
export function assertOriginalClientRequestJournalFacilityCurrent(database, statement, nativeBindings) {
  if (database !== facilityDatabase || statement !== facilityStatement) {
    fail('ClientRequestJournalFacilityUnavailable');
  }
  for (const {receiver, name, property} of facilityOperations) {
    const current = facilityDescriptor(receiver, name);
    if (property === undefined || current === undefined ||
        typeof property.value !== 'function' || current.value !== property.value ||
        current.get !== property.get || current.set !== property.set ||
        current.writable !== property.writable || current.configurable !== property.configurable ||
        current.enumerable !== property.enumerable) facilityChanged = true;
  }
  if (nativeBindings !== undefined) {
    // This is correspondence DATA from the actual early prefix, not a new
    // facility issuer. A foreign table cannot poison another original's
    // currentness; a detected change in the real operations is irreversible.
    for (const {group,name,property} of facilityPlatformOperations) {
      const selected = originalJournalFacilityField(nativeBindings,group);
      if (property === undefined || !facilityHasOwn(property, 'value') ||
          originalJournalFacilityField(selected,name) !== property.value) {
        fail('ClientRequestJournalFacilityUnavailable');
      }
    }
    for (const {receiver,name,property} of facilityPlatformOperations) {
      const current = receiver === undefined ? undefined : facilityDescriptor(receiver,name);
      if (current === undefined || current.value !== property.value ||
          current.get !== property.get || current.set !== property.set ||
          current.writable !== property.writable || current.configurable !== property.configurable ||
          current.enumerable !== property.enumerable) facilityChanged = true;
    }
  }
  if (facilityChanged) fail('ClientRequestJournalFacilityUnavailable');
}

// Private physical-facility observation, not request/Run authority or a
// capacity issuer. Only this module's actual constructor can install a member.
// Logical close, native connection close and optional observation ownership
// are distinct; a copied object cannot attest any of them.
export function observeOriginalClientRequestJournalCustody(journal) {
  const read = applyOriginal(originalJournalCustodyGet, originalJournalCustodies, [journal]);
  if (read === undefined) fail('ForeignClientRequestJournalCustody');
  return read();
}

function snapshotPrimarySqlLimits(value) {
  if (value === undefined) return undefined;
  const names = ['maxPreparedStatements', 'maxSqlBytes', 'maxTotalSqlBytes'];
  if (value === null || typeof value !== 'object' || utilTypes.isProxy(value)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== names.length || keys.some(key => !names.includes(key))) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const limits = {};
  for (const name of names) {
    const field = Object.getOwnPropertyDescriptor(value, name);
    if (!field || !Object.hasOwn(field, 'value') ||
        !Number.isSafeInteger(field.value) || field.value < 1) {
      fail('InvalidClientRequestJournalConfiguration');
    }
    limits[name] = field.value;
  }
  return Object.freeze(limits);
}

function snapshotPrimaryExecutionLimits(value) {
  if (value === undefined) return undefined;
  const names = ['maxParameters', 'maxParameterBytes', 'maxResultRows'];
  if (value === null || typeof value !== 'object' || utilTypes.isProxy(value)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== names.length || keys.some(key => !names.includes(key))) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const limits = {};
  for (const name of names) {
    const field = Object.getOwnPropertyDescriptor(value, name);
    if (!field || !Object.hasOwn(field, 'value') ||
        !Number.isSafeInteger(field.value) || field.value < 1) {
      fail('InvalidClientRequestJournalConfiguration');
    }
    limits[name] = field.value;
  }
  return Object.freeze(limits);
}

function guardJournalCurrentness(journal, assertCurrent) {
  if (assertCurrent === undefined) return journal;
  // Every new operation checks its same installed original. Completed calls
  // retain no lifetime issuance debt; their own finite input/SQL work remains
  // bounded at each actual consumer. Cleanup is always reachable below.
  const enter = () => {assertCurrent();};
  const descriptors = operationDescriptors(journal);
  for (const name of operationKeys(descriptors)) {
    const field = descriptors[name], original = field.value;
    // These are the fixed authored Owner's own methods, not caller DATA.
    // Cleanup remains reachable without operation/SQL credit or currentness.
    if (typeof original !== 'function' || name === 'close' || name === 'closeObservationStorage') continue;
    field.value = name === 'admitOrLookupDefinition'
      ? async function () { enter(); return applyOriginal(original, journal, arguments); }
      : function () { enter(); return applyOriginal(original, journal, arguments); };
  }
  return operationFreeze(operationDefineProperties({}, descriptors));
}

// One live WAL support bound for this Journal's two original writable
// connections. Work stays charged until their actual native checkpoint
// acknowledges truncation. This is not physical backing or Run authority.
function boundedJournalWalFrames(maxFrames, sourceBytes, maxDatabaseBytes) {
  if (maxFrames === undefined) return undefined;
  const integer = BigInt, floor = Math.floor, ceil = Math.ceil;
  const maximum = integer(maxFrames);
  // The original DB and WAL are jointly bounded before cold native inspection.
  // Reserve the worst original WAL at SQLite's minimum supported page size;
  // absence or a logical transaction exit alone cannot release these frames.
  let reserved = integer(sourceBytes) / 536n;
  if (reserved > maximum) fail('ClientRequestJournalWalUnavailable');
  const character = String.prototype.charCodeAt;
  const connections = [];
  let active = false;
  let originalPage, transactionFrames;
  const amount = units => transactionFrames === undefined ? 0n :
    integer(units) * transactionFrames;
  const reclaim = () => {
    // Never checkpoint an original active transaction or infer release from
    // a failed COMMIT/ROLLBACK. A busy/failed checkpoint keeps every charge.
    if (connections.length === 0 || connections.some(original => original.inTransaction() !== false)) {
      return false;
    }
    const result = connections[0].checkpoint();
    if (result?.busy !== 0 || result.log !== 0 || result.checkpointed !== 0 ||
        connections.some(original => original.inTransaction() !== false)) return false;
    reserved = 0n;
    return true;
  };
  const check = (units, transactionStart = false) => {
    const frames = amount(units);
    if (frames > maximum) fail('ClientRequestJournalWalUnavailable');
    // A transaction cannot reclaim prior work in its body. Try once at its
    // original BEGIN boundary, without refunding busy or concurrent work or
    // refusing an otherwise supported transaction just because reuse is busy.
    if ((transactionStart && reserved > 0n) || frames > maximum - reserved) {
      if (!reclaim() && frames > maximum - reserved) fail('ClientRequestJournalWalUnavailable');
    }
    return frames;
  };
  return Object.freeze({
    register(original) {
      if (connections.length === 2) fail('ClientRequestJournalWalUnavailable');
      connections.push(original);
      return () => {
        const index = connections.indexOf(original);
        if (index !== -1) connections.splice(index, 1);
      };
    },
    enter() {
      if (active) fail('ClientRequestJournalSqlCleanupPending');
      active = true;
    },
    leave() { active = false; },
    configure(page) {
      if (originalPage !== undefined && originalPage !== page) {
        fail('ClientRequestJournalWalUnavailable');
      }
      originalPage = page;
      // Same supported page-number set, possible repeated commit page, and
      // FULL-sync padding under SQLite's original 65536-byte sector clamp.
      // Counting two complete page sets is conservative; it does not assert
      // every dirty-page visit appends another frame or create two capacities.
      transactionFrames = 2n * integer(floor(maxDatabaseBytes / page)) +
        integer(ceil(65536 / (page + 24)));
    },
    beforePrepare() { check(2); },
    beforeStatement() {
      // Only the fixed page-size probe precedes configuration. Later extent
      // and temporary-storage operations keep their conservative charges.
      // Keep one conservative terminal COMMIT allowance available before
      // admitting another write. Checking it neither spends nor refunds it.
      check(2);
      reserved += amount(1);
    },
    beforeExec(sql) {
      if (transactionFrames === undefined) fail('ClientRequestJournalWalUnavailable');
      // At most one implicit transaction per top-level SQL statement. Count
      // every semicolon, including those in comments/literals/trigger bodies,
      // plus the final statement: a byte-level overestimate, not a SQL parser.
      let statements = 1;
      for (let index = 0; index < sql.length; index++) {
        if (applyOriginal(character, sql, [index]) === 59) statements++;
      }
      check(statements + (sql === 'COMMIT' ? 0 : 1), sql === 'BEGIN IMMEDIATE');
      reserved += amount(statements);
    },
  });
}

// Each operation has finite SQL/operand/result bounds. Only returned native
// statement originals and their SQL are retained against the live connection
// envelope; transient exec text and failed calls create no lifetime quota.
// Native heap/cache/WAL remain the separately selected opaque Host service,
// not a numerical claim made by these logical control counts.
function boundedPrimarySql(connection, limits, executionLimits, assertCurrent, walFrames) {
  const prepare = connection.prepare, exec = connection.exec;
  const buffer = Buffer, byteLength = buffer.byteLength;
  const isTransaction = Object.getOwnPropertyDescriptor(connection, 'isTransaction')?.get;
  if (typeof prepare !== 'function' || typeof exec !== 'function' || typeof byteLength !== 'function' ||
      typeof isTransaction !== 'function') fail('ClientRequestJournalSqlUnavailable');
  let prepared = 0, retainedSqlBytes = 0;
  const statements = [], cursors = [];
  const statementsBySql = executionLimits === undefined ? undefined : new Map();
  let operationActive = false, retired = false;
  const beginOperation = () => {
    if (retired) fail('ClientRequestJournalSqlUnavailable');
    if (executionLimits === undefined) return;
    // The selected one-connection recipe must not start another preparation
    // or execution from a current/native callback while this call is live.
    // Latch before those callbacks, not after native acquisition. This is a
    // synchronous operation fence, not native close or returned byte credit.
    if (operationActive) fail('ClientRequestJournalSqlCleanupPending');
    walFrames?.enter();
    operationActive = true;
  };
  const endOperation = () => { if (operationActive) walFrames?.leave(); operationActive = false; };
  const consume = (sql, isPrepare) => {
    assertCurrent?.();
    if (cursors.length !== 0) fail('ClientRequestJournalSqlCleanupPending');
    if (typeof sql !== 'string' || sql.length > limits.maxSqlBytes ||
        isPrepare && prepared >= limits.maxPreparedStatements) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    const size = applyOriginal(byteLength, buffer, [sql, 'utf8']);
    if (!Number.isSafeInteger(size) || size < sql.length ||
        size > limits.maxSqlBytes ||
        isPrepare && size > limits.maxTotalSqlBytes - retainedSqlBytes) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    return size;
  };
  const operands = values => {
    assertCurrent?.();
    if (cursors.length !== 0) fail('ClientRequestJournalSqlCleanupPending');
    if (values.length > executionLimits.maxParameters) fail('ClientRequestJournalSqlUnavailable');
    let total = 0;
    for (const value of values) {
      let size;
      if (value === null) size = 0;
      else if (typeof value === 'number' || typeof value === 'bigint') size = 8;
      else if (typeof value === 'string') {
        if (value.length > executionLimits.maxParameterBytes - total) {
          fail('ClientRequestJournalSqlUnavailable');
        }
        size = applyOriginal(byteLength, buffer, [value, 'utf8']);
        if (!Number.isSafeInteger(size) || size < value.length) {
          fail('ClientRequestJournalSqlUnavailable');
        }
      } else {
        // These fixed Journal statements bind positional scalar originals.
        // Named-object/Blob intake needs its own supported original boundary;
        // it is not inspected, cloned or silently coerced here.
        fail('ClientRequestJournalSqlUnavailable');
      }
      if (size > executionLimits.maxParameterBytes - total) {
        fail('ClientRequestJournalSqlUnavailable');
      }
      total += size;
    }
  };
  const wrap = (statement, statementWal) => {
    if (executionLimits === undefined) return statement;
    // Keep native statements in this original connection's custody until its
    // real close. Losing a local wrapper or GC supplies no earlier ACK.
    statements.push(statement);
    const get = statement.get, run = statement.run, iterate = statement.iterate;
    if ([get, run, iterate].some(method => typeof method !== 'function')) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    return Object.freeze({
      get(...values) {
        beginOperation();
        try {
          operands(values); statementWal?.beforeStatement();
          return applyOriginal(get, statement, values);
        } finally { endOperation(); }
      },
      run(...values) {
        beginOperation();
        try {
          operands(values); statementWal?.beforeStatement();
          return applyOriginal(run, statement, values);
        } finally { endOperation(); }
      },
      all(...values) {
        beginOperation();
        try {
          operands(values);
          statementWal?.beforeStatement();
          const iterator = applyOriginal(iterate, statement, values);
          const cursor = {iterator, next: undefined, end: undefined};
          cursors.push(cursor);
          let failed = false, primary;
          const rows = [];
          try {
            cursor.next = iterator.next;
            cursor.end = iterator.return;
            if (typeof cursor.next !== 'function' || typeof cursor.end !== 'function') {
              fail('ClientRequestJournalSqlUnavailable');
            }
            for (;;) {
              const row = applyOriginal(cursor.next, iterator, []);
              if (row.done === true) break;
              // One original lookahead row proves overflow. Do not materialize
              // native All()'s complete vector before checking the row ceiling.
              if (rows.length === executionLimits.maxResultRows) {
                fail('ClientRequestJournalSqlUnavailable');
              }
              rows.push(row.value);
            }
          } catch (cause) { failed = true; primary = cause; }
          try {
            if (typeof cursor.end !== 'function' ||
                applyOriginal(cursor.end, iterator, [])?.done !== true) {
              fail('ClientRequestJournalSqlCleanupPending');
            }
            cursors.pop();
          } catch (cause) {
            // Preserve the original iterator under the connection Owner. No new
            // statement can run while it is unresolved; the original database
            // close must finalize it before these retained aliases can retire.
            fail('ClientRequestJournalSqlCleanupPending', failed ?
              Object.freeze({primary, closeFailure: cause}) : cause);
          }
          if (failed) throw primary;
          return rows;
        } finally { endOperation(); }
      },
    });
  };
  let checkpoint;
  const prepareWalCheckpoint = () => {
    if (walFrames === undefined || checkpoint !== undefined) return;
    const sql = 'PRAGMA wal_checkpoint(TRUNCATE)';
    const bytes = consume(sql, true);
    const statement = applyOriginal(prepare, connection, [sql]);
    prepared++; retainedSqlBytes += bytes;
    statements.push(statement);
    const get = statement.get, run = statement.run, iterate = statement.iterate;
    if ([get, run, iterate].some(method => typeof method !== 'function')) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    checkpoint = {statement, get};
  };
  const retireWal = walFrames?.register(Object.freeze({
    inTransaction: () => applyOriginal(isTransaction, connection, []),
    checkpoint() {
      // This private native control uses the same finite SQL/operand and
      // retained-statement envelope. It cannot reenter the public SQL port.
      if (checkpoint === undefined) fail('ClientRequestJournalWalUnavailable');
      operands([]);
      const result = applyOriginal(checkpoint.get, checkpoint.statement, []);
      assertCurrent?.();
      return result;
    },
  }));
  return Object.freeze({database: Object.freeze({
    prepare(sql) {
      beginOperation();
      try {
        const retained = statementsBySql?.get(sql);
        if (retained !== undefined) {
          assertCurrent?.();
          if (cursors.length !== 0) fail('ClientRequestJournalSqlCleanupPending');
          // Exact immutable SQL selects this same connection's original
          // bounded wrapper. No compilation/allocation or allowance refill
          // occurs; every execution still checks its own operands and limits.
          return retained;
        }
        const sourceBytes = consume(sql, true);
        // Only authored metadata SQL reaches this private connection. It
        // installs no application SQL functions/extensions or writable virtual
        // tables. A leading SELECT reads metadata, not WAL-write history;
        // arbitrary SQL/PRAGMA and every write keep the conservative debit.
        const statementWal = /^\s*SELECT\b/iu.test(sql) ? undefined : walFrames;
        statementWal?.beforePrepare();
        const native = applyOriginal(prepare, connection, [sql]);
        // Commit the logical live entry only when this same native call returns
        // an original. wrap retains it even if its subsequent validation fails;
        // that failure still requires actual connection cleanup.
        prepared++; retainedSqlBytes += sourceBytes;
        const original = wrap(native, statementWal);
        statementsBySql?.set(sql, original);
        return original;
      } finally { endOperation(); }
    },
    exec(sql) {
      beginOperation();
      try {
        if (executionLimits !== undefined && sql === 'ROLLBACK' &&
            applyOriginal(isTransaction, connection, []) === true) {
          // This exact same-connection cleanup must remain reachable after
          // work/current refusal. It admits no new SQL work or statement,
          // refills no counter and still owns the native rollback outcome.
          if (cursors.length !== 0) fail('ClientRequestJournalSqlCleanupPending');
          return applyOriginal(exec, connection, [sql]);
        }
        consume(sql, false); walFrames?.beforeExec(sql);
        return applyOriginal(exec, connection, [sql]);
      } finally { endOperation(); }
    },
    get isTransaction() { return applyOriginal(isTransaction, connection, []); },
  }), prepareWalCheckpoint() {
    beginOperation();
    try { prepareWalCheckpoint(); } finally { endOperation(); }
  }, retireClosedNativeAliases() {
    retired = true;
    retireWal?.(); checkpoint = undefined;
    statements.length = cursors.length = 0;
    statementsBySql?.clear();
  }});
}

function journalDatabaseGeometry(database, maxDatabaseBytes, walFrames) {
  const page = database.prepare('PRAGMA page_size').get().page_size;
  if (!Number.isSafeInteger(page) || page < 512 || page > 65536 ||
      (page & (page - 1)) !== 0) {
    fail('ClientRequestJournalDatabaseUnavailable');
  }
  const pages = Math.floor(maxDatabaseBytes / page);
  if (pages < 1 || pages > 4294967294) fail('ClientRequestJournalDatabaseUnavailable');
  // max_page_count has PragFlg_NeedSchema in the selected SQLite. Configure
  // this same live WAL support bound from the observed page geometry, then
  // select MEMORY before that pragma can load schema and its internal reader.
  // Neither operation supplies backing or acknowledges another connection.
  walFrames?.configure(page);
  return {page, pages};
}

function boundJournalDatabaseExtent(database, maxDatabaseBytes, executionLimits, walFrames,
  temporarySelected = false, retainedGeometry, prepareWalCheckpoint) {
  if (maxDatabaseBytes === undefined) return;
  const {page, pages} = retainedGeometry ?? journalDatabaseGeometry(database, maxDatabaseBytes, walFrames);
  if (!temporarySelected) selectJournalTemporaryStorage(database, executionLimits);
  // Reserve the same native checkpoint statement after MEMORY is effective,
  // before normal metadata work can exhaust its finite preparation envelope.
  prepareWalCheckpoint?.();
  const observed = database.prepare(`PRAGMA max_page_count = ${pages}`).get().max_page_count;
  if (!Number.isSafeInteger(observed) || observed < 1 || observed > pages) {
    fail('ClientRequestJournalDatabaseUnavailable');
  }
  // Each actual connection owns a separate Pager limit, including the
  // optional observation connection to the same file. This is not native
  // heap/WAL backing, a bound on another writer, or a physical reservation.
  return page;
}

function selectJournalTemporaryStorage(database, executionLimits) {
  if (executionLimits === undefined) return;
  // This selected facility uses the pinned TEMP_STORE=1 implementation:
  // connection-local memory selection covers its fixed CHECK-IN Btrees,
  // not another file/FD supplier or a process-global heap limit. The complete
  // native recipe must retain their Pager/cache/VM and allocator overhead.
  const supported = database.prepare(
    "SELECT sqlite_compileoption_used('TEMP_STORE=1') AS supported").get().supported;
  if (supported !== 1) fail('ClientRequestJournalTemporaryUnavailable');
  database.exec('PRAGMA temp_store = MEMORY');
  const selected = database.prepare('PRAGMA temp_store').get().temp_store;
  if (selected !== 2) fail('ClientRequestJournalTemporaryUnavailable');
}

// This is an inspection-work ceiling, not a stored-request limit, format
// rule, physical capacity supplier or permission. Never materialize a complete
// unbounded listing before checking it. Preserve the exact full-name snapshot
// (including unrelated retained entries) for the existing currentness check.
function journalDirectoryEntries(directory, maxInspectionEntries, primaryDirectoryInspection) {
  if (primaryDirectoryInspection !== undefined) {
    return inspectHostJournalDirectory(primaryDirectoryInspection, directory, maxInspectionEntries);
  }
  return inspectJournalDirectory(directory, {maxEntries: maxInspectionEntries,
    unavailableCode: 'ClientRequestJournalInspectionUnavailable',
    cleanupCode: 'ClientRequestJournalInspectionCleanupPending'});
}

// Closed format markers have a fixed exact length. A prior pathname stat
// cannot bound a later readFile allocation: acquire one non-following original
// FD, inspect it, and read only the fixed body plus one byte of lookahead.
// Both classification and the final snapshot fence use this same operation.
function journalMarkerMatches(path, expected) {
  let original = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW |
    constants.O_NONBLOCK);
  const originalClose = closeSync;
  let closeAttempted = false;
  const close = () => {
    if (original === undefined || closeAttempted) return;
    // A numeric FD is not a retryable object. Latch before the original
    // syscall: an error/ambiguous return may already have consumed it, and
    // the same integer can now name another Owner's descriptor.
    closeAttempted = true;
    if (applyOriginal(originalClose, undefined, [original]) !== undefined) {
      throw new TypeError('JournalMarkerCleanupPending');
    }
    original = undefined;
  };
  let failed = false, primary, matches = false;
  try {
    const first = fstatSync(original, {bigint: true});
    if (first.isFile() && first.size === BigInt(expected.length)) {
      const body = Buffer.alloc(expected.length), lookahead = Buffer.alloc(1);
      let offset = 0;
      while (offset < body.length) {
        const count = readSync(original, body, offset, body.length - offset, null);
        if (!Number.isSafeInteger(count) || count <= 0 || count > body.length - offset) {
          fail('UnknownClientRequestJournalFormat');
        }
        offset += count;
      }
      const end = readSync(original, lookahead, 0, 1, null);
      const last = fstatSync(original, {bigint: true});
      matches = end === 0 && body.equals(expected) &&
        ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].every(name => first[name] === last[name]);
    }
  } catch (cause) { failed = true; primary = cause; }
  try { close(); }
  catch (cause) {
    const observation = Object.freeze({pending: true, closeAttempted: true,
      outcome: 'unknown', errors: Object.freeze([cause])});
    const status = () => {
      void original; void originalClose;
      return observation;
    };
    const carrier = Object.assign(new Error('ClientRequestJournalInspectionCleanupPending',
      {cause: failed ? primary : cause}), {
      code: 'ClientRequestJournalInspectionCleanupPending',
      primaryFailure: failed ? primary : cause,
      // Retry only observes this same unresolved original outcome. Neither
      // EBADF, restoration, Promise settlement nor a reused FD is its ACK.
      cleanupHandle: Object.freeze({status, retry: status}),
    });
    Object.defineProperty(carrier, 'cleanupPending', {get: () => status().pending});
    throw carrier;
  }
  if (failed) throw primary;
  return matches;
}
function syncDirectory(path) {
  const descriptor = openSync(path, 'r');
  try { fsyncSync(descriptor); }
  finally { closeSync(descriptor); }
}

function checkedIdentity(handle, control) {
  const fields = {
    authorityScopeCid: control.clientRequestAuthorityScopeCid(handle),
    requestId: control.clientRequestCallerId(handle),
    logicalRequestScopeCid: control.clientRequestScopeCid(handle),
    intentFingerprintCid: control.clientRequestIntentCid(handle),
    programDefinitionCid: control.clientRequestProgramCid(handle),
    parameterValuesCid: control.clientRequestParametersCid(handle),
    callerInputIntentCid: control.clientRequestInputCid(handle),
  };
  if (!text(fields.requestId) ||
      ![fields.authorityScopeCid, fields.logicalRequestScopeCid,
        fields.intentFingerprintCid, fields.programDefinitionCid,
        fields.parameterValuesCid, fields.callerInputIntentCid].every(cid) ||
      control.clientRequestAdmitRecord(
        fields.authorityScopeCid, fields.requestId,
        fields.programDefinitionCid, fields.parameterValuesCid,
        fields.callerInputIntentCid, fields.logicalRequestScopeCid,
        fields.intentFingerprintCid) === undefined) {
    fail('InvalidClientRequestIdentity');
  }
  return Object.freeze(fields);
}

function retainedIdentity(row, control) {
  const value = control.clientRequestAdmitRecord(
    row.authority_scope_cid, row.caller_request_id,
    row.program_definition_cid, row.parameter_values_cid,
    row.caller_input_intent_cid, row.logical_request_scope_cid,
    row.intent_fingerprint_cid,
  );
  if (value === undefined) fail('ClientRequestJournalCorrupt');
  return value;
}

function admission(row) {
  if (!text(row.namespace_id) || !cid(row.authority_scope_cid) ||
      !cid(row.run_definition_cid) ||
      !Number.isSafeInteger(row.revision) || row.revision < 0 ||
      !instant(row.lookup_expires_at)) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze({
    ref: Object.freeze({
      namespaceId: row.namespace_id,
      authorityScopeCid: row.authority_scope_cid,
      runDefinitionCid: row.run_definition_cid,
    }),
    durability: 'durable',
    revision: Number(row.revision),
    lookupExpiresAt: row.lookup_expires_at,
  });
}

function checkedRunDefinition(value, control, maxBytes) {
  if (value === null || typeof value !== 'object' ||
      value.name !== 'run_definition' || !cid(value.identity) ||
      typeof value.wire !== 'string' ||
      Buffer.byteLength(value.wire, 'utf8') > maxBytes ||
      control === null || typeof control !== 'object' ||
      typeof control.admit !== 'function') {
    fail('InvalidClientRunDefinition');
  }
  let admitted;
  try {
    admitted = control.admit('run_definition', value.wire, {
      maxWireBytes: maxBytes, maxNodes: 4096, maxDepth: 64,
    });
  } catch (cause) { fail('InvalidClientRunDefinition', cause); }
  if (admitted?.name !== 'run_definition' ||
      admitted.identity !== value.identity ||
      admitted.wire !== value.wire) {
    fail('InvalidClientRunDefinition');
  }
  return admitted;
}

function retainedRunDefinition(row, control, maxBytes) {
  if (typeof row.run_definition_wire !== 'string') {
    fail('ClientRequestDefinitionMissing');
  }
  let admitted;
  try {
    admitted = checkedRunDefinition({
      name: 'run_definition',
      identity: row.run_definition_cid,
      wire: row.run_definition_wire,
    }, control, maxBytes);
  } catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  return admitted;
}

// A bounded Host-private physical inventory. Its immutable canonical string
// stays in the existing Run admission row; it is not caller input identity,
// a permission token, or a second execution journal.
export function validateSourceInventory(wire) {
  if (typeof wire !== 'string' || Buffer.byteLength(wire) > 256 * 1024) {
    fail('InvalidClientSourceInventory');
  }
  let value;
  try { value = JSON.parse(wire); } catch (cause) { fail('InvalidClientSourceInventory', cause); }
  const keys = (object, expected) => object !== null && typeof object === 'object' &&
    !Array.isArray(object) && Object.keys(object).sort().join(',') === expected.split(',').sort().join(',');
  if (value?.version === BOUND_SOURCE_INVENTORY) {
    let canonical;
    try { canonical = canonicalValueJson(value, {dataKeys: true}); }
    catch (cause) { fail('InvalidClientSourceInventory', cause); }
    if (!keys(value, 'version,environmentCid,acquisitions') || !cid(value.environmentCid) ||
        canonical !== wire ||
        !Array.isArray(value.acquisitions) || value.acquisitions.length !== 2 ||
        !value.acquisitions.every(validBoundSourceOccurrence) ||
        (value.acquisitions.every(item => item.checkedSource.requirementCid !== undefined)
          ? value.acquisitions[0].checkedSource.requirementCid === value.acquisitions[1].checkedSource.requirementCid
          : value.acquisitions[0].stage === value.acquisitions[1].stage &&
            value.acquisitions[0].input === value.acquisitions[1].input)) fail('InvalidClientSourceInventory');
    return wire;
  }
  if (value?.version === 'actql-client-keyed-source-inventory/0.1') {
    // The installed Connector owns the target's physical schema. The journal
    // retains its exact data plus immutable installation binding, not another
    // provider-name dispatcher. Semantic preparation and replay still match
    // the original checked selections before physical start.
    if (!keys(value, 'version,environmentCid,acquisitions') || !cid(value.environmentCid) ||
        canonicalValueJson(value, {dataKeys: true}) !== wire ||
        !Array.isArray(value.acquisitions) || value.acquisitions.length !== 2) {
      fail('InvalidClientSourceInventory');
    }
    const commonKeys = 'sourceRef,sourceContractCid,carrierSchemaContractCid,sourceDataPolicyCid,dataClassification,sourceViewContractCid';
    // Source occurrence order is not physical task identity: a Content
    // component can consume both original reads inside task 0. The selection
    // CID below still binds the exact checked task, port and JOIN step.
    for (const [index, occurrence] of value.acquisitions.entries()) {
      const source = occurrence?.checkedSource, binding = occurrence?.installationBinding;
      if (!keys(occurrence, 'stage,input,task,checkedSource,readTuple,physicalBinding,installationBinding') ||
          !Number.isSafeInteger(occurrence.stage) || occurrence.stage < 0 ||
          !Number.isSafeInteger(occurrence.input) || occurrence.input < 0 ||
          (index === 0 ? occurrence.task !== 0 : occurrence.task !== 0 && occurrence.task !== 1) ||
          !keys(source, commonKeys + (index === 0 ? ',requirementCid,inputContractCid,outputContractCid'
            : ',selectionCid,programCid,parametersCid,step')) ||
          ![source.sourceContractCid, source.carrierSchemaContractCid, source.sourceDataPolicyCid,
            source.sourceViewContractCid, ...(index === 0
              ? [source.requirementCid, source.inputContractCid, source.outputContractCid]
              : [source.selectionCid, source.programCid, source.parametersCid])].every(cid) ||
          !text(source.sourceRef) || !['public', 'internal', 'confidential', 'restricted', 'unknown']
            .includes(source.dataClassification) ||
          !keys(binding, 'connectorId,connectorRegistration,connectorRevision,bindingCid') ||
          ![binding.connectorId, binding.connectorRegistration, binding.connectorRevision].every(text) ||
          !cid(binding.bindingCid) || !keys(occurrence.readTuple, 'connection,resource,operation') ||
          ![occurrence.readTuple.connection, occurrence.readTuple.resource].every(text) ||
          occurrence.readTuple.operation !== 'read' || occurrence.physicalBinding === null ||
          typeof occurrence.physicalBinding !== 'object' || Array.isArray(occurrence.physicalBinding) ||
          Object.keys(occurrence.physicalBinding).length === 0) fail('InvalidClientSourceInventory');
      if (index === 1) {
        if (!Number.isSafeInteger(source.step) || source.step < 0) fail('InvalidClientSourceInventory');
        const selection = {version: 'actql-installed-keyed-selection/0.1',
          programCid: source.programCid, parametersCid: source.parametersCid,
          coordinates: [occurrence.stage, occurrence.input, occurrence.task, source.step],
          sourceFacts: [source.sourceRef, source.sourceContractCid, source.carrierSchemaContractCid,
            source.sourceDataPolicyCid, source.dataClassification, source.sourceViewContractCid]};
        if (`sha256:${createHash('sha256').update(canonicalValueJson(selection, {dataKeys: true})).digest('hex')}` !==
            source.selectionCid) fail('InvalidClientSourceInventory');
      }
    }
    if (value.acquisitions[0].stage !== value.acquisitions[1].stage ||
        value.acquisitions[0].input === value.acquisitions[1].input) fail('InvalidClientSourceInventory');
    return wire;
  }
  if (!keys(value, 'version,environmentCid,acquisitions') ||
      value.version !== 'actql-client-source-inventory/0.1' || !cid(value.environmentCid) ||
      !Array.isArray(value.acquisitions) || value.acquisitions.length !== 2 ||
      canonicalJson(value) !== wire) fail('InvalidClientSourceInventory');
  const requirements = new Set();
  const validPhysicalBinding = binding => {
    if (keys(binding, 'version,database,schema,table,utf8_hex') &&
        binding.version === 'actql-installed-duckdb-target/0.1') {
      return keys(binding.utf8_hex, 'database,schema,table') &&
        !['database','schema','table'].some(key => typeof binding[key] !== 'string' ||
          !binding[key] || typeof binding.utf8_hex[key] !== 'string' ||
          !/^(?:[0-9a-f]{2})+$/u.test(binding.utf8_hex[key]) ||
          Buffer.from(Buffer.from(binding.utf8_hex[key], 'hex').toString('utf8'), 'utf8').toString('hex') !== binding.utf8_hex[key] ||
          Buffer.from(binding.utf8_hex[key], 'hex').toString('utf8').normalize('NFC') !== binding[key]);
    }
    if (keys(binding, 'version,org_id,instance_origin,site_key,site_generation,connection_revision,catalog_cid,resource,fields') &&
        binding.version === 'actql-installed-salesforce-target/0.1') {
      let origin;
      try { origin = new URL(binding.instance_origin); } catch { return false; }
      return origin.protocol === 'https:' && origin.origin === binding.instance_origin &&
        [binding.org_id, binding.site_key, binding.connection_revision,
          binding.resource].every(value => typeof value === 'string' && value !== '') &&
        Number.isSafeInteger(binding.site_generation) && binding.site_generation >= 0 &&
        cid(binding.catalog_cid) && Array.isArray(binding.fields) &&
        binding.fields.length > 0 && binding.fields.length <= 100 &&
        binding.fields.every(value => typeof value === 'string' && value !== '') &&
        new Set(binding.fields).size === binding.fields.length;
    }
    // This is a Host-private physical target, not a new common Engine
    // identity. The installed Site checks it again against its publication.
    let origin;
    try { origin = new URL(binding?.api_origin); } catch { return false; }
    return keys(binding, 'version,api_origin,repository_id,repository_node_id,owner,repo,catalog_cid,resource,fields') &&
      binding.version === 'actql-installed-github-target/0.1' &&
      origin.protocol === 'https:' && origin.origin === binding.api_origin &&
      Number.isSafeInteger(binding.repository_id) && binding.repository_id > 0 &&
      [binding.repository_node_id, binding.owner, binding.repo,
        binding.resource].every(value => typeof value === 'string' && value !== '') &&
      cid(binding.catalog_cid) && Array.isArray(binding.fields) &&
      binding.fields.length > 0 && binding.fields.length <= 100 &&
      binding.fields.every(value => typeof value === 'string' && value !== '') &&
      new Set(binding.fields).size === binding.fields.length;
  };
  for (const [index, occurrence] of value.acquisitions.entries()) {
    if (!keys(occurrence, 'stage,input,task,checkedSource,readTuple,physicalBinding') ||
        occurrence.stage !== index || occurrence.input !== 0 || occurrence.task !== index ||
        !keys(occurrence.checkedSource, 'requirementCid,sourceRef,sourceContractCid,carrierSchemaContractCid,sourceDataPolicyCid,dataClassification,sourceViewContractCid,inputContractCid,outputContractCid') ||
        !keys(occurrence.readTuple, 'connection,resource,operation') ||
        !validPhysicalBinding(occurrence.physicalBinding)) {
      fail('InvalidClientSourceInventory');
    }
    const source = occurrence.checkedSource, binding = occurrence.physicalBinding;
    if (![source.requirementCid, source.sourceContractCid, source.carrierSchemaContractCid,
      source.sourceDataPolicyCid, source.sourceViewContractCid, source.inputContractCid,
      source.outputContractCid].every(cid) || typeof source.sourceRef !== 'string' ||
      !source.sourceRef || !['public', 'internal', 'confidential', 'restricted', 'unknown']
        .includes(source.dataClassification) || requirements.has(source.requirementCid) ||
      occurrence.readTuple.operation !== 'read' ||
      typeof occurrence.readTuple.connection !== 'string' || !occurrence.readTuple.connection ||
      typeof occurrence.readTuple.resource !== 'string' || !occurrence.readTuple.resource ||
      !validPhysicalBinding(binding) ||
      (binding.version === 'actql-installed-github-target/0.1' &&
        (binding.resource !== occurrence.readTuple.resource ||
         occurrence.readTuple.connection !==
           `github:${new URL(binding.api_origin).host}/${binding.owner}/${binding.repo}`)) ||
      (binding.version === 'actql-installed-salesforce-target/0.1' &&
        (binding.resource !== occurrence.readTuple.resource ||
         occurrence.readTuple.connection !== `salesforce:${binding.org_id}`))) {
      fail('InvalidClientSourceInventory');
    }
    requirements.add(source.requirementCid);
  }
  return wire;
}

function logicalPlanOriginalShape(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).sort().join(',') === 'compiledPlanWire,planViewWire' &&
    typeof value.compiledPlanWire === 'string' && value.compiledPlanWire !== '' &&
    typeof value.planViewWire === 'string' && value.planViewWire !== '';
}

function assertKeyedInventoryRequest(wire, fields) {
  if (wire === undefined) return;
  const inventory = JSON.parse(wire);
  if (inventory.version !== 'actql-client-keyed-source-inventory/0.1') return;
  const selection = inventory.acquisitions[1].checkedSource;
  if (selection.programCid !== fields.programDefinitionCid ||
      selection.parametersCid !== fields.parameterValuesCid) {
    fail('ClientRequestSourceInventoryMismatch');
  }
}

const admissionEvidenceFields = Object.freeze(['authorization', 'prepared',
  'sourceInventory', 'resultPolicyOriginal', 'modelOriginalRunWire',
  'valuesHostPolicyOriginal', 'logicalPlanOriginal', 'updateTargetRunOriginal',
  'submittedIntentCid', 'effectOriginalRunWire', 'inferRunOriginal']);

function admissionEvidenceShape(value, updateOriginalControl, captured) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  if (Object.keys(value).some(key => !admissionEvidenceFields.includes(key)) ||
      !Object.hasOwn(value, 'prepared') || !Object.hasOwn(value, 'authorization') ||
      typeof value.prepared !== 'string' || typeof value.authorization !== 'string') return false;
  if (value.submittedIntentCid !== undefined && !cid(value.submittedIntentCid)) return false;
  // Bounded original-codec DATA only. Its Common material reader must still
  // admit the full Run/request/evidence pair before a restored use. Presence
  // in this private record is neither that admission nor a resume permission.
  if (value.effectOriginalRunWire !== undefined &&
      (typeof value.effectOriginalRunWire !== 'string' || value.effectOriginalRunWire.length === 0)) return false;
  if (value.inferRunOriginal !== undefined) {
    const original = value.inferRunOriginal;
    if (original === null || typeof original !== 'object' || Array.isArray(original)) return false;
    const keys = Object.keys(original);
    if (keys.length !== 2 || !keys.includes('materialsWire') || !keys.includes('resultPolicyOriginal') ||
        typeof original.materialsWire !== 'string' || original.materialsWire.length === 0) return false;
    const policy = original.resultPolicyOriginal;
    if (policy === null || typeof policy !== 'object' || Array.isArray(policy)) return false;
    const policyKeys = Object.keys(policy);
    if (policyKeys.length !== 3 || !['kind', 'cid', 'wire'].every(key => policyKeys.includes(key)) ||
        policy.kind !== 'data_policy' || !cid(policy.cid) || typeof policy.wire !== 'string') return false;
  }
  if (value.sourceInventory !== undefined) validateSourceInventory(value.sourceInventory);
  if (value.updateTargetRunOriginal !== undefined &&
      updateOriginalControl?.run(value.updateTargetRunOriginal, value) !== true) return false;
  if (value.logicalPlanOriginal !== undefined &&
      !logicalPlanOriginalShape(value.logicalPlanOriginal)) return false;
  if (value.valuesHostPolicyOriginal !== undefined) {
    const original = value.valuesHostPolicyOriginal;
    if (original === null || typeof original !== 'object' || Array.isArray(original) ||
        Object.keys(original).sort().join(',') !== 'cid,wire' ||
        !cid(original.cid) || typeof original.wire !== 'string') return false;
    let body, prepared, authorization;
    try {
      body = JSON.parse(original.wire);
      prepared = JSON.parse(value.prepared);
      authorization = JSON.parse(value.authorization);
    } catch { return false; }
    if (body === null || typeof body !== 'object' || Array.isArray(body) ||
        Object.keys(body).sort().join(',') !== 'max_rows,name,version' ||
        body.version !== 'actql-installed-local-policy/0.1' ||
        body.name !== 'source-free-values' ||
        !Number.isSafeInteger(body.max_rows) || body.max_rows < 1 || body.max_rows > 10000 ||
        canonicalJson(body) !== original.wire ||
        `sha256:${createHash('sha256').update(original.wire).digest('hex')}` !== original.cid ||
        prepared?.host_policy_cid !== original.cid ||
        authorization?.host_policy_cid !== original.cid) return false;
  }
  if (value.resultPolicyOriginal !== undefined &&
      (value.resultPolicyOriginal === null ||
       typeof value.resultPolicyOriginal !== 'object' ||
       Array.isArray(value.resultPolicyOriginal) ||
       Object.keys(value.resultPolicyOriginal).sort().join(',') !== 'cid,kind,wire' ||
       value.resultPolicyOriginal.kind !== 'data_policy' ||
       typeof value.resultPolicyOriginal.cid !== 'string' ||
       typeof value.resultPolicyOriginal.wire !== 'string')) return false;
  if (value.modelOriginalRunWire !== undefined) {
    if (typeof value.modelOriginalRunWire !== 'string') return false;
    let original;
    try { original = JSON.parse(value.modelOriginalRunWire); } catch { return false; }
    if (original === null || typeof original !== 'object' || Array.isArray(original) ||
        Object.keys(original).sort().join(',') !==
          'boundInvocationTemplateWire,compiledPlanWire,preparedInvocationWire,runAuthorizationWire,runDefinitionWire' ||
        Object.values(original).some(wire => typeof wire !== 'string' || wire === '') ||
        canonicalValueJson(original) !== value.modelOriginalRunWire ||
        original.preparedInvocationWire !== value.prepared ||
        original.runAuthorizationWire !== value.authorization) return false;
    if (captured !== undefined) captured.modelRunDefinitionWire = original.runDefinitionWire;
  }
  return true;
}

function assertSourceInventory(retained, proposed) {
  if (proposed !== undefined) validateSourceInventory(proposed);
  // A physical start can only be reconciled through its retained owner; a
// later configuration never becomes authority to restart its sources.
  if (retained.physicalStartReserved === true) return;
  if (retained.runAdmissionEvidence?.sourceInventory !== proposed) {
    fail('ClientRequestSourceInventoryMismatch');
  }
}

// Private replay evidence is stored atomically with acceptance. Its semantic
// admission remains with the common MoonBit owner before any physical start.
function evidenceJson(value, maxBytes, updateOriginalControl) {
  if (value === undefined) return null;
  // Capture mutable input once, then admit the exact bytes that can be stored.
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !admissionEvidenceFields.includes(key)) ||
      !Object.hasOwn(value, 'prepared') || !Object.hasOwn(value, 'authorization')) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  const wire = JSON.stringify(value);
  if (typeof wire !== 'string' || Buffer.byteLength(wire) > maxBytes) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  const captured = {wire, value: JSON.parse(wire)};
  if (!admissionEvidenceShape(captured.value, updateOriginalControl, captured)) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  freezeAdmissionEvidence(captured.value);
  return Object.freeze(captured);
}

function retainedEvidence(row, updateOriginalControl, original) {
  if (row.run_admission_evidence_json === null) return undefined;
  if (original != null && row.run_admission_evidence_json === original.wire) return original.value;
  let value;
  try { value = JSON.parse(row.run_admission_evidence_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  // This acceptance already admitted every unchanged material. A saved intent
  // CID is the only permitted addition, and it still receives its own check.
  if (original != null && original.value.submittedIntentCid === undefined &&
      cid(value?.submittedIntentCid) && JSON.stringify({...original.value,
        submittedIntentCid: value.submittedIntentCid}) === row.run_admission_evidence_json) {
    return freezeAdmissionEvidence(value);
  }
  try {
    if (!admissionEvidenceShape(value, updateOriginalControl)) fail('ClientRequestJournalCorrupt');
    assertKeyedInventoryRequest(value.sourceInventory, {
      programDefinitionCid: row.program_definition_cid,
      parameterValuesCid: row.parameter_values_cid});
  } catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  return freezeAdmissionEvidence(value);
}

function freezeAdmissionEvidence(value) {
  if (value.logicalPlanOriginal !== undefined) Object.freeze(value.logicalPlanOriginal);
  if (value.inferRunOriginal !== undefined) {
    Object.freeze(value.inferRunOriginal.resultPolicyOriginal);
    Object.freeze(value.inferRunOriginal);
  }
  if (value.updateTargetRunOriginal !== undefined) {
    value.updateTargetRunOriginal.installations.forEach(Object.freeze);
    Object.freeze(value.updateTargetRunOriginal.installations);
    Object.freeze(value.updateTargetRunOriginal);
  }
  return Object.freeze(value);
}

function retainedResultNames(row, maxWireBytes) {
  if (row.result_names_json === null) return undefined;
  // Reuse the installed per-metadata-object wire allowance before JSON
  // expansion. This is not an aggregate database or whole-record grant;
  // Result cardinality comes from the retained original inventory.
  if (Buffer.byteLength(row.result_names_json, 'utf8') > maxWireBytes) {
    fail('ClientRequestJournalCorrupt');
  }
  let names;
  try { names = JSON.parse(row.result_names_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  if (!Array.isArray(names) ||
      names.some(name => typeof name !== 'string' || !name) ||
      new Set(names).size !== names.length) {
    fail('ClientRequestJournalCorrupt');
  }
  return names;
}

function retainedRunFacts(row, publicationControl, maxWireBytes, updateOriginalControl) {
  if (![0, 1].includes(row.dispatch_reserved) ||
      ![0, 1].includes(row.pre_dispatch_failure_confirmed) ||
      ![null, 0, 1].includes(row.physical_start_reserved) ||
      ![0, 1].includes(row.cancellation_requested) ||
      ![0, 1].includes(row.physical_close_confirmed) ||
      ![null, 'failed', 'cancelled'].includes(
        row.observed_terminal_outcome)) {
    fail('ClientRequestJournalCorrupt');
  }
  const runAdmissionEvidence = retainedEvidence(row, updateOriginalControl);
  const runDefinition = retainedRunDefinition(row, publicationControl,
    maxWireBytes);
  if (runAdmissionEvidence?.valuesHostPolicyOriginal !== undefined &&
      JSON.parse(row.run_definition_wire).authorization_context_cid !==
        valuesExecutionContextCid(row.authority_scope_cid,
          runAdmissionEvidence.valuesHostPolicyOriginal)) {
    fail('ClientRequestJournalCorrupt');
  }
  if (runAdmissionEvidence?.modelOriginalRunWire !== undefined &&
      JSON.parse(runAdmissionEvidence.modelOriginalRunWire).runDefinitionWire !== row.run_definition_wire) {
    fail('ClientRequestJournalCorrupt');
  }
  // Metadata/status/control consumes the admitted Run and current row flags,
  // not its logical map. Keep the bounded original bytes here; the existing
  // plan reader checks their semantic binding only when that map is used.
  const savedPlan = runAdmissionEvidence?.logicalPlanOriginal;
  if (savedPlan !== undefined &&
      (Buffer.byteLength(savedPlan.compiledPlanWire) > maxWireBytes ||
       Buffer.byteLength(savedPlan.planViewWire) > maxWireBytes)) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze({
    runDefinition,
    programDefinitionCid: row.program_definition_cid,
    resultNames: retainedResultNames(row, maxWireBytes),
    runAdmissionEvidence,
    cancellationRequested: row.cancellation_requested === 1,
    physicalCloseConfirmed: row.physical_close_confirmed === 1,
    dispatchReserved: row.dispatch_reserved === 1,
    preDispatchFailureConfirmed:
      row.pre_dispatch_failure_confirmed === 1,
    physicalStartReserved: row.physical_start_reserved === null
      ? undefined : row.physical_start_reserved === 1,
    observedTerminalOutcome: row.observed_terminal_outcome,
  });
}

// The existing observation key already retains every non-clock state field.
// Reuse only its closed budget message for this SAME failed Run/control frame;
// no second store, error chain, execution owner or status inference is added.
function retainedBudgetFailureMessage(key, state, runId, control) {
  if (typeof key !== 'string' || state.status !== 'failed' ||
      state.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN' ||
      control.physical_stop !== 'confirmed') return undefined;
  let previous;
  try { previous = JSON.parse(key); } catch { return undefined; }
  if (previous?.run_id !== runId || previous.status !== 'failed' ||
      previous.result_available !== false || previous.next_action?.kind !== 'none' ||
      previous.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN' ||
      previous.control === null || typeof previous.control !== 'object' ||
      Object.keys(previous.control).sort().join('\0') !== Object.keys(control).sort().join('\0') ||
      Object.keys(control).some(name => previous.control[name] !== control[name])) return undefined;
  const message = previous.terminal_error.message;
  if (typeof message !== 'string') return undefined;
  const amount = '(?:0|[1-9][0-9]{0,18}|unavailable)';
  const prefix = 'Budget exceeded: phase=local_managed_advance; dimension=';
  const memory = new RegExp('^' + prefix + '(retained_bytes|execution_bytes); requested_delta=' + amount +
    '; remaining=' + amount + '; policy=' + amount + '; unit=logical_bytes; setting=installation\\.requestMemory\\.' +
    '(retainedBytes|executionBytes)\\. Logical quota, not process RSS\\.$', 'u').exec(message);
  if (memory && memory[2] === (memory[1] === 'retained_bytes' ? 'retainedBytes' : 'executionBytes')) return message;
  const work = new RegExp('^' + prefix + '(?:value_capture_work|control_work); requested_delta=(?:>=[1-9][0-9]{0,18}|unavailable)' +
    '; remaining=' + amount + '; policy=' + amount + '; unit=work_units; setting=installation\\.sourceFreeMaxWork\\. ' +
    'Runtime work, not Program parsing/checking\\. A lower bound does not give the complete UTF8 demand\\.$', 'u');
  return work.test(message) ? message : undefined;
}

const columns = `authority_scope_cid, caller_request_id,
  logical_request_scope_cid, intent_fingerprint_cid,
  program_definition_cid, parameter_values_cid, caller_input_intent_cid,
  namespace_id, run_definition_cid, run_definition_wire, revision,
  lookup_expires_at, result_names_json, run_admission_evidence_json`;
const selectColumns = `${columns}, dispatch_reserved,
  pre_dispatch_failure_confirmed, physical_start_reserved,
  cancellation_requested, physical_close_confirmed,
  observed_terminal_outcome, state_revision, state_observation_key`;
const journalMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1',
  isolation: 'execution-namespace',
}), 'utf8');
const journalColumns = [...columns.split(',').map(name => name.trim()),
  'dispatch_reserved', 'pre_dispatch_failure_confirmed',
  'physical_start_reserved', 'cancellation_requested',
  'physical_close_confirmed', 'observed_terminal_outcome',
  'reconciliation_state_wire', 'state_revision', 'state_observation_key'].sort();

// One bounded receipt per already admitted Run, committed with its first
// physical-start claim. This is private observation data, not a start/retry
// permission. Old journals/rows without it retain their unknown outcome.
const localExecutionOwnerTable = `CREATE TABLE client_local_execution_owners (
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_requests(run_definition_cid) ON DELETE CASCADE,
  owner_token TEXT NOT NULL CHECK (length(owner_token) = 36),
  anchor_identity TEXT NOT NULL CHECK (length(anchor_identity) = 36),
  anchor_device TEXT NOT NULL CHECK (length(anchor_device) BETWEEN 1 AND 32),
  anchor_inode TEXT NOT NULL CHECK (length(anchor_inode) BETWEEN 1 AND 32)
) STRICT`;
function inspectLocalExecutionOwnerStorage(database) {
  const row = database.prepare("SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_local_execution_owners'")
    .get(localExecutionOwnerTable.length + 1);
  if (row !== undefined && row.sql !== localExecutionOwnerTable) {
    fail('UnknownClientRequestJournalFormat');
  }
}
function validLocalExecutionOwnerReceipt(value) {
  const uuid = value => typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(value);
  const coordinate = value => typeof value === 'string' && /^[0-9]{1,32}$/u.test(value);
  return uuid(value?.token) && uuid(value?.anchor?.identity) &&
    coordinate(value?.anchor?.device) && coordinate(value?.anchor?.inode);
}

// Additive custody in the existing request journal. The original format marker
// is retained byte-for-byte; partially introduced custody is never reset.
const cancellationMarkerName = 'cancellation-operations-format.json';
const cancellationMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'cancellation_operations',
}));
const cancellationColumns = ['namespace_id', 'authority_scope_cid', 'cancel_id',
  'run_definition_cid', 'expected_revision', 'intent_fingerprint_cid',
  'outcome_wire', 'outcome_cid'].sort();

// Retain issuance independently of replay rows in this same journal. Losing
// a row cannot turn its consumed identity into a fresh admission opportunity.
const submissionMarkerName = 'submission-custody-format.json';
const submissionMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_custody',
}));
function inspectSubmissionStorage(database, enabled) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submission_custody'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_custody)')
    .all().map(field => field.name).sort();
  const records = database.prepare('SELECT singleton, issued_count FROM client_submission_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(['issued_count', 'singleton']) ||
      records.length !== 1 || records[0].singleton !== 1 ||
      !Number.isSafeInteger(records[0].issued_count) || records[0].issued_count < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
  // A lost replay row fences writes, but does not erase surviving individual
  // observations. Reopening must not reset this counter to the remaining rows.
}

const epochMarkerName = 'submission-epoch-format.json';
const intentMarkerName = 'submitted-intent-format.json';
const retirementMarkerName = 'submitted-intent-retirement-format.json';
const restartMarkerName = 'submission-restart-format.json';
const nameMarkerName = 'submission-name-format.json';
// Retained only to recognize the earlier two-step derived-metadata adoption.
// New adoption commits its private format transition inside SQLite instead.
const usageMarkerName = 'submission-usage-format.json';
// These are lookup/quota metadata of the SAME Journal, not admission receipts.
// Native triggers update them in the original row mutation's transaction.
const submissionUsageSources = [
  ['client_submitted_intent_usage','client_submitted_intents','intent_wire'],
  ['client_submission_restart_usage','client_submission_restarts','link_wire'],
];
const submissionUsageTables = submissionUsageSources.map(([name]) => [name,
  `CREATE TABLE ${name} (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991),
    retained_bytes INTEGER NOT NULL CHECK (retained_bytes >= 0 AND retained_bytes <= 67108864),
    revision INTEGER NOT NULL CHECK (revision >= 0 AND revision <= 9007199254740991)
  ) STRICT`]);
const submissionUsageTriggers = submissionUsageSources.flatMap(([usage,table,wire]) => [
  [`${usage}_insert`, `CREATE TRIGGER ${usage}_insert AFTER INSERT ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count + 1,
      retained_bytes = retained_bytes + length(CAST(NEW.${wire} AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`],
  [`${usage}_delete`, `CREATE TRIGGER ${usage}_delete AFTER DELETE ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count - 1,
      retained_bytes = retained_bytes - length(CAST(OLD.${wire} AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`],
  [`${usage}_update`, `CREATE TRIGGER ${usage}_update AFTER UPDATE OF ${wire} ON ${table} BEGIN
    UPDATE ${usage} SET retained_bytes = retained_bytes
      - length(CAST(OLD.${wire} AS BLOB)) + length(CAST(NEW.${wire} AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`],
]);
const validSubmissionUsage = row => row?.singleton === 1 &&
  Number.isSafeInteger(row.retained_count) && row.retained_count >= 0 &&
  Number.isSafeInteger(row.retained_bytes) && row.retained_bytes >= 0 && row.retained_bytes <= 67108864 &&
  Number.isSafeInteger(row.revision) && row.revision >= 0;
const journalRowUsageSources = [
  ['client_request_row_usage','client_requests','client_submission_custody'],
  ['client_cancellation_row_usage','client_cancellation_operations','client_cancellation_custody'],
];
const journalRowUsageTables = journalRowUsageSources.map(([usage]) => [usage,`CREATE TABLE ${usage} (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991)
) STRICT`]);
const journalRowUsageTriggers = journalRowUsageSources.flatMap(([usage,table]) => [
  [`${usage}_insert`,`CREATE TRIGGER ${usage}_insert AFTER INSERT ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count + 1 WHERE singleton = 1;
  END`],
  [`${usage}_delete`,`CREATE TRIGGER ${usage}_delete AFTER DELETE ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count - 1 WHERE singleton = 1;
  END`],
]);
const validJournalRowUsage = row => row?.singleton === 1 &&
  Number.isSafeInteger(row.retained_count) && row.retained_count >= 0;
function inspectJournalRowUsage(database, version) {
  const originals=[...journalRowUsageTables,...journalRowUsageTriggers], names=originals.map(([name])=>name);
  const schema=database.prepare(`SELECT name,sql FROM sqlite_master
    WHERE name IN (${names.map(()=>'?').join(',')})`).all(...names);
  if(version<2 && schema.length===0) return;
  if(version!==2 || schema.length!==originals.length || originals.some(([name,sql])=>
    schema.find(row=>row.name===name)?.sql!==sql)) fail('UnknownClientRequestJournalFormat');
  for(const [table] of journalRowUsageTables) {
    if(!validJournalRowUsage(database.prepare(`SELECT * FROM ${table} WHERE singleton=1`).get())) {
      fail('UnknownClientRequestJournalFormat');
    }
  }
}
function inspectSubmissionUsageStorage(database, enabled) {
  const version = database.prepare('PRAGMA user_version').get()?.user_version;
  if (![0,1,2].includes(version)) fail('UnknownClientRequestJournalFormat');
  inspectJournalRowUsage(database,version);
  const originals = [...submissionUsageTables,...submissionUsageTriggers];
  const names = originals.map(([name]) => name);
  const schema = database.prepare(`SELECT name,sql FROM sqlite_master
    WHERE name IN (${names.map(() => '?').join(',')})`).all(...names);
  if (!enabled && version === 0 && schema.length === 0) return false;
  if (schema.length !== originals.length || originals.some(([name,sql]) =>
    schema.find(row => row.name === name)?.sql !== sql)) fail('UnknownClientRequestJournalFormat');
  for (const [table] of submissionUsageTables) {
    if (!validSubmissionUsage(database.prepare(`SELECT * FROM ${table} WHERE singleton=1`).get())) {
      fail('UnknownClientRequestJournalFormat');
    }
  }
  return true;
}

function createSubmissionUsageStorage(database, retained) {
  database.exec(submissionUsageTables.map(([,sql]) => `${sql};`).join('\n'));
  for (let i=0;i<submissionUsageTables.length;i++) {
    database.prepare(`INSERT INTO ${submissionUsageTables[i][0]} VALUES(1,?,?,0)`)
      .run(retained[i].n,retained[i].bytes);
  }
  database.exec(submissionUsageTriggers.map(([,sql]) => `${sql};`).join('\n'));
}
function createJournalRowUsageStorage(database, retainedRows) {
  database.exec(journalRowUsageTables.map(([,sql])=>`${sql};`).join('\n'));
  for(let i=0;i<journalRowUsageTables.length;i++) {
    database.prepare(`INSERT INTO ${journalRowUsageTables[i][0]} VALUES(1,?)`).run(retainedRows[i]);
  }
  database.exec(journalRowUsageTriggers.map(([,sql])=>`${sql};`).join('\n'));
}
function adoptSubmissionUsageStorage(database, transact, previousMarker, fresh) {
  const complete = !fresh && inspectSubmissionUsageStorage(database,previousMarker);
  transact(() => {
    if (fresh) {
      // This connection created all source tables in this same transaction.
      // No historical issuance exists to census or adopt.
      createSubmissionUsageStorage(database,[{n:0,bytes:0},{n:0,bytes:0}]);
      createJournalRowUsageStorage(database,[0,0]);
      database.exec('PRAGMA user_version=2');
      return;
    }
    const issued = database.prepare('SELECT issued_count FROM client_submitted_intent_custody WHERE singleton=1').get()?.issued_count;
    const retired = database.prepare('SELECT retired_count FROM client_submitted_intent_retirement WHERE singleton=1').get()?.retired_count;
    const restarts = database.prepare('SELECT issued_count FROM client_submission_restart_custody WHERE singleton=1').get()?.issued_count;
    if (![issued,retired,restarts].every(n => Number.isSafeInteger(n) && n >= 0) ||
        retired > issued || issued - retired === Number.MAX_SAFE_INTEGER || restarts === Number.MAX_SAFE_INTEGER) {
      fail('ClientSubmittedIntentCustodyLost');
    }
    const counts = [issued-retired,restarts];
    if (complete) {
      for (let i=0;i<submissionUsageTables.length;i++) {
        const usage = database.prepare(`SELECT retained_count FROM ${submissionUsageTables[i][0]} WHERE singleton=1`).get();
        if (usage?.retained_count !== counts[i]) fail('ClientSubmittedIntentCustodyLost');
      }
    } else {
    // One bounded legacy adoption, never a normal-open or per-operation scan.
    // The existing original issuance/retirement bounds the selected prefix;
    // one extra row detects missing coverage instead of silently truncating it.
    const retained = submissionUsageSources.map(([,table,wire],index) => {
      const row = database.prepare(`SELECT COUNT(*) AS n,COALESCE(SUM(length(CAST(${wire} AS BLOB))),0) AS bytes
        FROM (SELECT ${wire} FROM ${table} LIMIT ?)` ).get(counts[index]+1);
      if (row.n !== counts[index] || !Number.isSafeInteger(row.bytes) || row.bytes < 0 || row.bytes > 67108864) {
        fail(index === 0 ? 'ClientSubmittedIntentCustodyLost' : 'ClientSubmissionRestartCustodyLost');
      }
      return row;
    });
    createSubmissionUsageStorage(database,retained);
    }
    // Extend the same private adoption transaction. No request or cancel is
    // issued here: original cumulative custody bounds this one legacy census.
    const retainedRows=journalRowUsageSources.map(([,table,custody])=>{
      const issued=database.prepare(`SELECT issued_count FROM ${custody} WHERE singleton=1`).get()?.issued_count;
      if(!Number.isSafeInteger(issued) || issued<0 || issued===Number.MAX_SAFE_INTEGER) fail('ClientRequestSubmissionCustodyLost');
      const n=database.prepare(`SELECT COUNT(*) AS n FROM (SELECT 1 FROM ${table} LIMIT ?)`).get(issued+1).n;
      if(n!==issued) fail(table==='client_requests'?'ClientRequestSubmissionCustodyLost':'ClientRequestJournalCorrupt');
      return n;
    });
    createJournalRowUsageStorage(database,retainedRows);
    database.exec('PRAGMA user_version=2');
  });
}
const nameMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'scoped_submission_names',
}));
const nameTables = [
  ['client_submission_names', `CREATE TABLE client_submission_names (
          namespace_id TEXT NOT NULL,
          actor_id TEXT NOT NULL,
          name TEXT NOT NULL,
          authority_scope_cid TEXT NOT NULL,
          submission_id TEXT NOT NULL UNIQUE,
          intent_cid TEXT NOT NULL,
          binding_authenticator TEXT NOT NULL,
          PRIMARY KEY (namespace_id, actor_id, name)
        ) STRICT`],
  ['client_submission_name_custody', `CREATE TABLE client_submission_name_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0),
          retained_count INTEGER NOT NULL CHECK (retained_count >= 0)
        ) STRICT`],
];
const nameTriggers = [
  ['client_submission_name_insert_count', `CREATE TRIGGER client_submission_name_insert_count
    AFTER INSERT ON client_submission_names BEGIN
      UPDATE client_submission_name_custody SET retained_count = retained_count + 1 WHERE singleton = 1;
    END`],
  ['client_submission_name_delete_count', `CREATE TRIGGER client_submission_name_delete_count
    AFTER DELETE ON client_submission_names BEGIN
      UPDATE client_submission_name_custody SET retained_count = retained_count - 1 WHERE singleton = 1;
    END`],
];
const restartMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_restarts',
}));
const retirementMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submitted_intent_retirement',
}));
const intentMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submitted_intents',
}));
const epochMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_epochs',
}));
const maxEpochTtlMs = 7 * 24 * 60 * 60 * 1000;
const hexKey = value => typeof value === 'string' && /^[0-9a-f]{64}$/u.test(value);
function validEpochAuthority(row) {
  return row?.singleton === 1 && hexKey(row.authentication_key) &&
    Number.isSafeInteger(row.observed_at) && row.observed_at >= 0 &&
    row.observed_at <= Number.MAX_SAFE_INTEGER - maxEpochTtlMs;
}
function inspectEpochStorage(database, enabled) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submission_epoch_authority'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_epoch_authority)')
    .all().map(field => field.name).sort();
  const records = database.prepare('SELECT * FROM client_submission_epoch_authority').all();
  if (JSON.stringify(fields) !== JSON.stringify(['authentication_key', 'observed_at', 'singleton']) ||
      records.length !== 1 || !validEpochAuthority(records[0])) {
    fail('UnknownClientRequestJournalFormat');
  }
}
function inspectIntentStorage(database, enabled) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submitted_intents', 'client_submitted_intent_custody')`).all();
  if (!enabled && names.length === 0) return;
  if (!enabled || names.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submitted_intents)').all()
    .map(field => field.name).sort();
  const expected = ['authority_scope_cid', 'submission_id', 'nonce', 'epoch_wire',
    'intent_cid', 'intent_wire', 'accepted_at', 'phase', 'outcome_wire', 'revision'].sort();
  const custody = database.prepare('SELECT singleton, issued_count FROM client_submitted_intent_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(expected) || custody.length !== 1 ||
      custody[0].singleton !== 1 || !Number.isSafeInteger(custody[0].issued_count) ||
      custody[0].issued_count < 0) fail('UnknownClientRequestJournalFormat');
}

function inspectIntentRetirementStorage(database, enabled) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submitted_intent_retirement'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submitted_intent_retirement)')
    .all().map(field => field.name).sort();
  const rows = database.prepare('SELECT * FROM client_submitted_intent_retirement').all();
  if (JSON.stringify(fields) !== JSON.stringify(['retired_count', 'singleton']) ||
      rows.length !== 1 || rows[0].singleton !== 1 ||
      !Number.isSafeInteger(rows[0].retired_count) || rows[0].retired_count < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
}

function inspectRestartStorage(database, enabled) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submission_restarts', 'client_submission_restart_custody')`).all();
  if (!enabled && names.length === 0) return;
  if (!enabled || names.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_restarts)').all()
    .map(field => field.name).sort();
  const custodyFields = database.prepare('PRAGMA table_info(client_submission_restart_custody)').all()
    .map(field => field.name).sort();
  const custody = database.prepare('SELECT * FROM client_submission_restart_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(['fresh_submission_id', 'original_submission_id', 'link_wire'].sort()) ||
      JSON.stringify(custodyFields) !== JSON.stringify(['issued_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || custody[0].issued_count < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
}

function inspectNameStorage(database, enabled) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submission_names', 'client_submission_name_custody')`).all();
  if (!enabled && names.length === 0) return;
  if (!enabled || names.length !== 2) fail('UnknownClientRequestJournalFormat');
  for (const [name, sql] of nameTables) {
    if (database.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?")
      .get(name)?.sql !== sql) fail('UnknownClientRequestJournalFormat');
  }
  const fields = database.prepare('PRAGMA table_info(client_submission_names)').all()
    .map(field => field.name).sort();
  const counters = database.prepare('PRAGMA table_info(client_submission_name_custody)').all()
    .map(field => field.name).sort();
  const custody = database.prepare('SELECT * FROM client_submission_name_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(['namespace_id', 'actor_id', 'name',
    'authority_scope_cid', 'submission_id', 'intent_cid', 'binding_authenticator'].sort()) ||
      JSON.stringify(counters) !== JSON.stringify(['issued_count', 'retained_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || custody[0].issued_count < 0 ||
      !Number.isSafeInteger(custody[0].retained_count) || custody[0].retained_count < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
  for (const [name, sql] of nameTriggers) {
    if (database.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = ?")
      .get(name)?.sql !== sql) fail('UnknownClientRequestJournalFormat');
  }
  // Exact schema/triggers and the original singleton are checked here;
  // target resolution and mutation check retained vs issued custody. Ordinary
  // open does not recount unrelated historical name rows.
}

function inspectCancellationStorage(database, enabled) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_cancellation_operations', 'client_cancellation_custody')`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_cancellation_operations)')
    .all().map(field => field.name).sort();
  const custodyFields = database.prepare('PRAGMA table_info(client_cancellation_custody)')
    .all().map(field => field.name).sort();
  const indexed=database.prepare('PRAGMA user_version').get().user_version===2;
  const usage=indexed?database.prepare('SELECT * FROM client_cancellation_row_usage WHERE singleton=1').get():undefined;
  if(indexed && !validJournalRowUsage(usage)) fail('UnknownClientRequestJournalFormat');
  // A legacy database is counted once by the bounded adoption transaction,
  // not once in this copy and again in the original. Adopted metadata is O(1).
  const records = indexed ? usage.retained_count : undefined;
  const custody = database.prepare('SELECT singleton, issued_count FROM client_cancellation_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(cancellationColumns) ||
      JSON.stringify(custodyFields) !== JSON.stringify(['issued_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || custody[0].issued_count < 0 ||
      indexed && custody[0].issued_count !== records) fail('UnknownClientRequestJournalFormat');
}

function readJournalFormatFeatures(directory, entries) {
  const featurePath = join(directory, cancellationMarkerName);
  const enabled = entries.includes(cancellationMarkerName);
  if (enabled && (!lstatSync(featurePath).isFile() ||
      !journalMarkerMatches(featurePath, cancellationMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const submissionPath = join(directory, submissionMarkerName);
  const submissionEnabled = entries.includes(submissionMarkerName);
  if (submissionEnabled && (!lstatSync(submissionPath).isFile() ||
      !journalMarkerMatches(submissionPath, submissionMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const epochPath = join(directory, epochMarkerName);
  const epochEnabled = entries.includes(epochMarkerName);
  if (epochEnabled && (!lstatSync(epochPath).isFile() ||
      !journalMarkerMatches(epochPath, epochMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const intentPath = join(directory, intentMarkerName);
  const intentEnabled = entries.includes(intentMarkerName);
  if (intentEnabled && (!lstatSync(intentPath).isFile() ||
      !journalMarkerMatches(intentPath, intentMarker))) fail('UnknownClientRequestJournalFormat');
  const retirementPath = join(directory, retirementMarkerName);
  const retirementEnabled = entries.includes(retirementMarkerName);
  if (retirementEnabled && (!intentEnabled || !lstatSync(retirementPath).isFile() ||
      !journalMarkerMatches(retirementPath, retirementMarker))) fail('UnknownClientRequestJournalFormat');
  const restartPath = join(directory, restartMarkerName);
  const restartEnabled = entries.includes(restartMarkerName);
  if (restartEnabled && (!intentEnabled || !lstatSync(restartPath).isFile() ||
      !journalMarkerMatches(restartPath, restartMarker))) fail('UnknownClientRequestJournalFormat');
  const namePath = join(directory, nameMarkerName);
  const nameEnabled = entries.includes(nameMarkerName);
  if (nameEnabled && (!intentEnabled || !lstatSync(namePath).isFile() ||
      !journalMarkerMatches(namePath, nameMarker))) fail('UnknownClientRequestJournalFormat');
  const usagePath = join(directory, usageMarkerName);
  const usageEnabled = entries.includes(usageMarkerName);
  if (usageEnabled && (!intentEnabled || !retirementEnabled || !restartEnabled ||
      !lstatSync(usagePath).isFile())) {
    fail('UnknownClientRequestJournalFormat');
  }
  return Object.freeze({enabled, submissionEnabled, epochEnabled, intentEnabled,
    retirementEnabled, restartEnabled, nameEnabled, usageEnabled,
    featurePath, submissionPath, epochPath, intentPath, retirementPath, restartPath, namePath});
}

function inspectJournalNativeStorage(database, features) {
  const fields = database.prepare('PRAGMA table_info(client_requests)')
    .all().map(field => field.name).sort();
  if (JSON.stringify(fields) !== JSON.stringify(journalColumns)) {
    fail('UnknownClientRequestJournalFormat');
  }
  inspectCancellationStorage(database, features.enabled);
  inspectSubmissionStorage(database, features.submissionEnabled);
  inspectEpochStorage(database, features.epochEnabled);
  inspectIntentStorage(database, features.intentEnabled);
  inspectIntentRetirementStorage(database, features.retirementEnabled);
  inspectRestartStorage(database, features.restartEnabled);
  inspectNameStorage(database, features.nameEnabled);
  inspectSubmissionUsageStorage(database, features.usageEnabled);
  inspectClientSourceOperationStorage(database);
  inspectLocalExecutionOwnerStorage(database);
}

// Unowned/standalone inspection still needs an isolated snapshot: merely
// opening a read-only connection can create SHM beside an unclassified file.
function inspectJournalSnapshot(directory, databasePath, markerPath, maxInspectionEntries, maxInspectionBytes,
  primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent,
  primaryDirectoryInspection, inspectionTemporaryDirectory) {
  const entries = journalDirectoryEntries(directory, maxInspectionEntries, primaryDirectoryInspection);
  const features = readJournalFormatFeatures(directory, entries);
  const {enabled, submissionEnabled, epochEnabled, intentEnabled,
    retirementEnabled, restartEnabled, nameEnabled,
    featurePath, submissionPath, epochPath, intentPath, retirementPath, restartPath, namePath} = features;
  let inspectionSql;
  try {
  inspectSqliteSnapshot(databasePath, originalDatabase => {
    // The isolated primary-Journal inspection precedes the writable original.
    // Apply the same selected support conditions to its owned metadata reads;
    // no native All() vector may precede the bounded cursor path.
    if (primaryExecutionLimits !== undefined) {
      inspectionSql = boundedPrimarySql(originalDatabase, primarySqlLimits, primaryExecutionLimits, primaryCurrent);
    }
    const database = inspectionSql?.database ?? originalDatabase;
    inspectJournalNativeStorage(database, features);
  }, {code: 'UnknownClientRequestJournalFormat', maxSourceBytes: maxInspectionBytes,
    unavailableCode: 'ClientRequestJournalInspectionUnavailable',
    schemaReadLimits: primarySchemaLimits,
    schemaSqlSupport: primarySchemaSqlSupport,
    assertCurrent: primaryCurrent,
    temporaryDirectory: inspectionTemporaryDirectory,
    validateSource: () => journalMarkerMatches(markerPath, journalMarker) &&
      (!enabled || journalMarkerMatches(featurePath, cancellationMarker)) &&
      (!submissionEnabled || journalMarkerMatches(submissionPath, submissionMarker)) &&
      (!epochEnabled || journalMarkerMatches(epochPath, epochMarker)) &&
      (!intentEnabled || journalMarkerMatches(intentPath, intentMarker)) &&
      (!retirementEnabled || journalMarkerMatches(retirementPath, retirementMarker)) &&
      (!restartEnabled || journalMarkerMatches(restartPath, restartMarker)) &&
      (!nameEnabled || journalMarkerMatches(namePath, nameMarker)) &&
      JSON.stringify(journalDirectoryEntries(directory, maxInspectionEntries, primaryDirectoryInspection)) === JSON.stringify(entries)});
  } catch (error) {
    if (inspectionSql !== undefined) {
      const handleField = error !== null && typeof error === 'object'
        ? Object.getOwnPropertyDescriptor(error, 'cleanupHandle') : undefined;
      const handle = handleField !== undefined && Object.hasOwn(handleField, 'value')
        ? handleField.value : undefined;
      if (handle === undefined) {
        // inspectSqliteSnapshot forwards a primary error without a carrier
        // only after its actual database/FD/copy cleanup has completed.
        inspectionSql.retireClosedNativeAliases();
      } else {
        const status = Object.getOwnPropertyDescriptor(handle, 'status')?.value;
        const retry = Object.getOwnPropertyDescriptor(handle, 'retry')?.value;
        const observe = value => {
          const pending = value !== null && typeof value === 'object'
            ? Object.getOwnPropertyDescriptor(value, 'pending') : undefined;
          if (pending !== undefined && Object.hasOwn(pending, 'value') && pending.value === false) {
            inspectionSql.retireClosedNativeAliases();
          }
          return value;
        };
        // Retain this same selected statement/cursor custody beside the
        // original copy/FD cleanup. No replacement close or synthetic ACK.
        error.cleanupHandle = Object.freeze({
          status: () => observe(applyOriginal(status, handle, [])),
          retry: () => observe(applyOriginal(retry, handle, [])),
        });
      }
    }
    throw error;
  }
  inspectionSql?.retireClosedNativeAliases();
}

function admitJournalDirectory(directory, maxInspectionEntries, maxInspectionBytes,
  primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent,
  primaryDirectoryInspection, inspectionTemporaryDirectory, ownedOriginal) {
  if (!existsSync(directory)) return false;
  const state = lstatSync(directory);
  if (!state.isDirectory() || state.isSymbolicLink()) {
    fail('UnknownClientRequestJournalFormat');
  }
  const entries = journalDirectoryEntries(directory, maxInspectionEntries, primaryDirectoryInspection);
  if (entries.length === 0) return false;
  const markerPath = join(directory, 'journal-format.json');
  if (!entries.includes('journal-format.json')) {
    fail(entries.includes('client-requests.sqlite3') ?
      'LegacyClientRequestJournalFormat' :
      'UnknownClientRequestJournalFormat');
  }
  if (!entries.includes('client-requests.sqlite3') ||
      !lstatSync(markerPath).isFile() ||
      !journalMarkerMatches(markerPath, journalMarker)) {
    fail('UnknownClientRequestJournalFormat');
  }
  const databasePath = join(directory, 'client-requests.sqlite3');
  if (!lstatSync(databasePath).isFile()) {
    fail('UnknownClientRequestJournalFormat');
  }
  if (ownedOriginal !== undefined) {
    assertOriginalPreparedLocalPublicationStoreOwnership(ownedOriginal,
      join(dirname(resolve(directory)), 'publication'));
    if (existsSync(`${databasePath}-journal`)) fail('UnknownClientRequestJournalFormat');
    let bytes = 0n;
    for (const path of [databasePath, `${databasePath}-wal`, `${databasePath}-shm`]) {
      if (!existsSync(path)) continue;
      const original = lstatSync(path, {bigint: true});
      if (!original.isFile() || original.isSymbolicLink()) fail('UnknownClientRequestJournalFormat');
      if (path.endsWith('-shm')) continue;
      bytes += original.size;
      if (bytes > BigInt(maxInspectionBytes)) fail('ClientRequestJournalInspectionUnavailable');
    }
    return readJournalFormatFeatures(directory, entries);
  }
  try {
    inspectJournalSnapshot(directory, databasePath, markerPath, maxInspectionEntries, maxInspectionBytes,
      primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent,
      primaryDirectoryInspection, inspectionTemporaryDirectory);
  } catch (cause) {
    if (cause?.cleanupPending) throw cause;
    if (['HostJournalDirectoryUnavailable', 'HostJournalDirectoryCurrentUnavailable',
      'HostJournalDirectoryBoundsUnavailable', 'HostJournalDirectoryReadUnavailable',
      'HostJournalDirectoryRecordUnavailable'].includes(cause?.code)) throw cause;
    if (cause?.code === 'ClientRequestJournalInspectionUnavailable') throw cause;
    if (cause?.code === 'ClientRequestJournalSqlUnavailable' ||
        cause?.code === 'ClientRequestJournalSqlCleanupPending') throw cause;
    if (cause?.code === 'SqliteSchemaPreparationUnavailable') throw cause;
    if (cause?.code === 'UnknownClientRequestJournalFormat') throw cause;
    fail('UnknownClientRequestJournalFormat', cause);
  }
  return true;
}

export function openClientRequestJournal(directory, {
  maxRecords = 100_000,
  maxInspectionEntries = 100_000,
  maxInspectionBytes = 64 * 1024 * 1024,
  maxDatabaseBytes,
  maxWalFrames,
  primarySqlLimits,
  primaryExecutionLimits,
  primarySchemaLimits,
  primarySchemaSqlSupport,
  primaryCurrent,
  primaryDirectoryInspection,
  inspectionTemporaryDirectory,
  maxRunDefinitionWireBytes = 65_536,
  submissionEpochTtlMs = maxEpochTtlMs,
  submissionEpochNow = Date.now,
  updateOriginalControl,
  sourceOperationLimits,
} = {}, ownedOriginal) {
  if (ownedOriginal !== undefined) {
    if (!pathText(directory) || basename(resolve(directory)) !== 'requests') {
      fail('InvalidClientRequestJournalConfiguration');
    }
    assertOriginalPreparedLocalPublicationStoreOwnership(ownedOriginal,
      join(dirname(resolve(directory)), 'publication'));
  }
  if (!pathText(directory) || !Number.isSafeInteger(maxRecords) ||
      !Number.isSafeInteger(maxInspectionEntries) || maxInspectionEntries < 1 ||
      !Number.isSafeInteger(maxInspectionBytes) || maxInspectionBytes < 1 ||
      maxDatabaseBytes !== undefined &&
        (!Number.isSafeInteger(maxDatabaseBytes) || maxDatabaseBytes < 1) ||
      maxWalFrames !== undefined &&
        (!Number.isSafeInteger(maxWalFrames) || maxWalFrames < 1) ||
      maxRecords < 1 || !Number.isSafeInteger(maxRunDefinitionWireBytes) ||
      maxRunDefinitionWireBytes < 1024 ||
      !Number.isSafeInteger(submissionEpochTtlMs) || submissionEpochTtlMs < 1 ||
      submissionEpochTtlMs > maxEpochTtlMs || typeof submissionEpochNow !== 'function') {
    fail('InvalidClientRequestJournalConfiguration');
  }
  sourceOperationLimits = snapshotClientSourceOperationLimits(sourceOperationLimits);
  if (primaryCurrent !== undefined && typeof primaryCurrent !== 'function') {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (inspectionTemporaryDirectory !== undefined &&
      (typeof inspectionTemporaryDirectory !== 'string' ||
        inspectionTemporaryDirectory.length === 0 || inspectionTemporaryDirectory.length > 4096 ||
        !isAbsolute(inspectionTemporaryDirectory) || inspectionTemporaryDirectory.includes('\0'))) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (primaryDirectoryInspection !== undefined) {
    // Validate the same private view and exact selected bound BEFORE any
    // directory/format/native acquisition. No fallback on selected refusal.
    assertHostJournalDirectoryInspector(primaryDirectoryInspection, maxInspectionEntries);
  }
  primarySqlLimits = snapshotPrimarySqlLimits(primarySqlLimits);
  primaryExecutionLimits = snapshotPrimaryExecutionLimits(primaryExecutionLimits);
  primarySchemaLimits = snapshotSqliteSchemaReadLimits(primarySchemaLimits);
  primarySchemaSqlSupport = snapshotSqliteSchemaSqlSupport(primarySchemaSqlSupport, primarySchemaLimits);
  if (primaryExecutionLimits !== undefined &&
      (primarySqlLimits === undefined || maxDatabaseBytes === undefined)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (primarySchemaLimits !== undefined && maxDatabaseBytes === undefined) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (maxWalFrames !== undefined && (maxDatabaseBytes === undefined ||
      primarySqlLimits === undefined || primaryExecutionLimits === undefined)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  // An optional selected-facility support bound is not a format rule or a
  // capacity issuer. Refuse original DB/WAL extent before its copy/SQLite
  // inspection, not after materializing rows. Unselected callers are unchanged.
  const inspectionBytes = maxDatabaseBytes === undefined ? maxInspectionBytes :
    Math.min(maxInspectionBytes, maxDatabaseBytes);
  const walFrames = boundedJournalWalFrames(maxWalFrames, inspectionBytes, maxDatabaseBytes);
  // Only the actual selected Root supplies this captured current fence. It
  // does not issue capacity; execute it before the first original directory,
  // copy or native acquisition, and again at each covered SQL boundary.
  primaryCurrent?.();
  if (primaryCurrent !== undefined && typeof facilityNativeRealpath !== 'function') {
    fail('ClientRequestJournalFacilityUnavailable');
  }
  const directoryAdmission = admitJournalDirectory(directory, maxInspectionEntries, inspectionBytes,
    primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent,
    primaryDirectoryInspection, inspectionTemporaryDirectory, ownedOriginal);
  const current = directoryAdmission !== false;
  mkdirSync(directory, {recursive: true, mode: 0o700});
  // Avoid the stock JS symlink walk's intermediate path/Map/Set history in
  // the selected recipe. Native libc/libuv path holdings remain distinct
  // terms of that recipe; selecting this original does not supply them.
  const root = primaryCurrent === undefined ? realpathSync(directory) :
    applyOriginal(facilityNativeRealpath, facilityRealpath, [directory, nativePathOptions]);
  const path = join(root, 'client-requests.sqlite3');
  const existed = existsSync(path);
  if (current !== existed) fail('UnknownClientRequestJournalFormat');
  // A fresh initialization is unpublished until its final directory ACK.
  // Existing-database format upgrades keep their original immediate ACKs.
  const syncFormatDirectory = () => {if (existed) syncDirectory(root);};
  primaryCurrent?.();
  // Native option lookup includes inherited properties. The selected facility
  // must not acquire arbitrary callbacks or configurations from that prototype.
  // This closed internal packet is not an operational admission.
  const connection = new DatabaseSync(path, primaryCurrent === undefined ? {
    // Retain the actual wrapper before native open can acquire a connection
    // and then fail. Cleanup must not depend on an unreachable constructor
    // result or on eventual garbage collection of that native connection.
    open: false,
    readOnly: false,
    enableForeignKeyConstraints: true,
  } : {__proto__: null, open: false, readOnly: false, enableForeignKeyConstraints: true});
  let database = connection;
  let selectedSql;
  let originalDatabaseClose, originalDatabaseIsOpen;
  const captureDatabaseCleanup = () => {
    originalDatabaseClose ??= connection.close;
    originalDatabaseIsOpen ??= Object.getOwnPropertyDescriptor(
      connection, 'isOpen')?.get;
    if (typeof originalDatabaseClose !== 'function' ||
        typeof originalDatabaseIsOpen !== 'function') {
      throw new TypeError('ClientRequestJournalConnectionCleanupUnavailable');
    }
  };
  const initializationCleanup = {close() {
    captureDatabaseCleanup();
    const opened = applyOriginal(originalDatabaseIsOpen, connection, []);
    if (typeof opened !== 'boolean') {
      throw new TypeError('ClientRequestJournalConnectionCleanupPending');
    }
    if (opened && (applyOriginal(originalDatabaseClose, connection, []) !== undefined ||
        applyOriginal(originalDatabaseIsOpen, connection, []) !== false)) {
      throw new TypeError('ClientRequestJournalConnectionCleanupPending');
    }
    selectedSql?.retireClosedNativeAliases();
  }};
  let transaction;
  let closed = false;
  let databaseClosed = false;
  try {
    captureDatabaseCleanup();
    if (primarySqlLimits !== undefined) {
      selectedSql = boundedPrimarySql(connection, primarySqlLimits, primaryExecutionLimits, primaryCurrent, walFrames);
      database = selectedSql.database;
    }
    transaction = createSqliteTransaction(database, 'ClientRequestJournal');
    primaryCurrent?.();
    const originalOpen = connection.open;
    if (typeof originalOpen !== 'function' ||
        applyOriginal(originalOpen, connection, []) !== undefined ||
        applyOriginal(originalDatabaseIsOpen, connection, []) !== true) {
      throw new TypeError('ClientRequestJournalConnectionOpenUnavailable');
    }
    let temporarySelected = false;
    let retainedGeometry;
    if (ownedOriginal !== undefined && current) {
      assertOriginalPreparedLocalPublicationStoreOwnership(ownedOriginal,
        join(dirname(resolve(directory)), 'publication'));
      if (maxDatabaseBytes !== undefined) {
        retainedGeometry = journalDatabaseGeometry(database, maxDatabaseBytes, walFrames);
      }
      selectJournalTemporaryStorage(database, primaryExecutionLimits);
      selectedSql?.prepareWalCheckpoint();
      temporarySelected = true;
      // SQLite is the format authority for this already-owned database.
      // Bound only schema metadata here; do not materialize historical rows.
      const schema = database.prepare(`SELECT COUNT(*) AS entries,
        COALESCE(SUM(length(CAST(sql AS BLOB))),0) AS bytes FROM sqlite_master`).get();
      const schemaLimits = primarySchemaLimits ?? {
        maxSchemaEntries: maxInspectionEntries, maxSchemaBytes: inspectionBytes};
      if (!Number.isSafeInteger(schema?.entries) || schema.entries < 1 ||
          schema.entries > schemaLimits.maxSchemaEntries ||
          !Number.isSafeInteger(schema?.bytes) || schema.bytes < 0 ||
          schema.bytes > schemaLimits.maxSchemaBytes) {
        fail('SqliteSchemaPreparationUnavailable');
      }
      if (primarySchemaSqlSupport !== undefined) {
        const statements = database.prepare('SELECT sql FROM sqlite_master WHERE sql IS NOT NULL').all();
        if (statements.some(row => !primarySchemaSqlSupport.includes(row.sql))) {
          fail('SqliteSchemaPreparationUnavailable');
        }
      }
      inspectJournalNativeStorage(database, directoryAdmission);
    }
    boundJournalDatabaseExtent(database, maxDatabaseBytes, primaryExecutionLimits, walFrames,
      temporarySelected, retainedGeometry, selectedSql?.prepareWalCheckpoint);
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
    // Fresh schema is one unpublished FULL transaction. Reuse these same DDL
    // statements for retained older formats; only those upgrades acknowledge
    // their separate durable feature transitions as before.
    const pendingFormatMarkers=[];
    const writeFormatMarker=(name,bytes)=>{
      const marker=openSync(join(root,name),'wx',0o600);
      try {writeFileSync(marker,bytes);fsyncSync(marker);}
      finally {closeSync(marker);}
      syncFormatDirectory();
    };
    const publishFormatMarker=(name,bytes)=>{
      if (existed) writeFormatMarker(name,bytes);
      else pendingFormatMarkers.push([name,bytes]);
    };
    const initializeFeature=action=>existed ? transaction.run(action) : action();
    const initializeSchema=()=>{
    database.exec(`
      CREATE TABLE IF NOT EXISTS client_requests (
        authority_scope_cid TEXT NOT NULL,
        caller_request_id TEXT NOT NULL,
        logical_request_scope_cid TEXT NOT NULL UNIQUE,
        intent_fingerprint_cid TEXT NOT NULL,
        program_definition_cid TEXT NOT NULL,
        parameter_values_cid TEXT NOT NULL,
        caller_input_intent_cid TEXT NOT NULL,
        namespace_id TEXT NOT NULL,
        run_definition_cid TEXT NOT NULL UNIQUE,
        run_definition_wire TEXT,
        run_admission_evidence_json TEXT,
        revision INTEGER NOT NULL CHECK (revision >= 0),
        state_revision INTEGER NOT NULL DEFAULT 0
          CHECK (state_revision >= 0 AND state_revision <= 9007199254740991),
        state_observation_key TEXT,
        lookup_expires_at TEXT NOT NULL,
        result_names_json TEXT,
        dispatch_reserved INTEGER NOT NULL DEFAULT 0
          CHECK (dispatch_reserved IN (0, 1)),
        pre_dispatch_failure_confirmed INTEGER NOT NULL DEFAULT 0
          CHECK (pre_dispatch_failure_confirmed IN (0, 1)),
        physical_start_reserved INTEGER NOT NULL DEFAULT 0
          CHECK (physical_start_reserved IN (0, 1)),
        cancellation_requested INTEGER NOT NULL DEFAULT 0
          CHECK (cancellation_requested IN (0, 1)),
        physical_close_confirmed INTEGER NOT NULL DEFAULT 0
          CHECK (physical_close_confirmed IN (0, 1)),
        observed_terminal_outcome TEXT
          CHECK (observed_terminal_outcome IN ('failed', 'cancelled')),
        reconciliation_state_wire TEXT,
        PRIMARY KEY (authority_scope_cid, caller_request_id)
      ) STRICT;
    `);
    if (!existed) publishFormatMarker('journal-format.json',journalMarker);
    if (!existsSync(join(root, submissionMarkerName))) {
      // Adopt only the retained original rows of an admitted prior format.
      // This cannot certify missing pre-upgrade history or issue an epoch.
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submission_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submission_custody
          SELECT 1, COUNT(*) FROM client_requests;
      `));
      publishFormatMarker(submissionMarkerName,submissionMarker);
    }
    if (!existsSync(join(root, epochMarkerName))) {
      // One retained authentication key and monotonic expiry watermark suffice
      // to validate bounded-lifetime tickets. No per-epoch history is evicted.
      initializeFeature(() => {
        database.exec(`CREATE TABLE client_submission_epoch_authority (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          authentication_key TEXT NOT NULL,
          observed_at INTEGER NOT NULL CHECK (observed_at >= 0)
        ) STRICT;`);
        database.prepare('INSERT INTO client_submission_epoch_authority VALUES (1, ?, 0)')
          .run(randomBytes(32).toString('hex'));
      });
      publishFormatMarker(epochMarkerName,epochMarker);
    }
    if (!existsSync(join(root, intentMarkerName))) {
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submitted_intents (
          submission_id TEXT PRIMARY KEY,
          authority_scope_cid TEXT NOT NULL,
          nonce TEXT NOT NULL,
          epoch_wire TEXT NOT NULL,
          intent_cid TEXT NOT NULL,
          intent_wire TEXT NOT NULL,
          accepted_at INTEGER NOT NULL,
          phase TEXT NOT NULL CHECK (phase IN ('preparing', 'not_accepted', 'preparation_failed', 'ready', 'held')),
          outcome_wire TEXT,
          revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0)
        ) STRICT;
        CREATE TABLE client_submitted_intent_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submitted_intent_custody VALUES (1, 0);
      `));
      publishFormatMarker(intentMarkerName,intentMarker);
    }
    if (!existsSync(join(root, retirementMarkerName))) {
      // Adoption records zero formal retirements; it never resets issuance
      // or repairs a missing original row in a previously admitted journal.
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submitted_intent_retirement (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          retired_count INTEGER NOT NULL CHECK (retired_count >= 0)
        ) STRICT;
        INSERT INTO client_submitted_intent_retirement VALUES (1, 0);
      `));
      publishFormatMarker(retirementMarkerName,retirementMarker);
    }
    if (!existsSync(join(root, restartMarkerName))) {
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submission_restarts (
          fresh_submission_id TEXT PRIMARY KEY,
          original_submission_id TEXT NOT NULL,
          link_wire TEXT NOT NULL
        ) STRICT;
        CREATE TABLE client_submission_restart_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submission_restart_custody VALUES (1, 0);
      `));
      publishFormatMarker(restartMarkerName,restartMarker);
    }
    if (!existsSync(join(root, cancellationMarkerName))) {
      initializeFeature(() => database.exec(`
        CREATE TABLE client_cancellation_operations (
          namespace_id TEXT NOT NULL,
          authority_scope_cid TEXT NOT NULL,
          cancel_id TEXT NOT NULL,
          run_definition_cid TEXT NOT NULL REFERENCES client_requests(run_definition_cid),
          expected_revision INTEGER NOT NULL CHECK (expected_revision >= 0),
          intent_fingerprint_cid TEXT NOT NULL,
          outcome_wire TEXT,
          outcome_cid TEXT,
          CHECK ((outcome_wire IS NULL) = (outcome_cid IS NULL)),
          PRIMARY KEY (namespace_id, authority_scope_cid, cancel_id)
        ) STRICT;
        CREATE TABLE client_cancellation_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_cancellation_custody VALUES (1, 0);
      `));
      publishFormatMarker(cancellationMarkerName,cancellationMarker);
    }
    if (!existsSync(join(root, nameMarkerName))) {
      // Old nonces are not names. This empty additive index never adopts or
      // searches their history. Once issued, a name is not evicted or reused.
      initializeFeature(() => database.exec(`
        ${nameTables.map(([, sql]) => `${sql};`).join('\n')}
        INSERT INTO client_submission_name_custody VALUES (1, 0, 0);
        ${nameTriggers.map(([, sql]) => `${sql};`).join('\n')}
      `));
      publishFormatMarker(nameMarkerName,nameMarker);
    }
    if (database.prepare('PRAGMA user_version').get().user_version < 2) {
      adoptSubmissionUsageStorage(database,initializeFeature,existsSync(join(root,usageMarkerName)),!existed);
    }
    // This optional original-operation storage belongs to this same Journal.
    // Legacy absence grants no new dispatch: live scope issuance additionally
    // requires the existing confirmed first physical-start transaction.
    inspectClientSourceOperationStorage(database);
    if (sourceOperationLimits !== undefined && database.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'client_source_operation_originals'").get() === undefined) {
      initializeFeature(() => database.exec(sourceOperationTable));
    }
    const keyedSchema = database.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'client_keyed_lookup_originals'").get();
    if (keyedSchema !== undefined && keyedSchema.sql !== keyedLookupOriginalTable) {
      fail('UnknownClientRequestJournalFormat');
    }
    if (keyedSchema === undefined) initializeFeature(() => database.exec(keyedLookupOriginalTable));
    inspectLocalExecutionOwnerStorage(database);
    if (ownedOriginal !== undefined && database.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'client_local_execution_owners'").get() === undefined) {
      initializeFeature(() => database.exec(localExecutionOwnerTable));
    }
    };
    if (existed) initializeSchema();
    else {
      transaction.run(initializeSchema);
      // No format marker claims an uncommitted current schema. Each original
      // file keeps its fsync; the existing final directory ACK precedes ready.
      for (const [name,bytes] of pendingFormatMarkers) writeFormatMarker(name,bytes);
    }
  // Statement preparation is part of initialization: no journal owner has
  // been returned yet. Keep it under the same single cleanup boundary.
  const ensureOpen = () => {
    if (closed) fail('ClientRequestJournalClosed');
    primaryCurrent?.();
    transaction.assertUsable();
  };
  // Only an explicit semantic rejection from this Owner, followed by a
  // confirmed rollback of initial admission, can certify this invocation.
  // An error code copied from another operation carries no such custody.
  const cancellationRejectionCandidates = new WeakMap();
  const cancellationRejections = new WeakMap();
  const submissionRejectionCandidates = new WeakMap();
  const submissionRejections = new WeakMap();
  let activeSubmissionAttempt;
  const rejectSubmission = (code, kind, reason) => {
    const error = Object.assign(new Error(code), {code});
    submissionRejectionCandidates.set(error, Object.freeze({kind, reason,
      ticket: activeSubmissionAttempt}));
    throw error;
  };
  const submissionTransaction = action => {
    try {return transaction.run(action);}
    catch (error) {
      const rejection = submissionRejectionCandidates.get(error);
      if (rejection !== undefined && rejection.ticket === activeSubmissionAttempt &&
          error.outcome !== 'unknown' && transaction.connectionUsable) {
        // transaction.run returns the original semantic error only after a
        // successful rollback. Commit and rollback failures wrap that error.
        submissionRejections.set(error, rejection);
      }
      throw error;
    }
  };
  const submissionAttempt = (submissionRef, intent, options, control, action, kind) => {
    ensureOpen();
    const attemptRef = options.attemptRef;
    if (!validSubmissionRef(submissionRef) || attemptRef === null ||
        typeof attemptRef !== 'object' ||
        Object.keys(attemptRef).sort().join(',') !== 'attemptId,operation' ||
        attemptRef.operation !== 'submit' || !text(attemptRef.attemptId) ||
        !attemptRef.attemptId.isWellFormed() || typeof options.currentAuthorization !== 'boolean') {
      fail('InvalidClientSubmissionAttempt');
    }
    const ownedAttempt = Object.freeze({operation: 'submit', attemptId: attemptRef.attemptId});
    if (!options.currentAuthorization) return Object.freeze({kind: 'refused',
      attemptRef: ownedAttempt, guarantee: 'attempt_uncommitted_unconsumed', reason: 'authorization'});
    const original = originalIntent(intent, control, submissionRef.epoch);
    const ownedRef = Object.freeze({...submissionRef, epoch: Object.freeze({...submissionRef.epoch})});
    const ticket = {}, previous = activeSubmissionAttempt;
    activeSubmissionAttempt = ticket;
    try {
      const result = action();
      return Object.freeze({kind, attemptRef: ownedAttempt,
        ...(kind === 'checked' ? {requestId: result.requestId} : {submission: result})});
    } catch (error) {
      const rejection = submissionRejections.get(error);
      if (rejection === undefined || rejection.ticket !== ticket) throw error;
      return Object.freeze({kind: rejection.kind, reason: rejection.reason, attemptRef: ownedAttempt,
        submissionRef: ownedRef, intentCid: original.identity,
        ...(rejection.kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed'} : {})});
    } finally {activeSubmissionAttempt = previous;}
  };
  const rejectSubmissionEpoch = validity => {
    const reason = validity === 'expired' ? 'epoch_expired' : 'epoch_not_yet_valid';
    const code = validity === 'expired' ? 'ClientSubmissionEpochExpired' : 'ClientSubmissionEpochNotYetValid';
    const error = Object.assign(new Error(code), {code});
    // This decision follows a successful transaction which confirmed that
    // this fresh identity has no retained receipt. The clock observation is
    // durable, but no intent custody was consumed by this invocation.
    submissionRejections.set(error, Object.freeze({kind: 'refused', reason,
      ticket: activeSubmissionAttempt}));
    throw error;
  };
  let activeCancellationAttempt;
  const rejectCancellation = (code, kind, reason) => {
    const error = Object.assign(new Error(code), {code});
    cancellationRejectionCandidates.set(error, Object.freeze({kind, reason,
      ticket: activeCancellationAttempt}));
    throw error;
  };
  const transact = (operation, unknownCode, known, action) => {
    try { return transaction.run(action); }
    catch (error) {
      const transactionFailure = [
        'ClientRequestJournalCommitOutcomeUnknown',
        'ClientRequestJournalRollbackFailed',
        'ClientRequestJournalConnectionUnusable',
      ].includes(error?.code);
      if (!transactionFailure && known(error) &&
          error.outcome !== 'unknown' &&
          transaction.connectionUsable) {
        const rejection = cancellationRejectionCandidates.get(error);
        if (operation === 'cancel_admission' && rejection !== undefined &&
            rejection.ticket === activeCancellationAttempt) {
          cancellationRejections.set(error, rejection);
        }
        throw error;
      }
      throw Object.assign(new Error(unknownCode, {
        cause: error.cause ?? error,
      }), {
        code: unknownCode, operation,
        outcome: error.outcome ?? 'failed',
        rollbackCause: error.rollbackCause,
        stateCause: error.stateCause,
        connectionUsable: transaction.connectionUsable,
      });
    }
  };
  let observationProjection;
  // Count only rows actually returned by these selected native reads. This
  // neither visits other Runs nor measures SQLite's internal page traversal.
  // The existing observation context aggregates scalars without per-get I/O.
  const selectedRequestStatement = (statement, selection, completeRef = false,
    completeRow = false) => {
    const get = statement.get;
    return Object.freeze({get(...parameters) {
      const row = applyOriginal(get, statement, parameters);
      if (observationProjection !== undefined) {
        try {
          const ref = completeRef ? {namespaceId: parameters[0],
            authorityScopeCid: parameters[1], runDefinitionCid: parameters[2]} : undefined;
          observationProjection.diagnostic('selected_rows_observed', {
            ref, rowOwner: 'request-journal', selection, rowKind: 'run',
            returnedRows: row === undefined ? 0 : 1,
            ...(selection === 'request' ? {requestSelection: {
              authorityScopeCid: parameters[0], requestId: parameters[1]},
            ...(row === undefined ? {} : {selectedRowRef: {namespaceId: row.namespace_id,
              authorityScopeCid: row.authority_scope_cid, runDefinitionCid: row.run_definition_cid}})} :
              !completeRef ? {runSelectionCid: parameters[0]} : {}),
            // Partial projections and pre-Run request keys cannot classify a
            // complete returned Run identity. Absence here means unknown.
            unrelatedRows: !completeRow ? undefined : row === undefined ? 0 :
              Number(row.namespace_id !== ref.namespaceId ||
                row.authority_scope_cid !== ref.authorityScopeCid ||
                row.run_definition_cid !== ref.runDefinitionCid),
            coverage: 'selected-returned',
          });
        } catch { /* Optional diagnostics never replace a native result. */ }
      }
      return row;
    }});
  };
  const select = selectedRequestStatement(database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE authority_scope_cid = ? AND caller_request_id = ?`), 'request');
  const selectRef = selectedRequestStatement(database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ?`), 'run-definition', true, true);
  // Prepare each keyed statement only when this Journal first needs it.
  // Retain that same original for its connection lifetime, not per key.
  let keyedLookupPrior, keyedLookupBatch, keyedLookupInsert, keyedLookupAdopt;
  const sourceOperations = clientSourceOperationStorage(database, {ensureOpen,
    transact, limits: sourceOperationLimits,
    readRun: ref => selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid)});
  // The FK and unique Run key bound this table by the existing admitted
  // request rows. SQL substr bounds materialization of corrupt old records.
  const localExecutionOwnerInsert = ownedOriginal === undefined ? undefined : database.prepare(`
    INSERT INTO client_local_execution_owners VALUES (?, ?, ?, ?, ?, ?, ?)`);
  const localExecutionOwnerLookup = ownedOriginal === undefined ? undefined : database.prepare(`
    SELECT substr(owner_token, 1, 37) AS owner_token,
      substr(anchor_identity, 1, 37) AS anchor_identity,
      substr(anchor_device, 1, 33) AS anchor_device,
      substr(anchor_inode, 1, 33) AS anchor_inode
    FROM client_local_execution_owners
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`);
  const readRunDefinitionRow = (ref, requestControl) => {
    ensureOpen();
    if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
        !cid(ref?.runDefinitionCid) ||
        typeof requestControl?.clientRequestAdmitRecord !== 'function') {
      fail('InvalidClientRunLookup');
    }
    try {
      return selectRef.get(ref.namespaceId, ref.authorityScopeCid,
        ref.runDefinitionCid);
    } catch (error) { fail('ClientRequestLookupUnknown', error); }
  };
  // These observation frames belong to this exact journal instance. They are
  // not authority and cannot be reconstituted from a copied DATA response.
  const runStateFrames = new WeakMap();
  const retainRunStateFrame = (frame, selected) => {
    const original=runStateFrames.get(frame);
    if(original===undefined || original.row.namespace_id!==selected?.namespaceId ||
        original.row.authority_scope_cid!==selected?.authorityScopeCid ||
        original.row.run_definition_cid!==selected?.runDefinitionCid) {
      fail('ForeignRunStateObservation');
    }
    return original;
  };
  const sameRunStateRow = (row, original) => row!==undefined &&
    Object.keys(row).length===Object.keys(original).length &&
    Object.keys(row).every(key=>row[key]===original[key]);
  const admitRunDefinitionRow = (row, requestControl, publicationControl) => {
    const retained = retainedIdentity(row, requestControl);
    if (requestControl.clientRequestScopeCid(retained) !== row.logical_request_scope_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    const accepted = admission(row);
    const facts = Object.freeze({
      ref: accepted.ref, durability: accepted.durability,
      revision: accepted.revision, requestId: row.caller_request_id,
      ...retainedRunFacts(row, publicationControl, maxRunDefinitionWireBytes, updateOriginalControl),
    });
    runStateFrames.set(facts, Object.freeze({row: Object.freeze({...row}),
      requestControl, publicationControl}));
    return facts;
  };
  const selectRun = selectedRequestStatement(database.prepare(`SELECT run_definition_cid
    FROM client_requests WHERE run_definition_cid = ?`), 'run-definition');
  const requestUsage = database.prepare('SELECT * FROM client_request_row_usage WHERE singleton=1');
  const submissionIssued = database.prepare('SELECT issued_count FROM client_submission_custody WHERE singleton = 1');
  const advanceSubmissionCustody = database.prepare('UPDATE client_submission_custody SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?');
  const assertSubmissionCustody = () => {
    const usage=requestUsage.get(), n=usage?.retained_count;
    if (!validJournalRowUsage(usage) || submissionIssued.get()?.issued_count !== n) {
      fail('ClientRequestSubmissionCustodyLost');
    }
    return n;
  };
  const epochAuthority = database.prepare('SELECT * FROM client_submission_epoch_authority WHERE singleton = 1');
  const advanceEpochTime = database.prepare('UPDATE client_submission_epoch_authority SET observed_at = ? WHERE singleton = 1');
  const submissionOperations = new WeakMap();
  const epochClock = (operation, persist = true) => {
    const row = epochAuthority.get();
    if (!validEpochAuthority(row)) fail('ClientSubmissionEpochCustodyLost');
    const now = submissionEpochNow();
    if (!Number.isSafeInteger(now) || now < 0 ||
        now > Number.MAX_SAFE_INTEGER - maxEpochTtlMs) fail('ClientSubmissionEpochClockInvalid');
    const observedAt = Math.max(now, row.observed_at, operation?.floor ?? 0);
    let floor = observedAt;
    if (operation !== undefined) {
      const boundary = observedAt < operation.epoch.notBefore ? 'early' :
        observedAt >= operation.epoch.expiresAt ? 'expired' : 'admissible';
      // One durable floor belongs to this public operation, not each private
      // getter. A newly observed interval boundary still has its own durable
      // consequence. The retained row, never this memo, establishes its ACK.
      if (operation.boundary !== boundary) {
        operation.floor = Math.max(operation.floor ?? 0, observedAt);
        operation.boundary = boundary;
      }
      floor = operation.floor;
    }
    const needsWrite = floor > row.observed_at;
    if (persist && needsWrite) advanceEpochTime.run(floor);
    return {...row, observed_at: observedAt, needsWrite};
  };
  const epochHandle = (epoch, control) => {
    const operation = submissionOperations.get(epoch);
    if (operation?.control === control && operation.original !== undefined) return operation.original;
    if (epoch === null || typeof epoch !== 'object' || Array.isArray(epoch) ||
        JSON.stringify(Object.keys(epoch).sort()) !== JSON.stringify([
          'authenticator', 'authorityScopeCid', 'epochNonce', 'expiresAt', 'notBefore', 'version',
        ])) fail('ClientSubmissionEpochUnverifiable');
    const captured = operation?.control === control ? epoch : Object.freeze({...epoch});
    if (captured.version !== 'actql-submission-epoch/0.1' ||
        !cid(captured.authorityScopeCid) || !hexKey(captured.epochNonce) ||
        !Number.isSafeInteger(captured.notBefore) || !Number.isSafeInteger(captured.expiresAt) ||
        Object.is(captured.notBefore, -0) || Object.is(captured.expiresAt, -0) ||
        !hexKey(captured.authenticator)) fail('ClientSubmissionEpochUnverifiable');
    const handle = control.clientSubmissionEpoch(captured.authorityScopeCid,
      captured.epochNonce, captured.notBefore, captured.expiresAt);
    if (handle === undefined) fail('ClientSubmissionEpochUnverifiable');
    const original = {captured, handle};
    if (operation?.control === control) operation.original = original;
    return original;
  };
  const authenticateEpoch = (key, wire) => createHmac('sha256',
    Buffer.from(key, 'hex')).update(wire, 'utf8').digest('hex');
  const authenticateOriginalEpoch = (epoch, control, authority, code) => {
    const original = epochHandle(epoch, control);
    const operation = submissionOperations.get(epoch);
    if (operation?.control !== control || operation.authenticationKey !== authority.authentication_key) {
      const authenticated = authenticateEpoch(authority.authentication_key,
        control.clientSubmissionEpochWire(original.handle));
      if (!timingSafeEqual(Buffer.from(authenticated, 'hex'),
        Buffer.from(original.captured.authenticator, 'hex'))) fail(code);
      if (operation?.control === control) operation.authenticationKey = authority.authentication_key;
    }
    return original;
  };
  const inspectEpoch = (epoch, {authorityScopeCid, currentAuthorization,
    purpose}, control, persist) => {
    ensureOpen();
    if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
    if (!cid(authorityScopeCid) || !['admit', 'lookup'].includes(purpose)) {
      fail('InvalidClientSubmissionEpochOperation');
    }
    const operation = submissionOperations.get(epoch);
    const clock = epochClock(operation?.control === control ? operation : undefined, persist);
    const {captured, handle} = authenticateOriginalEpoch(epoch, control, clock,
      'ClientSubmissionEpochUnverifiable');
    if (captured.authorityScopeCid !== authorityScopeCid) {
      fail('ClientSubmissionEpochScopeMismatch');
    }
    const validity = control.clientSubmissionEpochValidity(handle, clock.observed_at);
    if (validity === undefined) fail('ClientSubmissionEpochClockInvalid');
    if (operation?.control === control && operation.epochCid === undefined) {
      operation.epochCid = control.clientSubmissionEpochCid(handle);
    }
    return {verified: {handle, epoch: captured, validity,
      epochCid: operation?.control === control ? operation.epochCid : control.clientSubmissionEpochCid(handle)},
    needsWrite: clock.needsWrite};
  };
  const verifyEpochLocked = (epoch, fields, control) => inspectEpoch(epoch, fields, control, true).verified;
  const verifyEpoch = (epoch, fields, control) => {
    if (submissionOperations.get(epoch)?.control === control) {
      const observed = inspectEpoch(epoch, fields, control, false);
      if (!observed.needsWrite) return observed.verified;
    }
    return transaction.run(() => verifyEpochLocked(epoch, fields, control));
  };
  const checkSubmissionBinding = (fields, submission, control, locked = false) => {
    if (submission === undefined) return 'admissible';
    const verify = locked ? verifyEpochLocked : verifyEpoch;
    const verified = verify(submission.epoch, {authorityScopeCid: fields.authorityScopeCid,
      currentAuthorization: submission.currentAuthorization, purpose: 'admit'}, control);
    const requestId = control.clientSubmissionRequestId(verified.handle, submission.nonce);
    if (requestId === undefined) fail('InvalidClientSubmissionNonce');
    if (requestId !== fields.requestId) fail('ClientSubmissionIdentityMismatch');
    if (submission.intentCid !== undefined) {
      // Expiry stops new admission, not preparation of an already accepted
      // intent. The persisted receipt, rather than a caller flag, supplies
      // this fact. Rejection and failed preparation cannot acquire a Run.
      assertIntentCustody();
      const row = intentSelect.get(requestId);
      if (row === undefined) fail('ClientSubmittedIntentCustodyLost');
      const retained = retainedIntent(row, control, submission.epoch);
      if (retained.intentCid !== submission.intentCid ||
          !['preparing', 'held', 'ready'].includes(retained.phase)) {
        fail('ClientSubmittedIntentConflict');
      }
      return 'admissible';
    }
    return verified.validity;
  };
  const refuseEpoch = validity => {
    if (validity !== 'admissible') fail(validity === 'expired'
      ? 'ClientSubmissionEpochExpired' : 'ClientSubmissionEpochNotYetValid');
  };
  const intentSelect = database.prepare('SELECT * FROM client_submitted_intents WHERE submission_id = ?');
  const intentUsage = database.prepare(`SELECT retained_count AS n,retained_bytes AS bytes,revision
    FROM client_submitted_intent_usage WHERE singleton=1`);
  const intentIssued = database.prepare('SELECT issued_count FROM client_submitted_intent_custody WHERE singleton = 1');
  const intentRetired = database.prepare('SELECT retired_count FROM client_submitted_intent_retirement WHERE singleton = 1');
  const restartSelect = database.prepare('SELECT * FROM client_submission_restarts WHERE fresh_submission_id = ?');
  const restartUsage = database.prepare(`SELECT retained_count AS n,retained_bytes AS bytes,revision
    FROM client_submission_restart_usage WHERE singleton=1`);
  const restartIssued = database.prepare('SELECT issued_count FROM client_submission_restart_custody WHERE singleton = 1');
  const assertRestartCustody = () => {
    const retained = restartUsage.get();
    if (!retained || !Number.isSafeInteger(retained.n) || retained.n < 0 ||
        !Number.isSafeInteger(retained.bytes) || retained.bytes < 0 || retained.bytes > 67108864 ||
        !Number.isSafeInteger(retained.revision) || retained.revision < 0 ||
        restartIssued.get()?.issued_count !== retained.n) {
      fail('ClientSubmissionRestartCustodyLost');
    }
    return retained;
  };
  const assertIntentCustody = () => {
    const retained = intentUsage.get();
    const issued = intentIssued.get()?.issued_count;
    const retired = intentRetired.get()?.retired_count;
    if (!retained || !Number.isSafeInteger(retained.n) || retained.n < 0 ||
        !Number.isSafeInteger(retained.bytes) || retained.bytes < 0 || retained.bytes > 67108864 ||
        !Number.isSafeInteger(retained.revision) || retained.revision < 0 ||
        !Number.isSafeInteger(issued) || !Number.isSafeInteger(retired) || retired < 0 ||
        !Number.isSafeInteger(retained.n + retired) || retained.n + retired !== issued) {
      fail('ClientSubmittedIntentCustodyLost');
    }
    return {...retained, issued, retired};
  };
  // Current-version durable input is read under this Journal's selected
  // opaque Host service, never a retired preparation token or Store grant.
  // Native SQL still sums ALL operands against the same statement envelope.
  const intentWireBytes = wire => {
    if (typeof wire !== 'string') fail('InvalidClientSubmittedIntent');
    const bytes = Buffer.byteLength(wire, 'utf8');
    const selected = Math.min(maxInspectionBytes,
      maxDatabaseBytes ?? maxInspectionBytes,
      primaryExecutionLimits?.maxParameterBytes ?? maxInspectionBytes);
    // The shared Core constructor needs +128 bytes/+4 nodes/+1 depth headroom.
    // This is its actual signed-Int representation boundary, not a profile cap.
    if (bytes < 1 || bytes > selected || bytes > 2147483519) {
      fail('ClientSubmittedIntentCapacity');
    }
    return bytes;
  };
  const admitIntentOriginal = (wire, control, epoch, code, canonical = true) => {
    const bytes = intentWireBytes(wire);
    const operation = submissionOperations.get(epoch);
    const previous = operation?.control === control ? operation.borrowedIntentOriginal : undefined;
    if (previous !== undefined && previous.wire === wire) return previous;
    // Every JSON node and nesting level occupies at least one original byte.
    // No independent historical node/depth ceiling narrows this admitted wire.
    const intent = control.clientSubmittedIntent(wire, bytes, bytes, bytes);
    if (intent === undefined) fail(code);
    const original = {intent, wire: control.clientSubmittedIntentWire(intent),
      identity: control.clientSubmittedIntentCid(intent)};
    if (canonical && original.wire !== wire) fail(code);
    return original;
  };
  const originalIntent = (intent, control, epoch) => {
    const operation = submissionOperations.get(epoch);
    const previous = operation?.control === control ? operation.borrowedIntentOriginal : undefined;
    if (previous !== undefined && previous.intent === intent) return previous;
    const wire = control.clientSubmittedIntentWire(intent);
    const identity = control.clientSubmittedIntentCid(intent);
    const original = admitIntentOriginal(wire, control, epoch, 'InvalidClientSubmittedIntent');
    if (original.identity !== identity) fail('InvalidClientSubmittedIntent');
    return original;
  };
  const nameSelect = database.prepare(`SELECT * FROM client_submission_names
    WHERE namespace_id = ? AND actor_id = ? AND name = ?`);
  const nameCustody = database.prepare('SELECT * FROM client_submission_name_custody WHERE singleton = 1');
  const assertNameCustody = () => {
    const row = nameCustody.get();
    if (row?.singleton !== 1 || !Number.isSafeInteger(row.issued_count) ||
        row.issued_count < 0 || row.issued_count !== row.retained_count) {
      fail('ClientSubmissionNameCustodyLost');
    }
    return row.issued_count;
  };
  const authenticateName = row => {
    const authority = epochAuthority.get();
    if (!validEpochAuthority(authority)) fail('ClientSubmissionEpochCustodyLost');
    // This is private storage authentication, not a new public CID domain or
    // authority token. Every original scope and intent component is included.
    return createHmac('sha256', Buffer.from(authority.authentication_key, 'hex'))
      .update(JSON.stringify(['scoped-submission-name', row.namespace_id, row.actor_id,
        row.name, row.authority_scope_cid, row.submission_id, row.intent_cid]), 'utf8').digest('hex');
  };
  // The caller must already hold this journal's transaction. Both ordinary
  // epoch admission and named resolution use this same custody transition.
  const recordIntentLocked = (submissionRef, original, {authorityScopeCid,
    currentAuthorization, phase = 'preparing', outcome}, restartWire, requestId, control,
    originalCustody) => {
    const retained = originalCustody ?? assertIntentCustody();
    const existing = intentSelect.get(requestId);
    if (existing !== undefined) {
      const previous = retainedIntent(existing, control, submissionRef.epoch);
      if (previous.intentCid !== original.identity) rejectSubmission('ClientSubmittedIntentConflict', 'conflict', 'intent');
      if (restartSelect.get(requestId)?.link_wire !== restartWire) rejectSubmission('ClientSubmissionRestartConflict', 'conflict', 'restart_decision');
      return {inserted: false, ...previous};
    }
    const current = verifyEpochLocked(submissionRef.epoch, {authorityScopeCid,
      currentAuthorization, purpose: 'admit'}, control);
    if (current.validity !== 'admissible') return {epochRejected: current.validity};
    const {restarts, originalRequestId} = checkRestartLocked(requestId, restartWire,
      {authorityScopeCid, currentAuthorization}, control);
    if (retained.n >= maxRecords || retained.issued === Number.MAX_SAFE_INTEGER ||
        retained.bytes + Buffer.byteLength(original.wire) > 64 * 1024 * 1024) {
      rejectSubmission('ClientSubmittedIntentCapacity', 'refused', 'admission_capacity');
    }
    database.prepare(`INSERT INTO client_submitted_intents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`)
      .run(requestId, authorityScopeCid, submissionRef.nonce,
        canonicalValueJson(current.epoch, {dataKeys: true}), original.identity,
        original.wire, epochAuthority.get().observed_at, phase,
        outcome === undefined ? null : canonicalValueJson(outcome, {dataKeys: true}));
    if (Number(database.prepare(`UPDATE client_submitted_intent_custody
      SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?`)
      .run(retained.issued).changes) !== 1) fail('ClientSubmittedIntentCustodyLost');
    if (restartWire !== undefined) {
      database.prepare('INSERT INTO client_submission_restarts VALUES (?, ?, ?)')
        .run(requestId, originalRequestId, restartWire);
      if (Number(database.prepare(`UPDATE client_submission_restart_custody
        SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?`)
        .run(restarts.n).changes) !== 1) fail('ClientSubmissionRestartCustodyLost');
    }
    return {inserted: true, ...retainedIntent(intentSelect.get(requestId), control, submissionRef.epoch)};
  };
  const restartDecision = (submissionRef, intentCid, unresolvedHistory, actorId) => {
    if (unresolvedHistory === undefined) return undefined;
    if (unresolvedHistory === null || typeof unresolvedHistory !== 'object' ||
        JSON.stringify(Object.keys(unresolvedHistory).sort()) !== JSON.stringify(['acknowledgement', 'submissionRef']) ||
        unresolvedHistory.acknowledgement !== 'possible_prior_execution_and_effects' || !text(actorId)) {
      fail('InvalidClientSubmissionRestart');
    }
    return canonicalValueJson({submissionRef: unresolvedHistory.submissionRef,
      acknowledgement: unresolvedHistory.acknowledgement, freshSubmissionRef: submissionRef,
      intentCid, actorId}, {dataKeys: true});
  };
  const checkRestartLocked = (requestId, restartWire, fields, control) => {
    const restarts = assertRestartCustody();
    if (restartWire === undefined) return {restarts};
    const restart = JSON.parse(restartWire);
    assertSubmissionCustody();
    const prior = verifyEpochLocked(restart.submissionRef.epoch,
      {...fields, purpose: 'lookup'}, control);
    const originalRequestId = control.clientSubmissionRequestId(prior.handle, restart.submissionRef.nonce);
    if (originalRequestId === undefined) fail('InvalidClientSubmissionRestart');
    if (prior.validity !== 'expired' || intentSelect.get(originalRequestId) !== undefined) {
      fail('ClientSubmissionRestartOriginalResolvable');
    }
    if (restart.submissionRef.epoch.expiresAt >= restart.freshSubmissionRef.epoch.expiresAt) {
      fail('InvalidClientSubmissionRestart');
    }
    // Unknown old execution is not a new-work permit. This connection cannot
    // discharge an existing Run/Model/Effect owner's unresolved responsibility.
    if (select.get(fields.authorityScopeCid, originalRequestId) !== undefined) {
      fail('ClientSubmissionRestartRequiresReconciliation');
    }
    if (restartSelect.get(requestId) !== undefined) fail('ClientSubmissionRestartConflict');
    if (restarts.n >= maxRecords || restarts.n === Number.MAX_SAFE_INTEGER ||
        restarts.bytes + Buffer.byteLength(restartWire) > 64 * 1024 * 1024) {
      fail('ClientSubmissionRestartCapacity');
    }
    return {restarts, originalRequestId};
  };
  const retainedRestart = (row, control) => {
    if (row === undefined) return undefined;
    let link;
    try {link = JSON.parse(row.link_wire);} catch (cause) {fail('ClientSubmissionRestartCorrupt', cause);}
    let canonical;
    try {
      canonical = restartDecision(link?.freshSubmissionRef, link?.intentCid,
        {submissionRef: link?.submissionRef, acknowledgement: link?.acknowledgement}, link?.actorId);
    } catch (cause) {fail('ClientSubmissionRestartCorrupt', cause);}
    if (link === null || typeof link !== 'object' ||
        JSON.stringify(Object.keys(link).sort()) !== JSON.stringify([
          'acknowledgement', 'actorId', 'freshSubmissionRef', 'intentCid', 'submissionRef']) ||
        !cid(link.intentCid) || canonical !== row.link_wire) {
      fail('ClientSubmissionRestartCorrupt');
    }
    const admitRef = ref => {
      if (ref === null || typeof ref !== 'object' ||
          JSON.stringify(Object.keys(ref).sort()) !== JSON.stringify(['epoch', 'nonce'])) {
        fail('ClientSubmissionRestartCorrupt');
      }
      const {handle} = epochHandle(ref.epoch, control);
      const authority = epochAuthority.get();
      if (!validEpochAuthority(authority) ||
          authenticateEpoch(authority.authentication_key, control.clientSubmissionEpochWire(handle)) !== ref.epoch.authenticator) {
        fail('ClientSubmissionRestartCorrupt');
      }
      return control.clientSubmissionRequestId(handle, ref.nonce);
    };
    if (admitRef(link.submissionRef) !== row.original_submission_id ||
        admitRef(link.freshSubmissionRef) !== row.fresh_submission_id ||
        link.submissionRef.epoch.authorityScopeCid !== link.freshSubmissionRef.epoch.authorityScopeCid ||
        link.submissionRef.epoch.expiresAt >= link.freshSubmissionRef.epoch.expiresAt) {
      fail('ClientSubmissionRestartCorrupt');
    }
    Object.freeze(link.submissionRef.epoch); Object.freeze(link.submissionRef);
    Object.freeze(link.freshSubmissionRef.epoch); Object.freeze(link.freshSubmissionRef);
    return Object.freeze(link);
  };
  const retainedIntentOriginal = (row, control, originalEpoch, previous) => {
    const authority = epochAuthority.get();
    const restartRow = restartSelect.get(row.submission_id);
    if (previous !== undefined && validEpochAuthority(authority) &&
        authority.authentication_key === previous.authenticationKey &&
        Object.keys(row).length === Object.keys(previous.row).length &&
        Object.keys(row).every(key => row[key] === previous.row[key]) &&
        (restartRow === undefined && previous.restartRow === undefined ||
         restartRow !== undefined && previous.restartRow !== undefined &&
         Object.keys(restartRow).length === Object.keys(previous.restartRow).length &&
         Object.keys(restartRow).every(key => restartRow[key] === previous.restartRow[key]))) {
      assertRestartCustody();
      return previous;
    }
    const original = admitIntentOriginal(row.intent_wire, control, originalEpoch,
      'ClientSubmittedIntentCorrupt');
    if (original.identity !== row.intent_cid) fail('ClientSubmittedIntentCorrupt');
    const intent = original.intent;
    const operation = submissionOperations.get(originalEpoch);
    const epoch = operation?.control === control &&
      operation.wire === row.epoch_wire ? originalEpoch : JSON.parse(row.epoch_wire);
    if (!validEpochAuthority(authority)) fail('ClientSubmissionEpochCustodyLost');
    const {handle} = authenticateOriginalEpoch(epoch, control, authority, 'ClientSubmittedIntentCorrupt');
    if (control.clientSubmissionRequestId(handle, row.nonce) !== row.submission_id ||
        epoch.authorityScopeCid !== row.authority_scope_cid ||
        !Number.isSafeInteger(row.accepted_at) || row.accepted_at < epoch.notBefore ||
        row.accepted_at >= epoch.expiresAt || !Number.isSafeInteger(row.revision) || row.revision < 0 ||
        !control.clientSubmittedIntentTransition(row.phase, row.phase)) fail('ClientSubmittedIntentCorrupt');
    const submissionRef = Object.freeze({epoch: Object.freeze(epoch), nonce: row.nonce});
    const outcome = row.outcome_wire === null ? undefined : JSON.parse(row.outcome_wire);
    if (outcome === undefined && row.phase !== 'preparing' ||
        outcome !== undefined && (outcome.kind !== row.phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, row.intent_cid))) {
      fail('ClientSubmittedIntentCorrupt');
    }
    if (row.phase === 'ready') {
      const run = select.get(row.authority_scope_cid, row.submission_id);
      if (run === undefined || run.run_definition_cid !== outcome.admission.ref.runDefinitionCid ||
          run.namespace_id !== outcome.admission.ref.namespaceId) fail('ClientSubmittedIntentCorrupt');
    }
    assertRestartCustody();
    const unresolvedHistory = retainedRestart(restartRow, control);
    if (unresolvedHistory !== undefined && unresolvedHistory.intentCid !== row.intent_cid) {
      fail('ClientSubmissionRestartCorrupt');
    }
    const value = Object.freeze({submissionRef: Object.freeze({epoch: Object.freeze(epoch), nonce: row.nonce}),
      requestId: row.submission_id, intentCid: row.intent_cid, intentWire: row.intent_wire,
      phase: row.phase, revision: row.revision, outcome,
      ...(unresolvedHistory === undefined ? {} : {unresolvedHistory})});
    return Object.freeze({intent, value, row: Object.freeze({...row}),
      authenticationKey: authority.authentication_key,
      restartRow: restartRow === undefined ? undefined : Object.freeze({...restartRow})});
  };
  const retainedIntent = (row, control, originalEpoch) =>
    retainedIntentOriginal(row, control, originalEpoch).value;
  const cancellationUsage = database.prepare('SELECT * FROM client_cancellation_row_usage WHERE singleton=1');
  const cancellationIssued = database.prepare('SELECT issued_count FROM client_cancellation_custody WHERE singleton = 1');
  const cancellationSelect = database.prepare(`SELECT * FROM client_cancellation_operations
    WHERE namespace_id = ? AND authority_scope_cid = ? AND cancel_id = ?`);
  const cancellationInsert = database.prepare(`INSERT INTO client_cancellation_operations
    (namespace_id, authority_scope_cid, cancel_id, run_definition_cid,
     expected_revision, intent_fingerprint_cid) VALUES (?, ?, ?, ?, ?, ?)`);
  const assertCancellationCustody = () => {
    const usage=cancellationUsage.get(), n=usage?.retained_count;
    if (!validJournalRowUsage(usage) || cancellationIssued.get()?.issued_count !== n) fail('ClientRequestJournalCorrupt');
    return n;
  };
  const insert = database.prepare(`INSERT INTO client_requests (${columns})
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const reserve = database.prepare(`UPDATE client_requests
    SET dispatch_reserved = 1, revision = revision + 1
    WHERE authority_scope_cid = ? AND caller_request_id = ? AND
      dispatch_reserved = 0`);
  const confirmPreDispatchFailure = database.prepare(`UPDATE client_requests
    SET pre_dispatch_failure_confirmed = 1, revision = revision + 1
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);
  const reservePhysicalStart = database.prepare(`UPDATE client_requests
    SET physical_start_reserved = 1, revision = revision + 1
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);

  const validCancellationRef = ref => text(ref?.namespaceId) &&
    cid(ref?.authorityScopeCid) && cid(ref?.runDefinitionCid) &&
    text(ref?.cancelId) && Number.isInteger(ref?.expectedRevision) &&
    ref.expectedRevision >= 0 && ref.expectedRevision <= 2147483647;
  const ownedCancellationRef = ref => Object.freeze({namespaceId: ref.namespaceId,
    authorityScopeCid: ref.authorityScopeCid, runDefinitionCid: ref.runDefinitionCid,
    cancelId: ref.cancelId, expectedRevision: ref.expectedRevision});
  const cancellationKnownFailure = error => [
    'ClientCancellationDenied', 'ClientCancellationIntentConflict',
    'ClientCancellationRevisionConflict', 'ClientRequestJournalCapacity',
  ].includes(error?.code);
  const cancellationDefinition = (ref, requestControl, publicationControl) => {
    const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    if (row === undefined) fail('ClientCancellationDenied');
    retainedIdentity(row, requestControl);
    if (!Number.isInteger(row.revision) || row.revision < 0 || row.revision > 2147483647) {
      fail('ClientCancellationRevisionConflict');
    }
    return {row, facts: retainedRunFacts(row, publicationControl, maxRunDefinitionWireBytes, updateOriginalControl)};
  };
  const cancellationIdentity = (ref, definition, control) => {
    const identity = control.clientCancellationAdmitRecord(ref.namespaceId,
      ref.authorityScopeCid, ref.cancelId, definition, ref.expectedRevision);
    if (identity === undefined) fail('ClientCancellationDenied');
    return identity;
  };
  const cancellationReadmission = (record, requestControl, publicationControl) => {
    const cancelRef = Object.freeze({namespaceId: record.namespace_id,
      authorityScopeCid: record.authority_scope_cid,
      runDefinitionCid: record.run_definition_cid, cancelId: record.cancel_id,
      expectedRevision: record.expected_revision});
    if (!validCancellationRef(cancelRef)) fail('ClientRequestJournalCorrupt');
    const {facts} = cancellationDefinition(cancelRef, requestControl, publicationControl);
    const identity = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
    if (requestControl.clientCancellationIntentCid(identity) !== record.intent_fingerprint_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    if (record.outcome_wire === null && record.outcome_cid === null) {
      return {identity, cancelRef, outcome: undefined};
    }
    if (typeof record.outcome_wire !== 'string' ||
        Buffer.byteLength(record.outcome_wire) > 4096 || !cid(record.outcome_cid) ||
        `sha256:${createHash('sha256').update(record.outcome_wire).digest('hex')}` !== record.outcome_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    let outcome;
    try { outcome = JSON.parse(record.outcome_wire); }
    catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
    if (outcome === null || typeof outcome !== 'object' ||
        Object.keys(outcome).sort().join(',') !== 'cancelRef,kind,ref,revision' ||
        !['accepted', 'already_requested', 'already_terminal'].includes(outcome.kind) ||
        !Number.isInteger(outcome.revision) || outcome.revision < cancelRef.expectedRevision ||
        outcome.kind === 'accepted' && outcome.revision === cancelRef.expectedRevision ||
        outcome.revision > 2147483647 ||
        canonicalValueJson(outcome.cancelRef) !== canonicalValueJson(cancelRef) ||
        canonicalValueJson(outcome.ref) !== canonicalValueJson({namespaceId: cancelRef.namespaceId,
          authorityScopeCid: cancelRef.authorityScopeCid, runDefinitionCid: cancelRef.runDefinitionCid}) ||
        canonicalValueJson(outcome) !== record.outcome_wire) fail('ClientRequestJournalCorrupt');
    return {identity, cancelRef, outcome: Object.freeze({...outcome,
      ref: Object.freeze(outcome.ref), cancelRef})};
  };
  const cancellationAction = (requested, retained, facts, row, currentAuthorization,
    publicationCommitted, requestControl) => {
    const action = requestControl.clientCancellationOperationAction(requested,
      retained ?? requested, retained !== undefined, facts.runDefinition,
      Number(row.revision), currentAuthorization,
      publicationCommitted || facts.preDispatchFailureConfirmed ||
        facts.physicalCloseConfirmed && facts.observedTerminalOutcome !== null,
      facts.cancellationRequested);
    if (action === 4) rejectCancellation('ClientCancellationIntentConflict', 'conflict', 'intent');
    if (action === 6) rejectCancellation('ClientCancellationRevisionConflict', 'conflict', 'control_revision');
    if (![0, 1, 2, 3].includes(action)) fail('ClientCancellationDenied');
    return action;
  };

  const acceptRecord = (identity, {namespaceId, runDefinitionCid,
    runDefinitionWire, resultNames, runAdmissionEvidence, revision = 0, lookupExpiresAt,
    submission}, control) => {
    ensureOpen();
    if (!control || typeof control.clientRequestAdmitRecord !== 'function' ||
        typeof control.clientRequestRelation !== 'function') {
      fail('InvalidClientRequestJournalControl');
    }
    const fields = checkedIdentity(identity, control);
    if (!text(namespaceId) || !cid(runDefinitionCid) ||
        runDefinitionWire !== undefined &&
          (typeof runDefinitionWire !== 'string' ||
            Buffer.byteLength(runDefinitionWire, 'utf8') >
              maxRunDefinitionWireBytes) ||
        !Number.isSafeInteger(revision) || revision < 0 ||
        resultNames !== undefined && (!Array.isArray(resultNames) ||
          resultNames.some(name => typeof name !== 'string' || !name) ||
          new Set(resultNames).size !== resultNames.length ||
          Buffer.byteLength(JSON.stringify(resultNames), 'utf8') > maxRunDefinitionWireBytes) ||
        !instant(lookupExpiresAt) ||
        Date.parse(lookupExpiresAt) <= Date.now()) {
      fail('InvalidClientRequestAdmission');
    }
    const capturedAdmissionEvidence = evidenceJson(runAdmissionEvidence,
      maxRunDefinitionWireBytes, updateOriginalControl);
    const admissionEvidence = capturedAdmissionEvidence?.wire ?? null;
    const admittedEvidence = capturedAdmissionEvidence?.value;
    assertKeyedInventoryRequest(admittedEvidence?.sourceInventory, fields);
    if (admittedEvidence?.valuesHostPolicyOriginal !== undefined &&
        (typeof runDefinitionWire !== 'string' ||
         JSON.parse(runDefinitionWire).authorization_context_cid !==
           valuesExecutionContextCid(fields.authorityScopeCid,
             admittedEvidence.valuesHostPolicyOriginal))) {
      fail('InvalidClientRunAdmissionEvidence');
    }
    if (admittedEvidence?.modelOriginalRunWire !== undefined &&
        capturedAdmissionEvidence.modelRunDefinitionWire !== runDefinitionWire) {
      fail('InvalidClientRunAdmissionEvidence');
    }
    // Retain observed expiry even if another admission fact later conflicts
    // and rolls its transaction back. The atomic check below still decides
    // whether this particular Run may be inserted.
    checkSubmissionBinding(fields, submission, control);
    const outcome = transact('accept', 'ClientRequestAcceptanceUnknown',
      error => typeof error?.code === 'string' &&
        (error.code.startsWith('ClientRequest') || error.code.startsWith('ClientSubmission')), () => {
      const retainedCount = assertSubmissionCustody();
      const existing = select.get(fields.authorityScopeCid,
        fields.requestId);
      if (existing !== undefined) {
        // An expired identity may still identify its retained outcome. This
        // path performs no new issuance; authenticate the original binding.
        checkSubmissionBinding(fields, submission, control, true);
        if (existing.namespace_id !== namespaceId) {
          fail('ClientRequestOwnerMismatch');
        }
        const relation = control.clientRequestRelation(identity,
          retainedIdentity(existing, control));
        if (relation !== 1) {
          fail(relation === 2 ? 'ClientRequestIntentConflict' :
            'ClientRequestJournalCorrupt');
        }
        if (runDefinitionWire !== undefined &&
            existing.run_definition_wire === null) {
          fail('ClientRequestDefinitionMissing');
        }
        if (resultNames !== undefined &&
            existing.result_names_json !== null &&
            existing.result_names_json !== JSON.stringify(resultNames)) {
          fail('ClientRequestResultInventoryMismatch');
        }
        const existingEvidence = retainedEvidence(existing, updateOriginalControl, capturedAdmissionEvidence);
        assertSourceInventory({physicalStartReserved: existing.physical_start_reserved === 1,
          runAdmissionEvidence: existingEvidence}, admittedEvidence?.sourceInventory);
        const proposedPlan = admittedEvidence?.logicalPlanOriginal;
        if (proposedPlan !== undefined) {
          const originalPlan = existingEvidence?.logicalPlanOriginal;
          if (originalPlan === undefined) fail('ClientRequestPlanEvidenceMissing');
          if (originalPlan.compiledPlanWire !== proposedPlan.compiledPlanWire ||
              originalPlan.planViewWire !== proposedPlan.planViewWire) {
            fail('ClientRequestPlanEvidenceMismatch');
          }
        }
        const proposedInfer = admittedEvidence?.inferRunOriginal;
        if (proposedInfer !== undefined) {
          const original = existingEvidence?.inferRunOriginal;
          if (original === undefined) fail('ClientRequestInferEvidenceMissing');
          if (canonicalValueJson(original) !== canonicalValueJson(proposedInfer)) {
            fail('ClientRequestInferEvidenceMismatch');
          }
        }
        return Object.freeze({inserted: false, ...admission(existing),
          runAdmissionEvidence: existingEvidence,
          ...(runDefinitionWire === undefined ? {} :
            {runDefinitionWire: existing.run_definition_wire}),
          resultNames: retainedResultNames(existing, maxRunDefinitionWireBytes)});
      }
      const epochValidity = checkSubmissionBinding(fields, submission, control, true);
      if (epochValidity !== 'admissible') {
        // Commit the expiry watermark without admitting a Run. Throwing inside
        // this transaction would roll the watermark back and let a backwards
        // clock revive the identity after an awaited issuance.
        return {epochRejected: epochValidity};
      }
      if (retainedCount + assertCancellationCustody() >= maxRecords) {
        fail('ClientRequestJournalCapacity');
      }
      if (selectRun.get(runDefinitionCid) !== undefined) {
        fail('ClientRequestRunAlreadyAssigned');
      }
      // Only this original acceptance transaction may associate submitted
      // content with a new Run. Equal caller CIDs or later configuration are
      // not a way to attach a restriction to an already issued Run.
      let originalAdmissionEvidence = admissionEvidence;
      if (submission?.intentCid !== undefined && admittedEvidence !== undefined) {
        const original = retainedIntent(intentSelect.get(fields.requestId), control, submission.epoch);
        if (admittedEvidence.submittedIntentCid !== undefined &&
            admittedEvidence.submittedIntentCid !== original.intentCid) {
          fail('ClientRequestSubmittedIntentMismatch');
        }
        if (!cid(original.intentCid)) fail('InvalidClientRunAdmissionEvidence');
        originalAdmissionEvidence = JSON.stringify({...admittedEvidence,
          submittedIntentCid: original.intentCid});
        if (Buffer.byteLength(originalAdmissionEvidence) > maxRunDefinitionWireBytes) {
          fail('InvalidClientRunAdmissionEvidence');
        }
      } else if (admittedEvidence?.submittedIntentCid !== undefined) {
        fail('ClientRequestSubmittedIntentMismatch');
      }
      insert.run(fields.authorityScopeCid, fields.requestId,
        fields.logicalRequestScopeCid, fields.intentFingerprintCid,
        fields.programDefinitionCid, fields.parameterValuesCid,
        fields.callerInputIntentCid, namespaceId, runDefinitionCid,
        runDefinitionWire ?? null, revision, lookupExpiresAt,
        resultNames === undefined ? null : JSON.stringify(resultNames),
        originalAdmissionEvidence);
      if (Number(advanceSubmissionCustody.run(retainedCount).changes) !== 1) {
        fail('ClientRequestSubmissionCustodyLost');
      }
      return Object.freeze({inserted: true, ref: Object.freeze({
        namespaceId, authorityScopeCid: fields.authorityScopeCid,
        runDefinitionCid,
      }), durability: 'durable', revision, lookupExpiresAt,
      ...(runDefinitionWire === undefined ? {} : {runDefinitionWire}),
      resultNames, runAdmissionEvidence: originalAdmissionEvidence === null ? undefined :
        freezeAdmissionEvidence(JSON.parse(originalAdmissionEvidence))});
    });
    if (outcome.epochRejected !== undefined) refuseEpoch(outcome.epochRejected);
    return outcome;
  };

  const lookupRecord = ({namespaceId, authorityScopeCid, requestId}, control, original) => {
    ensureOpen();
    if (!text(namespaceId) || !cid(authorityScopeCid) || !text(requestId) ||
        !control || typeof control.clientRequestAdmitRecord !== 'function') {
      fail('InvalidClientRequestLookup');
    }
    let row;
    try { row = select.get(authorityScopeCid, requestId); }
    catch (error) { fail('ClientRequestLookupUnknown', error); }
    if (row === undefined || row.namespace_id !== namespaceId) return undefined;
    const identity = original !== undefined &&
        row.authority_scope_cid === original.fields.authorityScopeCid &&
        row.caller_request_id === original.fields.requestId &&
        row.logical_request_scope_cid === original.fields.logicalRequestScopeCid &&
        row.intent_fingerprint_cid === original.fields.intentFingerprintCid &&
        row.program_definition_cid === original.fields.programDefinitionCid &&
        row.parameter_values_cid === original.fields.parameterValuesCid &&
        row.caller_input_intent_cid === original.fields.callerInputIntentCid
      ? original.identity : retainedIdentity(row, control);
    if (control.clientRequestScopeCid(identity) !==
        row.logical_request_scope_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    return Object.freeze({row, identity, found: Object.freeze({
      requestId: row.caller_request_id,
      ...admission(row),
    })});
  };

  const resolveOriginalDefinition = (identity, fields, namespaceId,
    requestControl, publicationControl) => {
    if (typeof requestControl.clientRequestRelation !== 'function') {
      fail('InvalidClientRequestLookup');
    }
    const retained = lookupRecord({namespaceId,
      authorityScopeCid: fields.authorityScopeCid,
      requestId: fields.requestId}, requestControl, {identity, fields});
    if (retained === undefined) return undefined;
    // Exact saved identity fields reuse this entry's already admitted request.
    // A distinct saved identity still follows lookupRecord's full admission.
    const relation = requestControl.clientRequestRelation(identity, retained.identity);
    if (relation !== 1) {
      fail(relation === 2 ? 'ClientRequestIntentConflict' :
        'ClientRequestJournalCorrupt');
    }
    return Object.freeze({...retained.found,
      ...retainedRunFacts(retained.row, publicationControl,
        maxRunDefinitionWireBytes, updateOriginalControl),
    });
  };

  let observationStorage;
  let observationDatabase;
  let observationSql;
  let observationStorageAttempted = false;
  let observationDatabaseClosed = true;
  let originalObservationClose, originalObservationIsOpen;
  const captureObservationCleanup = () => {
    originalObservationClose ??= observationDatabase.close;
    originalObservationIsOpen ??= Object.getOwnPropertyDescriptor(
      observationDatabase, 'isOpen')?.get;
    if (typeof originalObservationClose !== 'function' ||
        typeof originalObservationIsOpen !== 'function') {
      throw new TypeError('ClientObservationConnectionCleanupUnavailable');
    }
  };
  const closeObservationStorage = () => {
    if (observationDatabaseClosed) return;
    captureObservationCleanup();
    const opened = applyOriginal(originalObservationIsOpen, observationDatabase, []);
    if (typeof opened !== 'boolean' || opened &&
        (applyOriginal(originalObservationClose, observationDatabase, []) !== undefined ||
         applyOriginal(originalObservationIsOpen, observationDatabase, []) !== false)) {
      throw new TypeError('ClientObservationConnectionCleanupPending');
    }
    // This is the separate original connection's own close observation. Keep
    // the historical attempted flag, and retain any escaped managed aliases.
    observationDatabaseClosed = true;
    observationSql?.retireClosedNativeAliases();
  };
  const journal = Object.freeze({
    // The submission adapter owns one deeply frozen snapshot per public call.
    // Only that exact epoch may reuse pure authentication and its durable
    // time floor. Current permission and the retained authority row are still
    // checked at use; releasing this scope retains no cross-operation fact.
    retainSubmissionOperation(epoch, control, borrowedIntent) {
      ensureOpen();
      if (epoch === undefined) return undefined;
      if (epoch === null || typeof epoch !== 'object' || !Object.isFrozen(epoch) ||
          submissionOperations.has(epoch)) fail('InvalidClientSubmissionOperation');
      const operation = {epoch, control, wire: canonicalValueJson(epoch, {dataKeys: true})};
      // An explicit fixed preparation consumer lends this exact nominal intent
      // only until this operation's existing release, before its handler holder
      // returns. No inferred cache, cross-epoch inheritance or durable alias.
      if (borrowedIntent !== undefined) {
        const wire = control.clientSubmittedIntentWire(borrowedIntent);
        const identity = control.clientSubmittedIntentCid(borrowedIntent);
        if (typeof wire !== 'string' || typeof identity !== 'string') fail('InvalidClientSubmittedIntent');
        intentWireBytes(wire);
        operation.borrowedIntentOriginal = {intent: borrowedIntent, wire, identity};
      }
      submissionOperations.set(epoch, operation);
      return () => {
        // A retained old release cannot revoke a later same-epoch operation.
        // Cut the borrowed alias even if this light release closure escapes.
        operation.borrowedIntentOriginal = undefined;
        if (submissionOperations.get(epoch) === operation) submissionOperations.delete(epoch);
      };
    },
    prepareSubmittedIntent(epoch, wire, control) {
      ensureOpen();
      // This admission is not cached. An explicit original preparation borrow
      // is registered separately and released by the active operation.
      return admitIntentOriginal(wire, control, epoch, 'InvalidClientSubmittedIntent', false).intent;
    },
    closeObservationStorage,
    observationStorage() {
      ensureOpen();
      if (observationStorageAttempted) {
        if (observationStorage === undefined) throw new Error('ObservationBudgetUnavailable');
        return observationStorage;
      }
      observationStorageAttempted = true;
      // Separate connection/transaction custody prevents an observation's
      // unknown COMMIT from poisoning the semantic journal connection.
      observationDatabase = new DatabaseSync(path, primaryCurrent === undefined ?
        {open: false} : {__proto__: null, open: false});
      observationDatabaseClosed = false;
      captureObservationCleanup();
      if (primarySqlLimits !== undefined) {
        observationSql = boundedPrimarySql(observationDatabase, primarySqlLimits,
          primaryExecutionLimits, primaryCurrent, walFrames);
      }
      primaryCurrent?.();
      const originalObservationOpen = observationDatabase.open;
      if (typeof originalObservationOpen !== 'function' ||
          applyOriginal(originalObservationOpen, observationDatabase, []) !== undefined ||
          applyOriginal(originalObservationIsOpen, observationDatabase, []) !== true) {
        throw new TypeError('ClientObservationConnectionOpenUnavailable');
      }
      const selectedObservation = observationSql?.database ?? observationDatabase;
      // The primary connection's Pager setting cannot constrain this new
      // original connection. Select the same finite extent before its first
      // schema/control write, retaining its existing separate close duty.
      boundJournalDatabaseExtent(selectedObservation, maxDatabaseBytes, primaryExecutionLimits, walFrames,
        false, undefined, observationSql?.prepareWalCheckpoint);
      selectedObservation.exec('PRAGMA busy_timeout = 0');
      const storage = openClientObservationStorage(selectedObservation,
        createSqliteTransaction(selectedObservation, 'ClientObservation'));
      observationStorage = Object.freeze({...storage, close: closeObservationStorage});
      return observationStorage;
    },
    installObservationProjection(projection) {
      if (!isHostObservationProjection(projection) || observationProjection !== undefined) {
        throw new TypeError('ForeignHostObservationProjection');
      }
      observationProjection = projection;
    },
    // Intent custody is separate from Run-definition custody. A preparing
    // receipt contains no invented execution CID and performs no dispatch.
    resolveOrBindSubmittedName(name, intent, {namespaceId, actorId, authorityScopeCid,
      currentAuthorization, submissionRef}, control) {
      ensureOpen();
      if (!validSubmissionName(name) || !text(namespaceId) ||
          !namespaceId.isWellFormed() || !text(actorId) || !actorId.isWellFormed() ||
          !cid(authorityScopeCid)) fail('InvalidClientSubmissionName');
      if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
      const original = originalIntent(intent, control, submissionRef?.epoch);
      const result = submissionTransaction(() => {
        const issued = assertNameCustody();
        const intentCustody = assertIntentCustody();
        const existing = nameSelect.get(namespaceId, actorId, name);
        if (existing !== undefined) {
          if (!hexKey(existing.binding_authenticator) ||
              !timingSafeEqual(Buffer.from(existing.binding_authenticator, 'hex'),
                Buffer.from(authenticateName(existing), 'hex'))) fail('ClientSubmissionNameCustodyLost');
          if (existing.authority_scope_cid !== authorityScopeCid ||
              existing.intent_cid !== original.identity) rejectSubmission('ClientSubmittedIntentConflict', 'conflict', 'intent');
          const row = intentSelect.get(existing.submission_id);
          // Formal retirement leaves this permanent bounded fence. Missing
          // history is never promoted to an unused name or a fresh epoch.
          if (row === undefined) fail('ClientSubmissionNameUnresolvable');
          const retained = retainedIntent(row, control, submissionRef?.epoch);
          if (retained.requestId !== existing.submission_id ||
              retained.intentCid !== existing.intent_cid || retained.intentWire !== original.wire ||
              retained.submissionRef.epoch.authorityScopeCid !== authorityScopeCid) {
            fail('ClientSubmissionNameCustodyLost');
          }
          verifyEpochLocked(retained.submissionRef.epoch, {authorityScopeCid,
            currentAuthorization, purpose: 'lookup'}, control);
          return {inserted: false, ...retained};
        }
        if (issued >= maxRecords || issued === Number.MAX_SAFE_INTEGER) {
          rejectSubmission('ClientSubmissionNameCapacity', 'refused', 'admission_capacity');
        }
        if (!validSubmissionRef(submissionRef)) fail('InvalidClientSubmissionName');
        const verified = verifyEpochLocked(submissionRef.epoch, {authorityScopeCid,
          currentAuthorization, purpose: 'admit'}, control);
        if (verified.validity !== 'admissible') return {epochRejected: verified.validity};
        const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
        if (requestId === undefined) fail('InvalidClientSubmissionNonce');
        // A caller-selected old nonce is not retroactively named. Only an
        // unused authenticated reference can acquire this new name and intent.
        if (intentSelect.get(requestId) !== undefined) fail('ClientSubmissionNameReferenceUsed');
        const retained = recordIntentLocked(submissionRef, original,
          {authorityScopeCid, currentAuthorization}, undefined, requestId, control, intentCustody);
        if (retained.epochRejected !== undefined) return retained;
        const row = {namespace_id: namespaceId, actor_id: actorId, name,
          authority_scope_cid: authorityScopeCid, submission_id: requestId, intent_cid: original.identity};
        database.prepare('INSERT INTO client_submission_names VALUES (?, ?, ?, ?, ?, ?, ?)')
          .run(namespaceId, actorId, name, authorityScopeCid, requestId,
            original.identity, authenticateName(row));
        if (Number(database.prepare(`UPDATE client_submission_name_custody
          SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?`)
          .run(issued).changes) !== 1) fail('ClientSubmissionNameCustodyLost');
        assertNameCustody();
        return retained;
      });
      if (result.epochRejected !== undefined) rejectSubmissionEpoch(result.epochRejected);
      return Object.freeze(result);
    },
    resolveNamedSubmissionAttempt(name, intent, options, control) {
      return submissionAttempt(options.submissionRef, intent, options, control,
        () => journal.resolveOrBindSubmittedName(name, intent, options, control), 'recorded');
    },
    checkSubmittedIntent(submissionRef, intent, {authorityScopeCid,
      currentAuthorization, unresolvedHistory, actorId}, control) {
      ensureOpen();
      const original = originalIntent(intent, control, submissionRef.epoch);
      const restartWire = restartDecision(submissionRef, original.identity, unresolvedHistory, actorId);
      const fields = {authorityScopeCid, currentAuthorization};
      const result = submissionTransaction(() => {
        assertIntentCustody();
        const verified = verifyEpochLocked(submissionRef.epoch, {...fields, purpose: 'lookup'}, control);
        const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
        if (requestId === undefined) fail('InvalidClientSubmittedIntent');
        const existing = intentSelect.get(requestId);
        if (existing !== undefined) {
          const previous = retainedIntent(existing, control, submissionRef.epoch);
          if (previous.intentCid !== original.identity) rejectSubmission('ClientSubmittedIntentConflict', 'conflict', 'intent');
          if (restartSelect.get(requestId)?.link_wire !== restartWire) rejectSubmission('ClientSubmissionRestartConflict', 'conflict', 'restart_decision');
        } else {
          if (verified.validity !== 'admissible') return {epochRejected: verified.validity};
          checkRestartLocked(requestId, restartWire, fields, control);
        }
        return {requestId};
      });
      if (result.epochRejected !== undefined) rejectSubmissionEpoch(result.epochRejected);
      return Object.freeze(result);
    },
    recordSubmittedIntent(submissionRef, intent, {authorityScopeCid,
      currentAuthorization, phase = 'preparing', outcome, unresolvedHistory, actorId}, control) {
      ensureOpen();
      const original = originalIntent(intent, control, submissionRef.epoch);
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'admit'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      const restartWire = restartDecision(submissionRef, original.identity, unresolvedHistory, actorId);
      if (requestId === undefined || !['preparing', 'not_accepted'].includes(phase)) {
        fail('InvalidClientSubmittedIntent');
      }
      if (phase === 'not_accepted' && (outcome?.kind !== phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, original.identity))) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      if (phase === 'preparing' && outcome !== undefined && (outcome.kind !== phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, original.identity))) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      const result = submissionTransaction(() => recordIntentLocked(submissionRef, original,
        {authorityScopeCid, currentAuthorization, phase, outcome}, restartWire, requestId, control));
      if (result.epochRejected !== undefined) rejectSubmissionEpoch(result.epochRejected);
      return Object.freeze(result);
    },
    // Invocation facts are projections of the existing admission boundary,
    // never replacement receipts or proof that another invocation did not run.
    checkSubmissionAttempt(submissionRef, intent, options, control) {
      return submissionAttempt(submissionRef, intent, options, control,
        () => journal.checkSubmittedIntent(submissionRef, intent, options, control), 'checked');
    },
    recordSubmissionAttempt(submissionRef, intent, options, control) {
      return submissionAttempt(submissionRef, intent, options, control,
        () => journal.recordSubmittedIntent(submissionRef, intent, options, control), 'recorded');
    },
    lookupSubmittedIntent(submissionRef, {authorityScopeCid, currentAuthorization}, control) {
      ensureOpen();
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'lookup'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined) fail('InvalidClientSubmissionNonce');
      const row = intentSelect.get(requestId);
      return row === undefined ? undefined : retainedIntent(row, control, submissionRef.epoch);
    },
    // Explicit trusted-Host retention operation, not a Client cancellation
    // or evidence of nonexecution. In-progress and Run-connected custody stays
    // with its existing owners. No automatic eviction during new admission.
    retireSubmittedIntent(submissionRef, {authorityScopeCid, currentAuthorization,
      expectedRevision}, control) {
      ensureOpen();
      const fields = {authorityScopeCid, currentAuthorization, purpose: 'lookup'};
      const verified = verifyEpoch(submissionRef.epoch, fields, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
        fail('InvalidClientSubmittedIntentRetirement');
      }
      return Object.freeze(transaction.run(() => {
        const custody = assertIntentCustody();
        const current = verifyEpochLocked(submissionRef.epoch, fields, control);
        if (current.validity !== 'expired') fail('ClientSubmittedIntentNotRetirable');
        const row = intentSelect.get(requestId);
        if (row === undefined) return {retired: false};
        const original = retainedIntent(row, control, submissionRef.epoch);
        if (original.revision !== expectedRevision) fail('ClientSubmittedIntentRetirementConflict');
        if (!['not_accepted', 'preparation_failed'].includes(original.phase) ||
            select.get(authorityScopeCid, requestId) !== undefined) {
          fail('ClientSubmittedIntentNotRetirable');
        }
        if (Number(database.prepare(`DELETE FROM client_submitted_intents
          WHERE submission_id = ? AND revision = ?`).run(requestId, expectedRevision).changes) !== 1 ||
            Number(database.prepare(`UPDATE client_submitted_intent_retirement
              SET retired_count = retired_count + 1 WHERE singleton = 1 AND retired_count = ?`)
              .run(custody.retired).changes) !== 1) fail('ClientSubmittedIntentCustodyLost');
        return {retired: true};
      }));
    },
    completeSubmittedIntent(submissionRef, outcome, {authorityScopeCid,
      currentAuthorization, expectedRevision, connection}, control) {
      ensureOpen();
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'lookup'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      return transaction.run(() => {
        assertIntentCustody();
        const row = intentSelect.get(requestId);
        if (row === undefined) fail('ClientSubmittedIntentCustodyLost');
        const retained = retainedIntent(row, control, submissionRef.epoch);
        if (!sameSubmissionRef(retained.submissionRef, submissionRef) ||
            !validSubmissionOutcome(outcome, connection, submissionRef, retained.intentCid)) {
          fail('InvalidClientSubmittedIntentOutcome');
        }
        if (retained.revision !== expectedRevision) return retained;
        if (!control.clientSubmittedIntentTransition(retained.phase, outcome.kind)) {
          fail('InvalidClientSubmittedIntentOutcome');
        }
        if (['ready', 'not_accepted', 'preparation_failed'].includes(retained.phase)) return retained;
        if (outcome.kind === 'ready') {
          const run = select.get(authorityScopeCid, requestId);
          if (run === undefined || run.run_definition_cid !== outcome.admission.ref.runDefinitionCid ||
              run.namespace_id !== outcome.admission.ref.namespaceId) fail('InvalidClientSubmittedIntentOutcome');
        }
        database.prepare(`UPDATE client_submitted_intents SET phase = ?, outcome_wire = ?, revision = revision + 1
          WHERE submission_id = ? AND revision = ?`).run(outcome.kind,
          canonicalValueJson(outcome, {dataKeys: true}), requestId, expectedRevision);
        return retainedIntent(intentSelect.get(requestId), control, submissionRef.epoch);
      });
    },
    issueSubmissionEpoch({authorityScopeCid, currentAuthorization}, control) {
      ensureOpen();
      if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
      if (!cid(authorityScopeCid)) fail('InvalidClientSubmissionEpochOperation');
      return transaction.run(() => {
        const clock = epochClock();
        const epoch = {version: 'actql-submission-epoch/0.1', authorityScopeCid,
          epochNonce: randomBytes(32).toString('hex'), notBefore: clock.observed_at,
          expiresAt: clock.observed_at + submissionEpochTtlMs};
        const handle = control.clientSubmissionEpoch(authorityScopeCid,
          epoch.epochNonce, epoch.notBefore, epoch.expiresAt);
        if (handle === undefined) fail('InvalidClientSubmissionEpochOperation');
        return Object.freeze({...epoch, authenticator: authenticateEpoch(
          clock.authentication_key, control.clientSubmissionEpochWire(handle))});
      });
    },
    verifySubmissionEpoch(epoch, fields, control) {
      const {handle: _handle, ...verified} = verifyEpoch(epoch, fields, control);
      return Object.freeze(verified);
    },
    submissionIdentity(epoch, nonce, fields, control) {
      const {handle, ...verified} = verifyEpoch(epoch, fields, control);
      const requestId = control.clientSubmissionRequestId(handle, nonce);
      if (requestId === undefined) fail('InvalidClientSubmissionNonce');
      return Object.freeze({...verified, requestId});
    },
    // The transaction owns uniqueness and durable acceptance; no task is
    // started here. A duplicate is interpreted only by the common MoonBit
    // relation, never by comparing transport JSON or a local retry counter.
    accept(identity, {namespaceId, runDefinitionCid, revision = 0,
      lookupExpiresAt, submission}, control) {
      return acceptRecord(identity, {namespaceId, runDefinitionCid,
        revision, lookupExpiresAt, submission}, control);
    },
    // The complete canonical Run Definition is retained in the same
    // transaction as the request. The caller must have obtained it from the
    // shared Run issuer; re-admission here checks identity, not authority.
    // Reattachment never reissues this identity.
    acceptDefinition(identity, {namespaceId, runDefinition, resultNames, runAdmissionEvidence, originalPlan, originalInferRun,
      revision = 0, lookupExpiresAt, submission}, requestControl, publicationControl) {
      ensureOpen();
      const definition = checkedRunDefinition(runDefinition,
        publicationControl, maxRunDefinitionWireBytes);
      // Only the existing compiler control can issue the first original. A
      // wire copy is not an opaque compiler selection. No later transaction
      // fills missing evidence in an already accepted Run.
      if (runAdmissionEvidence !== null && typeof runAdmissionEvidence === 'object' &&
          Object.hasOwn(runAdmissionEvidence, 'logicalPlanOriginal')) {
        fail('InvalidClientRunPlanOriginal');
      }
      if (runAdmissionEvidence !== null && typeof runAdmissionEvidence === 'object' &&
          Object.hasOwn(runAdmissionEvidence, 'inferRunOriginal')) {
        fail('InvalidClientInferRunOriginal');
      }
      if (originalInferRun !== undefined) {
        if (typeof publicationControl.originalInferRunAdmissionEvidence !== 'function' ||
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl)) {
          fail('InvalidClientInferRunOriginal');
        }
        let original;
        try {
          original = publicationControl.originalInferRunAdmissionEvidence(originalInferRun,
            definition, identity, runAdmissionEvidence);
        } catch (cause) { fail('InvalidClientInferRunOriginal', cause); }
        runAdmissionEvidence = {...runAdmissionEvidence, inferRunOriginal: original};
      }
      if (originalPlan !== undefined) {
        if (typeof publicationControl.originalRunPlanAdmissionEvidence !== 'function' ||
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl)) fail('InvalidClientRunPlanOriginal');
        let original;
        try {
          original = publicationControl.originalRunPlanAdmissionEvidence(originalPlan,
            definition, requestControl.clientRequestProgramCid(identity), runAdmissionEvidence);
          if (!logicalPlanOriginalShape(original)) fail('InvalidClientRunPlanOriginal');
          if (Buffer.byteLength(original.compiledPlanWire) > maxRunDefinitionWireBytes ||
              Buffer.byteLength(original.planViewWire) > maxRunDefinitionWireBytes) {
            fail('InvalidClientRunAdmissionEvidence');
          }
          // This nominal compiler selection already checked Plan/map/Run
          // binding before issuance. Adopting its exact original is not a
          // second stored-map read or another execution permission.
        } catch (cause) {
          if (cause?.code === 'InvalidClientRunAdmissionEvidence') throw cause;
          fail('InvalidClientRunPlanOriginal', cause);
        }
        runAdmissionEvidence = {...runAdmissionEvidence,
          logicalPlanOriginal: Object.freeze({...original})};
      }
      const accepted = acceptRecord(identity, {namespaceId,
        runDefinitionCid: definition.identity,
        runDefinitionWire: definition.wire,
        resultNames, runAdmissionEvidence, revision, lookupExpiresAt, submission}, requestControl);
      // This optional projection runs after the semantic transaction. Only
      // its branded bounded queue is reachable here, never user delivery.
      observationProjection?.accepted(accepted,
        requestControl.clientRequestCallerId(identity));
      observationProjection?.emit('run', 'definition_admitted',
        {ref: accepted.ref, revision: accepted.revision});
      return Object.freeze({
        inserted: accepted.inserted,
        ref: accepted.ref,
        durability: accepted.durability,
        revision: accepted.revision,
        lookupExpiresAt: accepted.lookupExpiresAt,
        resultNames: accepted.resultNames,
        runAdmissionEvidence: accepted.runAdmissionEvidence,
        // The acknowledged winner may be this operation's already admitted
        // original. A different selected body still follows full admission.
        runDefinition: accepted.ref.runDefinitionCid === definition.identity &&
          accepted.runDefinitionWire === definition.wire ? definition : retainedRunDefinition({
          run_definition_cid: accepted.ref.runDefinitionCid,
          run_definition_wire: accepted.runDefinitionWire,
        }, publicationControl, maxRunDefinitionWireBytes),
      });
    },
    // Authorization and retention policy are performed by the Host before
    // exposing a found record. Physical lookup never starts Compute.
    lookup(key, control) {
      return lookupRecord(key, control)?.found;
    },
    // Internal owner recovery, not a wire credential or current permission.
    // Both logical keys are re-admitted before the caller can reuse the scope.
    lookupIdentity(key, control) {
      return lookupRecord(key, control)?.identity;
    },
    lookupDefinition(key, requestControl, publicationControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl),
      });
    },
    // Attach reads the original accepted Run Definition by its exact ref.
    // It does not infer authority from a CID alone or create another Run.
    lookupRunDefinition(ref, requestControl, publicationControl, originalFrame) {
      let original;
      if(originalFrame!==undefined) {
        ensureOpen();
        original=retainRunStateFrame(originalFrame,ref);
        if(original.requestControl!==requestControl || original.publicationControl!==publicationControl) {
          fail('ForeignRunStateObservation');
        }
      }
      const row = readRunDefinitionRow(ref, requestControl);
      if (row === undefined) return undefined;
      if(original!==undefined && sameRunStateRow(row,original.row)) return originalFrame;
      return admitRunDefinitionRow(row, requestControl, publicationControl);
    },
    // Only public observation metadata may explain this particular frame
    // change. Both frames already belong to this Journal's full admission;
    // every immutable/control column and selected key must remain exact.
    canReinspectRunStopAfterStatePublication(beforeFrame, afterFrame) {
      ensureOpen();
      const before=runStateFrames.get(beforeFrame),after=runStateFrames.get(afterFrame);
      if(before===undefined||after===undefined||beforeFrame===afterFrame||
          before.requestControl!==after.requestControl||before.publicationControl!==after.publicationControl) return false;
      const old=before.row,next=after.row;
      return Number.isSafeInteger(old.state_revision)&&old.state_revision>=0&&
        Number.isSafeInteger(next.state_revision)&&
        (next.state_revision>old.state_revision||old.state_observation_key===null&&old.state_revision===0&&next.state_revision===0)&&
        (old.state_observation_key===null||typeof old.state_observation_key==='string'&&old.state_observation_key.length>0)&&
        typeof next.state_observation_key==='string'&&next.state_observation_key.length>0&&
        next.state_observation_key!==old.state_observation_key&&
        Object.keys(old).length===Object.keys(next).length&&
        Object.keys(old).every(key=>key==='state_revision'||key==='state_observation_key'||old[key]===next[key]);
    },
    // Private original-content projection for this journal's admitted Run.
    // It grants neither current authorization nor a physical/resume claim.
    // Historical unselected Runs remain readable without a new reference;
    // missing selected custody cannot be repaired from current caller options.
    originalSubmittedIntent(identity, {namespaceId}, requestControl,
      publicationControl) {
      ensureOpen();
      if (!text(namespaceId) ||
          typeof requestControl?.clientSubmittedIntentRequestsCommitStop !== 'function') {
        fail('InvalidClientRequestJournalControl');
      }
      const fields = checkedIdentity(identity, requestControl);
      const requestOriginal = Object.freeze({identity, fields});
      let previousRunRow, previousRunFacts, previousIntent;
      let previousReference;
      const readOriginal = () => {
        try {
          assertSubmissionCustody();
          assertIntentCustody();
          const run = lookupRecord({namespaceId, authorityScopeCid: fields.authorityScopeCid,
            requestId: fields.requestId}, requestControl, requestOriginal);
          if (run === undefined || requestControl.clientRequestRelation(identity,
            run.identity) !== 1) fail('ClientRequestSubmittedIntentMismatch');
          // This existing handle retains only typed facts for exact unchanged
          // scalar rows. Storage/custody is still observed in this transaction;
          // an actual change re-enters the original admission path below.
          if (previousRunRow === undefined ||
              Object.keys(run.row).length !== Object.keys(previousRunRow).length ||
              Object.keys(run.row).some(key => run.row[key] !== previousRunRow[key])) {
            previousRunFacts = retainedRunFacts(run.row, publicationControl,
              maxRunDefinitionWireBytes, updateOriginalControl);
            previousRunRow = Object.freeze({...run.row});
          }
          const facts = previousRunFacts;
          const expectedCid = facts.runAdmissionEvidence?.submittedIntentCid;
          const row = intentSelect.get(fields.requestId);
          if (row === undefined) {
            if (expectedCid !== undefined) fail('ClientSubmittedIntentCustodyLost');
            return undefined;
          }
          previousIntent = retainedIntentOriginal(row, requestControl, undefined, previousIntent);
          const {intent, value: original} = previousIntent;
          if (intent === undefined || !['preparing', 'held', 'ready'].includes(original.phase)) {
            fail('ClientRequestSubmittedIntentMismatch');
          }
          if (expectedCid === undefined) {
            if (requestControl.clientSubmittedIntentRequestsCommitStop(intent) ||
                requestControl.clientSubmittedIntentRequestsReadOnly(intent)) {
              fail('ClientRequestSubmittedIntentBindingMissing');
            }
            return undefined;
          }
          if (expectedCid !== original.intentCid) fail('ClientRequestSubmittedIntentMismatch');
          if (previousReference === undefined || previousReference.epochWire !== row.epoch_wire ||
              previousReference.nonce !== row.nonce) {
            previousReference = Object.freeze({epochWire: row.epoch_wire, nonce: row.nonce,
              wire: canonicalValueJson(original.submissionRef, {dataKeys: true})});
          }
          return {intent, intentCid: original.intentCid, intentWire: original.intentWire,
            referenceWire: previousReference.wire,
            runDefinitionCid: run.row.run_definition_cid};
        } catch (error) {
          previousRunRow = previousRunFacts = previousIntent = previousReference = undefined;
          throw error;
        }
      };
      const original = transaction.run(readOriginal);
      if (original === undefined) return undefined;
      return Object.freeze({intent: original.intent, referenceWire: original.referenceWire,
        assertCurrent() {
          try {
            ensureOpen();
            const current = transaction.run(readOriginal);
            if (current === undefined || current.intentCid !== original.intentCid ||
                current.intentWire !== original.intentWire ||
                current.referenceWire !== original.referenceWire ||
                current.runDefinitionCid !== original.runDefinitionCid) {
              fail('ClientRequestSubmittedIntentMismatch');
            }
          } catch (error) {
            previousRunRow = previousRunFacts = previousIntent = previousReference = undefined;
            throw error;
          }
        }});
    },
    // Advance only published logical/control/availability facts. The same
    // original accepted row, complete observation fence and confirmed COMMIT
    // own this counter. Neither reading nor wall-clock time increments it.
    publishRunState(frame, state, requestControl, publicationControl) {
      ensureOpen();
      const retained = runStateFrames.get(frame);
      if (retained === undefined || retained.requestControl !== requestControl ||
          retained.publicationControl !== publicationControl) fail('ForeignRunStateObservation');
      const expected = retained.row;
      if (!Number.isSafeInteger(expected.state_revision) || expected.state_revision < 0 ||
          expected.state_observation_key !== null &&
            (typeof expected.state_observation_key !== 'string' || expected.state_observation_key.length === 0)) {
        fail('ClientRequestJournalCorrupt');
      }
      // The frame already admitted this complete original row. Reuse its
      // typed Run/control facts, not a decode/encode/hash of identical bytes.
      const control = issueInstalledRunControlObservation(requestControl, {
          revision: frame.revision,
          cancellationRequested: frame.cancellationRequested,
          physicallyUnstarted: frame.physicalStartReserved === false,
          preDispatchFailureConfirmed: frame.preDispatchFailureConfirmed,
          physicalCloseConfirmed: frame.physicalCloseConfirmed,
        });
      const runId = publicationControl.runDefinitionRunId(frame.runDefinition);
      const originalMessage = retainedBudgetFailureMessage(expected.state_observation_key,
        state, runId, control);
      const projection = prepareInstalledRunStateObservation(requestControl, {
        state: {...state, ...(originalMessage === undefined ? {} : {
          terminal_error: {...state.terminal_error, message: originalMessage},
        }), control}, runId,
        revision: expected.state_revision, priorKey: expected.state_observation_key,
      });
      const currentRow = () => {
        const row = readRunDefinitionRow(frame.ref, requestControl);
        if (row === undefined || Object.keys(row).length !== Object.keys(expected).length ||
            Object.keys(expected).some(key => row[key] !== expected[key])) {
          fail('RunStateObservationChanged');
        }
        return row;
      };
      // This read follows projection/callback work and is the unchanged
      // observation's linearization point. No mutation means no write TX or
      // COMMIT. Changed observations still use the original atomic CAS below.
      const observed = currentRow();
      if (projection.key === observed.state_observation_key) return projection.wire;
      return transact('run_state_observation', 'ClientRunStateObservationUnknown',
        error => ['RunStateObservationChanged', 'ClientRequestJournalCorrupt',
          'ForeignRunStateObservation', 'MoonBitHostFailure'].includes(error?.code), () => {
          const row = currentRow();
          if (projection.key !== row.state_observation_key) {
            const result = database.prepare(`UPDATE client_requests SET
              state_revision = ?, state_observation_key = ?
              WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
                AND state_revision = ? AND state_observation_key IS ?`).run(
              projection.revision, projection.key, row.namespace_id, row.authority_scope_cid,
              row.run_definition_cid, row.state_revision, row.state_observation_key);
            if (Number(result.changes) !== 1) fail('RunStateObservationChanged');
          }
          // transaction.run exposes this value only after confirmed COMMIT.
          return projection.wire;
        });
    },
    // One observation frame for an already selected Run, not an authority
    // cache. Every call reads committed storage and checks connection health.
    // Reuse admission only for an exactly unchanged complete row, including
    // cancellation and payload bytes; revision alone is not sufficient.
    observeRunCancellation(ref, requestControl, publicationControl, originalFrame) {
      const selected = Object.freeze({namespaceId: ref?.namespaceId,
        authorityScopeCid: ref?.authorityScopeCid, runDefinitionCid: ref?.runDefinitionCid});
      let previousRow;
      let previousFacts;
      if (originalFrame !== undefined) {
        ensureOpen();
        const retained = retainRunStateFrame(originalFrame,selected);
        if (retained.requestControl !== requestControl ||
            retained.publicationControl !== publicationControl) {
          fail('ForeignRunStateObservation');
        }
        // The same observation already admitted this complete original row.
        // The first probe still reads and compares every current scalar field.
        previousRow = retained.row;
        previousFacts = Object.freeze({revision: originalFrame.revision,
          cancellationRequested: originalFrame.cancellationRequested});
      }
      return () => {
        try {
          const row = readRunDefinitionRow(selected, requestControl);
          if (row === undefined) {
            previousRow = previousFacts = undefined;
            return undefined;
          }
          if (previousRow !== undefined && sameRunStateRow(row,previousRow)) {
            return previousFacts;
          }
          const facts = admitRunDefinitionRow(row, requestControl, publicationControl);
          previousRow = row;
          // Do not expose cached mutable nested evidence or a Definition as
          // permission. The caller receives only the current cancellation fact.
          previousFacts = Object.freeze({revision: facts.revision,
            cancellationRequested: facts.cancellationRequested});
          return previousFacts;
        } catch (error) {
          previousRow = previousFacts = undefined;
          throw error;
        }
      };
    },
    // Recover identity and Definition from one physical journal observation.
    // This internal owner must not be projected as a Client wire response.
    lookupOwnedDefinition(key, requestControl, publicationControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        requestIdentity: retained.identity,
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl),
      });
    },
    // A resend can resolve an already accepted request before issuing a new
    // plan or Run Definition. The shared owner compares the checked intent;
    // absence does not prove that a concurrent submission cannot still land.
    resolveDefinition(identity, {namespaceId}, requestControl,
      publicationControl) {
      ensureOpen();
      if (!text(namespaceId) || !requestControl ||
          typeof requestControl.clientRequestRelation !== 'function') {
        fail('InvalidClientRequestLookup');
      }
      const fields = checkedIdentity(identity, requestControl);
      return resolveOriginalDefinition(identity, fields, namespaceId,
        requestControl, publicationControl);
    },
    // Physical admit-or-lookup ordering for a checked request. The common
    // MoonBit relation decides whether a retained intent is the same request;
    // the callback may issue authority but must not start Compute. A racing
    // issuer is discarded when the atomic insert finds an existing Run.
    async admitOrLookupDefinition(identity, {namespaceId, lookupExpiresAt,
      issueDefinition, resultNames, sourceInventory, submission}, requestControl, publicationControl) {
      if (!text(namespaceId) || !instant(lookupExpiresAt) ||
          Date.parse(lookupExpiresAt) <= Date.now() ||
          typeof issueDefinition !== 'function') {
        fail('InvalidClientRequestAdmission');
      }
      if (sourceInventory !== undefined) validateSourceInventory(sourceInventory);
      ensureOpen();
      assertSubmissionCustody();
      const fields = checkedIdentity(identity, requestControl);
      assertKeyedInventoryRequest(sourceInventory, fields);
      const epochValidity = checkSubmissionBinding(fields, submission, requestControl);
      const retained = resolveOriginalDefinition(identity, fields, namespaceId,
        requestControl, publicationControl);
      if (retained !== undefined) {
        assertSourceInventory(retained, sourceInventory);
        return Object.freeze({inserted: false, ...retained});
      }
      refuseEpoch(epochValidity);
      const issued = await issueDefinition();
      const runDefinition = issued.runDefinition ?? issued;
      if (issued.runAdmissionEvidence?.sourceInventory !== sourceInventory) {
        fail('ClientRequestSourceInventoryMismatch');
      }
      return journal.acceptDefinition(identity, {namespaceId, runDefinition,
        runAdmissionEvidence: issued.runAdmissionEvidence,
        originalPlan: issued.originalPlan,
        originalInferRun: issued.originalInferRun,
        lookupExpiresAt, resultNames: issued.resultNames ?? resultNames, submission}, requestControl, publicationControl);
    },
    // One physical transaction applies the common MoonBit start decision.
    // A committed reservation records possible dispatch before any work. A
    // later caller must reconcile that Run rather than run Compute again.
    reserveDispatch(identity, {namespaceId, currentAuthorization},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(namespaceId) || typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunStartAction !== 'function') {
        fail('InvalidClientRunStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      return transact('start', 'ClientRunStartUnknown',
        error => typeof error?.code === 'string' &&
          (error.code.startsWith('ClientRequest') ||
            error.code.startsWith('ClientRun')), () => {
        const row = select.get(fields.authorityScopeCid, fields.requestId);
        if (row === undefined || row.namespace_id !== namespaceId) {
          fail('ClientRunStartDenied');
        }
        const retained = retainedIdentity(row, requestControl);
        const definition = retainedRunDefinition(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunStartAction(identity, retained,
          definition, row.run_definition_cid, row.dispatch_reserved === 1,
          currentAuthorization);
        if (action === 0) {
          if (reserve.run(fields.authorityScopeCid, fields.requestId)
            .changes !== 1) {
            fail('ClientRequestJournalCorrupt');
          }
          return Object.freeze({kind: 'reserved',
            ...admission({...row, revision: Number(row.revision) + 1})});
        }
        if (action === 1) {
          return Object.freeze({kind: 'reconcile', ...admission(row)});
        }
        fail(action === 3 ? 'ClientRequestIntentConflict' :
          action === 5 ? 'ClientRunStartDenied' :
          'ClientRequestJournalCorrupt');
      });
    },
    // The exact durable claim precedes the call that can start physical
    // Compute. A missing claim is safe to resume; a claim or legacy unknown
    // is never evidence that Compute did not run.
    reservePhysicalStart(identity, {namespaceId, ref, currentAuthorization,
      captureSourceOperation, localExecutionOwner},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(namespaceId) || !text(ref?.namespaceId) ||
          !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunPhysicalStartWithCancellationAction !==
            'function') {
        fail('InvalidClientRunPhysicalStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      let sourceOriginal, captureOriginal, captureReceiver;
      if (captureSourceOperation !== undefined) {
        if (sourceOperations === undefined) fail('ClientSourceOperationUnavailable');
        const {program, compiled, capture, store} = captureSourceOperation;
        const checkStore = store?.privateEvidenceWireLimit;
        if (typeof capture !== 'function' ||
            typeof checkStore !== 'function' ||
            typeof requestControl.clientProgramMatchesRequestIdentity !== 'function' ||
            requestControl.clientProgramMatchesRequestIdentity(program, identity) !== true) {
          fail('ForeignClientSourceOperation');
        }
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
        if (row === undefined) fail('ForeignClientSourceOperation');
        const definition = retainedRunDefinition(row, publicationControl, maxRunDefinitionWireBytes);
        publicationControl.checkClientCompiledRunOwner(compiled, program);
        publicationControl.checkClientCompiledRunDefinition(compiled, definition);
        // Existing same-Store active guard only; its numeric result is neither
        // the Source operation's capacity nor a private-evidence permission.
        Reflect.apply(checkStore, store, []);
        sourceOriginal = Object.freeze({ref: Object.freeze({...ref}), program, compiled,
          definition, identity, requestControl, publicationControl,
          // The same Owner may deliver its bounded method facade. Retain
          // that exact original, which dispatch receives, not the inaccessible
          // inner method table. Copies still fail the nominal Source check.
          journal: deliveredJournal, store, checkStore,
          requestId: fields.requestId, requestScopeCid: fields.logicalRequestScopeCid,
          intentCid: fields.intentFingerprintCid});
        captureOriginal = capture;
        captureReceiver = captureSourceOperation;
      }
      // Only the actual compiled effect-free Prepared original can qualify;
      // source text, a caller boolean or an empty local worker map cannot.
      let localOwnerProgram, localOwnerCompiled;
      if (localExecutionOwner !== undefined && ownedOriginal !== undefined) {
        const {program, compiled} = localExecutionOwner;
        try {
          if (requestControl.clientProgramMatchesRequestIdentity(program, identity) !== true) {
            fail('ForeignClientLocalExecutionOwner');
          }
          publicationControl.checkClientCompiledRunOwner(compiled, program);
          const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
          if (row === undefined) fail('ForeignClientLocalExecutionOwner');
          const definition = retainedRunDefinition(row, publicationControl, maxRunDefinitionWireBytes);
          publicationControl.checkClientCompiledRunDefinition(compiled, definition);
          publicationControl.checkClientCompiledLocalExecutionOwner(compiled, definition);
          const inferred = checked(requestControl.clientProgramComposedInferOccurrences(program));
          const serialized = requestControl.clientProgramSerializationOccurrences(program);
          if (requestControl.clientProgramAcquisitionCount(program) !== 0 ||
              !Array.isArray(inferred) || inferred.length !== 0 ||
              !Array.isArray(serialized) || serialized.length !== 0) {
            fail('ForeignClientLocalExecutionOwner');
          }
          localOwnerProgram = program; localOwnerCompiled = compiled;
        } catch (cause) {fail('ForeignClientLocalExecutionOwner', cause);}
      }
      const started = transact('physical_start', 'ClientRunPhysicalStartUnknown',
        error => typeof error?.code === 'string' &&
          (error.code.startsWith('ClientRun') ||
            error.code.startsWith('ClientRequest')), () => {
        const row = select.get(fields.authorityScopeCid, fields.requestId);
        if (row === undefined || row.namespace_id !== namespaceId ||
            ref.namespaceId !== namespaceId ||
            ref.authorityScopeCid !== fields.authorityScopeCid ||
            ref.runDefinitionCid !== row.run_definition_cid) {
          fail('ClientRunPhysicalStartDenied');
        }
        const retained = retainedIdentity(row, requestControl);
        const definition = retainedRunDefinition(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunPhysicalStartWithCancellationAction(
          identity, retained, definition, row.run_definition_cid,
          row.dispatch_reserved === 1,
          row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved === 0,
          currentAuthorization, row.cancellation_requested === 1);
        if (action === 0) {
          return false;
        }
        if (action !== 1) {
          fail(action === 3 ? 'ClientRequestIntentConflict' :
            action === 5 ? 'ClientRunPhysicalStartDenied' :
            'ClientRequestJournalCorrupt');
        }
        if (localOwnerProgram !== undefined) {
          publicationControl.checkClientCompiledRunOwner(localOwnerCompiled, localOwnerProgram);
          publicationControl.checkClientCompiledRunDefinition(localOwnerCompiled, definition);
          publicationControl.checkClientCompiledLocalExecutionOwner(localOwnerCompiled, definition);
          const receipt = captureOriginalLocalExecutionOwner(ownedOriginal);
          // Unsupported native ownership proof preserves ordinary execution;
          // its absent receipt cannot later be promoted into a stop witness.
          if (receipt !== undefined) {
            if (!validLocalExecutionOwnerReceipt(receipt)) fail('ForeignClientLocalExecutionOwner');
            localExecutionOwnerInsert.run(ref.namespaceId, ref.authorityScopeCid,
              ref.runDefinitionCid, receipt.token, receipt.anchor.identity,
              receipt.anchor.device, receipt.anchor.inode);
          }
        }
        if (reservePhysicalStart.run(ref.namespaceId,
          ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
        return true;
      });
      // No lookup/recovery API exposes this issuer. In particular a lost COMMIT
      // response throws before a scope can reach physical Source dispatch.
      if (started && sourceOriginal !== undefined) {
        Reflect.apply(captureOriginal, captureReceiver, [sourceOperations.issue(sourceOriginal)]);
      }
      return started;
    },
    // Persist the original checked activation BEFORE its first physical
    // attempt. An existing/uncertain entry never authorizes another send.
    persistOriginalKeyedLookupActivation(ref, {activation, identity, preparedEffect,
      compilation, compiled, runDefinition, graph, limits}, requestControl, publicationControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          runDefinition?.identity !== ref.runDefinitionCid ||
          typeof publicationControl?.keyedLookupActivationJournalRecord !== 'function' ||
          typeof publicationControl?.keyedLookupActivationJournalCurrent !== 'function') {
        fail('ForeignClientKeyedLookupOriginal');
      }
      publicationControl.checkClientCompiledEffectRunOwner(compiled, preparedEffect, compilation);
      publicationControl.checkClientCompiledRunDefinition(compiled, runDefinition);
      const record = publicationControl.keyedLookupActivationJournalRecord(
        activation, identity, compiled, runDefinition, graph, limits);
      if (!cid(record?.batchCid) || !cid(record?.slotCid) ||
          !Number.isSafeInteger(record?.batchIndex) || record.batchIndex < 0 ||
          !Number.isSafeInteger(record?.batchCount) || record.batchCount < 1 ||
          record.batchIndex >= record.batchCount || typeof record.wire !== 'string') {
        fail('ForeignClientKeyedLookupOriginal');
      }
      const current = () => {
        ensureOpen();
        if (publicationControl.keyedLookupActivationJournalCurrent(
          activation, identity, compiled, runDefinition, graph) !== true) {
          fail('ForeignClientKeyedLookupOriginal');
        }
      };
      current();
      transact('keyed_lookup_activation', 'ClientKeyedLookupActivationUnknown',
        error => ['ForeignClientKeyedLookupOriginal', 'ClientRunPhysicalStartDenied',
          'ClientKeyedLookupActivationUnresolved', 'ClientRequestJournalCorrupt'].includes(error?.code), () => {
          const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
          if (row === undefined || requestControl.clientRequestRelation(identity,
                retainedIdentity(row, requestControl)) !== 1 ||
              row.run_definition_wire !== runDefinition.wire ||
              row.dispatch_reserved !== 1 || row.physical_start_reserved !== 1 ||
              row.pre_dispatch_failure_confirmed !== 0 || row.cancellation_requested !== 0) {
            fail('ClientRunPhysicalStartDenied');
          }
          current();
          const prior = (keyedLookupPrior ??= database.prepare(`SELECT 1 AS present FROM client_keyed_lookup_originals
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ? AND call_slot_cid = ?`)).get(ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.slotCid);
          if (prior !== undefined) fail('ClientKeyedLookupActivationUnresolved');
          const batch = (keyedLookupBatch ??= database.prepare(`SELECT COUNT(*) AS n,
    COUNT(CASE WHEN page_wire IS NULL THEN 1 END) AS pending FROM client_keyed_lookup_originals
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ? AND batch_plan_cid = ?`)).get(ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.batchCid);
          if (!Number.isSafeInteger(batch.n) || batch.n !== record.batchIndex) {
            fail('ClientRequestJournalCorrupt');
          }
          if (batch.pending !== 0) fail('ClientKeyedLookupActivationUnresolved');
          (keyedLookupInsert ??= database.prepare(`INSERT INTO client_keyed_lookup_originals
    (namespace_id, authority_scope_cid, run_definition_cid, batch_plan_cid,
      call_slot_cid, batch_index, batch_count, activation_wire, page_wire)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)`)).run(ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.batchCid, record.slotCid,
            record.batchIndex, record.batchCount, record.wire);
          current();
        });
      // A failed post-COMMIT current check still leaves the original durable
      // entry. It cannot turn into permission to retry the physical attempt.
      current();
      return record;
    },
    // A completed captured page replaces only the SAME unresolved activation.
    // Exact original wires and the checked nominal page are both required;
    // neither row absence nor a lost commit permits another physical read.
    persistOriginalKeyedLookupPage(ref, {page, keyedRequest, identity, preparedEffect,
      compilation, compiled, runDefinition, graph, limits, activationRecord}, requestControl, publicationControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          runDefinition?.identity !== ref.runDefinitionCid ||
          typeof activationRecord?.wire !== 'string' ||
          typeof publicationControl?.keyedLookupPageJournalRecord !== 'function' ||
          typeof publicationControl?.keyedLookupPageJournalCurrent !== 'function') {
        fail('ForeignClientKeyedLookupPage');
      }
      publicationControl.checkClientCompiledEffectRunOwner(compiled, preparedEffect, compilation);
      publicationControl.checkClientCompiledRunDefinition(compiled, runDefinition);
      const record = publicationControl.keyedLookupPageJournalRecord(page, keyedRequest,
        identity, compiled, runDefinition, graph, limits);
      if (!cid(record?.batchCid) || !cid(record?.slotCid) || !cid(record?.activationCid) ||
          typeof record.wire !== 'string' || record.batchCid !== activationRecord.batchCid ||
          record.slotCid !== activationRecord.slotCid || record.batchIndex !== activationRecord.batchIndex ||
          !Number.isSafeInteger(activationRecord.batchCount) || activationRecord.batchCount <= record.batchIndex ||
          !Number.isSafeInteger(record.batchIndex) || record.batchIndex < 0) {
        fail('ForeignClientKeyedLookupPage');
      }
      const current = () => {
        ensureOpen();
        if (publicationControl.keyedLookupPageJournalCurrent(page, keyedRequest, identity,
            compiled, runDefinition, graph) !== true) fail('ForeignClientKeyedLookupPage');
      };
      current();
      transact('keyed_lookup_page', 'ClientKeyedLookupPageUnknown',
        error => ['ForeignClientKeyedLookupPage', 'ClientRunPhysicalStartDenied',
          'ClientKeyedLookupPageUnresolved'].includes(error?.code), () => {
          const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
          if (row === undefined || requestControl.clientRequestRelation(identity,
                retainedIdentity(row, requestControl)) !== 1 ||
              row.run_definition_wire !== runDefinition.wire || row.dispatch_reserved !== 1 ||
              row.physical_start_reserved !== 1 || row.pre_dispatch_failure_confirmed !== 0 ||
              row.cancellation_requested !== 0) fail('ClientRunPhysicalStartDenied');
          current();
          if ((keyedLookupAdopt ??= database.prepare(`UPDATE client_keyed_lookup_originals
    SET page_wire = ? WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND batch_plan_cid = ? AND call_slot_cid = ? AND
      batch_index = ? AND batch_count = ? AND activation_wire = ? AND page_wire IS NULL`)).run(record.wire, ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.batchCid, record.slotCid, record.batchIndex,
            activationRecord.batchCount, activationRecord.wire).changes !== 1) {
            fail('ClientKeyedLookupPageUnresolved');
          }
          current();
        });
      current();
      return record;
    },
    lookupOriginalSourceOperation(ref, occurrence) {
      if (sourceOperations === undefined) fail('ClientSourceOperationUnavailable');
      return sourceOperations.lookup(ref, occurrence);
    },
    // Readiness only: the original physical-start transaction still issues
    // each live scope. This value cannot bind a Run or enable a POST.
    sourceOperationConfigured: sourceOperations !== undefined,
    // Persist the common cancellation decision under the physical-start lock.
    // The Host observes publication separately; a racing commit can still win.
    requestCancellation(ref, {currentAuthorization, publicationCommitted},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof publicationCommitted !== 'boolean') {
        fail('InvalidClientRunCancellation');
      }
      return transact('cancel', 'ClientRunCancellationUnknown',
        error => error?.code === 'ClientRunCancellationDenied', () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined) fail('ClientRunCancellationDenied');
        retainedIdentity(row, requestControl);
        const facts = retainedRunFacts(row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl);
        const action = requestControl.clientRunCancellationAction(facts.runDefinition,
          ref.runDefinitionCid, currentAuthorization,
          publicationCommitted || facts.preDispatchFailureConfirmed ||
            facts.physicalCloseConfirmed &&
              facts.observedTerminalOutcome !== null,
          facts.cancellationRequested);
        if (![0, 1, 2].includes(action)) fail('ClientRunCancellationDenied');
        if (action === 0) {
          database.prepare(`UPDATE client_requests SET
            cancellation_requested = 1, revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(ref.namespaceId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
        return Object.freeze({ref: admission(row).ref,
          kind: ['accepted', 'already_requested', 'already_terminal'][action],
          revision: Number(row.revision) + (action === 0 ? 1 : 0)});
      });
    },
    // Persist the immutable operation before touching the Model fence journal.
    // Pending custody is unknown, not acceptance. The final outcome and Run
    // cancellation flag commit together in this existing physical owner.
    recordCancellationOperation(ref, {cancelId, expectedRevision,
      currentAuthorization, publicationCommitted, modelCancellationOwner},
      requestControl, publicationControl) {
      ensureOpen();
      const cancelRef = ownedCancellationRef({...ref, cancelId, expectedRevision});
      if (!validCancellationRef(cancelRef) || typeof currentAuthorization !== 'boolean' ||
          typeof publicationCommitted !== 'boolean') fail('InvalidClientCancellationOperation');
      if (!currentAuthorization) fail('ClientCancellationDenied');
      const pending = transact('cancel_admission', 'ClientCancellationUnknown',
        cancellationKnownFailure, () => {
          const custodyCount = assertCancellationCustody();
          const {row, facts} = cancellationDefinition(ref, requestControl, publicationControl);
          const identity = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
          const record = cancellationSelect.get(ref.namespaceId, ref.authorityScopeCid, cancelId);
          const retained = record === undefined ? undefined :
            cancellationReadmission(record, requestControl, publicationControl);
          const action = cancellationAction(identity, retained?.identity, facts, row,
            currentAuthorization, publicationCommitted, requestControl);
          if (retained !== undefined) return {...retained, facts, action};
          if (assertSubmissionCustody() + custodyCount >= maxRecords) {
            rejectCancellation('ClientRequestJournalCapacity', 'refused', 'admission_capacity');
          }
          cancellationInsert.run(ref.namespaceId, ref.authorityScopeCid, cancelId,
            ref.runDefinitionCid, expectedRevision, requestControl.clientCancellationIntentCid(identity));
          database.prepare(`UPDATE client_cancellation_custody SET issued_count = issued_count + 1
            WHERE singleton = 1`).run();
          return {identity, cancelRef, outcome: undefined, facts, action};
        });
      if (pending.outcome !== undefined) return Object.freeze({cancellation: pending.outcome, recorded: false});
      const originalRunWire = pending.facts.runAdmissionEvidence?.modelOriginalRunWire;
      if (originalRunWire !== undefined && !publicationCommitted &&
          !pending.facts.preDispatchFailureConfirmed &&
          !(pending.facts.physicalCloseConfirmed && pending.facts.observedTerminalOutcome !== null)) {
        try {
          if (typeof modelCancellationOwner?.fenceRunCancellation !== 'function' ||
              typeof modelCancellationOwner?.modelCancellationFenced !== 'function') {
            fail('ClientCancellationModelFenceUnavailable');
          }
          // Only the checkpoint Owner can establish the fence, using the
          // retained original input rather than the current Host configuration.
          modelCancellationOwner.fenceRunCancellation({originalRunWire});
          const runId = publicationControl.runDefinitionRunId(pending.facts.runDefinition);
          if (modelCancellationOwner.modelCancellationFenced(runId, ref.runDefinitionCid) !== true) {
            fail('ClientCancellationModelFenceUnconfirmed');
          }
        } catch (cause) { fail('ClientCancellationUnknown', cause); }
      }
      return transact('cancel_commit', 'ClientCancellationUnknown', cancellationKnownFailure, () => {
        assertCancellationCustody();
        const record = cancellationSelect.get(ref.namespaceId, ref.authorityScopeCid, cancelId);
        if (record === undefined) fail('ClientRequestJournalCorrupt');
        const retained = cancellationReadmission(record, requestControl, publicationControl);
        const {row, facts} = cancellationDefinition(ref, requestControl, publicationControl);
        cancellationAction(pending.identity, retained.identity, facts, row,
          currentAuthorization, publicationCommitted, requestControl);
        if (retained.outcome !== undefined) return Object.freeze({cancellation: retained.outcome, recorded: false});
        const action = requestControl.clientRunCancellationAction(facts.runDefinition,
          ref.runDefinitionCid, currentAuthorization,
          publicationCommitted || facts.preDispatchFailureConfirmed ||
            facts.physicalCloseConfirmed && facts.observedTerminalOutcome !== null,
          facts.cancellationRequested);
        if (![0, 1, 2].includes(action)) fail('ClientCancellationDenied');
        if (action === 0 && row.revision >= 2147483647) fail('ClientCancellationRevisionConflict');
        if (action === 0) database.prepare(`UPDATE client_requests SET
          cancellation_requested = 1, revision = revision + 1
          WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`).run(
          ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
        const outcome = Object.freeze({ref: admission(row).ref, cancelRef: retained.cancelRef,
          kind: ['accepted', 'already_requested', 'already_terminal'][action],
          revision: Number(row.revision) + (action === 0 ? 1 : 0)});
        const wire = canonicalValueJson(outcome);
        const checksum = `sha256:${createHash('sha256').update(wire).digest('hex')}`;
        if (database.prepare(`UPDATE client_cancellation_operations SET outcome_wire = ?, outcome_cid = ?
          WHERE namespace_id = ? AND authority_scope_cid = ? AND cancel_id = ?
            AND outcome_wire IS NULL`).run(wire, checksum, ref.namespaceId,
          ref.authorityScopeCid, cancelId).changes !== 1) fail('ClientRequestJournalCorrupt');
        return Object.freeze({cancellation: outcome, recorded: true});
      });
    },
    // Per-invocation public facts are deliberately not persisted as operation
    // outcomes. Refused consumes no identity; another invocation can already
    // own the same cancellation. Pending custody and uncertain COMMIT never
    // produce this certificate. The durable original remains unchanged.
    recordCancellationAttempt(ref, {attemptRef, ...options}, requestControl, publicationControl) {
      ensureOpen();
      if (attemptRef === null || typeof attemptRef !== 'object' ||
          Object.keys(attemptRef).sort().join(',') !== 'attemptId,operation' ||
          attemptRef.operation !== 'cancel' || !text(attemptRef.attemptId) ||
          !attemptRef.attemptId.isWellFormed() ||
          !validCancellationRef({...ref, cancelId: options.cancelId,
            expectedRevision: options.expectedRevision}) ||
          typeof options.currentAuthorization !== 'boolean') {
        fail('InvalidClientCancellationAttempt');
      }
      const ownedAttempt = Object.freeze({operation: 'cancel', attemptId: attemptRef.attemptId});
      if (!options.currentAuthorization) return Object.freeze({
        kind: 'refused', attemptRef: ownedAttempt,
        guarantee: 'attempt_uncommitted_unconsumed', reason: 'authorization',
      });
      const ticket = {};
      const previousAttempt = activeCancellationAttempt;
      activeCancellationAttempt = ticket;
      try {
        const result = journal.recordCancellationOperation(ref, options, requestControl, publicationControl);
        return Object.freeze({kind: result.cancellation.kind === 'accepted'
          ? 'accepted' : 'already_satisfied', attemptRef: ownedAttempt,
          cancellation: result.cancellation, recorded: result.recorded});
      } catch (error) {
        const rejection = cancellationRejections.get(error);
        if (rejection === undefined || rejection.ticket !== ticket) throw error;
        return Object.freeze({kind: rejection.kind, reason: rejection.reason, attemptRef: ownedAttempt,
          ...(rejection.kind === 'refused' ? {guarantee: 'attempt_uncommitted_unconsumed'} : {}),
          cancelRef: ownedCancellationRef({...ref, cancelId: options.cancelId,
            expectedRevision: options.expectedRevision})});
      } finally { activeCancellationAttempt = previousAttempt; }
    },
    // An exact, authorized observation. It never fences, starts execution or
    // completes a pending operation; absent custody is not proof of rejection.
    lookupCancellationOperation(cancelRef, {currentAuthorization},
      requestControl, publicationControl) {
      ensureOpen();
      if (!validCancellationRef(cancelRef) || typeof currentAuthorization !== 'boolean') {
        fail('InvalidClientCancellationLookup');
      }
      if (!currentAuthorization) fail('ClientCancellationDenied');
      return transact('cancel_lookup', 'ClientCancellationLookupUnknown', cancellationKnownFailure, () => {
        assertCancellationCustody();
        const {row, facts} = cancellationDefinition(cancelRef, requestControl, publicationControl);
        const requested = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
        const record = cancellationSelect.get(cancelRef.namespaceId, cancelRef.authorityScopeCid, cancelRef.cancelId);
        if (record === undefined) return Object.freeze({kind: 'unknown',
          cancelRef: ownedCancellationRef(cancelRef)});
        const retained = cancellationReadmission(record, requestControl, publicationControl);
        cancellationAction(requested, retained.identity, facts, row, currentAuthorization, false, requestControl);
        return retained.outcome === undefined ? Object.freeze({kind: 'unknown', cancelRef: retained.cancelRef}) :
          Object.freeze({kind: 'found', cancellation: retained.outcome});
      });
    },
    // This observation is only available to the SAME original Store owner
    // holding its stable lease. It never starts work, marks a stop or claims
    // cleanup. The caller must still inspect publication and revalidate this
    // nominal frame before recording the existing terminal observation.
    observeStoppedLocalExecutionOwner(ref, originalFrame) {
      ensureOpen();
      const original = retainRunStateFrame(originalFrame, ref);
      if (localExecutionOwnerLookup === undefined) return false;
      const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      if (!sameRunStateRow(row, original.row)) fail('ClientRunStopObservationChanged');
      if (row.physical_start_reserved !== 1 || row.physical_close_confirmed !== 0 ||
          row.observed_terminal_outcome !== null) return false;
      const stored = localExecutionOwnerLookup.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      if (stored === undefined) return false;
      const receipt = {token: stored.owner_token, anchor: {identity: stored.anchor_identity,
        device: stored.anchor_device, inode: stored.anchor_inode}};
      if (!validLocalExecutionOwnerReceipt(receipt)) return false;
      const stopped = originalLocalExecutionOwnerStopped(ownedOriginal, receipt);
      // The native owner observation must not make a stale frame current.
      if (!sameRunStateRow(selectRef.get(ref.namespaceId, ref.authorityScopeCid,
        ref.runDefinitionCid), original.row)) fail('ClientRunStopObservationChanged');
      return stopped === true;
    },
    // Only original execution custody may report a completed physical close.
    // A successor needs the retained native lease, publication and cleanup
    // observations; an empty worker map never establishes any of them.
    markPhysicalClose(ref, terminalOutcome = null, originalFrame) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          terminalOutcome !== null &&
            !['failed', 'cancelled'].includes(terminalOutcome)) {
        fail('InvalidClientRunStopObservation');
      }
      const original=originalFrame===undefined?undefined:retainRunStateFrame(originalFrame,ref);
      return transact('stop_observation', 'ClientRunStopObservationUnknown',
        error => ['ClientRunStopObservationDenied','ClientRunStopObservationChanged'].includes(error?.code), () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if(original!==undefined && !sameRunStateRow(row,original.row)) {
          fail('ClientRunStopObservationChanged');
        }
        if (row === undefined || row.physical_start_reserved !== 1 ||
            row.physical_close_confirmed === 1 &&
              row.observed_terminal_outcome !== terminalOutcome) {
          fail('ClientRunStopObservationDenied');
        }
        if (row.physical_close_confirmed === 0) {
          const changed=database.prepare(`UPDATE client_requests SET
            physical_close_confirmed = 1, observed_terminal_outcome = ?,
            revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ? AND physical_start_reserved = 1 AND
              physical_close_confirmed = 0`).run(terminalOutcome,
            ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
          if(Number(changed.changes)!==1)fail('ClientRunStopObservationChanged');
        }
      });
    },
    // Physical Host evidence only: a failure before invoking Site execution
    // is confirmed. A lost reply or absent worker cannot call this method.
    markPreDispatchFailure(ref) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunFailureObservation');
      }
      return transact('failure_observation',
        'ClientRunFailureObservationUnknown',
        error => typeof error?.code === 'string' &&
          (error.code.startsWith('ClientRun') ||
            error.code.startsWith('ClientRequest')), () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.dispatch_reserved !== 1 ||
            row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved !== 0) {
          fail('ClientRunFailureObservationDenied');
        }
        if (row.pre_dispatch_failure_confirmed === 0 &&
            confirmPreDispatchFailure.run(ref.namespaceId,
              ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
      });
    },
    // Keep the owner-issued `needs_reconciliation` state of a started Run
    // whose Effect outcomes are unknown. It is recorded once and never
    // replaced: a different state for the same Run is a conflict.
    recordReconciliationState(ref, wire) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) || typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > maxRunDefinitionWireBytes) {
        fail('InvalidClientRunReconciliation');
      }
      let state;
      try { state = JSON.parse(wire); }
      catch { fail('InvalidClientRunReconciliation'); }
      if (state?.status !== 'needs_reconciliation' ||
          state?.next_action?.kind !== 'reconcile') {
        fail('InvalidClientRunReconciliation');
      }
      return transact('reconciliation', 'ClientRunReconciliationUnknown',
        error => typeof error?.code === 'string' &&
          error.code.startsWith('ClientRun'), () => {
        const row = selectedRequestStatement(database.prepare(`SELECT physical_start_reserved,
          reconciliation_state_wire FROM client_requests
          WHERE namespace_id = ? AND authority_scope_cid = ? AND
            run_definition_cid = ?`), 'run-definition', true).get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.physical_start_reserved !== 1) {
          fail('ClientRunReconciliationDenied');
        }
        if (row.reconciliation_state_wire !== null &&
            row.reconciliation_state_wire !== wire) {
          fail('ClientRunReconciliationConflict');
        }
        if (row.reconciliation_state_wire === null) {
          database.prepare(`UPDATE client_requests SET
            reconciliation_state_wire = ?, revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(wire, ref.namespaceId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
      });
    },
    lookupReconciliationState(ref) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunLookup');
      }
      const row = selectedRequestStatement(database.prepare(`SELECT reconciliation_state_wire
        FROM client_requests WHERE namespace_id = ? AND
          authority_scope_cid = ? AND run_definition_cid = ?`), 'run-definition', true).get(
        ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      return row?.reconciliation_state_wire ?? undefined;
    },
    close() {
      closed = true;
      if (!databaseClosed) {
        initializationCleanup.close();
        databaseClosed = true;
      }
      // Observation cleanup is optional and never changes Run cleanup facts.
      // Its projection retains the handle and may retry after this close.
      try { closeObservationStorage(); }
      catch { /* The observation projection owns this separate connection. */ }
    },
  });
  const deliveredJournal = guardJournalCurrentness(journal, primaryCurrent);
  applyOriginal(originalJournalCustodySet, originalJournalCustodies, [deliveredJournal, () =>
    Object.freeze({journalClosed: closed, databaseClosed,
      observationAttempted: observationStorageAttempted, observationDatabaseClosed})]);
  if (!existed) syncDirectory(root);
  return deliveredJournal;
  } catch (error) {
    throwSqliteInitializationFailure(initializationCleanup, error, 'client-request-journal');
  }
}
