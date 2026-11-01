// Physical stepping and custody for the existing MoonBit inference owner.
// Run admission, model policy and private Store confirmation precede opening;
// this adapter does not authorize dispatch or issue a public Run outcome.
import {runtimeFailure, runtimeField, runtimeTriple} from '../host-common/compiler-binding.generated.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {types as utilTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {claimInferIoNotification} from './infer-io-notification.mjs';
import {selectedInferOriginalMetadataLimits, selectedInferOriginalStoreBootstrapLimits,
  selectedInferOriginalPublicationCapacity, selectedInferOriginalCurrentStateCodec} from './infer-original-installation.mjs';
import {originalModelRawTransportPersistenceMatches, bindOriginalModelRawTransportPersistence}
  from './infer-raw-capture.mjs';

const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});
const activeOperations = new WeakMap();
const originalOperations = new WeakSet();
const cleanedOriginalReads = new WeakSet();
const isPromise = utilTypes.isPromise;
const observePromise = Promise.prototype.then;

// A parent may retire this exact descriptor alias after the consumer's actual
// Core cleanup. This observation issues no ACK and cannot mark another read,
// release a Scope, or turn a stopped/unknown operation into completed cleanup.
export function inferOriginalReadCleanupComplete(read) {
  return cleanedOriginalReads.has(read);
}

// The same original parent's read retirement for Pure and Effect consumers.
// A completed consuming execution does not settle its owning reservation.
export function retireNodeInferOriginalRead({control, compiled, runDefinition, graph, scope, read}) {
  if (read === undefined) return;
  if (!inferOriginalReadCleanupComplete(read)) {
    control.stopCheckedClientInferOriginalReadPreparation(compiled, runDefinition, graph, scope, read);
  }
  control.settleCheckedClientInferOriginalReadPreparation(compiled, runDefinition, graph, read, true);
}
// This is nominal membership in the existing operation, not a resource Owner.
// Escaped handles weakly borrow its retained record and cannot keep the original
// Model/Scope/Ledger graph alive after actual operation cleanup.
const originalMetadataSources = new WeakMap();
const metadataUnavailable = () => { throw Object.assign(new Error('InferOriginalMetadataAcquisitionUnavailable'),
  {code: 'InferOriginalMetadataAcquisitionUnavailable'}); };

// Keep an escaped per-preflight setter from retaining the installing operation
// after this synchronous constructor. Its mutable port is consumed once and
// cleared even when the original physical factory refuses or throws.
function prepareWithOriginalRawSetter(prepare, request, notification, retain) {
  const set = callback => {
    if (retain === undefined) throw new TypeError('InferRawCaptureBinderUnavailable');
    retain(callback);
    retain = undefined;
  };
  try { return prepare(request, notification, set); }
  finally { retain = undefined; }
}

export function selectOriginalInferMetadataAcquisition(handle, ownerId, requestCid) {
  const original = originalMetadataSources.get(handle)?.deref();
  if (original === undefined) metadataUnavailable();
  original.current(ownerId, requestCid);
  return original.selection;
}

// Reuse the SAME nominal handle and current/covers closure, not another issuer
// or a capacity inferred from physical clamps. Missing separate role refuses.
export function selectOriginalInferStoreBootstrapAcquisition(handle, ownerId, requestCid) {
  const original = originalMetadataSources.get(handle)?.deref();
  if (original === undefined) metadataUnavailable();
  return original.current(ownerId, requestCid, 'store-bootstrap');
}

// Same original installation's existing Writer/decoder bound. Metadata wire
// limits are a different role and cannot price or bound this resource body.
export function selectOriginalInferResourceCodecAcquisition(handle, ownerId, requestCid) {
  const original = originalMetadataSources.get(handle)?.deref();
  if (original === undefined) metadataUnavailable();
  return original.current(ownerId, requestCid, 'resource-state-codec');
}

// Validate the Node-to-Int boundary before entering the existing codec. These
// bounds are not physical funding or permission to acquire additional data.
const codecInt = (value, positive = false) => Number.isSafeInteger(value) &&
  value >= (positive ? 1 : 0) && value <= 2147483647;
const codecLimits = (value, keys) => value !== null && typeof value === 'object' &&
  Object.keys(value).sort().join(',') === keys && Object.values(value).every(item => codecInt(item));

// Publication metadata is issued by the same bounded common owner only after
// every original Model component has completed. This does not advance calls.
export function startCompleteInferObservation({moon, operations, ledger, maxSlots, maxWireBytes, maxWork,
  content}) {
  const active = operations.map(operation => {
    const value = activeOperations.get(operation);
    if (value === undefined) throw new TypeError('ForeignInferOperation');
    return value;
  });
  if (operations.some(operation => originalOperations.has(operation))) {
    if (operations.length !== 1 || ledger !== undefined || content !== undefined) {
      throw new TypeError('InferOriginalPublicationCapacityUnavailable');
    }
    // The actual operation retains its original opaque publication borrow.
    // A Source Ledger or a matching caller object cannot select that issuer.
    return operations[0].startObservation({maxSlots, maxWireBytes, maxWork});
  }
  if (content !== undefined) {
    return content.control.startCheckedClientContentInferObservation(content.compiled,
      active, content.generations, ledger, {maxSlots, maxWireBytes, maxWork});
  }
  return checked(moon.clientProgramStartCompleteInferObservationIssuance(active,
    ledger, maxSlots, maxWireBytes, maxWork));
}

