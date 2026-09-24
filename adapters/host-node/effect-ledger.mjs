import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteEffectLedger} from './sqlite-effect-ledger.mjs';
import {realpathSync} from 'node:fs';

// Process-local observations of physical calls. Durable dispatch entries are
// possible sends after restart, never proof that a call is still in progress.
const activePhysicalFlights = new Map();

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
  maxBatchRows = 1000,
  maxNodes = 64,
  maxDepth = 4,
  maxCallerBytes = 256,
}) {
  if (!Number.isSafeInteger(maxBatchRows) ||
      maxBatchRows < 1 || maxBatchRows > 1000) {
    fail('InvalidEffectLedgerBatchLimit');
  }
  const control = runtimeCore(moon).effectApplicationControl;
  const scope = control.logicalRequestScope(
    authorityScopeCid, callerRequestId, maxCallerBytes,
  );
  const scopeCid = control.logicalRequestScopeCid(scope);
  const physical = openSqliteEffectLedger(root, {
    authorityScopeCid, maxEntries, maxEntryBytes, maxResponseBytes,
    maxStoredBytes,
  });
  const flightPrefix = `${realpathSync(root)}\0${scopeCid}\0`;
  const flightKey = entry =>
    `${flightPrefix}${control.ledgerEntryCid(entry)}`;
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
  const ledger = Object.freeze({
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
    // Read each admitted row's authenticated durable head. MoonBit checks the
    // immutable basis and decides the common Effect frontier.
    // The caller must obtain the admitted Preview and claims from the checked
    // Program; this is progress, never send admission.
    frontierFromDurableHeads(admittedPreview, members, maxWork) {
      if (!admittedPreview || !Array.isArray(members) || members.length === 0 ||
          members.length > 1000 || !Number.isSafeInteger(maxWork) ||
          maxWork < 1 || maxWork > 100_000_000) {
        fail('InvalidEffectProgressInventory');
      }
      const scopes = [];
      const locators = [];
      const keys = [];
      const bases = [];
      const heads = [];
      const activeOwners = [];
      const seen = new Set();
      let totalRows = 0;
      for (const member of members) {
        if (!Array.isArray(member?.claims) ||
            member.claims.length > maxEntries - totalRows) {
          fail('InvalidEffectProgressInventory');
        }
        totalRows += member.claims.length;
        const memberScopes = [];
        const memberBases = [];
        const memberLocators = [];
        const memberKeys = [];
        const memberHeads = [];
        const memberActiveOwners = [];
        for (const claim of member.claims) {
          if (!claim?.basis || !claim.scope || !claim.locator ||
              !claim.key || typeof claim.canonicalRequestCid !== 'string' ||
              typeof claim.intentFingerprintCid !== 'string') {
            fail('InvalidEffectProgressInventory');
          }
          const prepared = control.issuePreparedLedgerEntry(
            claim.basis, maxEntryBytes, maxNodes, maxDepth);
          const dispatching = control.issueNextLedgerEntry(
            prepared, 'dispatching', '', maxEntryBytes, maxNodes, maxDepth);
          if (control.ledgerEntryScopeCid(prepared) !== scopeCid ||
              !control.ledgerEntryAdmitsDispatch(
                dispatching, claim.scope, claim.locator, claim.key,
                claim.canonicalRequestCid) ||
              control.recoveryActionFromEntry(
                claim.locator, claim.intentFingerprintCid, claim.key,
                claim.canonicalRequestCid, prepared, false) !== 1) {
            fail('EffectProgressBindingMismatch');
          }
          const locatorCid = control.logicalItemLocatorCid(claim.locator);
          if (seen.has(locatorCid)) fail('EffectProgressDuplicateLocator');
          seen.add(locatorCid);
          memberScopes.push(claim.scope);
          memberLocators.push(claim.locator);
          memberKeys.push(claim.key);
          memberBases.push(claim.basis);
          const head = validateStored(physical.current(locatorCid))?.entry;
          memberHeads.push(head);
          memberActiveOwners.push(head !== undefined &&
            activePhysicalFlights.has(flightKey(head)));
        }
        scopes.push(memberScopes);
        locators.push(memberLocators);
        keys.push(memberKeys);
        bases.push(memberBases);
        heads.push(memberHeads);
        activeOwners.push(memberActiveOwners);
      }
      return control.setFrontierFromLedger(
        admittedPreview, scopes, locators, keys, bases, heads, activeOwners,
        members.length, totalRows, maxWork);
    },
    // The standard Client Host supplies the same captured Preview owner that
    // retained the Result inputs. Historical progress survives pin release;
    // this path does not turn an uncertain row into a new send permission.
    frontierFromCapturedHeads(captured, members, maxWork) {
      if (typeof moon.clientProgramEffectPreviewLedgerIdentity !== 'function' ||
          !captured) {
        fail('InvalidCapturedEffectProgress');
      }
      return ledger.frontierFromDurableHeads(
        moon.clientProgramEffectPreviewLedgerIdentity(captured),
        members, maxWork);
    },
    // The caller must have won the durable send claim. This observation ends
    // when the physical call settles, independently of response persistence.
    beginPhysicalFlight(dispatching, claims) {
      const entries = Array.isArray(dispatching)
        ? dispatching : [dispatching];
      const binding = Array.isArray(claims) ? claims : [claims];
      if (entries.length === 0 || entries.length !== binding.length) {
        fail('InvalidEffectPhysicalFlight');
      }
      const token = Symbol('effect-physical-flight');
      const keys = entries.map((entry, index) => {
        const claim = binding[index];
        if (!entry || !claim ||
            control.ledgerEntryScopeCid(entry) !== scopeCid ||
            !control.ledgerEntryAdmitsDispatch(
              entry, claim.scope, claim.locator, claim.key,
              claim.canonicalRequestCid)) {
          fail('InvalidEffectPhysicalFlight');
        }
        const locatorCid = control.ledgerEntryLocatorCid(entry);
        const current = validateStored(physical.current(locatorCid));
        if (current?.row.entryCid !== control.ledgerEntryCid(entry)) {
          fail('EffectPhysicalFlightHeadMismatch');
        }
        return flightKey(entry);
      });
      if (new Set(keys).size !== keys.length ||
          keys.some(key => activePhysicalFlights.has(key))) {
        fail('EffectPhysicalFlightCollision');
      }
      for (const key of keys) activePhysicalFlights.set(key, token);
      let ended = false;
      return () => {
        if (ended) return;
        ended = true;
        for (const key of keys) {
          if (activePhysicalFlights.get(key) === token) {
            activePhysicalFlights.delete(key);
          }
        }
      };
    },
    response(dispatchEntryCid) {
      const row = physical.response(dispatchEntryCid);
      if (row !== undefined && row.logicalRequestScopeCid !== scopeCid) {
        fail('EffectLedgerScopeMismatch');
      }
      return row;
    },
    // This is an exact, read-only physical observation for an already
    // possible dispatch. The Host must authorize evidence viewing before
    // calling it; no claim, state transition, or provider request occurs.
    readClaimedResponse(claim) {
      if (!claim?.basis || !claim.scope || !claim.locator || !claim.key ||
          typeof claim.intentFingerprintCid !== 'string' ||
          typeof claim.canonicalRequestCid !== 'string') {
        fail('InvalidEffectResponseRead');
      }
      const locatorCid = control.logicalItemLocatorCid(claim.locator);
      const stored = validateStored(physical.current(locatorCid));
      if (stored === undefined) return undefined;
      if (!control.ledgerEntryMatchesBasis(stored.entry, claim.basis)) {
        fail('EffectLedgerIntentConflict');
      }
      const action = control.recoveryActionFromEntry(
        claim.locator, claim.intentFingerprintCid, claim.key,
        claim.canonicalRequestCid, stored.entry, false);
      if (action === 8 || action === 9) {
        fail('EffectDispatchBindingMismatch');
      }
      if (action < 3 || action > 7) return undefined;
      const row = physical.responseForLocator(locatorCid);
      if (row !== undefined && row.logicalRequestScopeCid !== scopeCid) {
        fail('EffectLedgerScopeMismatch');
      }
      if (row?.batchMembers !== undefined) {
        fail('EffectResponseKindMismatch');
      }
      return row;
    },
    // Read physical outcome custody only through the same exact claim that
    // owns the saved response. This does not admit the outcome's semantic
    // body, issue a receipt, or make a dispatch terminal.
    readClaimedOutcome(claim) {
      const stored = ledger.readClaimedResponse(claim);
      if (stored === undefined) return undefined;
      return physical.outcomeForLocator(stored.logicalItemLocatorCid);
    },
    // Physical custody only. The caller must separately admit the typed
    // provider projection and issue its semantic outcome Receipt. A partial
    // Collections projection can resume from the saved response without a
    // second HTTP send.
    recordClaimedOutcome({claim, claims, rowIndex, responsePhysicalSha256,
      outcomeCid, outcomeJson}) {
      let stored, member;
      if (claims === undefined) {
        if (rowIndex !== undefined) fail('InvalidEffectPhysicalOutcome');
        stored = ledger.readClaimedResponse(claim);
        member = stored;
      } else {
        if (claim !== undefined || !Array.isArray(claims) ||
            !Number.isSafeInteger(rowIndex) ||
            rowIndex < 0 || rowIndex >= claims.length) {
          fail('InvalidEffectPhysicalOutcome');
        }
        stored = ledger.readClaimedBatchResponse(claims);
        member = stored?.batchMembers[rowIndex];
      }
      if (stored === undefined || member === undefined ||
          stored.responsePhysicalSha256 !== responsePhysicalSha256) {
        fail('EffectPhysicalResponseNotOwned');
      }
      return physical.recordOutcome({
        logicalRequestScopeCid: scopeCid,
        logicalItemLocatorCid: member.logicalItemLocatorCid,
        dispatchEntryCid: member.dispatchEntryCid,
        responsePhysicalSha256, outcomeCid, outcomeJson,
      });
    },
    // A sealed Collections response belongs to the original ordered member
    // list. A reordered or partially replaced list cannot borrow its bytes.
    readClaimedBatchResponse(claims) {
      if (!Array.isArray(claims) || claims.length === 0 ||
          claims.length > maxBatchRows) {
        fail('InvalidEffectResponseRead');
      }
      const members = [];
      const seen = new Set();
      for (const claim of claims) {
        if (!claim?.basis || !claim.scope || !claim.locator || !claim.key ||
            typeof claim.intentFingerprintCid !== 'string' ||
            typeof claim.canonicalRequestCid !== 'string' ||
            claim.canonicalRequestCid !== claims[0].canonicalRequestCid) {
          fail('InvalidEffectResponseRead');
        }
        const locatorCid = control.logicalItemLocatorCid(claim.locator);
        if (seen.has(locatorCid)) fail('EffectDispatchBatchBindingMismatch');
        seen.add(locatorCid);
        const stored = validateStored(physical.current(locatorCid));
        if (stored === undefined) return undefined;
        if (!control.ledgerEntryMatchesBasis(stored.entry, claim.basis)) {
          fail('EffectLedgerIntentConflict');
        }
        const action = control.recoveryActionFromEntry(
          claim.locator, claim.intentFingerprintCid, claim.key,
          claim.canonicalRequestCid, stored.entry, false);
        if (action === 8 || action === 9) {
          fail('EffectDispatchBatchBindingMismatch');
        }
        if (action < 3 || action > 7) return undefined;
        members.push({logicalItemLocatorCid: locatorCid});
      }
      const row = physical.responseForLocator(members[0].logicalItemLocatorCid);
      if (row === undefined) return undefined;
      if (row.logicalRequestScopeCid !== scopeCid ||
          row.batchOwnerCid !== row.dispatchEntryCid ||
          row.batchPosition !== 0 || row.batchCount !== members.length ||
          row.batchMembers?.length !== members.length ||
          row.batchMembers.some((member, index) =>
            member.logicalItemLocatorCid !==
              members[index].logicalItemLocatorCid ||
            member.dispatchEntryCid !== physical.dispatchForLocator(
              members[index].logicalItemLocatorCid))) {
        fail('EffectCollectionResponseBindingMismatch');
      }
      return row;
    },
    // Each Collections row retains its own dispatch and outcome owner even
    // though all rows share one durable HTTP observation.
    readClaimedBatchOutcomes(claims) {
      const stored = ledger.readClaimedBatchResponse(claims);
      if (stored === undefined) return undefined;
      return Object.freeze(stored.batchMembers.map(member =>
        physical.outcome(member.dispatchEntryCid)));
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
    claimDispatchBatch(claims) {
      if (!Array.isArray(claims) || claims.length === 0 ||
          claims.length > maxBatchRows) {
        fail('InvalidEffectLedgerBatch');
      }
      const firstRequestCid = claims[0]?.canonicalRequestCid;
      const seen = new Set();
      const seenKeys = new Set();
      for (const claim of claims) {
        const locatorCid = claim?.locator &&
          control.logicalItemLocatorCid(claim.locator);
        const keyCid = claim?.key && control.dispatchKeyCid(claim.key);
        if (typeof firstRequestCid !== 'string' ||
            claim?.canonicalRequestCid !== firstRequestCid ||
            typeof locatorCid !== 'string' || seen.has(locatorCid) ||
            typeof keyCid !== 'string' || seenKeys.has(keyCid) ||
            !control.batchRowsShareMember(
              claims[0].locator, claims[0].key, claim.locator, claim.key)) {
          fail('EffectLedgerBatchBindingMismatch');
        }
        seen.add(locatorCid);
        seenKeys.add(keyCid);
        const prepared = control.issuePreparedLedgerEntry(
          claim.basis, maxEntryBytes, maxNodes, maxDepth);
        const dispatching = control.issueNextLedgerEntry(
          prepared, 'dispatching', '', maxEntryBytes, maxNodes, maxDepth);
        if (control.ledgerEntryScopeCid(prepared) !== scopeCid ||
            !control.ledgerEntryFollows(undefined, prepared) ||
            !control.ledgerEntryFollows(prepared, dispatching) ||
            !control.ledgerEntryAdmitsDispatch(
              dispatching, claim.scope, claim.locator, claim.key,
              claim.canonicalRequestCid)) {
          fail('EffectLedgerBatchBindingMismatch');
        }
      }
      for (let retry = 0; retry < 8; retry++) {
        const operations = [];
        const dispatchingEntries = [];
        const actions = [];
        for (const claim of claims) {
          const locatorCid = control.logicalItemLocatorCid(claim.locator);
          const stored = validateStored(physical.current(locatorCid));
          if (stored !== undefined &&
              !control.ledgerEntryMatchesBasis(stored.entry, claim.basis)) {
            fail('EffectLedgerIntentConflict');
          }
          const action = control.recoveryActionFromEntry(
            claim.locator, claim.intentFingerprintCid, claim.key,
            claim.canonicalRequestCid, stored?.entry, false);
          actions.push(action);
          if (action !== 0 && action !== 1) continue;
          const prepared = action === 0
            ? control.issuePreparedLedgerEntry(
              claim.basis, maxEntryBytes, maxNodes, maxDepth)
            : stored.entry;
          const dispatching = control.issueNextLedgerEntry(
            prepared, 'dispatching', '', maxEntryBytes, maxNodes, maxDepth);
          if (!control.ledgerEntryAdmitsDispatch(
            dispatching, claim.scope, claim.locator, claim.key,
            claim.canonicalRequestCid) ||
              (action === 0 &&
                !control.ledgerEntryFollows(undefined, prepared)) ||
              !control.ledgerEntryFollows(prepared, dispatching)) {
            fail('EffectLedgerBatchBindingMismatch');
          }
          operations.push({
            logicalRequestScopeCid: scopeCid,
            logicalItemLocatorCid: locatorCid,
            expectedRevision: stored?.row.revision ?? 0,
            expectedEntryCid: stored?.row.entryCid ?? null,
            entries: action === 0
              ? [prepared, dispatching].map(entry => ({
                entryCid: control.ledgerEntryCid(entry),
                entryJson: control.ledgerEntryWire(entry),
              }))
              : [{entryCid: control.ledgerEntryCid(dispatching),
                entryJson: control.ledgerEntryWire(dispatching)}],
          });
          dispatchingEntries.push(dispatching);
        }
        if (actions.some(action => action !== 0 && action !== 1)) {
          return Object.freeze({claimed: false, actions: Object.freeze(actions)});
        }
        const result = physical.appendBatch(operations);
        if (result.created) {
          return Object.freeze({claimed: true,
            actions: Object.freeze(actions),
            dispatching: Object.freeze(dispatchingEntries)});
        }
      }
      fail('EffectLedgerClaimContention');
    },
    recordBatchResponse({claims, ownership, credentialUseCid,
      statusCode, responseBytes}) {
      if (!Array.isArray(claims) || claims.length === 0 ||
          claims.length > maxBatchRows || ownership?.claimed !== true ||
          !Array.isArray(ownership.dispatching) ||
          ownership.dispatching.length !== claims.length) {
        fail('EffectDispatchBatchBindingMismatch');
      }
      const canonicalRequestCid = claims[0].canonicalRequestCid;
      const members = claims.map((claim, index) => {
        const dispatching = ownership.dispatching[index];
        if (claim.canonicalRequestCid !== canonicalRequestCid ||
            control.ledgerEntryScopeCid(dispatching) !== scopeCid ||
            !control.ledgerEntryAdmitsDispatch(
              dispatching, claim.scope, claim.locator, claim.key,
              claim.canonicalRequestCid)) {
          fail('EffectDispatchBatchBindingMismatch');
        }
        return {
          logicalItemLocatorCid: control.logicalItemLocatorCid(claim.locator),
          dispatchEntryCid: control.ledgerEntryCid(dispatching),
        };
      });
      return physical.recordBatchResponse({
        logicalRequestScopeCid: scopeCid,
        credentialUseCid,
        statusCode,
        responseBytes,
        members,
      });
    },
    close: () => physical.close(),
  });
  return ledger;
}
