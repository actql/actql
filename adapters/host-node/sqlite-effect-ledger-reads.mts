import {batchResponseDigest, cid, count, fail, outcomeDigest, physicalDigest,
  responseDigest, sha256Hex} from './sqlite-effect-ledger-storage.mjs';

import type {DatabaseSync, SQLOutputValue, StatementSync} from 'node:sqlite';

type SqlRow = ReturnType<StatementSync['get']>;
type ResponseLocators = Pick<StatementSync, 'all'>;
type CheckedBatchMember = NonNullable<SqlRow> & Parameters<typeof batchResponseDigest>[1][number];

export function prepareSqliteEffectLedgerReads(
  database: Pick<DatabaseSync, 'prepare'>, maxEntryBytes: number, maxReadResponseBytes: number,
  active: () => undefined,
) {
  // Preserve the original UTF8 semantic byte check below. SQL first bounds
  // actual String backing: valid UTF8 input has <=B UTF16 units, so a UTF16
  // database may return <=2B native text bytes without rejecting valid ASCII.
  const textEncoding = database.prepare('PRAGMA main.encoding').get()!.encoding;
  if (!(['UTF-8', 'UTF-16le', 'UTF-16be'] as readonly SQLOutputValue[]).includes(textEncoding)) {
    fail('EffectLedgerIntegrityFailed');
  }
  const nativeTextUnitBytes = textEncoding === 'UTF-8' ? 1n : 2n;
  const nativeTextBytes = BigInt(maxEntryBytes) * nativeTextUnitBytes;
  // These closed metadata fields are ASCII CIDs/digests after validation.
  // Bound their actual native backing in the SAME SELECT first, so malformed
  // text cannot allocate an unbounded String before the integrity check.
  const fixedText = (column: string, units: number) => `CASE WHEN TYPEOF(${column}) = 'text'
    AND LENGTH(CAST(${column} AS BLOB)) <= ${BigInt(units) * nativeTextUnitBytes}
    THEN ${column} ELSE NULL END AS ${column}`;
  const fixedInteger = (column: string, minimum: number, maximum = Number.MAX_SAFE_INTEGER) =>
    `CASE WHEN TYPEOF(${column}) = 'integer' AND ${column} >= ${minimum}
    AND ${column} <= ${maximum} THEN ${column} ELSE NULL END AS ${column}`;
  const readHead = database.prepare(`
    SELECT ${fixedText('logical_request_scope_cid', 71)},
      ${fixedInteger('revision', 1)}, ${fixedText('entry_cid', 71)}
    FROM effect_ledger_heads WHERE logical_item_locator_cid = ?
  `);
  const boundedEntryJson = `CASE WHEN LENGTH(CAST(entry_json AS BLOB)) <= ${nativeTextBytes}
    THEN entry_json ELSE NULL END AS entry_json`;
  const boundedOutcomeJson = `CASE WHEN LENGTH(CAST(outcome_json AS BLOB)) <= ${nativeTextBytes}
    THEN outcome_json ELSE NULL END AS outcome_json`;
  // A receiver may admit less than the installation's durable response policy.
  // Apply its bound in SQL before allocating the BLOB or the Buffer copy. Old
  // unrelated rows retain their original storage quota and startup validation.
  const boundedResponseBytes = `CASE WHEN TYPEOF(response_bytes) = 'blob'
    AND LENGTH(response_bytes) <= ${maxReadResponseBytes}
    THEN response_bytes ELSE NULL END AS response_bytes`;
  const readEntry = database.prepare(`
    SELECT ${fixedText('logical_item_locator_cid', 71)}, ${fixedInteger('revision', 1)},
      ${fixedText('entry_cid', 71)}, ${boundedEntryJson},
      ${fixedText('physical_sha256', 64)} FROM effect_ledger_entries
    WHERE logical_item_locator_cid = ? AND revision = ?
  `);
  const readResponse = database.prepare(`
    SELECT ${fixedText('logical_item_locator_cid', 71)}, ${fixedText('dispatch_entry_cid', 71)},
      ${fixedText('logical_request_scope_cid', 71)}, ${fixedText('credential_use_cid', 71)},
      ${fixedInteger('status_code', 100, 599)},
      ${boundedResponseBytes}, ${fixedText('physical_sha256', 64)}
    FROM effect_ledger_responses WHERE dispatch_entry_cid = ?
  `);
  const readResponseLocators = database.prepare(`
    SELECT ${fixedText('dispatch_entry_cid', 71)} FROM effect_ledger_responses
    WHERE logical_item_locator_cid = ? LIMIT 2
  `);
  const readDispatchEntry = database.prepare(`
    SELECT ${fixedText('logical_item_locator_cid', 71)} FROM effect_ledger_entries
    WHERE entry_cid = ?
  `);
  const readBatchMember = database.prepare(`
    SELECT ${fixedText('dispatch_entry_cid', 71)}, ${fixedText('batch_owner_cid', 71)},
      ${fixedInteger('position', 0)}, ${fixedText('logical_item_locator_cid', 71)}
    FROM effect_ledger_batch_members
    WHERE dispatch_entry_cid = ?
  `);
  const readBatchLocators = database.prepare(`
    SELECT ${fixedText('dispatch_entry_cid', 71)} FROM effect_ledger_batch_members
    WHERE logical_item_locator_cid = ? LIMIT 2
  `);
  const readBatchResponse = database.prepare(`
    SELECT ${fixedText('batch_owner_cid', 71)}, ${fixedText('logical_request_scope_cid', 71)},
      ${fixedText('credential_use_cid', 71)}, ${fixedInteger('status_code', 100, 599)},
      ${boundedResponseBytes}, ${fixedInteger('member_count', 1)},
      ${fixedText('physical_sha256', 64)} FROM effect_ledger_batch_responses
    WHERE batch_owner_cid = ?
  `);
  const readBatchMembers = database.prepare(`
    SELECT ${fixedText('dispatch_entry_cid', 71)}, ${fixedText('batch_owner_cid', 71)},
      ${fixedInteger('position', 0)}, ${fixedText('logical_item_locator_cid', 71)}
    FROM effect_ledger_batch_members
    WHERE batch_owner_cid = ? ORDER BY position ASC
  `);
  const readOutcome = database.prepare(`
    SELECT ${fixedText('dispatch_entry_cid', 71)}, ${fixedText('logical_item_locator_cid', 71)},
      ${fixedText('logical_request_scope_cid', 71)}, ${fixedText('response_physical_sha256', 64)},
      ${fixedText('outcome_cid', 71)}, ${boundedOutcomeJson}, ${fixedText('physical_sha256', 64)}
    FROM effect_ledger_outcomes WHERE dispatch_entry_cid = ?
  `);
  const readOutcomeLocators = database.prepare(`
    SELECT ${fixedText('dispatch_entry_cid', 71)} FROM effect_ledger_outcomes
    WHERE logical_item_locator_cid = ? LIMIT 2
  `);
  const materialize = (row: SqlRow, scopeCid: unknown) => {
    if (row === undefined) fail('EffectLedgerEntryMissing');
    if (!cid(scopeCid) || !cid(row.entry_cid) || !count(row.revision) ||
        row.revision === 0 || !cid(row.logical_item_locator_cid) ||
        typeof row.entry_json !== 'string' ||
        Buffer.byteLength(row.entry_json) > maxEntryBytes ||
        physicalDigest(row.entry_json) !== row.physical_sha256) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({
      logicalRequestScopeCid: scopeCid,
      logicalItemLocatorCid: row.logical_item_locator_cid,
      revision: row.revision,
      entryCid: row.entry_cid,
      entryJson: row.entry_json,
    });
  };
  const current = (locatorCid: unknown) => {
    active();
    if (!cid(locatorCid)) fail('InvalidEffectItemLocator');
    const head = readHead.get(locatorCid);
    if (head === undefined) return undefined;
    if (!cid(head.logical_request_scope_cid) ||
        !cid(head.entry_cid) || !count(head.revision) ||
        head.revision === 0) {
      fail('EffectLedgerIntegrityFailed');
    }
    const entry = materialize(
      readEntry.get(locatorCid, head.revision),
      head.logical_request_scope_cid,
    );
    if (entry.entryCid !== head.entry_cid) {
      fail('EffectLedgerIntegrityFailed');
    }
    return entry;
  };
  const materializeResponse = (row: SqlRow) => {
    if (row === undefined) return undefined;
    if (!cid(row.logical_item_locator_cid) ||
        !cid(row.dispatch_entry_cid) ||
        !cid(row.logical_request_scope_cid) ||
        !cid(row.credential_use_cid) ||
        !count(row.status_code) || row.status_code < 100 ||
        row.status_code > 599 ||
        !(row.response_bytes instanceof Uint8Array) ||
        row.response_bytes.byteLength > maxReadResponseBytes ||
        responseDigest(row as Parameters<typeof responseDigest>[0]) !== row.physical_sha256 ||
        readDispatchEntry.get(row.dispatch_entry_cid)
          ?.logical_item_locator_cid !== row.logical_item_locator_cid) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({
      logicalItemLocatorCid: row.logical_item_locator_cid,
      dispatchEntryCid: row.dispatch_entry_cid,
      logicalRequestScopeCid: row.logical_request_scope_cid,
      credentialUseCid: row.credential_use_cid,
      statusCode: row.status_code,
      responseBytes: Buffer.from(row.response_bytes),
      responsePhysicalSha256: row.physical_sha256,
    });
  };
  const dataVersion = database.prepare('PRAGMA data_version');
  const currentDataVersion = () => dataVersion.get()!.data_version as number;
  const verifiedBatchResponses = new WeakMap<object, number>();
  const materializeBatchResponse = (dispatchEntryCid: string) => {
    const member = readBatchMember.get(dispatchEntryCid);
    if (member === undefined) return undefined;
    const row = readBatchResponse.get(member.batch_owner_cid);
    const members = readBatchMembers.all(member.batch_owner_cid);
    if (row === undefined || !cid(row.batch_owner_cid) ||
        !cid(row.logical_request_scope_cid) ||
        !cid(row.credential_use_cid) ||
        !count(row.status_code) || row.status_code < 100 ||
        row.status_code > 599 ||
        !(row.response_bytes instanceof Uint8Array) ||
        row.response_bytes.byteLength > maxReadResponseBytes ||
        !count(row.member_count) || row.member_count === 0 ||
        row.member_count !== members.length ||
        row.batch_owner_cid !== members[0].dispatch_entry_cid ||
        members.some((item, index) =>
          !cid(item.dispatch_entry_cid) ||
          !cid(item.logical_item_locator_cid) ||
          item.batch_owner_cid !== row.batch_owner_cid ||
          item.position !== index ||
          readDispatchEntry.get(item.dispatch_entry_cid)
            ?.logical_item_locator_cid !== item.logical_item_locator_cid) ||
        batchResponseDigest(row as Parameters<typeof batchResponseDigest>[0],
          members as CheckedBatchMember[]) !== row.physical_sha256 ||
        readHead.get(member.logical_item_locator_cid)
          ?.logical_request_scope_cid !== row.logical_request_scope_cid) {
      fail('EffectLedgerIntegrityFailed');
    }
    const verified = Object.freeze({
      logicalItemLocatorCid: member.logical_item_locator_cid,
      dispatchEntryCid,
      logicalRequestScopeCid: row.logical_request_scope_cid,
      credentialUseCid: row.credential_use_cid,
      statusCode: row.status_code,
      responseBytes: Buffer.from(row.response_bytes),
      responsePhysicalSha256: row.physical_sha256,
      batchOwnerCid: row.batch_owner_cid,
      batchPosition: member.position,
      batchCount: row.member_count,
      batchMembers: Object.freeze((members as CheckedBatchMember[]).map(item => Object.freeze({
        dispatchEntryCid: item.dispatch_entry_cid,
        logicalItemLocatorCid: item.logical_item_locator_cid,
      }))),
    });
    verifiedBatchResponses.set(verified, currentDataVersion());
    return verified;
  };
  const response = (dispatchEntryCid: unknown, singleOnly = false): SingleResponse | BatchResponse | undefined => {
    active();
    if (!cid(dispatchEntryCid) || typeof singleOnly !== 'boolean') fail('InvalidEffectDispatchEntry');
    const single = materializeResponse(readResponse.get(dispatchEntryCid));
    // A selected one-row constructor can inspect bounded batch presence, but
    // cannot materialize a foreign batch's unbounded member array. Collision
    // and wrong-kind refusals require no batch response or member inventory.
    const member = readBatchMember.get(dispatchEntryCid);
    if (member !== undefined) {
      if (single !== undefined || !cid(member.dispatch_entry_cid) ||
          !cid(member.batch_owner_cid) || !cid(member.logical_item_locator_cid) ||
          !count(member.position)) fail('EffectLedgerIntegrityFailed');
      if (singleOnly) fail('EffectResponseKindMismatch');
    }
    if (single !== undefined || member === undefined) return single;
    const batch = materializeBatchResponse(dispatchEntryCid);
    return batch;
  };
  const uniqueLocatorDispatch = (locatorCid: string, singles: ResponseLocators, batches: ResponseLocators) => {
    const rows = [...singles.all(locatorCid), ...batches.all(locatorCid)];
    if (rows.length > 1 || rows.length === 1 && !cid(rows[0].dispatch_entry_cid)) {
      fail('EffectLedgerIntegrityFailed');
    }
    return rows[0]?.dispatch_entry_cid as string | undefined;
  };
  const responseForLocator = (locatorCid: unknown, singleOnly = false) => {
    active();
    if (!cid(locatorCid) || typeof singleOnly !== 'boolean') fail('InvalidEffectItemLocator');
    const dispatchCid = uniqueLocatorDispatch(locatorCid,
      readResponseLocators, readBatchLocators);
    return dispatchCid === undefined ? undefined : response(dispatchCid, singleOnly);
  };
  type SingleResponse = NonNullable<ReturnType<typeof materializeResponse>> & Readonly<{batchMembers?: never}>;
  type BatchResponse = NonNullable<ReturnType<typeof materializeBatchResponse>>;
  const materializeOutcome = (row: SqlRow, observed: SingleResponse | BatchResponse | undefined) => {
    if (row === undefined) return undefined;
    if (!cid(row.dispatch_entry_cid) ||
        !cid(row.logical_item_locator_cid) ||
        !cid(row.logical_request_scope_cid) ||
        !sha256Hex(row.response_physical_sha256) ||
        !cid(row.outcome_cid) ||
        typeof row.outcome_json !== 'string' ||
        Buffer.byteLength(row.outcome_json) > maxEntryBytes ||
        !sha256Hex(row.physical_sha256) ||
        outcomeDigest(row as Parameters<typeof outcomeDigest>[0]) !== row.physical_sha256 ||
        !(observed?.batchMembers === undefined
          ? observed?.logicalItemLocatorCid === row.logical_item_locator_cid
          : observed.batchMembers.some(member =>
            member.dispatchEntryCid === row.dispatch_entry_cid &&
            member.logicalItemLocatorCid === row.logical_item_locator_cid)) ||
        observed!.logicalRequestScopeCid !== row.logical_request_scope_cid ||
        observed!.responsePhysicalSha256 !==
          row.response_physical_sha256) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({
      dispatchEntryCid: row.dispatch_entry_cid,
      logicalItemLocatorCid: row.logical_item_locator_cid,
      logicalRequestScopeCid: row.logical_request_scope_cid,
      responsePhysicalSha256: row.response_physical_sha256,
      outcomeCid: row.outcome_cid,
      outcomeJson: row.outcome_json,
    });
  };
  const outcome = (dispatchEntryCid: unknown, singleOnly = false) => {
    active();
    if (!cid(dispatchEntryCid) || typeof singleOnly !== 'boolean') fail('InvalidEffectDispatchEntry');
    const row = readOutcome.get(dispatchEntryCid);
    return row === undefined ? undefined :
      materializeOutcome(row, response(dispatchEntryCid, singleOnly));
  };
  return {
    nativeTextUnitBytes, nativeTextBytes, fixedText, fixedInteger, readHead, boundedEntryJson,
    readEntry, readResponse, readResponseLocators, readDispatchEntry, readBatchMember, readBatchLocators,
    readBatchResponse, readBatchMembers, readOutcome, readOutcomeLocators, materialize, current,
    materializeResponse, currentDataVersion, verifiedBatchResponses, materializeBatchResponse,
    response, uniqueLocatorDispatch, responseForLocator, materializeOutcome, outcome,
  };
}
