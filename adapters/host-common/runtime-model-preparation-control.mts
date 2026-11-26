import {checked} from './runtime-result.mjs';

type CompiledRunView = Readonly<{kind?: unknown}>;
type SerializationLimits = Readonly<{
  maxRows: number;
  maxWork: number;
  maxEntries: number;
  maxValueBytes: number;
  maxValueNodes: number;
  maxValueDepth: number;
  maxFrames: number;
}>;
type ModelQuantities = Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
// The installation retains these artifact fields as DATA. Core validates the
// actual pair when it consumes the original installation.
type ModelReadInstallation = Readonly<{
  nodeInstallation: Readonly<{
    layout?: unknown;
    installation: unknown;
    runtimeArtifactCid: unknown;
    layoutArtifactCid: unknown;
    probability?: unknown;
  }>;
  modelRetainedBytes: bigint;
  modelExecutionBytes: bigint;
  bootstrap: Readonly<{
    maxReservations: number;
    maxHoldings: number;
    maxDelegations: number;
    bootstrapRetainedBytes: bigint;
    bootstrapExecutionBytes: bigint;
  }>;
}>;
type ModelGroupMember = Readonly<{
  originalReadInstallation: ModelReadInstallation;
  selection: Readonly<{quantityCapacity: Readonly<{limits: ModelQuantities}>}>;
}>;
type BindComponent = (original: unknown) => unknown;
type ModelComponentConstructor = (owner: unknown, input: unknown, bind: BindComponent) => unknown;
type ModelGroupConstructor = (index: number, owner: unknown, input: unknown, bind: BindComponent) => unknown;
type CheckModelGroupMember = (
  layout: unknown, installation: unknown, runtimeArtifactCid: string, layoutArtifactCid: string,
  probability: unknown, modelRetainedBytes: bigint, modelExecutionBytes: bigint, maxReservations: number,
  maxHoldings: number, maxDelegations: number, bootstrapRetainedBytes: bigint, bootstrapExecutionBytes: bigint,
  tokens: bigint, costUnits: bigint, durationMs: bigint,
) => unknown;
type ModelGroupProjection = (index: number, check: CheckModelGroupMember) => unknown;

