// Immutable admission for publication work that is known before Compute.
// MoonBit owns contract meaning and inventory consistency. Environment Stores
// report only their current bounded physical capacity without reserving it.

import {completedPublicationCapacity} from './publication-capacity.mjs';
import {validResultOutputLimits} from './result-output-limits.mjs';
import type {PublicationFrontierBounds} from './publication-capacity.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type DataRecord = Readonly<Record<PropertyKey, unknown>>;
type PublicationContract = Readonly<{name: string; identity: string; wire: string}>;
type IssuedContract = PublicationContract & Extract<SynchronousRuntimeData, object>;
type ContractLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Capacity = ReturnType<typeof completedPublicationCapacity>;
type PublicationStore = Readonly<{publicationCapacitySupports(capacity: Capacity): boolean}>;
type PreflightControl = Readonly<{
  issuePublicationRequest(run: PublicationContract, definitions: readonly PublicationContract[],
    request: DataRecord, limits: ContractLimits): IssuedContract;
  issuePublicationAttempt(request: IssuedContract, run: PublicationContract,
    attempt: DataRecord, limits: ContractLimits): IssuedContract;
  publicationPreflightValid(admission: unknown, run: PublicationContract, invocation: PublicationContract,
    definitions: readonly PublicationContract[], retentions: readonly PublicationContract[],
    evidenceContexts: readonly DataRecord[], request: IssuedContract, attempt: IssuedContract,
    programDefinitionCid: string): boolean;
  resultPublicationContractByteBounds?(inputs: readonly unknown[], schemaBytes: number,
    limits: ContractLimits): readonly number[];
  ordinaryPublicationFrontierByteBounds?(request: IssuedContract, resultCount: number,
    limits: ContractLimits): PublicationFrontierBounds | undefined;
  ordinaryPublicationReceiptByteBound?(plan: ReturnType<typeof snapshotPlan>, request: IssuedContract,
    limits: ContractLimits): number;
}>;


export class RunPublicationPreflightError extends Error {
  declare code: string;
  declare primaryFailure: unknown;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw new RunPublicationPreflightError(code, cause);
};
const exactKeys = (value: unknown, keys: readonly string[]) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = (value: unknown) => Number.isSafeInteger(value) && (value as number) > 0;
const contract = (value: unknown): value is PublicationContract => value !== null && typeof value === 'object' &&
  typeof (value as PublicationContract).name === 'string' && typeof (value as PublicationContract).identity === 'string' &&
  typeof (value as PublicationContract).wire === 'string';

// Capture scalar data bags once. Accessors are not stable publication inputs:
// neither a measurement nor later issuance may invoke a different getter value.
// Nominal Common handles are retained, never reconstructed from their fields.
function ownedDataRecord(value: unknown): DataRecord {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail('InvalidRunPublicationPreflight');
  }
  const descriptors = Object.getOwnPropertyDescriptors(value) as PropertyDescriptorMap;
  const entries: [PropertyKey, unknown][] = [];
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
function ownedDataArray<Value = unknown, Captured = Value>(value: unknown,
  capture: (item: Value) => Captured = item => item as unknown as Captured): readonly Captured[] {
  if (!Array.isArray(value)) fail('InvalidRunPublicationPreflight');
  let descriptors: Record<string, PropertyDescriptor>;
  try { descriptors = Object.getOwnPropertyDescriptors(value); }
  catch (cause) { fail('InvalidRunPublicationPreflight', cause); }
  const length = descriptors.length?.value as number;
  if (!Number.isSafeInteger(length) || length < 0) fail('InvalidRunPublicationPreflight');
  const result: Captured[] = [];
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

function snapshotPlan(plan: DataRecord) {
  plan = ownedDataRecord(plan);
  const receiptEvidence = ownedDataRecord(plan.receiptEvidence);
  const captureEvidence = ownedDataRecord(plan.captureEvidence);
  const outputLimits = ownedDataRecord(plan.outputLimits);
  const contractLimits = ownedDataRecord(plan.contractLimits) as ContractLimits;
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
    now: plan.now as () => string,
  });
}

export function prepareCompletedEffectFreeRunPublication(options: unknown) {
  options = ownedDataRecord(options);
  if (!exactKeys(options, [
    'store', 'control', 'publicationInventory', 'plan',
  ])) {
    fail('InvalidRunPublicationPreflight');
  }
  const {store, control} = options as Readonly<{store: PublicationStore; control: PreflightControl}>;
  const publicationInventory = ownedDataRecord((options as DataRecord).publicationInventory);
  const occurrences = ownedDataArray(publicationInventory.occurrences, ownedDataRecord);
  if (store === null || typeof store !== 'object' ||
      typeof store.publicationCapacitySupports !== 'function' ||
      control === null || typeof control !== 'object' ||
      !['issuePublicationRequest', 'issuePublicationAttempt',
        'publicationPreflightValid']
        .every(name => typeof control[name as keyof PreflightControl] === 'function') ||
      publicationInventory === null ||
      typeof publicationInventory !== 'object' ||
      !Array.isArray(publicationInventory.occurrences) ||
      occurrences.length === 0 ||
      typeof publicationInventory.programDefinitionCid !== 'string') {
    fail('InvalidRunPublicationPreflight');
  }
  const plan = snapshotPlan((options as DataRecord).plan as DataRecord);
  if (plan.results.length !== occurrences.length) {
    fail('IncompleteRunPublicationInventory');
  }
  const definitions = ownedDataArray<DataRecord, PublicationContract>(occurrences, occurrence => {
    if (occurrence === null || typeof occurrence !== 'object' ||
        !contract(occurrence.definitionContract)) {
      fail('InvalidRunPublicationPreflight');
    }
    return occurrence.definitionContract;
  });
  let request: IssuedContract;
  let attempt: IssuedContract;
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
  let capacity: Capacity;
  try {
    const bounds = typeof control.resultPublicationContractByteBounds === 'function'
      ? plan.results.map(result => control.resultPublicationContractByteBounds!(
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
