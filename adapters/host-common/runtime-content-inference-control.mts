// Contents and execution handles remain opaque outside their Common owner.
type GraphBounds = Readonly<{task: number; step: number; maxRows: number; maxBytes: number}>;
type GeneratedGraphOptions = GraphBounds & Readonly<{resultDataPolicy: unknown}>;
type PolicyCandidate = Readonly<{kind?: unknown; cid?: unknown; wire?: unknown}>;
type GraphRequest = Readonly<{parent: unknown; input: unknown; contracts: unknown; modelOccurrence?: unknown}>;
type ObservationLimits = Readonly<{maxSlots: number; maxWireBytes: number; maxWork: number}>;
type RetainedContentIdentity = Readonly<{binding: string; descriptorWire: string}>;
type RetainedContent = RetainedContentIdentity & Readonly<{rows: readonly string[]}>;
type RestoredContentBodies = Readonly<{registry: unknown; values: string; fragment: string; ordered: string}>;

type CommonContentInferenceBindings = Readonly<{
  clientProgramAcquiredSerializationPlanComponent(owner: unknown, task: number, step: number,
    maxRows: number, maxBytes: number): unknown;
  clientProgramAcquiredSerializationPlanGraph(owner: unknown, task: number, step: number, maxRows: number,
    maxBytes: number): unknown;
  clientProgramPrepareRequestAcquiredSerializationGraph?(parent: unknown, input: unknown, task: number,
    step: number, maxRows: number, maxBytes: number, includeResults: boolean, contracts: unknown): unknown;
  clientProgramPrepareRequestModelAcquiredSerializationGraph?(parent: unknown, input: unknown,
    occurrence: unknown, task: number, step: number, maxRows: number, maxBytes: number,
    includeResults: boolean, contracts: unknown): unknown;
  clientProgramPrepareRequestModelSerializationGraph?(parent: unknown, input: unknown, occurrence: unknown,
    task: number, step: number, policyCid: string, policyWire: string, maxRows: number, maxBytes: number,
    includeResults: boolean, contracts: unknown): unknown;
  clientProgramPrepareRequestSerializationGraph?(parent: unknown, input: unknown, task: number, step: number,
    policyCid: string, policyWire: string, maxRows: number, maxBytes: number, includeResults: boolean,
    contracts: unknown): unknown;
  clientProgramPrepareRequestSerializedModelGraph?(parent: unknown, input: unknown, occurrence: unknown,
    serialization: unknown, execution: unknown, contracts: unknown): unknown;
  clientProgramSerializationGenerationEvidence(generation: unknown, run: unknown): unknown;
  clientProgramSerializationPlanComponent(owner: unknown, task: number, step: number, policyCid: string,
    policyWire: string, maxRows: number, maxBytes: number): unknown;
  clientProgramSerializationPlanGraph(owner: unknown, task: number, step: number, policyCid: string,
    policyWire: string, maxRows: number, maxBytes: number): unknown;
  clientProgramSerializationPlanGraphWire(graph: unknown): string;
  clientProgramSerializedInferPlanGraph(occurrence: unknown, component: unknown, execution: unknown): unknown;
  clientProgramStartCompleteOriginalInferObservationIssuance(active: unknown, capacity: unknown,
    maxSlots: number, maxWireBytes: number, maxWork: number, generations: unknown): unknown;
  clientProgramStartContentInferObservationIssuance(executions: unknown, generations: unknown,
    ledger: unknown, maxSlots: number, maxWireBytes: number, maxWork: number): unknown;
  clientProgramStartGeneratedInferExecution(prepared: unknown, compiled: unknown, generation: unknown,
    graph: unknown, provider: unknown): unknown;
  clientProgramStartGeneratedInferInputs(compiled: unknown, generation: unknown, graph: unknown,
    inputs: unknown, provider: unknown): unknown;
  clientProgramStartOriginalGeneratedInferExecution(prepared: unknown, compiled: unknown,
    generation: unknown, graph: unknown, provider: unknown, definition: unknown, consumer: unknown,
    readRetainedBytes: bigint, readExecutionBytes: bigint, modelRetainedBytes: bigint,
    modelExecutionBytes: bigint): unknown;
  clientProgramStartOriginalGeneratedInferInputs(compiled: unknown, generation: unknown, graph: unknown,
    inputs: unknown, provider: unknown, definition: unknown, consumer: unknown, readRetainedBytes: bigint,
    readExecutionBytes: bigint, modelRetainedBytes: bigint, modelExecutionBytes: bigint): unknown;
  clientProgramStartOriginalInferObservationIssuance(active: unknown, capacity: unknown, maxSlots: number,
    maxWireBytes: number, maxWork: number, generations: unknown): unknown;
  clientProgramStartRestoredGeneratedInferInput(prepared: unknown, compiled: unknown, definition: unknown,
    generation: unknown, graph: unknown, sequenceContracts: unknown, values: string, provider: unknown,
    binding: string, descriptor: string, rows: unknown, custody: () => boolean, fragment: string,
    ordered: string): unknown;
  clientProgramStartRestoredGeneratedInferInputs(compiled: unknown, definition: unknown, generation: unknown,
    graph: unknown, inputs: unknown, provider: unknown, binding: string, descriptor: string,
    custody: () => boolean): unknown;
}>;

