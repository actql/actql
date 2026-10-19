// Physical durable storage for an owner-issued Client request and Run ref.
// MoonBit supplies and re-admits the identity and decides intent conflicts.
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {prepareInstalledRunStateObservation, issueInstalledRunControlObservation}
  from '../host-common/run-state-observation.mjs';
import {createHash, createHmac, randomBytes, timingSafeEqual} from 'node:crypto';
import {closeSync, constants, existsSync, fstatSync, fsyncSync, lstatSync,
  mkdirSync, openSync, readSync,
  realpathSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {types as utilTypes} from 'node:util';
import {createSqliteTransaction, throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {inspectSqliteSnapshot, inspectJournalDirectory} from '../host-common/sqlite-format-inspection.mjs';
import {snapshotSqliteSchemaReadLimits, snapshotSqliteSchemaSqlSupport}
  from '../host-common/sqlite-schema-resource-bounds.mjs';
import {openClientObservationStorage} from './client-observation-journal.mjs';
import {isHostObservationProjection} from '../host-common/observation.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {BOUND_SOURCE_INVENTORY, validBoundSourceOccurrence} from './ordinary-source-binding.mjs';
import {valuesExecutionContextCid} from './local-values-capacity.mjs';
import {sourceOperationTable, inspectClientSourceOperationStorage,
  clientSourceOperationStorage, snapshotClientSourceOperationLimits} from './client-source-operation.mjs';
import {sameSubmissionRef, validSubmissionRef, validSubmissionName, validSubmissionOutcome, validStoredSubmissionOutcome} from '../../packages/client-wire/index.mjs';

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
const operationDefineProperty = Object.defineProperty;
const operationKeys = Reflect.ownKeys, operationFreeze = Object.freeze;
const OperationError = Error;
const originalJournalCustodies = new WeakMap();
const originalJournalCustodyGet = WeakMap.prototype.get;
const originalJournalCustodySet = WeakMap.prototype.set;
const facilityDescriptor = Object.getOwnPropertyDescriptor;
const facilityDatabase = DatabaseSync, facilityStatement = StatementSync;
const facilityOperations = Object.freeze([
  [facilityDatabase.prototype, 'open'], [facilityDatabase.prototype, 'close'],
  [facilityDatabase.prototype, 'prepare'], [facilityDatabase.prototype, 'exec'],
  [facilityStatement.prototype, 'get'], [facilityStatement.prototype, 'run'],
  [facilityStatement.prototype, 'iterate'],
].map(([receiver, name]) => Object.freeze({receiver, name,
  property: facilityDescriptor(receiver, name)})));

// Fixed namespace forwarder for the selected startup's actual node:sqlite
// originals. This observes correspondence/currentness, not capacity, a new
// installation or authority. No caller callback or equal label is a native
// constructor, and restoration after a detected change cannot revive it.
let facilityChanged = false;
export function assertOriginalClientRequestJournalFacilityCurrent(database, statement) {
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
  const names = ['maxCalls', 'maxPreparedStatements', 'maxSqlBytes', 'maxTotalSqlBytes'];
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
  const names = ['maxStatementCalls', 'maxParameters', 'maxParameterBytes', 'maxResultRows'];
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
  if (!Number.isSafeInteger(limits.maxStatementCalls * limits.maxParameterBytes)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  return Object.freeze(limits);
}

function boundJournalOperations(journal, maximum, assertCurrent) {
  if (maximum === undefined) return journal;
  let attempts = 0;
  // Keep one refusal original, rather than allocate another error/stack for
  // every call after exhaustion. A failed argument/current check still used
  // this operation attempt; SQL counters alone cannot bound that prefix work.
  const failure = new OperationError('ClientRequestJournalOperationUnavailable');
  operationDefineProperty(failure, 'code', {value: 'ClientRequestJournalOperationUnavailable',
    enumerable: true});
  operationFreeze(failure);
  const enter = () => {
    if (attempts >= maximum) throw failure;
    attempts++;
    assertCurrent?.();
  };
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

// One lifetime support counter for this Journal's two original writable
// connections. A finite value is not physical WAL/mapping backing, an issuer,
// a lock against another writer, or a new Run/resource Ledger. The selected
// facility must separately cover this whole bound before its first acquisition.
function boundedJournalWalFrames(maxFrames, sourceBytes, maxDatabaseBytes) {
  if (maxFrames === undefined) return undefined;
  const integer = BigInt, floor = Math.floor, ceil = Math.ceil;
  const maximum = integer(maxFrames);
  // The original DB and WAL are jointly bounded before cold native inspection.
  // Reserve the worst original WAL at SQLite's minimum supported page size;
  // a fresh file or later checkpoint does not replenish this lifetime amount.
  let reserved = integer(sourceBytes) / 536n;
  if (reserved > maximum) fail('ClientRequestJournalWalUnavailable');
  const character = String.prototype.charCodeAt;
  let originalPage, transactionFrames;
  const amount = units => transactionFrames === undefined ? 0n :
    integer(units) * transactionFrames;
  const check = units => {
    const frames = amount(units);
    if (frames > maximum - reserved) fail('ClientRequestJournalWalUnavailable');
    return frames;
  };
  return Object.freeze({
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
    beforePrepare() { check(1); },
    beforeStatement() {
      // Only the fixed page-size probe precedes configuration. Later extent
      // and temporary-storage operations keep their conservative charges.
      reserved += check(1);
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
      reserved += check(statements);
    },
  });
}

// Bound compilation attempts and account every prepared wrapper as retained
// until this primary connection's real lifetime ends. Native failure and GC do
// not refund an attempt. This is not a bound on bind values, result rows, native
// heap/cache/WAL, or the separate observation connection, and issues no capacity.
// A selected execution boundary additionally limits scalar bind extent and
// calls, and replaces metadata All() with a bounded original native cursor.
function boundedPrimarySql(connection, limits, executionLimits, assertCurrent, walFrames) {
  const prepare = connection.prepare, exec = connection.exec;
  const buffer = Buffer, byteLength = buffer.byteLength;
  const isTransaction = Object.getOwnPropertyDescriptor(connection, 'isTransaction')?.get;
  if (typeof prepare !== 'function' || typeof exec !== 'function' || typeof byteLength !== 'function' ||
      typeof isTransaction !== 'function') fail('ClientRequestJournalSqlUnavailable');
  let calls = 0, prepared = 0, bytes = 0;
  let statementCalls = 0;
  const statements = [], cursors = [];
  let operationActive = false;
  const beginOperation = () => {
    if (executionLimits === undefined) return;
    // The selected one-connection recipe must not start another preparation
    // or execution from a current/native callback while this call is live.
    // Latch before those callbacks, not after native acquisition. This is a
    // synchronous operation fence, not native close or returned byte credit.
    if (operationActive) fail('ClientRequestJournalSqlCleanupPending');
    operationActive = true;
  };
  const endOperation = () => { operationActive = false; };
  const consume = (sql, isPrepare) => {
    assertCurrent?.();
    if (cursors.length !== 0) fail('ClientRequestJournalSqlCleanupPending');
    if (typeof sql !== 'string' || sql.length > limits.maxSqlBytes ||
        calls >= limits.maxCalls || isPrepare && prepared >= limits.maxPreparedStatements) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    const size = applyOriginal(byteLength, buffer, [sql, 'utf8']);
    if (!Number.isSafeInteger(size) || size < sql.length ||
        size > limits.maxSqlBytes || size > limits.maxTotalSqlBytes - bytes) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    calls++; bytes += size;
    if (isPrepare) prepared++;
  };
  const operands = values => {
    assertCurrent?.();
    if (cursors.length !== 0) fail('ClientRequestJournalSqlCleanupPending');
    if (statementCalls >= executionLimits.maxStatementCalls) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    // Attempts, including refused operands and native failures, never refill.
    statementCalls++;
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
  const wrap = statement => {
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
          operands(values); walFrames?.beforeStatement();
          return applyOriginal(get, statement, values);
        } finally { endOperation(); }
      },
      run(...values) {
        beginOperation();
        try {
          operands(values); walFrames?.beforeStatement();
          return applyOriginal(run, statement, values);
        } finally { endOperation(); }
      },
      all(...values) {
        beginOperation();
        try {
          operands(values);
          walFrames?.beforeStatement();
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
  return Object.freeze({database: Object.freeze({
    prepare(sql) {
      beginOperation();
      try {
        consume(sql, true); walFrames?.beforePrepare();
        return wrap(applyOriginal(prepare, connection, [sql]));
      } finally { endOperation(); }
    },
    exec(sql) {
      beginOperation();
      try {
        consume(sql, false); walFrames?.beforeExec(sql);
        return applyOriginal(exec, connection, [sql]);
      } finally { endOperation(); }
    },
    get isTransaction() { return applyOriginal(isTransaction, connection, []); },
  }), retireClosedNativeAliases() { statements.length = cursors.length = 0; }});
}

function boundJournalDatabaseExtent(database, maxDatabaseBytes, executionLimits, walFrames) {
  if (maxDatabaseBytes === undefined) return;
  const page = database.prepare('PRAGMA page_size').get().page_size;
  if (!Number.isSafeInteger(page) || page < 512 || page > 65536 ||
      (page & (page - 1)) !== 0) {
    fail('ClientRequestJournalDatabaseUnavailable');
  }
  const pages = Math.floor(maxDatabaseBytes / page);
  if (pages < 1 || pages > 4294967294) fail('ClientRequestJournalDatabaseUnavailable');
  // max_page_count has PragFlg_NeedSchema in the selected SQLite. Configure
  // this same non-refilling WAL counter from the observed page geometry, then
  // select MEMORY before that pragma can load schema and its internal reader.
  // Neither operation supplies backing or acknowledges another connection.
  walFrames?.configure(page);
  selectJournalTemporaryStorage(database, executionLimits);
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
function journalDirectoryEntries(directory, maxInspectionEntries) {
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
  const close = () => {
    if (original === undefined) return;
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
    const first = cause;
    let latest = cause;
    const status = () => Object.freeze({pending: original !== undefined,
      errors: Object.freeze(first === latest ? [first] : [first, latest])});
    const retry = () => {
      try { close(); } catch (error) { latest = error; }
      return status();
    };
    const carrier = Object.assign(new Error('ClientRequestJournalInspectionCleanupPending',
      {cause: failed ? primary : cause}), {
      code: 'ClientRequestJournalInspectionCleanupPending',
      primaryFailure: failed ? primary : cause,
      cleanupHandle: Object.freeze({status, retry}),
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
        value.acquisitions[0].checkedSource.requirementCid ===
          value.acquisitions[1].checkedSource.requirementCid) fail('InvalidClientSourceInventory');
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

function admissionEvidenceShape(value, updateOriginalControl) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  if (Object.keys(value).some(key => !['authorization', 'prepared',
    'sourceInventory', 'resultPolicyOriginal', 'modelOriginalRunWire',
    'valuesHostPolicyOriginal', 'logicalPlanOriginal', 'updateTargetRunOriginal',
    'submittedIntentCid', 'effectOriginalRunWire', 'inferRunOriginal'].includes(key)) ||
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
  if (!admissionEvidenceShape(value, updateOriginalControl)) fail('InvalidClientRunAdmissionEvidence');
  const wire = JSON.stringify(value);
  if (Buffer.byteLength(wire) > maxBytes) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  return wire;
}

function retainedEvidence(row, updateOriginalControl) {
  if (row.run_admission_evidence_json === null) return undefined;
  let value;
  try { value = JSON.parse(row.run_admission_evidence_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
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

function checkStoredPlanOriginal(value, definition, programCid, control, maxBytes) {
  if (!logicalPlanOriginalShape(value) ||
      Buffer.byteLength(value.compiledPlanWire) > maxBytes ||
      Buffer.byteLength(value.planViewWire) > maxBytes) {
    fail('InvalidClientRunPlanOriginal');
  }
  if (typeof control?.readStoredRunPlanOriginal !== 'function') {
    fail('ClientRequestPlanEvidenceUnavailable');
  }
  const wire = control.readStoredRunPlanOriginal(value, definition, programCid,
    {maxWireBytes: maxBytes, maxNodes: 4096, maxDepth: 64});
  if (wire !== value.planViewWire) fail('InvalidClientRunPlanOriginal');
}

function retainedResultNames(row) {
  if (row.result_names_json === null) return undefined;
  let names;
  try { names = JSON.parse(row.result_names_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  if (!Array.isArray(names) || names.length > 100 ||
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
  if (runAdmissionEvidence?.logicalPlanOriginal !== undefined) {
    try { checkStoredPlanOriginal(runAdmissionEvidence.logicalPlanOriginal,
      runDefinition, row.program_definition_cid, publicationControl, maxWireBytes); }
    catch (cause) {
      if (cause?.code === 'ClientRequestPlanEvidenceUnavailable') throw cause;
      if (cause?.code === 'ClientOperationUnavailable') {
        fail('ClientRequestPlanEvidenceUnavailable', cause);
      }
      if (cause instanceof TypeError || cause instanceof SyntaxError ||
          ['InvalidClientRunPlanOriginal', 'MoonBitHostFailure',
            'RunHostOriginalMapRejected'].includes(cause?.code)) {
        fail('ClientRequestJournalCorrupt', cause);
      }
      fail('ClientRequestPlanReadUnknown', cause);
    }
  }
  return Object.freeze({
    runDefinition,
    programDefinitionCid: row.program_definition_cid,
    resultNames: retainedResultNames(row),
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
  // Startup integrity inspection has no retained JS row inventory. Ordinary
  // resolution uses the indexed key and the transaction-maintained singleton.
  if (database.prepare('SELECT COUNT(*) AS n FROM client_submission_names').get().n !==
      custody[0].retained_count) fail('UnknownClientRequestJournalFormat');
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
  const records = database.prepare('SELECT COUNT(*) AS n FROM client_cancellation_operations').get().n;
  const custody = database.prepare('SELECT singleton, issued_count FROM client_cancellation_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(cancellationColumns) ||
      JSON.stringify(custodyFields) !== JSON.stringify(['issued_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || custody[0].issued_count < 0 ||
      custody[0].issued_count !== records) fail('UnknownClientRequestJournalFormat');
}

// A read-only SQLite connection can still create -shm beside a WAL database.
// Inspect a private copy and refuse a source that changes during inspection.
function inspectJournalSnapshot(directory, databasePath, markerPath, maxInspectionEntries, maxInspectionBytes,
  primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent) {
  const entries = journalDirectoryEntries(directory, maxInspectionEntries);
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
    const fields = database.prepare('PRAGMA table_info(client_requests)')
      .all().map(field => field.name).sort();
    if (JSON.stringify(fields) !== JSON.stringify(journalColumns)) {
      fail('UnknownClientRequestJournalFormat');
    }
    inspectCancellationStorage(database, enabled);
    inspectSubmissionStorage(database, submissionEnabled);
    inspectEpochStorage(database, epochEnabled);
    inspectIntentStorage(database, intentEnabled);
    inspectIntentRetirementStorage(database, retirementEnabled);
    inspectRestartStorage(database, restartEnabled);
    inspectNameStorage(database, nameEnabled);
    inspectClientSourceOperationStorage(database);
  }, {code: 'UnknownClientRequestJournalFormat', maxSourceBytes: maxInspectionBytes,
    unavailableCode: 'ClientRequestJournalInspectionUnavailable',
    schemaReadLimits: primarySchemaLimits,
    schemaSqlSupport: primarySchemaSqlSupport,
    assertCurrent: primaryCurrent,
    validateSource: () => journalMarkerMatches(markerPath, journalMarker) &&
      (!enabled || journalMarkerMatches(featurePath, cancellationMarker)) &&
      (!submissionEnabled || journalMarkerMatches(submissionPath, submissionMarker)) &&
      (!epochEnabled || journalMarkerMatches(epochPath, epochMarker)) &&
      (!intentEnabled || journalMarkerMatches(intentPath, intentMarker)) &&
      (!retirementEnabled || journalMarkerMatches(retirementPath, retirementMarker)) &&
      (!restartEnabled || journalMarkerMatches(restartPath, restartMarker)) &&
      (!nameEnabled || journalMarkerMatches(namePath, nameMarker)) &&
      JSON.stringify(journalDirectoryEntries(directory, maxInspectionEntries)) === JSON.stringify(entries)});
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
  primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent) {
  if (!existsSync(directory)) return false;
  const state = lstatSync(directory);
  if (!state.isDirectory() || state.isSymbolicLink()) {
    fail('UnknownClientRequestJournalFormat');
  }
  const entries = journalDirectoryEntries(directory, maxInspectionEntries);
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
  try {
    inspectJournalSnapshot(directory, databasePath, markerPath, maxInspectionEntries, maxInspectionBytes,
      primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent);
  } catch (cause) {
    if (cause?.cleanupPending) throw cause;
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
  maxJournalOperations,
  primarySqlLimits,
  primaryExecutionLimits,
  primarySchemaLimits,
  primarySchemaSqlSupport,
  primaryCurrent,
  maxRunDefinitionWireBytes = 65_536,
  submissionEpochTtlMs = maxEpochTtlMs,
  submissionEpochNow = Date.now,
  updateOriginalControl,
  sourceOperationLimits,
} = {}) {
  if (!pathText(directory) || !Number.isSafeInteger(maxRecords) ||
      !Number.isSafeInteger(maxInspectionEntries) || maxInspectionEntries < 1 ||
      !Number.isSafeInteger(maxInspectionBytes) || maxInspectionBytes < 1 ||
      maxDatabaseBytes !== undefined &&
        (!Number.isSafeInteger(maxDatabaseBytes) || maxDatabaseBytes < 1) ||
      maxWalFrames !== undefined &&
        (!Number.isSafeInteger(maxWalFrames) || maxWalFrames < 1) ||
      maxJournalOperations !== undefined &&
        (!Number.isSafeInteger(maxJournalOperations) || maxJournalOperations < 1) ||
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
  if (maxJournalOperations !== undefined && (maxDatabaseBytes === undefined ||
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
  const current = admitJournalDirectory(directory, maxInspectionEntries, inspectionBytes,
    primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent);
  mkdirSync(directory, {recursive: true, mode: 0o700});
  const root = realpathSync(directory);
  const path = join(root, 'client-requests.sqlite3');
  const existed = existsSync(path);
  if (current !== existed) fail('UnknownClientRequestJournalFormat');
  primaryCurrent?.();
  const connection = new DatabaseSync(path, {
    // Retain the actual wrapper before native open can acquire a connection
    // and then fail. Cleanup must not depend on an unreachable constructor
    // result or on eventual garbage collection of that native connection.
    open: false,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
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
    boundJournalDatabaseExtent(database, maxDatabaseBytes, primaryExecutionLimits, walFrames);
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
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
    if (!existed) {
      syncDirectory(root);
      const marker = openSync(join(root, 'journal-format.json'), 'wx', 0o600);
      try {
        writeFileSync(marker, journalMarker);
        fsyncSync(marker);
      } finally {
        closeSync(marker);
      }
      syncDirectory(root);
    }
    if (!existsSync(join(root, submissionMarkerName))) {
      // Adopt only the retained original rows of an admitted prior format.
      // This cannot certify missing pre-upgrade history or issue an epoch.
      transaction.run(() => database.exec(`
        CREATE TABLE client_submission_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submission_custody
          SELECT 1, COUNT(*) FROM client_requests;
      `));
      const marker = openSync(join(root, submissionMarkerName), 'wx', 0o600);
      try { writeFileSync(marker, submissionMarker); fsyncSync(marker); }
      finally { closeSync(marker); }
      syncDirectory(root);
    }
    if (!existsSync(join(root, epochMarkerName))) {
      // One retained authentication key and monotonic expiry watermark suffice
      // to validate bounded-lifetime tickets. No per-epoch history is evicted.
      transaction.run(() => {
        database.exec(`CREATE TABLE client_submission_epoch_authority (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          authentication_key TEXT NOT NULL,
          observed_at INTEGER NOT NULL CHECK (observed_at >= 0)
        ) STRICT;`);
        database.prepare('INSERT INTO client_submission_epoch_authority VALUES (1, ?, 0)')
          .run(randomBytes(32).toString('hex'));
      });
      const marker = openSync(join(root, epochMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, epochMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    if (!existsSync(join(root, intentMarkerName))) {
      transaction.run(() => database.exec(`
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
      const marker = openSync(join(root, intentMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, intentMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    if (!existsSync(join(root, retirementMarkerName))) {
      // Adoption records zero formal retirements; it never resets issuance
      // or repairs a missing original row in a previously admitted journal.
      transaction.run(() => database.exec(`
        CREATE TABLE client_submitted_intent_retirement (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          retired_count INTEGER NOT NULL CHECK (retired_count >= 0)
        ) STRICT;
        INSERT INTO client_submitted_intent_retirement VALUES (1, 0);
      `));
      const marker = openSync(join(root, retirementMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, retirementMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    if (!existsSync(join(root, restartMarkerName))) {
      transaction.run(() => database.exec(`
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
      const marker = openSync(join(root, restartMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, restartMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    if (!existsSync(join(root, cancellationMarkerName))) {
      transaction.run(() => database.exec(`
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
      const marker = openSync(join(root, cancellationMarkerName), 'wx', 0o600);
      try { writeFileSync(marker, cancellationMarker); fsyncSync(marker); }
      finally { closeSync(marker); }
      syncDirectory(root);
    }
    if (!existsSync(join(root, nameMarkerName))) {
      // Old nonces are not names. This empty additive index never adopts or
      // searches their history. Once issued, a name is not evicted or reused.
      transaction.run(() => database.exec(`
        ${nameTables.map(([, sql]) => `${sql};`).join('\n')}
        INSERT INTO client_submission_name_custody VALUES (1, 0, 0);
        ${nameTriggers.map(([, sql]) => `${sql};`).join('\n')}
      `));
      const marker = openSync(join(root, nameMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, nameMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    // This optional original-operation storage belongs to this same Journal.
    // Legacy absence grants no new dispatch: live scope issuance additionally
    // requires the existing confirmed first physical-start transaction.
    inspectClientSourceOperationStorage(database);
    if (sourceOperationLimits !== undefined && database.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'client_source_operation_originals'").get() === undefined) {
      transaction.run(() => database.exec(sourceOperationTable));
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
    const original = originalIntent(intent, control);
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
  const select = database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE authority_scope_cid = ? AND caller_request_id = ?`);
  const selectRef = database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ?`);
  const sourceOperations = clientSourceOperationStorage(database, {ensureOpen,
    transact, limits: sourceOperationLimits,
    readRun: ref => selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid)});
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
    runStateFrames.set(facts, Object.freeze({...row}));
    return facts;
  };
  const selectRun = database.prepare(`SELECT run_definition_cid
    FROM client_requests WHERE run_definition_cid = ?`);
  const count = database.prepare('SELECT COUNT(*) AS n FROM client_requests');
  const submissionIssued = database.prepare('SELECT issued_count FROM client_submission_custody WHERE singleton = 1');
  const advanceSubmissionCustody = database.prepare('UPDATE client_submission_custody SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?');
  const assertSubmissionCustody = () => {
    const n = Number(count.get().n);
    if (!Number.isSafeInteger(n) || submissionIssued.get()?.issued_count !== n) {
      fail('ClientRequestSubmissionCustodyLost');
    }
    return n;
  };
  const epochAuthority = database.prepare('SELECT * FROM client_submission_epoch_authority WHERE singleton = 1');
  const advanceEpochTime = database.prepare('UPDATE client_submission_epoch_authority SET observed_at = ? WHERE singleton = 1');
  const epochClock = () => {
    const row = epochAuthority.get();
    if (!validEpochAuthority(row)) fail('ClientSubmissionEpochCustodyLost');
    const now = submissionEpochNow();
    if (!Number.isSafeInteger(now) || now < 0 ||
        now > Number.MAX_SAFE_INTEGER - maxEpochTtlMs) fail('ClientSubmissionEpochClockInvalid');
    const observedAt = Math.max(now, row.observed_at);
    advanceEpochTime.run(observedAt);
    return {...row, observed_at: observedAt};
  };
  const epochHandle = (epoch, control) => {
    if (epoch === null || typeof epoch !== 'object' || Array.isArray(epoch) ||
        JSON.stringify(Object.keys(epoch).sort()) !== JSON.stringify([
          'authenticator', 'authorityScopeCid', 'epochNonce', 'expiresAt', 'notBefore', 'version',
        ])) fail('ClientSubmissionEpochUnverifiable');
    const captured = Object.freeze({...epoch});
    if (captured.version !== 'actql-submission-epoch/0.1' ||
        !cid(captured.authorityScopeCid) || !hexKey(captured.epochNonce) ||
        !Number.isSafeInteger(captured.notBefore) || !Number.isSafeInteger(captured.expiresAt) ||
        Object.is(captured.notBefore, -0) || Object.is(captured.expiresAt, -0) ||
        !hexKey(captured.authenticator)) fail('ClientSubmissionEpochUnverifiable');
    const handle = control.clientSubmissionEpoch(captured.authorityScopeCid,
      captured.epochNonce, captured.notBefore, captured.expiresAt);
    if (handle === undefined) fail('ClientSubmissionEpochUnverifiable');
    return {captured, handle};
  };
  const authenticateEpoch = (key, wire) => createHmac('sha256',
    Buffer.from(key, 'hex')).update(wire, 'utf8').digest('hex');
  const verifyEpochLocked = (epoch, {authorityScopeCid, currentAuthorization,
    purpose}, control) => {
    ensureOpen();
    if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
    if (!cid(authorityScopeCid) || !['admit', 'lookup'].includes(purpose)) {
      fail('InvalidClientSubmissionEpochOperation');
    }
    const {captured, handle} = epochHandle(epoch, control);
    const clock = epochClock();
    const authenticated = authenticateEpoch(clock.authentication_key,
      control.clientSubmissionEpochWire(handle));
    if (!timingSafeEqual(Buffer.from(authenticated, 'hex'),
      Buffer.from(captured.authenticator, 'hex'))) fail('ClientSubmissionEpochUnverifiable');
    if (captured.authorityScopeCid !== authorityScopeCid) {
      fail('ClientSubmissionEpochScopeMismatch');
    }
    const validity = control.clientSubmissionEpochValidity(handle, clock.observed_at);
    if (validity === undefined) fail('ClientSubmissionEpochClockInvalid');
    return {handle, epoch: captured, validity,
      epochCid: control.clientSubmissionEpochCid(handle)};
  };
  const verifyEpoch = (epoch, fields, control) =>
    transaction.run(() => verifyEpochLocked(epoch, fields, control));
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
      const retained = retainedIntent(row, control);
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
  const intentCount = database.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(length(CAST(intent_wire AS BLOB))), 0) AS bytes FROM client_submitted_intents');
  const intentIssued = database.prepare('SELECT issued_count FROM client_submitted_intent_custody WHERE singleton = 1');
  const intentRetired = database.prepare('SELECT retired_count FROM client_submitted_intent_retirement WHERE singleton = 1');
  const restartSelect = database.prepare('SELECT * FROM client_submission_restarts WHERE fresh_submission_id = ?');
  const restartCount = database.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(length(CAST(link_wire AS BLOB))), 0) AS bytes FROM client_submission_restarts');
  const restartIssued = database.prepare('SELECT issued_count FROM client_submission_restart_custody WHERE singleton = 1');
  const assertRestartCustody = () => {
    const retained = restartCount.get();
    if (!Number.isSafeInteger(retained.n) || restartIssued.get()?.issued_count !== retained.n) {
      fail('ClientSubmissionRestartCustodyLost');
    }
    return retained;
  };
  const assertIntentCustody = () => {
    const retained = intentCount.get();
    const issued = intentIssued.get()?.issued_count;
    const retired = intentRetired.get()?.retired_count;
    if (!Number.isSafeInteger(issued) || !Number.isSafeInteger(retired) || retired < 0 ||
        !Number.isSafeInteger(retained.n + retired) || retained.n + retired !== issued) {
      fail('ClientSubmittedIntentCustodyLost');
    }
    return {...retained, issued, retired};
  };
  const originalIntent = (intent, control) => {
    const wire = control.clientSubmittedIntentWire(intent);
    const identity = control.clientSubmittedIntentCid(intent);
    const checked = control.clientSubmittedIntent(wire, 1048576, 65536, 64);
    if (checked === undefined || control.clientSubmittedIntentCid(checked) !== identity ||
        control.clientSubmittedIntentWire(checked) !== wire) fail('InvalidClientSubmittedIntent');
    return {wire, identity};
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
    currentAuthorization, phase = 'preparing', outcome}, restartWire, requestId, control) => {
    const retained = assertIntentCustody();
    assertRestartCustody();
    const existing = intentSelect.get(requestId);
    if (existing !== undefined) {
      const previous = retainedIntent(existing, control);
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
    return {inserted: true, ...retainedIntent(intentSelect.get(requestId), control)};
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
  const retainedIntent = (row, control) => {
    const intent = control.clientSubmittedIntent(row.intent_wire, 1048576, 65536, 64);
    if (intent === undefined || control.clientSubmittedIntentCid(intent) !== row.intent_cid ||
        control.clientSubmittedIntentWire(intent) !== row.intent_wire) fail('ClientSubmittedIntentCorrupt');
    const epoch = JSON.parse(row.epoch_wire);
    const {handle} = epochHandle(epoch, control);
    const authority = epochAuthority.get();
    if (!validEpochAuthority(authority)) fail('ClientSubmissionEpochCustodyLost');
    if (authenticateEpoch(authority.authentication_key, control.clientSubmissionEpochWire(handle)) !==
        epoch.authenticator) fail('ClientSubmittedIntentCorrupt');
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
    const unresolvedHistory = retainedRestart(restartSelect.get(row.submission_id), control);
    if (unresolvedHistory !== undefined && unresolvedHistory.intentCid !== row.intent_cid) {
      fail('ClientSubmissionRestartCorrupt');
    }
    return Object.freeze({submissionRef: Object.freeze({epoch: Object.freeze(epoch), nonce: row.nonce}),
      requestId: row.submission_id, intentCid: row.intent_cid, intentWire: row.intent_wire,
      phase: row.phase, revision: row.revision, outcome,
      ...(unresolvedHistory === undefined ? {} : {unresolvedHistory})});
  };
  const cancellationCount = database.prepare('SELECT COUNT(*) AS n FROM client_cancellation_operations');
  const cancellationIssued = database.prepare('SELECT issued_count FROM client_cancellation_custody WHERE singleton = 1');
  const cancellationSelect = database.prepare(`SELECT * FROM client_cancellation_operations
    WHERE namespace_id = ? AND authority_scope_cid = ? AND cancel_id = ?`);
  const cancellationInsert = database.prepare(`INSERT INTO client_cancellation_operations
    (namespace_id, authority_scope_cid, cancel_id, run_definition_cid,
     expected_revision, intent_fingerprint_cid) VALUES (?, ?, ?, ?, ?, ?)`);
  const assertCancellationCustody = () => {
    const n = Number(cancellationCount.get().n);
    if (cancellationIssued.get()?.issued_count !== n) fail('ClientRequestJournalCorrupt');
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
          resultNames.length > 100 ||
          resultNames.some(name => typeof name !== 'string' || !name) ||
          new Set(resultNames).size !== resultNames.length ||
          Buffer.byteLength(JSON.stringify(resultNames)) > 8192) ||
        !instant(lookupExpiresAt) ||
        Date.parse(lookupExpiresAt) <= Date.now()) {
      fail('InvalidClientRequestAdmission');
    }
    const admissionEvidence = evidenceJson(runAdmissionEvidence,
      maxRunDefinitionWireBytes, updateOriginalControl);
    assertKeyedInventoryRequest(runAdmissionEvidence?.sourceInventory, fields);
    if (runAdmissionEvidence?.valuesHostPolicyOriginal !== undefined &&
        (typeof runDefinitionWire !== 'string' ||
         JSON.parse(runDefinitionWire).authorization_context_cid !==
           valuesExecutionContextCid(fields.authorityScopeCid,
             runAdmissionEvidence.valuesHostPolicyOriginal))) {
      fail('InvalidClientRunAdmissionEvidence');
    }
    if (runAdmissionEvidence?.modelOriginalRunWire !== undefined &&
        JSON.parse(runAdmissionEvidence.modelOriginalRunWire).runDefinitionWire !== runDefinitionWire) {
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
        assertSourceInventory({physicalStartReserved: existing.physical_start_reserved === 1,
          runAdmissionEvidence: retainedEvidence(existing, updateOriginalControl)},
          admissionEvidence === null ? undefined : JSON.parse(admissionEvidence).sourceInventory);
        const proposedPlan = runAdmissionEvidence?.logicalPlanOriginal;
        if (proposedPlan !== undefined) {
          const originalPlan = retainedEvidence(existing, updateOriginalControl)?.logicalPlanOriginal;
          if (originalPlan === undefined) fail('ClientRequestPlanEvidenceMissing');
          if (originalPlan.compiledPlanWire !== proposedPlan.compiledPlanWire ||
              originalPlan.planViewWire !== proposedPlan.planViewWire) {
            fail('ClientRequestPlanEvidenceMismatch');
          }
        }
        const proposedInfer = runAdmissionEvidence?.inferRunOriginal;
        if (proposedInfer !== undefined) {
          const original = retainedEvidence(existing, updateOriginalControl)?.inferRunOriginal;
          if (original === undefined) fail('ClientRequestInferEvidenceMissing');
          if (canonicalValueJson(original) !== canonicalValueJson(proposedInfer)) {
            fail('ClientRequestInferEvidenceMismatch');
          }
        }
        return Object.freeze({inserted: false, ...admission(existing),
          runAdmissionEvidence: retainedEvidence(existing, updateOriginalControl),
          ...(runDefinitionWire === undefined ? {} :
            {runDefinitionWire: existing.run_definition_wire}),
          resultNames: retainedResultNames(existing)});
      }
      const epochValidity = checkSubmissionBinding(fields, submission, control, true);
      if (epochValidity !== 'admissible') {
        // Commit the expiry watermark without admitting a Run. Throwing inside
        // this transaction would roll the watermark back and let a backwards
        // clock revive the identity after an awaited issuance.
        return {epochRejected: epochValidity};
      }
      if (Number(count.get().n) + assertCancellationCustody() >= maxRecords) {
        fail('ClientRequestJournalCapacity');
      }
      if (selectRun.get(runDefinitionCid) !== undefined) {
        fail('ClientRequestRunAlreadyAssigned');
      }
      // Only this original acceptance transaction may associate submitted
      // content with a new Run. Equal caller CIDs or later configuration are
      // not a way to attach a restriction to an already issued Run.
      let originalAdmissionEvidence = admissionEvidence;
      const admittedEvidence = admissionEvidence === null ? undefined : JSON.parse(admissionEvidence);
      if (submission?.intentCid !== undefined && admittedEvidence !== undefined) {
        const original = retainedIntent(intentSelect.get(fields.requestId), control);
        if (admittedEvidence.submittedIntentCid !== undefined &&
            admittedEvidence.submittedIntentCid !== original.intentCid) {
          fail('ClientRequestSubmittedIntentMismatch');
        }
        originalAdmissionEvidence = evidenceJson({...admittedEvidence,
          submittedIntentCid: original.intentCid},
        maxRunDefinitionWireBytes, updateOriginalControl);
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

  const lookupRecord = ({namespaceId, authorityScopeCid, requestId}, control) => {
    ensureOpen();
    if (!text(namespaceId) || !cid(authorityScopeCid) || !text(requestId) ||
        !control || typeof control.clientRequestAdmitRecord !== 'function') {
      fail('InvalidClientRequestLookup');
    }
    let row;
    try { row = select.get(authorityScopeCid, requestId); }
    catch (error) { fail('ClientRequestLookupUnknown', error); }
    if (row === undefined || row.namespace_id !== namespaceId) return undefined;
    const identity = retainedIdentity(row, control);
    if (control.clientRequestScopeCid(identity) !==
        row.logical_request_scope_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    return Object.freeze({row, identity, found: Object.freeze({
      requestId: row.caller_request_id,
      ...admission(row),
    })});
  };

  let observationStorage;
  let observationDatabase;
  let observationSql;
  let observationStorageAttempted = false;
  let observationDatabaseClosed = true;
  let originalObservationClose, originalObservationIsOpen;
  let observationProjection;
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
      observationDatabase = new DatabaseSync(path, {open: false});
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
      boundJournalDatabaseExtent(selectedObservation, maxDatabaseBytes, primaryExecutionLimits, walFrames);
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
      const original = originalIntent(intent, control);
      const result = submissionTransaction(() => {
        const issued = assertNameCustody();
        assertIntentCustody();
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
          const retained = retainedIntent(row, control);
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
          {authorityScopeCid, currentAuthorization}, undefined, requestId, control);
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
      const original = originalIntent(intent, control);
      const restartWire = restartDecision(submissionRef, original.identity, unresolvedHistory, actorId);
      const fields = {authorityScopeCid, currentAuthorization};
      const result = submissionTransaction(() => {
        assertIntentCustody();
        assertRestartCustody();
        const verified = verifyEpochLocked(submissionRef.epoch, {...fields, purpose: 'lookup'}, control);
        const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
        if (requestId === undefined) fail('InvalidClientSubmittedIntent');
        const existing = intentSelect.get(requestId);
        if (existing !== undefined) {
          const previous = retainedIntent(existing, control);
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
      const original = originalIntent(intent, control);
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
      return row === undefined ? undefined : retainedIntent(row, control);
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
        const original = retainedIntent(row, control);
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
        const retained = retainedIntent(row, control);
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
        return retainedIntent(intentSelect.get(requestId), control);
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
          if (logicalPlanOriginalShape(original) &&
              (Buffer.byteLength(original.compiledPlanWire) > maxRunDefinitionWireBytes ||
               Buffer.byteLength(original.planViewWire) > maxRunDefinitionWireBytes)) {
            fail('InvalidClientRunAdmissionEvidence');
          }
          checkStoredPlanOriginal(original, definition,
            requestControl.clientRequestProgramCid(identity), publicationControl, maxRunDefinitionWireBytes);
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
        runDefinition: retainedRunDefinition({
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
    lookupRunDefinition(ref, requestControl, publicationControl) {
      const row = readRunDefinitionRow(ref, requestControl);
      if (row === undefined) return undefined;
      return admitRunDefinitionRow(row, requestControl, publicationControl);
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
      const readOriginal = () => {
        assertSubmissionCustody();
        assertIntentCustody();
        const run = lookupRecord({namespaceId, authorityScopeCid: fields.authorityScopeCid,
          requestId: fields.requestId}, requestControl);
        if (run === undefined || requestControl.clientRequestRelation(identity,
          run.identity) !== 1) fail('ClientRequestSubmittedIntentMismatch');
        // Re-admit the retained Definition/evidence through the existing Owner
        // before using its private submitted-content reference.
        const facts = retainedRunFacts(run.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl);
        const expectedCid = facts.runAdmissionEvidence?.submittedIntentCid;
        const row = intentSelect.get(fields.requestId);
        if (row === undefined) {
          if (expectedCid !== undefined) fail('ClientSubmittedIntentCustodyLost');
          return undefined;
        }
        const original = retainedIntent(row, requestControl);
        const intent = requestControl.clientSubmittedIntent(original.intentWire,
          1048576, 65536, 64);
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
        return {intent, intentCid: original.intentCid, intentWire: original.intentWire,
          referenceWire: canonicalValueJson(original.submissionRef, {dataKeys: true}),
          runDefinitionCid: run.row.run_definition_cid};
      };
      const original = transaction.run(readOriginal);
      if (original === undefined) return undefined;
      return Object.freeze({intent: original.intent, referenceWire: original.referenceWire,
        assertCurrent() {
          ensureOpen();
          const current = transaction.run(readOriginal);
          if (current === undefined || current.intentCid !== original.intentCid ||
              current.intentWire !== original.intentWire ||
              current.referenceWire !== original.referenceWire ||
              current.runDefinitionCid !== original.runDefinitionCid) {
            fail('ClientRequestSubmittedIntentMismatch');
          }
        }});
    },
    // Advance only published logical/control/availability facts. The same
    // original accepted row, complete observation fence and confirmed COMMIT
    // own this counter. Neither reading nor wall-clock time increments it.
    publishRunState(frame, state, requestControl, publicationControl) {
      ensureOpen();
      const expected = runStateFrames.get(frame);
      if (expected === undefined) fail('ForeignRunStateObservation');
      return transact('run_state_observation', 'ClientRunStateObservationUnknown',
        error => ['RunStateObservationChanged', 'ClientRequestJournalCorrupt',
          'ForeignRunStateObservation', 'MoonBitHostFailure'].includes(error?.code), () => {
          const row = readRunDefinitionRow(frame.ref, requestControl);
          if (row === undefined || Object.keys(row).length !== Object.keys(expected).length ||
              Object.keys(expected).some(key => row[key] !== expected[key])) {
            fail('RunStateObservationChanged');
          }
          const current = admitRunDefinitionRow(row, requestControl, publicationControl);
          if (!Number.isSafeInteger(row.state_revision) || row.state_revision < 0 ||
              row.state_observation_key !== null &&
                (typeof row.state_observation_key !== 'string' || row.state_observation_key.length === 0)) {
            fail('ClientRequestJournalCorrupt');
          }
          const projection = prepareInstalledRunStateObservation(requestControl, {
            state: {...state, control: issueInstalledRunControlObservation(requestControl, {
              revision: current.revision,
              cancellationRequested: current.cancellationRequested,
              physicallyUnstarted: current.physicalStartReserved === false,
              preDispatchFailureConfirmed: current.preDispatchFailureConfirmed,
              physicalCloseConfirmed: current.physicalCloseConfirmed,
            })}, runId: publicationControl.runDefinitionRunId(current.runDefinition),
            revision: row.state_revision, priorKey: row.state_observation_key,
          });
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
    observeRunCancellation(ref, requestControl, publicationControl) {
      const selected = Object.freeze({namespaceId: ref?.namespaceId,
        authorityScopeCid: ref?.authorityScopeCid, runDefinitionCid: ref?.runDefinitionCid});
      let previousRow;
      let previousFacts;
      return () => {
        try {
          const row = readRunDefinitionRow(selected, requestControl);
          if (row === undefined) {
            previousRow = previousFacts = undefined;
            return undefined;
          }
          if (previousRow !== undefined &&
              Object.keys(row).length === Object.keys(previousRow).length &&
              Object.keys(row).every(key => row[key] === previousRow[key])) {
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
      const retained = lookupRecord({namespaceId,
        authorityScopeCid: fields.authorityScopeCid,
        requestId: fields.requestId}, requestControl);
      if (retained === undefined) return undefined;
      const relation = requestControl.clientRequestRelation(identity,
        retainedIdentity(retained.row, requestControl));
      if (relation !== 1) {
        fail(relation === 2 ? 'ClientRequestIntentConflict' :
          'ClientRequestJournalCorrupt');
      }
      return Object.freeze({...retained.found,
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl),
      });
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
      const retained = journal.resolveDefinition(identity, {namespaceId},
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
      captureSourceOperation},
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
          journal, store, checkStore,
          requestId: fields.requestId, requestScopeCid: fields.logicalRequestScopeCid,
          intentCid: fields.intentFingerprintCid});
        captureOriginal = capture;
        captureReceiver = captureSourceOperation;
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
          if (Number(count.get().n) + custodyCount >= maxRecords) {
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
    // Only the live execution owner may report a completed physical close.
    // A restarted process cannot infer this from its empty worker map.
    markPhysicalClose(ref, terminalOutcome = null) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          terminalOutcome !== null &&
            !['failed', 'cancelled'].includes(terminalOutcome)) {
        fail('InvalidClientRunStopObservation');
      }
      return transact('stop_observation', 'ClientRunStopObservationUnknown',
        error => error?.code === 'ClientRunStopObservationDenied', () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.physical_start_reserved !== 1 ||
            row.physical_close_confirmed === 1 &&
              row.observed_terminal_outcome !== terminalOutcome) {
          fail('ClientRunStopObservationDenied');
        }
        if (row.physical_close_confirmed === 0) {
          database.prepare(`UPDATE client_requests SET
            physical_close_confirmed = 1, observed_terminal_outcome = ?,
            revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ? AND physical_start_reserved = 1 AND
              physical_close_confirmed = 0`).run(terminalOutcome,
            ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
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
        const row = database.prepare(`SELECT physical_start_reserved,
          reconciliation_state_wire FROM client_requests
          WHERE namespace_id = ? AND authority_scope_cid = ? AND
            run_definition_cid = ?`).get(ref.namespaceId, ref.authorityScopeCid,
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
      const row = database.prepare(`SELECT reconciliation_state_wire
        FROM client_requests WHERE namespace_id = ? AND
          authority_scope_cid = ? AND run_definition_cid = ?`).get(
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
  const deliveredJournal = boundJournalOperations(journal, maxJournalOperations, primaryCurrent);
  applyOriginal(originalJournalCustodySet, originalJournalCustodies, [deliveredJournal, () =>
    Object.freeze({journalClosed: closed, databaseClosed,
      observationAttempted: observationStorageAttempted, observationDatabaseClosed})]);
  return deliveredJournal;
  } catch (error) {
    throwSqliteInitializationFailure(initializationCleanup, error, 'client-request-journal');
  }
}