// Use the generated parameter shapes while keeping Core handles opaque.
type CommonModelPreparationBindings = Readonly<{
  clientProgramInstalledEffectModelDemandPrepare(prepared: unknown, compiled: unknown,
    compilation: unknown, definition: unknown, occurrence: unknown, graph: unknown): unknown;
  clientProgramInstalledMockModelCapturePlanBind(original: unknown, compiled: unknown,
    definition: unknown, occurrence: unknown, graph: unknown, selected: unknown): unknown;
  clientProgramInstalledMockModelManagedRunRequirements(prepared: unknown, compiled: unknown,
    definition: unknown, occurrence: unknown, graph: unknown, declarations: unknown,
    queryContractBody: string, evidenceContractBody: string, transportBytes: unknown,
    transportExecutionBytes: unknown, installedContracts: unknown, valuesBody: string,
    fragmentBody: string | undefined, orderedBody: string | undefined): unknown;
  clientProgramInstalledNodeEffectModelDemandPrepare(prepared: unknown, compiled: unknown,
    compilation: unknown, definition: unknown, occurrence: unknown, graph: unknown, selected: unknown,
    layout: unknown, installation: unknown, runtimeArtifactCid: string, layoutArtifactCid: string,
    probability: unknown, modelRetainedBytes: bigint, modelExecutionBytes: bigint,
    maxReservations: number, maxHoldings: number, maxDelegations: number,
    bootstrapRetainedBytes: bigint, bootstrapExecutionBytes: bigint): unknown;
  clientProgramOpenRequestModelRecoveryHost(parent: unknown, input: unknown, request: unknown,
    definition: unknown, prepared: unknown, sources: unknown, contracts: unknown, values: string,
    fragment: string | undefined, ordered: string | undefined, providers: unknown): unknown;
  clientProgramPrepareRequestKeyedSerializationCompilation(parent: unknown, input: unknown,
    selected: unknown, component: unknown): unknown;
  clientProgramPrepareRequestModelCaptureModule(parent: unknown, input: unknown, request: unknown,
    compiled: unknown, definition: unknown, compilation: unknown, declarations: unknown,
    queryContractBody: string, evidenceContractBody: string, transportBytes: unknown,
    transportExecutionBytes: unknown, contracts: unknown, retainedOutput: boolean, queryTime: unknown): unknown;
  clientProgramPrepareRequestModelCapturePlan(parent: unknown, input: unknown, original: unknown,
    request: unknown, compiled: unknown, definition: unknown, occurrence: unknown, graph: unknown,
    selected: unknown): unknown;
  clientProgramPrepareRequestModelComponentCaptureModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown,
    declarations: unknown, queryContractBody: string, evidenceContractBody: string,
    transportBytes: unknown, transportExecutionBytes: unknown, contracts: unknown,
    retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: unknown, _arg1: unknown, _arg2: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelDuckDBComponentCaptureModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown, sourceRef: string,
    databaseSchema: string, table: string, queryContractBody: string, evidenceContractBody: string,
    twoReceiptContractBody: string, transportBytes: bigint, transportExecutionBytes: bigint,
    contracts: unknown, retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: unknown, _arg1: unknown, _arg2: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelProviderCaptureModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown,
    declaration: unknown, provider: unknown, queryContractBody: string, evidenceContractBody: string,
    transportBytes: bigint, transportExecutionBytes: bigint, contracts: unknown,
    retainedOutput: boolean, queryTime: unknown): unknown;
  clientProgramPrepareRequestModelProviderComponentCaptureModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown,
    declaration: unknown, provider: unknown, queryContractBody: string, evidenceContractBody: string,
    transportBytes: bigint, transportExecutionBytes: bigint, contracts: unknown,
    retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: unknown, _arg1: unknown, _arg2: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelRecoveryReadScopes(parent: unknown, input: unknown,
    request: unknown, definition: unknown, prepared: unknown, compiled: unknown, graphs: unknown,
    selected: unknown, modelRetainedBytes: unknown, modelExecutionBytes: unknown,
    readRetainedBytes: unknown, readExecutionBytes: unknown, maxReservations: number,
    maxHoldings: number, maxDelegations: number): unknown;
  clientProgramPrepareRequestModelRecoveryReadScopesWithQuantities(parent: unknown, input: unknown,
    request: unknown, definition: unknown, prepared: unknown, compiled: unknown, graphs: unknown,
    selected: unknown, modelRetainedBytes: unknown, modelExecutionBytes: unknown,
    readRetainedBytes: unknown, readExecutionBytes: unknown, maxReservations: number,
    maxHoldings: number, maxDelegations: number, tokens: bigint, costUnits: bigint, durationMs: bigint): unknown;
  clientProgramPrepareRequestModelSerializationPlan(parent: unknown, input: unknown, request: unknown,
    compiled: unknown, definition: unknown, maxRows: number, maxWork: number, maxEntries: number,
    maxValueBytes: number, maxValueNodes: number, maxValueDepth: number, maxFrames: number,
    workspace: unknown, queryTime: unknown): unknown;
  clientProgramPrepareRequestModelSourceFreeComponentModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown,
    contracts: unknown, retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: unknown, _arg1: unknown, _arg2: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelSourceFreeModule(parent: unknown, input: unknown, request: unknown,
    compiled: unknown, definition: unknown, compilation: unknown, contracts: unknown,
    retainedOutput: boolean, queryTime: unknown): unknown;
  clientProgramPrepareRequestModelSourceFreePlan(parent: unknown, input: unknown, original: unknown,
    request: unknown, compiled: unknown, definition: unknown, occurrence: unknown, graph: unknown,
    selected: unknown): unknown;
  clientProgramPrepareRequestModelWholeInputsComponentCaptureModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown,
    wholeSources: unknown, queryContractBody: string, evidenceContractBody: string,
    transportBytes: unknown, transportExecutionBytes: unknown, contracts: unknown,
    retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: unknown, _arg1: unknown, _arg2: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelsCapturePlan(parent: unknown, input: unknown, original: unknown,
    request: unknown, compiled: unknown, definition: unknown, occurrences: unknown, graphs: unknown,
    selected: unknown): unknown;
  clientProgramPrepareRequestModelsDuckDBComponentCaptureModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown, sourceRef: string,
    databaseSchema: string, table: string, queryContractBody: string, evidenceContractBody: string,
    twoReceiptContractBody: string, transportBytes: bigint, transportExecutionBytes: bigint,
    contracts: unknown, retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: number, _arg1: unknown, _arg2: unknown, _arg3: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelsProviderComponentCaptureModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown,
    declarations: unknown, providers: unknown, queryContractBody: string,
    evidenceContractBody: string, transportBytes: unknown, transportExecutionBytes: unknown,
    contracts: unknown, retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: number, _arg1: unknown, _arg2: unknown, _arg3: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelsSourceFreeComponentModule(parent: unknown, input: unknown,
    request: unknown, compiled: unknown, definition: unknown, compilation: unknown,
    contracts: unknown, retainedOutput: boolean, queryTime: unknown,
    construct: (_arg0: number, _arg1: unknown, _arg2: unknown, _arg3: (_arg0: unknown) => unknown) => unknown): unknown;
  clientProgramPrepareRequestModelsSourceFreePlan(parent: unknown, input: unknown, original: unknown,
    request: unknown, compiled: unknown, definition: unknown, occurrences: unknown, graphs: unknown,
    selected: unknown): unknown;
  clientProgramPrepareRequestNodeModelCapturePlan(parent: unknown, input: unknown, original: unknown,
    request: unknown, compiled: unknown, definition: unknown, occurrence: unknown, graph: unknown,
    selected: unknown, layout: unknown, installation: unknown, runtimeArtifactCid: string,
    layoutArtifactCid: string, probability: unknown, modelRetainedBytes: bigint,
    modelExecutionBytes: bigint, maxReservations: number, maxHoldings: number, maxDelegations: number,
    bootstrapRetainedBytes: bigint, bootstrapExecutionBytes: bigint): unknown;
  clientProgramPrepareRequestNodeModelSourceFreePlan(parent: unknown, input: unknown,
    original: unknown, request: unknown, compiled: unknown, definition: unknown, occurrence: unknown,
    graph: unknown, selected: unknown, layout: unknown, installation: unknown,
    runtimeArtifactCid: string, layoutArtifactCid: string, probability: unknown,
    modelRetainedBytes: bigint, modelExecutionBytes: bigint, maxReservations: number,
    maxHoldings: number, maxDelegations: number, bootstrapRetainedBytes: bigint,
    bootstrapExecutionBytes: bigint): unknown;
  clientProgramPrepareRequestNodeModelsSourceFreePlan(parent: unknown, input: unknown,
    original: unknown, request: unknown, compiled: unknown, definition: unknown, occurrences: unknown,
    graphs: unknown, selected: unknown, project: ModelGroupProjection): unknown;
  clientProgramPrepareRequestSerializationCompilation(parent: unknown, input: unknown,
    component: unknown, contracts: unknown): unknown;
  clientProgramPrepareRequestSerializationPlan(parent: unknown, input: unknown, request: unknown,
    compiled: unknown, definition: unknown, maxRows: number, maxWork: number, maxEntries: number,
    maxValueBytes: number, maxValueNodes: number, maxValueDepth: number, maxFrames: number,
    workspace: unknown): unknown;
  clientProgramPrepareRequestWholeSerializationPlan(parent: unknown, input: unknown, request: unknown,
    compiled: unknown, definition: unknown, maxRows: number, maxWork: number, maxEntries: number,
    maxValueBytes: number, maxValueNodes: number, maxValueDepth: number, maxFrames: number,
    workspace: unknown, sourcePlan: unknown): unknown;
  clientProgramRequestModelRecoveryLedger(parent: unknown, input: unknown, request: unknown,
    definition: unknown): unknown;
  clientProgramRequestModelRecoverySourceCoordinates(parent: unknown, input: unknown,
    request: unknown, definition: unknown, prepared: unknown): unknown;
  clientProgramRequestModelRecoveryUsageIsolated(parent: unknown, input: unknown, request: unknown,
    definition: unknown, captured: unknown): boolean;
  clientProgramReserveRequestModelRecoveryMaterials(parent: unknown, input: unknown, request: unknown,
    definition: unknown, count: number, wireAt: (_arg0: number) => string, containers: number): unknown;
}>;