type Owners = Readonly<{
  serializationPlanTokens: WeakMap<object, unknown>;
  serializationGenerationTokens: WeakMap<object, unknown>;
  compiledContent: (compiled: unknown) => unknown;
  compiledRunResult: (result: unknown, code: string) => unknown;
  token: (definition: unknown) => unknown;
}>;

export function createContentInferenceControls(moon: CommonContentInferenceBindings, {
  serializationPlanTokens, serializationGenerationTokens, compiledContent, compiledRunResult, token,
}: Owners) {
  const prepareSerializationGraph = (checkedProgram: unknown, options: GeneratedGraphOptions,
    intermediate: boolean | undefined, request?: GraphRequest) => {
    const original = options?.resultDataPolicy as PolicyCandidate | null | undefined;
    if (original?.kind !== 'data_policy' || typeof original.cid !== 'string' ||
        typeof original.wire !== 'string' ||
        !(['task', 'step', 'maxRows', 'maxBytes'] as const).every(key =>
          Number.isInteger(options[key]) && options[key] >= 0 &&
          options[key] <= 2147483647)) {
      throw new TypeError('Invalid Content compilation options');
    }
    let graph;
    if (request === undefined) {
      const issue = intermediate ? moon.clientProgramSerializationPlanComponent
        : moon.clientProgramSerializationPlanGraph;
      graph = compiledRunResult(issue(checkedProgram, options.task, options.step,
        original.cid, original.wire, options.maxRows, options.maxBytes), 'RunHostContentPlanRejected');
    } else {
      const issue = request.modelOccurrence === undefined ? moon.clientProgramPrepareRequestSerializationGraph
        : moon.clientProgramPrepareRequestModelSerializationGraph;
      if (typeof issue !== 'function') throw new TypeError('Request Content Graph constructor unavailable');
      graph = compiledRunResult(Reflect.apply(issue, moon, [request.parent, request.input,
        ...(request.modelOccurrence === undefined ? [] : [request.modelOccurrence]),
        options.task, options.step, original.cid, original.wire, options.maxRows,
        options.maxBytes, !intermediate, request.contracts]), 'RunHostContentPlanRejected');
    }
    const selected = Object.freeze({task: options.task, step: options.step,
      wire: moon.clientProgramSerializationPlanGraphWire(graph)});
    serializationPlanTokens.set(selected, graph);
    return selected;
  };
  const prepareAcquiredSerializationGraph = (checkedProgram: unknown, options: GraphBounds,
    intermediate: boolean | undefined, request?: GraphRequest) => {
    if (!(['task', 'step', 'maxRows', 'maxBytes'] as const).every(key =>
      Number.isInteger(options?.[key]) && options[key] >= 0 && options[key] <= 2147483647)) {
      throw new TypeError('Invalid acquired Content compilation options');
    }
    let graph;
    if (request === undefined) {
      const issue = intermediate ? moon.clientProgramAcquiredSerializationPlanComponent
        : moon.clientProgramAcquiredSerializationPlanGraph;
      graph = compiledRunResult(issue(checkedProgram, options.task, options.step,
        options.maxRows, options.maxBytes), 'RunHostContentPlanRejected');
    } else {
      const issue = request.modelOccurrence === undefined ? moon.clientProgramPrepareRequestAcquiredSerializationGraph
        : moon.clientProgramPrepareRequestModelAcquiredSerializationGraph;
      if (typeof issue !== 'function') throw new TypeError('Request acquired Content Graph constructor unavailable');
      graph = compiledRunResult(Reflect.apply(issue, moon, [request.parent, request.input,
        ...(request.modelOccurrence === undefined ? [] : [request.modelOccurrence]),
        options.task, options.step, options.maxRows, options.maxBytes,
        !intermediate, request.contracts]), 'RunHostContentPlanRejected');
    }
    const selected = Object.freeze({task: options.task, step: options.step,
      wire: moon.clientProgramSerializationPlanGraphWire(graph)});
    serializationPlanTokens.set(selected, graph);
    return selected;
  };
  return {
    prepareCheckedClientSerializationGraph(checkedProgram: unknown, options: GeneratedGraphOptions) {
      return prepareSerializationGraph(checkedProgram, options, false);
    },
    prepareCheckedClientSerializationComponent(checkedProgram: unknown, options: GeneratedGraphOptions) {
      return prepareSerializationGraph(checkedProgram, options, true);
    },
    prepareCheckedClientRequestSerializationGraph(parent: unknown, input: unknown, contracts: unknown,
      checkedProgram: unknown, options: GeneratedGraphOptions, intermediate: boolean | undefined,
      modelOccurrence?: unknown) {
      return prepareSerializationGraph(checkedProgram, options, intermediate, {parent, input, contracts, modelOccurrence});
    },
    // Keep the selected facade outside Core. Only this existing private map
    // supplies the SAME opaque Content original to the Request constructor.
    // Return its original Result to the manager's existing error projection.
    prepareClientRequestSerializedInferGraph(parent: unknown, input: unknown, occurrence: unknown,
      selected: unknown, execution: unknown, contracts: unknown) {
      const graph = serializationPlanTokens.get(selected as object);
      if (graph === undefined) throw new TypeError('Foreign Content compilation graph');
      const prepare = moon.clientProgramPrepareRequestSerializedModelGraph;
      if (typeof prepare !== 'function') throw new TypeError('Request serialized Model Graph constructor unavailable');
      return Reflect.apply(prepare, moon, [parent, input, occurrence, graph, execution, contracts]);
    },
    prepareCheckedClientSerializedInferGraph(occurrence: unknown, selected: unknown, execution: unknown) {
      const graph = serializationPlanTokens.get(selected as object);
      if (graph === undefined) throw new TypeError('Foreign Content compilation graph');
      return compiledRunResult(moon.clientProgramSerializedInferPlanGraph(
        occurrence, graph, execution), 'RunHostContentInferPlanRejected');
    },
    startCheckedClientGeneratedInferExecution(compiled: unknown, generation: unknown, prepared: unknown,
      graph: unknown, provider: unknown) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation as object);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartGeneratedInferExecution(
        prepared, run, original, graph, provider), 'RunHostContentInferInputRejected');
    },
    startCheckedClientGeneratedInferInputs(compiled: unknown, generation: unknown, graph: unknown,
      inputs: readonly unknown[], provider: unknown) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation as object);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartGeneratedInferInputs(
        run, original, graph, inputs, provider), 'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalGeneratedInferExecution(compiled: unknown, generation: unknown,
      prepared: unknown, graph: unknown, provider: unknown, definition: unknown, consumer: unknown,
      readRetainedBytes: bigint, readExecutionBytes: bigint, modelRetainedBytes: bigint,
      modelExecutionBytes: bigint) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation as object);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartOriginalGeneratedInferExecution(
        prepared, run, original, graph, provider, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes),
      'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalGeneratedInferInputs(compiled: unknown, generation: unknown, graph: unknown,
      inputs: readonly unknown[], provider: unknown, definition: unknown, consumer: unknown,
      readRetainedBytes: bigint, readExecutionBytes: bigint, modelRetainedBytes: bigint,
      modelExecutionBytes: bigint) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation as object);
      if (original === undefined) throw new TypeError('Foreign Client Content generation');
      return compiledRunResult(moon.clientProgramStartOriginalGeneratedInferInputs(
        run, original, graph, inputs, provider, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes),
      'RunHostContentInferInputRejected');
    },
    startCheckedClientRestoredGeneratedInferExecution(compiled: unknown, definition: unknown,
      generation: unknown, prepared: unknown, graph: unknown, provider: unknown, bodies: RestoredContentBodies,
      snapshot: RetainedContent, available: () => boolean) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation as object);
      if (original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client Content generation');
      }
      return compiledRunResult(moon.clientProgramStartRestoredGeneratedInferInput(
        prepared, run, token(definition), original, graph, bodies.registry, bodies.values,
        provider, snapshot.binding, snapshot.descriptorWire, snapshot.rows, available,
        bodies.fragment, bodies.ordered), 'RunHostContentInferInputRejected');
    },
    startCheckedClientRestoredGeneratedInferInputs(compiled: unknown, definition: unknown, generation: unknown,
      graph: unknown, inputs: readonly unknown[], provider: unknown, snapshot: RetainedContentIdentity,
      available: () => boolean) {
      const run = compiledContent(compiled);
      const original = serializationGenerationTokens.get(generation as object);
      if (original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client Content generation');
      }
      return compiledRunResult(moon.clientProgramStartRestoredGeneratedInferInputs(
        run, token(definition), original, graph, inputs, provider, snapshot.binding,
        snapshot.descriptorWire, available), 'RunHostContentInferInputRejected');
    },
    startCheckedClientOriginalContentInferObservation(executions: readonly unknown[],
      generations: readonly unknown[], capacity: unknown, limits: ObservationLimits) {
      if (!Array.isArray(generations)) throw new TypeError('Invalid Content capture inventory');
      const originals = generations.map(generation => {
        const original = serializationGenerationTokens.get(generation as object);
        if (original === undefined) throw new TypeError('Foreign Client Content generation');
        return original;
      });
      // Project the SAME private generation tokens as the input constructor.
      // The existing typed issuer alone checks Run/Scope/current/complete
      // inventory; this projection adds no callbackful evidence recheck.
      return compiledRunResult(executions.length === 1
        ? moon.clientProgramStartOriginalInferObservationIssuance(executions[0],
          capacity, limits.maxSlots, limits.maxWireBytes, limits.maxWork, originals)
        : moon.clientProgramStartCompleteOriginalInferObservationIssuance(executions,
          capacity, limits.maxSlots, limits.maxWireBytes, limits.maxWork, originals),
      'RunHostContentInferObservationRejected');
    },
    startCheckedClientContentInferObservation(compiled: unknown, executions: readonly unknown[],
      generations: readonly unknown[], ledger: unknown, limits: ObservationLimits) {
      const run = compiledContent(compiled);
      if (!Array.isArray(generations)) throw new TypeError('Invalid Content capture inventory');
      const originals = generations.map(generation => {
        const original = serializationGenerationTokens.get(generation as object);
        if (original === undefined ||
            moon.clientProgramSerializationGenerationEvidence(original, run) === undefined) {
          throw new TypeError('Foreign Client Content generation');
        }
        return original;
      });
      return compiledRunResult(moon.clientProgramStartContentInferObservationIssuance(
        executions, originals, ledger, limits.maxSlots, limits.maxWireBytes, limits.maxWork),
      'RunHostContentInferObservationRejected');
    },
    prepareCheckedClientAcquiredSerializationGraph(checkedProgram: unknown, options: GraphBounds) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, false);
    },
    prepareCheckedClientAcquiredSerializationComponent(checkedProgram: unknown, options: GraphBounds) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, true);
    },
    prepareCheckedClientRequestAcquiredSerializationGraph(parent: unknown, input: unknown, contracts: unknown,
      checkedProgram: unknown, options: GraphBounds, intermediate: boolean | undefined,
      modelOccurrence?: unknown) {
      return prepareAcquiredSerializationGraph(checkedProgram, options, intermediate, {parent, input, contracts, modelOccurrence});
    },
  };
}
