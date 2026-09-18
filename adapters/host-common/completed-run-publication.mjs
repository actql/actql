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
const contract = value => value !== null && typeof value === 'object' &&
  typeof value.name === 'string' && typeof value.identity === 'string' &&
  typeof value.wire === 'string';

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
        'issueEffectFreeCapturedRun']
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
  for (let index = 0; index < results.length; index++) {
    signal?.throwIfAborted();
    const stored = await execution.storePublicationResult(index, store, {
      outputLimits,
      contractLimits,
      runDefinition,
      invocation,
      retention: results[index].retention,
      evidenceContext: results[index].evidenceContext,
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
      fail('InvalidCompletedRunPublicationExport');
    }
    exported.push(stored);
  }
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
    retentions: Object.freeze(results.map(value => value.retention)),
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
  return Object.freeze({
    publication,
    evidence,
    results: Object.freeze(exported),
  });
}