// Called by the installed Run's dispatch callback. The caller transfers this
// object to client-dispatch-owner before calling run, hence before any advance.
// Exactly one physical provider or already Store-confirmed saved read is used.
export function openNodeInferOperation({moon, preparedProgram, step, graph,
  registry, values, fragment, ordered, provider, savedCapture, savedSlots, quantityCapacity,
  physicalPreflight, egressAdmission, computeSuffix, acquiredInput, composedInput, keyedInput,
  signal, quantum = 256, observeProgress, durableCalls = false, restoredInput, retainOperation,
  ioNotification, originalPreparation, rawCaptureBinder, serializedInput, restoredReferenceIssuer,
  assertRuntimeCurrent, bindComputeSuffix}) {
  if (rawCaptureBinder !== undefined && typeof rawCaptureBinder !== 'function') {
    throw new TypeError('InvalidInferRawCaptureBinder');
  }
  if (assertRuntimeCurrent !== undefined &&
      (originalPreparation === undefined || typeof assertRuntimeCurrent !== 'function' ||
        typeof moon.clientProgramBindInferPhysicalPreflightCurrent !== 'function')) {
    throw new TypeError('InferTrustedRuntimeScopeUnavailable');
  }
  if (bindComputeSuffix !== undefined && (typeof bindComputeSuffix !== 'function' ||
      originalPreparation === undefined || computeSuffix !== undefined)) {
    throw new TypeError('InvalidInferOriginalSuffixBinding');
  }
  let rawCaptureBound = false;
  let preparedRawCaptureBinders;
  // The original installing Run has already reserved this entire simultaneous
  // envelope, including this adapter's controls. Do not derive it from counts,
  // aggregate headroom or the later Model seal's distinct requirements.
  let originalConsumer;
  let originalRead;
  let originalScope = originalPreparation?.scope;
  let metadataInstallation = originalPreparation?.metadataInstallation;
  let metadataNodeInstallation = originalPreparation?.nodeInstallation;
  let metadataControl = originalPreparation?.control;
  let metadataDefinition = originalPreparation?.runDefinition;
  let originalMetadata;
  let originalStoreBootstrap;
  let originalPublicationCapacity;
  let originalPublicationSelection;
  let originalPublicationReceiver;
  if (originalPreparation !== undefined) {
    if (provider === undefined || acquiredInput !== undefined || keyedInput !== undefined ||
        restoredInput !== undefined || savedCapture !== undefined || savedSlots !== undefined ||
        originalPreparation === null || typeof originalPreparation !== 'object' ||
        typeof originalPreparation.readRetainedBytes !== 'bigint' ||
        originalPreparation.readRetainedBytes <= 0n ||
        typeof originalPreparation.readExecutionBytes !== 'bigint' ||
        originalPreparation.readExecutionBytes <= 0n ||
        typeof originalPreparation.modelRetainedBytes !== 'bigint' ||
        originalPreparation.modelRetainedBytes <= 0n ||
        typeof originalPreparation.modelExecutionBytes !== 'bigint' ||
        originalPreparation.modelExecutionBytes < 0n) {
      throw new TypeError('InvalidInferOriginalPreparation');
    }
    originalRead = originalPreparation.read;
    const publication = Object.getOwnPropertyDescriptor(originalPreparation, 'publicationCapacity');
    if (publication !== undefined) {
      if (!Object.hasOwn(publication, 'value') || typeof publication.value !== 'function') {
        throw Object.assign(new Error('InferOriginalPublicationCapacityUnavailable'),
          {code: 'InferOriginalPublicationCapacityUnavailable'});
      }
      // Keep the same installing callback/receiver across Model execution.
      // Its current same-Run selection is DATA, not a reservation or grant.
      originalPublicationSelection = publication.value;
      originalPublicationReceiver = originalPreparation;
    }
    // The original read owner retains the issued ticket if a later constructor
    // fails. No JS ownership map, claim reset or unowned-start fallback exists.
    if (composedInput !== undefined &&
        typeof originalPreparation.control?.startCheckedClientOriginalComposedInferExecution !== 'function') {
      throw new TypeError('InferOriginalComposedControlUnavailable');
    }
    if (Object.hasOwn(originalPreparation, 'nodeInstallation')) {
      const selected = originalPreparation.nodeInstallation;
      if (selected === null || typeof selected !== 'object' ||
          Object.keys(selected).sort().join(',') !==
            'installation,layout,layoutArtifactCid,probability,runtimeArtifactCid' ||
          typeof originalPreparation.control?.claimCheckedClientInferNodePreparationLayout !== 'function' ||
          composedInput === undefined &&
            typeof originalPreparation.control?.startCheckedClientInferOriginalPreparation !== 'function') {
        throw new TypeError('InvalidInferOriginalPreparationLayout');
      }
      // The same installed layout claim supplies the one original consumer
      // for both single-stage and composed input. A rejected claim never uses
      // the private envelope or an unowned start as a replacement.
      originalConsumer = originalPreparation.control.claimCheckedClientInferNodePreparationLayout(
        originalPreparation.compiled, originalPreparation.runDefinition, graph,
        originalRead, selected);
    } else if (composedInput !== undefined) {
      const control = originalPreparation.control;
      if (typeof control?.claimCheckedClientInferOriginalComposedPreparation !== 'function') {
        throw new TypeError('InferOriginalComposedControlUnavailable');
      }
      originalConsumer = control.claimCheckedClientInferOriginalComposedPreparation(
        originalPreparation.compiled, originalPreparation.runDefinition, graph,
        originalRead, originalPreparation.readRetainedBytes,
        originalPreparation.readExecutionBytes);
    } else {
      // Explicit existing private envelope caller; no production supplier or
      // physical adequacy is implied by this older diagnostic interface.
      originalConsumer = checked(moon.clientProgramClaimInferOriginalPreparation(originalRead,
        originalPreparation.compiled, originalPreparation.runDefinition, graph,
        originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes));
    }
  }
  if (retainOperation !== undefined && typeof retainOperation !== 'function') {
    throw new TypeError('InvalidInferOperationCustody');
  }
  if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647 ||
      [provider, savedCapture, savedSlots].filter(value => value !== undefined)
        .length !== 1) {
    throw new TypeError('InvalidInstalledInferOperation');
  }
  if (physicalPreflight !== undefined &&
      (typeof physicalPreflight !== 'function' || provider === undefined ||
        quantityCapacity === undefined)) {
    throw new TypeError('InvalidInstalledInferPhysicalPreflight');
  }
  if (egressAdmission !== undefined && provider === undefined) {
    throw new TypeError('InvalidInstalledInferEgress');
  }
  if (quantityCapacity !== undefined && (provider === undefined ||
      quantityCapacity === null ||
      typeof quantityCapacity !== 'object' ||
      Object.keys(quantityCapacity).sort().join(',') !== 'limits,perAttempt' ||
      ['limits', 'perAttempt'].some(scope => {
        const value = quantityCapacity[scope];
        return value === null || typeof value !== 'object' ||
          Object.keys(value).sort().join(',') !==
            'costUnits,durationMs,tokens' ||
          Object.values(value).some(amount => typeof amount !== 'bigint' ||
            amount < 0n || amount > BigInt(Number.MAX_SAFE_INTEGER));
      }))) {
    throw new TypeError('InvalidInstalledInferQuantityCapacity');
  }
  signal?.throwIfAborted();
  if (acquiredInput !== undefined && savedCapture !== undefined) {
    throw new TypeError('AcquiredInferReplayNotConnected');
  }
  if (composedInput !== undefined && (provider === undefined ||
      acquiredInput !== undefined || savedSlots !== undefined ||
      savedCapture !== undefined)) {
    throw new TypeError('InvalidComposedInferOperation');
  }
  if (keyedInput !== undefined && (provider === undefined || acquiredInput !== undefined ||
      composedInput !== undefined || savedSlots !== undefined || savedCapture !== undefined ||
      serializedInput !== undefined || keyedInput.occurrence === undefined ||
      keyedInput.prefix === undefined || keyedInput.ledger === undefined ||
      restoredInput === undefined && keyedInput.sources === undefined ||
      typeof moon.clientProgramAdvanceInferRoot !== 'function')) {
    throw new TypeError('InvalidKeyedInferOperation');
  }
  if (restoredInput !== undefined && (provider === undefined || acquiredInput !== undefined ||
      savedCapture !== undefined || savedSlots !== undefined)) {
    throw new TypeError('InvalidRestoredInferInput');
  }
  // This is a Host-owned issuer confirmed against the original Store holding,
  // not authority reconstructed from the saved reference envelope itself.
  if (restoredReferenceIssuer !== undefined &&
      (restoredInput === undefined || serializedInput !== undefined)) {
    throw new TypeError('InvalidRestoredInferReferenceIssuer');
  }
  if (serializedInput !== undefined && (provider === undefined ||
      acquiredInput !== undefined || composedInput !== undefined ||
      savedCapture !== undefined || savedSlots !== undefined ||
      serializedInput.inputs !== undefined && !Array.isArray(serializedInput.inputs) ||
      typeof serializedInput?.control?.[serializedInput.inputs !== undefined
        ? restoredInput === undefined ? 'startCheckedClientGeneratedInferInputs'
          : 'startCheckedClientRestoredGeneratedInferInputs' : restoredInput === undefined
        ? 'startCheckedClientGeneratedInferExecution'
        : 'startCheckedClientRestoredGeneratedInferExecution'] !== 'function')) {
    throw new TypeError('InvalidSerializedInferInput');
  }
  if (ioNotification !== undefined && (provider === undefined || composedInput !== undefined)) {
    throw new TypeError('InvalidInferIoNotificationProfile');
  }
  let io = ioNotification === undefined ? undefined : claimInferIoNotification(ioNotification);
  let active;
  try { active = serializedInput !== undefined
    ? serializedInput.inputs !== undefined
      ? restoredInput !== undefined
        ? serializedInput.control.startCheckedClientRestoredGeneratedInferInputs(
          serializedInput.compiled, serializedInput.definition, serializedInput.generation,
          graph, serializedInput.inputs, provider, restoredInput.snapshot,
          () => restoredInput.token.available)
        : originalPreparation === undefined
          ? serializedInput.control.startCheckedClientGeneratedInferInputs(
            serializedInput.compiled, serializedInput.generation, graph, serializedInput.inputs, provider)
          : serializedInput.control.startCheckedClientOriginalGeneratedInferInputs(
            serializedInput.compiled, serializedInput.generation, graph, serializedInput.inputs, provider,
            originalPreparation.runDefinition, originalConsumer,
            originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes,
            originalPreparation.modelRetainedBytes, originalPreparation.modelExecutionBytes)
      : restoredInput !== undefined
      ? serializedInput.control.startCheckedClientRestoredGeneratedInferExecution(
        serializedInput.compiled, serializedInput.definition, serializedInput.generation,
        preparedProgram, graph, provider, {registry, values, fragment, ordered},
        restoredInput.snapshot, () => restoredInput.token.available)
      : originalPreparation === undefined
        ? serializedInput.control.startCheckedClientGeneratedInferExecution(
          serializedInput.compiled, serializedInput.generation, preparedProgram, graph, provider)
        : serializedInput.control.startCheckedClientOriginalGeneratedInferExecution(
          serializedInput.compiled, serializedInput.generation, preparedProgram, graph, provider,
          originalPreparation.runDefinition, originalConsumer,
          originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes,
          originalPreparation.modelRetainedBytes, originalPreparation.modelExecutionBytes)

    : originalPreparation !== undefined && composedInput !== undefined
    ? originalPreparation.control.startCheckedClientOriginalComposedInferExecution(
      originalPreparation.compiled, originalPreparation.runDefinition,
      composedInput.occurrence, graph, composedInput.prefix, composedInput.inputs,
      provider, originalConsumer, originalPreparation.readRetainedBytes,
      originalPreparation.readExecutionBytes, originalPreparation.modelRetainedBytes,
      originalPreparation.modelExecutionBytes, composedInput.sources)
    : originalPreparation !== undefined && Object.hasOwn(originalPreparation, 'nodeInstallation')
    ? originalPreparation.control.startCheckedClientInferOriginalPreparation(
      originalPreparation.compiled, originalPreparation.runDefinition,
      preparedProgram, step, graph, registry, values, provider, originalConsumer,
      originalPreparation.readRetainedBytes, originalPreparation.readExecutionBytes,
      originalPreparation.modelRetainedBytes, originalPreparation.modelExecutionBytes, fragment, ordered)
    : checked(originalPreparation !== undefined
    ? moon.clientProgramStartOriginalInferExecution(preparedProgram, step, graph,
      registry, values, provider, originalPreparation.compiled, originalPreparation.runDefinition,
      originalConsumer, originalPreparation.readRetainedBytes,
      originalPreparation.readExecutionBytes, originalPreparation.modelRetainedBytes,
      originalPreparation.modelExecutionBytes, fragment, ordered)
    : restoredInput !== undefined && (composedInput !== undefined || keyedInput !== undefined)
    ? moon.clientProgramStartRestoredComposedInferInput((composedInput ?? keyedInput).occurrence, graph,
      (composedInput ?? keyedInput).prefix, provider, restoredInput.snapshot.binding,
      restoredInput.snapshot.descriptorWire, restoredInput.snapshot.rows,
      () => restoredInput.token.available, restoredInput.savedScope, restoredReferenceIssuer,
      keyedInput?.ledger, computeSuffix)
    : restoredInput !== undefined
    ? moon.clientProgramStartRestoredInferInput(preparedProgram, step, graph, registry,
      values, provider, restoredInput.snapshot.binding, restoredInput.snapshot.descriptorWire,
      restoredInput.snapshot.rows, () => restoredInput.token.available, restoredInput.savedScope,
      fragment, ordered, restoredReferenceIssuer)
    : keyedInput !== undefined
    ? moon.clientProgramStartKeyedInferExecution(keyedInput.occurrence, graph,
      keyedInput.prefix, provider, keyedInput.sources, computeSuffix, keyedInput.ledger)
    : composedInput !== undefined
    ? moon.clientProgramStartComposedInferExecution(composedInput.occurrence,
      graph, composedInput.prefix, composedInput.inputs, provider,
      composedInput.sources)
    : savedSlots !== undefined
    ? acquiredInput === undefined
      ? moon.clientProgramStartRestoredInferSlotReplay(preparedProgram, step,
        graph, registry, values, savedSlots, fragment, ordered)
      : moon.clientProgramStartAcquiredInferSlotReplay(preparedProgram, step,
        graph, registry, values, savedSlots, acquiredInput, fragment, ordered)
    : savedCapture === undefined
      ? acquiredInput === undefined
        ? moon.clientProgramStartScopedInferExecution(preparedProgram, step,
          graph, registry, values, provider, fragment, ordered)
        : moon.clientProgramStartAcquiredInferExecution(preparedProgram, step,
          graph, registry, values, provider, acquiredInput, fragment, ordered)
      : moon.clientProgramStartRestoredInferReplay(preparedProgram, step,
        graph, registry, values, savedCapture, fragment, ordered)); }
  catch (error) { io?.close(); io = undefined; throw error; }
  let stopNotified = false;
  const requestStop = () => {
    const result = moon.clientProgramCancelInferExecution(active);
    // Deliver a new stop request once. Repeated sticky cancellation cannot
    // turn a still-pending physical save into a zero-work polling loop.
    if (!stopNotified) { stopNotified = true; io?.notify(); }
    return result;
  };
  const runtimeCurrent = () => {
    if (assertRuntimeCurrent === undefined) return true;
    try { assertRuntimeCurrent(); return true; }
    catch {
      // Actual original currentness loss, NEVER Host closing alone. Only the
      // existing Core stop/failure/cleanup paths drive the retained children.
      requestStop();
      return false;
    }
  };
  let runtimeObservedCallSet;
  let runtimeDiagnostic;
  function observeOriginalRuntime(value) {
    runtimeCurrent();
    try {
      if (runtimeDiagnostic !== undefined) {
        const facts = moon.clientProgramInferPhysicalObservationFacts(value);
        runtimeDiagnostic({slot: runtimeField(facts, 0), attemptCid: runtimeField(facts, 1),
          event: runtimeField(facts, 2), outcome: runtimeField(facts, 3)});
      }
    } catch { /* Optional diagnostics cannot authorize or block cleanup. */ }
    finally { runtimeCurrent(); }
  }
  function bindOriginalRuntimeObservation(preparedCallSet) {
    if (runtimeObservedCallSet !== undefined) {
      return runtimeObservedCallSet === preparedCallSet;
    }
    const installed = moon.clientProgramBindInferModelObservation(active,
      preparedCallSet, observeOriginalRuntime);
    if (installed === true) runtimeObservedCallSet = preparedCallSet;
    return installed === true;
  }
  signal?.addEventListener('abort', requestStop, {once: true});
  let flight;
  let closeFlight;
  let reclaimed = false;
  let closing = false;
  let cleanupSettlement;

  function cleanup() {
    if (reclaimed) return true;
    // This same nominal borrower must retire after its actual publication
    // children/aliases and before parent cleanup. Never drop it on stop alone.
    if (originalPublicationCapacity !== undefined) return false;
    // Cancellation delivery alone never permits releasing the execution.
    if (!moon.clientProgramInferExecutionStopped(active)) return false;
    reclaimed = checked(moon.clientProgramCleanupInferExecution(active));
    if (reclaimed) {
      if (reclaimed === true && originalConsumer !== undefined && originalRead !== null &&
          (typeof originalRead === 'object' || typeof originalRead === 'function')) {
        cleanedOriginalReads.add(originalRead);
      }
      originalRead = undefined;
      signal?.removeEventListener('abort', requestStop);
      originalPreparedCallSet = undefined;
      if (originalMetadata !== undefined) originalMetadataSources.delete(originalMetadata.handle);
      originalMetadata = undefined;
      if (originalStoreBootstrap !== undefined) originalMetadataSources.delete(originalStoreBootstrap.handle);
      originalStoreBootstrap = undefined;
      originalScope = undefined;
      // Escaped metadata methods must not keep the original installation/Run
      // after this same Core Owner acknowledges cleanup. Pending/failed
      // cleanup retains these aliases; independent immutable borrows and
      // external Store/read custody are neither mutated nor settled here.
      metadataInstallation = undefined;
      metadataNodeInstallation = undefined;
      metadataControl = undefined;
      metadataDefinition = undefined;
      originalPublicationSelection = undefined;
      originalPublicationReceiver = undefined;
      rawCaptureBinder = undefined;
      preparedRawCaptureBinders = undefined;
      runtimeObservedCallSet = undefined;
      runtimeDiagnostic = undefined;
      assertRuntimeCurrent = undefined;
      io?.close();
      io = undefined;
    }
    return reclaimed;
  }

  async function drive() {
    for (;;) {
      runtimeCurrent();
      if (closing || signal?.aborted) requestStop();
      // Arm before polling: a completion during the poll must not be lost.
      // Only Core may decide whether the notification has changed its state.
      const ticket = io?.arm();
      let poll, kind;
      try {
        poll = checked((keyedInput === undefined ? moon.clientProgramAdvanceInferExecution
          : moon.clientProgramAdvanceInferRoot)(active, quantum));
        kind = moon.clientProgramInferExecutionPollKind(poll);
        if (kind === 'await_io') {
          if (ticket === undefined) throw new Error('InferIoNotificationUnavailable');
          await ticket.promise;
          continue;
        }
      } finally { ticket?.dispose(); }
      if (kind === 'waiting') {
        const preparedCallSet = moon.clientProgramInferPreparedCallSet(active);
        if (preparedCallSet === undefined) throw new Error('InferPreparedOwnerUnavailable');
        if (assertRuntimeCurrent !== undefined && !bindOriginalRuntimeObservation(preparedCallSet)) {
          requestStop();
          throw new TypeError('InferTrustedRuntimeObservationUnavailable');
        }
        return Object.freeze({status: 'waiting', preparedCallSet});
      }
      if (kind === 'settling') {
        const settlement = moon.clientProgramInferCallSettlement(active);
        if (settlement === undefined) throw new Error('InferSettlementOwnerUnavailable');
        return Object.freeze({status: 'settling', settlement});
      }
      if (kind === 'complete') {
        return moon.clientProgramInferExecutionOutput(poll);
      }
      if (kind === 'failed') {
        // Preserve the existing typed cause without a new public classifier.
        checked(runtimeFailure(moon.clientProgramInferExecutionPollIssue(poll)));
      }
      if (kind === 'stopped') {
        if (signal?.aborted) signal.throwIfAborted();
        throw Object.assign(new Error('InferExecutionStopped'),
          {code: 'InferExecutionStopped'});
      }
      if (kind !== 'continue') throw new Error('InvalidInferExecutionPoll');
      await observeProgress?.();
      // A macrotask delivers timer/I/O cancellation; a resolved Promise does
      // not. MoonBit owns work, progress, phase changes and safe stop checks.
      await yieldEventLoop();
    }
  }

  function run() {
    if (composedInput !== undefined || serializedInput?.inputs !== undefined) {
      return Promise.reject(new Error('InferComponentDrivenByLocal'));
    }
    if (closing || reclaimed) {
      return Promise.reject(new Error('InferOperationClosed'));
    }
    if (flight === undefined) {
      flight = drive().then(result => {
        if (result?.status === 'waiting' || result?.status === 'settling') flight = undefined;
        return result;
      });
      // The supervisor observes this promise even if its Client disconnects.
      // Retaining the rejection here prevents an unhandled detached failure.
      flight.catch(() => {});
    }
    return flight;
  }

  async function stop() {
    closing = true;
    requestStop();
    if (flight !== undefined) await flight.catch(() => {});
    // Finish only bounded observation/custody already owned by an entered
    // attempt. requestStop is sticky, so this cannot dispatch another slot.
    while (!moon.clientProgramInferExecutionStopped(active)) {
      requestStop();
      const ticket = io?.arm();
      let poll, kind;
      try {
        poll = checked(moon.clientProgramAdvanceInferExecution(active, 1));
        kind = moon.clientProgramInferExecutionPollKind(poll);
        if (kind === 'await_io') {
          if (ticket === undefined) throw pending();
          await ticket.promise;
          continue;
        }
      } finally { ticket?.dispose(); }
      if (kind === 'settling') {
        if (typeof cleanupSettlement !== 'function') throw pending();
        const settlement = moon.clientProgramInferCallSettlement(active);
        if (settlement === undefined) throw pending();
        await cleanupSettlement(settlement);
      } else if (kind === 'continue') {
        await yieldEventLoop();
      } else if (!moon.clientProgramInferExecutionStopped(active)) {
        throw pending();
      }
    }
  }

  function close() {
    if (reclaimed) return Promise.resolve();
    if (closeFlight === undefined) {
      closing = true;
      closeFlight = (async () => {
        await stop();
        if (!cleanup()) throw pending();
      })();
      closeFlight.catch(() => {});
    }
    return closeFlight;
  }

  let originalPreparedCallSet;
  // One setter per original Core preflight, not one per whole execution. Core
  // bounds and owns that finite cursor inventory before issuing its CallSet.
  // The same original preparation envelope must cover this array/reference
  // and setter/callback overlap BEFORE preparation, not at later registration.
  // No provider-global map, slot scheduler or additional physical Call is used.
  const retainRawCaptureBinder = callback => {
    if (closing || reclaimed || rawCaptureBound || rawCaptureBinder !== undefined ||
        typeof callback !== 'function') {
      throw new TypeError('InferRawCaptureBinderUnavailable');
    }
    preparedRawCaptureBinders ??= [];
    preparedRawCaptureBinders.push(callback);
  };
  const operation = Object.freeze({run, stop, close, cleanup,
    contentGenerationCount: serializedInput === undefined ? 0 : 1,
    // Publication borrows the same opaque generation used by execution and
    // the joint observation issuer, never a JSON reconstruction of its proof.
    contentGenerations: () => serializedInput === undefined ? undefined
      : Object.freeze([serializedInput.generation]),
    contentRecovery: () => serializedInput?.recovery,
    capturedContentRecovery: () => serializedInput?.capturedRecovery ?? keyedInput?.capturedRecovery,
    capturedContentBinding: () => serializedInput?.capturedBinding ?? keyedInput?.capturedBinding,
    installSettlementCleanup(callback) {
      if (cleanupSettlement !== undefined || typeof callback !== 'function') {
        throw new TypeError('InvalidInferSettlementCleanup');
      }
      cleanupSettlement = callback;
    },
    cleanupPending: () => !reclaimed,
    cleanupProgress: () => moon.clientProgramInferCleanupProgress?.(active),
    physicalStopped: () => moon.clientProgramInferExecutionStopped(active),
    quantityUsage: () => moon.clientProgramInferQuantityUsage(active),
    stoppedAttemptCount: () => moon.clientProgramInferStoppedAttemptCount(active),
    stoppedAttemptSlot: index => moon.clientProgramInferStoppedAttemptSlot(active, index),
    hasUnknownCalls: () => moon.clientProgramInferHasUnknownCalls(active),
    acquireOutput: () => moon.clientProgramAcquireInferOutput(active),
    acquireCapture: () => moon.clientProgramAcquireInferCapture(active),
    acquireOutcomes: () => moon.clientProgramAcquireInferOutcomes(active),
    invocationEvidence: slot => moon.clientProgramInferInvocationEvidence(active,
      slot),
    invocationEvidenceView: (control, slot) => {
      if (reclaimed) return undefined;
      return control.inspectInferInvocationEvidence(moon, active, slot);
    },
    evaluationRequest: slot => {
      if (reclaimed) return undefined;
      const physical = moon.clientProgramInferEvaluationRequest(active, slot);
      if (physical !== undefined) return physical;
      if (restoredInput?.token.available !== true ||
          moon.clientProgramInferInvocationEvidence(active, slot) === undefined) return undefined;
      const prepared = originalPreparedCallSet;
      if (prepared === undefined) return undefined;
      const request = moon.clientProgramInferPreparedRequest(prepared, slot);
      const call = moon.clientProgramInferPreparedCallAt(prepared, slot);
      if (request === undefined || call === undefined) return undefined;
      const callWire = moon.strategyRunEvidenceJson(call);
      const saved = restoredInput.snapshot.providerInputs?.find(item => item.callWire === callWire);
      // This reads authenticated original strings. A current preflight must
      // never rebuild missing historical provider input or context.
      if (saved === undefined || saved.typedInputWire !== moon.clientProgramModelRequestInputFrame(request)) return undefined;
      return runtimeTriple(request, saved.renderedInput, saved.contextManifest);
    },
    preparedPhysicalRequest: (prepared, slot) => moon.clientProgramInferPreparedPhysicalRequest(prepared, slot),
    // The ordinary publication control owns compilation and contract tokens.
    // It passes the original owner to MoonBit, never recompiling this Program.
    bindRun: (control, {compiled, runDefinition}) =>
      control.bindCheckedClientInferRun(compiled, active, runDefinition),
    // The original installing Owner retains read custody. Core verifies the
    // original Run and claims its seal after the actual bounded Identity scan.
    // This private seam does not install a normal physical funding profile.
    bindOriginalPreparation: (read, retainedBytes, executionBytes) =>
      checked(moon.clientProgramBindInferOriginalPreparation(active, read,
        retainedBytes, executionBytes)),
    // Installation-owned original references only. The existing Common owner
    // admits its quiescent boundary; no Node snapshot, caller Bool or CID can
    // substitute for the actual scope/token. A missing port is unavailable,
    // not a fallback to a Resource-only park.
    parkOriginalResources() {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramParkInferOriginalModelResources !== 'function') {
        throw new Error('InferOriginalModelParkUnavailable');
      }
      return checked(moon.clientProgramParkInferOriginalModelResources(
        active, originalScope));
    },
    parkOriginalResourcesForStateWrite() {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramParkInferOriginalModelResourcesForStateWrite !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      return checked(moon.clientProgramParkInferOriginalModelResourcesForStateWrite(active, originalScope));
    },
    prepareOriginalCurrentStateWriter(park, limits) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramPrepareInferOriginalCurrentStateWriter !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      if (limits === null || typeof limits !== 'object' ||
          Object.keys(limits).sort().join(',') !== 'maxDepth,maxNodes,maxWireBytes' ||
          Object.values(limits).some(value => !Number.isSafeInteger(value) || value < 0 || value > 2147483647) ||
          limits.maxNodes === 0) throw new TypeError('InvalidInferOriginalCurrentWriterLimits');
      return checked(moon.clientProgramPrepareInferOriginalCurrentStateWriter(active, originalScope, park,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    advanceOriginalCurrentStateWriter(park, writer, quantum) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramAdvanceInferOriginalCurrentStateWriter !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647) {
        throw new TypeError('InvalidInferOriginalCurrentWriterQuantum');
      }
      const poll = moon.clientProgramInferNodeReadStatePoll(
        moon.clientProgramAdvanceInferOriginalCurrentStateWriter(active, originalScope, park, writer, quantum));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2)});
    },
    finishOriginalCurrentStateWriter(park, writer) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramFinishInferOriginalCurrentStateWriter !== 'function') {
        throw new Error('InferOriginalCurrentWriterUnavailable');
      }
      return checked(moon.clientProgramFinishInferOriginalCurrentStateWriter(active, originalScope, park, writer));
    },
    cancelOriginalCurrentStateWriter(writer) {
      // Codec retirement remains legal during close; it neither frees the
      // Resource park nor substitutes for the original Model/read cleanup.
      moon.clientProgramCancelInferOriginalCurrentStateWriter(writer);
    },
    startOriginalCurrentStateDecode(park, wire, limits) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramStartInferOriginalCurrentStateDecode !== 'function') {
        throw new Error('InferOriginalCurrentDecodeUnavailable');
      }
      if (limits === null || typeof limits !== 'object' ||
          Object.keys(limits).sort().join(',') !== 'maxWork,parse,tree' ||
          !codecLimits(limits.parse, 'max_depth,max_input_bytes,max_nodes') ||
          !codecLimits(limits.tree, 'max_depth,max_nodes,max_string_bytes,max_total_string_bytes') ||
          !codecInt(limits.maxWork, true) || typeof wire !== 'string') {
        throw new TypeError('InvalidInferOriginalCurrentDecodeLimits');
      }
      const {parse, tree, maxWork} = limits;
      return checked(moon.clientProgramStartInferOriginalCurrentStateDecode(active, originalScope,
        park, wire, parse, tree, maxWork));
    },
    advanceOriginalCurrentStateDecode(park, decoder, quantum) {
      if (closing || reclaimed || originalScope === undefined) throw new Error('InferOriginalCurrentDecodeUnavailable');
      if (!codecInt(quantum, true)) throw new TypeError('InvalidInferOriginalCurrentDecodeQuantum');
      const poll = moon.clientProgramInferOriginalCurrentStateDecodePoll(
        moon.clientProgramAdvanceInferOriginalCurrentStateDecode(active, originalScope, park, decoder, quantum));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2), document: runtimeField(poll, 3)});
    },
    cancelOriginalCurrentStateDecode: decoder => moon.clientProgramCancelInferOriginalCurrentStateDecode(decoder),
    retireOriginalCurrentStateDocument: document => moon.clientProgramRetireInferOriginalCurrentStateDocument(document),
    startOriginalCurrentStateComparison(park, document, maxWork) {
      if (closing || reclaimed || originalScope === undefined) throw new Error('InferOriginalCurrentDecodeUnavailable');
      if (!codecInt(maxWork, true)) throw new TypeError('InvalidInferOriginalCurrentComparisonWork');
      return checked(moon.clientProgramStartInferOriginalCurrentStateComparison(active, originalScope, park, document, maxWork));
    },
    advanceOriginalCurrentStateComparison(park, comparison, quantum) {
      if (closing || reclaimed || originalScope === undefined) throw new Error('InferOriginalCurrentDecodeUnavailable');
      if (!codecInt(quantum, true)) throw new TypeError('InvalidInferOriginalCurrentComparisonQuantum');
      const poll = moon.clientProgramInferOriginalCurrentStateComparisonPoll(checked(
        moon.clientProgramAdvanceInferOriginalCurrentStateComparison(active, originalScope, park, comparison, quantum)));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2)});
    },
    cancelOriginalCurrentStateComparison: comparison => moon.clientProgramCancelInferOriginalCurrentStateComparison(comparison),
    advanceOriginalCurrentStateComparisonWithMatch(park, comparison, quantum) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch !== 'function') {
        throw new Error('InferOriginalCurrentMatchUnavailable');
      }
      if (!codecInt(quantum, true)) throw new TypeError('InvalidInferOriginalCurrentComparisonQuantum');
      const poll = moon.clientProgramInferOriginalCurrentStateMatchPoll(checked(
        moon.clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch(active, originalScope,
          park, comparison, quantum)));
      return Object.freeze({kind: runtimeField(poll, 0), work: runtimeField(poll, 1), issue: runtimeField(poll, 2), matched: runtimeField(poll, 3)});
    },
    originalCurrentStateMatchCurrent(park, matched) {
      if (reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalCurrentStateMatchCurrent !== 'function') return undefined;
      return moon.clientProgramInferOriginalCurrentStateMatchCurrent(active, originalScope, park, matched);
    },
    retireOriginalCurrentStateMatch: matched => moon.clientProgramRetireInferOriginalCurrentStateMatch(matched),
    originalResourceParkCurrent(park) {
      // A pending close is not a physical stop or invalidation. Preserve the
      // original observation while Core still owns this same parked scope.
      if (reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalModelResourceParkCurrent !== 'function') {
        return undefined;
      }
      return moon.clientProgramInferOriginalModelResourceParkCurrent(
        active, originalScope, park);
    },
    originalParkedReadCapacityAvailable(park, retainedBytes, executionBytes) {
      if (reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalParkedReadCapacityAvailable !== 'function') return false;
      if ([retainedBytes, executionBytes].some(value => typeof value !== 'bigint' ||
          value < 0n || value > 9223372036854775807n)) {
        throw new TypeError('InvalidInferOriginalParkedCapacity');
      }
      // Read the same original token only. Caller/installation must still
      // supply the justified simultaneous envelope before any physical I/O.
      return moon.clientProgramInferOriginalParkedReadCapacityAvailable(
        active, originalScope, park, retainedBytes, executionBytes);
    },
    originalStoreBootstrapAcquisition() {
      if (originalStoreBootstrap !== undefined) {
        originalStoreBootstrap.current(undefined, undefined, 'store-bootstrap');
        return originalStoreBootstrap.handle;
      }
      const selection = selectedInferOriginalMetadataLimits(metadataInstallation, metadataNodeInstallation);
      const current = (ownerId, requestCid, role) => {
        // This pre-park borrow is deliberately NOT a metadata/body/codec
        // acquisition or a stable cut. Only the same original read reservation
        // may cover the first Store observation while approval is pending.
        if (role !== 'store-bootstrap' || reclaimed || closing || signal?.aborted ||
            originalScope === undefined ||
            typeof moon.clientProgramInferOriginalUnparkedReadCapacityAvailable !== 'function' ||
            selectedInferOriginalMetadataLimits(metadataInstallation, metadataNodeInstallation) !== selection ||
            !moon.clientProgramInferOriginalUnparkedReadCapacityAvailable(active, originalScope,
              selection.retainedBytes, selection.workspaceBytes)) metadataUnavailable();
        if (ownerId !== undefined && (typeof metadataControl?.runDefinitionRunId !== 'function' ||
            ownerId !== `model-${metadataControl.runDefinitionRunId(metadataDefinition)}`) ||
            requestCid !== undefined && requestCid !== metadataDefinition?.identity) metadataUnavailable();
        return selectedInferOriginalStoreBootstrapLimits(metadataInstallation, metadataNodeInstallation);
      };
      // Same full envelope before allocating the extra record/handle. Physical
      // clamps themselves neither reserve bytes nor issue permission.
      current(undefined, undefined, 'store-bootstrap');
      const handle = Object.freeze({kind: 'original-infer-store-bootstrap-acquisition'});
      originalStoreBootstrap = {handle, current};
      originalMetadataSources.set(handle, new WeakRef(originalStoreBootstrap));
      return handle;
    },
    originalMetadataAcquisition(park) {
      if (originalMetadata !== undefined) {
        if (originalMetadata.park !== park) metadataUnavailable();
        originalMetadata.current();
        return originalMetadata.handle;
      }
      const selection = selectedInferOriginalMetadataLimits(metadataInstallation, metadataNodeInstallation);
      const current = (ownerId, requestCid, role) => {
        if (reclaimed || closing || signal?.aborted || originalScope === undefined ||
            typeof moon.clientProgramInferOriginalModelResourceParkCurrent !== 'function' ||
            typeof moon.clientProgramInferOriginalParkedReadCapacityAvailable !== 'function' ||
            selectedInferOriginalMetadataLimits(metadataInstallation, metadataNodeInstallation) !== selection ||
            moon.clientProgramInferOriginalModelResourceParkCurrent(active, originalScope, park) !== park ||
            !moon.clientProgramInferOriginalParkedReadCapacityAvailable(active, originalScope, park,
              selection.retainedBytes, selection.workspaceBytes)) metadataUnavailable();
        if (ownerId !== undefined && (typeof metadataControl?.runDefinitionRunId !== 'function' ||
            ownerId !== `model-${metadataControl.runDefinitionRunId(metadataDefinition)}`) ||
            requestCid !== undefined && requestCid !== metadataDefinition?.identity) metadataUnavailable();
        if (role === 'store-bootstrap') {
          return selectedInferOriginalStoreBootstrapLimits(metadataInstallation, metadataNodeInstallation);
        }
        if (role === 'resource-state-codec') {
          return selectedInferOriginalCurrentStateCodec(metadataInstallation, metadataNodeInstallation);
        }
      };
      // Inspect the same token BEFORE allocating the retained record/handle or
      // permitting physical metadata I/O. No grant/reset/refund follows.
      current();
      const handle = Object.freeze({kind: 'original-infer-metadata-acquisition'});
      originalMetadata = {park, selection, handle, current};
      originalMetadataSources.set(handle, new WeakRef(originalMetadata));
      return handle;
    },
    // Borrow the opaque scope captured by this actual operation, not a new
    // selection supplied to a later continuation. Successful cleanup retires
    // the alias; its presence alone is not a park, grant or send permission.
    originalResourceScope: () => reclaimed ? undefined : originalScope,
    beginOriginalResourceInvalidation(park) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramBeginInferOriginalModelInvalidation !== 'function') {
        throw new Error('InferOriginalModelInvalidationUnavailable');
      }
      return checked(moon.clientProgramBeginInferOriginalModelInvalidation(active, originalScope, park));
    },
    originalResourceInvalidationCurrent(park, request) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramInferOriginalModelInvalidationCurrent !== 'function') return undefined;
      return moon.clientProgramInferOriginalModelInvalidationCurrent(active, originalScope, park, request);
    },
    completeOriginalJournalInvalidation(port, receipt, reference, park, request) {
      if (closing || reclaimed || originalScope === undefined ||
          typeof moon.clientProgramCompleteInferOriginalJournalInvalidation !== 'function') {
        throw new Error('InferOriginalModelInvalidationUnavailable');
      }
      // This compiled entry authenticates the actual journal module, not a
      // supplied callback or a bare Core consume. Its arguments always borrow
      // this operation's original active/Scope; the caller cannot replace them.
      return checked(moon.clientProgramCompleteInferOriginalJournalInvalidation(
        active, originalScope, port, receipt, reference, park, request));
    },
    bindDispatch: (control, {compiled, runDefinition, ...observation}) =>
      control.bindCheckedClientInferDispatch(compiled, active, runDefinition,
        observation),
    preparedCallSet: () => reclaimed ? undefined : moon.clientProgramInferPreparedCallSet(active),
    pendingSettlement: () => moon.clientProgramInferCallSettlement(active),
    exportPreparedInput: (preparedCallSet, binding) => {
      const exported = checked(moon.clientProgramExportInferPreparedInput(active, preparedCallSet, binding));
      return Object.freeze({owner: exported,
        descriptorWire: moon.clientProgramInferPreparedInputExportDescriptor(exported),
        rows: Object.freeze(moon.clientProgramInferPreparedInputExportRows(exported)),
        current: () => moon.clientProgramInferPreparedInputExportMatches(active, preparedCallSet, exported)});
    },
    preparedFacts: preparedCallSet => {
      if (reclaimed) throw new Error('InferPreparedOwnerUnavailable');
      originalPreparedCallSet = preparedCallSet;
      const count = moon.clientProgramInferPreparedCallCount(preparedCallSet);
      const input = moon.clientProgramInferPreparedInput(preparedCallSet);
      const artifact = moon.clientProgramInferPreparedInputArtifact(preparedCallSet);
      const ids = moon.clientProgramInferPreparedIdentities(preparedCallSet);
      if (!Number.isSafeInteger(count) || count < 0 || count > 128 ||
          input === undefined || artifact === undefined || ids === undefined) {
        throw new Error('InferPreparedOwnerUnavailable');
      }
      const slotWires = Array.from({length: count}, (_, slot) => {
        const call = moon.clientProgramInferPreparedCallAt(preparedCallSet, slot);
        if (call === undefined) throw new Error('InferPreparedCallUnavailable');
        return moon.strategyRunEvidenceJson(call);
      });
      return Object.freeze({preparedCallSet, input,
        inputArtifactWire: moon.strategyRunEvidenceJson(artifact),
        slotWires: Object.freeze(slotWires), providerId: runtimeField(ids, 0),
        modelTaskCid: runtimeField(ids, 1), fixedRequestCid: runtimeField(ids, 2),
        unitId: moon.clientProgramInferCallScopeUnitId(active),
        callScopeSnapshotWire: checked(moon.clientProgramInferCallScopeSnapshot(active))});
    },
    bindModelScope: (control, plan, preparedCallSet, originals) =>
      control.bindCheckedClientInferModelScope(plan.compiled, active,
        plan.runDefinition, preparedCallSet, originals),
    bindModelDispatch: (control, plan, preparedCallSet, scope, observation) =>
      control.bindCheckedClientInferModelDispatch(plan.compiled, active,
        plan.runDefinition, preparedCallSet, scope, {...observation,
          enterCall: entry => {
            const originals = moon.clientProgramInferCallEntryOriginals(entry);
            if (originals === undefined) return false;
            return observation.enterCall(Object.freeze({entry,
              slot: runtimeField(originals, 0), callWire: runtimeField(originals, 1),
              attemptWire: runtimeField(originals, 2), authorityWire: runtimeField(originals, 3)})) === true;
          }}),
    entryCurrent: (entry, preparedCallSet) =>
      moon.clientProgramInferCallEntryCurrent(entry, preparedCallSet),
    // Installation-only wake endpoint of this already claimed operation.
    // It is not an ACK, public capability or permission to begin another call.
    ioNotification,
    // Private installation seam of this original physical operation only.
    // Common registration supplies the nominal raw authority; this callback
    // creates neither a send claim nor an alternate cleanup owner.
    bindModelRawCapture(registration, persistence) {
      if (closing || reclaimed || rawCaptureBound ||
          rawCaptureBinder === undefined && preparedRawCaptureBinders === undefined) {
        throw new TypeError('InferRawCaptureBindingUnavailable');
      }
      if (persistence !== undefined &&
          !originalModelRawTransportPersistenceMatches(persistence, operation, registration)) {
        throw new TypeError('ForeignInferRawCapturePersistence');
      }
      rawCaptureBound = true;
      try {
        const callbacks = preparedRawCaptureBinders ?? [rawCaptureBinder];
        bindOriginalModelRawTransportPersistence(persistence, operation, registration, next => {
          for (const callback of callbacks) {
            if (callback(registration, next()) !== undefined) {
              throw new TypeError('InvalidInferRawCaptureBinderResult');
            }
          }
        });
      } finally {
        // A partial failure cannot retry any already bound child. Every
        // original cursor still belongs to Common's existing cleanup census;
        // dropping these auxiliary aliases neither retires it nor ACKs raw.
        rawCaptureBinder = undefined;
        preparedRawCaptureBinders = undefined;
      }
    },
    bindModelEntryPersistence: (control, plan, preparedCallSet, scope, observation) =>
      control.bindCheckedClientInferModelEntryPersistence(plan.compiled, active,
        plan.runDefinition, preparedCallSet, scope, {...observation,
          beginEntry: entry => {
            const originals = moon.clientProgramInferCallEntryOriginals(entry);
            if (originals === undefined) return undefined;
            return observation.beginEntry(Object.freeze({entry,
              slot: runtimeField(originals, 0), callWire: runtimeField(originals, 1),
              attemptWire: runtimeField(originals, 2), authorityWire: runtimeField(originals, 3)}));
          }}),
    bindModelObservation: (preparedCallSet, observe) => {
      if (assertRuntimeCurrent !== undefined) {
        // Currentness is installed even when optional OTel is absent. Attach
        // metadata delivery to that SAME once-bound observer, not another one.
        if (!bindOriginalRuntimeObservation(preparedCallSet)) return false;
        runtimeDiagnostic = observe;
        return true;
      }
      return moon.clientProgramBindInferModelObservation(active, preparedCallSet, value => {
        // Only the installed metadata observer is called here. Its failure
        // must not escape into invoke, admission, accounting, or cleanup.
        try {
          const facts = moon.clientProgramInferPhysicalObservationFacts(value);
          observe({slot: runtimeField(facts, 0), attemptCid: runtimeField(facts, 1), event: runtimeField(facts, 2), outcome: runtimeField(facts, 3)});
        } catch { /* Optional observation has no execution authority. */ }
      });
    },
    restoreCall: (preparedCallSet, slot, record, proof, bundle) => checked(
      moon.clientProgramRestoreInferPreparedCall(preparedCallSet, slot, record, proof, bundle)),
    restoreUnknown: (preparedCallSet, slot, attempt, authority) => checked(
      moon.clientProgramRestoreInferPreparedUnknown(preparedCallSet, slot, attempt, authority)),
    prepareResponseReconciliation: (preparedCallSet, slot, attempt, authority) => checked(
      moon.clientProgramPrepareInferResponseReconciliation(preparedCallSet, slot, attempt, authority)),
    adoptReconciledResponse: (token, response) => checked(
      moon.clientProgramAdoptReconciledInferResponse(token, response)),
    settlementSlot: settlement => moon.clientProgramInferCallSettlementSlot(settlement),
    acknowledgeSettlement: settlement => {
      if (!moon.clientProgramAcknowledgeInferCallSettlement(settlement)) {
        throw new Error('InferSettlementAcknowledgementRejected');
      }
    },
    attemptEvidence: slot => checked(moon.clientProgramInferAttemptEvidence(
      active, slot)),
    advanceStoppedAttemptUsage(slot, quantum) {
      if (reclaimed || typeof moon.clientProgramAdvanceInferStoppedRawUsage !== 'function') {
        throw new Error('InstalledInferRawUsageUnavailable');
      }
      if (!codecInt(slot) || !codecInt(quantum, true)) {
        throw new TypeError('InvalidInferRawUsageQuantum');
      }
      // Common selects the original call/child and accounts its remaining
      // work. Closing/AbortSignal alone cannot erase partial observations or
      // become a new dispatch authorization check for this cleanup duty.
      const progress = checked(moon.clientProgramAdvanceInferStoppedRawUsage(active, slot, quantum));
      return Object.freeze({complete:runtimeField(progress, 0),work:runtimeField(progress, 1),issue:runtimeField(progress, 2)});
    },
    issuedAttachmentAdmission: slot => checked(moon.clientProgramIssueInferAttachmentAdmission(active, slot)),
    issuedSlotCapture: slot => checked(moon.clientProgramIssueInferSlotCapture(
      active, slot)),
    bindInvocation: (control, {compiled, runDefinition, verification,
      invocation, dataPolicyCid}) => control.bindCheckedClientInferInvocation(
      compiled, active, runDefinition, verification, invocation, dataPolicyCid),
    reserveOriginalPublicationCapacity() {
      if (originalConsumer === undefined) return;
      if (reclaimed || closing) throw new Error('InferOriginalPublicationCapacityUnavailable');
      if (originalPublicationCapacity !== undefined) return;
      const selection = originalPublicationSelection === undefined
        ? selectedInferOriginalPublicationCapacity(metadataInstallation, metadataNodeInstallation)
        : Reflect.apply(originalPublicationSelection, originalPublicationReceiver, []);
      const names = selection !== null && typeof selection === 'object' && !Array.isArray(selection)
        ? Reflect.ownKeys(selection) : [];
      const retained = Object.getOwnPropertyDescriptor(selection ?? {}, 'retainedBytes');
      const workspace = Object.getOwnPropertyDescriptor(selection ?? {}, 'workspaceBytes');
      if (names.length !== 2 || !names.includes('retainedBytes') || !names.includes('workspaceBytes') ||
          retained === undefined || workspace === undefined ||
          !Object.hasOwn(retained, 'value') || !Object.hasOwn(workspace, 'value') ||
          typeof retained.value !== 'bigint' || retained.value <= 0n || retained.value > 9223372036854775807n ||
          typeof workspace.value !== 'bigint' || workspace.value < 0n || workspace.value > 9223372036854775807n) {
        throw Object.assign(new Error('InferOriginalPublicationCapacityUnavailable'),
          {code: 'InferOriginalPublicationCapacityUnavailable'});
      }
      // Common binds this borrow to the exact terminal Model/Scope and its
      // original Run Ledger. Missing/refused selection never falls back.
      originalPublicationCapacity = checked(moon.clientProgramReserveOriginalInferPublicationCapacity(
        active, retained.value, workspace.value));
    },
    publicationCapacityPending: () => originalPublicationCapacity !== undefined,
    releaseOriginalPublicationCapacity() {
      if (originalPublicationCapacity === undefined) return true;
      const released = checked(moon.clientProgramReleaseOriginalInferPublicationCapacity(
        originalPublicationCapacity));
      if (released) originalPublicationCapacity = undefined;
      return released;
    },
    startObservation: ({ledger, maxSlots, maxWireBytes, maxWork}) => {
      if (originalConsumer !== undefined) {
        if (ledger !== undefined || originalPublicationCapacity === undefined) {
          throw new Error('InferOriginalPublicationCapacityUnavailable');
        }
        return checked(moon.clientProgramStartOriginalInferObservationIssuance(active,
          originalPublicationCapacity, maxSlots, maxWireBytes, maxWork,
          serializedInput === undefined ? [] : [serializedInput.generation]));
      }
      // Preserve the explicit legacy diagnostic/publication path. The original
      // installation never creates this separate Ledger as a funding fallback.
      ledger ??= checked(moon.clientProgramInferPublicationLedger(
        BigInt(maxWireBytes) * 16n + BigInt(maxSlots) * 128n +
        BigInt(operation.contentGenerationCount ?? 0) * 256n, maxWork));
      return serializedInput !== undefined
      ? serializedInput.control.startCheckedClientContentInferObservation(
        serializedInput.compiled, [active], [serializedInput.generation], ledger,
        {maxSlots, maxWireBytes, maxWork})
      : checked(moon.clientProgramStartInferObservationIssuance(active, ledger,
        maxSlots, maxWireBytes, maxWork));
    },
    bindIssuedInvocation: (control, {compiled, runDefinition, issued}) =>
      control.bindIssuedClientInferInvocation(compiled, active, runDefinition,
        issued),
    // Store use is awaited to settlement before releasing the common Result
    // owner. Aborting a writer is not physical stop confirmation.
    withResult: (binding, result, consume, resultSignal = signal) =>
      withNodeInferResult({moon, binding, result, consume,
        signal: resultSignal, quantum}),
  });
  activeOperations.set(operation, active);
  if (originalConsumer !== undefined) originalOperations.add(operation);
  try {
    // Input construction already owns Core resources. Transfer that exact
    // owner before any fallible binding, without granting permission to run.
    retainOperation?.(operation);
    if (durableCalls) checked(moon.clientProgramRequireInferCallEntry(active));
    if (restoredInput !== undefined) checked(moon.clientProgramRestrictInferSendSlots(active,
      restoredInput.sendMask));
    if (quantityCapacity !== undefined) {
      const {limits, perAttempt} = quantityCapacity;
      checked(moon.clientProgramBindInferQuantityCapacity(active,
        limits.tokens, limits.costUnits, limits.durationMs,
        perAttempt.tokens, perAttempt.costUnits, perAttempt.durationMs));
    }
    if (bindComputeSuffix !== undefined) checked(bindComputeSuffix(active));
    else if (computeSuffix !== undefined && keyedInput === undefined) checked(moon.clientProgramBindInferComputeSuffix(active, computeSuffix));
    if (physicalPreflight !== undefined) {
      // Reuse this operation's nominal wake endpoint for SDK preparation and
      // physical I/O. It carries no ACK, outcome, authority or send permission.
      // The original preparation envelope funds this one callback closure and
      // its overlap with Core's retained callback; no per-poll context is made.
      const prepare = ioNotification === undefined ? physicalPreflight
        : request => prepareWithOriginalRawSetter(physicalPreflight, request,
          ioNotification, retainRawCaptureBinder);
      checked(assertRuntimeCurrent === undefined
        ? moon.clientProgramBindInferPhysicalPreflight(active, prepare)
        : moon.clientProgramBindInferPhysicalPreflightCurrent(active, prepare, runtimeCurrent));
    }
    if (egressAdmission !== undefined) checked(moon.clientProgramBindInferEgress(active, egressAdmission));
  } catch (error) {
    // Preserve the admission failure even when stop/cleanup cannot finish.
    // The receiving parent retries this owner, never construction or dispatch.
    closing = true;
    try {
      requestStop();
      const stopped = checked(moon.clientProgramAdvanceInferExecution(active, 1));
      if (moon.clientProgramInferExecutionPollKind(stopped) === 'stopped' &&
          retainOperation === undefined) cleanup();
    } catch { /* The original failure and pending owner remain authoritative. */ }
    if (!reclaimed && error !== null && typeof error === 'object' &&
        Object.isExtensible(error) && !Object.hasOwn(error, 'cleanupOwner')) {
      Object.defineProperty(error, 'cleanupOwner', {value: operation});
    }
    throw error;
  }
  return operation;
}

