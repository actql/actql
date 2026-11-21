import {retainFirstAndLatestCleanupError} from './managed-failure.mjs';
// Complete publication of every checked Named Result retained by one finished
// Effect-free Run. MoonBit issues and validates every semantic contract. This
// coordinator only sequences bounded export and durable Store effects.
import {publishEffectFreeRun, publishEffectfulRun} from
  './run-publication.mjs';
import {preparePrivatePublicationHolding} from
  './private-publication-holding.mjs';

import type {publicationAction} from './publication-action.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type CommonObject = Extract<SynchronousRuntimeData, object>;
type FreePublication = Parameters<typeof publishEffectFreeRun>[0];
type EffectPublication = Parameters<typeof publishEffectfulRun>[0];
type Evidence = FreePublication['evidence'];
type Contract = Evidence['runDefinition'];
type Limits = FreePublication['limits'];
type Preview = EffectPublication['preview'];
type Physical = Readonly<{cid: string; bytes: number}>;
type Schema = Readonly<{cid: string; wire: string}>;
type CleanupState = Readonly<{pending: boolean; outcome?: string; errors?: readonly unknown[]}>;
type Cleanup = Readonly<{status(): CleanupState; retry?(): Awaitable<unknown>}>;
type Prepared = Cleanup & Readonly<{release(): Awaitable<unknown>}>;
type PreparedEntry = Readonly<{prepared?: Prepared}>;
type PreparedPhysical = Prepared & Readonly<{cid: string}>;
type PreparedSchema = PreparedEntry & Readonly<{prepared: Prepared}>;
type HoldingStore = Parameters<typeof preparePrivatePublicationHolding>[0];
type HoldingRecord = Readonly<Omit<Parameters<HoldingStore['commitPhysicalHolding']>[0], 'namespace'> & {
  namespace: 'publication-private' | 'effect-capture' | 'effect-source';
}>;
type PrivateHolding = ReturnType<typeof preparePrivatePublicationHolding>;
type WireBinding = Parameters<NonNullable<HoldingStore['confirmPrivateEvidence']>>[0];
type PrivateRead = Readonly<{
  releaseBytes(): string;
  confirm(binding: WireBinding): Awaitable<HoldingRecord | undefined>;
}>;
type BeforeRead = ((bytes: number) => SynchronousRuntimeData) & Readonly<{
  reserveEnvelope?: (wire: string) => undefined;
}>;
type RecoveryResources = NonNullable<EffectPublication['recoveryResources']> & Readonly<{
  begin(): undefined;
  reserve(bytes: number): undefined;
  finish(failed: boolean, cause: unknown): undefined;
  retainCleanup(cleanup: () => Awaitable<unknown>): undefined;
  reserveEnvelope?(wire: string): undefined;
  reserveDecoded?(wire: string): undefined;
  admitCapturedRun?(wire: string): Contract;
}>;
type Extent = {bytes: number | undefined};
type CaptureStore = HoldingStore & Readonly<{
  storeAuthorityCid: string;
  confirmPrivateEvidence: NonNullable<HoldingStore['confirmPrivateEvidence']>;
  inspectPhysicalHolding(cid: string): Awaitable<HoldingRecord | undefined>;
  inspectPhysicalHoldingForRetirement(cid: string): Awaitable<HoldingRecord | undefined>;
  commitPhysicalHolding(record: HoldingRecord, prepared: readonly Prepared[], borrowed?: readonly string[]): Awaitable<unknown>;
  retirePhysicalHolding(cid: string): Awaitable<Readonly<{cleanup: Cleanup}>>;
  retainEffectCaptureCustody(run: Contract, holdings: readonly HoldingRecord[]): Awaitable<unknown>;
  retireEffectCaptureCustody(run: Contract): Awaitable<boolean>;
  forgetEffectCaptureCustody(run: Contract): Awaitable<unknown>;
  readPrivateEvidence<Value>(name: 'effect_capture', semanticCid: string, holdingCid: string,
    consume: (plaintext: Uint8Array, read: PrivateRead) => Awaitable<Value>, beforeRead?: BeforeRead): Awaitable<Value>;
  putPreparedResultSchema(wire: string, schemaCid: string, runCid: string): Awaitable<PreparedSchema>;
}>;
type ReleaseControl = Readonly<{
  publicationPreparedReleaseAction(current: number, total: number,
    checked: boolean, pending: boolean, attempted: boolean): ReturnType<typeof publicationAction<'preparedRelease'>>;
  publicationCleanupOwnerAction(current: number, total: number, checked: boolean,
    pending: boolean, retryAvailable: boolean, attempted: boolean): ReturnType<typeof publicationAction<'cleanupOwner'>>;
}>;
type AdmitControl = Readonly<{admit(name: string, wire: string, limits: Limits): Contract}>;
type EvidenceChain = Pick<Evidence, 'runDefinition' | 'invocation' | 'definitions' | 'artifacts' | 'manifest' | 'receipt'>;
type EffectEvidenceChain = Omit<EvidenceChain, 'receipt'> & Computation;
type ContentEvidence = Readonly<{contentGenerations?: readonly CommonObject[]}>;
type ReceiptEvidence = ContentEvidence & Readonly<{
  bindings: readonly CommonObject[];
  sourceEvidence: readonly CommonObject[];
  modelEvidence: readonly CommonObject[];
  barrierAttemptReceiptCids: readonly string[];
}>;
type CaptureEvidence = ContentEvidence & Readonly<{
  pendingSourceStateAdvances: readonly CommonObject[];
  modelEvidence: readonly CommonObject[];
}>;
type CapturedFacts = CaptureEvidence & Readonly<{snapshots: readonly CommonObject[]; authoringContext: Contract}>;
type CommonPublicationControl = ReleaseControl & AdmitControl & Readonly<{
  issueResultManifest(run: Contract, invocation: Contract, definitions: readonly Contract[],
    artifacts: readonly Contract[], limits: Limits): Contract;
  issueEffectFreeRunReceipt(chain: Omit<EvidenceChain, 'receipt'> &
    Readonly<{admission: CommonObject; observation: Contract}>, evidence: ReceiptEvidence &
    Readonly<{normalizationJournal: Contract}>, limits: Limits): Contract;
}>;
type FreeControl = CommonPublicationControl & FreePublication['control'] & Readonly<{
  issueEffectFreeCapturedRun(chain: EvidenceChain, evidence: CapturedFacts, limits: Limits,
    signal?: AbortSignal, resource?: unknown): Awaitable<Contract>;
}>;
type Source = EffectPublication['effectSources'][number];
type SourceMember = Readonly<{memberIndex: number; artifact: Contract; schema?: Schema}>;
type LocalSource = CommonObject & Readonly<{kind: 'captured-local-effect-source'}>;
type SourceHolding = SourceMember & Readonly<{source: Source; localEvidence: LocalSource; record: HoldingRecord}>;
type ConnectorRecovery = Readonly<{memberIndex: number; kind: string; observationCid: string; wire: string}>;
type DependencyFacts = Readonly<{artifact_cid: string; physical_cid: string; byte_count: number}>;
type DependencyBinding = Readonly<{artifactCid: string; physicalCid: string; byteCount: number}>;
type DependencyPayload = Readonly<{artifact: Contract; physical: Physical; prepared: PreparedPhysical}>;
type CaptureControl = CommonPublicationControl & Readonly<{
  capturedEffectSourceHoldingCid(source: Source): string;
  capturedEffectSourceArtifactCid(source: Source): string;
  capturedEffectSourceStoreAuthorityCid(source: Source): string;
  capturedEffectSourceMatchesPreview(preview: Preview, memberIndex: number, invocation: Contract,
    source: Source, localEvidence: LocalSource, authorityCid: string, limits: Limits): boolean;
  capturedEffectDependencyPayloadBindings(captured: Contract, bindings: readonly DependencyFacts[]): readonly DependencyFacts[];
  capturedEffectDependencySchemas(captured: Contract): readonly Schema[];
  effectComputationCaptureHoldingCid(run: Contract, authorityCid: string): string;
  effectComputationRecordHoldingCid(run: Contract, authorityCid: string): string;
  effectComputationPreviewLedgerIdentity(preview: Preview): SynchronousRuntimeData;
  effectPrivateEvidenceBinding(preview: Preview, authorityCid: string): WireBinding;
  admitEffectComputationPreview(wire: string, run: Contract, authoring: Contract, limits: Limits): Preview;
  admitRunEvidence(name: string, wire: string, limits: Limits): Contract;
  hasPreparedCapturedEffectRun?(captured: Contract): boolean;
  effectfulComputationEvidenceChainValid(chain: EffectEvidenceChain, preview: Preview, limits: Limits): boolean;
  prepareCapturedEffectSourceInventory(chain: EffectEvidenceChain, preview: Preview, sources: readonly SourceMember[],
    authorityCid: string, limits: Limits): readonly Source[] | undefined;
  capturedEffectSourceInventoryFromCaptureValid(preview: Preview, sources: readonly SourceMember[], invocation: Contract,
    captured: Contract, authorityCid: string, limits: Limits): boolean;
  admitCapturedEffectSourceFromCapture(preview: Preview, memberIndex: number, invocation: Contract, artifact: Contract,
    captured: Contract, authorityCid: string, limits: Limits): Source;
  localEffectResultPayloadBinding(artifact: Contract, run: Contract): DependencyBinding;
  issueEffectfulCapturedRun(chain: EvidenceChain, evidence: CapturedFacts & Readonly<{
    effectSources: readonly Source[]; localEffectSources: readonly LocalSource[];
    dependencyInventoryWire?: string; dependencyConstruction?: CommonObject;
  }>, preview: Preview, plans: readonly Contract[], limits: Limits, signal?: AbortSignal): Awaitable<Contract>;
}>;
type ResultPlan = Readonly<{retention: Contract; evidenceContext: object; transformation?: unknown}>;
type ResultRequest = ResultPlan & Readonly<{
  outputLimits: unknown; contractLimits: Limits; runDefinition: Contract; invocation: Contract; resultProgress?: unknown;
}>;
type StoredResult = PreparedEntry & Readonly<{publication: Readonly<{
  artifact: Contract; derivation: Contract; ordering: Contract; durableBinding: Contract;
}>}>;
type LiveResult = StoredResult & Readonly<{
  occurrence: Readonly<{name: string; task: number; definition: Contract}>;
  publication: StoredResult['publication'] & Readonly<{snapshot: CommonObject}>;
  physical: Physical; schema: Readonly<{semanticCid: string}>;
  orderedRows: Readonly<{resultSchemaWire: string}>;
  physicalPrepared?: PreparedPhysical;
}>;
type StoredResults<Result extends StoredResult = StoredResult> = Readonly<{
  results: readonly Result[]; definitions: readonly Contract[]; artifacts: readonly Contract[];
}>;
type Execution = Readonly<{
  status: 'host-tasks-completed';
  resultInventory: readonly unknown[];
  publicationInventory: Readonly<{occurrences: readonly Readonly<{
    name: string; task: number; definitionContract: Contract;
  }>[] }>;
  storePublicationResult(index: number, store: unknown, request: ResultRequest, signal?: AbortSignal,
    resource?: unknown): Awaitable<LiveResult>;
}>;
type ResultOptions = Readonly<{
  execution: Execution; store: CaptureStore; control: ReleaseControl & AdmitControl;
  runDefinition: Contract; invocation: Contract; results: readonly ResultPlan[];
  outputLimits: unknown; contractLimits: Limits; signal?: AbortSignal; resultProgress?: unknown;
}>;
type CaptureInputs = Readonly<{
  admission: CommonObject; observation: Contract; authoringContext: Contract; normalizationJournal: Contract;
  receiptEvidence: ReceiptEvidence; captureEvidence: CaptureEvidence;
}>;
type CompletedFreeOptions = Omit<ResultOptions, 'store' | 'control'> & CaptureInputs &
  Pick<FreePublication, 'request' | 'attempt' | 'now' | 'signal'> &
  Readonly<{store: FreePublication['store']; control: FreeControl}>;
