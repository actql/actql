// Physical acquisition for a Host-authorized DuckDB source. The checked
// Program and MoonBit acquisition planner own the source request and query;
// this adapter supplies only the approved database grant and bounded I/O.
import {runtimeField, runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {readFile} from 'node:fs/promises';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {validateLimits} from '../connectors/duckdb/node/configuration.mjs';
import {checkDuckDBAcquisitionPlanning, freezeAcquisitionDiagnostic, selectInstalledDuckDBAcquisition} from '../connectors/duckdb/node/acquisition-planning.mjs';
import {computePhysicalCapacity} from '../connectors/duckdb/node/physical-capacity.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';
import {acquisitionFailure, acquisitionOutcome} from '../host-common/acquisition-outcome.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';
import type {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {loadDuckDBNativeRuntime} from '../connectors/duckdb/node/native-runtime.mjs';

type QueryOptions = Parameters<typeof prepareOriginalSourceQuery>[0];
type SelectionInputs = Parameters<typeof selectInstalledDuckDBAcquisition>[0];
type Selection = ReturnType<typeof selectInstalledDuckDBAcquisition>['selection'];
type TransportLimits = Parameters<typeof validateLimits>[0];
type Authorize = ReturnType<typeof createAuthorizationGate>['authorize'];
type ReadDecision = Pick<Awaited<ReturnType<Authorize>>, 'action' | 'basis' | 'reason'>;
type SourceAccess = Readonly<{
  authorization?: {authorize(...args: Parameters<Authorize>): ReadDecision | Promise<ReadDecision>};
  connection?: string;
  resource?: string;
  sourceRef: string;
  subjectCid?: string;
}>;
type Occurrence = Readonly<{stage: number; input: number; task: number}>;
type LogicalOwner = (owner: unknown, source: unknown, identity: unknown,
  requirement: unknown, occurrence?: number) => unknown;
type OpenHost = (owner: unknown, source: unknown, registry: QueryOptions['registry'], values: string,
  epochs: bigint, rows: bigint, cells: bigint, bytes: bigint, fragment: string, ordered: string) => unknown;
type Runtime = QueryOptions['moon'] & SelectionInputs['moon'] & Readonly<{
  clientProgramMatchesRequestIdentity(owner: unknown, request: unknown): boolean;
  clientProgramPrepareLocalQueryRequirement: NonNullable<QueryOptions['moon']['clientProgramPrepareLocalQueryRequirement']>;
  clientProgramQueryRequirementSourceEvidenceFacts(requirement: unknown): unknown;
  clientProgramQueryRequirementInputContractCid(requirement: unknown): string;
  clientProgramQueryRequirementOutputContractCid(requirement: unknown): string;
  clientProgramPrepareDuckDBSourceEvidenceContext(requirement: unknown): unknown;
  clientProgramPrepareDuckDBCaptureCapacity?(requirement: unknown, schema: string, table: string,
    ...contracts: SelectionInputs['contracts']): unknown;
  clientProgramCapturedBroadConfiguration(acquisition: unknown): unknown;
  clientProgramCapturedNativeConfiguration(acquisition: unknown): unknown;
  clientProgramInstalledDuckDBCaptureCapacityAccepts?(capacity: unknown, configuration: unknown): boolean;
  clientProgramDuckDBCaptureCapacityAccepts?(capacity: unknown, configuration: unknown): boolean;
  clientProgramEffectCapturedSourceMatches(owner: unknown, source: unknown): boolean;
  clientProgramEffectCapturedSourceMatchesAt(owner: unknown, source: unknown, occurrence: number): boolean;
  clientProgramCapturedTaskSourceMatches(owner: unknown, source: unknown, occurrence: number): boolean;
  clientProgramIdentifyCapturedEffectSourceRelation(source: unknown): unknown;
  clientProgramIdentifyCapturedSourceRelation(source: unknown): unknown;
  clientProgramEffectIssueCapturedSourceLogical: LogicalOwner;
  clientProgramEffectIssueCapturedSourceLogicalAt: LogicalOwner;
  clientProgramIssueCapturedTaskSourceLogical: LogicalOwner;
  clientProgramSelectedInferStep(owner: unknown): unknown;
  clientProgramComposedInferOccurrences(owner: unknown): unknown;
  clientProgramOpenCapturedLocalRetainedHost: OpenHost;
  clientProgramOpenCapturedLocalHost: OpenHost;
}>;
type CaptureOptions = Omit<QueryOptions, 'moon' | 'stage' | 'input' | 'fragment' | 'ordered'> & Readonly<{
  moon: Runtime;
  database: string;
  schema: string;
  table: string;
  fragment: string;
  ordered: string;
  sourceAccess: SourceAccess;
  transportLimits: TransportLimits;
  acquisitionPlanning?: unknown;
  occurrence?: Occurrence;
}>;
type PrepareCaptureOptions = CaptureOptions & Readonly<{
  originalCapture?: Readonly<{requirement: unknown; capacity?: unknown}>;
  originalContracts?: SelectionInputs['contracts'];
  requireImmediateReadAuthorization?: boolean;
}>;
type OpenCaptureOptions = CaptureOptions & Readonly<{
  preparedSource?: ReturnType<typeof describeCapturedSource>;
  signal?: AbortSignal;
  reportAcquisitionFailure?: (failure: ReturnType<typeof acquisitionFailure>) => void;
  ledger?: unknown;
  retainedRelationOutput?: boolean;
}>;
type Preparation = Readonly<Pick<CaptureOptions,
  'moon' | 'registry' | 'values' | 'fragment' | 'ordered' | 'database' | 'schema' | 'table' | 'sourceAccess'> & {
  retainedOnly?: false;
  checkedOwner: unknown;
  effectful: boolean;
  requirement: unknown;
  evidenceContext: unknown;
  acquisition: unknown;
  broad: boolean;
  selection: Selection | undefined;
  selectionInputs: SelectionInputs;
  transportLimits: TransportLimits;
  acquisitionPlanning: unknown;
  capacityEnvelope: unknown;
  installedCapacity: boolean;
  occurrence: Occurrence;
}>;
type RetainedPreparation = Readonly<{
  retainedOnly: true;
  requirement: unknown;
  broad?: never;
  acquisition?: never;
  moon?: never;
  transportLimits?: never;
  capacityEnvelope?: never;
}>;
type NativeCapture = Readonly<{
  source(): unknown;
  document(): string;
  close(): unknown;
}>;
type EvidenceOptions = Readonly<Record<string, unknown>>;
type NativeRuntime = Readonly<{
  session: {
    authorizeLocalDatabase(database: string, access: SourceAccess): Promise<unknown>;
  };
  host: {
    runNativeHostQuery(grant: unknown, acquisition: unknown, limits: TransportLimits,
      signal?: AbortSignal): Promise<NativeCapture>;
    runBroadHostQuery(grant: unknown, acquisition: unknown, limits: TransportLimits,
      signal: AbortSignal | undefined, moon: Runtime, ledger: unknown): Promise<NativeCapture>;
    runStrategyNativeHostQuery(grant: unknown, acquisition: unknown, ledger: unknown,
      limits: TransportLimits, signal?: AbortSignal): Promise<NativeCapture>;
    nativeSourceIdentityMatches(capture: NativeCapture, identity: unknown): boolean;
    issueNativeSourceEvidence(capture: NativeCapture, options: EvidenceOptions): Promise<unknown>;
    prepareNativeSourceEvidenceOriginal(capture: NativeCapture, options: EvidenceOptions): Promise<unknown>;
  };
}>;

const contractRoot = new URL('../../spec/contracts/', import.meta.url);
const contractFiles = [
  'actql-query-acquisition.json',
  'actql-query-process-evidence.json',
  'actql-query-two-receipt.json',
] as const;
const preparations = new WeakMap<object, Preparation | RetainedPreparation>();
const transportLimitKeys = Object.freeze(['maxRows', 'maxCells', 'maxTransportBytes',
  'maxSqlBytes', 'maxParameters', 'maxColumns', 'memoryBytes', 'threads',
  'cancelWaitMs', 'maxChunkRows', 'maxChunkBytes']);
function admittedTransportPolicy(limits: TransportLimits) {
  const validated = validateLimits(limits);
  computePhysicalCapacity(validated);
  return Object.freeze(Object.fromEntries(transportLimitKeys.map(key => [key, validated[key]])));
}

// This pure authorization check precedes comparison. The provider still
// checks the current gate again immediately before opening its read session.
async function currentReadDecision(database: string, access: SourceAccess | undefined, signal?: AbortSignal): Promise<ReadDecision> {
  if (typeof access?.authorization?.authorize !== 'function') {
    return {action: 'deny', basis: 'account', reason: 'configuration_missing'};
  }
  return access.authorization.authorize('acquisition', {
    connection: access.connection ?? 'local-database',
    resource: access.resource ?? database, operation: 'read',
  }, {subjectCid: access.subjectCid, signal});
}

function selectAcquisition(inputs: SelectionInputs) {
  const chosen = selectInstalledDuckDBAcquisition(inputs);
  if (chosen.native === undefined && chosen.broad === undefined) {
    const code = chosen.selection.status === 'deferred'
      ? 'InstalledSourceSelectionDeferred' : 'InstalledSourceNoEligibleCandidate';
    throw Object.assign(new Error(code), {code, selection: chosen.selection});
  }
  return {acquisition: chosen.native ?? chosen.broad,
    broad: chosen.native === undefined, selection: chosen.selection};
}

function checkedSourceForRequirement(moon: Runtime, requirement: unknown, sourceAccess: SourceAccess | undefined) {
  const sourceFacts = checked(
    moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
  if (!Array.isArray(sourceFacts) || sourceFacts.length !== 6 ||
      !sourceFacts.every(value => typeof value === 'string')) {
    throw new Error('InstalledSourceEvidenceFactsUnavailable');
  }
  const [sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid] =
    sourceFacts;
  if (sourceRef !== sourceAccess?.sourceRef) {
    throw new Error('InstalledSourceProgramMismatch');
  }
  const checkedSource = Object.freeze({
    requirementCid: moon.clientProgramQueryRequirementCid(requirement),
    sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid,
    inputContractCid:
      moon.clientProgramQueryRequirementInputContractCid(requirement),
    outputContractCid:
      moon.clientProgramQueryRequirementOutputContractCid(requirement),
  });
  return checkedSource;
}

function describeCapturedSource(checkedSource: ReturnType<typeof checkedSourceForRequirement>,
  selection: Selection | undefined, admittedLimits: TransportLimits,
  planning: ReturnType<typeof checkDuckDBAcquisitionPlanning> | undefined, occurrence: Occurrence,
  sourceAccess: SourceAccess, database: string, schema: string, table: string) {
  return Object.freeze({checkedSource, selection,
    physicalPolicy: Object.freeze({transportLimits: admittedLimits,
      acquisitionPlanning: planning ?? null}),
    occurrence: Object.freeze({...occurrence}),
    readTuple: Object.freeze({connection: sourceAccess.connection ??
      'local-database', resource: sourceAccess.resource ?? database,
    operation: 'read'}),
    physicalBinding: duckDBPhysicalTarget({database, schema, table})});
}

// Readonly target metadata for an already saved Model input. The original
// recovery Request backs this call; it selects no acquisition or physical read.
export function prepareRetainedCapturedDuckDBSource({moon, preparedProgram, requestIdentity,
  registry, values, fragment, ordered, sourceAccess, database, schema, table,
  transportLimits, acquisitionPlanning, occurrence}: CaptureOptions) {
  if (requestIdentity === undefined ||
      moon.clientProgramMatchesRequestIdentity(preparedProgram, requestIdentity) !== true ||
      occurrence === undefined || !['stage', 'input', 'task'].every(name =>
        Number.isSafeInteger(occurrence[name as keyof Occurrence]) && occurrence[name as keyof Occurrence] >= 0)) {
    throw new Error('InstalledSourcePreparationMismatch');
  }
  const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(preparedProgram,
    occurrence.stage, occurrence.input, registry, values, fragment, ordered));
  const checkedSource = checkedSourceForRequirement(moon, requirement, sourceAccess);
  const admittedLimits = admittedTransportPolicy(transportLimits);
  const planning = acquisitionPlanning === undefined ? undefined
    : checkDuckDBAcquisitionPlanning(acquisitionPlanning);
  const prepared = describeCapturedSource(checkedSource, undefined, admittedLimits, planning,
    occurrence, sourceAccess, database, schema, table);
  // Retain only this checked requirement for explicit saved-capture restoration.
  // This record has no acquisition, physical configuration or new-read owner.
  preparations.set(prepared, Object.freeze({requirement, retainedOnly: true}));
  return prepared;
}

// Checked preparation for the Host's acquisition Checkpoint. It does not
// open the database or infer authority from the source CID. The returned
// handle can only be consumed with the same checked Program and Host profile.
export async function prepareCapturedDuckDBSource({moon, preparedProgram,
  preparedEffect,
  queryTimePreparation, requestIdentity, originalCapture, originalContracts,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess, transportLimits, acquisitionPlanning, requireImmediateReadAuthorization = false,
  occurrence = {stage: 0, input: 0, task: 0}}: PrepareCaptureOptions) {
  if (typeof database !== 'string' || typeof schema !== 'string' ||
      typeof table !== 'string' || registry === undefined || registry === null ||
      typeof values !== 'string' || typeof fragment !== 'string' ||
      typeof ordered !== 'string' || typeof requireImmediateReadAuthorization !== 'boolean' ||
      (preparedProgram === undefined) ===
        (preparedEffect === undefined)) {
    throw new TypeError('InvalidInstalledSourceConfiguration');
  }
  if (![occurrence.stage, occurrence.input, occurrence.task].every(Number.isSafeInteger) ||
      occurrence.stage < 0 || occurrence.input !== 0 || occurrence.task !== occurrence.stage ||
      occurrence.task > 1) throw new TypeError('InvalidAcquisitionOccurrence');
  // This installed profile has one captured source at the first task. The
  // owner rejects a different checked source rather than using file settings
  // as a substitute for the Program's source declaration.
  const effectful = preparedEffect !== undefined;
  const checkedOwner = preparedEffect ?? preparedProgram;
  const {requirement} = originalCapture ?? prepareOriginalSourceQuery({moon,
    preparedProgram, preparedEffect, stage: occurrence.stage, input: occurrence.input,
    registry, values, fragment, ordered, queryTimePreparation, requestIdentity});
  const checkedSource = checkedSourceForRequirement(moon, requirement, sourceAccess);
  const sourceRef = checkedSource.sourceRef;
  const evidenceContext = checked(
    moon.clientProgramPrepareDuckDBSourceEvidenceContext(requirement));
  const contracts = originalContracts ?? await Promise.all(contractFiles.map(name =>
    readFile(new URL(name, contractRoot), 'utf8'))) as [...SelectionInputs['contracts']];
  // Mandatory physical limits are actual Host policy, independent of all
  // optional cost/quantity evidence. Validate them before any comparison.
  const admittedLimits = admittedTransportPolicy(transportLimits);
  const planning = acquisitionPlanning === undefined ? undefined
    : checkDuckDBAcquisitionPlanning(acquisitionPlanning);
  const selectionInputs = {moon, requirement, schema, table, contracts,
    source: {database, schema, table, sourceRef}, planning};
  // A bounded capacity envelope is preparation, not a selected acquisition
  // or a read grant. It lets the existing pair ledger retain a completed
  // first input while the second input still awaits its own authorization.
  const capacityEnvelope = originalCapture?.capacity ?? (typeof moon.clientProgramPrepareDuckDBCaptureCapacity === 'function'
    ? checked(moon.clientProgramPrepareDuckDBCaptureCapacity(requirement,
      schema, table, ...contracts)) : undefined);
  let acquisition: unknown, broad = false, selection: Selection | undefined;
  const decision = await currentReadDecision(database, sourceAccess);
  if (decision.action === 'dispatch') {
    ({acquisition, broad, selection} = selectAcquisition(selectionInputs));
  } else if (decision.action === 'deny' ||
      requireImmediateReadAuthorization && decision.action === 'unsupported') {
    // This requirement only stops pre-Run preparation when no later Host
    // authorization owner exists. Actual reads still check current authority.
    throw new ExecutionAuthorizationError(decision);
  }
  // A delegated/held read has no execution authority yet. Its existing
  // Checkpoint owner handles approval; comparison waits for resumed access.
  // Source count and downstream Effects do not change candidate eligibility.
  // The Host-resolved physical target is part of what an approval covers:
  // the same checked source read from another schema or table is another
  // read. Physical names are bound by their exact UTF-8 bytes (hex): the
  // database distinguishes names that ActQL's logical text normalization
  // treats as equal. The readable names are display only.
  const prepared = describeCapturedSource(checkedSource, selection, admittedLimits, planning,
    occurrence, sourceAccess, database, schema, table);
  preparations.set(prepared, Object.freeze({moon, checkedOwner, effectful, registry,
    values, fragment, ordered, database, schema, table, sourceAccess,
    requirement, evidenceContext, acquisition, broad, selection, selectionInputs,
    transportLimits: admittedLimits, acquisitionPlanning, capacityEnvelope,
    installedCapacity: originalCapture !== undefined,
    occurrence: prepared.occurrence}));
  return prepared;
}

// A failure states how the acquisition ended: nothing before the native read
// starts it (a denied read is decided before any session opens). Native/broad
// reads transfer physical session observations and unresolved recovery owners.
// A capture's successful close is required before reporting its stop.
export async function openCapturedDuckDBSource({moon, preparedProgram,
  preparedEffect,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess, transportLimits, acquisitionPlanning, signal, preparedSource,
  reportAcquisitionFailure, occurrence = {stage: 0, input: 0, task: 0}, ledger,
  retainedRelationOutput = false}: OpenCaptureOptions) {
  if (typeof retainedRelationOutput !== 'boolean') {
    throw new TypeError('InvalidLocalRetainedOutputConfiguration');
  }
  if (reportAcquisitionFailure !== undefined &&
      typeof reportAcquisitionFailure !== 'function') {
    throw new TypeError('InvalidAcquisitionEndReceiver');
  }
  const failAcquisition: (cause: unknown, outcome: unknown, recovery?: unknown) => never =
    (cause, outcome, recovery) => {
    const failure = acquisitionFailure(cause, outcome, recovery);
    reportAcquisitionFailure?.(failure);
    throw failure;
  };
  let owner: Preparation | RetainedPreparation | undefined;
  let prepared: ReturnType<typeof describeCapturedSource>;
  let grant: unknown;
  let native: NativeRuntime;
  let authorizedSelection: ReturnType<typeof selectAcquisition> | undefined;
  try {
    prepared = preparedSource ?? await prepareCapturedDuckDBSource({moon,
      preparedProgram, preparedEffect, registry, values, fragment, ordered,
      database, schema, table, sourceAccess, transportLimits, acquisitionPlanning, occurrence});
    owner = preparations.get(prepared);
    const effectful = preparedEffect !== undefined;
    if (owner === undefined || owner.retainedOnly === true || owner.moon !== moon ||
        owner.checkedOwner !== (preparedEffect ?? preparedProgram) ||
        owner.effectful !== effectful ||
        owner.occurrence.stage !== occurrence.stage ||
        owner.occurrence.input !== occurrence.input ||
        owner.occurrence.task !== occurrence.task ||
        owner.registry !== registry || owner.values !== values ||
        owner.fragment !== fragment || owner.ordered !== ordered ||
        owner.database !== database || owner.schema !== schema ||
        owner.table !== table || owner.sourceAccess !== sourceAccess ||
        owner.acquisitionPlanning !== acquisitionPlanning) {
      throw new Error('InstalledSourcePreparationMismatch');
    }
    const currentLimits = admittedTransportPolicy(transportLimits);
    if (transportLimitKeys.some(key => currentLimits[key] !== owner!.transportLimits![key])) {
      throw new Error('InstalledSourceResourcePolicyMismatch');
    }
    const decision = await currentReadDecision(database, sourceAccess, signal);
    if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
    if (owner.acquisition === undefined) {
      authorizedSelection = selectAcquisition(owner.selectionInputs);
    }
    if (owner.capacityEnvelope !== undefined) {
      const selected = authorizedSelection ?? owner;
      const configuration = (selected.broad ? moon.clientProgramCapturedBroadConfiguration
        : moon.clientProgramCapturedNativeConfiguration)(selected.acquisition);
      const accepts = owner.installedCapacity ? moon.clientProgramInstalledDuckDBCaptureCapacityAccepts
        : moon.clientProgramDuckDBCaptureCapacityAccepts;
      if (typeof accepts !== 'function' ||
          Reflect.apply(accepts, moon, [owner.capacityEnvelope, configuration]) !== true) {
        throw new Error('InstalledSourceCapacityEnvelopeMismatch');
      }
    }
    native = await loadDuckDBNativeRuntime() as NativeRuntime;
    grant = await native.session.authorizeLocalDatabase(database, sourceAccess);
  } catch (cause) {
    failAcquisition(cause, 'not_started');
  }
  const {checkedSource} = prepared;
  const {requirement, evidenceContext} = owner;
  const {acquisition, broad, selection} = authorizedSelection ?? owner;
  const {runNativeHostQuery, runBroadHostQuery, runStrategyNativeHostQuery,
    nativeSourceIdentityMatches, issueNativeSourceEvidence,
    prepareNativeSourceEvidenceOriginal} = native.host;
  let capture: NativeCapture;
  try {
    capture = broad
      ? await runBroadHostQuery(grant, acquisition, owner.transportLimits,
        signal, moon, ledger)
      : ledger === undefined
        ? await runNativeHostQuery(grant, acquisition, owner.transportLimits, signal)
        : await runStrategyNativeHostQuery(grant, acquisition, ledger,
          owner.transportLimits, signal);
  } catch (cause) {
    const ended = acquisitionOutcome(cause);
    failAcquisition(cause, cause instanceof
      ExecutionAuthorizationError ? 'not_started' : ended.outcome,
      ended.recovery);
  }
  try {
    const capturedSource = capture.source();
    if ((owner.effectful
      ? (owner.occurrence.task === 0
        ? moon.clientProgramEffectCapturedSourceMatches(owner.checkedOwner, capturedSource)
        : moon.clientProgramEffectCapturedSourceMatchesAt(owner.checkedOwner,
          capturedSource, owner.occurrence.task))
      : moon.clientProgramCapturedTaskSourceMatches(owner.checkedOwner,
        capturedSource, owner.occurrence.task)) !== true) {
      throw new Error('InstalledSourceProgramMismatch');
    }
    const identity = checked(owner.effectful
      ? moon.clientProgramIdentifyCapturedEffectSourceRelation(capturedSource)
      : moon.clientProgramIdentifyCapturedSourceRelation(capturedSource));
    if (!nativeSourceIdentityMatches(capture, identity)) {
      throw new Error('InstalledSourceObservationMismatch');
    }
    const logicalInput = checked(owner.effectful
      ? (owner.occurrence.task === 0
        ? moon.clientProgramEffectIssueCapturedSourceLogical(owner.checkedOwner,
          capturedSource, identity, requirement)
        : moon.clientProgramEffectIssueCapturedSourceLogicalAt(owner.checkedOwner,
          capturedSource, identity, requirement, owner.occurrence.task))
      : moon.clientProgramIssueCapturedTaskSourceLogical(owner.checkedOwner,
        capturedSource, identity, requirement, owner.occurrence.task));
    // An Effect Run is opened only after durable Run admission. Acquisition
    // cannot mint that owner or begin its computation as a read-only Run.
    const inferStep = owner.effectful || ledger !== undefined ? undefined :
      moon.clientProgramSelectedInferStep(owner.checkedOwner);
    const inferInventory = owner.effectful || ledger !== undefined ? undefined :
      moon.clientProgramComposedInferOccurrences(owner.checkedOwner);
    const composedInfer = runtimeIsOk(inferInventory) && (runtimeField(inferInventory, 0) as readonly unknown[]).length > 1;
    const open = retainedRelationOutput
      ? moon.clientProgramOpenCapturedLocalRetainedHost
      : moon.clientProgramOpenCapturedLocalHost;
    const setup = owner.effectful || ledger !== undefined ||
      inferStep !== undefined || composedInfer ? undefined :
      open(owner.checkedOwner,
        capturedSource, registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
    if (!owner.effectful && ledger === undefined &&
        inferStep === undefined && !composedInfer && setup === undefined) {
      throw new Error('InstalledSourceHostUnavailable');
    }
    return Object.freeze({capture, identity, logicalInput, requirement,
      checkedSource, setup, inferStep, composedInfer, capturedSource,
      occurrence: owner.occurrence,
      acquisition: selection === undefined ? undefined : freezeAcquisitionDiagnostic({
        selection, observation: JSON.parse(capture.document())}),
      prepareSourceEvidenceOriginal: (options: EvidenceOptions) => prepareNativeSourceEvidenceOriginal(capture,
        {...options, context: evidenceContext, identity, logicalInput}),
      issueSourceEvidence: (options: EvidenceOptions) => issueNativeSourceEvidence(capture,
        {...options, context: evidenceContext, identity, logicalInput}),
      close: () => capture.close()});
  } catch (cause) {
    try { await capture.close(); }
    catch (cleanup) {
      let pending = true;
      const recovery = Object.freeze({
        close() {},
        async cleanup() { await capture.close(); pending = false; return true; },
        cleanupPending: () => pending,
      });
      const failure = Object.assign(new Error((cause as {message?: string} | null | undefined)?.message ?? 'AcquisitionFailed', {cause}), {
        code: (cause as {code?: unknown} | null | undefined)?.code, primaryFailure: cause,
        cleanupErrors: Object.freeze([cleanup]),
      });
      failAcquisition(failure, 'unknown', recovery);
    }
    failAcquisition(cause, 'stopped');
  }
}

// The checked native preparation contributes its already-admitted capacity to
// the one Run ledger before any source starts. Foreign/closed handles cannot
// manufacture a configuration or bypass the occurrence owner.
export function capturedDuckDBNativeConfiguration(prepared: object) {
  const owner = preparations.get(prepared);
  if (owner === undefined || owner.broad || owner.acquisition === undefined) {
    throw new TypeError('InstalledMultiSourceNativeAcquisitionRequired');
  }
  return owner.acquisition;
}

// Keep the selected configuration's typed owner. Broad remains Broad, with
// the existing Client/Local residual represented in capacity admission.
export function capturedDuckDBConfiguration(prepared: object) {
  const owner = preparations.get(prepared);
  if (owner === undefined) {
    throw new TypeError('InstalledSourcePreparationMismatch');
  }
  if (owner.acquisition === undefined) {
    throw new TypeError('InstalledSourceSelectionRequired');
  }
  return (owner.broad ? owner.moon.clientProgramCapturedBroadConfiguration
    : owner.moon.clientProgramCapturedNativeConfiguration)(owner.acquisition);
}

export function capturedDuckDBPhysicalCapacity(prepared: object) {
  const owner = preparations.get(prepared);
  if (owner === undefined || owner.transportLimits === undefined) {
    throw new TypeError('InstalledSourcePreparationMismatch');
  }
  return computePhysicalCapacity(owner.transportLimits);
}

export function capturedDuckDBPendingCapacity(prepared: object) {
  const owner = preparations.get(prepared);
  if (owner?.capacityEnvelope === undefined) {
    throw new TypeError('InstalledSourceCapacityEnvelopeUnavailable');
  }
  return owner.capacityEnvelope;
}

export function capturedDuckDBRequirement(prepared: object) {
  const owner = preparations.get(prepared);
  if (owner === undefined) throw new TypeError('InstalledSourcePreparationMismatch');
  return owner.requirement;
}