// One original Model component is opened by the common Local task driver,
// after it has bound actual producer reads. Local alone advances it. The
// installing Run retains physical custody before binding current admissions.
export function openNodeComposedInferProvider({moon, selected, sources,
  control, plan, principalId, now, signal, retainOperation, retainCompleted,
  durableCalls = false, restoredInput, generatedInput, originalPreparation, deferred = false,
  inputPrefix = selected?.computePrefix, bindComputeSuffix, assertRuntimeCurrent}) {
  if (selected?.occurrence === undefined ||
      typeof deferred !== 'boolean' || !deferred && typeof retainOperation !== 'function' ||
      deferred && (generatedInput !== undefined || originalPreparation !== undefined || retainOperation !== undefined)) {
    throw new TypeError('InvalidComposedInferProvider');
  }
  if (bindComputeSuffix !== undefined && typeof bindComputeSuffix !== 'function') {
    throw new TypeError('InvalidInferOriginalSuffixBinding');
  }
  let prepareRead = originalPreparation?.prepareRead;
  let deferredRead = prepareRead !== undefined;
  if (deferredRead && (typeof prepareRead !== 'function' ||
      generatedInput !== undefined || restoredInput !== undefined)) {
    throw new TypeError('InvalidComposedInferOriginalPreparation');
  }
  let readAttempted = false;
  let operation;
  let failure;
  let failureRecorded = false;
  const recordFailure = cause => {
    if (!failureRecorded) {failure = cause; failureRecorded = true;}
  };
  let bound = !deferred, attempted = false;
  // A Request module can supply its already-backed original before this
  // native component selects input-dependent capacity. Never reprepare it.
  const computePrefix = inputPrefix;
  const selectProvider = generatedInput === undefined
    ? moon.clientProgramComposedInferLocalProvider : moon.clientProgramGeneratedInferLocalProvider;
  const provider = selectProvider(
    selected.occurrence, inputs => {
      try {
        if (attempted || operation !== undefined || readAttempted || deferredRead && failure !== undefined) {
          if (failureRecorded) throw failure;
          throw new Error('ComposedInferAlreadyOpened');
        }
        attempted = true;
        if (!bound) throw new Error('ComposedInferOriginalContextUnavailable');
        let preparation = originalPreparation;
        if (deferredRead) {
          // The parent already retains the Scope. Claim its read only after
          // Local has supplied the actual inputs, with no intervening await.
          readAttempted = true;
          try { preparation = Reflect.apply(prepareRead, originalPreparation, []); }
          finally {
            // Retire only these callback aliases, never the original parent's
            // read/Scope duty or a failed issuance's pending cleanup.
            prepareRead = undefined;
            originalPreparation = undefined;
          }
          // Do not read an inherited getter on the original view. A native
          // async return is observed only to suppress detached rejection, not
          // awaited or admitted as a synchronous read original.
          const asyncView = isPromise(preparation);
          if (preparation === null || typeof preparation !== 'object' ||
              asyncView || Object.hasOwn(preparation, 'then')) {
            if (asyncView) void Reflect.apply(observePromise, preparation, [undefined, () => {}]);
            throw new TypeError('InvalidComposedInferOriginalPreparation');
          }
        }
        operation = openNodeInferOperation({moon, graph: selected.graph,
          composedInput: generatedInput !== undefined ? undefined : {occurrence: selected.occurrence,
            prefix: computePrefix, inputs, sources},
          serializedInput: generatedInput === undefined ? undefined : {
            control, compiled: plan.compiled, definition: plan.runDefinition,
            generation: generatedInput.generation(), inputs,
            recovery: generatedInput.recovery?.()},
          computeSuffix: generatedInput === undefined ? selected.computeSuffix : undefined, provider: selected.provider,
          quantityCapacity: selected.quantityCapacity,
          physicalPreflight: selected.physicalPreflight,
          egressAdmission: selected.egressAdmission, signal, durableCalls, restoredInput,
          originalPreparation: preparation, bindComputeSuffix, assertRuntimeCurrent,
          retainOperation(value) { operation = value; retainOperation(value); }});
        operation.bindRun(control, plan);
        if (!durableCalls) operation.bindDispatch(control, {...plan, account: selected.account,
          principalId, at: now(), observeAccount: selected.observeAccount,
          observeAt: now});
        return activeOperations.get(operation);
      } catch (error) {
        recordFailure(error);
        return undefined;
      }
    }, issue => {
      recordFailure(Object.assign(new Error('ComposedInferComponentFailed'),
        {code: 'MoonBitHostFailure', cause: issue}));
    }, active => {
      try {
        if (operation === undefined || activeOperations.get(operation) !== active) {
          throw new Error('ForeignComposedInferCompletion');
        }
        return retainCompleted?.(operation) !== false;
      } catch (error) {
        recordFailure(error);
        return false;
      }
    }, active => operation !== undefined &&
      activeOperations.get(operation) === active &&
      operation.cleanupPending() === false,
    ...(generatedInput === undefined ? [computePrefix] : []));
  const component = Object.freeze({provider, operation: () => operation,
    failure: () => failure, hasFailure: () => failureRecorded,
    ...(deferred ? {bindOriginal(context) {
      if (bound || attempted) throw new Error('ComposedInferAlreadyBound');
      const read = name => Object.getOwnPropertyDescriptor(context ?? {}, name)?.value;
      if (read('selected') !== selected || typeof read('retainOperation') !== 'function') {
        throw new TypeError('InvalidComposedInferOriginalContext');
      }
      const preparation = read('originalPreparation'), prepare = preparation?.prepareRead;
      if (prepare !== undefined && (typeof prepare !== 'function' || read('restoredInput') !== undefined)) {
        throw new TypeError('InvalidComposedInferOriginalPreparation');
      }
      sources = read('sources'); control = read('control'); plan = read('plan');
      principalId = read('principalId'); now = read('now'); signal = read('signal');
      retainOperation = read('retainOperation'); retainCompleted = read('retainCompleted');
      durableCalls = read('durableCalls') === true; restoredInput = read('restoredInput');
      assertRuntimeCurrent = read('assertRuntimeCurrent');
      if (assertRuntimeCurrent !== undefined && typeof assertRuntimeCurrent !== 'function') {
        throw new TypeError('InferTrustedRuntimeScopeUnavailable');
      }
      originalPreparation = preparation; prepareRead = prepare; deferredRead = prepare !== undefined;
      bound = true;
      return component;
    }} : {})});
  return component;
}

