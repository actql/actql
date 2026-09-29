// Complete publication of every checked Named Result retained by one finished
// Effect-free Run. MoonBit issues and validates every semantic contract. This
// coordinator only sequences bounded export and durable Store effects.
import {publishEffectFreeRun, publishEffectfulRun} from
  './run-publication.mjs';
import {preparePrivatePublicationHolding} from
  './private-publication-holding.mjs';

export class CompletedRunPublicationError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
  }
}

const fail = (code, cause) => {
  throw new CompletedRunPublicationError(code, cause);
};
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};
const contract = value => value !== null && typeof value === 'object' &&
  typeof value.name === 'string' && typeof value.identity === 'string' &&
  typeof value.wire === 'string';
const ownContract = (control, value, limits,
  code = 'InvalidCompletedRunPublicationContract') => {
  const admitted = control.admit(value.name, value.wire, limits);
  if (admitted.identity !== value.identity) {
    fail(code);
  }
  return admitted;
};
const completedResultOwners = new WeakMap();
const completedEffectfulOwners = new WeakMap();
const privateEffectfulHoldings = new WeakMap();

function validateExecution(execution) {
  if (execution === null || typeof execution !== 'object' ||
      execution.status !== 'host-tasks-completed' ||
      !Array.isArray(execution.resultInventory) ||
      execution.resultInventory.length === 0 ||
      execution.publicationInventory === undefined ||
      !Array.isArray(execution.publicationInventory.occurrences) ||
      execution.publicationInventory.occurrences.length !==
        execution.resultInventory.length ||
      typeof execution.storePublicationResult !== 'function') {
    fail('InvalidCompletedRunPublicationExecution');
  }
}

function validateControl(control) {
  if (control === null || typeof control !== 'object' ||
      !['issueResultManifest', 'issueEffectFreeRunReceipt',
        'issueEffectFreeCapturedRun', 'publicationPreparedReleaseAction',
        'publicationCleanupOwnerAction']
        .every(name => typeof control[name] === 'function')) {
    fail('InvalidCompletedRunPublicationControl');
  }
}

function validateOptions(options) {
  const keys = [
    'execution', 'store', 'control', 'admission', 'runDefinition',
    'invocation', 'observation', 'normalizationJournal', 'authoringContext',
    'results', 'receiptEvidence', 'captureEvidence', 'request', 'attempt',
    'outputLimits', 'contractLimits', 'now', 'signal',
  ];
  if (!exactKeys(options, keys) || !Array.isArray(options.results) ||
      !exactKeys(options.receiptEvidence, [
        'bindings', 'sourceEvidence', 'modelEvidence',
        'barrierAttemptReceiptCids',
      ]) || !exactKeys(options.captureEvidence, [
        'pendingSourceStateAdvances', 'modelEvidence',
      ]) || !Array.isArray(options.receiptEvidence.bindings) ||
      !Array.isArray(options.receiptEvidence.sourceEvidence) ||
      !Array.isArray(options.receiptEvidence.modelEvidence) ||
      !Array.isArray(options.receiptEvidence.barrierAttemptReceiptCids) ||
      !Array.isArray(options.captureEvidence.pendingSourceStateAdvances) ||
      !Array.isArray(options.captureEvidence.modelEvidence)) {
    fail('InvalidCompletedRunPublicationOptions');
  }
  validateExecution(options.execution);
  validateControl(options.control);
  if (![options.runDefinition, options.invocation].every(contract) ||
      options.results.length !== options.execution.resultInventory.length) {
    fail('InvalidCompletedRunPublicationOptions');
  }
  for (const result of options.results) {
    if (!exactKeys(result, ['retention', 'evidenceContext',
          ...(result?.transformation === undefined ? [] : ['transformation'])]) ||
        !contract(result.retention) || result.evidenceContext === null ||
        typeof result.evidenceContext !== 'object') {
      fail('InvalidCompletedRunPublicationOptions');
    }
  }
}

function uniqueContracts(values) {
  const seen = new Set();
  return values.filter(value => {
    if (seen.has(value.identity)) return false;
    seen.add(value.identity);
    return true;
  });
}

// Shared failure cleanup for prepared public Results and private Effect
// inputs. Always rethrow the primary failure, retaining retryable custody.
export async function releasePreparedResults(exported, primary, control) {
  const prepared = [...new Set(exported
    .map(value => value?.prepared)
    .filter(value => value !== undefined))];
  const errors = [];
  let currentPrepared = prepared.length - 1;
  let preparedStatusChecked = false;
  let preparedPending = false;
  let preparedReleaseAttempted = false;
  while (true) {
    const action = control.publicationPreparedReleaseAction(
      currentPrepared,
      prepared.length,
      preparedStatusChecked,
      preparedPending,
      preparedReleaseAttempted,
    );
    if (action === 'inspect') {
      try {
        preparedPending = prepared[currentPrepared].status()?.pending !== false;
      } catch (error) {
        errors.push(error);
        preparedPending = true;
      }
      preparedStatusChecked = true;
      continue;
    }
    if (action === 'release') {
      preparedReleaseAttempted = true;
      try { await prepared[currentPrepared].release(); }
      catch (error) { errors.push(error); }
      continue;
    }
    if (action === 'advance') {
      currentPrepared--;
      preparedStatusChecked = false;
      preparedPending = false;
      preparedReleaseAttempted = false;
      continue;
    }
    if (action === 'finished') break;
    fail('InvalidCompletedRunPublicationReleaseProgress');
  }
  const owners = [];
  const ownerHandles = new Set();
  const addOwner = (handle, required) => {
    if (handle !== undefined && ownerHandles.has(handle)) return;
    if (handle !== undefined) ownerHandles.add(handle);
    owners.push(Object.freeze({handle, required}));
  };
  if (member(primary, 'cleanupPending') === true) {
    addOwner(member(primary, 'cleanupHandle'), true);
  }
  for (const handle of prepared) addOwner(handle, true);
  const ownerState = owner => {
    if (!owner.handle || typeof member(owner.handle, 'status') !== 'function') {
      return {pending: owner.required, errors: []};
    }
    try {
      const value = owner.handle.status();
      return value && typeof value.pending === 'boolean'
        ? {pending: value.pending,
          outcome: typeof value.outcome === 'string'
            ? value.outcome : undefined,
          errors: Array.isArray(value.errors) ? [...value.errors] : []}
        : {pending: true, errors: []};
    } catch (error) { return {pending: true, errors: [error]}; }
  };
  if (!owners.some(owner => ownerState(owner).pending)) throw primary;
  const failure = new CompletedRunPublicationError(
    typeof member(primary, 'code') === 'string'
      ? member(primary, 'code') : 'CompletedRunPublicationFailed',
    primary,
  );
  const status = () => Object.freeze({
    pending: owners.some(owner => ownerState(owner).pending),
    outcome: owners.map(owner => ownerState(owner).outcome)
      .find(value => value !== undefined),
    errors: Object.freeze([
      ...owners.flatMap(owner => ownerState(owner).errors),
      ...errors,
    ]),
  });
  failure.primaryFailure = primary;
  failure.cleanupPending = true;
  failure.cleanupErrors = status().errors;
  failure.cleanupHandle = Object.freeze({
    status,
    async retry() {
      let currentOwner = 0;
      let ownerStatusChecked = false;
      let ownerPending = false;
      let retryAvailable = false;
      let retryAttempted = false;
      while (true) {
        const action = control.publicationCleanupOwnerAction(
          currentOwner,
          owners.length,
          ownerStatusChecked,
          ownerPending,
          retryAvailable,
          retryAttempted,
        );
        if (action === 'inspect') {
          ownerPending = ownerState(owners[currentOwner]).pending;
          retryAvailable = typeof member(
            owners[currentOwner].handle, 'retry',
          ) === 'function';
          ownerStatusChecked = true;
          continue;
        }
        if (action === 'retry') {
          retryAttempted = true;
          try { await owners[currentOwner].handle.retry(); }
          catch (error) { errors.push(error); }
          continue;
        }
        if (action === 'advance') {
          currentOwner++;
          ownerStatusChecked = false;
          ownerPending = false;
          retryAvailable = false;
          retryAttempted = false;
          continue;
        }
        if (action === 'finished') break;
        fail('InvalidCompletedRunPublicationCleanupProgress');
      }
      failure.cleanupPending = status().pending;
      failure.cleanupErrors = status().errors;
      return status();
    },
  });
  throw failure;
}