type RecoveryOptions = Readonly<{store: CaptureStore; control: CaptureControl; runDefinition: Contract; contractLimits: Limits}>;
type EffectCaptureOptions = RecoveryOptions & CaptureInputs & Readonly<{
  execution: Execution; storedResults: StoredResults<LiveResult>; invocation: Contract;
  preview: Preview; plans: readonly Contract[]; effectSourceHoldings: readonly SourceHolding[];
  connectorRecovery: readonly ConnectorRecovery[]; signal?: AbortSignal;
}>;
type Computation = Readonly<{manifest: Contract; computationReceipt: Contract; capturedRun: Contract}>;
type EffectConfirmation = Readonly<{store: CaptureStore; control: CaptureControl; computation: Computation; preview: Preview}>;
type EffectOwnerOptions = EffectConfirmation & Readonly<{execution: Execution | null; storedResults: StoredResults}>;
type CompletedEffectOptions = Omit<EffectOwnerOptions, 'store' | 'control'> &
  Pick<EffectPublication, 'ledger' | 'issuedSet' | 'request' | 'attempt' | 'now' | 'signal'> &
  Readonly<{store: CaptureStore & EffectPublication['store']; control: CaptureControl & EffectPublication['control']; contractLimits: Limits}>;
type DependencyOptions = Readonly<{
  execution: Execution; store: CaptureStore; storedResults: StoredResults;
  control: CaptureControl; runDefinition: Contract; dependencies: readonly DependencyPayload[];
  dependencyInventoryWire: string; dependencyConstruction?: CommonObject;
}>;
type RetainedResult = {
  execution: Execution | null; store: CaptureStore; control: ReleaseControl & AdmitControl;
  runDefinition: Contract; retentions: readonly Contract[];
  releaseComplete: boolean; releaseFlight?: Promise<boolean>;
  cleanupFailure?: CompletedRunPublicationError;
  captureHolding?: HoldingRecord; captureRecordOwner?: PrivateHolding;
  captureRecordWire?: string; capturePublished: boolean; retainCapture?: boolean;
  privateEffectOwner?: PrivateHolding; publicationFailure?: Readonly<{error: unknown}>;
  effectDependencyPayloads?: readonly (DependencyPayload & Readonly<{binding: DependencyBinding}>)[];
  effectDependencyInventoryWire?: string; effectDependencyConstruction?: CommonObject;
  effectSourceSchemaInputs?: readonly Schema[]; effectSourceSchemas?: PreparedSchema[];
  effectDependencySchemas?: readonly PreparedSchema[]; effectSourceHoldingCids?: readonly string[];
};
type RetainedEffect = Readonly<{
  execution: Execution | null; store: CaptureStore; storedResults: StoredResults; control: CaptureControl;
  preview: Preview; runDefinition: Contract; invocation: Contract; captureHolding: HoldingRecord;
  effectSourceHoldings: readonly (Pick<SourceMember, 'artifact'> & Readonly<{source: Source; memberIndex?: number}>)[];
  recoveryResources?: RecoveryResources;
}>;
// The exact DATA is still checked by the existing guards and original Common admission.
type CaptureRecord = Readonly<{
  version: string; store_authority_cid: string; run_definition: string; invocation: string;
  definitions: readonly string[]; artifacts: readonly string[]; derivations: readonly string[];
  orderings: readonly string[]; retentions: readonly string[]; durable_bindings: readonly string[];
  result_schemas: readonly Schema[]; manifest: string; computation_receipt: string; captured_run: string;
  effect_dependency_payloads: readonly DependencyFacts[]; preview: string; authoring_context: string;
  effect_source_artifacts: readonly Readonly<{member_index: number; artifact: string; schema?: Schema}>[];
  connector_recovery: readonly Readonly<{member_index: number; kind: string; observation_cid: string; wire: string}>[];
}>;

