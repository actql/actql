// Immutable admission for publication work that is known before Compute.
// MoonBit owns contract meaning and inventory consistency. Environment Stores
// report only their current bounded physical capacity without reserving it.

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

function snapshotPlan(plan) {
  const keys = [
    'admission', 'runDefinition', 'invocation', 'observation',
    'normalizationJournal', 'authoringContext', 'results',
    'receiptEvidence', 'captureEvidence', 'request', 'attempt',
    'outputLimits', 'contractLimits', 'now',
  ];
  if (!exactKeys(plan, keys) || !Array.isArray(plan.results) ||
      !exactKeys(plan.receiptEvidence, [
        'bindings', 'sourceEvidence', 'modelEvidence',
        'barrierAttemptReceiptCids',
      ]) || !exactKeys(plan.captureEvidence, [
        'pendingSourceStateAdvances', 'modelEvidence',
      ]) || !Array.isArray(plan.receiptEvidence.bindings) ||
      !Array.isArray(plan.receiptEvidence.sourceEvidence) ||
      !Array.isArray(plan.receiptEvidence.modelEvidence) ||
      !Array.isArray(plan.receiptEvidence.barrierAttemptReceiptCids) ||
      !Array.isArray(plan.captureEvidence.pendingSourceStateAdvances) ||
      !Array.isArray(plan.captureEvidence.modelEvidence) ||
      !exactKeys(plan.contractLimits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(plan.contractLimits).every(positive) ||
      plan.outputLimits === null || typeof plan.outputLimits !== 'object' ||
      !positive(plan.outputLimits.maxWireBytes) ||
      typeof plan.now !== 'function' || !contract(plan.runDefinition) ||
      !contract(plan.invocation)) {
    fail('InvalidRunPublicationPreflight');
  }
  const results = plan.results.map(result => {
    if (!exactKeys(result, ['retention', 'evidenceContext']) ||
        !contract(result.retention) || result.evidenceContext === null ||
        typeof result.evidenceContext !== 'object' ||
        Array.isArray(result.evidenceContext)) {
      fail('InvalidRunPublicationPreflight');
    }
    return Object.freeze({
      retention: result.retention,
      evidenceContext: Object.freeze({...result.evidenceContext}),
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
      bindings: Object.freeze([...plan.receiptEvidence.bindings]),
      sourceEvidence: Object.freeze([...plan.receiptEvidence.sourceEvidence]),
      modelEvidence: Object.freeze([...plan.receiptEvidence.modelEvidence]),
      barrierAttemptReceiptCids: Object.freeze([
        ...plan.receiptEvidence.barrierAttemptReceiptCids,
      ]),
    }),
    captureEvidence: Object.freeze({
      pendingSourceStateAdvances: Object.freeze([
        ...plan.captureEvidence.pendingSourceStateAdvances,
      ]),
      modelEvidence: Object.freeze([...plan.captureEvidence.modelEvidence]),
    }),
    request: Object.freeze({...plan.request}),
    attempt: Object.freeze({...plan.attempt}),
    outputLimits: Object.freeze({...plan.outputLimits}),
    contractLimits: Object.freeze({...plan.contractLimits}),
    now: plan.now,
  });
}

function checkedCapacity(resultCount, outputLimits, contractLimits) {
  // One payload and one schema object per Result. Contracts include the six
  // Result-scoped objects, the Run roots, request, attempt, index and bounded
  // state records.
  const objectCount = resultCount * 8 + 11;
  const maxObjectBytes = Math.max(
    outputLimits.maxWireBytes,
    outputLimits.maxLogicalWireBytes ?? 0,
    outputLimits.maxSchemaBytes ?? 0,
    contractLimits.maxWireBytes,
  );
  const requiredBytes = objectCount * maxObjectBytes;
  if (!Number.isSafeInteger(objectCount) ||
      !Number.isSafeInteger(maxObjectBytes) ||
      !Number.isSafeInteger(requiredBytes)) {
    fail('RunPublicationPreflightCapacityOverflow');
  }
  return Object.freeze({requiredBytes, objectCount, maxObjectBytes});
}

export function prepareCompletedEffectFreeRunPublication(options) {
  if (!exactKeys(options, [
    'store', 'control', 'publicationInventory', 'plan',
  ])) {
    fail('InvalidRunPublicationPreflight');
  }
  const {store, control, publicationInventory} = options;
  if (store === null || typeof store !== 'object' ||
      typeof store.publicationCapacitySupports !== 'function' ||
      control === null || typeof control !== 'object' ||
      !['issuePublicationRequest', 'issuePublicationAttempt',
        'publicationPreflightValid']
        .every(name => typeof control[name] === 'function') ||
      publicationInventory === null ||
      typeof publicationInventory !== 'object' ||
      !Array.isArray(publicationInventory.occurrences) ||
      publicationInventory.occurrences.length === 0 ||
      typeof publicationInventory.programDefinitionCid !== 'string') {
    fail('InvalidRunPublicationPreflight');
  }
  const plan = snapshotPlan(options.plan);
  if (plan.results.length !== publicationInventory.occurrences.length) {
    fail('IncompleteRunPublicationInventory');
  }
  const definitions = publicationInventory.occurrences.map(occurrence => {
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
  const capacity = checkedCapacity(
    definitions.length,
    plan.outputLimits,
    plan.contractLimits,
  );
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