async function exportCompletedRunResultSet({
  execution, store, control, runDefinition, invocation, results,
  outputLimits, contractLimits, signal,
}, exported) {
  validateExecution(execution);
  if (!Array.isArray(results) ||
      results.length !== execution.resultInventory.length ||
      !contract(runDefinition) || !contract(invocation) ||
      typeof control?.publicationPreparedReleaseAction !== 'function' ||
      typeof control?.publicationCleanupOwnerAction !== 'function') {
    fail('InvalidCompletedRunResultSet');
  }
  for (let index = 0; index < results.length; index++) {
    signal?.throwIfAborted();
    const result = results[index];
    if (!exactKeys(result, ['retention', 'evidenceContext',
          ...(result?.transformation === undefined ? [] : ['transformation'])]) ||
        !contract(result.retention) ||
        result.evidenceContext === null ||
        typeof result.evidenceContext !== 'object') {
      fail('InvalidCompletedRunResultSet');
    }
    const stored = await execution.storePublicationResult(index, store, {
      outputLimits, contractLimits, runDefinition, invocation,
      retention: result.retention,
      evidenceContext: result.evidenceContext,
      transformation: result.transformation,
    }, signal);
    const expected = execution.publicationInventory.occurrences[index];
    if (stored?.occurrence?.name !== expected.name ||
        stored?.occurrence?.task !== expected.task ||
        stored?.occurrence?.definition?.identity !==
          expected.definitionContract.identity ||
        !contract(stored?.publication?.artifact) ||
        !contract(stored?.publication?.derivation) ||
        !contract(stored?.publication?.ordering) ||
        !contract(stored?.publication?.durableBinding) ||
        stored?.publication?.snapshot === undefined) {
      if (stored?.prepared !== undefined) exported.push(stored);
      fail('InvalidCompletedRunPublicationExport');
    }
    exported.push(stored);
  }
  return Object.freeze({
    results: Object.freeze([...exported]),
    definitions: Object.freeze(execution.publicationInventory.occurrences
      .map(value => value.definitionContract)),
    artifacts: Object.freeze(exported.map(
      value => value.publication.artifact)),
  });
}

// Prepare the exact checked Named Result inventory for either Run kind.
// This is not publication: the caller retains every prepared Store owner
// until the enclosing chain is committed or explicitly released.
export async function storeCompletedRunResultSet(options) {
  const exported = [];
  try {
    const stored = await exportCompletedRunResultSet(options, exported);
    completedResultOwners.set(stored, {
      execution: options.execution, store: options.store,
      control: options.control,
      runDefinition: Object.freeze({...options.runDefinition}),
      retentions: Object.freeze(options.results.map(value =>
        ownContract(options.control, value.retention,
          options.contractLimits))),
      releaseComplete: false, releaseFlight: undefined,
      cleanupFailure: undefined, captureHolding: undefined,
      capturePublished: false,
    });
    return stored;
  } catch (error) {
    if (exported.length === 0 &&
        member(error, 'cleanupPending') !== true) throw error;
    await releasePreparedResults(exported, error, options?.control);
  }
}

// Adopt prepared upstream payloads into the existing completed Result owner.
// This is process-local custody, not a durable capture or approval permit.
// The Artifact's admitted export receipt supplies physical facts; caller
// coordinates cannot relabel a foreign Run or a different exported payload.
export function retainCompletedEffectDependencyPayloads({
  execution, store, storedResults, control, runDefinition, dependencies,
  dependencyInventoryWire,
}) {
  const owner = completedResultOwners.get(storedResults);
  if (owner === undefined || owner.execution !== execution || owner.store !== store ||
      owner.control !== control || owner.releaseComplete ||
      owner.releaseFlight !== undefined || owner.cleanupFailure !== undefined ||
      owner.captureHolding !== undefined ||
      owner.effectDependencyPayloads !== undefined ||
      !Array.isArray(dependencies) || dependencies.length > 4096 ||
      typeof control?.localEffectResultPayloadBinding !== 'function') {
    fail('InvalidCompletedEffectDependencyOwner');
  }
  const seen = new Set();
  const adopted = dependencies.map(dependency => {
    if (!exactKeys(dependency, ['artifact', 'physical', 'prepared']) ||
        !exactKeys(dependency.physical, ['cid', 'bytes']) ||
        typeof dependency.prepared?.release !== 'function' ||
        typeof dependency.prepared?.status !== 'function' ||
        dependency.prepared.status()?.pending !== true) {
      fail('InvalidCompletedEffectDependencyPayload');
    }
    const binding = control.localEffectResultPayloadBinding(
      dependency.artifact, runDefinition);
    if (binding.physicalCid !== dependency.physical.cid ||
        binding.byteCount !== dependency.physical.bytes ||
        seen.has(binding.artifactCid)) {
      fail('InvalidCompletedEffectDependencyBinding');
    }
    seen.add(binding.artifactCid);
    return Object.freeze({artifact: dependency.artifact,
      physical: Object.freeze({...dependency.physical}),
      prepared: dependency.prepared, binding});
  });
  if (typeof dependencyInventoryWire !== 'string') {
    fail('MissingCompletedEffectDependencyInventory');
  }
  // All validation precedes ownership transfer. Failure leaves every input
  // with its caller; successful adoption uses the existing cleanup retry path.
  owner.effectDependencyPayloads = Object.freeze(adopted);
  owner.effectDependencyInventoryWire = dependencyInventoryWire;
  return Object.freeze(adopted.map(value => value.binding));
}

// Release the unpublished physical payload owners. Schema semantic objects
// have separate Store custody. Concurrent callers join one release flight;
// failed physical cleanup retains its retry handle.
export function releaseCompletedRunPreparedPayloads(storedResults, control) {
  return releaseCompletedResultOwner(storedResults, control, false);
}