export class CompletedRunPublicationError extends Error {
  declare code: string;
  declare primaryFailure: unknown;
  declare cleanupPending?: boolean;
  declare cleanupErrors?: readonly unknown[];
  declare cleanupError?: unknown;
  declare cleanupHandle?: Cleanup | PrivateHolding;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw new CompletedRunPublicationError(code, cause);
};
const exactKeys = (value: unknown, keys: readonly string[]) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const contentEvidenceKeys = (value: unknown, keys: readonly string[]) => exactKeys(value,
  [...keys, ...(Object.hasOwn(value ?? {}, 'contentGenerations') ? ['contentGenerations'] : [])]);
const matchingContentEvidence = (receipt: ContentEvidence, capture: ContentEvidence) => {
  if (!Object.hasOwn(receipt, 'contentGenerations') &&
      !Object.hasOwn(capture, 'contentGenerations')) return true;
  const left = receipt.contentGenerations, right = capture.contentGenerations;
  return Array.isArray(left) && Array.isArray(right) &&
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
};
const member = (value: unknown, name: string): unknown => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? (value as Record<string, unknown>)[name] : undefined;
  } catch { return undefined; }
};
const contract = (value: unknown) => value !== null && typeof value === 'object' &&
  typeof (value as Contract).name === 'string' && typeof (value as Contract).identity === 'string' &&
  typeof (value as Contract).wire === 'string';
const ownContract = (control: AdmitControl, value: Contract, limits: Limits,
  code = 'InvalidCompletedRunPublicationContract') => {
  const admitted = control.admit(value.name, value.wire, limits);
  if (admitted.identity !== value.identity) {
    fail(code);
  }
  return admitted;
};
const completedResultOwners = new WeakMap<StoredResults, RetainedResult>();
const completedEffectfulOwners = new WeakMap<Computation, RetainedEffect>();
const privateEffectfulHoldings = new WeakMap<Computation, PrivateHolding>();

function validateExecution(execution: Execution) {
  if (execution === null || typeof execution !== 'object' ||
      execution.status !== 'host-tasks-completed' ||
      !Array.isArray(execution.resultInventory) ||
      execution.publicationInventory === undefined ||
      !Array.isArray(execution.publicationInventory.occurrences) ||
      execution.publicationInventory.occurrences.length !==
        execution.resultInventory.length ||
      typeof execution.storePublicationResult !== 'function') {
    fail('InvalidCompletedRunPublicationExecution');
  }
}

function validateControl(control: CommonPublicationControl) {
  if (control === null || typeof control !== 'object' ||
      !['issueResultManifest', 'issueEffectFreeRunReceipt',
        'issueEffectFreeCapturedRun', 'publicationPreparedReleaseAction',
        'publicationCleanupOwnerAction']
        .every(name => typeof control[name as keyof CommonPublicationControl] === 'function')) {
    fail('InvalidCompletedRunPublicationControl');
  }
}

function validateOptions(options: CompletedFreeOptions) {
  const keys = [
    'execution', 'store', 'control', 'admission', 'runDefinition',
    'invocation', 'observation', 'normalizationJournal', 'authoringContext',
    'results', 'receiptEvidence', 'captureEvidence', 'request', 'attempt',
    'outputLimits', 'contractLimits', 'now', 'signal',
  ];
  if (!exactKeys(options, keys) || !Array.isArray(options.results) ||
      !contentEvidenceKeys(options.receiptEvidence, [
        'bindings', 'sourceEvidence', 'modelEvidence',
        'barrierAttemptReceiptCids',
      ]) || !contentEvidenceKeys(options.captureEvidence, [
        'pendingSourceStateAdvances', 'modelEvidence',
      ]) || !Array.isArray(options.receiptEvidence.bindings) ||
      !Array.isArray(options.receiptEvidence.sourceEvidence) ||
      !Array.isArray(options.receiptEvidence.modelEvidence) ||
      !Array.isArray(options.receiptEvidence.barrierAttemptReceiptCids) ||
      !Array.isArray(options.captureEvidence.pendingSourceStateAdvances) ||
      !Array.isArray(options.captureEvidence.modelEvidence)) {
    fail('InvalidCompletedRunPublicationOptions');
  }
  if (!matchingContentEvidence(options.receiptEvidence, options.captureEvidence)) {
    fail('InvalidCompletedRunPublicationOptions');
  }
  validateExecution(options.execution);
  // Pure publication still needs a public root. The shared Result inventory
  // may be empty while an independently checked Effect owns the execution.
  if (options.execution.resultInventory.length === 0) {
    fail('InvalidCompletedRunPublicationOptions');
  }
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

function uniqueContracts(values: readonly Contract[]) {
  const seen = new Set();
  return values.filter(value => {
    if (seen.has(value.identity)) return false;
    seen.add(value.identity);
    return true;
  });
}

// Shared failure cleanup for prepared public Results and private Effect
// inputs. Always rethrow the primary failure, retaining retryable custody.
export async function releasePreparedResults(exported: readonly PreparedEntry[], primary: unknown,
  control: ReleaseControl): Promise<never> {
  const prepared = [...new Set(exported
    .map(value => value?.prepared)
    .filter(value => value !== undefined))];
  const errors: unknown[] = [];
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
  const owners: Readonly<{handle: unknown; required: boolean}>[] = [];
  const ownerHandles = new Set<unknown>();
  const addOwner = (handle: unknown, required: boolean) => {
    if (handle !== undefined && ownerHandles.has(handle)) return;
    if (handle !== undefined) ownerHandles.add(handle);
    owners.push(Object.freeze({handle, required}));
  };
  if (member(primary, 'cleanupPending') === true) {
    addOwner(member(primary, 'cleanupHandle'), true);
  }
  for (const handle of prepared) addOwner(handle, true);
  const ownerState = (owner: (typeof owners)[number]) => {
    if (!owner.handle || typeof member(owner.handle, 'status') !== 'function') {
      return {pending: owner.required, errors: []};
    }
    try {
      const value = (owner.handle as Cleanup).status();
      return value && typeof value.pending === 'boolean'
        ? {pending: value.pending,
          outcome: typeof value.outcome === 'string'
            ? value.outcome : undefined,
          errors: Array.isArray(value.errors) ? [...value.errors] : []}
        : {pending: true, errors: []};
    } catch (error) { return {pending: true, errors: [error]}; }
  };
  if (!owners.some(owner => ownerState(owner).pending)) throw primary;
  const initialErrorCount = errors.length;
  const failure = new CompletedRunPublicationError(
    typeof member(primary, 'code') === 'string'
      ? member(primary, 'code') as string : 'CompletedRunPublicationFailed',
    primary,
  );
  const status = () => {
    // One observation per original owner at this synchronous boundary. Do not
    // call its potentially callbackful status again for each projected field.
    const observed = owners.map(ownerState);
    return Object.freeze({
      pending: observed.some(value => value.pending),
      outcome: observed.find(value => value.outcome !== undefined)?.outcome,
      errors: Object.freeze([...observed.flatMap(value => value.errors), ...errors]),
    });
  };
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
          try { await (owners[currentOwner].handle as Cleanup).retry!(); }
          catch (error) { retainFirstAndLatestCleanupError(errors, error, initialErrorCount); }
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
      const observed = status();
      failure.cleanupPending = observed.pending;
      failure.cleanupErrors = observed.errors;
      return observed;
    },
  });
  throw failure;
}

