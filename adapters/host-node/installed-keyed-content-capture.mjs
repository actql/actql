// Physical composition under the dispatch owner's existing Source custody.
// The common Run/Source/candidate and Store owners decide identity, admission,
// byte retention and resource settlement; there is no capture journal here.
import {runtimeField, runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {contentCid} from './local-account-config.mjs';
import {retainCapturedContent} from './captured-content-holding.mjs';
import {issueStoredCapturedContent, consumeStoredContentOriginal,
  closeStoredContentReaders} from './generated-content-holding.mjs';

export function installRunKeyedContentCapture({moon, publications, control,
  preparedProgram, plan, acquisition, ledger, maxBytes, maxWork = 1000000, store, namespaceId,
  authorityScopeCid, storeAuthorityCid, principalId, ownerPrincipal, now,
  authorize, retainExecution, signal, inputAvailable = () => true, sourceBinding}) {
  publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
  publications.checkClientCompiledRunDefinition(plan.compiled, plan.runDefinition);
  if (principalId !== ownerPrincipal || store.storeAuthorityCid !== storeAuthorityCid ||
      typeof retainExecution !== 'function' || typeof inputAvailable !== 'function' ||
      moon.clientProgramKeyedAcquisitionMatchesProgram(acquisition, preparedProgram) !== true) {
    throw new TypeError('InvalidInstalledKeyedContentCapture');
  }
  const definition = JSON.parse(plan.runDefinition.wire);
  const facts = moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition);
  if (!runtimeIsOk(facts) || runtimeField(facts, 0).length !== 6) {
    throw new TypeError('InstalledKeyedContentSourceUnavailable');
  }
  const source = runtimeField(facts, 0);
  // No Source cardinality is needed to create an empty retained inventory.
  // Each actual addition grows the SAME workspace before constructing it.
  let inventoryCount = 0, inventoryGrowing = false;
  const limits = Object.freeze({maxBytes, maxNodes: 256, maxDepth: 32, maxTextUnits: maxBytes});
  const live = () => !cleaned && cleanupFlight === undefined && signal?.aborted !== true &&
    inputAvailable() === true &&
    store.status().closed === false &&
    Date.parse(now()) < Date.parse(definition.valid_until) && authorize(principalId) === true;
  let reservation, current, last, flight, cleanupFlight, failureCleanup, cleaned = false;
  let inventoryReady = true, inventoryFlight;
  const inventory = new Map();
  const contentReaders = new Set();
  const ensureInventoryCapacity = count => {
    if (!Number.isSafeInteger(count) || count < 0 || count > 2147483647 || inventoryGrowing) {
      throw new TypeError('InvalidInstalledContentInventoryCapacity');
    }
    if (count <= inventoryCount) return;
    if (!live() || reservation === undefined) throw new Error('InstalledContentAuthorityUnavailable');
    const original = reservation;
    inventoryGrowing = true;
    try {
      control.growWorkspace(ledger, original, maxBytes, count);
      // A successful debit remains owned even if its current callback began
      // cleanup. Never expose a new inventory entry after that state change.
      inventoryCount = count;
      if (reservation !== original || !live()) throw new Error('InstalledContentAuthorityUnavailable');
    } finally { inventoryGrowing = false; }
  };
  const checkInventoryRoom = wire => {
    if (!inventory.has(wire) && inventory.size >= inventoryCount) {
      throw new TypeError('InstalledContentInventoryLimit');
    }
  };
  const remember = entry => {
    const prior = inventory.get(entry.wire);
    if (prior !== undefined && prior.captureAuthorityCid !== entry.captureAuthorityCid) {
      throw new TypeError('InstalledContentInventoryChanged');
    }
    checkInventoryRoom(entry.wire);
    inventory.set(entry.wire, entry);
    last = entry;
  };
  const releaseCurrent = async () => {
    if (current?.holding !== undefined && current?.prepared?.status().pending === true) {
      // A failed holding ACK may leave its exact record installed. Confirm it
      // through the same Store before releasing bytes or the original frame;
      // cleanup does not re-capture, issue authority, or create an absent holding.
      const observed = await store.inspectPhysicalHolding(current.holding.holding_cid);
      if (observed !== undefined) await store.commitPhysicalHolding(current.holding, []);
    }
    if (current?.prepared?.status().pending === true) await current.prepared.release();
    if (current?.prepared?.status().pending === true) return false;
    if (current?.writer !== undefined) {
      await current.writer.cancel();
      const status = current.writer.status();
      if (status.reservationHeld || status.custodyPending || status.cleanupPending) return false;
    }
    current = undefined;
    return true;
  };
  const cleanup = () => {
    if (cleaned) return Promise.resolve(true);
    if (cleanupFlight !== undefined) return cleanupFlight;
    let operation;
    operation = (async () => {
      if (!await closeStoredContentReaders(contentReaders)) return false;
      if (inventoryFlight !== undefined) await inventoryFlight.catch(() => {});
      if (flight !== undefined) await flight.catch(() => {});
      if (failureCleanup !== undefined) {
        if ((await failureCleanup.retry()).pending) return false;
        failureCleanup = undefined;
      }
      if (!await releaseCurrent()) return false;
      // Committed Content has its own original declared lifetime and Store
      // quota. Temporary Source close is not permission to retire those bytes.
      last = undefined;
      inventory.clear();
      if (reservation !== undefined) control.releaseWorkspace(ledger, reservation);
      reservation = undefined;
      cleaned = true;
      return true;
    })().finally(() => { if (cleanupFlight === operation) cleanupFlight = undefined; });
    cleanupFlight = operation;
    return operation;
  };
  retainExecution(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !cleaned}));
  // Retain the cleanup composition before reserving or allocating any child.
  reservation = control.reserveWorkspace(ledger, maxBytes, inventoryCount);
  if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
  const referenceIssuer = control.reissuer((media, wire) => {
    const original = inventory.get(wire);
    return inventoryReady && original !== undefined && live() &&
      (media === undefined || media === original.mediaType) ? original.value : undefined;
  });
  const selectionCurrent = () => inventoryReady && !inventoryGrowing && !cleaned && cleanupFlight === undefined &&
    flight === undefined && inventoryFlight === undefined;
  // Select an already issued original, not a reference reconstructed from wire
  // or a caller-provided matching predicate. Nonmatching references short-circuit
  // in Common before its bounded current/field checks. The existing inventory
  // count bounds this scan without allocating a second reference index.
  const selectedForContent = binding => {
    if (binding === undefined || !selectionCurrent() || !live() ||
        !selectionCurrent() ||
        typeof moon.clientProgramEffectCommandContentMatchesIssued !== 'function') return undefined;
    let remaining = inventoryCount;
    for (const original of inventory.values()) {
      if (remaining-- <= 0) return undefined;
      const matched = moon.clientProgramEffectCommandContentMatchesIssued(binding, original.value);
      // Common invokes Host currentness callbacks. They may begin cleanup or
      // replace this inventory; their prior true return is not a handoff fence.
      if (!selectionCurrent() || !live() || !selectionCurrent()) return undefined;
      if (matched === true && inventory.get(original.wire) === original) return original;
    }
    return undefined;
  };
  const issuedForContent = binding => selectedForContent(binding)?.value;
  // The same Source supplies this exact stored binding only after the typed
  // original match. Exposed facts contain no Store/path/key, byte buffer or
  // allocation. An escaped/copy record cannot replace the live entry check.
  const storageForContent = binding => selectedForContent(binding)?.storedOriginal;
  const storageCurrentForContent = (stored, binding) => stored !== undefined &&
    selectedForContent(binding)?.storedOriginal === stored;
  const bindingFor = captureAuthorityCid => ({content_store_id: namespaceId,
    content_store_cid: storeAuthorityCid, workspace_scope_cid: authorityScopeCid,
    storage_scope: 'workspace', retention_class: 'local-content',
    expires_at: definition.valid_until,
    availability_evidence_cid: contentCid({version: 'actql-installed-local-policy/0.1',
      name: 'content-availability', storeAuthorityCid,
      runDefinitionCid: plan.runDefinition.identity, expiresAt: definition.valid_until}),
    effective_data_policy_cid: source[3], data_classification: source[4],
    issuer_contract_cid: contentCid({version: 'actql-installed-local-policy/0.1',
      name: 'content-issuer', storeAuthorityCid, authorityScopeCid}),
    capture_authority_cid: captureAuthorityCid});
  const capture = options => {
    if (!inventoryReady || inventoryGrowing || cleaned || cleanupFlight !== undefined || flight !== undefined || inventoryFlight !== undefined ||
        options.keyedAcquisition !== acquisition || typeof options.verifyRead !== 'function') {
      throw new TypeError('InstalledKeyedContentCaptureMismatch');
    }
    let operation;
    operation = (async () => {
      signal?.throwIfAborted();
      options.signal?.throwIfAborted();
      await options.verifyRead();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      if (!await releaseCurrent()) throw new Error('CapturedContentCleanupPending');
      last = undefined;
      ensureInventoryCapacity(inventory.size + 1);
      const binding = bindingFor(options.readSubjectCid);
      const candidate = control.candidateForRun(plan.compiled, plan.runDefinition,
        acquisition, options.request, binding,
        {mediaType: options.mediaType, contentCid: options.contentCid,
          sizeBytes: options.bytes?.byteLength}, limits);
      const description = control.inspect(candidate);
      checkInventoryRoom(description.wire);
      current = {};
      let storedOriginal;
      const retained = await retainCapturedContent({store, control, candidate,
        bytes: options.bytes, holdingCid: control.holdingCid(candidate),
        workspaceScopeCid: authorityScopeCid, effectiveDataPolicyCid: source[3],
        available: live, authorize: live, limits, signal: options.signal,
        retainCustody: handles => { Object.assign(current, handles); },
        retainOriginal: original => {
          storedOriginal = original;
          current.storedOriginal = original;
        }});
      await options.verifyRead();
      signal?.throwIfAborted();
      options.signal?.throwIfAborted();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      if (!await releaseCurrent()) throw new Error('CapturedContentCleanupPending');
      remember(Object.freeze({candidate, wire: retained.wire, mediaType: description.mediaType,
        value: retained.value, storedOriginal, captureAuthorityCid: options.readSubjectCid}));
      return JSON.parse(retained.wire);
    })().catch(error => {
      if (error?.cleanupPending === true && error.cleanupHandle !== undefined) {
        failureCleanup = error.cleanupHandle;
      }
      throw error;
    }).finally(() => { if (flight === operation) flight = undefined; });
    flight = operation;
    return operation;
  };
  // The caller supplies this entry only from authenticated original inventory.
  // This operation borrows the same frame/reservation and Store: it cannot send
  // a provider request, synthesize completion, renew expiry or retire bytes.
  const recover = (options, ownedInventory = false) => {
    if (inventoryGrowing || cleaned || cleanupFlight !== undefined || flight !== undefined ||
        inventoryFlight !== undefined && !ownedInventory ||
        options.keyedAcquisition !== acquisition || typeof options.verifyRead !== 'function' ||
        typeof options.referenceWire !== 'string' || typeof options.captureAuthorityCid !== 'string') {
      throw new TypeError('InstalledKeyedContentRecoveryMismatch');
    }
    let operation;
    operation = (async () => {
      signal?.throwIfAborted();
      await options.verifyRead();
      signal?.throwIfAborted();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      if (!await releaseCurrent()) throw new Error('CapturedContentCleanupPending');
      last = undefined;
      ensureInventoryCapacity(inventory.size + (inventory.has(options.referenceWire) ? 0 : 1));
      const candidate = control.recoveryCandidateForRun(plan.compiled, plan.runDefinition,
        acquisition, options.referenceWire, bindingFor(options.captureAuthorityCid), limits);
      const description = control.inspect(candidate);
      checkInventoryRoom(description.wire);
      let storedOriginal;
      const value = await issueStoredCapturedContent({store, control, candidate,
        holdingCid: control.holdingCid(candidate), workspaceScopeCid: authorityScopeCid,
        effectiveDataPolicyCid: source[3], available: live, authorize: live, limits,
        retainOriginal: original => { storedOriginal = original; }});
      await options.verifyRead();
      signal?.throwIfAborted();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      remember(Object.freeze({candidate, wire: description.wire, mediaType: description.mediaType,
        value, storedOriginal, captureAuthorityCid: options.captureAuthorityCid}));
      return JSON.parse(description.wire);
    })().finally(() => { if (flight === operation) flight = undefined; });
    flight = operation;
    return operation;
  };
  const recoverInventory = options => {
    const original = options.inventory;
    const closed = (item, keys) => item !== null && typeof item === 'object' &&
      !Array.isArray(item) && Object.keys(item).sort().join(',') === keys;
    if (inventoryGrowing || cleaned || cleanupFlight !== undefined || flight !== undefined || inventoryFlight !== undefined ||
        options.keyedAcquisition !== acquisition || typeof options.verifyRead !== 'function' ||
        !closed(original, 'entries,runDefinitionCid,version') ||
        original.version !== 'actql-installed-captured-content-inventory/0.1' ||
        original.runDefinitionCid !== plan.runDefinition.identity ||
        !Array.isArray(original.entries) || original.entries.length > 2147483647) {
      throw new TypeError('InstalledKeyedContentInventoryMismatch');
    }
    // The authenticated original inventory supplies its actual entry count;
    // fund its copy and duplicate index before either collection is built.
    const entriesOriginal = original.entries, count = entriesOriginal.length;
    ensureInventoryCapacity(count);
    if (original.entries !== entriesOriginal || entriesOriginal.length !== count ||
        original.version !== 'actql-installed-captured-content-inventory/0.1' ||
        original.runDefinitionCid !== plan.runDefinition.identity) {
      throw new TypeError('InstalledKeyedContentInventoryMismatch');
    }
    const seen = new Set();
    for (const entry of original.entries) {
      if (!closed(entry, 'captureAuthorityCid,referenceWire') ||
          typeof entry.referenceWire !== 'string' || Buffer.byteLength(entry.referenceWire) > maxBytes ||
          typeof entry.captureAuthorityCid !== 'string' || seen.has(entry.referenceWire)) {
        throw new TypeError('InstalledKeyedContentInventoryMismatch');
      }
      seen.add(entry.referenceWire);
    }
    const entries = original.entries.map(entry => Object.freeze({...entry}));
    const verifyRead = options.verifyRead;
    // One receiving frame confirms the full original inventory before its
    // issuer becomes usable. A failed batch keeps custody but exposes no
    // partial restored authority; an explicit retry confirms saved bytes only.
    inventoryReady = false;
    inventory.clear();
    last = undefined;
    let operation;
    operation = (async () => {
      await verifyRead();
      signal?.throwIfAborted();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      for (const entry of entries) {
        await recover({...entry, keyedAcquisition: acquisition, verifyRead}, true);
      }
      await verifyRead();
      signal?.throwIfAborted();
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      inventoryReady = true;
    })().finally(() => { if (inventoryFlight === operation) inventoryFlight = undefined; });
    inventoryFlight = operation;
    return operation;
  };
  return Object.freeze({capture, recover: options => recover(options), recoverInventory, referenceIssuer,
    issuedForContent, storageForContent, storageCurrentForContent,
    consumeContent(binding, accept) {
      const original = storageForContent(binding);
      if (original === undefined) throw new Error('OriginalEffectContentUnavailable');
      return consumeStoredContentOriginal({store, original, readers: contentReaders, accept,
        assertCurrent() {
          if (!storageCurrentForContent(original, binding)) throw new Error('OriginalEffectContentUnavailable');
        }});
    },
    sourceBinding,
    recoveryInventory: () => !inventoryReady || !live() || cleaned || flight !== undefined ||
        inventoryFlight !== undefined ? undefined : Object.freeze({
      version: 'actql-installed-captured-content-inventory/0.1',
      runDefinitionCid: plan.runDefinition.identity,
      entries: Object.freeze([...inventory.values()].map(entry => Object.freeze({
        referenceWire: entry.wire, captureAuthorityCid: entry.captureAuthorityCid}))),
    }),
    recovery: () => !inventoryReady || last === undefined || !live() ? undefined : Object.freeze({
      referenceWire: last.wire, captureAuthorityCid: last.captureAuthorityCid}),
  });
}