// Relinquish only process-local payload custody after a durable continuation
// has been recorded. The exact captured computation remains recoverable in
// the Store; this is neither final publication nor retirement. A later Host
// recovers a new owner from that capture before applying or retiring it.
export async function suspendCompletedEffectfulComputation({
  execution, store, storedResults, control, computation, preview,
}) {
  const issued = completedEffectfulOwners.get(computation);
  if (issued === undefined || issued.execution !== execution ||
      issued.store !== store || issued.storedResults !== storedResults ||
      issued.control !== control || issued.preview !== preview) {
    fail('InvalidCompletedEffectfulRunOwner');
  }
  await confirmCompletedEffectfulApplySources({store, control,
    computation, preview});
  return releaseCompletedResultOwner(storedResults, control, true);
}

function releaseCompletedResultOwner(storedResults, control, retainCapture) {
  const owner = completedResultOwners.get(storedResults);
  if (owner === undefined || owner.control !== control) {
    fail('InvalidCompletedRunResultSetOwner');
  }
  if (owner.retainCapture !== undefined &&
      owner.retainCapture !== retainCapture) {
    fail('CompletedRunResultSetReleaseModeConflict');
  }
  owner.retainCapture = retainCapture;
  if (owner.releaseComplete) return Promise.resolve(false);
  if (owner.releaseFlight !== undefined) return owner.releaseFlight;
  let flight;
  flight = (async () => {
    if (owner.cleanupFailure !== undefined) {
      const status = await owner.cleanupFailure.cleanupHandle.retry();
      if (status.pending) throw owner.cleanupFailure;
    } else {
      const released = new Error('CompletedRunResultSetReleased');
      try {
        await releasePreparedResults([...storedResults.results,
          ...(owner.effectDependencyPayloads ?? [])], released, control);
      } catch (error) {
        if (error !== released) {
          if (error.cleanupPending === true) owner.cleanupFailure = error;
          throw error;
        }
      }
    }
    if (owner.privateEffectOwner !== undefined &&
        !owner.capturePublished && !retainCapture) {
      await owner.privateEffectOwner.abort();
      const retired = await owner.store.retirePhysicalHolding(
        owner.privateEffectOwner.binding.holdingCid,
      );
      if (retired.cleanup.status().pending) {
        const error = new CompletedRunPublicationError(
          'CompletedEffectPrivateCleanupPending',
        );
        error.cleanupPending = true;
        error.cleanupHandle = retired.cleanup;
        owner.cleanupFailure = error;
        throw error;
      }
    }
    if (owner.captureRecordOwner !== undefined &&
        !owner.capturePublished && !retainCapture) {
      try { await owner.captureRecordOwner.abort(); }
      catch (error) {
        error.cleanupPending = true;
        error.cleanupHandle = owner.captureRecordOwner;
        throw error;
      }
      const retired = await owner.store.retirePhysicalHolding(
        owner.captureRecordOwner.binding.holdingCid,
      );
      if (retired.cleanup.status().pending) {
        const error = new CompletedRunPublicationError(
          'CompletedRunCaptureRecordCleanupPending',
        );
        error.cleanupPending = true;
        error.cleanupHandle = retired.cleanup;
        owner.cleanupFailure = error;
        throw error;
      }
    }
    if (owner.captureHolding !== undefined && !owner.capturePublished &&
        !retainCapture) {
      const retired = await owner.store.retirePhysicalHolding(
        owner.captureHolding.holding_cid,
      );
      if (retired.cleanup.status().pending) {
        const error = new CompletedRunPublicationError(
          'CompletedRunCaptureCleanupPending',
        );
        error.cleanupPending = true;
        error.cleanupHandle = retired.cleanup;
        owner.cleanupFailure = error;
        throw error;
      }
    }
    // A committed publication's metadata inventory still owns these source
    // holdings. Only an unpublished terminal capture may retire them.
    if (!retainCapture && !owner.capturePublished) {
      for (const holdingCid of owner.effectSourceHoldingCids ?? []) {
        const retired = await owner.store.retirePhysicalHolding(holdingCid);
        if (retired.cleanup.status().pending) {
          const error = new CompletedRunPublicationError(
            'CompletedEffectSourceCleanupPending',
          );
          error.cleanupPending = true;
          error.cleanupHandle = retired.cleanup;
          owner.cleanupFailure = error;
          throw error;
        }
      }
      await owner.store.retireEffectCaptureCustody(owner.runDefinition);
    }
    owner.releaseComplete = true;
    return true;
  })().finally(() => {
    if (owner.releaseFlight === flight) owner.releaseFlight = undefined;
  });
  owner.releaseFlight = flight;
  return flight;
}