// This is physical stepping of the existing checked Result transformer, not
// another publisher or an adapter-authored publication inventory. The Store
// callback receives the common selection and ordinary opaque output exporter.
export async function withNodeInferResult({moon, binding, result, consume,
  signal, quantum = 256}) {
  if (typeof consume !== 'function' || !Number.isSafeInteger(result) ||
      result < 0 || !Number.isSafeInteger(quantum) || quantum < 1 ||
      quantum > 2147483647) {
    throw new TypeError('InvalidInstalledInferResult');
  }
  signal?.throwIfAborted();
  const owner = checked(moon.clientProgramInferPublicationBegin(binding,
    result));
  const cancel = () => moon.clientProgramInferPublicationCancel(owner);
  signal?.addEventListener('abort', cancel, {once: true});
  let custodyTransferred = false;
  try {
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(moon.clientProgramInferPublicationAdvance(owner,
        quantum));
      if (runtimeField(progress, 0)) break;
      await yieldEventLoop();
    }
    signal?.throwIfAborted();
    const selection = moon.clientProgramInferPublicationSelection(owner);
    const exported = checked(moon.clientProgramInferPublicationFinish(owner));
    // Do not race this against abort: a rejected/aborted consumer must first
    // settle its physical I/O and retain any unresolved cleanup responsibility.
    return await consume({selection, exported, signal,
      storeExport: () => checked(
        moon.clientProgramInferPublicationStoreExport(owner))});
  } catch (failure) {
    if (failure?.cleanupPending === true) {
      // The existing dispatch supervisor retries this exact Store cleanup
      // handle. Keep the Result pinned until that handle confirms settlement;
      // a rejected consumer Promise alone cannot confirm physical stop.
      const original = failure.cleanupHandle;
      custodyTransferred = true;
      const retained = Object.freeze({
        status: () => ({pending: custodyTransferred}),
        async retry() {
          if (!custodyTransferred) return false;
          if (typeof original?.retry !== 'function' ||
              typeof original?.status !== 'function') throw pending();
          if (original.status()?.pending === true) await original.retry();
          if (original.status()?.pending !== false) throw pending();
          moon.clientProgramInferPublicationRelease(owner);
          custodyTransferred = false;
          return true;
        },
      });
      // Preserve the original typed cause even when its Error is immutable.
      const held = new Error(failure.message, {cause: failure});
      held.code = failure.code;
      held.cleanupPending = true;
      held.cleanupHandle = retained;
      throw held;
    }
    throw failure;
  } finally {
    signal?.removeEventListener('abort', cancel);
    if (!custodyTransferred) moon.clientProgramInferPublicationRelease(owner);
  }
}
