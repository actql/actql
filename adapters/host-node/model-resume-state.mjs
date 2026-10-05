// Storage facts for a fixed Model invocation scope. Core/physical-owner ports
// admit identities and retry classifications; this helper never calls a provider,
// schedules work, classifies a failure, or supplies authorization policy.
const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const natural = value => Number.isSafeInteger(value) && value >= 0;
const fact = value => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).length > 0;
const copy = value => JSON.parse(JSON.stringify(value));
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const ownerKeys = ['runId', 'runDefinitionCid', 'preparedInvocationCid'];
const scopeKeys = [...ownerKeys, 'scopeCid',
  'providerBindingCid', 'inputArtifactCid', 'taskIndex', 'strategyRevision'];
const entryKeys = [...scopeKeys, 'provenance', 'ordinal', 'slotCid', 'attemptIndex', 'attemptCid'];
const deferredKeys = ['checkpointCid', 'intentId', 'claimant', 'generation', 'resolutionCid'];
const select = (value, keys) => Object.fromEntries(keys.map(key => [key, value[key]]));
const omit = (value, keys) => Object.fromEntries(Object.entries(value).filter(([key]) => !keys.includes(key)));
// Keep the existing deferred settlement identity; its real Checkpoint and
// intent already distinguish it from an immediate receipt. Immediate receipts
// name their distinct provenance and authority without fabricated equivalents.
const entryIdentity = value => select(value, value.provenance === 'deferred'
  ? [...ownerKeys, 'checkpointCid', ...scopeKeys.slice(ownerKeys.length),
      'ordinal', 'slotCid', 'attemptIndex', 'attemptCid', ...deferredKeys.slice(1)]
  : [...entryKeys, 'authorityCid']);
const timestamp = value => text(value) && Number.isSafeInteger(Date.parse(value)) &&
  Date.parse(value) >= 0;
const ownerValid = value => text(value?.runId) &&
  ownerKeys.slice(1).every(key => cid(value[key]));
const scopeValid = value => ownerValid(value) &&
  scopeKeys.slice(ownerKeys.length, -2).every(key => cid(value[key])) &&
  natural(value.taskIndex) && natural(value.strategyRevision);
function synchronous(port, input) {
  if (typeof port !== 'function') fail('ModelResumeVerifierUnavailable');
  const result = port(freeze(copy(input)));
  if (result && typeof result.then === 'function') fail('AsyncModelResumeAdmission');
  return copy(result);
}

// Opaque issuer objects must cross this boundary by reference. Never clone,
// serialize or recursively freeze the action or the prepared execution owner.
function immediateAdmission(port, decision, preparedCallSet, facts) {
  if (typeof port !== 'function') fail('ModelImmediateVerifierUnavailable');
  let result;
  try { result = port(Object.freeze({decision, preparedCallSet, ...freeze(copy(facts))})); }
  catch (error) { fail('ModelImmediateGrantRejected', error); }
  if (result && typeof result.then === 'function') fail('AsyncModelResumeAdmission');
  if (!fact(result)) fail('ModelImmediateGrantRejected');
  return copy(result);
}