// Bind an already retained Effectful computation to its exact private
// Preview. The prepared Store owners remain with the caller until the final
// publication commit or an explicit release; issuing evidence is not commit.
export async function issueCompletedEffectfulComputationEvidence(options) {
  if (!exactKeys(options, [
    'execution', 'store', 'storedResults', 'control', 'admission', 'runDefinition',
    'invocation', 'observation', 'normalizationJournal', 'authoringContext',
    'receiptEvidence', 'captureEvidence', 'preview', 'plans',
    'effectSourceHoldings', 'connectorRecovery',
    'contractLimits',
  ])) fail('InvalidCompletedEffectfulComputationOptions');
  const {
    execution, store, storedResults, control, admission, runDefinition,
    invocation, observation, normalizationJournal, authoringContext,
    receiptEvidence, captureEvidence, preview, plans, effectSourceHoldings,
    connectorRecovery,
    contractLimits,
  } = options;
  validateExecution(execution);
  const owner = completedResultOwners.get(storedResults);
  if (owner?.execution !== execution || owner.control !== control ||
      owner.releaseComplete || owner.releaseFlight !== undefined ||
      owner.cleanupFailure !== undefined ||
      !exactKeys(storedResults, ['results', 'definitions', 'artifacts']) ||
      !Array.isArray(storedResults.results) ||
      storedResults.results.length !== execution.resultInventory.length ||
      !Array.isArray(storedResults.definitions) ||
      !Array.isArray(storedResults.artifacts) ||
      !Array.isArray(plans) ||
      !Array.isArray(effectSourceHoldings) ||
      !Array.isArray(connectorRecovery) ||
      typeof store?.commitPhysicalHolding !== 'function' ||
      typeof store.storeAuthorityCid !== 'string' ||
      !['capturedEffectSourceHoldingCid',
        'capturedEffectSourceArtifactCid',
        'capturedEffectSourceStoreAuthorityCid',
        'effectComputationCaptureHoldingCid',
        'effectComputationRecordHoldingCid',
        'effectPrivateEvidenceBinding'].every(name =>
        typeof control?.[name] === 'function') ||
      !exactKeys(receiptEvidence, [
        'bindings', 'sourceEvidence', 'modelEvidence',
        'barrierAttemptReceiptCids',
      ]) ||
      !exactKeys(captureEvidence, [
        'pendingSourceStateAdvances', 'modelEvidence',
      ]) ||
      !['issueResultManifest', 'issueEffectFreeRunReceipt',
        'issueEffectfulCapturedRun'].every(name =>
        typeof control?.[name] === 'function')) {
    fail('InvalidCompletedEffectfulComputationOptions');
  }
  const ownedHoldings = effectSourceHoldings.map(holding => {
    if (!contract(holding?.artifact) ||
        holding.artifact.name !== 'effect_source_artifact' ||
        !Number.isSafeInteger(holding.memberIndex) ||
        holding.memberIndex < 0 ||
        holding.localEvidence?.kind !== 'captured-local-effect-source' ||
        !holding.record || !Array.isArray(holding.record.objects)) {
      fail('InvalidCompletedEffectSourceHolding');
    }
    return Object.freeze({
      source: holding.source,
      memberIndex: holding.memberIndex,
      localEvidence: holding.localEvidence,
      artifact: ownContract(control, holding.artifact, contractLimits,
        'InvalidCompletedEffectSourceHolding'),
      record: Object.freeze({...holding.record,
        objects: Object.freeze(holding.record.objects.map(object =>
          Object.freeze({...object})))}),
    });
  });
  const ownedMemberIndices = new Set(ownedHoldings.map(
    holding => holding.memberIndex));
  const seenRecoveryMembers = new Set();
  const ownedConnectorRecovery = connectorRecovery.map(entry => {
    if (!exactKeys(entry, [
      'memberIndex', 'kind', 'observationCid', 'wire',
    ]) || !Number.isSafeInteger(entry.memberIndex) ||
        entry.memberIndex < 0 ||
        !ownedMemberIndices.has(entry.memberIndex) ||
        seenRecoveryMembers.has(entry.memberIndex) ||
        typeof entry.kind !== 'string' || entry.kind.length === 0 ||
        entry.kind.length > 100 ||
        typeof entry.observationCid !== 'string' ||
        !/^sha256:[0-9a-f]{64}$/u.test(entry.observationCid) ||
        typeof entry.wire !== 'string' || entry.wire.length === 0) {
      fail('InvalidCompletedEffectConnectorRecovery');
    }
    seenRecoveryMembers.add(entry.memberIndex);
    return Object.freeze({...entry});
  });
  for (const holding of ownedHoldings) {
    const source = holding.source;
    const record = holding.record;
    if (
        control.capturedEffectSourceHoldingCid(
          control.admitCapturedEffectSourceArtifact(
            preview, holding.memberIndex, invocation,
            holding.artifact, store.storeAuthorityCid,
          )) !== record.holding_cid ||
        record?.namespace !== 'effect-source' ||
        record?.holding_cid !==
          control.capturedEffectSourceHoldingCid(source) ||
        record.manifest_cid !==
          control.capturedEffectSourceArtifactCid(source) ||
        record.manifest_cid !== holding.artifact.identity ||
        control.capturedEffectSourceStoreAuthorityCid(source) !==
          store.storeAuthorityCid) {
      fail('InvalidCompletedEffectSourceHolding');
    }
  }
  const definitions = storedResults.definitions;
  const artifacts = storedResults.artifacts;
  const manifest = control.issueResultManifest(
    runDefinition, invocation, definitions, artifacts, contractLimits);
  // The pre-effect Receipt uses the shared 0.1 body without final Effect
  // references. It is not the final Effectful Run Receipt.
  const receipt = control.issueEffectFreeRunReceipt({
    admission, runDefinition, invocation, observation, definitions,
    artifacts, manifest,
  }, {normalizationJournal, ...receiptEvidence}, contractLimits);
  const capturedRun = control.issueEffectfulCapturedRun({
    runDefinition, invocation, definitions, artifacts, manifest, receipt,
  }, {
    snapshots: storedResults.results.map(value =>
      value.publication.snapshot),
    pendingSourceStateAdvances:
      captureEvidence.pendingSourceStateAdvances,
    authoringContext,
    modelEvidence: captureEvidence.modelEvidence,
    effectSources: ownedHoldings.map(value => value.source),
    localEffectSources: ownedHoldings.map(value => value.localEvidence),
    dependencyInventoryWire: owner.effectDependencyInventoryWire,
  }, preview, plans, contractLimits);
  const dependencyBindings = control.capturedEffectDependencyPayloadBindings(
    capturedRun, (owner.effectDependencyPayloads ?? []).map(value => ({
      artifact_cid: value.binding.artifactCid,
      physical_cid: value.binding.physicalCid,
      byte_count: value.binding.byteCount,
    })));
  const captureHoldingCid = control.effectComputationCaptureHoldingCid(
    runDefinition, store.storeAuthorityCid,
  );
  const objects = new Map();
  for (const result of [...storedResults.results,
    ...(owner.effectDependencyPayloads ?? []).map(value => ({
      physical: value.physical, physicalPrepared: value.prepared,
    }))]) {
    const physical = result.physical;
    if (typeof physical?.cid !== 'string' ||
        !Number.isSafeInteger(physical.bytes) || physical.bytes < 0 ||
        result.physicalPrepared?.cid !== physical.cid) {
      fail('InvalidCompletedEffectfulCaptureOwner');
    }
    const previous = objects.get(physical.cid);
    if (previous !== undefined && previous.physical.bytes !== physical.bytes) {
      fail('InvalidCompletedEffectfulCaptureOwner');
    }
    if (previous === undefined) objects.set(physical.cid, result);
  }
  const captureHolding = Object.freeze({
    version: 'actql-local-physical-holding/0.1',
    namespace: 'effect-capture',
    holding_cid: captureHoldingCid,
    manifest_cid: capturedRun.identity,
    objects: Object.freeze([...objects.values()].map(result => Object.freeze({
      cid: result.physical.cid, byte_count: result.physical.bytes,
    }))),
  });
  const previewBinding = control.effectPrivateEvidenceBinding(
    preview, store.storeAuthorityCid,
  );
  const captureRecordWire = JSON.stringify({
    version: 'actql-completed-effectful-capture/0.1',
    store_authority_cid: store.storeAuthorityCid,
    run_definition: runDefinition.wire,
    invocation: invocation.wire,
    definitions: definitions.map(value => value.wire),
    artifacts: artifacts.map(value => value.wire),
    derivations: storedResults.results.map(value =>
      value.publication.derivation.wire),
    orderings: storedResults.results.map(value =>
      value.publication.ordering.wire),
    retentions: uniqueContracts(owner.retentions).map(value => value.wire),
    durable_bindings: storedResults.results.map(value =>
      value.publication.durableBinding.wire),
    result_schemas: storedResults.results.map(value => Object.freeze({
      cid: value.schema.semanticCid,
      wire: value.orderedRows.resultSchemaWire,
    })),
    manifest: manifest.wire,
    computation_receipt: receipt.wire,
    captured_run: capturedRun.wire,
    effect_dependency_payloads: dependencyBindings,
    preview: previewBinding.wire,
    authoring_context: authoringContext.wire,
    effect_source_artifacts: ownedHoldings.map(value => Object.freeze({
      member_index: value.memberIndex, artifact: value.artifact.wire,
    })),
    connector_recovery: ownedConnectorRecovery.map(value => Object.freeze({
      member_index: value.memberIndex, kind: value.kind,
      observation_cid: value.observationCid, wire: value.wire,
    })),
  });
  if (owner.captureRecordOwner !== undefined &&
      owner.captureRecordWire !== captureRecordWire) {
    fail('CompletedEffectfulCaptureConflict');
  }
  // Admit the complete inventory and serialize the capture before yielding.
  // Caller-owned plans and evidence cannot change while Store sync is pending.
  // A later invalid member must not leave earlier members partially synced.
  const commitHolding = store.commitPhysicalHolding.bind(store);
  const prepared = [...objects.values()].map(result => result.physicalPrepared);
  const sourceHoldingCids = ownedHoldings.map(holding =>
    holding.record.holding_cid);
  // Retain responsibility before any fallible Store operation, including a
  // lost acknowledgement. Retry reconciles these exact records without export.
  owner.captureHolding = captureHolding;
  owner.effectSourceHoldingCids = Object.freeze([...sourceHoldingCids]);
  await store.retainEffectCaptureCustody(runDefinition,
    [...ownedHoldings.map(holding => holding.record), captureHolding]);
  for (const holding of ownedHoldings) {
    await commitHolding(holding.record, []);
  }
  await commitHolding(captureHolding, prepared, sourceHoldingCids);
  // A source sync can fail before the private writer exists. Do not retain
  // that connection in a new private owner until the capture holding commits.
  if (owner.captureRecordOwner === undefined) {
    owner.captureRecordWire = captureRecordWire;
    owner.captureRecordOwner = preparePrivatePublicationHolding(store,
      Object.freeze({
        name: 'effect_capture', semanticCid: capturedRun.identity,
        holdingCid: control.effectComputationRecordHoldingCid(
          runDefinition, store.storeAuthorityCid,
        ),
        wire: captureRecordWire,
      }));
  } else if (owner.captureRecordWire !== captureRecordWire) {
    fail('CompletedEffectfulCaptureConflict');
  }
  await owner.captureRecordOwner.commit();
  const issued = Object.freeze({manifest, computationReceipt: receipt,
    capturedRun});
  completedEffectfulOwners.set(issued, Object.freeze({
    execution, store, storedResults, control, preview,
    runDefinition, invocation, captureHolding,
    effectSourceHoldings: Object.freeze(ownedHoldings.map(value =>
      Object.freeze({source: value.source, artifact: value.artifact}))),
  }));
  return issued;
}