async function exportCompletedRunResultSet({
  execution, store, control, runDefinition, invocation, results,
  outputLimits, contractLimits, signal,
  resultProgress,
}: Omit<ResultOptions, 'store' | 'control'> & Readonly<{store: unknown; control: ReleaseControl}>,
  exported: LiveResult[], publicationResource?: unknown) {
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
      resultProgress,
    }, signal, publicationResource);
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
export async function storeCompletedRunResultSet(options: ResultOptions) {
  const exported: LiveResult[] = [];
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
  dependencyInventoryWire, dependencyConstruction,
}: DependencyOptions) {
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
  owner.effectDependencyConstruction = dependencyConstruction;
  return Object.freeze(adopted.map(value => value.binding));
}

// Release the unpublished physical payload owners. Schema semantic objects
// have separate Store custody. Concurrent callers join one release flight;
// failed physical cleanup retains its retry handle.
export function releaseCompletedRunPreparedPayloads(storedResults: StoredResults, control: ReleaseControl) {
  return releaseCompletedResultOwner(storedResults, control, false);
}

// Relinquish process-local payload custody without selecting a new durable
// capture outcome. A retained capture remains recoverable by a later Host;
// an already selected terminal release continues with its original mode.
// Durable retention, transfer and retirement remain with the enclosing owner.
export async function suspendCompletedEffectfulComputation({
  execution, store, storedResults, control, computation, preview,
}: EffectOwnerOptions) {
  const issued = completedEffectfulOwners.get(computation);
  if (issued === undefined || issued.execution !== execution ||
      issued.store !== store || issued.storedResults !== storedResults ||
      issued.control !== control || issued.preview !== preview) {
    fail('InvalidCompletedEffectfulRunOwner');
  }
  // Publication can select terminal release and then fail while releasing
  // its prepared handles. Continue that owner's exact selected operation;
  // a later cleanup visit must not change it back to capture retention.
  if (completedResultOwners.get(storedResults)?.retainCapture === false) {
    return releaseCompletedResultOwner(storedResults, control, false);
  }
  await confirmCompletedEffectfulApplySources({store, control,
    computation, preview});
  return releaseCompletedResultOwner(storedResults, control, true);
}