type ModelRecoveryArguments = Parameters<CommonModelPreparationBindings['clientProgramPrepareRequestModelRecoveryReadScopes']> |
  Parameters<CommonModelPreparationBindings['clientProgramPrepareRequestModelRecoveryReadScopesWithQuantities']>;

type ModelPreparationPorts = Readonly<{
  compiledRunTokens: WeakMap<object, unknown>;
  serializationPlanTokens: WeakMap<object, unknown>;
  token: (value: unknown) => unknown;
  compiledRunResult: (value: unknown, code: string) => unknown;
  currentControl: () => Readonly<{
    checkClientCompiledRunOwner(compiled: unknown, prepared: unknown): unknown;
    checkClientCompiledRunDefinition(compiled: unknown, definition: unknown): unknown;
  }>;
}>;

export function createModelPreparationControls(moon: CommonModelPreparationBindings, {
  compiledRunTokens, serializationPlanTokens, token, compiledRunResult, currentControl,
}: ModelPreparationPorts) {
  return {
    prepareCheckedClientRequestSerializationCompilation(parent: unknown, input: unknown, graph: unknown,
      contracts: unknown) {
      const original = serializationPlanTokens.get(graph as object);
      if (original === undefined) throw new TypeError('Foreign Content compilation graph');
      const compile = moon.clientProgramPrepareRequestSerializationCompilation;
      if (typeof compile !== 'function') throw new TypeError('Request Content compiler unavailable');
      // The actual typed constructor checks this SAME parent/input, checked
      // graph and contracts. No graph token or rebuilt compilation escapes.
      return compiledRunResult(Reflect.apply(compile, moon, [parent, input, original, contracts] satisfies Parameters<typeof compile>),
        'RunHostTaskCompilationRejected');
    },
    prepareCheckedClientRequestKeyedSerializationCompilation(parent: unknown, input: unknown,
      selected: unknown, graph: unknown) {
      const original = serializationPlanTokens.get(graph as object);
      if (original === undefined) throw new TypeError('Foreign Content compilation graph');
      const compile = moon.clientProgramPrepareRequestKeyedSerializationCompilation;
      if (typeof compile !== 'function') throw new TypeError('Request keyed Content compiler unavailable');
      return compiledRunResult(Reflect.apply(compile, moon, [parent, input, selected, original] satisfies Parameters<typeof compile>),
        'RunHostTaskCompilationRejected');
    },
    prepareCheckedClientRequestSerializationPlan(parent: unknown, input: unknown, request: unknown,
      compiled: unknown, definition: unknown, limits: SerializationLimits, workspace: unknown, sourcePlan?: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'serialization') {
        throw new TypeError('Foreign Client compiled Content preparation');
      }
      if (sourcePlan !== undefined) {
        const prepare = moon.clientProgramPrepareRequestWholeSerializationPlan;
        if (typeof prepare !== 'function') throw new TypeError('Request acquired Content Plan unavailable');
        return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition),
          limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
          limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, workspace, sourcePlan] satisfies Parameters<typeof prepare>));
      }
      const prepare = moon.clientProgramPrepareRequestSerializationPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request Content Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition),
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, workspace] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelSerializationPlan(parent: unknown, input: unknown, request: unknown,
      compiled: unknown, definition: unknown, limits: SerializationLimits, workspace: unknown,
      queryTime: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSerializationPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request Model Content Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition),
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, workspace, queryTime] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientEffectModelDemand(prepared: unknown, compiled: unknown, compilation: unknown,
      definition: unknown, occurrence: unknown, graph: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      // The nominal JS holder is not the native compiled Run. Unwrap only
      // its existing private association; Core binds the complete original
      // Effect/compilation/definition/occurrence tuple without another issuer.
      return checked(moon.clientProgramInstalledEffectModelDemandPrepare(
        prepared, value, compilation, token(definition), occurrence, graph));
    },
    prepareCheckedClientNodeEffectModelDemand(prepared: unknown, compiled: unknown, compilation: unknown,
      definition: unknown, occurrence: unknown, graph: unknown, selected: unknown,
      installation: ModelReadInstallation) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const node = installation.nodeInstallation, census = installation.bootstrap;
      return checked(moon.clientProgramInstalledNodeEffectModelDemandPrepare(
        prepared, value, compilation, token(definition), occurrence, graph, selected,
        node.layout, node.installation, node.runtimeArtifactCid as string, node.layoutArtifactCid as string,
        node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations,
        census.bootstrapRetainedBytes, census.bootstrapExecutionBytes));
    },
    prepareCheckedClientRequestModelSourceFreeModule(parent: unknown, input: unknown, request: unknown,
      compiled: unknown, definition: unknown, compilation: unknown, contracts: unknown,
      retainedOutput: boolean, queryTime: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSourceFreeModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, contracts, retainedOutput, queryTime] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelSourceFreeComponentModule(parent: unknown, input: unknown,
      request: unknown, compiled: unknown, definition: unknown, compilation: unknown, contracts: unknown,
      retainedOutput: boolean, queryTime: unknown, construct: ModelComponentConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSourceFreeComponentModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model component constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value,
        token(definition), compilation, contracts, retainedOutput, queryTime, construct] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelsSourceFreeComponentModule(parent: unknown, input: unknown,
      request: unknown, compiled: unknown, definition: unknown, compilation: unknown, contracts: unknown,
      retainedOutput: boolean, queryTime: unknown, construct: ModelGroupConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsSourceFreeComponentModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model components constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value,
        token(definition), compilation, contracts, retainedOutput, queryTime, construct] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelsProviderComponentCaptureModule(parent: unknown, input: unknown,
      request: unknown, compiled: unknown, definition: unknown, compilation: unknown, declarations: unknown,
      providers: unknown, query: string, evidence: string, transport: unknown, scratch: unknown,
      contracts: unknown, retainedOutput: boolean, queryTime: unknown, construct: ModelGroupConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsProviderComponentCaptureModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model components constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value,
        token(definition), compilation, declarations, providers, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelCaptureModule(parent: unknown, input: unknown, request: unknown,
      compiled: unknown, definition: unknown, compilation: unknown, declarations: unknown, query: string,
      evidence: string, transport: unknown, scratch: unknown, contracts: unknown, retainedOutput: boolean,
      queryTime: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, declarations, query, evidence,
        transport, scratch, contracts, retainedOutput, queryTime] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelComponentCaptureModule(parent: unknown, input: unknown, request: unknown,
      compiled: unknown, definition: unknown, compilation: unknown, declarations: unknown, query: string,
      evidence: string, transport: unknown, scratch: unknown, contracts: unknown, retainedOutput: boolean,
      queryTime: unknown, construct: ModelComponentConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelComponentCaptureModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model component constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation,
        declarations, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelWholeInputsComponentCaptureModule(parent: unknown, input: unknown,
      request: unknown, compiled: unknown, definition: unknown, compilation: unknown, wholeSources: unknown,
      query: string, evidence: string, transport: unknown, scratch: unknown, contracts: unknown,
      retainedOutput: boolean, queryTime: unknown, construct: ModelComponentConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelWholeInputsComponentCaptureModule;
      if (typeof prepare !== 'function' || typeof construct !== 'function') {
        throw new TypeError('Request Model component constructor unavailable');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation,
        wholeSources, query, evidence, transport, scratch, contracts, retainedOutput, queryTime, construct] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelProviderCaptureModule(parent: unknown, input: unknown, request: unknown,
      compiled: unknown, definition: unknown, compilation: unknown, declaration: unknown, provider: unknown,
      query: string, evidence: string, transport: bigint, scratch: bigint, contracts: unknown,
      retainedOutput: boolean, queryTime: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelProviderCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, declaration, provider, query, evidence,
        transport, scratch, contracts, retainedOutput, queryTime] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelProviderComponentCaptureModule(parent: unknown, input: unknown,
      request: unknown, compiled: unknown, definition: unknown, compilation: unknown, declaration: unknown,
      provider: unknown, query: string, evidence: string, transport: bigint, scratch: bigint,
      contracts: unknown, retainedOutput: boolean, queryTime: unknown, bindOriginal: ModelComponentConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelProviderComponentCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, declaration, provider, query, evidence,
        transport, scratch, contracts, retainedOutput, queryTime, bindOriginal] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelDuckDBComponentCaptureModule(parent: unknown, input: unknown,
      request: unknown, compiled: unknown, definition: unknown, compilation: unknown, sourceRef: string,
      schema: string, table: string, query: string, evidence: string, receipts: string, transport: bigint,
      scratch: bigint, contracts: unknown, retainedOutput: boolean, queryTime: unknown,
      bindOriginal: ModelComponentConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelDuckDBComponentCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, sourceRef, schema, table, query, evidence, receipts,
        transport, scratch, contracts, retainedOutput, queryTime, bindOriginal] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelsDuckDBComponentCaptureModule(parent: unknown, input: unknown,
      request: unknown, compiled: unknown, definition: unknown, compilation: unknown, sourceRef: string,
      schema: string, table: string, query: string, evidence: string, receipts: string, transport: bigint,
      scratch: bigint, contracts: unknown, retainedOutput: boolean, queryTime: unknown,
      bindOriginal: ModelGroupConstructor) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsDuckDBComponentCaptureModule;
      if (typeof prepare !== 'function') throw new TypeError('Request Model module constructor unavailable');
      // Same existing private originals, never the wire/identity facade.
      return checked(Reflect.apply(prepare, moon, [parent, input, request, value, token(definition), compilation, sourceRef, schema, table, query, evidence, receipts,
        transport, scratch, contracts, retainedOutput, queryTime, bindOriginal] satisfies Parameters<typeof prepare>));
    },
    reserveCheckedClientRequestModelRecoveryMaterials(parent: unknown, input: unknown, request: unknown,
      definition: unknown, count: number, wireAt: (index: number) => string, containers: number) {
      const reserve = moon.clientProgramReserveRequestModelRecoveryMaterials;
      if (typeof reserve !== 'function') throw new TypeError('Installed Model recovery material reservation unavailable');
      return checked(Reflect.apply(reserve, moon, [parent, input, request, token(definition), count, wireAt, containers] satisfies Parameters<typeof reserve>));
    },
    checkedClientRequestModelRecoverySourceCoordinates(parent: unknown, input: unknown, request: unknown,
      definition: unknown, prepared: unknown) {
      const select = moon.clientProgramRequestModelRecoverySourceCoordinates;
      if (typeof select !== 'function') throw new TypeError('Installed Model recovery Source unavailable');
      return checked(Reflect.apply(select, moon, [parent, input, request, token(definition), prepared] satisfies Parameters<typeof select>));
    },
    checkedClientRequestModelRecoveryLedger(parent: unknown, input: unknown, request: unknown,
      definition: unknown) {
      const borrow = moon.clientProgramRequestModelRecoveryLedger;
      if (typeof borrow !== 'function') throw new TypeError('Installed Model recovery Ledger unavailable');
      return checked(Reflect.apply(borrow, moon, [parent, input, request, token(definition)] satisfies Parameters<typeof borrow>));
    },
    checkedClientRequestModelRecoveryUsageIsolated(parent: unknown, input: unknown, request: unknown,
      definition: unknown, dag: unknown) {
      const inspect = moon.clientProgramRequestModelRecoveryUsageIsolated;
      if (typeof inspect !== 'function') throw new TypeError('Installed Model recovery usage unavailable');
      return Reflect.apply(inspect, moon, [parent, input, request, token(definition), dag] satisfies Parameters<typeof inspect>);
    },
    openCheckedClientRequestModelRecoveryHost(parent: unknown, input: unknown, request: unknown,
      definition: unknown, prepared: unknown, sources: unknown, contracts: unknown, values: string,
      fragment: string | undefined, ordered: string | undefined, providers: unknown) {
      const open = moon.clientProgramOpenRequestModelRecoveryHost;
      if (typeof open !== 'function') throw new TypeError('Installed Model recovery Host unavailable');
      return checked(Reflect.apply(open, moon, [parent, input, request, token(definition), prepared,
        sources, contracts, values, fragment, ordered, providers] satisfies Parameters<typeof open>));
    },
    prepareCheckedClientRequestModelRecoveryReadScopes(parent: unknown, input: unknown, request: unknown,
      definition: unknown, prepared: unknown, compiled: unknown, graphs: unknown, bounds: unknown,
      modelRetained: unknown, modelExecution: unknown, readRetained: unknown, readExecution: unknown,
      maxReservations: number, maxHoldings: number, maxDelegations: number,
      quantityLimits: ModelQuantities | undefined) {
      currentControl().checkClientCompiledRunOwner(compiled, prepared);
      currentControl().checkClientCompiledRunDefinition(compiled, definition);
      if ((compiled as CompiledRunView).kind !== 'infer') throw new TypeError('Foreign Client compiled Infer preparation');
      const value = compiledRunTokens.get(compiled as object);
      const prepare = moon[quantityLimits === undefined ? 'clientProgramPrepareRequestModelRecoveryReadScopes'
        : 'clientProgramPrepareRequestModelRecoveryReadScopesWithQuantities'];
      if (typeof prepare !== 'function') throw new TypeError('Installed Model recovery Scope unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, request, token(definition), prepared, value,
        graphs, bounds, modelRetained, modelExecution, readRetained, readExecution,
        maxReservations, maxHoldings, maxDelegations,
        ...(quantityLimits === undefined ? [] as const
          : [quantityLimits.tokens, quantityLimits.costUnits, quantityLimits.durationMs] as const),
      ] satisfies ModelRecoveryArguments));
    },
    prepareCheckedClientRequestModelsSourceFreePlan(parent: unknown, input: unknown, original: unknown,
      request: unknown, compiled: unknown, definition: unknown, occurrences: unknown, graphs: unknown,
      selected: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrences, graphs, selected] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestNodeModelsSourceFreePlan(parent: unknown, input: unknown, original: unknown,
      request: unknown, compiled: unknown, definition: unknown, occurrences: unknown, graphs: unknown,
      selected: unknown, memberAt: (index: number) => ModelGroupMember) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestNodeModelsSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Node Model group Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrences, graphs, selected, (index: number, check: CheckModelGroupMember) => {
          // Common checks the original at this index after reserving the Plan
          // projection. The Host borrows the selected installation in place.
          const member = memberAt(index), installation = member.originalReadInstallation;
          const quantities = member.selection.quantityCapacity.limits;
          const node = installation.nodeInstallation, census = installation.bootstrap;
          return check(node.layout, node.installation, node.runtimeArtifactCid as string, node.layoutArtifactCid as string,
            node.probability, installation.modelRetainedBytes, installation.modelExecutionBytes,
            census.maxReservations, census.maxHoldings, census.maxDelegations,
            census.bootstrapRetainedBytes, census.bootstrapExecutionBytes,
            quantities.tokens, quantities.costUnits, quantities.durationMs);
        }] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelsCapturePlan(parent: unknown, input: unknown, original: unknown,
      request: unknown, compiled: unknown, definition: unknown, occurrences: unknown, graphs: unknown,
      selected: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelsCapturePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrences, graphs, selected] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelSourceFreePlan(parent: unknown, input: unknown, original: unknown,
      request: unknown, compiled: unknown, definition: unknown, occurrence: unknown, graph: unknown,
      selected: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      // These are the original module, selected Limits and Run tokens. The
      // existing typed constructor checks their complete tuple; this binding
      // issues no Scope/Run and does not select bounds or compile again.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestModelCapturePlan(parent: unknown, input: unknown, original: unknown,
      request: unknown, compiled: unknown, definition: unknown, occurrence: unknown, graph: unknown,
      selected: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestModelCapturePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestNodeModelSourceFreePlan(parent: unknown, input: unknown, original: unknown,
      request: unknown, compiled: unknown, definition: unknown, occurrence: unknown, graph: unknown,
      selected: unknown, installation: ModelReadInstallation) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestNodeModelSourceFreePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Node Model Plan unavailable');
      const node = installation.nodeInstallation, census = installation.bootstrap;
      // SAME immutable installed declaration and opaque selected bounds. The
      // typed constructor validates layout/originals and the Request admits
      // these actual extents before Scope/read; no JS Ledger is constructed.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected, node.layout, node.installation,
        node.runtimeArtifactCid as string, node.layoutArtifactCid as string, node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations,
        census.bootstrapRetainedBytes, census.bootstrapExecutionBytes] satisfies Parameters<typeof prepare>));
    },
    prepareCheckedClientRequestNodeModelCapturePlan(parent: unknown, input: unknown, original: unknown,
      request: unknown, compiled: unknown, definition: unknown, occurrence: unknown, graph: unknown,
      selected: unknown, installation: ModelReadInstallation) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const prepare = moon.clientProgramPrepareRequestNodeModelCapturePlan;
      if (typeof prepare !== 'function') throw new TypeError('Installed Node Model Plan unavailable');
      const node = installation.nodeInstallation, census = installation.bootstrap;
      // SAME immutable installed declaration and opaque selected bounds. The
      // typed constructor validates layout/originals and the Request admits
      // these actual extents before Scope/read; no JS Ledger is constructed.
      return checked(Reflect.apply(prepare, moon, [parent, input, original, request, value,
        token(definition), occurrence, graph, selected, node.layout, node.installation,
        node.runtimeArtifactCid as string, node.layoutArtifactCid as string, node.probability,
        installation.modelRetainedBytes, installation.modelExecutionBytes,
        census.maxReservations, census.maxHoldings, census.maxDelegations,
        census.bootstrapRetainedBytes, census.bootstrapExecutionBytes] satisfies Parameters<typeof prepare>));
    },
    bindCheckedClientMockModelCapturePlan(original: unknown, compiled: unknown, definition: unknown,
      occurrence: unknown, graph: unknown, selected: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      const bind = moon.clientProgramInstalledMockModelCapturePlanBind;
      if (typeof bind !== 'function') throw new TypeError('Installed Model Plan unavailable');
      return checked(Reflect.apply(bind, moon, [original, value, token(definition),
        occurrence, graph, selected] satisfies Parameters<typeof bind>));
    },
    checkedClientMockModelRunRequirements(prepared: unknown, compiled: unknown, definition: unknown,
      occurrence: unknown, graph: unknown, declarations: unknown, query: string, evidence: string,
      transport: unknown, scratch: unknown, registry: unknown, values: string, fragment: string | undefined,
      ordered: string | undefined) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as CompiledRunView).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInstalledMockModelManagedRunRequirements(
        prepared, value, token(definition), occurrence, graph, declarations,
        query, evidence, transport, scratch, registry, values, fragment, ordered));
    },
  };
}
