import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {localContractLimits as limits, localOutputLimits} from './local-publication-limits.mjs';
import {prepareQueryInvocation, bindQueryInvocation} from './local-query-invocation.mjs';
import {checkedTaskRunAdmission, inferResultPolicy} from './local-source-free-plan.mjs';
import {localPublicationPlan, managedProgramPublicationCurrent,
  managedProgramInitialRetention} from './local-publication-plan.mjs';

type AdmissionOptions = Parameters<typeof checkedTaskRunAdmission>[0];
type TaskAdmission = ReturnType<typeof checkedTaskRunAdmission>;
type Compiled = TaskAdmission['compiled'];
type Definition = TaskAdmission['runDefinition'];
type OriginalInfer = Readonly<{graph: unknown; execution: unknown}>;
type RestoredInfer = Readonly<{
  compiled: Compiled; runDefinition: Definition; graph: unknown; authoringContextOriginal?: unknown;
}>;
type RestoreControls = {
  checkRestoredClientInferRunOwner(restored: RestoredInfer, prepared: unknown): unknown;
  checkedClientCompiledInferOriginal(compiled: Compiled, prepared: unknown, definition: Definition): OriginalInfer;
  checkedClientCompiledInferOriginals(compiled: Compiled, prepared: unknown,
    definition: Definition): readonly OriginalInfer[];
};
type InferOccurrence = {
  moon: {
    clientProgramInferOccurrenceCoordinates(occurrence: unknown): unknown;
    clientProgramInferPlanBoundary(graph: unknown): unknown;
  };
  control: RestoreControls;
  preparedProgram: unknown;
  restored: RestoredInfer;
  occurrence?: unknown;
};
type InferRestore = Pick<InferOccurrence, 'preparedProgram' | 'restored'> & {
  control: RestoreControls & Parameters<typeof prepareQueryInvocation>[0];
  requestIdentity?: unknown;
};
type ContentSelection = Readonly<{
  task: number; step: number; maxRows: number; maxBytes: number; resultDataPolicy: unknown;
}>;
type ContentGraphControl = {
  prepareCheckedClientSerializationComponent(program: unknown, selected: ContentSelection): unknown;
  prepareCheckedClientSerializationGraph(program: unknown, selected: ContentSelection): unknown;
  prepareCheckedClientAcquiredSerializationComponent(program: unknown, selected: ContentSelection): unknown;
  prepareCheckedClientAcquiredSerializationGraph(program: unknown, selected: ContentSelection): unknown;
};
type ContentGraphOptions = {
  moon: {
    clientProgramEffectSerializationOccurrences(program: unknown): unknown;
    clientProgramSerializationOccurrences(program: unknown): unknown;
    clientProgramAcquisitionCount(program: unknown): number;
  };
  control: ContentGraphControl;
  preparedProgram: unknown;
  effectful?: boolean;
  resultDataPolicy?: unknown;
  prepareSerializationGraph?: (selected: ContentSelection, component: boolean) => unknown;
};
type ContentAdmission = AdmissionOptions & ContentGraphOptions;
type PlanOptions<Retention> = Parameters<typeof localPublicationPlan<Retention>>[0];
type ManagedPublication = Parameters<typeof managedProgramInitialRetention>[4];
type PublicationControl<Retention> = PlanOptions<Retention>['control'] &
  Parameters<typeof managedProgramInitialRetention<Retention>>[1] & {
  checkClientCompiledRunOwner(compiled: Compiled, prepared: unknown): unknown;
};
type TaskPublication<Retention> = {
  control: PublicationControl<Retention>;
  moon: {
    clientProgramDefinitionCid(program: unknown): string;
    clientProgramResultCount(program: unknown): number;
  };
  preparedProgram: unknown;
  admitted: TaskAdmission;
  authorityScopeCid: string;
  namespaceId: string;
  storeAuthorityCid: string;
  now(): string;
  sourceEvidence?: readonly unknown[];
  managedPublication?: ManagedPublication;
  assertCurrent?: () => undefined;
};
type IssuedPublication = {observation: Readonly<{wire: string}>; invocation: unknown};
type ContentPublication<Retention> = TaskPublication<Retention> & {
  control: PublicationControl<Retention> & {
    issueCheckedClientSerializationInvocation(compiled: Compiled, definition: Definition,
      generation: unknown, bounds: typeof limits): IssuedPublication;
    checkedClientSerializationRecoveryBindings(compiled: Compiled, generation: unknown,
      storeAuthorityCid: string): readonly Readonly<{name: string; wire: string}>[];
  };
  generation: unknown;
  outputLimits?: PlanOptions<Retention>['outputLimits'];
};
type InferPublication<Retention, Issued extends IssuedPublication & {binding: unknown}> =
  TaskPublication<Retention> & {
    moon: TaskPublication<Retention>['moon'] & {
      clientProgramReleaseInferInvocationBinding(binding: unknown): boolean;
    };
    operation: {
      bindIssuedInvocation(control: PublicationControl<Retention>, input: Readonly<{
        compiled: Compiled; runDefinition: Definition; issued: unknown;
      }>): Issued;
      contentGenerations?(): readonly unknown[] | undefined;
    };
    issuance: unknown;
    modelEvidence: readonly unknown[];
  };