// Retire a terminal, unpublished Effect capture from its durable private
// record. The record is deleted last: after a crash, the remaining exact
// holdings can still be derived without re-running Compute or an Effect.
export async function retireCompletedEffectfulCapture({store, control,
  runDefinition, contractLimits}) {
  if (!contract(runDefinition) ||
      typeof store?.storeAuthorityCid !== 'string' ||
      !['inspectPhysicalHolding', 'inspectPhysicalHoldingForRetirement',
        'readPrivateEvidence',
        'retirePhysicalHolding'].every(name =>
        typeof store?.[name] === 'function')) {
    fail('InvalidCompletedEffectfulRetirement');
  }
  const run = ownContract(control, runDefinition, contractLimits);
  const recordCid = control.effectComputationRecordHoldingCid(run,
    store.storeAuthorityCid);
  const captureCid = control.effectComputationCaptureHoldingCid(run,
    store.storeAuthorityCid);
  const record = await store.inspectPhysicalHolding(recordCid);
  if (record === undefined) {
    if (await store.retireEffectCaptureCustody(run)) return true;
    if (await store.inspectPhysicalHolding(captureCid) !== undefined) {
      fail('CompletedEffectfulCaptureRecordMissing');
    }
    return false;
  }
  if (record.namespace !== 'publication-private' ||
      record.objects.length !== 1) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  let body;
  try {
    body = JSON.parse((await store.readPrivateEvidence('effect_capture',
      record.manifest_cid, recordCid)).toString('utf8'));
  } catch (error) {
    fail('InvalidCompletedEffectfulCaptureRecord', error);
  }
  if (!exactKeys(body, [
    'version', 'store_authority_cid', 'run_definition', 'invocation',
    'definitions', 'artifacts', 'derivations', 'orderings', 'retentions',
    'durable_bindings', 'result_schemas', 'manifest',
    'computation_receipt', 'captured_run', 'preview',
    'authoring_context', 'effect_source_artifacts', 'connector_recovery',
    'effect_dependency_payloads',
  ]) || body.version !== 'actql-completed-effectful-capture/0.1' ||
      body.store_authority_cid !== store.storeAuthorityCid ||
      body.run_definition !== run.wire ||
      !Array.isArray(body.effect_source_artifacts) ||
      !Array.isArray(body.definitions) ||
      !Array.isArray(body.artifacts)) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  const admit = (name, wire) => control.admit(name, wire, contractLimits);
  const chain = {
    runDefinition: run,
    invocation: admit('run_invocation', body.invocation),
    definitions: body.definitions.map(wire =>
      admit('result_definition', wire)),
    artifacts: body.artifacts.map(wire => admit('result_artifact', wire)),
    manifest: admit('result_manifest', body.manifest),
    computationReceipt: admit('run_receipt', body.computation_receipt),
    capturedRun: admit('captured_run', body.captured_run),
  };
  const preview = control.admitEffectComputationPreview(body.preview, run,
    control.admitRunEvidence('authoring_context', body.authoring_context,
      contractLimits), contractLimits);
  const previewBinding = control.effectPrivateEvidenceBinding(preview,
    store.storeAuthorityCid);
  if (chain.capturedRun.identity !== record.manifest_cid ||
      !control.effectfulComputationEvidenceChainValid(chain, preview,
        contractLimits)) {
    fail('InvalidCompletedEffectfulCaptureChain');
  }
  const sources = body.effect_source_artifacts.map(item => {
    if (!exactKeys(item, ['member_index', 'artifact']) ||
        !Number.isSafeInteger(item.member_index) || item.member_index < 0) {
      fail('InvalidCompletedEffectfulCaptureSource');
    }
    return Object.freeze({memberIndex: item.member_index,
      artifact: admit('effect_source_artifact', item.artifact)});
  });
  if (!control.capturedEffectSourceRecoveryInventoryValid(preview,
    sources)) {
    fail('InvalidCompletedEffectfulCaptureSource');
  }
  const sourceCids = sources.map(({memberIndex, artifact}) => {
    const source = control.admitCapturedEffectSourceArtifact(preview,
      memberIndex, chain.invocation, artifact, store.storeAuthorityCid);
    return control.capturedEffectSourceHoldingCid(source);
  });
  // Validate every remaining record before starting deletion. Missing
  // records are allowed only as progress from an earlier retirement pass.
  for (const [index, holdingCid] of sourceCids.entries()) {
    const holding = await store.inspectPhysicalHoldingForRetirement(holdingCid);
    if (holding !== undefined &&
        (holding.namespace !== 'effect-source' ||
         holding.manifest_cid !== sources[index].artifact.identity)) {
      fail('InvalidCompletedEffectfulCaptureSource');
    }
  }
  const capture = await store.inspectPhysicalHoldingForRetirement(captureCid);
  const expectedObjects = new Map();
  if (!Array.isArray(body.durable_bindings)) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  for (const wire of body.durable_bindings) {
    const binding = JSON.parse(admit('durable_result_binding', wire).wire);
    if (binding.store_authority_cid !== store.storeAuthorityCid ||
        expectedObjects.has(binding.material_generation_cid) &&
          expectedObjects.get(binding.material_generation_cid) !==
            binding.byte_count) {
      fail('InvalidCompletedEffectfulCaptureBinding');
    }
    expectedObjects.set(binding.material_generation_cid,
      binding.byte_count);
  }
  for (const binding of control.capturedEffectDependencyPayloadBindings(
    chain.capturedRun, body.effect_dependency_payloads)) {
    const previous = expectedObjects.get(binding.physical_cid);
    if (previous !== undefined && previous !== binding.byte_count) {
      fail('InvalidCompletedEffectfulCaptureBinding');
    }
    expectedObjects.set(binding.physical_cid, binding.byte_count);
  }
  if (capture !== undefined &&
      (capture.namespace !== 'effect-capture' ||
       capture.manifest_cid !== chain.capturedRun.identity ||
       capture.objects.length !== expectedObjects.size ||
       capture.objects.some(object =>
         expectedObjects.get(object.cid) !== object.byte_count))) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  const previewHolding = await store.inspectPhysicalHolding(
    previewBinding.holdingCid);
  if (previewHolding !== undefined &&
      (previewHolding.namespace !== 'publication-private' ||
       previewHolding.manifest_cid !== previewBinding.semanticCid)) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  for (const holdingCid of [...sourceCids, captureCid,
    previewBinding.holdingCid, recordCid]) {
    const retired = await store.retirePhysicalHolding(holdingCid);
    if (retired.cleanup.status().pending) {
      const error = new CompletedRunPublicationError(
        'CompletedEffectfulCaptureCleanupPending');
      error.cleanupPending = true;
      error.cleanupHandle = retired.cleanup;
      throw error;
    }
  }
  await store.forgetEffectCaptureCustody(run);
  return true;
}

