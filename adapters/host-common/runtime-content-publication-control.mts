import {runtimeField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';
import {resultOutputLimitFields} from './result-output-limits.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type RunEvidence = Readonly<{name: string; identity: string; wire: string}>;
type PublicationContract = RunEvidence & Readonly<{identityField: string}>;
// The Common inventory producers return exactly these three roles.
type RecoveryBindingName = 'content_input_artifact' | 'content_evidence' | 'content_generation';
type RetainedContentOutput = Readonly<{binding: string; descriptorWire: string; rows: readonly string[]}>;

// Node Common bridges keep compiled handles and Result variants opaque.
// The checked projections below reflect the declared String, Int, Int64 and tuple outputs.
type CommonContentPublicationBindings = Readonly<{
  clientProgramSerializationByteHoldingCid(run: unknown, definition: unknown, storeCid: string): unknown;
  clientCapturedContentGenerationCount(captured: unknown): unknown;
  clientCapturedContentGenerationStorage(captured: unknown, definition: unknown, storeCid: string,
    index: number): unknown;
  clientProgramSerializationRecoveryBindings(generation: unknown, run: unknown, storeCid: string): unknown;
  clientProgramSerializationGenerationOutput(generation: unknown, run: unknown): Extract<import('./runtime-result.mjs').SynchronousRuntimeData, object> | undefined;
  clientProgramExportContentGenerationOutput(generation: unknown, run: unknown, definition: unknown,
    storeCid: string): unknown;
  clientProgramSerializationGenerationEvidence(generation: unknown, run: unknown): unknown;
  clientProgramPrepareRetainedContentOutput(generation: unknown, run: unknown, definition: unknown,
    storeCid: string, binding: string, descriptorWire: string, rows: readonly string[],
    available: () => boolean): unknown;
  clientProgramCompiledEffectProgram(run: unknown, checkedEffect: unknown): unknown;
  clientProgramSerializationGenerationDerivation(generation: unknown, run: unknown): unknown;
  clientProgramIssueSerializationInvocation(run: unknown, definition: unknown, generation: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;

type Current = () => boolean;
type CommonObject = Extract<SynchronousRuntimeData, object>;
type RetainContentStep = (step: CommonObject) => boolean;
type Physical = Readonly<{cancel: Current; stopped: Current; cleanup: Current}>;
type ContentBodies = Readonly<{registry: unknown; values: string; fragment?: string; ordered?: string}>;
type ResultLimits = Readonly<Record<typeof resultOutputLimitFields[number], number>>;
type CompletionLimits = Readonly<{
  maxNodes: number; maxTextBytes: number; maxDepth: number; maxWork: number; maxNameBytes: number;
}>;
type CompletionEvidence = Readonly<{input: unknown; derivation: unknown; generation: unknown}>;
type CapturedSource = Readonly<{
  capture?: Readonly<{source(): unknown; originalRowCapture?(): unknown; originalWholeInput?(): unknown}>;
  inputKind?: string; identity?: unknown; logicalInput?: unknown; wholeCapacity?: unknown; requirement?: unknown;
}>;
type CaptureObservation = Readonly<{
  sourceEvidenceWire: string; authorityScopeCid: string; captureStartedAt: string; captureCompletedAt: string;
  keyedObservation?: Readonly<{observation: unknown}>;
}>;
type SerializationGraphWire = Readonly<{
  nodes?: ReadonlyArray<Readonly<{kind: string; node_id: string;
    barrier?: Readonly<{serialization?: Readonly<{bounds?: Readonly<{max_rows: number; max_bytes: number}>}>}>;
  }>>;
}>;

type CommonContentPreparationBindings = Readonly<{
  clientProgramAdmitEffectSerializationCapturedInput(run: unknown, owner: unknown, source: unknown,
    identity: unknown, requirement: unknown, logical: unknown, sourceWire: string,
    authorityScopeCid: string, startedAt: string, completedAt: string): unknown;
  clientProgramAdmitEffectSerializationWholeCapturedInput(run: unknown, owner: unknown,
    source: unknown, identity: unknown, capacity: unknown, logical: unknown, sourceWire: string,
    authorityScopeCid: string, startedAt: string, completedAt: string): unknown;
  clientProgramAdmitSerializationCapturedInput(owner: unknown, graph: unknown, source: unknown,
    identity: unknown, requirement: unknown, logical: unknown, sourceWire: string,
    authorityScopeCid: string, startedAt: string, completedAt: string, keyed: unknown): unknown;
  clientProgramAdmitSerializationWholeCapturedInput(owner: unknown, graph: unknown, source: unknown,
    identity: unknown, capacity: unknown, logical: unknown, sourceWire: string,
    authorityScopeCid: string, startedAt: string, completedAt: string): unknown;
  clientProgramAdmitManagedSerializationQueryCapturedInput?(run: unknown, owner: unknown, selected: unknown,
    graph: unknown, capture: unknown, identity: unknown, logical: unknown,
    sourceWire: string, authorityScopeCid: string, startedAt: string, completedAt: string): unknown;
  clientProgramAdmitManagedSerializationWholeCapturedInputs(run: unknown, owner: unknown, selected: unknown,
    graph: unknown, captures: readonly unknown[], identities: readonly unknown[], logical: readonly unknown[],
    sourceWires: readonly string[], authorityScopeCid: string, startedAt: string, completedAt: string): unknown;
  clientProgramCheckCompiledRunDefinition(compiled: unknown, definition: unknown): boolean;
  clientProgramCompiledRunAdmission(value: unknown): unknown;
  clientProgramCompiledRunAuthorization(value: unknown): unknown;
  clientProgramCompiledRunPlan(value: unknown): unknown;
  clientProgramCompiledRunPrepared(value: unknown): unknown;
  clientProgramCompiledRunSerializationGraph(run: unknown): unknown;
  clientProgramCompiledRunTemplate(value: unknown): unknown;
  clientProgramCompleteContentStep(active: unknown, run: unknown, definition: unknown,
    evidence: unknown, candidate: unknown, content: unknown, available: Current, maxNodes: number,
    maxTextBytes: number, maxDepth: number, maxWork: number, maxNameBytes: number): unknown;
  clientProgramEffectAllowedSerializationRun(allowed: unknown): unknown;
  clientProgramInferPlanSerializationGraph(graph: unknown): unknown;
  clientProgramInstalledEffectContentPreparationPrepare(prepared: unknown, compiled: unknown,
    compilation: unknown, definition: unknown, component: unknown, contracts: unknown, values: string,
    fragment: string | undefined, ordered: string | undefined, workspace: unknown, cancel: Current,
    stopped: Current, cleanup: Current, retain: RetainContentStep): unknown;
  clientProgramPrepareRequestSerializationOutputDemand(parent: unknown, input: unknown, compiled: unknown, component: unknown,
    ...limits: readonly number[]): unknown;
  clientProgramReadmitSerializationGeneration(run: unknown, definition: unknown, plan: unknown,
    scope: unknown, expectedGenerationCid: string, input: unknown, derivation: unknown,
    generation: unknown, candidate: unknown, content: unknown): unknown;
  clientProgramSerializationGeneration(run: unknown, definition: unknown, input: unknown,
    inputEvidence: unknown, candidate: unknown, content: unknown, available: Current, maxNodes: number,
    maxTextBytes: number, maxDepth: number, maxWork: number, maxNameBytes: number): unknown;
  clientProgramSerializationInputArtifact(input: unknown): unknown;
  clientProgramSerializationInputIdentityBind(run: unknown, input: unknown, receipt: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number, captured: unknown): unknown;
  clientProgramSerializationInputRowBound(graph: unknown): number;
  clientProgramSerializationJsonLeafFieldCount(component: unknown): number;
  clientProgramSerializationPlanGraphCoordinates(component: unknown): readonly [number, number];
  clientProgramSerializationPlanGraphWire(graph: unknown): string;
  clientProgramSerializationPolicyBody(run: unknown): readonly [string, string, string] | undefined;
}>;

type Owners = Readonly<{
  serializationPlanTokens: WeakMap<object, unknown>;
  serializationInputEvidenceTokens: WeakMap<object, unknown>;
  inspectAdmission: (admission: unknown) => Readonly<{kind: 'run-publication-admission'}>;
  evidenceToken: (evidence: unknown) => unknown;
  issuanceLimits: (limits: Limits, label: string) => void;

  compiledRunTokens: WeakMap<object, unknown>;
  serializationGenerationTokens: WeakMap<object, unknown>;
  compiledContent: (run: unknown) => unknown;
  compiledRunResult: (result: unknown, code: string) => unknown;
  token: (value: unknown) => unknown;
  inspectEvidence: (evidence: unknown) => RunEvidence;
  inspect: (contract: unknown, limits?: Limits) => PublicationContract;
  captureContractLimits: (limits: Limits, label: string) => Limits;
}>;

export function createContentPublicationControls(
  moon: CommonContentPublicationBindings & CommonContentPreparationBindings, {
  compiledRunTokens, serializationGenerationTokens, compiledContent, compiledRunResult, token,
  inspectEvidence, inspect, captureContractLimits,
  serializationPlanTokens, serializationInputEvidenceTokens, inspectAdmission, evidenceToken, issuanceLimits,
}: Owners) {
  return {
    adoptCheckedClientEffectSerializationRun(allowed: unknown, definition: unknown) {
      const value = compiledRunResult(moon.clientProgramEffectAllowedSerializationRun(allowed),
        'RunHostEffectContentAdmissionRejected');
      if (!moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Effect Content Run Definition differs from admission');
      }
      const result = Object.freeze({kind: 'serialization' as const,
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(result, value);
      return result;
    },
    prepareCheckedClientEffectContentOriginal(prepared: unknown, compiled: unknown, compilation: unknown,
      definition: unknown, graph: unknown, bodies: ContentBodies, workspace: unknown, physical: Physical,
      retain: RetainContentStep) {
      const value = compiledContent(compiled), component = serializationPlanTokens.get(graph as object);
      if (component === undefined || moon.clientProgramCompiledRunSerializationGraph(value) !== component) {
        throw new TypeError('Foreign Content compilation graph');
      }
      return checked(moon.clientProgramInstalledEffectContentPreparationPrepare(prepared,
        value, compilation, token(definition), component, bodies.registry, bodies.values,
        bodies.fragment, bodies.ordered, workspace, physical.cancel, physical.stopped, physical.cleanup, retain)) as CommonObject;
    },
    compiledSerializationGraph(compiled: unknown) {
      const value = compiledContent(compiled);
      const graph = moon.clientProgramCompiledRunSerializationGraph(value);
      if (graph === undefined) throw new TypeError('Content compilation graph unavailable');
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const selected = Object.freeze({task: runtimeField(coordinates, 0) as number, step: runtimeField(coordinates, 1) as number,
        wire: moon.clientProgramSerializationPlanGraphWire(graph)});
      serializationPlanTokens.set(selected, graph);
      return selected;
    },
    prepareRequestSerializationOutputDemand(parent: unknown, input: unknown, compiled: unknown,
      selection: unknown, fields: readonly number[], output: ResultLimits) {
      const graph = serializationPlanTokens.get(selection as object);
      if (graph === undefined) throw new TypeError('Foreign Content compilation graph');
      // Nominal map lookup only; actual same-Graph/Task and current checks are
      // performed after the original Request funds its Common constructor.
      return checked(moon.clientProgramPrepareRequestSerializationOutputDemand(
        parent, input, compiledContent(compiled), graph, ...fields,
        ...resultOutputLimitFields.map(name => output[name])));
    },
    checkedClientSerializationInputRows(compiled: unknown, selection: unknown) {
      const value = compiledContent(compiled), graph = serializationPlanTokens.get(selection as object);
      if (graph === undefined || moon.clientProgramCompiledRunSerializationGraph(value) !== graph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      const rows = moon.clientProgramSerializationInputRowBound(graph);
      if (!Number.isSafeInteger(rows) || rows < -1) throw new TypeError('Invalid Content input row bound');
      return rows < 0 ? undefined : rows;
    },
    checkedClientSerializationGenerationLimits(compiled: unknown, selection: unknown) {
      const value = compiledContent(compiled);
      const graph = serializationPlanTokens.get(selection as object);
      if (graph === undefined || moon.clientProgramCompiledRunSerializationGraph(value) !== graph) {
        throw new TypeError('Foreign Content compilation graph');
      }
      // Read only the same nominal compiler output, not the caller-visible
      // wire/coordinates. These quantities constrain generation; they supply
      // neither current permission nor physical capacity or cleanup evidence.
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const id = `task_${runtimeField(coordinates, 0)}_serialize_${runtimeField(coordinates, 1)}`;
      const body = JSON.parse(moon.clientProgramSerializationPlanGraphWire(graph)) as SerializationGraphWire;
      const nodes = body.nodes?.filter(node => node.kind === 'content_barrier' && node.node_id === id);
      const bounds = nodes?.length === 1 ? nodes[0].barrier?.serialization?.bounds : undefined;
      if (bounds === undefined || !(['max_rows', 'max_bytes'] as const).every(name =>
        Number.isInteger(bounds[name]) && bounds[name] >= 0 && bounds[name] <= 2147483647)) {
        throw new TypeError('Content compilation generation bounds unavailable');
      }
      const fieldCount = moon.clientProgramSerializationJsonLeafFieldCount(graph);
      if (!Number.isSafeInteger(fieldCount) || fieldCount < -1) {
        throw new TypeError('Content compilation input shape unavailable');
      }
      return Object.freeze({maxRows: bounds.max_rows, maxBytes: bounds.max_bytes,
        jsonLeafFields: fieldCount < 0 ? undefined : fieldCount});
    },
    inferSerializationGraph(inferGraph: unknown) {
      const graph = moon.clientProgramInferPlanSerializationGraph(inferGraph);
      if (graph === undefined) return undefined;
      const coordinates = moon.clientProgramSerializationPlanGraphCoordinates(graph);
      const selected = Object.freeze({task: runtimeField(coordinates, 0) as number, step: runtimeField(coordinates, 1) as number,
        wire: moon.clientProgramSerializationPlanGraphWire(graph)});
      serializationPlanTokens.set(selected, graph);
      return selected;
    },
    compiledSerializationPolicy(compiled: unknown) {
      const value = compiledContent(compiled);
      const body = moon.clientProgramSerializationPolicyBody(value);
      return body === undefined ? undefined : Object.freeze({kind: runtimeField(body, 0) as string, cid: runtimeField(body, 1) as string, wire: runtimeField(body, 2) as string});
    },
    withCheckedClientSerializationGraph<T>(compiled: unknown, graph: unknown, use: (original: unknown) => T) {
      const selected = serializationPlanTokens.get(graph as object);
      if (selected === undefined ||
          moon.clientProgramCompiledRunSerializationGraph(compiledContent(compiled)) !== selected) {
        throw new TypeError('Foreign Content compilation graph');
      }
      return use(selected);
    },
    bindCheckedClientSerializationCapture(checkedProgram: unknown, graph: unknown,
      captured: CapturedSource, observation: CaptureObservation) {
      const selection = serializationPlanTokens.get(graph as object);
      if (selection === undefined) throw new TypeError('Foreign Content compilation graph');
      if (typeof captured?.capture?.source !== 'function' || captured.logicalInput === undefined) {
        throw new TypeError('Invalid Content Source capture');
      }
      if (captured.inputKind === 'whole-input') {
        if (captured.wholeCapacity === undefined || observation.keyedObservation !== undefined) {
          throw new TypeError('Invalid Whole Content Source capture');
        }
        return compiledRunResult(moon.clientProgramAdmitSerializationWholeCapturedInput(
          checkedProgram, selection, captured.capture.source(), captured.identity,
          captured.wholeCapacity, captured.logicalInput, observation.sourceEvidenceWire,
          observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt),
        'RunHostContentCaptureRejected');
      }
      return compiledRunResult(moon.clientProgramAdmitSerializationCapturedInput(
        checkedProgram, selection, captured.capture.source(), captured.identity,
        captured.requirement, captured.logicalInput, observation.sourceEvidenceWire,
        observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt,
        observation.keyedObservation?.observation),
      'RunHostContentCaptureRejected');
    },
    bindCheckedClientSerializationManagedCaptures(run: unknown, checkedProgram: unknown, selected: unknown, graph: unknown,
      sources: readonly Readonly<{captured: CapturedSource; sourceEvidenceWire: string}>[],
      authorityScopeCid: string, startedAt: string, completedAt: string) {
      const component = serializationPlanTokens.get(graph as object);
      if (component === undefined || sources.length < 1 || sources.length > 2 ||
          sources.some(({captured}) => captured.identity === undefined || captured.logicalInput === undefined ||
            typeof (captured.inputKind === 'whole-input' ? captured.capture?.originalWholeInput
              : captured.capture?.originalRowCapture) !== 'function')) {
        throw new TypeError('Invalid Content Source captures');
      }
      if (sources.length === 1 && sources[0].captured.inputKind !== 'whole-input' && sources[0].captured.requirement !== undefined) {
        const bind = moon.clientProgramAdmitManagedSerializationQueryCapturedInput;
        if (typeof bind !== 'function') throw new TypeError('Unavailable Query Content Source capture');
        const {captured, sourceEvidenceWire} = sources[0];
        return compiledRunResult(Reflect.apply(bind, moon, [run, checkedProgram, selected, component,
          captured.capture!.originalRowCapture!(), captured.identity, captured.logicalInput, sourceEvidenceWire,
          authorityScopeCid, startedAt, completedAt]), 'RunHostContentCaptureRejected');
      }
      const bind = moon.clientProgramAdmitManagedSerializationWholeCapturedInputs;
      if (typeof bind !== 'function' || sources.some(({captured}) => captured.inputKind !== 'whole-input')) {
        throw new TypeError('Invalid Whole Content Source captures');
      }
      const captures = sources.map(({captured}) => captured.capture!.originalWholeInput!());
      return compiledRunResult(Reflect.apply(bind, moon, [run, checkedProgram, selected, component, captures,
        sources.map(({captured}) => captured.identity), sources.map(({captured}) => captured.logicalInput),
        sources.map(({sourceEvidenceWire}) => sourceEvidenceWire), authorityScopeCid, startedAt, completedAt]),
        'RunHostContentCaptureRejected');
    },
    bindCheckedClientSerializationInputIdentity(compiled: unknown, input: unknown, receipt: unknown,
      limits: Limits, captured: unknown) {
      const value = compiledContent(compiled);
      issuanceLimits(limits, 'Content input Artifact');
      const evidence = compiledRunResult(moon.clientProgramSerializationInputIdentityBind(
        value, input, receipt, limits.maxWireBytes, limits.maxNodes, limits.maxDepth, captured),
      'RunHostContentInputIdentityRejected');
      const result = inspectEvidence(moon.clientProgramSerializationInputArtifact(evidence));
      serializationInputEvidenceTokens.set(result, evidence);
      return result;
    },
    bindCheckedClientEffectSerializationCapture(compiled: unknown, checkedEffect: unknown,
      captured: CapturedSource, observation: CaptureObservation) {
      const value = compiledContent(compiled);
      if (typeof captured?.capture?.source !== 'function' || captured.logicalInput === undefined) {
        throw new TypeError('Invalid Effect Content Source capture');
      }
      const whole = captured.inputKind === 'whole-input';
      const original = whole ? captured.wholeCapacity : captured.requirement;
      if (original === undefined) throw new TypeError('Invalid Effect Content Source original');
      const admit = whole ? moon.clientProgramAdmitEffectSerializationWholeCapturedInput
        : moon.clientProgramAdmitEffectSerializationCapturedInput;
      return compiledRunResult(admit(
        value, checkedEffect, captured.capture.source(), captured.identity,
        original, captured.logicalInput, observation.sourceEvidenceWire,
        observation.authorityScopeCid, observation.captureStartedAt, observation.captureCompletedAt),
      'RunHostEffectContentCaptureRejected');
    },
    completeCheckedClientContentStep(compiled: unknown, definition: unknown, step: unknown,
      inputEvidence: unknown, candidate: unknown, content: unknown, available: Current, limits: CompletionLimits) {
      const value = compiledContent(compiled);
      const identity = serializationInputEvidenceTokens.get(inputEvidence as object);
      if (identity === undefined) throw new TypeError('Foreign Content input identity');
      const generation = compiledRunResult(moon.clientProgramCompleteContentStep(
        step, value, token(definition), identity, candidate, content, available,
        limits.maxNodes, limits.maxTextBytes, limits.maxDepth, limits.maxWork, limits.maxNameBytes),
      'RunHostContentGenerationRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    completeCheckedClientSerializationGeneration(compiled: unknown, definition: unknown, input: unknown,
      inputEvidence: unknown, candidate: unknown, content: unknown, available: Current, limits: CompletionLimits) {
      const value = compiledContent(compiled);
      const identity = serializationInputEvidenceTokens.get(inputEvidence as object);
      if (identity === undefined) throw new TypeError('Foreign Content input identity');
      const generation = compiledRunResult(moon.clientProgramSerializationGeneration(
        value, token(definition), input, identity, candidate, content, available, limits.maxNodes,
        limits.maxTextBytes, limits.maxDepth, limits.maxWork, limits.maxNameBytes),
      'RunHostContentGenerationRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    readmitCheckedClientSerializationGeneration(compiled: unknown, definition: unknown, graph: unknown,
      scope: unknown, expectedGenerationCid: string, evidence: CompletionEvidence, candidate: unknown, content: unknown) {
      const run = compiledContent(compiled);
      const generation = compiledRunResult(moon.clientProgramReadmitSerializationGeneration(
        run, token(definition), graph, scope, expectedGenerationCid,
        evidenceToken(evidence.input), evidenceToken(evidence.derivation),
        evidenceToken(evidence.generation), candidate, content),
      'RunHostContentGenerationRecoveryRejected');
      const result = Object.freeze({});
      serializationGenerationTokens.set(result, generation);
      return result;
    },
    checkedClientSerializationByteHoldingCid(compiled: unknown, definition: unknown, storeAuthorityCid: string) {
      const value = compiledContent(compiled);
      return compiledRunResult(moon.clientProgramSerializationByteHoldingCid(
        value, token(definition), storeAuthorityCid), 'Client Content byte binding unavailable') as string;
    },
    capturedContentGenerationCount(captured: unknown) {
      return compiledRunResult(moon.clientCapturedContentGenerationCount(token(captured)),
        'Captured Content inventory unavailable') as number;
    },
    capturedContentGenerationStorage(captured: unknown, definition: unknown, storeAuthorityCid: string, index: number) {
      if (!Number.isSafeInteger(index) || index < 0) {
        throw new TypeError('Invalid Captured Content occurrence');
      }
      const value = compiledRunResult(moon.clientCapturedContentGenerationStorage(
        token(captured), token(definition), storeAuthorityCid, index),
      'Captured Content storage binding unavailable');
      return Object.freeze({holdingCid: runtimeField(value, 0) as string, manifestCid: runtimeField(value, 1) as string,
        contentCid: runtimeField(value, 2) as string, byteCount: runtimeField(value, 3) as bigint,
        bindings: Object.freeze((runtimeField(value, 4) as readonly unknown[]).map(binding => Object.freeze({
          name: runtimeField(binding, 0) as RecoveryBindingName, semanticCid: runtimeField(binding, 1) as string, wire: runtimeField(binding, 2) as string, holdingCid: runtimeField(binding, 3) as string,
        })))});
    },
    checkedClientSerializationRecoveryBindings(compiled: unknown, generation: unknown, storeAuthorityCid: string) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const bindings = compiledRunResult(moon.clientProgramSerializationRecoveryBindings(completion,
        value, storeAuthorityCid), 'Client Content recovery binding unavailable') as readonly unknown[];
      return Object.freeze(bindings.map(binding => Object.freeze({
        name: runtimeField(binding, 0) as RecoveryBindingName, semanticCid: runtimeField(binding, 1) as string, wire: runtimeField(binding, 2) as string, holdingCid: runtimeField(binding, 3) as string,
      })));
    },
    checkedClientSerializationGenerationOutput(compiled: unknown, generation: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const output = moon.clientProgramSerializationGenerationOutput(completion, value);
      if (output === undefined) throw new TypeError('Client Content generation unavailable');
      return output;
    },
    exportCheckedClientContentGenerationOutput(compiled: unknown, definition: unknown, generation: unknown, storeAuthorityCid: string) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const exported = compiledRunResult(moon.clientProgramExportContentGenerationOutput(
        completion, value, token(definition), storeAuthorityCid),
      'Client Content completion export unavailable');
      return Object.freeze({binding: runtimeField(exported, 0) as string, descriptorWire: runtimeField(exported, 1) as string,
        rows: Object.freeze((runtimeField(exported, 2) as readonly string[]).slice())});
    },
    checkedClientSerializationGenerationEvidence(compiled: unknown, generation: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationEvidence(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    prepareCheckedClientRetainedContentOutput(compiled: unknown, definition: unknown, generation: unknown,
      storeAuthorityCid: string, completion: RetainedContentOutput, available: () => boolean) {
      const run = compiledRunTokens.get(compiled as object);
      const original = serializationGenerationTokens.get(generation as object);
      if (run === undefined || original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client retained Content output');
      }
      return compiledRunResult(moon.clientProgramPrepareRetainedContentOutput(
        original, run, token(definition), storeAuthorityCid, completion.binding,
        completion.descriptorWire, completion.rows, available),
      'Client Content completion recovery unavailable');
    },
    checkedClientCompiledEffectProgram(compiled: unknown, checkedEffect: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const original = value === undefined ? undefined
        : moon.clientProgramCompiledEffectProgram(value, checkedEffect);
      if (original === undefined) throw new TypeError('Foreign Client compiled Effect Run');
      return original;
    },
    checkedClientSerializationGenerationDerivation(compiled: unknown, generation: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationDerivation(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    issueCheckedClientSerializationInvocation(compiled: unknown, definition: unknown, generation: unknown, limits: Limits) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      limits = captureContractLimits(limits, 'Content Invocation');
      const issued = compiledRunResult(moon.clientProgramIssueSerializationInvocation(
        value, token(definition), completion,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostContentInvocationRejected');
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
  };
}
