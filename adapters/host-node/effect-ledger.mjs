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
  maxResponseBytes = 1_000_000,
  maxStoredBytes = 134_217_728,
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
    authorityScopeCid, maxEntries, maxEntryBytes, maxResponseBytes,
    maxStoredBytes,
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
  const append = entryJson => {
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
  };
  return Object.freeze({
    scopeCid,
    current(locatorCid) {
      return validateStored(physical.current(locatorCid))?.row;
    },
    currentAdmitted(locatorCid) {
      return validateStored(physical.current(locatorCid))?.entry;
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
    response(dispatchEntryCid) {
      const row = physical.response(dispatchEntryCid);
      if (row !== undefined && row.logicalRequestScopeCid !== scopeCid) {
        fail('EffectLedgerScopeMismatch');
      }
      return row;
    },
    recordResponse({dispatching, scope, locator, key,
      canonicalRequestCid, credentialUseCid, statusCode, responseBytes}) {
      if (!control.ledgerEntryAdmitsDispatch(
        dispatching, scope, locator, key, canonicalRequestCid) ||
          control.ledgerEntryScopeCid(dispatching) !== scopeCid) {
        fail('EffectDispatchBindingMismatch');
      }
      const locatorCid = control.ledgerEntryLocatorCid(dispatching);
      return physical.recordResponse({
        logicalRequestScopeCid: scopeCid,
        logicalItemLocatorCid: locatorCid,
        dispatchEntryCid: control.ledgerEntryCid(dispatching),
        credentialUseCid,
        statusCode,
        responseBytes,
      });
    },
    append,
    claimDispatch({scope, locator, key, basis,
      intentFingerprintCid, canonicalRequestCid}) {
      const prepared = control.issuePreparedLedgerEntry(
        basis, maxEntryBytes, maxNodes, maxDepth);
      const draftAction = control.recoveryActionFromEntry(
        locator, intentFingerprintCid, key, canonicalRequestCid,
        prepared, false);
      const draftDispatching = control.issueNextLedgerEntry(
        prepared, 'dispatching', '', maxEntryBytes, maxNodes, maxDepth);
      if (draftAction !== 1 ||
          !control.ledgerEntryAdmitsDispatch(
            draftDispatching, scope, locator, key, canonicalRequestCid) ||
          control.ledgerEntryScopeCid(prepared) !== scopeCid) {
        fail('EffectDispatchBindingMismatch');
      }
      const locatorCid = control.logicalItemLocatorCid(locator);
      for (let retry = 0; retry < 8; retry++) {
        const stored = validateStored(physical.current(locatorCid));
        if (stored !== undefined &&
            !control.ledgerEntryMatchesBasis(stored.entry, basis)) {
          fail('EffectLedgerIntentConflict');
        }
        const action = control.recoveryActionFromEntry(
          locator, intentFingerprintCid, key, canonicalRequestCid,
          stored?.entry, false);
        if (action === 0) {
          try { append(control.ledgerEntryWire(prepared)); }
          catch (error) {
            if (error?.code !== 'EffectLedgerInvalidTransition') throw error;
          }
          continue;
        }
        if (action === 1) {
          const dispatching = control.issueNextLedgerEntry(
            stored.entry, 'dispatching', '',
            maxEntryBytes, maxNodes, maxDepth);
          try {
            const result = append(control.ledgerEntryWire(dispatching));
            if (result.created) {
              return Object.freeze({action, claimed: true, dispatching});
            }
          } catch (error) {
            if (error?.code !== 'EffectLedgerInvalidTransition') throw error;
          }
          continue;
        }
        if (action >= 3 && action <= 7) {
          return Object.freeze({
            action, claimed: false, entry: stored.entry,
            response: action === 3
              ? physical.response(control.ledgerEntryCid(stored.entry))
              : undefined,
          });
        }
        fail('EffectLedgerIntentConflict');
      }
      fail('EffectLedgerClaimContention');
    },
    close: () => physical.close(),
  });
}