function releaseCompletedResultOwner(storedResults: StoredResults, control: ReleaseControl, retainCapture: boolean) {
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
  let flight: Promise<boolean>;
  flight = (async () => {
    if (owner.cleanupFailure !== undefined) {
      const status = await (owner.cleanupFailure.cleanupHandle as Cleanup).retry!() as CleanupState;
      if (status.pending) throw owner.cleanupFailure;
    } else {
      const released = new Error('CompletedRunResultSetReleased');
      try {
        await releasePreparedResults([...storedResults.results,
          ...(owner.effectDependencyPayloads ?? []),
          ...(owner.effectDependencySchemas ?? []),
          ...(owner.effectSourceSchemas ?? [])], released, control);
      } catch (error) {
        if (error !== released) {
          if ((error as CompletedRunPublicationError).cleanupPending === true) owner.cleanupFailure = error as CompletedRunPublicationError;
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
        (error as CompletedRunPublicationError).cleanupPending = true;
        (error as CompletedRunPublicationError).cleanupHandle = owner.captureRecordOwner;
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
export async function issueCompletedEffectfulComputationEvidence(options: EffectCaptureOptions) {
  if (!exactKeys(options, [
    'execution', 'store', 'storedResults', 'control', 'admission', 'runDefinition',
    'invocation', 'observation', 'normalizationJournal', 'authoringContext',
    'receiptEvidence', 'captureEvidence', 'preview', 'plans',
    'effectSourceHoldings', 'connectorRecovery',
    'contractLimits',
    ...(Object.hasOwn(options ?? {}, 'signal') ? ['signal'] : []),
  ])) fail('InvalidCompletedEffectfulComputationOptions');
  const {
    execution, store, storedResults, control, admission, runDefinition,
    invocation, observation, normalizationJournal, authoringContext,
    receiptEvidence, captureEvidence, preview, plans, effectSourceHoldings,
    connectorRecovery,
    contractLimits, signal,
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
        'capturedEffectSourceMatchesPreview',
        'capturedEffectSourceArtifactCid',
        'capturedEffectSourceStoreAuthorityCid',
        'effectComputationCaptureHoldingCid',
        'effectComputationRecordHoldingCid',
        'effectPrivateEvidenceBinding'].every(name =>
        typeof control?.[name as keyof CaptureControl] === 'function') ||
      !contentEvidenceKeys(receiptEvidence, [
        'bindings', 'sourceEvidence', 'modelEvidence',
        'barrierAttemptReceiptCids',
      ]) ||
      !contentEvidenceKeys(captureEvidence, [
        'pendingSourceStateAdvances', 'modelEvidence',
      ]) ||
      !matchingContentEvidence(receiptEvidence, captureEvidence) ||
      !['issueResultManifest', 'issueEffectFreeRunReceipt',
        'issueEffectfulCapturedRun'].every(name =>
        typeof control?.[name as keyof CaptureControl] === 'function')) {
    fail('InvalidCompletedEffectfulComputationOptions');
  }
  const ownedHoldings = effectSourceHoldings.map((holding: SourceHolding) => {
    if (!contract(holding?.artifact) ||
        holding.artifact.name !== 'effect_source_artifact' ||
        !Number.isSafeInteger(holding.memberIndex) ||
        holding.memberIndex < 0 ||
        holding.localEvidence?.kind !== 'captured-local-effect-source' ||
        !holding.record || !Array.isArray(holding.record.objects)) {
      fail('InvalidCompletedEffectSourceHolding');
    }
    const schema = holding.schema;
    if (schema !== undefined && (!exactKeys(schema, ['cid', 'wire']) ||
        typeof schema.wire !== 'string' ||
        schema.cid !== JSON.parse(holding.artifact.wire).result_schema_cid)) {
      fail('InvalidCompletedEffectSourceSchema');
    }
    return Object.freeze({
      source: holding.source,
      ...(schema === undefined ? {} : {schema: Object.freeze({...schema})}),
      memberIndex: holding.memberIndex,
      localEvidence: holding.localEvidence,
      artifact: ownContract(control, holding.artifact, contractLimits,
        'InvalidCompletedEffectSourceHolding'),
      record: Object.freeze({...holding.record,
        objects: Object.freeze(holding.record.objects.map((object: HoldingRecord['objects'][number]) =>
          Object.freeze({...object})))}),
    });
  });
  const ownedMemberIndices = new Set(ownedHoldings.map(
    holding => holding.memberIndex));
  const seenRecoveryMembers = new Set();
  const ownedConnectorRecovery = connectorRecovery.map((entry: ConnectorRecovery) => {
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
        control.capturedEffectSourceMatchesPreview(
          preview, holding.memberIndex, invocation, source,
          holding.localEvidence, store.storeAuthorityCid, contractLimits,
        ) !== true ||
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
  const capturedRun = await control.issueEffectfulCapturedRun({
    runDefinition, invocation, definitions, artifacts, manifest, receipt,
  }, {
    snapshots: storedResults.results.map(value =>
      value.publication.snapshot),
    pendingSourceStateAdvances:
      captureEvidence.pendingSourceStateAdvances,
    authoringContext,
    modelEvidence: captureEvidence.modelEvidence,
    contentGenerations: captureEvidence.contentGenerations,
    effectSources: ownedHoldings.map(value => value.source),
    localEffectSources: ownedHoldings.map(value => value.localEvidence),
    dependencyInventoryWire: owner.effectDependencyInventoryWire,
    dependencyConstruction: owner.effectDependencyConstruction,
  }, preview, plans, contractLimits, signal);
  const dependencyBindings = control.capturedEffectDependencyPayloadBindings(
    capturedRun, (owner.effectDependencyPayloads ?? []).map(value => ({
      artifact_cid: value.binding.artifactCid,
      physical_cid: value.binding.physicalCid,
      byte_count: value.binding.byteCount,
    })));
  const captureHoldingCid = control.effectComputationCaptureHoldingCid(
    runDefinition, store.storeAuthorityCid,
  );
  const objects = new Map<string, Readonly<{physical: Physical; physicalPrepared?: PreparedPhysical}>>();
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
    version: 'actql-local-physical-holding/0.1' as const,
    namespace: 'effect-capture' as const,
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
      ...(value.schema === undefined ? {} : {schema: value.schema}),
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
  const schemas = new Map<string, Schema>();
  for (const {schema} of ownedHoldings) {
    if (schema === undefined) continue;
    if (schemas.has(schema.cid) && schemas.get(schema.cid)!.wire !== schema.wire) {
      fail('InvalidCompletedEffectSourceSchema');
    }
    schemas.set(schema.cid, schema);
  }
  const sourceSchemas = [...schemas.values()];
  if (owner.effectSourceSchemaInputs === undefined) {
    owner.effectSourceSchemaInputs = Object.freeze(sourceSchemas);
    owner.effectSourceSchemas = [];
  } else if (JSON.stringify(owner.effectSourceSchemaInputs) !== JSON.stringify(sourceSchemas)) {
    fail('CompletedEffectfulCaptureConflict');
  }
  // Retain every successful preparation immediately. A later failure keeps
  // its original cleanup and this same owner's already-acquired prefix.
  for (let index = owner.effectSourceSchemas!.length; index < sourceSchemas.length; index++) {
    const schema = sourceSchemas[index];
    owner.effectSourceSchemas!.push(await store.putPreparedResultSchema(
      schema.wire, schema.cid, runDefinition.identity,
    ));
  }
  const commitHolding = store.commitPhysicalHolding.bind(store);
  const prepared = [...objects.values()].map(result => result.physicalPrepared!);
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
export async function retireCompletedEffectfulCapture(options: RecoveryOptions, recoveryResources?: RecoveryResources) {
  return withCaptureRecoveryResources(recoveryResources, beforeRead =>
    retireCompletedEffectfulCaptureOwned(options, beforeRead, recoveryResources));
}

async function retireCompletedEffectfulCaptureOwned({store, control,
  runDefinition, contractLimits}: RecoveryOptions, beforeRead: BeforeRead | undefined, recoveryResources?: RecoveryResources) {
  if (!contract(runDefinition) ||
      typeof store?.storeAuthorityCid !== 'string' ||
      !['inspectPhysicalHolding', 'inspectPhysicalHoldingForRetirement',
        'readPrivateEvidence',
        'retirePhysicalHolding'].every(name =>
        typeof store?.[name as keyof CaptureStore] === 'function')) {
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
  let consuming = false, holdingCids: readonly string[];
  try {
    holdingCids = await store.readPrivateEvidence('effect_capture',
      record.manifest_cid, recordCid, (_plaintext, read) => {
        if (consuming) fail('InvalidCompletedEffectfulCaptureRecord');
        consuming = true;
        return prepareCompletedEffectfulCaptureRetirement(store, control, run,
          contractLimits, record, recordCid, captureCid, read.releaseBytes(), recoveryResources);
      }, beforeRead);
  } catch (error) {
    if (!consuming) fail('InvalidCompletedEffectfulCaptureRecord', error);
    throw error;
  }
  if (!consuming) fail('InvalidCompletedEffectfulCaptureRecord');
  for (const holdingCid of holdingCids) {
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

// Validate the complete remaining original inventory while its encrypted
// record is still protected. Deletion starts only after this reader returns.
async function prepareCompletedEffectfulCaptureRetirement(store: CaptureStore, control: CaptureControl, run: Contract,
  contractLimits: Limits, record: HoldingRecord, recordCid: string, captureCid: string, wire: string, recoveryResources?: RecoveryResources) {
  recoveryResources?.reserveDecoded?.(wire);
  let body: CaptureRecord;
  try { body = JSON.parse(wire) as CaptureRecord; }
  catch (error) { fail('InvalidCompletedEffectfulCaptureRecord', error); }
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
  const admit = (name: string, wire: string) => control.admit(name, wire, contractLimits);
  const chain = {
    runDefinition: run,
    invocation: admit('run_invocation', body.invocation),
    definitions: body.definitions.map(wire =>
      admit('result_definition', wire)),
    artifacts: body.artifacts.map(wire => admit('result_artifact', wire)),
    manifest: admit('result_manifest', body.manifest),
    computationReceipt: admit('run_receipt', body.computation_receipt),
    capturedRun: recoveryResources?.admitCapturedRun?.(body.captured_run) ?? admit('captured_run', body.captured_run),
  };
  const preview = control.admitEffectComputationPreview(body.preview, run,
    control.admitRunEvidence('authoring_context', body.authoring_context,
      contractLimits), contractLimits);
  const previewBinding = control.effectPrivateEvidenceBinding(preview,
    store.storeAuthorityCid);
  // This selects immutable DATA routing only. The prepared branch validates
  // the SAME complete chain inside its one Source projection call below.
  const preparedRoute = control.hasPreparedCapturedEffectRun?.(chain.capturedRun) === true;
  if (chain.capturedRun.identity !== record.manifest_cid ||
      !preparedRoute && !control.effectfulComputationEvidenceChainValid(chain, preview,
        contractLimits)) {
    fail('InvalidCompletedEffectfulCaptureChain');
  }
  const sources = body.effect_source_artifacts.map(item => {
    if (!exactKeys(item, ['member_index', 'artifact',
      ...(Object.hasOwn(item ?? {}, 'schema') ? ['schema'] : [])]) ||
        !Number.isSafeInteger(item.member_index) || item.member_index < 0) {
      fail('InvalidCompletedEffectfulCaptureSource');
    }
    const artifact = admit('effect_source_artifact', item.artifact);
    const schema = item.schema;
    if (schema !== undefined && (!exactKeys(schema, ['cid', 'wire']) ||
        typeof schema.wire !== 'string' ||
        schema.cid !== JSON.parse(artifact.wire).result_schema_cid)) {
      fail('InvalidCompletedEffectSourceSchema');
    }
    return Object.freeze({memberIndex: item.member_index, artifact,
      ...(schema === undefined ? {} : {schema: Object.freeze({...schema})})});
  });
  const preparedSources = preparedRoute ? control.prepareCapturedEffectSourceInventory(
    chain, preview, sources, store.storeAuthorityCid, contractLimits) : undefined;
  if (preparedRoute && (!Array.isArray(preparedSources) || preparedSources.length !== sources.length)) {
    fail('InvalidCompletedEffectfulCaptureSource');
  }
  if (preparedSources === undefined && !control.capturedEffectSourceInventoryFromCaptureValid(preview,
    sources, chain.invocation, chain.capturedRun, store.storeAuthorityCid,
    contractLimits)) {
    fail('InvalidCompletedEffectfulCaptureSource');
  }
  const sourceCids = sources.map(({memberIndex, artifact}, index) => {
    const source = preparedSources === undefined ? control.admitCapturedEffectSourceFromCapture(preview,
      memberIndex, chain.invocation, artifact, chain.capturedRun,
      store.storeAuthorityCid, contractLimits) : preparedSources[index];
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
  return [...sourceCids, captureCid, previewBinding.holdingCid, recordCid];
}

// Recover a completed computation without re-running its physical work. The
// encrypted capture record is only a source of bytes; MoonBit re-admits and
// validates the exact computation chain before any owner is reconstructed.
export async function recoverCompletedEffectfulComputation(options: RecoveryOptions, recoveryResources?: RecoveryResources) {
  return withCaptureRecoveryResources(recoveryResources, (beforeRead, extent) =>
    recoverCompletedEffectfulComputationOwned(options, beforeRead, recoveryResources, extent));
}

// The fixed Host supplies the SAME already admitted Request/Run reservation.
// Finishing this synchronous/asynchronous constructor does not settle it:
// successful returned schema/material owners and any failed physical child
// remain backed until their original caller's actual retirement continuation.
async function withCaptureRecoveryResources<Value>(resources: RecoveryResources | undefined,
  consume: (beforeRead: BeforeRead | undefined, extent: Extent | undefined) => Awaitable<Value>): Promise<Value> {
  if (resources === undefined) return consume(undefined, undefined);
  if (!['begin', 'reserve', 'finish', 'retainCleanup'].every(name => typeof resources?.[name as keyof RecoveryResources] === 'function')) {
    fail('InvalidCompletedEffectfulRecoveryResources');
  }
  const {begin, reserve, finish} = resources;
  Reflect.apply(begin, resources, []);
  let failed = true, cause: unknown;
  try {
    // This cell records only the SAME acquired outer Store extent after its
    // original parent has admitted the reservation. Inner metadata never
    // supplies this constructor bound or changes the selected resource budget.
    const extent: Extent = {bytes: undefined};
    const beforeRead: BeforeRead = bytes => {
      // Preserve the Store's synchronous-void reservation contract.
      const result = Reflect.apply(reserve, resources, [bytes]);
      if (result !== undefined) return result;
      extent.bytes = bytes;
    };
    if (typeof resources.reserveEnvelope === 'function') {
      Object.defineProperty(beforeRead, 'reserveEnvelope', {value: (wire: string) =>
        Reflect.apply(resources.reserveEnvelope!, resources, [wire])});
    }
    const value = await consume(beforeRead, extent);
    failed = false;
    return value;
  } catch (error) {
    cause = error;
    throw error;
  } finally {
    Reflect.apply(finish, resources, [failed, cause]);
  }
}

async function recoverCompletedEffectfulComputationOwned(options: RecoveryOptions, beforeRead: BeforeRead | undefined,
  recoveryResources: RecoveryResources | undefined, extent: Extent | undefined) {
  if (!exactKeys(options, [
    'store', 'control', 'runDefinition', 'contractLimits',
  ])) fail('InvalidCompletedEffectfulRecoveryOptions');
  const {store, control, runDefinition, contractLimits} = options;
  if (!contract(runDefinition) ||
      typeof store?.storeAuthorityCid !== 'string' ||
      !['inspectPhysicalHolding', 'readPrivateEvidence',
        'confirmPrivateEvidence', 'putPreparedResultSchema']
        .every(name => typeof store?.[name as keyof CaptureStore] === 'function') ||
      !['admit', 'admitRunEvidence', 'admitEffectComputationPreview',
        'admitCapturedEffectSourceFromCapture',
        'capturedEffectSourceHoldingCid',
        'capturedEffectSourceArtifactCid',
        'effectComputationCaptureHoldingCid',
        'effectComputationRecordHoldingCid',
        'effectfulComputationEvidenceChainValid',
        'capturedEffectSourceInventoryFromCaptureValid',
        'capturedEffectDependencySchemas']
        .every(name => typeof control?.[name as keyof CaptureControl] === 'function')) {
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
  let consuming = false;
  try {
    const recovered = await store.readPrivateEvidence('effect_capture', record.manifest_cid,
      recordHoldingCid, (_plaintext, read) => {
        if (consuming) fail('InvalidCompletedEffectfulCaptureRecord');
        consuming = true;
        return recoverCompletedEffectfulPlaintext(store, control, contractLimits, admittedRun,
          captureHoldingCid, recordHoldingCid, record, read, recoveryResources, extent);
      }, beforeRead);
    if (!consuming) fail('InvalidCompletedEffectfulCaptureRecord');
    return recovered;
  } catch (error) {
    // Store read/authentication failures retain the old capture-record refusal;
    // typed/physical child failures keep their exact original cleanup carrier.
    if (!consuming) fail('InvalidCompletedEffectfulCaptureRecord', error);
    throw error;
  }
}

// One trusted consumer of the same temporary decrypted backing. The Store's
// original reader spans the complete typed/schema construction and its awaits.
async function recoverCompletedEffectfulPlaintext(store: CaptureStore, control: CaptureControl, contractLimits: Limits,
  admittedRun: Contract, captureHoldingCid: string, recordHoldingCid: string, record: HoldingRecord, read: PrivateRead,
  recoveryResources: RecoveryResources | undefined, extent: Extent | undefined) {
  if (extent !== undefined) {
    // The acquired original must agree with the inspected immutable holding.
    // This bounded inverse never needs to emit a metadata wire larger than
    // the original outer record that contains it. Preserve a smaller policy.
    const bytes = extent.bytes;
    if (!Number.isSafeInteger(bytes) || bytes! < 1 ||
        bytes !== record.objects[0].byte_count ||
        !Number.isSafeInteger(contractLimits?.maxWireBytes) || contractLimits.maxWireBytes < 1) {
      fail('InvalidCompletedEffectfulCaptureRecord');
    }
  }
  let captured: CaptureRecord | undefined, captureRecordWire: string;
  try {
    captureRecordWire = read.releaseBytes();
  } catch (error) {
    fail('InvalidCompletedEffectfulCaptureRecord', error);
  }
  recoveryResources?.reserveDecoded?.(captureRecordWire);
  if (extent !== undefined) {
    // This is the SAME authenticated plaintext returned by the acquired Store
    // read, not inner metadata or a caller-supplied extent. Core funded its
    // UTF8 selector scan before returning from reserveDecoded. Keep a smaller
    // original semantic policy, and retain the encrypted envelope separately.
    const plaintextBytes = Buffer.byteLength(captureRecordWire, 'utf8');
    if (plaintextBytes > extent.bytes!) fail('InvalidCompletedEffectfulCaptureRecord');
    contractLimits = Object.freeze({maxWireBytes: Math.min(contractLimits.maxWireBytes, plaintextBytes),
      maxNodes: contractLimits.maxNodes, maxDepth: contractLimits.maxDepth});
  }
  try {captured = JSON.parse(captureRecordWire) as CaptureRecord;}
  catch (error) {fail('InvalidCompletedEffectfulCaptureRecord', error);}
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
        .every(name => Array.isArray(captured![name as keyof CaptureRecord]))) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  const admit = (name: string, wire: string) => control.admit(name, wire, contractLimits);
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
  if ([artifacts, derivations, orderings, durableBindings,
    captured.result_schemas].some(values => values.length !== count)) {
    fail('InvalidCompletedEffectfulCaptureInventory');
  }
  const invocation = admit('run_invocation', captured.invocation);
  const manifest = admit('result_manifest', captured.manifest);
  const computationReceipt = admit('run_receipt',
    captured.computation_receipt);
  const capturedRun = recoveryResources?.admitCapturedRun?.(captured.captured_run) ?? admit('captured_run', captured.captured_run);
  if (capturedRun.identity !== record.manifest_cid) {
    fail('InvalidCompletedEffectfulCaptureRecord');
  }
  const authoringContext = control.admitRunEvidence('authoring_context',
    captured.authoring_context, contractLimits);
  const preview = control.admitEffectComputationPreview(
    captured.preview, admittedRun, authoringContext, contractLimits);
  const chain = {
    runDefinition: admittedRun, invocation, definitions, artifacts,
    manifest, computationReceipt, capturedRun,
  };
  const preparedRoute = control.hasPreparedCapturedEffectRun?.(capturedRun) === true;
  if (!preparedRoute && !control.effectfulComputationEvidenceChainValid(chain, preview, contractLimits)) {
    fail('InvalidCompletedEffectfulCaptureChain');
  }
  const sourceInventory = captured.effect_source_artifacts.map(item => {
    if (!exactKeys(item, ['member_index', 'artifact',
      ...(Object.hasOwn(item ?? {}, 'schema') ? ['schema'] : [])]) ||
        !Number.isSafeInteger(item.member_index) || item.member_index < 0) {
      fail('InvalidCompletedEffectfulCaptureSource');
    }
    const artifact = admit('effect_source_artifact', item.artifact);
    const schema = item.schema;
    if (schema !== undefined && (!exactKeys(schema, ['cid', 'wire']) ||
        typeof schema.wire !== 'string' ||
        schema.cid !== JSON.parse(artifact.wire).result_schema_cid)) {
      fail('InvalidCompletedEffectSourceSchema');
    }
    return Object.freeze({memberIndex: item.member_index, artifact,
      ...(schema === undefined ? {} : {schema: Object.freeze({...schema})})});
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
  const preparedSources = preparedRoute ? control.prepareCapturedEffectSourceInventory(
    chain, preview, sourceInventory, store.storeAuthorityCid, contractLimits) : undefined;
  if (preparedRoute && (!Array.isArray(preparedSources) || preparedSources.length !== sourceInventory.length)) {
    fail('InvalidCompletedEffectfulCaptureSource');
  }
  if (preparedSources === undefined && !control.capturedEffectSourceInventoryFromCaptureValid(
    preview, sourceInventory, invocation, capturedRun,
    store.storeAuthorityCid, contractLimits)) {
    fail('InvalidCompletedEffectfulCaptureSource');
  }
  const sourceHoldings = [];
  for (const [index, {memberIndex, artifact}] of sourceInventory.entries()) {
    const source = preparedSources === undefined ? control.admitCapturedEffectSourceFromCapture(
      preview, memberIndex, invocation, artifact, capturedRun,
      store.storeAuthorityCid, contractLimits,
    ) : preparedSources[index];
    const holdingCid = control.capturedEffectSourceHoldingCid(source);
    const holding = await store.inspectPhysicalHolding(holdingCid);
    if (holding?.namespace !== 'effect-source' ||
        holding.manifest_cid !== artifact.identity ||
        control.capturedEffectSourceArtifactCid(source) !==
          artifact.identity) {
      fail('CompletedEffectfulCaptureSourceUnavailable');
    }
    await store.commitPhysicalHolding(holding, []);
    sourceHoldings.push(Object.freeze({source, artifact, memberIndex}));
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
    name: 'effect_capture' as const, semanticCid: capturedRun.identity,
    holdingCid: recordHoldingCid, wire: captureRecordWire,
  });
  if (await read.confirm(recordBinding) === undefined) {
    fail('CompletedEffectfulCaptureRecordUnavailable');
  }
  const preparedSchemas: PreparedSchema[] = [];
  const dependencySchemas: PreparedSchema[] = [];
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
    // Private Effect inputs can have a different schema from every public
    // Named Result. Their original bodies are already authenticated inside
    // this CapturedRun's dependency inventory. Restore their Store custody
    // before apply, without publishing the private Result or rerunning Compute.
    for (const schema of [...control.capturedEffectDependencySchemas(capturedRun),
      ...sourceInventory.flatMap(value => value.schema === undefined ? [] : [value.schema])]) {
      dependencySchemas.push(await store.putPreparedResultSchema(
        schema.wire, schema.cid, admittedRun.identity,
      ));
    }
  } catch (error) {
    await releasePreparedResults([...preparedSchemas, ...dependencySchemas], error, control);
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
    effectDependencySchemas: dependencySchemas,
    captureRecordWire: recordBinding.wire, capturePublished: false,
    effectSourceHoldingCids: Object.freeze(sourceHoldings.map(({source}) =>
      control.capturedEffectSourceHoldingCid(source))),
  });
  completedEffectfulOwners.set(computation, Object.freeze({
    execution: null, store, storedResults, control, preview,
    runDefinition: admittedRun, invocation, captureHolding,
    effectSourceHoldings: Object.freeze(sourceHoldings), recoveryResources,
  }));
  if (recoveryResources !== undefined) {
    recoveryResources.retainCleanup(async () => {
      const owner = completedResultOwners.get(storedResults)!;
      // The ordinary caller already selected retain/terminal retirement when
      // applicable. Host shutdown without a selected terminal outcome only
      // relinquishes process-local children; it never deletes saved evidence.
      await releaseCompletedResultOwner(storedResults, control, owner.retainCapture ?? true);
      completedEffectfulOwners.delete(computation);
      // Keep only the existing idempotent result-release tombstone. Caller
      // aliases have been severed before this same resource duty can return.
      for (const field of Object.keys(owner)) {
        if (!['control', 'retainCapture', 'releaseComplete', 'releaseFlight'].includes(field)) {
          (owner as unknown as Record<string, unknown>)[field] = undefined;
        }
      }
    });
  }
  // The returned owners retain their typed contracts, schemas/member handles
  // and original record wire. None borrows this complete parsed container.
  // Cut it before the Store returns and the SAME frame refines its backing;
  // failed construction keeps its original peak and cleanup duties.
  captured = undefined;
  return Object.freeze({execution: null, storedResults, computation,
    preview, invocation, connectorRecovery: Object.freeze(connectorRecovery),
    // These are the exact already admitted and Store-confirmed member handles,
    // not identities from which a caller can recreate Compute or byte custody.
    effectSources: Object.freeze(sourceHoldings)});
}

// Recognize this owner's exact publication or post-publication cleanup failure.
// The publication caller has already received the completed Effect receipt;
// its failure must not be replaced by another interrupted-apply completion.
// This is not evidence that publication committed or its cleanup was ACKed.
export function isCompletedEffectfulPublicationCleanupFailure({
  execution, store, storedResults, control, computation, preview,
}: EffectOwnerOptions, error: unknown) {
  const issued = completedEffectfulOwners.get(computation);
  const owner = completedResultOwners.get(storedResults);
  return issued !== undefined && owner !== undefined &&
    issued.execution === execution && issued.store === store &&
    issued.storedResults === storedResults && issued.control === control &&
    issued.preview === preview && owner.execution === execution &&
    owner.store === store && owner.control === control &&
    owner.releaseComplete === false &&
    (owner.publicationFailure !== undefined &&
      owner.publicationFailure.error === error ||
      owner.capturePublished === true && owner.retainCapture === false &&
      owner.cleanupFailure !== undefined && owner.cleanupFailure === error);
}

// Derive the only final-chain inventory from the same completed Compute and
// Effect-source owners used at capture. This is not apply or publication.
export function prepareCompletedEffectfulPublication(options: EffectOwnerOptions) {
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

// Preserve the closed publication inventory. Connector recovery projects exact
// occurrences separately, through the same existing owners and availability
// checks, rather than extending final publication's accepted argument shape.
export function prepareCompletedEffectSourceMembers(options: EffectOwnerOptions) {
  prepareCompletedEffectfulPublication(options);
  const issued = completedEffectfulOwners.get(options.computation);
  return Object.freeze(issued!.effectSourceHoldings.map(
    ({source, artifact, memberIndex}) => Object.freeze({source, artifact, memberIndex})));
}

// A recovered Preview remains historical evidence until its exact physical
// source holdings and capture record are confirmed at the send boundary.
// This does not authenticate a current Site grant or admit an Effect apply.
export async function confirmCompletedEffectfulApplySources({
  store, control, computation, preview,
}: EffectConfirmation) {
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
      await store.confirmPrivateEvidence(record.binding as WireBinding) === undefined) {
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
}: EffectConfirmation) {
  const issued = completedEffectfulOwners.get(computation);
  if (issued?.store !== store || issued.control !== control ||
      issued.preview !== preview) fail('InvalidCompletedEffectfulApplyOwner');
  await store.forgetEffectCaptureCustody(issued.runDefinition);
}

// Publish only from the retained completed owner and an issued physical
// Effect set. A failed or uncertain commit leaves every owner available for
// reconciliation; a repeated call never re-runs Compute or Effect dispatch.
export async function publishCompletedEffectfulRun(options: CompletedEffectOptions) {
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
  const captureHolding = completedEffectfulOwners.get(computation)!
    .captureHolding;
  if (typeof store.inspectPhysicalHolding !== 'function' ||
      JSON.stringify(await store.inspectPhysicalHolding(
        captureHolding.holding_cid)) !== JSON.stringify(captureHolding)) {
    fail('CompletedEffectfulCaptureUnavailable');
  }
  const captureRecord = completedResultOwners.get(storedResults)!
    .captureRecordOwner;
  if (captureRecord === undefined ||
      await store.confirmPrivateEvidence(captureRecord.binding as WireBinding) ===
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
  const resultOwner = completedResultOwners.get(storedResults)!;
  resultOwner.privateEffectOwner = privateOwner;
  resultOwner.publicationFailure = undefined;
  let publication;
  try {
    await privateOwner.commit();
    const publicationOptions: EffectPublication & {recoveryResources?: RecoveryResources} = {store, control, ...inventory, ledger, issuedSet,
      request, attempt, limits: contractLimits, now, signal};
    const resources = completedEffectfulOwners.get(computation)!.recoveryResources;
    if (resources !== undefined) publicationOptions.recoveryResources = resources;
    publication = await publishEffectfulRun(publicationOptions);
  } catch (error) {
    // Preserve the exact original, including any same-Store cleanup receiver,
    // before an outer caller can attempt interrupted Effect completion.
    resultOwner.publicationFailure = Object.freeze({error});
    throw error;
  }
  if (publication.state === 'succeeded') {
    completedResultOwners.get(storedResults)!.capturePublished = true;
  }
  if (publication.idempotent) {
    await releaseCompletedRunPreparedPayloads(storedResults, control);
  }
  return Object.freeze({publication, computation, storedResults});
}

export async function publishCompletedEffectFreeRun(options: CompletedFreeOptions, publicationResource?: unknown) {
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
  const exported: LiveResult[] = [];
  const retireCaptured = member(control, 'retireCapturedComputation');
  let capturedRun: Contract | undefined, publicationEntered = false;
  try {
    await exportCompletedRunResultSet({
      execution, store, control, runDefinition, invocation, results,
      outputLimits, contractLimits, signal,
    }, exported, publicationResource);
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
    capturedRun = await control.issueEffectFreeCapturedRun({
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
      ...(captureEvidence.contentGenerations === undefined ? {} : {
        contentGenerations: captureEvidence.contentGenerations,
      }),
    }, contractLimits, signal, publicationResource);
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
    // The publication entry owns every terminal/Unknown path from here.
    publicationEntered = true;
    const publication = await publishEffectFreeRun({
      store,
      preparedHandles: Object.freeze(exported.flatMap(value => value.physicalPrepared === undefined ? [] : [value.physicalPrepared])),
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
    if (!publicationEntered && capturedRun !== undefined && typeof retireCaptured === 'function') {
      try {Reflect.apply(retireCaptured, control, [capturedRun]);}
      catch (cleanup) {
        const failure = new CompletedRunPublicationError('CompletedRunCaptureRetirementFailed', error);
        failure.primaryFailure = error;
        failure.cleanupError = cleanup;
        error = failure;
      }
    }
    await releasePreparedResults(exported, error, control);
  }
}