export function createModelResumeTables(database) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS run_cancellation_fences (
      run_id TEXT PRIMARY KEY NOT NULL,
      owner_json TEXT NOT NULL,
      original_run_wire TEXT NOT NULL,
      cancelled_at TEXT NOT NULL
    ) STRICT;
    CREATE TABLE IF NOT EXISTS resume_model_scopes (
      checkpoint_cid TEXT UNIQUE REFERENCES checkpoints (checkpoint_cid),
      run_id TEXT NOT NULL REFERENCES runs (run_id),
      scope_cid TEXT PRIMARY KEY NOT NULL,
      task_index INTEGER NOT NULL CHECK (task_index >= 0),
      strategy_revision INTEGER NOT NULL CHECK (strategy_revision >= 0),
      inventory_json TEXT NOT NULL,
      originals_json TEXT NOT NULL,
      slot_count INTEGER NOT NULL CHECK (slot_count >= 0),
      registered_at TEXT NOT NULL,
      registration_kind TEXT NOT NULL CHECK (registration_kind IN ('immediate', 'deferred')),
      checkpoint_inventory_json TEXT NOT NULL DEFAULT '',
      checkpoint_originals_json TEXT NOT NULL DEFAULT '',
      CHECK (registration_kind != 'deferred' OR checkpoint_cid IS NOT NULL),
      UNIQUE (run_id, task_index)
    ) STRICT;
    CREATE TABLE IF NOT EXISTS resume_model_slots (
      scope_cid TEXT NOT NULL REFERENCES resume_model_scopes (scope_cid),
      ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
      slot_cid TEXT NOT NULL,
      binding_json TEXT NOT NULL,
      state TEXT NOT NULL CHECK (state IN
        ('Unsent', 'EnteredUnknown', 'SavedSuccess', 'SavedFailure')),
      attempt_index INTEGER NOT NULL CHECK (attempt_index >= 0),
      PRIMARY KEY (scope_cid, ordinal),
      UNIQUE (scope_cid, slot_cid),
      CHECK ((state = 'Unsent') = (attempt_index = 0))
    ) STRICT;
    CREATE TABLE IF NOT EXISTS resume_model_attempts (
      scope_cid TEXT NOT NULL,
      ordinal INTEGER NOT NULL,
      attempt_index INTEGER NOT NULL CHECK (attempt_index >= 1),
      attempt_cid TEXT NOT NULL UNIQUE,
      entry_json TEXT NOT NULL,
      attempt_wire TEXT NOT NULL,
      authority_wire TEXT NOT NULL,
      state TEXT NOT NULL CHECK (state IN
        ('EnteredUnknown', 'SavedSuccess', 'SavedFailure')),
      settlement_json TEXT NOT NULL DEFAULT '',
      entered_at TEXT NOT NULL,
      settled_at TEXT NOT NULL DEFAULT '',
      PRIMARY KEY (scope_cid, ordinal, attempt_index),
      FOREIGN KEY (scope_cid, ordinal) REFERENCES resume_model_slots (scope_cid, ordinal),
      CHECK ((state = 'EnteredUnknown') = (settlement_json = ''))
    ) STRICT;
  `);
}

// Configured trusted ports, all fail closed when absent:
// admitOriginalRun({originalRunWire}) -> {runId, runDefinitionCid,
//   preparedInvocationCid}, checked against the original Run admission.
// admitCallSet({checkpointWire, originalRunWire, preparedInvocationWire,
//   scopeWire, providerBindingWire, slotWires, fixedInputReceiptWire,
//   ...ownerInputs}) -> {...scope identity, taskIndex, strategyRevision,
//   fixedInputCustody, retryBinding,
//   slots:[{ordinal,slotCid,modelTaskCid,fixedRequestCid,maxAttempts}]}.
// This port must check the owner-issued, durably held original inputs and exact
// original Run/PreparedInvocation/scope/provider/slot linkage, not just schema
// validity or caller-provided CIDs. Empty inventories are valid.
// admitImmediateCallSet(originals) establishes the same complete immutable
// inventory without checkpoint/review originals, plus runValidUntil from the
// actual admitted original Run. This historical port also runs on restart.
// admitImmediateEntry({decision, preparedCallSet, inventory, originals, slot,
//   attemptIndex, attemptCid, attemptWire, authorityWire, at}) receives the actual
// opaque issuer objects by reference. It synchronously checks current action,
// exact prepared owner/attempt/authority and original Run validity at the trusted
// journal time, including the existing physical Run/dispatch owner's live fence
// and ordering policy. This journal serializes slots, not cross-slot scheduling.
// It returns {...scope identity, ordinal, slotCid, attemptIndex,
//   attemptCid, authorityCid, current:true, admittedAt:at, runValidUntil,
//   dispatchValidUntil}. The dispatch bound is owner-derived and may simply be
// the Run bound for AccountAllow; it is not a manufactured approval TTL.
// A valid cached permit may serve another slot only after this exact entry check.
// admitAttempt({inventory, originals, slot, attemptIndex, attemptCid, attemptWire, authorityWire,
//   admission}) -> {attemptIndex,attemptCid}; checks the immutable attempt
// original against the bound Model retry contract and historical authority.
// Both immutable admit ports also run on reads after expiry/cancellation; they
// must not require current permission. Fresh entry uses the dedicated current
// immediate issuer port, or admissionLocked plus the committed deferred grant.
// verifySettlement({inventory, originals, slot, entry, attemptWire, authorityWire}) is async:
// it derives deterministic original Store keys from these persisted facts,
// verifies durable originals/custody, and returns null if still unknown, or
// {entry: <exact entry identity>, state:'SavedSuccess'|'SavedFailure',
//  durable:true, evidence:<checked original refs>, retryAllowed:boolean}.
// The verifier must never synthesize a failure from a sent-unknown attempt.
// Distinct entered and settled originals are retained; no original is replaced.
export function createModelResumeState(database, {
  verifier, transaction, alive, now, iso, fault, admissionLocked, confirmEntryGrant, checkpoint, run,
}) {
  const q = {
    scope: database.prepare('SELECT * FROM resume_model_scopes WHERE checkpoint_cid = ?'),
    scopeByCid: database.prepare('SELECT * FROM resume_model_scopes WHERE scope_cid = ?'),
    slots: database.prepare('SELECT * FROM resume_model_slots WHERE scope_cid = ? ORDER BY ordinal'),
    attempts: database.prepare('SELECT * FROM resume_model_attempts WHERE scope_cid = ? ORDER BY ordinal, attempt_index'),
    cancelled: database.prepare('SELECT * FROM run_cancellation_fences WHERE run_id = ?'),
    insertCancel: database.prepare('INSERT INTO run_cancellation_fences VALUES (?, ?, ?, ?)'),
    insertScope: database.prepare(`INSERT INTO resume_model_scopes
      (checkpoint_cid, run_id, scope_cid, task_index, strategy_revision,
       inventory_json, originals_json, slot_count, registered_at, registration_kind)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`),
    attachCheckpoint: database.prepare(`UPDATE resume_model_scopes SET checkpoint_cid = ?,
      checkpoint_inventory_json = ?, checkpoint_originals_json = ?
      WHERE scope_cid = ? AND checkpoint_cid IS NULL AND registration_kind = 'immediate'`),
    insertSlot: database.prepare("INSERT INTO resume_model_slots VALUES (?, ?, ?, ?, 'Unsent', 0)"),
    insertAttempt: database.prepare(`INSERT INTO resume_model_attempts
      VALUES (?, ?, ?, ?, ?, ?, ?, 'EnteredUnknown', '', ?, '')`),
    advanceSlot: database.prepare(`UPDATE resume_model_slots
      SET state = 'EnteredUnknown', attempt_index = ?
      WHERE scope_cid = ? AND ordinal = ? AND state = ? AND attempt_index = ?`),
    settleAttempt: database.prepare(`UPDATE resume_model_attempts
      SET state = ?, settlement_json = ?, settled_at = ?
      WHERE scope_cid = ? AND ordinal = ? AND attempt_index = ?
        AND state = 'EnteredUnknown'`),
    settleSlot: database.prepare(`UPDATE resume_model_slots SET state = ?
      WHERE scope_cid = ? AND ordinal = ? AND attempt_index = ?
        AND state = 'EnteredUnknown'`),
  };
  const changed = result => {
    if (result.changes !== 1) fail('ModelResumeStateConflict');
  };
  function admittedOwner(originalRunWire) {
    if (!text(originalRunWire)) fail('InvalidModelOriginalRun');
    const owner = synchronous(verifier?.admitOriginalRun, {originalRunWire});
    if (!ownerValid(owner)) fail('InvalidModelOriginalRun');
    return select(owner, ownerKeys);
  }
  function requireNotCancelled(owner) {
    const cancelled = q.cancelled.get(owner.runId);
    if (cancelled === undefined) return;
    if (!same(JSON.parse(cancelled.owner_json), select(owner, ownerKeys))) {
      fail('ModelRunIdentityMismatch');
    }
    fail('ModelRunCancelled');
  }
  function prepareInventory(input, sealed) {
    const immediate = sealed === undefined;
    if (input === null || typeof input !== 'object' ||
        !['originalRunWire', 'preparedInvocationWire', 'scopeWire',
          'providerBindingWire', 'fixedInputReceiptWire'].every(key => text(input[key])) ||
        !Array.isArray(input.slotWires) || !input.slotWires.every(text)) {
      fail('ModelCallInventoryRequired');
    }
    if (immediate && ['checkpointWire', 'reviewWire'].some(key => Object.hasOwn(input, key))) {
      fail('ModelImmediateProvenanceMismatch');
    }
    const originals = copy(immediate ? input : {...input, checkpointWire: sealed.checkpoint_wire});
    const inventory = synchronous(immediate ? verifier?.admitImmediateCallSet : verifier?.admitCallSet, originals);
    const body = immediate ? undefined : JSON.parse(sealed.checkpoint_wire);
    if (!scopeValid(inventory) ||
        !same(select(inventory, ownerKeys), admittedOwner(input.originalRunWire)) ||
        !fact(inventory.fixedInputCustody) || !fact(inventory.retryBinding) ||
        !Array.isArray(inventory.slots) || inventory.slots.length !== input.slotWires.length ||
        (immediate ? Object.hasOwn(inventory, 'checkpointCid') || !timestamp(inventory.runValidUntil)
          : inventory.checkpointCid !== sealed.checkpoint_cid || inventory.runId !== sealed.run_id ||
            inventory.runDefinitionCid !== body.run_definition_cid ||
            inventory.scopeCid !== body.required_artifact.artifact_cid)) {
      fail('InvalidModelCallInventory');
    }
    const ids = new Set();
    inventory.slots.forEach((slot, ordinal) => {
      if (slot.ordinal !== ordinal || !cid(slot.slotCid) || ids.has(slot.slotCid) ||
          !cid(slot.modelTaskCid) || !cid(slot.fixedRequestCid) ||
          !Number.isSafeInteger(slot.maxAttempts) || slot.maxAttempts < 1) {
        fail('InvalidModelCallInventory');
      }
      ids.add(slot.slotCid);
    });
    return freeze({inventory, originals});
  }
  function prepare(sealed, input) {
    if (JSON.parse(sealed.checkpoint_wire).kind !== 'model_invocation') {
      if (input !== undefined) fail('ModelCheckpointKindMismatch');
      return undefined;
    }
    return prepareInventory(input, sealed);
  }
  function sameCallSet(a, b) {
    return same(omit(a.inventory, ['checkpointCid', 'runValidUntil']),
      omit(b.inventory, ['checkpointCid', 'runValidUntil'])) &&
      same(omit(a.originals, ['checkpointWire', 'reviewWire']),
        omit(b.originals, ['checkpointWire', 'reviewWire']));
  }
  function checked(identity) {
    if (!scopeValid(identity)) fail('InvalidModelResumeIdentity');
    const row = cid(identity.checkpointCid) ? q.scope.get(identity.checkpointCid)
      : q.scopeByCid.get(identity.scopeCid);
    if (row === undefined) fail('ModelResumeInventoryCorrupt');
    try {
      const saved = JSON.parse(row.inventory_json);
      const originals = JSON.parse(row.originals_json);
      let deferred;
      if (row.checkpoint_cid !== null) {
        const cp = checkpoint(row.checkpoint_cid);
        if (cp === undefined || cp.run_id !== row.run_id) fail('ModelResumeInventoryCorrupt');
        const deferredOriginals = row.registration_kind === 'deferred' ? originals
          : JSON.parse(row.checkpoint_originals_json);
        if (deferredOriginals.checkpointWire !== cp.checkpoint_wire) fail('ModelResumeInventoryCorrupt');
        deferred = prepare(cp, deferredOriginals);
        if (deferred === undefined || (row.registration_kind === 'immediate' &&
            (!same(JSON.parse(row.checkpoint_inventory_json), deferred.inventory) ||
             !sameCallSet({inventory: saved, originals}, deferred)))) fail('ModelResumeInventoryCorrupt');
      } else if (row.checkpoint_inventory_json !== '' || row.checkpoint_originals_json !== '') {
        fail('ModelResumeInventoryCorrupt');
      }
      const prepared = row.registration_kind === 'deferred' ? deferred
        : row.registration_kind === 'immediate' ? prepareInventory(originals) : undefined;
      if (prepared === undefined || !same(saved, prepared.inventory) ||
          row.run_id !== saved.runId || row.scope_cid !== saved.scopeCid ||
          row.task_index !== saved.taskIndex || row.strategy_revision !== saved.strategyRevision ||
          row.slot_count !== saved.slots.length || run(row.run_id) === undefined ||
          (row.registration_kind === 'deferred' &&
            (row.checkpoint_inventory_json !== '' || row.checkpoint_originals_json !== ''))) {
        fail('ModelResumeInventoryCorrupt');
      }
      if (!same(select(saved, scopeKeys), select(identity, scopeKeys)) ||
          (Object.hasOwn(identity, 'checkpointCid') && identity.checkpointCid !== row.checkpoint_cid)) {
        fail('ModelResumeIdentityMismatch');
      }
      const slots = q.slots.all(saved.scopeCid);
      const attempts = q.attempts.all(saved.scopeCid);
      if (slots.length !== saved.slots.length) fail('ModelResumeInventoryCorrupt');
      for (const [index, slot] of slots.entries()) {
        const history = attempts.filter(attempt => attempt.ordinal === index);
        if (slot.ordinal !== index || slot.slot_cid !== saved.slots[index].slotCid ||
            slot.binding_json !== JSON.stringify(saved.slots[index]) ||
            slot.attempt_index !== history.length ||
            slot.state !== (history.at(-1)?.state ?? 'Unsent')) fail('ModelResumeInventoryCorrupt');
        for (const [attemptIndex, attempt] of history.entries()) {
          const entry = JSON.parse(attempt.entry_json);
          const admission = entry.admission;
          if (attempt.attempt_index !== attemptIndex + 1 || attempt.attempt_cid !== entry.attemptCid ||
              entry.attemptIndex !== attemptIndex + 1 || entry.ordinal !== index ||
              entry.slotCid !== slot.slot_cid || entry.admittedAt !== attempt.entered_at ||
              admission?.kind !== 'model_invocation' || admission.provenance !== entry.provenance ||
              admission.requiredArtifactCid !== saved.scopeCid || admission.runId !== saved.runId ||
              admission.admittedAt !== entry.admittedAt || !text(entry.modelGrantExpiresAt) ||
              entry.modelGrantExpiresAt !== admission.modelGrantExpiresAt ||
              !same(select(entry, scopeKeys), select(saved, scopeKeys))) fail('ModelResumeInventoryCorrupt');
          let attemptOriginals;
          if (entry.provenance === 'deferred') {
            if (deferred === undefined || entry.checkpointCid !== row.checkpoint_cid ||
                !text(entry.intentId) || !text(entry.claimant) ||
                !Number.isSafeInteger(entry.generation) || entry.generation < 1 || !cid(entry.resolutionCid) ||
                !same(select(admission, deferredKeys), select(entry, deferredKeys))) fail('ModelResumeInventoryCorrupt');
            attemptOriginals = deferred.originals;
          } else if (entry.provenance === 'immediate') {
            if (row.registration_kind !== 'immediate' || deferredKeys.some(key => Object.hasOwn(entry, key)) ||
                !cid(entry.authorityCid) || entry.authorityCid !== admission.authorityCid ||
                !timestamp(admission.dispatchValidUntil) || admission.runValidUntil !== saved.runValidUntil ||
                entry.modelGrantExpiresAt !== iso(Math.min(Date.parse(saved.runValidUntil),
                  Date.parse(admission.dispatchValidUntil)))) fail('ModelResumeInventoryCorrupt');
            attemptOriginals = originals;
          } else fail('ModelResumeInventoryCorrupt');
          const verifiedAttempt = synchronous(verifier?.admitAttempt, {
            inventory: saved, originals: attemptOriginals, slot: saved.slots[index], attemptIndex: entry.attemptIndex,
            attemptCid: entry.attemptCid, attemptWire: attempt.attempt_wire,
            authorityWire: attempt.authority_wire, admission,
          });
          if (verifiedAttempt.attemptCid !== entry.attemptCid || verifiedAttempt.attemptIndex !== entry.attemptIndex ||
              history.length > saved.slots[index].maxAttempts) fail('ModelResumeInventoryCorrupt');
          if (attempt.state !== 'EnteredUnknown') {
            const settlement = JSON.parse(attempt.settlement_json);
            if (!validSettlement(settlement, entry) || settlement.state !== attempt.state) fail('ModelResumeInventoryCorrupt');
          }
          if (attemptIndex + 1 < history.length && (attempt.state !== 'SavedFailure' ||
              JSON.parse(attempt.settlement_json).retryAllowed !== true)) fail('ModelResumeInventoryCorrupt');
        }
      }
      if (attempts.some(attempt => !slots[attempt.ordinal])) fail('ModelResumeInventoryCorrupt');
      return {inventory: saved, originals, checkpointCid: row.checkpoint_cid, deferred, slots, attempts};
    } catch (error) {
      if (error.code === 'ModelResumeIdentityMismatch' || error.code === 'ModelResumeVerifierUnavailable') throw error;
      fail('ModelResumeInventoryCorrupt', error);
    }
  }
  function insertInventory(prepared, kind, at) {
    const {inventory, originals} = prepared;
    requireNotCancelled(inventory);
    for (const row of database.prepare('SELECT inventory_json, originals_json FROM resume_model_scopes WHERE run_id = ?').all(inventory.runId)) {
      if (!same(select(JSON.parse(row.inventory_json), ownerKeys), select(inventory, ownerKeys)) ||
          JSON.parse(row.originals_json).originalRunWire !== originals.originalRunWire) fail('ModelRunIdentityMismatch');
    }
    const occurrence = database.prepare('SELECT scope_cid FROM resume_model_scopes WHERE run_id = ? AND task_index = ?')
      .get(inventory.runId, inventory.taskIndex);
    if (occurrence !== undefined) fail('ModelResumeOccurrenceConflict');
    q.insertScope.run(inventory.checkpointCid ?? null, inventory.runId, inventory.scopeCid,
      inventory.taskIndex, inventory.strategyRevision, JSON.stringify(inventory), JSON.stringify(originals),
      inventory.slots.length, at, kind);
    for (const slot of inventory.slots) {
      q.insertSlot.run(inventory.scopeCid, slot.ordinal, slot.slotCid, JSON.stringify(slot));
      fault('registerResumeCallSlot');
    }
    fault('registerResumeCallSet');
  }
  function registerImmediateLocked(prepared, at) {
    requireNotCancelled(prepared.inventory);
    const row = q.scopeByCid.get(prepared.inventory.scopeCid);
    if (row === undefined) return insertInventory(prepared, 'immediate', at);
    const stored = checked(prepared.inventory);
    if (row.registration_kind !== 'immediate' ||
        !same(stored.inventory, prepared.inventory) || !same(stored.originals, prepared.originals)) {
      fail('ModelResumeInventoryConflict');
    }
    if (row.checkpoint_cid !== null) fail('ModelImmediateProvenanceMismatch');
  }
  function registerLocked(sealed, prepared, at, existing = false, attachImmediate = false) {
    if (prepared === undefined) return;
    const {inventory, originals} = prepared;
    requireNotCancelled(inventory);
    if (existing) {
      const stored = checked(inventory);
      if (stored.deferred === undefined || !same(stored.deferred.inventory, inventory) ||
          !same(stored.deferred.originals, originals)) fail('ModelResumeInventoryConflict');
      return;
    }
    const row = q.scopeByCid.get(inventory.scopeCid);
    if (row !== undefined) {
      if (!attachImmediate || row.registration_kind !== 'immediate' || row.checkpoint_cid !== null) {
        fail('ModelResumeInventoryConflict');
      }
      const stored = checked(JSON.parse(row.inventory_json));
      if (!sameCallSet(stored, prepared)) fail('ModelResumeInventoryConflict');
      changed(q.attachCheckpoint.run(sealed.checkpoint_cid, JSON.stringify(inventory),
        JSON.stringify(originals), inventory.scopeCid));
      fault('attachModelCallSetCheckpoint');
      return;
    }
    if (attachImmediate) fail('ModelImmediateInventoryRequired');
    insertInventory(prepared, 'deferred', at);
  }
  function entryFor(state, reference) {
    const attempt = state.attempts.find(value => value.ordinal === reference.ordinal &&
      value.attempt_index === reference.attemptIndex);
    if (attempt === undefined) fail('ModelResumeAttemptNotEntered');
    const entry = JSON.parse(attempt.entry_json);
    if (!same(entryIdentity(entry), entryIdentity(reference))) {
      fail('ModelResumeAttemptMismatch');
    }
    return {attempt, entry};
  }
  function validSettlement(value, entry) {
    return value !== null && value?.durable === true &&
      ['SavedSuccess', 'SavedFailure'].includes(value.state) &&
      typeof value.retryAllowed === 'boolean' &&
      (value.state === 'SavedFailure' || value.retryAllowed === false) &&
      fact(value.evidence) &&
      same(value.entry, entryIdentity(entry));
  }
  function slotForEntry(state, reference) {
    const slot = state.slots[reference.ordinal];
    const binding = state.inventory.slots[reference.ordinal];
    if (!natural(reference.ordinal) || slot === undefined || slot.slot_cid !== reference.slotCid) {
      fail('ModelResumeSlotMismatch');
    }
    const previous = state.attempts.find(value => value.ordinal === slot.ordinal &&
      value.attempt_index === slot.attempt_index);
    if (slot.state === 'EnteredUnknown') fail('ModelResumeAttemptUnknown');
    if (slot.state === 'SavedSuccess' || (slot.state === 'SavedFailure' &&
        JSON.parse(previous.settlement_json).retryAllowed !== true)) fail('ModelResumeCallSettled');
    if (reference.attemptIndex !== slot.attempt_index + 1 || reference.attemptIndex > binding.maxAttempts ||
        !cid(reference.attemptCid) || !text(reference.attemptWire) || !text(reference.authorityWire)) {
      fail('ModelResumeAttemptMismatch');
    }
    return {slot, binding};
  }
  function appendEntered(state, reference, admission, step) {
    const {slot, binding} = slotForEntry(state, reference);
    const originals = admission.provenance === 'deferred' ? state.deferred.originals : state.originals;
    const admitted = synchronous(verifier?.admitAttempt, {
      inventory: state.inventory, originals, slot: binding,
      attemptIndex: reference.attemptIndex, attemptCid: reference.attemptCid,
      attemptWire: reference.attemptWire, authorityWire: reference.authorityWire, admission,
    });
    if (admitted.attemptCid !== reference.attemptCid || admitted.attemptIndex !== reference.attemptIndex) {
      fail('ModelResumeAttemptMismatch');
    }
    const entry = {...select(state.inventory, scopeKeys), provenance: admission.provenance,
      ordinal: slot.ordinal, slotCid: slot.slot_cid, attemptIndex: reference.attemptIndex,
      attemptCid: reference.attemptCid, admittedAt: admission.admittedAt,
      modelGrantExpiresAt: admission.modelGrantExpiresAt, admission,
      ...select(admission, admission.provenance === 'deferred' ? deferredKeys : ['authorityCid'])};
    q.insertAttempt.run(entry.scopeCid, entry.ordinal, entry.attemptIndex,
      entry.attemptCid, JSON.stringify(entry), reference.attemptWire, reference.authorityWire, entry.admittedAt);
    changed(q.advanceSlot.run(entry.attemptIndex, entry.scopeCid, entry.ordinal, slot.state, slot.attempt_index));
    fault(step);
    return freeze({...entry, state: 'EnteredUnknown'});
  }
  async function observeCall(reference, provenance, step) {
    alive();
    const before = transaction.run(() => {
      const state = checked(reference);
      const {attempt, entry} = entryFor(state, reference);
      if (entry.provenance !== provenance) fail('ModelResumeAttemptMismatch');
      return {inventory: state.inventory,
        originals: provenance === 'deferred' ? state.deferred.originals : state.originals,
        slot: state.inventory.slots[reference.ordinal], entry,
        attemptWire: attempt.attempt_wire, authorityWire: attempt.authority_wire};
    });
    if (typeof verifier?.verifySettlement !== 'function') fail('ModelResumeVerifierUnavailable');
    const result = await verifier.verifySettlement(freeze(copy(before)));
    alive();
    if (result === null) return transaction.run(() => {
      const state = checked(reference);
      const {attempt, entry} = entryFor(state, reference);
      return freeze({...entry, state: attempt.state, settlement:
        attempt.settlement_json === '' ? null : JSON.parse(attempt.settlement_json)});
    });
    const settlement = copy(result);
    if (!validSettlement(settlement, before.entry)) fail('ModelResumeSettlementUnverified');
    return transaction.run(() => {
      const state = checked(reference);
      const {attempt, entry} = entryFor(state, reference);
      if (attempt.state !== 'EnteredUnknown') {
        if (!same(JSON.parse(attempt.settlement_json), settlement)) fail('ModelResumeSettlementConflict');
        return freeze({...entry, state: attempt.state, settlement});
      }
      changed(q.settleAttempt.run(settlement.state, JSON.stringify(settlement),
        iso(now()), entry.scopeCid, entry.ordinal, entry.attemptIndex));
      changed(q.settleSlot.run(settlement.state, entry.scopeCid, entry.ordinal, entry.attemptIndex));
      fault(step);
      return freeze({...entry, state: settlement.state, settlement});
    });
  }
  const view = state => freeze({...select(state.inventory, scopeKeys), checkpointCid: state.checkpointCid,
    slots: state.slots.map(slot => ({...JSON.parse(slot.binding_json), state: slot.state,
      attemptIndex: slot.attempt_index,
      attempts: state.attempts.filter(attempt => attempt.ordinal === slot.ordinal)
        .map(attempt => ({...JSON.parse(attempt.entry_json), state: attempt.state,
          settlement: attempt.settlement_json === '' ? null : JSON.parse(attempt.settlement_json)})),
    })),
  });
  return Object.freeze({prepare, prepareImmediate: prepareInventory, registerLocked, registerImmediateLocked,
    // Read under the parent transaction before a generic unsent transition.
    // Every entered attempt counts, including saved outcomes; this establishes
    // a physical-start fact, never an aggregate Model completion decision.
    hasEnteredUnderParentLocked({checkpointCid, intentId, runId}) {
      const rows = database.prepare('SELECT inventory_json FROM resume_model_scopes WHERE run_id = ?').all(runId);
      for (const row of rows) {
        const state = checked(JSON.parse(row.inventory_json));
        for (const attempt of state.attempts) {
          const entry = JSON.parse(attempt.entry_json);
          const parent = entry.admission?.parentResumeFence;
          if (parent === undefined) continue;
          if (entry.provenance !== 'immediate' || entry.runId !== runId ||
              typeof parent.generation !== 'number' || typeof parent.claimant !== 'string') {
            fail('ModelResumeInventoryCorrupt');
          }
          if (parent.checkpointCid === checkpointCid && parent.intentId === intentId) return true;
        }
      }
      return false;
    },
    hasEnteredLocked({checkpointCid, intentId, runId, resolutionCid}) {
      const row = q.scope.get(checkpointCid);
      if (row === undefined) fail('ModelResumeInventoryCorrupt');
      let identity;
      try { identity = JSON.parse(row.inventory_json); }
      catch (error) { fail('ModelResumeInventoryCorrupt', error); }
      if (!scopeValid(identity)) fail('ModelResumeInventoryCorrupt');
      const state = checked(identity);
      if (state.checkpointCid !== checkpointCid ||
          state.inventory.runId !== runId || !text(intentId) || !cid(resolutionCid) ||
          state.attempts.some(attempt => {
            const entry = JSON.parse(attempt.entry_json);
            return entry.provenance === 'deferred' &&
              (entry.intentId !== intentId || entry.resolutionCid !== resolutionCid);
          })) fail('ModelResumeInventoryCorrupt');
      return state.attempts.length > 0;
    },
    // Only used under the parent journal's transaction. These checked originals
    // select the compiled Core's Model-specific Resolution admission; no public
    // summary or caller-supplied CID can replace the retained request.
    resolutionOriginals(checkpointCid) {
      const row = q.scope.get(checkpointCid);
      if (row === undefined) fail('ModelResumeInventoryCorrupt');
      const state = checked(JSON.parse(row.inventory_json));
      requireNotCancelled(state.inventory);
      return freeze(copy(state.deferred.originals));
    },
    grantContext(checkpointCid) {
      const row = q.scope.get(checkpointCid);
      if (row === undefined) fail('ModelResumeInventoryCorrupt');
      const state = checked(JSON.parse(row.inventory_json));
      requireNotCancelled(state.inventory);
      return freeze({inventory: state.deferred.inventory, originals: state.deferred.originals});
    },
    immediateOriginals(prepared) {
      if (prepared === undefined) fail('ModelCallInventoryRequired');
      requireNotCancelled(prepared.inventory);
      return prepared.originals;
    },
    public: {
      // Safe public metadata for the exact inspected Model Checkpoint. Re-admit
      // retained originals; the requested CID selects a row, never authority.
      modelCheckpointSummary(checkpointCid) {
        alive();
        if (!cid(checkpointCid)) fail('InvalidCheckpointReference');
        return transaction.run(() => {
          const cp = checkpoint(checkpointCid);
          if (cp === undefined) fail('CheckpointNotFound');
          if (JSON.parse(cp.checkpoint_wire).kind !== 'model_invocation') {
            fail('ModelCheckpointKindMismatch');
          }
          const row = q.scope.get(checkpointCid);
          if (row === undefined) fail('ModelResumeInventoryCorrupt');
          const state = checked(JSON.parse(row.inventory_json));
          const reviewProjectionCid = JSON.parse(cp.checkpoint_wire).review_projection_cid;
          if (!cid(reviewProjectionCid)) fail('ModelResumeInventoryCorrupt');
          return freeze({checkpointCid, ...select(state.inventory, ['runId',
            'runDefinitionCid', 'scopeCid']), reviewProjectionCid,
            preparedInvocationCid: state.inventory.preparedInvocationCid});
        });
      },
      readResumeCalls(identity) {
        alive();
        if (!cid(identity?.checkpointCid)) fail('InvalidModelResumeIdentity');
        return transaction.run(() => view(checked(identity)));
      },
      readModelCalls(identity) {
        alive();
        return transaction.run(() => view(checked(identity)));
      },
      readModelAttemptOriginals(reference) {
        alive();
        return transaction.run(() => {
          const state = checked(reference);
          const {attempt, entry} = entryFor(state, reference);
          return freeze({entry: copy(entry), attemptWire: attempt.attempt_wire,
            authorityWire: attempt.authority_wire});
        });
      },
      // The original Run and full inventory are already durable. A fresh
      // decision and prepared execution owner cross the trusted port unchanged.
      // Call the provider immediately after return, without any intervening await.
      enterImmediateModelCall(reference, {decision, preparedCallSet, parentResume} = {}) {
        alive();
        return transaction.run(() => {
          if (deferredKeys.some(key => Object.hasOwn(reference, key))) fail('ModelImmediateProvenanceMismatch');
          const state = checked(reference);
          requireNotCancelled(state.inventory);
          if (state.checkpointCid !== null) fail('ModelImmediateProvenanceMismatch');
          const at = now(); const admittedAt = iso(at);
          const status = run(state.inventory.runId)?.status;
          let parentAdmission;
          if (status === 'resuming' && parentResume !== undefined) {
            parentAdmission = admissionLocked(parentResume.claim, parentResume.checkpointCid, at);
            if (parentAdmission.runId !== state.inventory.runId || parentAdmission.kind !== 'read_access') {
              fail('ModelImmediateParentResumeMismatch');
            }
          } else if (status !== 'running' || parentResume !== undefined) {
            fail('ModelImmediateRunNotRunning');
          }
          if (at >= Date.parse(state.inventory.runValidUntil)) fail('ModelRunExpired');
          const {binding} = slotForEntry(state, reference);
          const grant = immediateAdmission(verifier?.admitImmediateEntry, decision, preparedCallSet, {
            inventory: state.inventory, originals: state.originals, slot: binding,
            attemptIndex: reference.attemptIndex, attemptCid: reference.attemptCid,
            attemptWire: reference.attemptWire, authorityWire: reference.authorityWire, at: admittedAt,
          });
          if (grant?.current !== true || grant.admittedAt !== admittedAt ||
              !same(select(grant, scopeKeys), select(state.inventory, scopeKeys)) ||
              grant.ordinal !== reference.ordinal || grant.slotCid !== reference.slotCid ||
              grant.attemptCid !== reference.attemptCid || grant.attemptIndex !== reference.attemptIndex ||
              !cid(grant.authorityCid) || grant.runValidUntil !== state.inventory.runValidUntil ||
              !timestamp(grant.dispatchValidUntil) || at >= Date.parse(grant.dispatchValidUntil)) {
            fail('ModelImmediateGrantRejected');
          }
          const modelGrantExpiresAt = iso(Math.min(Date.parse(grant.runValidUntil),
            Date.parse(grant.dispatchValidUntil)));
          return appendEntered(state, reference, {kind: 'model_invocation', provenance: 'immediate',
            runId: state.inventory.runId, requiredArtifactCid: state.inventory.scopeCid,
            authorityCid: grant.authorityCid, admittedAt, runValidUntil: grant.runValidUntil,
            dispatchValidUntil: grant.dispatchValidUntil, modelGrantExpiresAt,
            ...(parentAdmission === undefined ? {} : {parentResumeFence: {
              checkpointCid: parentAdmission.checkpointCid, intentId: parentAdmission.intentId,
              generation: parentAdmission.generation, claimant: parentAdmission.claimant}})}, 'enterImmediateModelCall');
        });
      },
      enterResumedCall(claim, reference) {
        alive();
        return transaction.run(() => {
          const state = checked(reference);
          requireNotCancelled(state.inventory);
          if (state.deferred === undefined || reference.checkpointCid !== state.checkpointCid) {
            fail('ModelResumeIdentityMismatch');
          }
          const at = now();
          const admission = admissionLocked(claim, reference.checkpointCid, at);
          if (admission.kind !== 'model_invocation' ||
              admission.runId !== state.inventory.runId ||
              admission.requiredArtifactCid !== state.inventory.scopeCid ||
              reference.resolutionCid !== admission.resolutionCid ||
              claim.runId !== state.inventory.runId) fail('ModelResumeIdentityMismatch');
          const modelGrantExpiresAt = confirmEntryGrant(state.deferred.originals,
            state.deferred.inventory, admission, at);
          return appendEntered(state, reference, {...admission, provenance: 'deferred', modelGrantExpiresAt},
            'enterResumedCall');
        });
      },
      // Both paths repair Store-committed / marker-missing crashes from exact
      // historical receipts. Neither checks current permission or allows a send.
      observeResumedCall: reference => observeCall(reference, 'deferred', 'observeResumedCall'),
      observeImmediateModelCall: reference => observeCall(reference, 'immediate', 'observeImmediateModelCall'),
      // This is the controller's first cancellation commit, before its request
      // journal write. No Run row is required; registration and every later
      // entry consult this same SQLite transaction domain. The controller must
      // acknowledge cancellation only after both journals are durably updated.
      modelCancellationFenced(runId, runDefinitionCid) {
        alive();
        if (!text(runId) || !cid(runDefinitionCid)) fail('InvalidModelRunIdentity');
        return transaction.run(() => {
          const row = q.cancelled.get(runId);
          if (row === undefined) return false;
          const owner = admittedOwner(row.original_run_wire);
          if (!same(JSON.parse(row.owner_json), owner)) fail('ModelRunIdentityMismatch');
          return owner.runId === runId && owner.runDefinitionCid === runDefinitionCid;
        });
      },
      fenceRunCancellation({originalRunWire}) {
        alive();
        const owner = admittedOwner(originalRunWire);
        return transaction.run(() => {
          const existing = q.cancelled.get(owner.runId);
          if (existing !== undefined) {
            if (!same(JSON.parse(existing.owner_json), owner) ||
                existing.original_run_wire !== originalRunWire) fail('ModelRunIdentityMismatch');
            return freeze({...owner, outcome: 'already_requested'});
          }
          for (const row of database.prepare('SELECT inventory_json FROM resume_model_scopes WHERE run_id = ?').all(owner.runId)) {
            if (!same(select(JSON.parse(row.inventory_json), ownerKeys), owner)) fail('ModelRunIdentityMismatch');
          }
          q.insertCancel.run(owner.runId, JSON.stringify(owner), originalRunWire, iso(now()));
          fault('fenceRunCancellation');
          return freeze({...owner, outcome: 'accepted'});
        });
      },
    },
  });
}
