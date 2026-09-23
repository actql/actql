import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteEffectLedger} from './sqlite-effect-ledger.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// MoonBit admits the canonical fact and its transition. SQLite only owns
// durable bytes and the atomic compare-and-swap of one item head.
export function openEffectLedger({
  moon,
  root,
  authorityScopeCid,
  callerRequestId,
  maxEntries = 100_000,
  maxEntryBytes = 1_000_000,
  maxNodes = 64,
  maxDepth = 4,
  maxCallerBytes = 4096,
}) {
  const control = runtimeCore(moon).effectApplicationControl;
  const scope = control.logicalRequestScope(
    authorityScopeCid, callerRequestId, maxCallerBytes,
  );
  const scopeCid = control.logicalRequestScopeCid(scope);
  const physical = openSqliteEffectLedger(root, {
    authorityScopeCid, maxEntries, maxEntryBytes,
  });
  const admit = wire => control.admitLedgerEntry(
    wire, maxEntryBytes, maxNodes, maxDepth,
  );
  const validateStored = row => {
    if (row === undefined) return undefined;
    if (row.logicalRequestScopeCid !== scopeCid) {
      fail('EffectLedgerScopeMismatch');
    }
    const entry = admit(row.entryJson);
    if (control.ledgerEntryCid(entry) !== row.entryCid ||
        control.ledgerEntryLocatorCid(entry) !== row.logicalItemLocatorCid ||
        control.ledgerEntryScopeCid(entry) !== row.logicalRequestScopeCid ||
        control.ledgerEntryWire(entry) !== row.entryJson) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({row, entry});
  };
  return Object.freeze({
    scopeCid,
    current(locatorCid) {
      return validateStored(physical.current(locatorCid))?.row;
    },
    history(locatorCid, maxRevisions) {
      const rows = physical.history(locatorCid, maxRevisions);
      let previous;
      for (const row of rows) {
        const stored = validateStored(row);
        if (!control.ledgerEntryFollows(previous, stored.entry)) {
          fail('EffectLedgerIntegrityFailed');
        }
        previous = stored.entry;
      }
      return rows;
    },
    append(entryJson) {
      const next = admit(entryJson);
      if (control.ledgerEntryScopeCid(next) !== scopeCid) {
        fail('EffectLedgerScopeMismatch');
      }
      const locatorCid = control.ledgerEntryLocatorCid(next);
      const existing = validateStored(physical.current(locatorCid));
      if (existing?.row.entryCid === control.ledgerEntryCid(next)) {
        if (existing.row.entryJson !== entryJson) {
          fail('EffectLedgerEntryCollision');
        }
        return Object.freeze({entry: existing.row, created: false});
      }
      if (!control.ledgerEntryFollows(existing?.entry, next)) {
        fail('EffectLedgerInvalidTransition');
      }
      const result = physical.append({
        logicalRequestScopeCid: scopeCid,
        logicalItemLocatorCid: locatorCid,
        expectedRevision: existing?.row.revision ?? 0,
        entryCid: control.ledgerEntryCid(next),
        entryJson,
      });
      return Object.freeze({
        ...result,
        entry: validateStored(result.entry).row,
      });
    },
    close: () => physical.close(),
  });
}