// The model graph belongs to the original prepared Program. Compilation
// verifies that ownership; no source-free Observation Set is issued for a
// model barrier. Capture and its common issuer must supply it after dispatch.
export function inferTaskRunAdmission(options: AdmissionOptions) {
  if (options.inferGraph === undefined) {
    throw new TypeError('MissingInstalledInferGraph');
  }
  return checkedTaskRunAdmission(options, 'infer');
}

// Reuse the admitted original Run and its compiler-owned graph. This is not
// fresh authorization, a new expiry, a replacement execution or a new Ledger.
// Select metadata from this restored compiler's existing opaque inventory.
// Coordinates identify the checked occurrence, never a new execution owner.
export function selectRestoredInferOccurrence({moon, control, preparedProgram, restored, occurrence}: InferOccurrence) {
  control.checkRestoredClientInferRunOwner(restored, preparedProgram);
  if (!Array.isArray(restored.graph)) {
    const original = control.checkedClientCompiledInferOriginal(
      restored.compiled, preparedProgram, restored.runDefinition);
    if (original.graph !== restored.graph) throw new TypeError('ForeignInstalledInferOriginalGraph');
    return original;
  }
  const originals = control.checkedClientCompiledInferOriginals(
    restored.compiled, preparedProgram, restored.runDefinition);
  if (originals.length !== restored.graph.length || occurrence === undefined ||
      originals.some((original, index) => original.graph !== (restored.graph as readonly unknown[])[index])) {
    throw new TypeError('ForeignInstalledInferOriginalGraph');
  }
  const coordinates = moon.clientProgramInferOccurrenceCoordinates(occurrence);
  const selected = originals.filter(original => {
    const boundary = moon.clientProgramInferPlanBoundary(original.graph);
    return runtimeField(boundary, 0) === runtimeField(coordinates, 0) &&
      runtimeField(boundary, 1) === runtimeField(coordinates, 1);
  });
  if (selected.length !== 1) throw new TypeError('ForeignInstalledInferOriginalOccurrence');
  return selected[0];
}

export function restoreInferTaskRunAdmission({control, preparedProgram, restored, requestIdentity}: InferRestore) {
  control.checkRestoredClientInferRunOwner(restored, preparedProgram);
  if (restored.compiled.kind !== 'infer') {
    throw new TypeError('ForeignInstalledInferOriginalRun');
  }
  const {compiled, runDefinition} = restored;
  const originals = Array.isArray(restored.graph)
    ? control.checkedClientCompiledInferOriginals(compiled, preparedProgram, runDefinition)
    : [control.checkedClientCompiledInferOriginal(compiled, preparedProgram, runDefinition)];
  const graphs = Array.isArray(restored.graph) ? restored.graph : [restored.graph];
  if (originals.length !== graphs.length ||
      originals.some((original, index) => original.graph !== graphs[index])) {
    throw new TypeError('ForeignInstalledInferOriginalGraph');
  }
  const queryInvocation=prepareQueryInvocation(control,preparedProgram,requestIdentity,
    JSON.parse(runDefinition.wire));
  const queryTime=bindQueryInvocation(control,queryInvocation,preparedProgram,compiled,runDefinition);
  return Object.freeze({...compiled, compiled, runDefinition, requestIdentity,
    ...queryTime,
    authoringContextOriginal: restored.authoringContextOriginal,
    createdAt: (JSON.parse(runDefinition.wire) as {created_at: string}).created_at, inferGraph: restored.graph});
}

