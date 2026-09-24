// Complete publication of every checked Named Result retained by one finished
// Effect-free Run. MoonBit issues and validates every semantic contract. This
// coordinator only sequences bounded export and durable Store effects.
import {publishEffectFreeRun} from './run-publication.mjs';

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
const completedResultOwners = new WeakMap();

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
      execution: options.execution, control: options.control,
      releaseComplete: false, releaseFlight: undefined,
      cleanupFailure: undefined,
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
        'capturedEffectSourceStoreAuthorityCid'].every(name =>
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
  for (const holding of effectSourceHoldings) {
    const source = holding?.source;
    const record = holding?.record;
    if (record?.namespace !== 'effect-source' ||
        record?.holding_cid !==
          control.capturedEffectSourceHoldingCid(source) ||
        record.manifest_cid !==
          control.capturedEffectSourceArtifactCid(source) ||
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
    effectSources: effectSourceHoldings.map(value => value.source),
  }, preview, plans, contractLimits);
  return Object.freeze({manifest, computationReceipt: receipt, capturedRun});
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
