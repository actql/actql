// Original SQLite operation and WAL limits for the Request Journal.
import {types as utilTypes} from 'node:util';
import {DatabaseSync, type DatabaseSyncOptions, type StatementSync, type SQLOutputValue} from 'node:sqlite';
import {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import {openClientObservationStorage} from './client-observation-journal.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type Current = () => SynchronousRuntimeData;
type SqlLimits = Readonly<{maxPreparedStatements: number; maxSqlBytes: number; maxTotalSqlBytes: number}>;
type ExecutionLimits = Readonly<{maxParameters: number; maxParameterBytes: number; maxResultRows: number}>;
type OriginalConnection = Pick<DatabaseSync, 'prepare' | 'exec' | 'isTransaction'>;
type SqlValue = string | number | bigint | null;
type Row = Record<string, SQLOutputValue>;
type Cursor = ReturnType<StatementSync['iterate']>;
type CursorWork = {iterator: Cursor; next?: Cursor['next']; end?: Cursor['return']};
type PreparedStatement = Readonly<{
  get(...values: SqlValue[]): Row | undefined;
  run(...values: SqlValue[]): ReturnType<StatementSync['run']>;
  all(...values: SqlValue[]): Row[];
}>;
export type JournalSqlConnection = Readonly<{
  prepare(sql: string): PreparedStatement;
  exec(sql: string): void;
}>;
type WalConnection = Readonly<{inTransaction(): unknown; checkpoint(): Row | undefined}>;
type WalFrames = NonNullable<ReturnType<typeof boundedJournalWalFrames>>;
type Geometry = Readonly<{page: number; pages: number}>;

export const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
export const applyOriginal = Reflect.apply;
export const operationDescriptors = Object.getOwnPropertyDescriptors;
const operationDefineProperties = Object.defineProperties;
export const operationKeys = Reflect.ownKeys;
const operationFreeze = Object.freeze;

export function snapshotPrimarySqlLimits(value: unknown): SqlLimits | undefined {
  if (value === undefined) return undefined;
  const names = ['maxPreparedStatements', 'maxSqlBytes', 'maxTotalSqlBytes'] as const;
  if (value === null || typeof value !== 'object' || utilTypes.isProxy(value)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== names.length || keys.some(key => !names.includes(key as typeof names[number]))) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const limits = {} as Record<typeof names[number], number>;
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

export function snapshotPrimaryExecutionLimits(value: unknown): ExecutionLimits | undefined {
  if (value === undefined) return undefined;
  const names = ['maxParameters', 'maxParameterBytes', 'maxResultRows'] as const;
  if (value === null || typeof value !== 'object' || utilTypes.isProxy(value)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== names.length || keys.some(key => !names.includes(key as typeof names[number]))) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const limits = {} as Record<typeof names[number], number>;
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

export function guardJournalCurrentness<Journal extends object>(journal: Journal, assertCurrent?: Current): Journal {
  if (assertCurrent === undefined) return journal;
  // Every new operation checks its same installed original. Completed calls
  // retain no lifetime issuance debt; their own finite input/SQL work remains
  // bounded at each actual consumer. Cleanup is always reachable below.
  const enter = () => {assertCurrent();};
  const descriptors = operationDescriptors(journal);
  for (const name of operationKeys(descriptors)) {
    const field = descriptors[name as keyof typeof descriptors], original = field.value;
    // These are the fixed authored Owner's own methods, not caller DATA.
    // Cleanup remains reachable without operation/SQL credit or currentness.
    if (typeof original !== 'function' || name === 'close' || name === 'closeObservationStorage') continue;
    field.value = name === 'admitOrLookupDefinition'
      ? async function () { enter(); return applyOriginal(original, journal, arguments); }
      : function () { enter(); return applyOriginal(original, journal, arguments); };
  }
  return operationFreeze(operationDefineProperties({}, descriptors)) as Journal;
}

// One live WAL support bound for this Journal's two original writable
// connections. Work stays charged until their actual native checkpoint
// acknowledges truncation. This is not physical backing or Run authority.
export function boundedJournalWalFrames(maxFrames: number | undefined, sourceBytes: number, maxDatabaseBytes: number | undefined) {
  if (maxFrames === undefined) return undefined;
  const integer = BigInt, floor = Math.floor, ceil = Math.ceil;
  const maximum = integer(maxFrames);
  // The original DB and WAL are jointly bounded before cold native inspection.
  // Reserve the worst original WAL at SQLite's minimum supported page size;
  // absence or a logical transaction exit alone cannot release these frames.
  let reserved = integer(sourceBytes) / 536n;
  if (reserved > maximum) fail('ClientRequestJournalWalUnavailable');
  const character = String.prototype.charCodeAt;
  const connections: WalConnection[] = [];
  let active = false;
  let originalPage: number | undefined, transactionFrames: bigint | undefined;
  const amount = (units: number) => transactionFrames === undefined ? 0n :
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
  const check = (units: number, transactionStart = false) => {
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
    register(original: WalConnection) {
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
    configure(page: number) {
      if (originalPage !== undefined && originalPage !== page) {
        fail('ClientRequestJournalWalUnavailable');
      }
      originalPage = page;
      // Same supported page-number set, possible repeated commit page, and
      // FULL-sync padding under SQLite's original 65536-byte sector clamp.
      // Counting two complete page sets is conservative; it does not assert
      // every dirty-page visit appends another frame or create two capacities.
      transactionFrames = 2n * integer(floor(maxDatabaseBytes! / page)) +
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
    beforeExec(sql: string) {
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
export function boundedPrimarySql(connection: OriginalConnection, limits: SqlLimits,
  executionLimits?: ExecutionLimits, assertCurrent?: Current, walFrames?: WalFrames) {
  const prepare = connection.prepare, exec = connection.exec;
  const buffer = Buffer, byteLength = buffer.byteLength;
  const isTransaction = Object.getOwnPropertyDescriptor(connection, 'isTransaction')?.get;
  if (typeof prepare !== 'function' || typeof exec !== 'function' || typeof byteLength !== 'function' ||
      typeof isTransaction !== 'function') fail('ClientRequestJournalSqlUnavailable');
  let prepared = 0, retainedSqlBytes = 0;
  const statements: StatementSync[] = [], cursors: CursorWork[] = [];
  const statementsBySql = executionLimits === undefined ? undefined : new Map<string, PreparedStatement>();
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
  const consume = (sql: string, isPrepare: boolean) => {
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
  const operands = (values: readonly SqlValue[]) => {
    assertCurrent?.();
    if (cursors.length !== 0) fail('ClientRequestJournalSqlCleanupPending');
    if (values.length > executionLimits!.maxParameters) fail('ClientRequestJournalSqlUnavailable');
    let total = 0;
    for (const value of values) {
      let size;
      if (value === null) size = 0;
      else if (typeof value === 'number' || typeof value === 'bigint') size = 8;
      else if (typeof value === 'string') {
        if (value.length > executionLimits!.maxParameterBytes - total) {
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
      if (size > executionLimits!.maxParameterBytes - total) {
        fail('ClientRequestJournalSqlUnavailable');
      }
      total += size;
    }
  };
  const wrap = (statement: StatementSync, statementWal: WalFrames | undefined): PreparedStatement => {
    if (executionLimits === undefined) return statement;
    // Keep native statements in this original connection's custody until its
    // real close. Losing a local wrapper or GC supplies no earlier ACK.
    statements.push(statement);
    const get = statement.get, run = statement.run, iterate = statement.iterate;
    if ([get, run, iterate].some(method => typeof method !== 'function')) {
      fail('ClientRequestJournalSqlUnavailable');
    }
    return Object.freeze({
      get(...values: SqlValue[]) {
        beginOperation();
        try {
          operands(values); statementWal?.beforeStatement();
          return applyOriginal(get, statement, values);
        } finally { endOperation(); }
      },
      run(...values: SqlValue[]) {
        beginOperation();
        try {
          operands(values); statementWal?.beforeStatement();
          return applyOriginal(run, statement, values);
        } finally { endOperation(); }
      },
      all(...values: SqlValue[]) {
        beginOperation();
        try {
          operands(values);
          statementWal?.beforeStatement();
          const iterator = applyOriginal(iterate, statement, values);
          const cursor: CursorWork = {iterator, next: undefined, end: undefined};
          cursors.push(cursor);
          let failed = false, primary;
          const rows: Row[] = [];
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
              rows.push(row.value as Row);
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
  let checkpoint: {statement: StatementSync; get: StatementSync['get']} | undefined;
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
    prepare(sql: string) {
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
    exec(sql: string) {
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
    get isTransaction(): unknown { return applyOriginal(isTransaction, connection, []); },
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

export function journalDatabaseGeometry(database: JournalSqlConnection, maxDatabaseBytes: number, walFrames?: WalFrames) {
  const page = database.prepare('PRAGMA page_size').get()!.page_size as number;
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

export function boundJournalDatabaseExtent(database: JournalSqlConnection, maxDatabaseBytes?: number,
  executionLimits?: ExecutionLimits, walFrames?: WalFrames, temporarySelected = false,
  retainedGeometry?: Geometry, prepareWalCheckpoint?: () => SynchronousRuntimeData) {
  if (maxDatabaseBytes === undefined) return;
  const {page, pages} = retainedGeometry ?? journalDatabaseGeometry(database, maxDatabaseBytes, walFrames);
  if (!temporarySelected) selectJournalTemporaryStorage(database, executionLimits);
  // Reserve the same native checkpoint statement after MEMORY is effective,
  // before normal metadata work can exhaust its finite preparation envelope.
  prepareWalCheckpoint?.();
  const observed = database.prepare(`PRAGMA max_page_count = ${pages}`).get()!.max_page_count as number;
  if (!Number.isSafeInteger(observed) || observed < 1 || observed > pages) {
    fail('ClientRequestJournalDatabaseUnavailable');
  }
  // Each actual connection owns a separate Pager limit, including the
  // optional observation connection to the same file. This is not native
  // heap/WAL backing, a bound on another writer, or a physical reservation.
  return page;
}

export function selectJournalTemporaryStorage(database: JournalSqlConnection, executionLimits?: ExecutionLimits) {
  if (executionLimits === undefined) return;
  // This selected facility uses the pinned TEMP_STORE=1 implementation:
  // connection-local memory selection covers its fixed CHECK-IN Btrees,
  // not another file/FD supplier or a process-global heap limit. The complete
  // native recipe must retain their Pager/cache/VM and allocator overhead.
  const supported = database.prepare(
    "SELECT sqlite_compileoption_used('TEMP_STORE=1') AS supported").get()!.supported;
  if (supported !== 1) fail('ClientRequestJournalTemporaryUnavailable');
  database.exec('PRAGMA temp_store = MEMORY');
  const selected = database.prepare('PRAGMA temp_store').get()!.temp_store;
  if (selected !== 2) fail('ClientRequestJournalTemporaryUnavailable');
}

// One secondary connection for this exact Request Journal. Its historical
// attempt and captured native cleanup survive a failed open or close.
export function createJournalObservationConnection(path: string, ensureOpen: () => undefined,
  primaryCurrent: Parameters<typeof boundedPrimarySql>[3],
  primarySqlLimits: Parameters<typeof boundedPrimarySql>[1] | undefined,
  primaryExecutionLimits: Parameters<typeof boundedPrimarySql>[2],
  walFrames: Parameters<typeof boundedPrimarySql>[4], maxDatabaseBytes: number | undefined) {
  let observationStorage: (ReturnType<typeof openClientObservationStorage> &
    Readonly<{close(): undefined}>) | undefined;
  let observationDatabase: DatabaseSync | undefined;
  let observationSql: ReturnType<typeof boundedPrimarySql> | undefined;
  let observationStorageAttempted = false;
  let observationDatabaseClosed = true;
  let originalObservationClose: DatabaseSync['close'] | undefined;
  let originalObservationIsOpen: (() => unknown) | undefined;
  const captureObservationCleanup = () => {
    originalObservationClose ??= observationDatabase!.close;
    originalObservationIsOpen ??= Object.getOwnPropertyDescriptor(
      observationDatabase!, 'isOpen')?.get;
    if (typeof originalObservationClose !== 'function' ||
        typeof originalObservationIsOpen !== 'function') {
      throw new TypeError('ClientObservationConnectionCleanupUnavailable');
    }
  };
  const closeObservationStorage = (): undefined => {
    if (observationDatabaseClosed) return;
    captureObservationCleanup();
    const opened = applyOriginal(originalObservationIsOpen!, observationDatabase, []);
    if (typeof opened !== 'boolean' || opened &&
        (applyOriginal(originalObservationClose!, observationDatabase, []) !== undefined ||
         applyOriginal(originalObservationIsOpen!, observationDatabase, []) !== false)) {
      throw new TypeError('ClientObservationConnectionCleanupPending');
    }
    // This is the separate original connection's own close observation. Keep
    // the historical attempted flag, and retain any escaped managed aliases.
    observationDatabaseClosed = true;
    observationSql?.retireClosedNativeAliases();
  };

  return {
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
        {open: false} : {__proto__: null, open: false} as DatabaseSyncOptions);
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
          applyOriginal(originalObservationIsOpen!, observationDatabase, []) !== true) {
        throw new TypeError('ClientObservationConnectionOpenUnavailable');
      }
      const selectedObservation = (observationSql?.database ?? observationDatabase) as
        Parameters<typeof openClientObservationStorage>[0] & Pick<DatabaseSync, 'isTransaction'>;
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
    get observationAttempted() { return observationStorageAttempted; },
    get observationDatabaseClosed() { return observationDatabaseClosed; },
  } as const;
}