// Select the original checked Content occurrence, not a second parsed Program
// or a pure Values fallback. Physical generation must still supply its actual
// input/generation observations before publication can issue an Invocation.
export function serializationTaskRunAdmission(options: ContentAdmission) {
  const serializationGraph = options.serializationGraph ?? selectInstalledSerializationGraph(options);
  return checkedTaskRunAdmission({...options, serializationGraph}, 'serialization');
}

// Both terminal publication and an intermediate Model input select the same
// installed ceilings and original checked occurrence. Only root ownership differs.
export function selectInstalledSerializationGraph(options: ContentGraphOptions, component = false) {
  const {moon, control, preparedProgram} = options;
  const effectful = options.effectful === true;
  if (effectful && (!component || typeof options.prepareSerializationGraph !== 'function')) {
    throw new TypeError('InstalledContentComponentUnsupported');
  }
  const occurrences = (effectful ? moon.clientProgramEffectSerializationOccurrences
    : moon.clientProgramSerializationOccurrences)(preparedProgram);
  if (!Array.isArray(occurrences) || occurrences.length !== 1) {
    throw new TypeError('InstalledContentComponentUnsupported');
  }
  const occurrence = occurrences[0];
  const selected = {task: runtimeField(occurrence, 0) as number, step: runtimeField(occurrence, 1) as number,
      maxRows: localOutputLimits.maxRows, maxBytes: localOutputLimits.maxWireBytes,
      resultDataPolicy: options.resultDataPolicy ?? inferResultPolicy};
  if (options.prepareSerializationGraph !== undefined) {
    return options.prepareSerializationGraph(selected, component);
  }
  const serializationGraph = moon.clientProgramAcquisitionCount(preparedProgram) === 0
    ? component
      ? control.prepareCheckedClientSerializationComponent(preparedProgram, selected)
      : control.prepareCheckedClientSerializationGraph(preparedProgram, selected)
    : component
      ? control.prepareCheckedClientAcquiredSerializationComponent(preparedProgram, selected)
      : control.prepareCheckedClientAcquiredSerializationGraph(preparedProgram, selected);
  return serializationGraph;
}

// Physical generation discharges the already-admitted Content component.
// Reuse the normal Result retention/publication plan and add only its original
// typed Content proofs. No caller-composed observation or second Run is used.
export function serializationTaskPublicationPlan<Retention>({moon, control, preparedProgram,
  admitted, generation, authorityScopeCid, namespaceId, storeAuthorityCid, now,
  sourceEvidence = [], outputLimits = localOutputLimits, managedPublication, assertCurrent}: ContentPublication<Retention>) {
  if (managedPublication !== undefined) {
    managedProgramPublicationCurrent(moon, preparedProgram, admitted, managedPublication,
      managedPublication.value, managedPublication.request);
    if (typeof assertCurrent !== 'function') throw new TypeError('OriginalProgramRetentionCurrentRequired');
  }
  control.checkClientCompiledRunOwner(admitted.compiled, preparedProgram);
  if (admitted.kind !== 'serialization') {
    throw new TypeError('InvalidContentPublicationAdmission');
  }
  const issued = control.issueCheckedClientSerializationInvocation(admitted.compiled,
    admitted.runDefinition, generation, limits);
  const bindings = control.checkedClientSerializationRecoveryBindings(admitted.compiled,
    generation, storeAuthorityCid);
  const input = bindings.find(binding => binding.name === 'content_input_artifact');
  if (input === undefined) throw new TypeError('ContentPublicationInputMissing');
  const observation = JSON.parse(issued.observation.wire) as {data_policy_cid: string};
  const originalRetention = managedPublication === undefined ? undefined :
    managedProgramInitialRetention(moon, control, preparedProgram, admitted, managedPublication,
      observation.data_policy_cid, now, assertCurrent);
  const plan = localPublicationPlan({control, originalRetention, admission: admitted.admission,
    runDefinition: admitted.runDefinition, invocation: issued.invocation,
    observation: issued.observation, compiledPlanCid: admitted.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [(JSON.parse(input.wire) as {logical_relation_cid: string}).logical_relation_cid], sourceEvidence,
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: observation.data_policy_cid, createdAt: admitted.createdAt, now,
    resultCount: moon.clientProgramResultCount(preparedProgram), outputLimits,
    compiled: admitted.compiled, preparedProgram, authoringContextOriginal: admitted.authoringContextOriginal});
  const contentGenerations = Object.freeze([generation]);
  return Object.freeze({...plan,
    receiptEvidence: Object.freeze({...plan.receiptEvidence, contentGenerations}),
    captureEvidence: Object.freeze({...plan.captureEvidence, contentGenerations})});
}

