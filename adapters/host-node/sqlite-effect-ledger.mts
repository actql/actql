import {DatabaseSync} from 'node:sqlite';
import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  realpathSync,
} from 'node:fs';
import {dirname, join} from 'node:path';
import {createSqliteTransaction, throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {batchResponseDigest, cid, count, fail, initializeEffectLedgerStorage,
  outcomeDigest, physicalDigest, responseDigest, sha256Hex} from './sqlite-effect-ledger-storage.mjs';
import {prepareSqliteEffectLedgerReads} from './sqlite-effect-ledger-reads.mjs';

import type {StatementSync} from 'node:sqlite';

type SqliteRow = NonNullable<ReturnType<StatementSync['get']>>;
type SqliteFailure = Readonly<{code?: unknown; errcode?: unknown}>;
type LedgerReads = ReturnType<typeof prepareSqliteEffectLedgerReads>;
type BatchEvidence = NonNullable<ReturnType<LedgerReads['materializeBatchResponse']>>;

type LedgerOptions = Readonly<{
  authorityScopeCid: string;
  maxEntries?: number;
  maxEntryBytes?: number;
  maxResponseBytes?: number;
  maxReadResponseBytes?: number;
  maxStoredBytes?: number;
  beforeHistoryRead?: (count: number, wireUnits: number) => undefined;
}>;
type ItemBinding = Readonly<{
  logicalRequestScopeCid: string;
  logicalItemLocatorCid: string;
}>;
type ResponseMember = Readonly<{logicalItemLocatorCid: string; dispatchEntryCid: string}>;
type ResponseBody = Readonly<{
  logicalRequestScopeCid: string;
  credentialUseCid: string;
  statusCode: number;
  responseBytes: Uint8Array;
}>;
type StoredOutcome = ItemBinding & Readonly<{
  dispatchEntryCid: string;
  responsePhysicalSha256: string;
  outcomeCid: string;
  outcomeJson: string;
  batchEvidence?: BatchEvidence;
  singleOnly?: boolean;
}>;
type EntryBody = Readonly<{entryCid: string; entryJson: string}>;
type AppendEntry = ItemBinding & EntryBody & Readonly<{expectedRevision: number}>;
type AppendOperation = ItemBinding & Readonly<{
  expectedRevision: number;
  expectedEntryCid: string | null;
  entries: readonly EntryBody[];
}>;
type Cursor = Readonly<{entryCid: string; generation: string; revision: number}>;
type ScopePage = Readonly<{after?: string | null; maxItems?: number; maxWireBytes?: number}>;
type HistoryPage = Readonly<{after?: Cursor | null; maxEntries?: number; maxWireBytes?: number}>;

// Stores the exact canonical ledger-entry bytes and CAS head pointers. It
// neither constructs CIDs nor decides Effect transitions or retry authority.
export function openSqliteEffectLedger(root: string, {
  authorityScopeCid,
  maxEntries = 100_000,
  maxEntryBytes = 1_048_576,
  maxResponseBytes = 1_000_000,
  // Bound every response materialized by this connection, including write
  // acknowledgements and exact retries. Unrelated durable history keeps the
  // installation's maxResponseBytes policy.
  maxReadResponseBytes = maxResponseBytes,
  maxStoredBytes = 134_217_728,
  // The existing caller grows its active control before a whole, bounded
  // original history materializes. This callback supplies no read authority.
  beforeHistoryRead,
}: Partial<LedgerOptions> = {}) {
  if (typeof root !== 'string' || root.length === 0 ||
      !cid(authorityScopeCid) || !count(maxEntries) || maxEntries === 0 ||
      !count(maxEntryBytes) || maxEntryBytes === 0 ||
      !count(maxResponseBytes) || maxResponseBytes === 0 ||
      !count(maxReadResponseBytes) || maxReadResponseBytes === 0 ||
      maxReadResponseBytes > maxResponseBytes ||
      !count(maxStoredBytes) || maxStoredBytes === 0 ||
      beforeHistoryRead !== undefined && typeof beforeHistoryRead !== 'function') {
    fail('InvalidEffectLedgerConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'effect-ledger.sqlite3');
  const existed = existsSync(path);
  if (existed && dirname(realpathSync(path)) !== directory) {
    fail('EffectLedgerPathEscapesRoot');
  }
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  const transaction = createSqliteTransaction(database, 'EffectLedger');
  let closed = false;
  let databaseClosed = false;
  let usage: ReturnType<typeof initializeEffectLedgerStorage>;
  try {
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
    transaction.run(() => {
      usage = initializeEffectLedgerStorage(database, authorityScopeCid);
      const initialUsage = usage.initial;
      if (!count(initialUsage.entries) || !count(initialUsage.bytes) ||
          !count(initialUsage.max_response_bytes) ||
          initialUsage.entries > maxEntries ||
          initialUsage.max_response_bytes > maxResponseBytes ||
          initialUsage.bytes > maxStoredBytes) {
        fail('EffectLedgerCapacityExceeded');
      }
    });
    if (!existed) {
      const descriptor = openSync(directory, 'r');
      try { fsyncSync(descriptor); }
      finally { closeSync(descriptor); }
    }
  } catch (error) {
    throwSqliteInitializationFailure(database, error, 'effect_ledger');
  }
  try {
  const active = (): undefined => {
    if (closed) fail('EffectLedgerClosed');
    transaction.assertUsable();
  };
  const {
    nativeTextUnitBytes, nativeTextBytes, fixedText, fixedInteger, readHead, boundedEntryJson,
    readEntry, readResponse, readResponseLocators, readDispatchEntry, readBatchMember, readBatchLocators,
    readBatchResponse, readBatchMembers, readOutcome, readOutcomeLocators, materialize, current,
    materializeResponse, currentDataVersion, verifiedBatchResponses, materializeBatchResponse,
    response, uniqueLocatorDispatch, responseForLocator, materializeOutcome, outcome,
  } = prepareSqliteEffectLedgerReads(database, maxEntryBytes, maxReadResponseBytes, active);
  return Object.freeze({
    current,
    // One SQLite read transaction gives every member the same durable head
    // snapshot. A missing head remains distinct from an unknown dispatch.
    currentSnapshot(locatorCids: readonly string[]) {
      active();
      if (!Array.isArray(locatorCids) || locatorCids.length > maxEntries ||
          locatorCids.some(value => !cid(value)) ||
          new Set(locatorCids).size !== locatorCids.length) {
        fail('InvalidEffectLedgerSnapshot');
      }
      database.exec('BEGIN');
      try {
        const rows = Object.freeze(locatorCids.map(current));
        database.exec('COMMIT');
        return rows;
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch { fail('EffectLedgerRollbackFailed'); }
        throw error;
      }
    },
    response,
    dispatchForLocator(locatorCid: unknown) {
      active();
      if (!cid(locatorCid)) fail('InvalidEffectItemLocator');
      return uniqueLocatorDispatch(locatorCid,
        readResponseLocators, readBatchLocators);
    },
    responseForLocator,
    outcome,
    outcomeForLocator(locatorCid: unknown, batchEvidence?: BatchEvidence, singleOnly = false) {
      active();
      if (!cid(locatorCid) || typeof singleOnly !== 'boolean') fail('InvalidEffectItemLocator');
      if (batchEvidence !== undefined &&
          !verifiedBatchResponses.has(batchEvidence)) {
        fail('EffectPhysicalResponseNotOwned');
      }
      if (singleOnly && batchEvidence !== undefined) fail('EffectResponseKindMismatch');
      const rows = readOutcomeLocators.all(locatorCid);
      if (rows.length > 1 || rows.length === 1 && !cid(rows[0].dispatch_entry_cid)) {
        fail('EffectLedgerIntegrityFailed');
      }
      if (rows.length === 0) return undefined;
      const dispatchEntryCid = rows[0].dispatch_entry_cid;
      const reused = batchEvidence !== undefined &&
        verifiedBatchResponses.get(batchEvidence) === currentDataVersion();
      const observed = reused ? batchEvidence : response(dispatchEntryCid, singleOnly);
      return materializeOutcome(readOutcome.get(dispatchEntryCid), observed);
    },
    // This is physical custody, not semantic outcome admission. The common
    // MoonBit issuer must bind and classify the stored response before use.
    recordOutcome({logicalRequestScopeCid, logicalItemLocatorCid,
      dispatchEntryCid, responsePhysicalSha256, outcomeCid, outcomeJson,
      batchEvidence, singleOnly = false}: StoredOutcome) {
      active();
      if (!cid(logicalRequestScopeCid) ||
          !cid(logicalItemLocatorCid) || !cid(dispatchEntryCid) ||
          !sha256Hex(responsePhysicalSha256) || !cid(outcomeCid) ||
          typeof outcomeJson !== 'string' ||
          Buffer.byteLength(outcomeJson) > maxEntryBytes || typeof singleOnly !== 'boolean') {
        fail('InvalidEffectPhysicalOutcome');
      }
      if (batchEvidence !== undefined &&
          !verifiedBatchResponses.has(batchEvidence)) {
        fail('EffectPhysicalResponseNotOwned');
      }
      if (singleOnly && batchEvidence !== undefined) fail('EffectResponseKindMismatch');
      return transaction.run(() => {
        // A write through another connection invalidates the short-lived
        // verified view. Re-read and re-hash before accepting its custody.
        const reused = batchEvidence !== undefined &&
          verifiedBatchResponses.get(batchEvidence) === currentDataVersion();
        const observed = reused ? batchEvidence : response(dispatchEntryCid, singleOnly);
        if (batchEvidence !== undefined &&
            (!batchEvidence.batchMembers.some(member =>
              member.dispatchEntryCid === dispatchEntryCid &&
              member.logicalItemLocatorCid === logicalItemLocatorCid) ||
              readBatchResponse.get(batchEvidence.batchOwnerCid)
                ?.physical_sha256 !== batchEvidence.responsePhysicalSha256)) {
          fail('EffectPhysicalResponseNotOwned');
        }
        if (!(observed?.batchMembers === undefined
          ? observed?.logicalItemLocatorCid === logicalItemLocatorCid
          : observed.batchMembers.some(member =>
            member.dispatchEntryCid === dispatchEntryCid &&
            member.logicalItemLocatorCid === logicalItemLocatorCid)) ||
            observed!.logicalRequestScopeCid !== logicalRequestScopeCid ||
            observed!.responsePhysicalSha256 !== responsePhysicalSha256) {
          fail('EffectPhysicalResponseNotOwned');
        }
        const existing = batchEvidence === undefined
          ? outcome(dispatchEntryCid, singleOnly)
          : materializeOutcome(readOutcome.get(dispatchEntryCid), observed);
        if (existing !== undefined) {
          if (existing.outcomeCid !== outcomeCid ||
              existing.outcomeJson !== outcomeJson) {
            fail('EffectPhysicalOutcomeCollision');
          }
          return Object.freeze({outcome: existing, created: false});
        }
        const currentUsage = usage.get();
        const bytes = Buffer.byteLength(outcomeJson);
        if (currentUsage.entries >= maxEntries ||
            currentUsage.bytes > maxStoredBytes - bytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        const record = {
          logical_item_locator_cid: logicalItemLocatorCid,
          dispatch_entry_cid: dispatchEntryCid,
          logical_request_scope_cid: logicalRequestScopeCid,
          response_physical_sha256: responsePhysicalSha256,
          outcome_cid: outcomeCid,
          outcome_json: outcomeJson,
        };
        try {
          database.prepare(`
            INSERT INTO effect_ledger_outcomes (
              dispatch_entry_cid, logical_item_locator_cid,
              logical_request_scope_cid, response_physical_sha256,
              outcome_cid, outcome_json, physical_sha256
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
          `).run(dispatchEntryCid, logicalItemLocatorCid,
            logicalRequestScopeCid, responsePhysicalSha256, outcomeCid,
            outcomeJson, outcomeDigest(record));
        } catch (error) {
          if ((error as SqliteFailure).code === 'ERR_SQLITE_ERROR' &&
              ((error as SqliteFailure).errcode === 2067 || (error as SqliteFailure).errcode === 1555)) {
            fail('EffectPhysicalOutcomeCollision');
          }
          throw error;
        }
        usage.add(1, 0, outcomeJson);
        return Object.freeze({outcome: batchEvidence === undefined
          ? outcome(dispatchEntryCid, singleOnly)
          : materializeOutcome(readOutcome.get(dispatchEntryCid), observed),
          created: true});
      });
    },
    recordResponse({logicalRequestScopeCid, logicalItemLocatorCid,
      dispatchEntryCid, credentialUseCid, statusCode, responseBytes}: ResponseBody & ResponseMember) {
      active();
      if (!cid(logicalRequestScopeCid) ||
          !cid(logicalItemLocatorCid) || !cid(dispatchEntryCid) ||
          !cid(credentialUseCid) || !count(statusCode) ||
          statusCode < 100 || statusCode > 599 ||
          !(responseBytes instanceof Uint8Array) ||
          responseBytes.byteLength > maxResponseBytes ||
          responseBytes.byteLength > maxReadResponseBytes) {
        fail('InvalidEffectPhysicalResponse');
      }
      return transaction.run(() => {
        const existing = materializeResponse(
          readResponse.get(dispatchEntryCid));
        if (readBatchMember.get(dispatchEntryCid) !== undefined) {
          fail('EffectPhysicalResponseCollision');
        }
        if (existing !== undefined) {
          if (existing.logicalRequestScopeCid !== logicalRequestScopeCid ||
              existing.logicalItemLocatorCid !== logicalItemLocatorCid ||
              existing.credentialUseCid !== credentialUseCid ||
              existing.statusCode !== statusCode ||
              !existing.responseBytes.equals(Buffer.from(responseBytes))) {
            fail('EffectPhysicalResponseCollision');
          }
          return Object.freeze({response: existing, created: false});
        }
        const head = readHead.get(logicalItemLocatorCid);
        const dispatchEntry = readDispatchEntry.get(dispatchEntryCid);
        if (head !== undefined && (!cid(head.logical_request_scope_cid) ||
            !cid(head.entry_cid) || !count(head.revision) || head.revision === 0) ||
            dispatchEntry !== undefined && !cid(dispatchEntry.logical_item_locator_cid)) {
          fail('EffectLedgerIntegrityFailed');
        }
        if (head?.logical_request_scope_cid !== logicalRequestScopeCid ||
            dispatchEntry?.logical_item_locator_cid !==
              logicalItemLocatorCid) {
          fail('EffectDispatchNotOwned');
        }
        const locatorDispatch = uniqueLocatorDispatch(logicalItemLocatorCid,
          readResponseLocators, readBatchLocators);
        if (locatorDispatch !== undefined) {
          fail('EffectPhysicalResponseCollision');
        }
        const currentUsage = usage.get();
        if (currentUsage.entries >= maxEntries ||
            currentUsage.bytes > maxStoredBytes - responseBytes.byteLength) {
          fail('EffectLedgerCapacityExceeded');
        }
        database.prepare(`
          INSERT INTO effect_ledger_responses (
            logical_item_locator_cid, dispatch_entry_cid,
            logical_request_scope_cid, credential_use_cid,
            status_code, response_bytes, physical_sha256
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(logicalItemLocatorCid, dispatchEntryCid,
          logicalRequestScopeCid, credentialUseCid,
          statusCode, responseBytes, responseDigest({
            logical_item_locator_cid: logicalItemLocatorCid,
            dispatch_entry_cid: dispatchEntryCid,
            logical_request_scope_cid: logicalRequestScopeCid,
            credential_use_cid: credentialUseCid,
            status_code: statusCode,
            response_bytes: responseBytes,
          }));
        usage.add(1, responseBytes.byteLength);
        return Object.freeze({
          response: materializeResponse(readResponse.get(dispatchEntryCid)),
          created: true,
        });
      });
    },
    recordBatchResponse({logicalRequestScopeCid, credentialUseCid,
      statusCode, responseBytes, members}: ResponseBody & Readonly<{members: readonly ResponseMember[]}>) {
      active();
      if (!cid(logicalRequestScopeCid) || !cid(credentialUseCid) ||
          !count(statusCode) || statusCode < 100 || statusCode > 599 ||
          !(responseBytes instanceof Uint8Array) ||
          responseBytes.byteLength > maxResponseBytes ||
          responseBytes.byteLength > maxReadResponseBytes ||
          !Array.isArray(members) || members.length === 0 ||
          members.length > maxEntries) {
        fail('InvalidEffectPhysicalBatchResponse');
      }
      const seenLocators = new Set<string>();
      const seenDispatches = new Set<string>();
      const indexed = members.map((member: ResponseMember, position: number) => {
        if (!cid(member?.logicalItemLocatorCid) ||
            !cid(member.dispatchEntryCid) ||
            seenLocators.has(member.logicalItemLocatorCid) ||
            seenDispatches.has(member.dispatchEntryCid)) {
          fail('InvalidEffectPhysicalBatchResponse');
        }
        seenLocators.add(member.logicalItemLocatorCid);
        seenDispatches.add(member.dispatchEntryCid);
        return {
          logical_item_locator_cid: member.logicalItemLocatorCid,
          dispatch_entry_cid: member.dispatchEntryCid,
          position,
        };
      });
      const batchOwnerCid = indexed[0].dispatch_entry_cid;
      return transaction.run(() => {
        const existing = readBatchResponse.get(batchOwnerCid);
        if (existing !== undefined) {
          const stored = materializeBatchResponse(batchOwnerCid);
          const storedMembers = readBatchMembers.all(batchOwnerCid);
          if (stored === undefined ||
              stored.logicalRequestScopeCid !== logicalRequestScopeCid ||
              stored.credentialUseCid !== credentialUseCid ||
              stored.statusCode !== statusCode ||
              !stored.responseBytes.equals(Buffer.from(responseBytes)) ||
              storedMembers.length !== indexed.length ||
              storedMembers.some((member, index) =>
                member.logical_item_locator_cid !==
                  indexed[index].logical_item_locator_cid ||
                member.dispatch_entry_cid !==
                  indexed[index].dispatch_entry_cid)) {
            fail('EffectPhysicalResponseCollision');
          }
          return Object.freeze({created: false, batchOwnerCid});
        }
        for (const member of indexed) {
          if (uniqueLocatorDispatch(member.logical_item_locator_cid,
              readResponseLocators, readBatchLocators) !== undefined ||
              readResponse.get(member.dispatch_entry_cid) !== undefined ||
              readBatchMember.get(member.dispatch_entry_cid) !== undefined ||
              readHead.get(member.logical_item_locator_cid)
                ?.logical_request_scope_cid !== logicalRequestScopeCid ||
              readDispatchEntry.get(member.dispatch_entry_cid)
                ?.logical_item_locator_cid !==
                  member.logical_item_locator_cid) {
            fail('EffectDispatchNotOwned');
          }
        }
        const currentUsage = usage.get();
        if (indexed.length + 1 > maxEntries - currentUsage.entries ||
            responseBytes.byteLength > maxStoredBytes - currentUsage.bytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        const record = {
          batch_owner_cid: batchOwnerCid,
          logical_request_scope_cid: logicalRequestScopeCid,
          credential_use_cid: credentialUseCid,
          status_code: statusCode,
          response_bytes: responseBytes,
        };
        database.prepare(`
          INSERT INTO effect_ledger_batch_responses (
            batch_owner_cid, logical_request_scope_cid,
            credential_use_cid, status_code, response_bytes,
            member_count, physical_sha256
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(batchOwnerCid, logicalRequestScopeCid, credentialUseCid,
          statusCode, responseBytes, indexed.length,
          batchResponseDigest(record, indexed));
        const insertMember = database.prepare(`
          INSERT INTO effect_ledger_batch_members (
            dispatch_entry_cid, batch_owner_cid, position,
            logical_item_locator_cid
          ) VALUES (?, ?, ?, ?)
        `);
        for (const member of indexed) {
          insertMember.run(member.dispatch_entry_cid, batchOwnerCid,
            member.position, member.logical_item_locator_cid);
        }
        usage.add(indexed.length + 1, responseBytes.byteLength);
        return Object.freeze({created: true, batchOwnerCid});
      });
    },
    append({
      logicalRequestScopeCid,
      logicalItemLocatorCid,
      expectedRevision,
      entryCid,
      entryJson,
    }: AppendEntry) {
      active();
      if (!cid(logicalRequestScopeCid) ||
          !cid(logicalItemLocatorCid) || !cid(entryCid) ||
          !count(expectedRevision) ||
          expectedRevision >= Number.MAX_SAFE_INTEGER ||
          typeof entryJson !== 'string' || entryJson.length === 0 ||
          Buffer.byteLength(entryJson) > maxEntryBytes) {
        fail('InvalidEffectLedgerAppend');
      }
      return transaction.run(() => {
        const head = readHead.get(logicalItemLocatorCid);
        const revision = head?.revision ?? 0;
        if (head !== undefined &&
            head.logical_request_scope_cid !== logicalRequestScopeCid) {
          fail('EffectLedgerAuthorityMismatch');
        }
        if (revision === expectedRevision + 1 &&
            head!.entry_cid === entryCid) {
          const existing = current(logicalItemLocatorCid);
          if (existing!.entryJson !== entryJson) {
            fail('EffectLedgerEntryCollision');
          }
          return Object.freeze({entry: existing, created: false});
        }
        if (revision !== expectedRevision) {
          return Object.freeze({
            entry: current(logicalItemLocatorCid),
            created: false,
            conflict: true,
          });
        }
        const currentUsage = usage.get();
        const entryBytes = Buffer.byteLength(entryJson);
        if (currentUsage.entries >= maxEntries ||
            currentUsage.bytes > maxStoredBytes - entryBytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        const nextRevision = revision + 1;
        try {
          database.prepare(`
            INSERT INTO effect_ledger_entries (
              logical_item_locator_cid, revision, entry_cid,
              entry_json, physical_sha256
            ) VALUES (?, ?, ?, ?, ?)
          `).run(logicalItemLocatorCid, nextRevision, entryCid,
            entryJson, physicalDigest(entryJson));
        } catch (error) {
          if ((error as SqliteFailure).code === 'ERR_SQLITE_ERROR' &&
              ((error as SqliteFailure).errcode === 2067 || (error as SqliteFailure).errcode === 1555)) {
            fail('EffectLedgerEntryCollision');
          }
          throw error;
        }
        if (head === undefined) {
          database.prepare(`
            INSERT INTO effect_ledger_heads (
              logical_item_locator_cid, logical_request_scope_cid,
              revision, entry_cid
            ) VALUES (?, ?, ?, ?)
          `).run(logicalItemLocatorCid, logicalRequestScopeCid,
            nextRevision, entryCid);
        } else {
          const result = database.prepare(`
            UPDATE effect_ledger_heads SET revision = ?, entry_cid = ?
            WHERE logical_item_locator_cid = ? AND revision = ?
              AND entry_cid = ?
          `).run(nextRevision, entryCid, logicalItemLocatorCid,
            expectedRevision, head.entry_cid);
          if (result.changes !== 1) fail('EffectLedgerCASFailed');
        }
        usage.add(1, 0, entryJson);
        return Object.freeze({
          entry: current(logicalItemLocatorCid),
          created: true,
        });
      });
    },
    // Atomically advance every row covered by one physical request. The
    // caller has already admitted each typed transition in MoonBit; this
    // adapter only fences heads and reserves the aggregate physical storage.
    appendBatch(operations: readonly AppendOperation[]) {
      active();
      if (!(Array.isArray(operations) as boolean) || operations.length === 0 ||
          operations.length > maxEntries) {
        fail('InvalidEffectLedgerBatch');
      }
      const seen = new Set<string>();
      let additionalEntries = 0;
      let additionalBytes = 0;
      for (const operation of operations) {
        if (!cid(operation?.logicalRequestScopeCid) ||
            !cid(operation.logicalItemLocatorCid) ||
            !count(operation.expectedRevision) ||
            operation.expectedRevision >= Number.MAX_SAFE_INTEGER - 1 ||
            (operation.expectedRevision === 0
              ? operation.expectedEntryCid !== null
              : !cid(operation.expectedEntryCid)) ||
            !Array.isArray(operation.entries) ||
            operation.entries.length < 1 || operation.entries.length > 2 ||
            (operation.expectedRevision !== 0 &&
              operation.entries.length !== 1) ||
            seen.has(operation.logicalItemLocatorCid)) {
          fail('InvalidEffectLedgerBatch');
        }
        seen.add(operation.logicalItemLocatorCid);
        for (const entry of operation.entries) {
          if (!cid(entry?.entryCid) || typeof entry.entryJson !== 'string' ||
              entry.entryJson.length === 0 ||
              Buffer.byteLength(entry.entryJson) > maxEntryBytes) {
            fail('InvalidEffectLedgerBatch');
          }
          additionalEntries += 1;
          additionalBytes += Buffer.byteLength(entry.entryJson);
        }
      }
      return transaction.run(() => {
        for (const operation of operations) {
          const head = readHead.get(operation.logicalItemLocatorCid);
          if ((head?.revision ?? 0) !== operation.expectedRevision ||
              (head?.entry_cid ?? null) !== operation.expectedEntryCid) {
            return Object.freeze({created: false, conflict: true});
          }
          if (head !== undefined && head.logical_request_scope_cid !==
              operation.logicalRequestScopeCid) {
            fail('EffectLedgerAuthorityMismatch');
          }
        }
        const currentUsage = usage.get();
        if (additionalEntries > maxEntries - currentUsage.entries ||
            additionalBytes > maxStoredBytes - currentUsage.bytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        for (const operation of operations) {
          let revision = operation.expectedRevision;
          for (const entry of operation.entries) {
            revision += 1;
            database.prepare(`
              INSERT INTO effect_ledger_entries (
                logical_item_locator_cid, revision, entry_cid,
                entry_json, physical_sha256
              ) VALUES (?, ?, ?, ?, ?)
            `).run(operation.logicalItemLocatorCid, revision, entry.entryCid,
              entry.entryJson, physicalDigest(entry.entryJson));
            usage.add(1, 0, entry.entryJson);
          }
          const lastCid = operation.entries.at(-1)!.entryCid;
          if (operation.expectedRevision === 0) {
            database.prepare(`
              INSERT INTO effect_ledger_heads (
                logical_item_locator_cid, logical_request_scope_cid,
                revision, entry_cid
              ) VALUES (?, ?, ?, ?)
            `).run(operation.logicalItemLocatorCid,
              operation.logicalRequestScopeCid, revision, lastCid);
          } else {
            const updated = database.prepare(`
              UPDATE effect_ledger_heads SET revision = ?, entry_cid = ?
              WHERE logical_item_locator_cid = ? AND revision = ?
                AND entry_cid = ?
            `).run(revision, lastCid, operation.logicalItemLocatorCid,
              operation.expectedRevision, operation.expectedEntryCid);
            if (updated.changes !== 1) fail('EffectLedgerCASFailed');
          }
        }
        return Object.freeze({created: true, entries: Object.freeze(
          operations.map(operation => current(operation.logicalItemLocatorCid)),
        )});
      });
    },
    // Discover a bounded set of current streams from this existing request
    // scope. Locator ordering is only an inventory order, never event order.
    currentScopePage(scopeCid: unknown,{after=null,maxItems,maxWireBytes}: ScopePage={}) {
      active();
      if (!cid(scopeCid) || after !== null && !cid(after) || !count(maxItems) || maxItems < 1 ||
          maxItems > 5 || !count(maxWireBytes) || maxWireBytes < 1) fail('InvalidEffectLedgerScopePage');
      return transaction.run(()=>{
        if (after !== null && readHead.get(after)?.logical_request_scope_cid !== scopeCid) {
          return Object.freeze({kind:'cursor_mismatch'});
        }
        const rows=database.prepare(`SELECT h.logical_item_locator_cid,h.revision,h.entry_cid,
          length(CAST(e.entry_json AS BLOB)) AS wire_bytes FROM effect_ledger_heads h
          LEFT JOIN effect_ledger_entries e ON e.logical_item_locator_cid=h.logical_item_locator_cid
            AND e.revision=h.revision
          WHERE h.logical_request_scope_cid=? AND h.logical_item_locator_cid>?
          ORDER BY h.logical_item_locator_cid ASC LIMIT ?`).all(scopeCid,after ?? '',maxItems+1);
        const selected=rows.slice(0,maxItems);
        if (selected.some(row=>!cid(row.logical_item_locator_cid) || !cid(row.entry_cid) ||
            !count(row.revision) || row.revision < 1 || !count(row.wire_bytes) || row.wire_bytes > nativeTextBytes)) {
          fail('EffectLedgerIntegrityFailed');
        }
        if (selected.reduce((total,row)=>total+(row.wire_bytes as number),0) > maxWireBytes) {
          return Object.freeze({kind:'limit_exceeded'});
        }
        const entries=selected.map(row=>{
          const entry=materialize(readEntry.get(row.logical_item_locator_cid,row.revision),scopeCid);
          if (entry.entryCid !== row.entry_cid) fail('EffectLedgerIntegrityFailed');
          return entry;
        });
        return Object.freeze({kind:'page',entries:Object.freeze(entries),hasMore:rows.length>maxItems});
      });
    },
    // Page the existing append-only chain. This is an Owner-local read
    // transaction, not a composite snapshot or authority to resend an Effect.
    historyPage(locatorCid: unknown, {after = null, maxEntries: pageEntries,
      maxWireBytes}: HistoryPage = {}) {
      active();
      if (!cid(locatorCid) || !count(pageEntries) || pageEntries === 0 ||
          pageEntries > Math.min(maxEntries, 1000) || !count(maxWireBytes) || maxWireBytes === 0 ||
          after !== null && (!after || typeof after !== 'object' ||
            Object.keys(after).sort().join(',') !== 'entryCid,generation,revision' ||
            !cid(after.generation) || !cid(after.entryCid) ||
            !count(after.revision) || after.revision === 0)) {
        fail('InvalidEffectLedgerHistoryPage');
      }
      return transaction.run(() => {
        const head = readHead.get(locatorCid);
        if (head === undefined) return Object.freeze(after === null
          ? {kind:'page', generation:null, head:null, previous:null, entries:Object.freeze([])}
          : {kind:'history_unrecoverable'});
        if (!count(head.revision) || head.revision === 0 ||
            !cid(head.entry_cid) || !cid(head.logical_request_scope_cid)) {
          fail('EffectLedgerIntegrityFailed');
        }
        const metadata = (revision: number) => database.prepare(`
          SELECT revision, entry_cid, length(CAST(entry_json AS BLOB)) AS wire_bytes
          FROM effect_ledger_entries WHERE logical_item_locator_cid = ? AND revision = ?
        `).get(locatorCid, revision);
        const first = metadata(1), last = metadata(head.revision);
        if (!first || !last || !cid(first.entry_cid) || last.entry_cid !== head.entry_cid) {
          fail('EffectLedgerIntegrityFailed');
        }
        const position = after?.revision ?? 0;
        if (after !== null && (after.generation !== first.entry_cid ||
            position > head.revision)) return Object.freeze({kind:'cursor_mismatch'});
        const previous = position === 0 ? null : metadata(position);
        if (position !== 0 && !previous) fail('EffectLedgerIntegrityFailed');
        if (previous !== null && previous!.entry_cid !== after!.entryCid) {
          return Object.freeze({kind:'cursor_mismatch'});
        }
        // Inspect byte counts before materializing entry strings. Do not
        // read the whole history merely to slice a small replay page.
        const rows = database.prepare(`
          SELECT revision, entry_cid, length(CAST(entry_json AS BLOB)) AS wire_bytes
          FROM effect_ledger_entries WHERE logical_item_locator_cid = ? AND revision > ?
          ORDER BY revision ASC LIMIT ?
        `).all(locatorCid, position, pageEntries);
        if (rows.length !== Math.min(pageEntries, head.revision - position) ||
            rows.some((row, index) => row.revision !== position + index + 1 ||
              !cid(row.entry_cid) || !count(row.wire_bytes) || row.wire_bytes > nativeTextBytes) ||
            previous !== null && (!count(previous!.wire_bytes) || previous!.wire_bytes > nativeTextBytes)) {
          fail('EffectLedgerIntegrityFailed');
        }
        const bytes = rows.reduce((total, row) => total + (row.wire_bytes as number),
          (previous?.wire_bytes as number | undefined) ?? 0);
        if (bytes > maxWireBytes) return Object.freeze({kind:'limit_exceeded'});
        const load = (row: SqliteRow) => {
          const entry = materialize(readEntry.get(locatorCid, row.revision), head.logical_request_scope_cid);
          if (entry.entryCid !== row.entry_cid) fail('EffectLedgerIntegrityFailed');
          return entry;
        };
        return Object.freeze({kind:'page', generation:first.entry_cid,
          head:Object.freeze({revision:head.revision, entryCid:head.entry_cid}),
          previous:previous === null ? null : load(previous!),
          entries:Object.freeze(rows.map(load))});
      });
    },
    history(locatorCid: unknown, maxRevisions: number) {
      active();
      if (!cid(locatorCid) || !count(maxRevisions) || maxRevisions === 0 ||
          maxRevisions > maxEntries) {
        fail('InvalidEffectLedgerHistory');
      }
      return transaction.run(() => {
        const head = readHead.get(locatorCid);
        if (head === undefined) return Object.freeze([]);
        if (!cid(head.logical_request_scope_cid) || !cid(head.entry_cid) ||
            !count(head.revision) || head.revision === 0) fail('EffectLedgerIntegrityFailed');
        if (head.revision > maxRevisions) fail('EffectLedgerHistoryLimitExceeded');
        // TOTAL cannot overflow SQLite's signed integer accumulator. All terms
        // are nonnegative integers: a total within the safe range is exact,
        // and only that case is cast back to INTEGER for native marshalling.
        const geometry = database.prepare(`
          SELECT CASE WHEN entries <= 9007199254740991 THEN entries ELSE NULL END AS entries,
            CASE WHEN valid_entries = entries AND wire_bytes <= 9007199254740991
              THEN CAST(wire_bytes AS INTEGER) ELSE NULL END AS wire_bytes
          FROM (
            SELECT COUNT(*) AS entries, COUNT(wire_bytes) AS valid_entries,
              TOTAL(wire_bytes) AS wire_bytes
            FROM (
              SELECT CASE WHEN TYPEOF(entry_json) = 'text'
                AND LENGTH(CAST(entry_json AS BLOB)) <= ${nativeTextBytes}
                THEN LENGTH(CAST(entry_json AS BLOB)) ELSE NULL END AS wire_bytes
              FROM effect_ledger_entries WHERE logical_item_locator_cid = ?
              ORDER BY revision ASC LIMIT ?
            )
          )
        `).get(locatorCid, BigInt(maxEntries) + 1n)!;
        if (!count(geometry.entries) || !count(geometry.wire_bytes) ||
            geometry.entries !== head.revision) fail('EffectLedgerIntegrityFailed');
        const wireUnits = geometry.wire_bytes / Number(nativeTextUnitBytes);
        if (!count(wireUnits)) fail('EffectLedgerIntegrityFailed');
        if (beforeHistoryRead?.(geometry.entries, wireUnits) !== undefined) {
          fail('InvalidEffectLedgerHistory');
        }
        const rows = database.prepare(`
          SELECT ${fixedText('logical_item_locator_cid', 71)}, ${fixedInteger('revision', 1)},
            ${fixedText('entry_cid', 71)}, ${boundedEntryJson}, ${fixedText('physical_sha256', 64)}
          FROM effect_ledger_entries WHERE logical_item_locator_cid = ?
          ORDER BY revision ASC LIMIT ?
        `).all(locatorCid, BigInt(maxEntries) + 1n);
        if (rows.length !== head.revision) fail('EffectLedgerIntegrityFailed');
        return Object.freeze(rows.map((row, index) => {
          if (row.revision !== index + 1) fail('EffectLedgerIntegrityFailed');
          return materialize(row, head.logical_request_scope_cid);
        }));
      });
    },
    close() {
      closed = true;
      if (databaseClosed) return false;
      database.close();
      databaseClosed = true;
      return true;
    },
  });
  } catch (error) {
    throwSqliteInitializationFailure(database, error, 'effect_ledger');
  }
}
