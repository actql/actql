// Immutable admission for publication work that is known before Compute.
// MoonBit owns contract meaning and inventory consistency. Environment Stores
// report only their current bounded physical capacity without reserving it.

import {completedPublicationCapacity} from './publication-capacity.mjs';
import {validResultOutputLimits} from './result-output-limits.mjs';

export class RunPublicationPreflightError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail = (code, cause) => {
  throw new RunPublicationPreflightError(code, cause);
};
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = value => Number.isSafeInteger(value) && value > 0;
const contract = value => value !== null && typeof value === 'object' &&
  typeof value.name === 'string' && typeof value.identity === 'string' &&
  typeof value.wire === 'string';

// Capture scalar data bags once. Accessors are not stable publication inputs:
// neither a measurement nor later issuance may invoke a different getter value.
// Nominal Common handles are retained, never reconstructed from their fields.
function ownedDataRecord(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail('InvalidRunPublicationPreflight');
  }
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const entries = [];
  for (const key of Reflect.ownKeys(descriptors)) {
    const descriptor = descriptors[key];
    if (!descriptor.enumerable) continue;
    if (!Object.hasOwn(descriptor, 'value')) fail('InvalidRunPublicationPreflight');
    entries.push([key, descriptor.value]);
  }
  return Object.freeze(Object.fromEntries(entries));
}

// Do not invoke caller-owned map, iterators, inherited indices, or accessors.
// Own dense data elements are captured once and transformed by trusted code.
function ownedDataArray(value, capture = item => item) {
  if (!Array.isArray(value)) fail('InvalidRunPublicationPreflight');
  let descriptors;
  try { descriptors = Object.getOwnPropertyDescriptors(value); }
  catch (cause) { fail('InvalidRunPublicationPreflight', cause); }
  const length = descriptors.length?.value;
  if (!Number.isSafeInteger(length) || length < 0) fail('InvalidRunPublicationPreflight');
  const result = [];
  for (let index = 0; index < length; index++) {
    const descriptor = descriptors[index];
    if (descriptor === undefined || !Object.hasOwn(descriptor, 'value')) {
      fail('InvalidRunPublicationPreflight');
    }
    Object.defineProperty(result, index, {value: capture(descriptor.value),
      enumerable: true, configurable: true, writable: true});
  }
  return Object.freeze(result);
}