// Recover a completed computation without re-running its physical work. The
// encrypted capture record is only a source of bytes; MoonBit re-admits and
// validates the exact computation chain before any owner is reconstructed.
export async function recoverCompletedEffectfulComputation(options) {
  if (!exactKeys(options, [
    'store', 'control', 'runDefinition', 'contractLimits',
  ])) fail('InvalidCompletedEffectfulRecoveryOptions');
  const {store, control, runDefinition, contractLimits} = options;
  if (!contract(runDefinition) ||
      typeof store?.storeAuthorityCid !== 'string' ||
      !['inspectPhysicalHolding', 'readPrivateEvidence',
        'confirmPrivateEvidence', 'putPreparedResultSchema']
        .every(name => typeof store?.[name] === 'function') ||
      !['admit', 'admitRunEvidence', 'admitEffectComputationPreview',
        'admitCapturedEffectSourceArtifact',
        'capturedEffectSourceHoldingCid',
        'capturedEffectSourceArtifactCid',
        'effectComputationCaptureHoldingCid',
        'effectComputationRecordHoldingCid',
        'effectfulComputationEvidenceChainValid',
        'capturedEffectSourceRecoveryInventoryValid']
        .every(name => typeof control?.[name] === 'function')) {
    fail('InvalidCompletedEffectfulRecoveryOptions');
  }
  const admittedRun = ownContract(control, runDefinition, contractLimits);
  const captureHoldingCid = control.effectComputationCaptureHoldingCid(
    admittedRun, store.storeAuthorityCid);
  const recordHoldingCid = control.effectComputationRecordHoldingCid(
    admittedRun, store.storeAuthorityCid);
  const record = await store.inspectPhysicalHolding(recordHoldingCid);
  if (record === undefined) {
    if (await store.inspectPhysicalHolding(captureHoldingCid) !== undefined) {
      fail('CompletedEffectfulCaptureRecordMissing');
    }
    fail('CompletedEffectfulCaptureUnavailable');
  }
  if (record.namespace !== 'publication-private' ||
      record.objects.length !== 1) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  let captured;
  let captureRecordWire;
  try {
    captureRecordWire = (await store.readPrivateEvidence(
      'effect_capture', record.manifest_cid, recordHoldingCid,
    )).toString('utf8');
    captured = JSON.parse(captureRecordWire);
  } catch (error) {
    fail('InvalidCompletedEffectfulCaptureRecord', error);
  }
  if (!exactKeys(captured, [
    'version', 'store_authority_cid', 'run_definition', 'invocation',
    'definitions', 'artifacts', 'derivations', 'orderings', 'retentions',
    'durable_bindings', 'result_schemas', 'manifest',
    'computation_receipt', 'captured_run', 'preview',
    'authoring_context', 'effect_source_artifacts', 'connector_recovery',
    'effect_dependency_payloads',
  ]) || captured.version !== 'actql-completed-effectful-capture/0.1' ||
      captured.store_authority_cid !== store.storeAuthorityCid ||
      captured.run_definition !== admittedRun.wire ||
      !['definitions', 'artifacts', 'derivations', 'orderings',
        'retentions', 'durable_bindings', 'result_schemas',
        'effect_source_artifacts', 'connector_recovery']
        .every(name => Array.isArray(captured[name]))) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  const admit = (name, wire) => control.admit(name, wire, contractLimits);
  const definitions = captured.definitions.map(wire =>
    admit('result_definition', wire));
  const artifacts = captured.artifacts.map(wire =>
    admit('result_artifact', wire));
  const derivations = captured.derivations.map(wire =>
    admit('derivation_evidence', wire));
  const orderings = captured.orderings.map(wire =>
    admit('ordering_evidence', wire));
  const retentions = captured.retentions.map(wire =>
    admit('result_retention_policy', wire));
  const durableBindings = captured.durable_bindings.map(wire =>
    admit('durable_result_binding', wire));
  const count = definitions.length;
  if (count === 0 || [artifacts, derivations, orderings, durableBindings,
    captured.result_schemas].some(values => values.length !== count)) {
    fail('InvalidCompletedEffectfulCaptureInventory');
  }
  const invocation = admit('run_invocation', captured.invocation);
  const manifest = admit('result_manifest', captured.manifest);
  const computationReceipt = admit('run_receipt',
    captured.computation_receipt);
  const capturedRun = admit('captured_run', captured.captured_run);
  if (capturedRun.identity !== record.manifest_cid) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  const authoringContext = control.admitRunEvidence('authoring_context',
    captured.authoring_context, contractLimits);
  const preview = control.admitEffectComputationPreview(
    captured.preview, admittedRun, authoringContext, contractLimits);
  if (!control.effectfulComputationEvidenceChainValid({
    runDefinition: admittedRun, invocation, definitions, artifacts,
    manifest, computationReceipt, capturedRun,
  }, preview, contractLimits)) {
    fail('InvalidCompletedEffectfulCaptureChain');
  }
  const sourceInventory = captured.effect_source_artifacts.map(item => {
    if (!exactKeys(item, ['member_index', 'artifact']) ||
        !Number.isSafeInteger(item.member_index) || item.member_index < 0) {
      fail('InvalidCompletedEffectfulCaptureSource');
    }
    return Object.freeze({memberIndex: item.member_index,
      artifact: admit('effect_source_artifact', item.artifact)});
  });
  const sourceMemberIndices = new Set(sourceInventory.map(
    source => source.memberIndex));
  const seenConnectorMembers = new Set();
  const connectorRecovery = captured.connector_recovery.map(item => {
    if (!exactKeys(item, [
      'member_index', 'kind', 'observation_cid', 'wire',
    ]) || !Number.isSafeInteger(item.member_index) ||
        item.member_index < 0 ||
        !sourceMemberIndices.has(item.member_index) ||
        seenConnectorMembers.has(item.member_index) ||
        typeof item.kind !== 'string' || item.kind.length === 0 ||
        item.kind.length > 100 ||
        typeof item.observation_cid !== 'string' ||
        !/^sha256:[0-9a-f]{64}$/u.test(item.observation_cid) ||
        typeof item.wire !== 'string' || item.wire.length === 0) {
      fail('InvalidCompletedEffectConnectorRecovery');
    }
    seenConnectorMembers.add(item.member_index);
    return Object.freeze({memberIndex: item.member_index,
      kind: item.kind, observationCid: item.observation_cid,
      wire: item.wire});
  });
  if (!control.capturedEffectSourceRecoveryInventoryValid(
    preview, sourceInventory)) {
    fail('InvalidCompletedEffectfulCaptureSource');
  }
  const sourceHoldings = [];
  for (const {memberIndex, artifact} of sourceInventory) {
    const source = control.admitCapturedEffectSourceArtifact(
      preview, memberIndex, invocation, artifact,
      store.storeAuthorityCid,
    );
    const holdingCid = control.capturedEffectSourceHoldingCid(source);
    const holding = await store.inspectPhysicalHolding(holdingCid);
    if (holding?.namespace !== 'effect-source' ||
        holding.manifest_cid !== artifact.identity ||
        control.capturedEffectSourceArtifactCid(source) !==
          artifact.identity) {
      fail('CompletedEffectfulCaptureSourceUnavailable');
    }
    await store.commitPhysicalHolding(holding, []);
    sourceHoldings.push(Object.freeze({source, artifact}));
  }
  const captureHolding = await store.inspectPhysicalHolding(
    captureHoldingCid);
  const expected = new Map();
  for (const binding of durableBindings) {
    const body = JSON.parse(binding.wire);
    if (body.store_authority_cid !== store.storeAuthorityCid ||
        (expected.has(body.material_generation_cid) &&
          expected.get(body.material_generation_cid) !== body.byte_count)) {
      fail('InvalidCompletedEffectfulCaptureBinding');
    }
    expected.set(body.material_generation_cid, body.byte_count);
  }
  for (const binding of control.capturedEffectDependencyPayloadBindings(
    capturedRun, captured.effect_dependency_payloads)) {
    const previous = expected.get(binding.physical_cid);
    if (previous !== undefined && previous !== binding.byte_count) {
      fail('InvalidCompletedEffectfulCaptureBinding');
    }
    expected.set(binding.physical_cid, binding.byte_count);
  }
  if (captureHolding?.namespace !== 'effect-capture' ||
      captureHolding.manifest_cid !== capturedRun.identity ||
      captureHolding.objects.length !== expected.size ||
      captureHolding.objects.some(object =>
        expected.get(object.cid) !== object.byte_count)) {
    fail('CompletedEffectfulCaptureUnavailable');
  }
  await store.commitPhysicalHolding(captureHolding, []);
  const recordBinding = Object.freeze({
    name: 'effect_capture', semanticCid: capturedRun.identity,
    holdingCid: recordHoldingCid, wire: captureRecordWire,
  });
  if (await store.confirmPrivateEvidence(recordBinding) === undefined) {
    fail('CompletedEffectfulCaptureRecordUnavailable');
  }
  const preparedSchemas = [];
  try {
    for (let index = 0; index < count; index++) {
      const schema = captured.result_schemas[index];
      const binding = JSON.parse(durableBindings[index].wire);
      if (!exactKeys(schema, ['cid', 'wire']) ||
          schema.cid !== binding.result_schema_cid) {
        fail('InvalidCompletedEffectfulCaptureSchema');
      }
      preparedSchemas.push(await store.putPreparedResultSchema(
        schema.wire, schema.cid, admittedRun.identity,
      ));
    }
  } catch (error) {
    for (const schema of preparedSchemas) {
      try { await schema.prepared.release(); }
      catch { /* The Store retains failed prepared-schema cleanup. */ }
    }
    throw error;
  }
  const storedResults = Object.freeze({
    results: Object.freeze(definitions.map((definition, index) =>
      Object.freeze({
        publication: Object.freeze({artifact: artifacts[index],
          derivation: derivations[index], ordering: orderings[index],
          durableBinding: durableBindings[index]}),
        prepared: preparedSchemas[index].prepared,
      }))),
    definitions: Object.freeze(definitions),
    artifacts: Object.freeze(artifacts),
  });
  const computation = Object.freeze({manifest, computationReceipt,
    capturedRun});
  const captureRecordOwner = preparePrivatePublicationHolding(store,
    recordBinding);
  completedResultOwners.set(storedResults, {
    execution: null, store, control, runDefinition: admittedRun,
    retentions: Object.freeze(retentions),
    releaseComplete: false, releaseFlight: undefined,
    cleanupFailure: undefined, captureHolding, captureRecordOwner,
    captureRecordWire: recordBinding.wire, capturePublished: false,
    effectSourceHoldingCids: Object.freeze(sourceHoldings.map(({source}) =>
      control.capturedEffectSourceHoldingCid(source))),
  });
  completedEffectfulOwners.set(computation, Object.freeze({
    execution: null, store, storedResults, control, preview,
    runDefinition: admittedRun, invocation, captureHolding,
    effectSourceHoldings: Object.freeze(sourceHoldings),
  }));
  return Object.freeze({execution: null, storedResults, computation,
    preview, connectorRecovery: Object.freeze(connectorRecovery)});
}