// Only the common issuer can attach a model observation to this exact Run.
// Retention and Result evidence reuse the ordinary publication plan. The
// caller owns the returned binding until all Store users have settled.
export function inferTaskPublicationPlan<Retention, Issued extends IssuedPublication & {binding: unknown}>({moon, control, preparedProgram,
  admitted, operation, issuance, modelEvidence, sourceEvidence = [], authorityScopeCid, namespaceId,
  storeAuthorityCid, now, managedPublication, assertCurrent}: InferPublication<Retention, Issued>) {
  if (managedPublication !== undefined) {
    managedProgramPublicationCurrent(moon, preparedProgram, admitted, managedPublication,
      managedPublication.value, managedPublication.request);
    if (typeof assertCurrent !== 'function') throw new TypeError('OriginalProgramRetentionCurrentRequired');
  }
  control.checkClientCompiledRunOwner(admitted.compiled, preparedProgram);
  if (admitted.kind !== 'infer' || !Array.isArray(modelEvidence)) {
    throw new TypeError('InvalidInferPublicationAdmission');
  }
  const issued = operation.bindIssuedInvocation(control, {
    compiled: admitted.compiled, runDefinition: admitted.runDefinition,
    issued: issuance});
  try {
    const observation = JSON.parse(issued.observation.wire) as {data_policy_cid: string; captured_input_artifact_cids: string[]};
    const originalRetention = managedPublication === undefined ? undefined :
      managedProgramInitialRetention(moon, control, preparedProgram, admitted, managedPublication,
        observation.data_policy_cid, now, assertCurrent);
    const plan = localPublicationPlan({control, originalRetention,
      admission: admitted.admission, runDefinition: admitted.runDefinition,
      invocation: issued.invocation, observation: issued.observation,
      compiledPlanCid: admitted.compiledPlan.identity,
      programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
      inputRelationCids: observation.captured_input_artifact_cids,
      sourceEvidence, modelEvidence, authorityScopeCid, namespaceId,
      storeAuthorityCid, dataPolicyCid: observation.data_policy_cid,
      createdAt: admitted.createdAt, now,
      resultCount: moon.clientProgramResultCount(preparedProgram),
      compiled: admitted.compiled, preparedProgram, authoringContextOriginal: admitted.authoringContextOriginal});
    const contentGenerations = operation.contentGenerations?.();
    const completePlan = contentGenerations === undefined ? plan : Object.freeze({...plan,
      receiptEvidence: Object.freeze({...plan.receiptEvidence, contentGenerations}),
      captureEvidence: Object.freeze({...plan.captureEvidence, contentGenerations})});
    return Object.freeze({plan: completePlan, ...issued});
  } catch (error) {
    moon.clientProgramReleaseInferInvocationBinding(issued.binding);
    throw error;
  }
}