function snapshotPlan(plan) {
  plan = ownedDataRecord(plan);
  const receiptEvidence = ownedDataRecord(plan.receiptEvidence);
  const captureEvidence = ownedDataRecord(plan.captureEvidence);
  const outputLimits = ownedDataRecord(plan.outputLimits);
  const contractLimits = ownedDataRecord(plan.contractLimits);
  const request = ownedDataRecord(plan.request);
  const attempt = ownedDataRecord(plan.attempt);
  const keys = [
    'admission', 'runDefinition', 'invocation', 'observation',
    'normalizationJournal', 'authoringContext', 'results',
    'receiptEvidence', 'captureEvidence', 'request', 'attempt',
    'outputLimits', 'contractLimits', 'now',
  ];
  if (!exactKeys(plan, keys) || !Array.isArray(plan.results) ||
      !exactKeys(receiptEvidence, [
        'bindings', 'sourceEvidence', 'modelEvidence',
        'barrierAttemptReceiptCids',
      ]) || !exactKeys(captureEvidence, [
        'pendingSourceStateAdvances', 'modelEvidence',
      ]) || !Array.isArray(receiptEvidence.bindings) ||
      !Array.isArray(receiptEvidence.sourceEvidence) ||
      !Array.isArray(receiptEvidence.modelEvidence) ||
      !Array.isArray(receiptEvidence.barrierAttemptReceiptCids) ||
      !Array.isArray(captureEvidence.pendingSourceStateAdvances) ||
      !Array.isArray(captureEvidence.modelEvidence) ||
      !exactKeys(contractLimits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(contractLimits).every(positive) ||
      !validResultOutputLimits(outputLimits) ||
      typeof plan.now !== 'function' || !contract(plan.runDefinition) ||
      !contract(plan.invocation)) {
    fail('InvalidRunPublicationPreflight');
  }
  const bindings = ownedDataArray(receiptEvidence.bindings, value => {
    const binding = ownedDataRecord(value);
    if (typeof binding.name !== 'string' || typeof binding.sha256 !== 'string') {
      fail('InvalidRunPublicationPreflight');
    }
    return Object.freeze({name: binding.name, sha256: binding.sha256});
  });
  const results = ownedDataArray(plan.results, original => {
    const result = ownedDataRecord(original);
    const evidenceContext = ownedDataRecord(result.evidenceContext);
    if (!exactKeys(result, ['retention', 'evidenceContext',
          ...(result?.transformation === undefined ? [] : ['transformation'])]) ||
        !contract(result.retention) || result.evidenceContext === null ||
        typeof result.evidenceContext !== 'object' ||
        Array.isArray(result.evidenceContext) ||
        !Array.isArray(evidenceContext.inputRelationCids)) {
      fail('InvalidRunPublicationPreflight');
    }
    return Object.freeze({
      retention: result.retention,
      ...(result.transformation === undefined ? {} :
        {transformation: result.transformation}),
      evidenceContext: Object.freeze({...evidenceContext,
        inputRelationCids: ownedDataArray(evidenceContext.inputRelationCids),
      }),
    });
  });
  return Object.freeze({
    admission: plan.admission,
    runDefinition: plan.runDefinition,
    invocation: plan.invocation,
    observation: plan.observation,
    normalizationJournal: plan.normalizationJournal,
    authoringContext: plan.authoringContext,
    results: Object.freeze(results),
    receiptEvidence: Object.freeze({
      bindings: Object.freeze(bindings),
      sourceEvidence: ownedDataArray(receiptEvidence.sourceEvidence),
      modelEvidence: ownedDataArray(receiptEvidence.modelEvidence),
      barrierAttemptReceiptCids: ownedDataArray(receiptEvidence.barrierAttemptReceiptCids),
    }),
    captureEvidence: Object.freeze({
      pendingSourceStateAdvances: ownedDataArray(captureEvidence.pendingSourceStateAdvances),
      modelEvidence: ownedDataArray(captureEvidence.modelEvidence),
    }),
    request,
    attempt,
    outputLimits,
    contractLimits,
    now: plan.now,
  });
}

export function prepareCompletedEffectFreeRunPublication(options) {
  options = ownedDataRecord(options);
  if (!exactKeys(options, [
    'store', 'control', 'publicationInventory', 'plan',
  ])) {
    fail('InvalidRunPublicationPreflight');
  }
  const {store, control} = options;
  const publicationInventory = ownedDataRecord(options.publicationInventory);
  const occurrences = ownedDataArray(publicationInventory.occurrences, ownedDataRecord);
  if (store === null || typeof store !== 'object' ||
      typeof store.publicationCapacitySupports !== 'function' ||
      control === null || typeof control !== 'object' ||
      !['issuePublicationRequest', 'issuePublicationAttempt',
        'publicationPreflightValid']
        .every(name => typeof control[name] === 'function') ||
      publicationInventory === null ||
      typeof publicationInventory !== 'object' ||
      !Array.isArray(publicationInventory.occurrences) ||
      occurrences.length === 0 ||
      typeof publicationInventory.programDefinitionCid !== 'string') {
    fail('InvalidRunPublicationPreflight');
  }
  const plan = snapshotPlan(options.plan);
  if (plan.results.length !== occurrences.length) {
    fail('IncompleteRunPublicationInventory');
  }
  const definitions = ownedDataArray(occurrences, occurrence => {
    if (occurrence === null || typeof occurrence !== 'object' ||
        !contract(occurrence.definitionContract)) {
      fail('InvalidRunPublicationPreflight');
    }
    return occurrence.definitionContract;
  });
  let request;
  let attempt;
  try {
    request = control.issuePublicationRequest(
      plan.runDefinition,
      definitions,
      plan.request,
      plan.contractLimits,
    );
    attempt = control.issuePublicationAttempt(
      request,
      plan.runDefinition,
      plan.attempt,
      plan.contractLimits,
    );
  } catch (error) {
    fail('InvalidRunPublicationPreflight', error);
  }
  if (control.publicationPreflightValid(
    plan.admission,
    plan.runDefinition,
    plan.invocation,
    definitions,
    plan.results.map(result => result.retention),
    plan.results.map(result => result.evidenceContext),
    request,
    attempt,
    publicationInventory.programDefinitionCid,
  ) !== true) {
    fail('IncompatibleRunPublicationPreflight');
  }
  let capacity;
  try {
    const bounds = typeof control.resultPublicationContractByteBounds === 'function'
      ? plan.results.map(result => control.resultPublicationContractByteBounds(
        result.evidenceContext.inputRelationCids,
        plan.outputLimits.maxSchemaBytes,
        plan.contractLimits,
      )) : undefined;
    let frontier = typeof control.ordinaryPublicationFrontierByteBounds === 'function'
      ? control.ordinaryPublicationFrontierByteBounds(request, plan.results.length, plan.contractLimits)
      : undefined;
    if (frontier !== undefined && typeof control.ordinaryPublicationReceiptByteBound === 'function') {
      frontier = Object.freeze({...frontier,
        receipt: control.ordinaryPublicationReceiptByteBound(plan, request, plan.contractLimits)});
    }
    capacity = completedPublicationCapacity(plan, definitions, request, attempt, bounds, frontier);
  } catch (error) {
    fail(error instanceof RangeError ? 'RunPublicationPreflightCapacityOverflow' :
      'InvalidRunPublicationPreflight', error);
  }
  if (store.publicationCapacitySupports(capacity) !== true) {
    fail('RunPublicationCapacityUnsupported');
  }
  return Object.freeze({
    plan,
    request,
    attempt,
    definitions: Object.freeze(definitions),
    capacity,
  });
}