// Derive the only final-chain inventory from the same completed Compute and
// Effect-source owners used at capture. This is not apply or publication.
export function prepareCompletedEffectfulPublication(options) {
  if (!exactKeys(options, [
    'execution', 'store', 'storedResults', 'control', 'computation',
    'preview',
  ])) fail('InvalidCompletedEffectfulRunOptions');
  const {execution, store, storedResults, control, computation, preview,
  } = options;
  const issued = completedEffectfulOwners.get(computation);
  const resultOwner = completedResultOwners.get(storedResults);
  if (issued?.execution !== execution || issued.store !== store ||
      issued.storedResults !== storedResults || issued.control !== control ||
      issued.preview !== preview || resultOwner?.execution !== execution ||
      resultOwner.control !== control || resultOwner.releaseComplete ||
      resultOwner.releaseFlight !== undefined ||
      resultOwner.cleanupFailure !== undefined) {
    fail('InvalidCompletedEffectfulRunOwner');
  }
  const chain = Object.freeze({
    runDefinition: issued.runDefinition,
    invocation: issued.invocation,
    definitions: storedResults.definitions,
    artifacts: storedResults.artifacts,
    derivations: Object.freeze(storedResults.results.map(
      value => value.publication.derivation)),
    orderings: Object.freeze(storedResults.results.map(
      value => value.publication.ordering)),
    retentions: Object.freeze(uniqueContracts(resultOwner.retentions)),
    durableBindings: Object.freeze(storedResults.results.map(
      value => value.publication.durableBinding)),
    manifest: computation.manifest,
    computationReceipt: computation.computationReceipt,
    capturedRun: computation.capturedRun,
  });
  return Object.freeze({chain, preview,
    effectSources: Object.freeze(issued.effectSourceHoldings.map(
      value => value.source)),
    sourceArtifacts: Object.freeze(issued.effectSourceHoldings.map(
      value => value.artifact)),
  });
}

