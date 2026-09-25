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
    if (!exactKeys(result, ['retention', 'evidenceContext']) ||
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

async function releasePreparedResults(exported, primary, control) {
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
    if (action === 0) {
      try {
        preparedPending = prepared[currentPrepared].status()?.pending !== false;
      } catch (error) {
        errors.push(error);
        preparedPending = true;
      }
      preparedStatusChecked = true;
      continue;
    }
    if (action === 1) {
      preparedReleaseAttempted = true;
      try { await prepared[currentPrepared].release(); }
      catch (error) { errors.push(error); }
      continue;
    }
    if (action === 2) {
      currentPrepared--;
      preparedStatusChecked = false;
      preparedPending = false;
      preparedReleaseAttempted = false;
      continue;
    }
    if (action === 3) break;
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
        if (action === 0) {
          ownerPending = ownerState(owners[currentOwner]).pending;
          retryAvailable = typeof member(
            owners[currentOwner].handle, 'retry',
          ) === 'function';
          ownerStatusChecked = true;
          continue;
        }
        if (action === 1) {
          retryAttempted = true;
          try { await owners[currentOwner].handle.retry(); }
          catch (error) { errors.push(error); }
          continue;
        }
        if (action === 2) {
          currentOwner++;
          ownerStatusChecked = false;
          ownerPending = false;
          retryAvailable = false;
          retryAttempted = false;
          continue;
        }
        if (action === 3) break;
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
    if (!exactKeys(result, ['retention', 'evidenceContext']) ||
        !contract(result.retention) ||
        result.evidenceContext === null ||
        typeof result.evidenceContext !== 'object') {
      fail('InvalidCompletedRunResultSet');
    }
    const stored = await execution.storePublicationResult(index, store, {
      outputLimits, contractLimits, runDefinition, invocation,
      retention: result.retention,
      evidenceContext: result.evidenceContext,
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

// Release the unpublished physical payload owners. Schema semantic objects
// have separate Store custody. Concurrent callers join one release flight;
// failed physical cleanup retains its retry handle.
export function releaseCompletedRunPreparedPayloads(storedResults, control) {
  const owner = completedResultOwners.get(storedResults);
  if (owner === undefined || owner.control !== control) {
    fail('InvalidCompletedRunResultSetOwner');
  }
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
        await releasePreparedResults(storedResults.results, released, control);
      } catch (error) {
        if (error !== released) {
          if (error.cleanupPending === true) owner.cleanupFailure = error;
          throw error;
        }
      }
    }
    if (owner.captureRecordOwner !== undefined &&
        !owner.capturePublished) {
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
    if (owner.captureHolding !== undefined && !owner.capturePublished) {
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
    'effectSourceHoldings',
    'contractLimits',
  ])) fail('InvalidCompletedEffectfulComputationOptions');
  const {
    execution, store, storedResults, control, admission, runDefinition,
    invocation, observation, normalizationJournal, authoringContext,
    receiptEvidence, captureEvidence, preview, plans, effectSourceHoldings,
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
    // An existing exact record must be re-synced, not merely visible.
    // No payload is re-exported on this reconciliation path.
    await store.commitPhysicalHolding(record, []);
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
  }, preview, plans, contractLimits);
  const captureHoldingCid = control.effectComputationCaptureHoldingCid(
    runDefinition, store.storeAuthorityCid,
  );
  const objects = new Map();
  for (const result of storedResults.results) {
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
  // Retain the owner before a fallible Store commit. A visible but unsynced
  // holding must remain addressable for reconciliation and cleanup.
  owner.captureHolding = captureHolding;
  await store.commitPhysicalHolding(captureHolding,
    [...objects.values()].map(result => result.physicalPrepared),
    ownedHoldings.map(holding => holding.record.holding_cid));
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
    preview: previewBinding.wire,
    authoring_context: authoringContext.wire,
    effect_source_artifacts: ownedHoldings.map(value => Object.freeze({
      member_index: value.memberIndex, artifact: value.artifact.wire,
    })),
  });
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
        'effectfulComputationEvidenceChainValid']
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
    'authoring_context', 'effect_source_artifacts',
  ]) || captured.version !== 'actql-completed-effectful-capture/0.1' ||
      captured.store_authority_cid !== store.storeAuthorityCid ||
      captured.run_definition !== admittedRun.wire ||
      !['definitions', 'artifacts', 'derivations', 'orderings',
        'retentions', 'durable_bindings', 'result_schemas',
        'effect_source_artifacts']
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
  const sourceHoldings = [];
  for (const item of captured.effect_source_artifacts) {
    if (!exactKeys(item, ['member_index', 'artifact']) ||
        !Number.isSafeInteger(item.member_index) || item.member_index < 0) {
      fail('InvalidCompletedEffectfulCaptureSource');
    }
    const artifact = admit('effect_source_artifact', item.artifact);
    const source = control.admitCapturedEffectSourceArtifact(
      preview, item.member_index, invocation, artifact,
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
    execution: null, store, control, retentions: Object.freeze(retentions),
    releaseComplete: false, releaseFlight: undefined,
    cleanupFailure: undefined, captureHolding, captureRecordOwner,
    captureRecordWire: recordBinding.wire, capturePublished: false,
  });
  completedEffectfulOwners.set(computation, Object.freeze({
    execution: null, store, storedResults, control, preview,
    runDefinition: admittedRun, invocation, captureHolding,
    effectSourceHoldings: Object.freeze(sourceHoldings),
  }));
  return Object.freeze({execution: null, storedResults, computation,
    preview});
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