// A recovered Preview remains historical evidence until its exact physical
// source holdings and capture record are confirmed at the send boundary.
// This does not authenticate a current Site grant or admit an Effect apply.
export async function confirmCompletedEffectfulApplySources({
  store, control, computation, preview,
}) {
  const issued = completedEffectfulOwners.get(computation);
  if (issued?.store !== store || issued.control !== control ||
      issued.preview !== preview ||
      typeof store?.inspectPhysicalHolding !== 'function' ||
      typeof store?.commitPhysicalHolding !== 'function' ||
      typeof store?.confirmPrivateEvidence !== 'function') {
    fail('InvalidCompletedEffectfulApplyOwner');
  }
  const capture = await store.inspectPhysicalHolding(
    issued.captureHolding.holding_cid);
  if (JSON.stringify(capture) !==
      JSON.stringify(issued.captureHolding)) {
    fail('CompletedEffectfulCaptureUnavailable');
  }
  const record = completedResultOwners.get(issued.storedResults)
    ?.captureRecordOwner;
  if (record === undefined ||
      await store.confirmPrivateEvidence(record.binding) === undefined) {
    fail('CompletedEffectfulCaptureRecordUnavailable');
  }
  for (const {source, artifact} of issued.effectSourceHoldings) {
    const holdingCid = control.capturedEffectSourceHoldingCid(source);
    const holding = await store.inspectPhysicalHolding(holdingCid);
    if (holding?.namespace !== 'effect-source' ||
        holding.holding_cid !== holdingCid ||
        holding.manifest_cid !== artifact.identity ||
        control.capturedEffectSourceArtifactCid(source) !==
          artifact.identity ||
        control.capturedEffectSourceStoreAuthorityCid(source) !==
          store.storeAuthorityCid) {
      fail('CompletedEffectfulCaptureSourceUnavailable');
    }
    await store.commitPhysicalHolding(holding, []);
  }
  return control.effectComputationPreviewLedgerIdentity(preview);
}

// The standard completion owner invokes this immediately before handing a
// row to physical dispatch. Waiting Checkpoints protect their saved inventory
// without removing it, until resume or terminal retirement takes custody.
// Preparing a complete private record alone is not that custody transfer.
// This removes cleanup eligibility; it grants no mutation authority.
export async function transferCompletedEffectfulCaptureCustody({
  store, control, computation, preview,
}) {
  const issued = completedEffectfulOwners.get(computation);
  if (issued?.store !== store || issued.control !== control ||
      issued.preview !== preview) fail('InvalidCompletedEffectfulApplyOwner');
  await store.forgetEffectCaptureCustody(issued.runDefinition);
}

// Publish only from the retained completed owner and an issued physical
// Effect set. A failed or uncertain commit leaves every owner available for
// reconciliation; a repeated call never re-runs Compute or Effect dispatch.
export async function publishCompletedEffectfulRun(options) {
  if (!exactKeys(options, [
    'execution', 'store', 'storedResults', 'control', 'computation',
    'preview', 'ledger', 'issuedSet', 'request', 'attempt',
    'contractLimits', 'now', 'signal',
  ])) fail('InvalidCompletedEffectfulRunOptions');
  const {execution, store, storedResults, control, computation, preview,
    ledger, issuedSet, request, attempt, contractLimits, now, signal} = options;
  const inventory = prepareCompletedEffectfulPublication({
    execution, store, storedResults, control, computation, preview,
  });
  const captureHolding = completedEffectfulOwners.get(computation)
    .captureHolding;
  if (typeof store.inspectPhysicalHolding !== 'function' ||
      JSON.stringify(await store.inspectPhysicalHolding(
        captureHolding.holding_cid)) !== JSON.stringify(captureHolding)) {
    fail('CompletedEffectfulCaptureUnavailable');
  }
  const captureRecord = completedResultOwners.get(storedResults)
    .captureRecordOwner;
  if (captureRecord === undefined ||
      await store.confirmPrivateEvidence(captureRecord.binding) ===
        undefined) {
    fail('CompletedEffectfulCaptureRecordUnavailable');
  }
  let privateOwner = privateEffectfulHoldings.get(computation);
  if (privateOwner === undefined) {
    const binding = control.effectPrivateEvidenceBinding(
      preview, store.storeAuthorityCid,
    );
    privateOwner = preparePrivatePublicationHolding(store, binding);
    privateEffectfulHoldings.set(computation, privateOwner);
  }
  completedResultOwners.get(storedResults).privateEffectOwner = privateOwner;
  await privateOwner.commit();
  const publication = await publishEffectfulRun({
    store, control, ...inventory, ledger, issuedSet,
    request, attempt, limits: contractLimits, now, signal,
  });
  if (publication.state === 'succeeded') {
    completedResultOwners.get(storedResults).capturePublished = true;
  }
  if (publication.idempotent) {
    await releaseCompletedRunPreparedPayloads(storedResults, control);
  }
  return Object.freeze({publication, computation, storedResults});
}

export async function publishCompletedEffectFreeRun(options) {
  validateOptions(options);
  const {
    execution,
    store,
    control,
    admission,
    runDefinition,
    invocation,
    observation,
    normalizationJournal,
    authoringContext,
    results,
    receiptEvidence,
    captureEvidence,
    request,
    attempt,
    outputLimits,
    contractLimits,
    now,
    signal,
  } = options;
  const exported = [];
  try {
    await exportCompletedRunResultSet({
      execution, store, control, runDefinition, invocation, results,
      outputLimits, contractLimits, signal,
    }, exported);
    signal?.throwIfAborted();
    const definitions = execution.publicationInventory.occurrences
      .map(value => value.definitionContract);
    const artifacts = exported.map(value => value.publication.artifact);
    const manifest = control.issueResultManifest(
      runDefinition, invocation, definitions, artifacts, contractLimits,
    );
    const receipt = control.issueEffectFreeRunReceipt({
      admission,
      runDefinition,
      invocation,
      observation,
      definitions,
      artifacts,
      manifest,
    }, {
      normalizationJournal,
      ...receiptEvidence,
    }, contractLimits);
    const capturedRun = control.issueEffectFreeCapturedRun({
      runDefinition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
    }, {
      snapshots: exported.map(value => value.publication.snapshot),
      pendingSourceStateAdvances:
        captureEvidence.pendingSourceStateAdvances,
      authoringContext,
      modelEvidence: captureEvidence.modelEvidence,
    }, contractLimits);
    const evidence = Object.freeze({
      runDefinition,
      invocation,
      definitions: Object.freeze(definitions),
      artifacts: Object.freeze(artifacts),
      derivations: Object.freeze(exported.map(
        value => value.publication.derivation,
      )),
      orderings: Object.freeze(exported.map(
        value => value.publication.ordering,
      )),
      retentions: Object.freeze(uniqueContracts(
        results.map(value => value.retention),
      )),
      durableBindings: Object.freeze(exported.map(
        value => value.publication.durableBinding,
      )),
      manifest,
      receipt,
      capturedRun,
    });
    signal?.throwIfAborted();
    const publication = await publishEffectFreeRun({
      store,
      control,
      evidence,
      request,
      attempt,
      limits: contractLimits,
      now,
      signal,
    });
    if (publication.idempotent) {
      for (const value of exported) await value.prepared?.release();
    }
    return Object.freeze({
      publication,
      evidence,
      results: Object.freeze(exported),
    });
  } catch (error) {
    await releasePreparedResults(exported, error, control);
  }
}
