import {runtimeField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';

type WireLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Quantity = Readonly<{tokens: bigint; costUnits: bigint; durationMs: bigint}>;
type QuantityCapacity = Readonly<{limits: Quantity; perAttempt: Quantity}>;
type InferReadBudget = Readonly<{readRetainedBytes: bigint; readExecutionBytes: bigint}>;
type BootstrapBudget = Readonly<{
  quantityCapacity?: QuantityCapacity;
  bootstrapRetainedBytes: bigint;
  bootstrapExecutionBytes: bigint;
  maxReservations: number;
  maxHoldings: number;
  maxDelegations: number;
}>;
type SelectedLayout = Readonly<{
  layout?: unknown;
  installation: unknown;
  runtimeArtifactCid: string;
  layoutArtifactCid: string;
  probability?: unknown;
}>;
type RetainedSnapshot = Readonly<{binding: string; descriptorWire: string; rows: unknown}>;
type Evidence = Readonly<{name: string; identity: string; wire: string}>;

// Original Core handles and unchecked Result variants remain opaque here.
type CommonInferOriginalReadBindings = Readonly<{
  clientProgramAdvanceInferNodeReadState(value: unknown, compiled: unknown, definition: unknown,
    graph: unknown, quantum: number): unknown;
  clientProgramBeginInferOriginalReadScope(compiled: unknown, definition: unknown, graph: unknown,
    quantityCapacity: unknown, retainedBytes: bigint, executionBytes: bigint,
    maxReservations: number, maxHoldings: number, maxDelegations: number): unknown;
  clientProgramCheckInferOriginalParkedStorageOrigin(scope: unknown, compiled: unknown,
    definition: unknown, graph: unknown, park: unknown, document: unknown, layout: unknown,
    installation: unknown, runtimeArtifactCid: string, layoutArtifactCid: string,
    probability: unknown, storage: unknown): unknown;
  clientProgramCheckInferOriginalPreRestoreOrigin(compiled: unknown, definition: unknown,
    graph: unknown, document: unknown, layout: unknown, installation: unknown,
    runtimeArtifactCid: string, layoutArtifactCid: string, probability: unknown): unknown;
  clientProgramClaimInferNodePreparationLayout(read: unknown, compiled: unknown, definition: unknown,
    graph: unknown, layout: unknown, installation: unknown, runtimeArtifactCid: string,
    layoutArtifactCid: string, probability: unknown): unknown;
  clientProgramClaimInferOriginalPreparation(read: unknown, compiled: unknown, definition: unknown,
    graph: unknown, retainedBytes: bigint, executionBytes: bigint): unknown;
  clientProgramFinishInferNodeReadState(value: unknown, compiled: unknown, definition: unknown,
    graph: unknown): unknown;
  clientProgramFinishInferOriginalReadScope(scope: unknown, compiled: unknown, definition: unknown,
    graph: unknown, originalRunCleanupComplete: boolean): unknown;
  clientProgramInferNodeReadStatePoll(poll: unknown): readonly [string, number, unknown];
  clientProgramInferNodeReadStateRead(value: unknown): unknown;
  clientProgramInferOriginalReadScopeLive(scope: unknown, compiled: unknown, definition: unknown,
    graph: unknown): boolean;
  clientProgramInferOriginalResourceOriginField(scope: unknown, compiled: unknown,
    definition: unknown, graph: unknown, layout: unknown, installation: unknown,
    runtimeArtifactCid: string, layoutArtifactCid: string, probability: unknown, storage: unknown,
    field: string): unknown;
  clientProgramInstalledEffectManagedRestoredModelHostOpen(owner: unknown, bound: unknown,
    sources: unknown, held: unknown, compiled: unknown, definition: unknown, graph: unknown): unknown;
  clientProgramInstalledEffectManagedRestoredModelsHostOpen(owner: unknown, bound: unknown,
    sources: unknown, held: unknown, compiled: unknown, definition: unknown, graphs: unknown): unknown;
  clientProgramPrepareInferNodeReadLayout(scope: unknown, compiled: unknown, definition: unknown,
    graph: unknown, layout: unknown, installation: unknown, runtimeArtifactCid: string,
    layoutArtifactCid: string, probability: unknown): unknown;
  clientProgramPrepareInferNodeReadState(scope: unknown, compiled: unknown, definition: unknown,
    graph: unknown, layout: unknown, installation: unknown, runtimeArtifactCid: string,
    layoutArtifactCid: string, probability: unknown, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramPrepareInferOriginalRead(scope: unknown, compiled: unknown, definition: unknown,
    graph: unknown, retainedBytes: bigint, executionBytes: bigint): unknown;
  clientProgramRestoredInferSourceOriginals(scope: unknown, compiled: unknown, definition: unknown,
    occurrence: unknown, graph: unknown): unknown;
  clientProgramSettleInferNodeReadState(value: unknown, compiled: unknown, definition: unknown,
    graph: unknown, physicalCleanupComplete: boolean): unknown;
  clientProgramSettleInferOriginalReadPreparation(read: unknown, compiled: unknown,
    definition: unknown, graph: unknown, physicalCleanupComplete: boolean): unknown;
  clientProgramStartOriginalComposedInferExecution(occurrence: unknown, graph: unknown,
    prefix: unknown, inputs: unknown, provider: unknown, compiled: unknown, definition: unknown,
    consumer: unknown, readRetainedBytes: bigint, readExecutionBytes: bigint,
    modelRetainedBytes: bigint, modelExecutionBytes: bigint, sources: unknown, inputBodyRead: unknown): unknown;
  clientProgramStartOriginalInferExecution(prepared: unknown, step: number, graph: unknown,
    sequenceContracts: unknown, values: string, provider: unknown, compiled: unknown,
    definition: unknown, consumer: unknown, readRetainedBytes: bigint, readExecutionBytes: bigint,
    modelRetainedBytes: bigint, modelExecutionBytes: bigint, fragment: string, ordered: string): unknown;
  clientProgramStartOriginalRestoredComposedInferExecution(occurrence: unknown, graph: unknown,
    prefix: unknown, provider: unknown, binding: string, descriptorWire: string, rows: unknown,
    custodyAvailable: () => boolean, savedScope: unknown, compiled: unknown, definition: unknown,
    consumer: unknown, readRetainedBytes: bigint, readExecutionBytes: bigint,
    modelRetainedBytes: bigint, modelExecutionBytes: bigint, referenceIssuer: unknown,
    inputBodyRead: unknown): unknown;
  clientProgramStopInferNodeReadState(value: unknown, scope: unknown, compiled: unknown,
    definition: unknown, graph: unknown): unknown;
  clientProgramStopInferOriginalReadPreparation(scope: unknown, read: unknown, compiled: unknown,
    definition: unknown, graph: unknown): unknown;
  strategyRunEvidenceIdentity(value: unknown): string;
}>;

// Translate the installed Node envelope only; Common owns contract ceilings.
function inferQuantityCapacity(value: QuantityCapacity | undefined) {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== 'limits,perAttempt' ||
      (['limits', 'perAttempt'] as const).some(scope => {
        const amount = value[scope];
        return amount === null || typeof amount !== 'object' || Array.isArray(amount) ||
          Object.keys(amount).sort().join(',') !== 'costUnits,durationMs,tokens' ||
          Object.values(amount).some(quantity => typeof quantity !== 'bigint' ||
            quantity < 0n || quantity > BigInt(Number.MAX_SAFE_INTEGER));
      })) {
    throw new TypeError('InvalidInstalledInferQuantityCapacity');
  }
  return {
    limits: {tokens: value.limits.tokens, cost_units: value.limits.costUnits,
      duration_ms: value.limits.durationMs},
    per_attempt: {tokens: value.perAttempt.tokens, cost_units: value.perAttempt.costUnits,
      duration_ms: value.perAttempt.durationMs},
  };
}

type InferOriginalReadPorts = Readonly<{
  compiledRunTokens: WeakMap<object, unknown>;
  modelOriginalDocumentTokens: WeakMap<object, unknown>;
  token: (value: unknown) => unknown;
  evidenceToken: (value: unknown) => unknown;
  inspectEvidence: (value: unknown) => Evidence;
  issuanceLimits: (limits: WireLimits, label: string) => WireLimits;
}>;

export function createInferOriginalReadControls(moon: CommonInferOriginalReadBindings, {
  compiledRunTokens, modelOriginalDocumentTokens, token, evidenceToken, inspectEvidence, issuanceLimits,
}: InferOriginalReadPorts) {
  return {
    prepareCheckedClientInferOriginalRead(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown, budget: InferReadBudget) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramPrepareInferOriginalRead(scope, value, token(definition),
        graph, budget.readRetainedBytes, budget.readExecutionBytes));
    },
    // Installation-only original bootstrap: caller custody must keep this
    // same scope on failure/recovery, never issue a replacement Ledger.
    // Initial allocation and the full preset projection require pre-funding
    // by the trusted installation; supplied numbers do not prove a layout.
    beginCheckedClientInferOriginalReadScope(compiled: unknown, definition: unknown, graph: unknown,
    {quantityCapacity, bootstrapRetainedBytes, bootstrapExecutionBytes, maxReservations, maxHoldings, maxDelegations}: BootstrapBudget) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramBeginInferOriginalReadScope(value,
        token(definition), graph, inferQuantityCapacity(quantityCapacity), bootstrapRetainedBytes,
        bootstrapExecutionBytes, maxReservations, maxHoldings, maxDelegations));
    },
    checkedClientInferOriginalReadScopeLive(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer' ||
          typeof moon.clientProgramInferOriginalReadScopeLive !== 'function') {
        throw new TypeError('InferTrustedRuntimeScopeUnavailable');
      }
      // This lifetime observation neither exposes a Ledger nor substitutes
      // for allocation/current authority/egress or confirmed park invalidation.
      return moon.clientProgramInferOriginalReadScopeLive(scope, value,
        token(definition), graph) === true;
    },
    prepareCheckedClientInferNodeReadLayout(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown,
    {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}: SelectedLayout) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramPrepareInferNodeReadLayout(scope, value,
        token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    // Data-only origin selection from the original checked Owner, before
    // park. Storage must be the same actual port's rechecked binding evidence;
    // matching strings/configuration cannot substitute for its opaque custody.
    checkedClientInferOriginalResourceOriginField(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown,
    {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}: SelectedLayout,
    storage: unknown, field: string) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInferOriginalResourceOriginField(scope,
        value, token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability, evidenceToken(storage), field));
    },
    checkCheckedClientInferOriginalParkedStorageOrigin(compiled: unknown, definition: unknown,
    graph: unknown, scope: unknown, park: unknown, document: unknown,
    {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}: SelectedLayout,
    storage: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const original = modelOriginalDocumentTokens.get(document as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer' || original === undefined) {
        throw new TypeError('Foreign Client original Model document');
      }
      return checked(moon.clientProgramCheckInferOriginalParkedStorageOrigin(scope,
        value, token(definition), graph, park, original, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability, evidenceToken(storage)));
    },
    // DATA-only comparison before a Scope exists. The existing Common Owner
    // reads expected origins from the checked Run/Plan, not this document.
    // Storage custody, funding and atomic original admission remain separate.
    checkCheckedClientInferOriginalPreRestoreOrigin(compiled: unknown, definition: unknown, graph: unknown,
    document: unknown, selected: SelectedLayout) {
      const value = compiledRunTokens.get(compiled as object);
      const original = modelOriginalDocumentTokens.get(document as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer' || original === undefined) {
        throw new TypeError('Foreign Client original Model document');
      }
      const originalDefinition = token(definition);
      if (typeof moon.clientProgramCheckInferOriginalPreRestoreOrigin !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      const {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability} = selected;
      return checked(moon.clientProgramCheckInferOriginalPreRestoreOrigin(value,
        originalDefinition, graph, original, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    // Explicit alternative to the normal descriptor issuer, not a fallback.
    // Bootstrap must already cover the dedicated Writer and finish-text borrow.
    prepareCheckedClientInferNodeReadState(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown,
    {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}: SelectedLayout,
    limits: WireLimits) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      issuanceLimits(limits, 'Original Model state Writer');
      if ((['maxWireBytes', 'maxNodes', 'maxDepth'] as const).some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 0 || limits[key] > 2147483647) ||
        limits.maxNodes === 0) {
        throw new TypeError('Invalid original Model state Writer limits');
      }
      return checked(moon.clientProgramPrepareInferNodeReadState(scope, value,
        token(definition), graph, layout, installation, runtimeArtifactCid,
        layoutArtifactCid, probability, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    originalClientInferNodeReadStateRead(writer: unknown) {
      return checked(moon.clientProgramInferNodeReadStateRead(writer));
    },
    advanceCheckedClientInferNodeReadState(compiled: unknown, definition: unknown, graph: unknown,
    writer: unknown, quantum: number) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647) {
        throw new TypeError('Invalid original Model state Writer quantum');
      }
      const poll = moon.clientProgramInferNodeReadStatePoll(
        moon.clientProgramAdvanceInferNodeReadState(writer, value, token(definition), graph, quantum));
      return Object.freeze({kind: runtimeField(poll, 0) as typeof poll[0],
        work: runtimeField(poll, 1) as typeof poll[1], issue: runtimeField(poll, 2)});
    },
    finishCheckedClientInferNodeReadState(compiled: unknown, definition: unknown, graph: unknown,
    writer: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramFinishInferNodeReadState(writer, value, token(definition), graph));
    },
    stopCheckedClientInferNodeReadState(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown, writer: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStopInferNodeReadState(writer, scope, value, token(definition), graph));
    },
    settleCheckedClientInferNodeReadState(compiled: unknown, definition: unknown, graph: unknown,
    writer: unknown, physicalCleanupComplete: boolean) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof physicalCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original read cleanup observation');
      }
      return checked(moon.clientProgramSettleInferNodeReadState(writer, value,
        token(definition), graph, physicalCleanupComplete));
    },
    // Do not derive whole-Run cleanup from read refusal, AbortSignal or a
    // saved response. The original census also checks every live child.
    finishCheckedClientInferOriginalReadScope(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown, originalRunCleanupComplete: boolean) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof originalRunCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original Run cleanup observation');
      }
      return checked(moon.clientProgramFinishInferOriginalReadScope(scope,
        value, token(definition), graph, originalRunCleanupComplete)) as boolean;
    },
    settleCheckedClientInferOriginalReadPreparation(compiled: unknown, definition: unknown, graph: unknown,
    read: unknown, physicalCleanupComplete: boolean) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      if (typeof physicalCleanupComplete !== 'boolean') {
        throw new TypeError('Invalid original read cleanup observation');
      }
      return checked(moon.clientProgramSettleInferOriginalReadPreparation(read,
        value, token(definition), graph, physicalCleanupComplete));
    },
    stopCheckedClientInferOriginalReadPreparation(compiled: unknown, definition: unknown, graph: unknown,
    scope: unknown, read: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStopInferOriginalReadPreparation(scope,
        read, value, token(definition), graph));
    },
    claimCheckedClientInferOriginalComposedPreparation(compiled: unknown, definition: unknown,
    graph: unknown, read: unknown, readRetainedBytes: bigint, readExecutionBytes: bigint) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramClaimInferOriginalPreparation(read,
        value, token(definition), graph, readRetainedBytes, readExecutionBytes));
    },
    startCheckedClientOriginalComposedInferExecution(compiled: unknown, definition: unknown,
    occurrence: unknown, graph: unknown, prefix: unknown, inputs: unknown, provider: unknown,
    consumer: unknown, readRetainedBytes: bigint, readExecutionBytes: bigint, modelRetainedBytes: bigint,
    modelExecutionBytes: bigint, sources: unknown, inputBodyRead: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalComposedInferExecution(
        occurrence, graph, prefix, inputs, provider, value, token(definition),
        consumer, readRetainedBytes, readExecutionBytes, modelRetainedBytes,
        modelExecutionBytes, sources, inputBodyRead));
    },
    startCheckedClientOriginalRestoredComposedInferExecution(compiled: unknown, definition: unknown,
    occurrence: unknown, graph: unknown, prefix: unknown, provider: unknown, snapshot: RetainedSnapshot,
    custodyAvailable: () => boolean, savedScope: unknown, consumer: unknown, readRetainedBytes: bigint,
    readExecutionBytes: bigint, modelRetainedBytes: bigint, modelExecutionBytes: bigint,
    referenceIssuer: unknown, inputBodyRead: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalRestoredComposedInferExecution(
        occurrence, graph, prefix, provider, snapshot.binding, snapshot.descriptorWire,
        snapshot.rows, custodyAvailable, savedScope, value, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes, modelExecutionBytes,
        referenceIssuer, inputBodyRead));
    },
    openCheckedClientInstalledRestoredModelEffectHost(compiled: unknown, definition: unknown,
    managedRun: unknown, bound: unknown, sources: unknown, heldOutput: unknown, graph: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInstalledEffectManagedRestoredModelHostOpen(
        managedRun, bound, sources, heldOutput, value, token(definition), graph));
    },
    openCheckedClientInstalledRestoredModelsEffectHost(compiled: unknown, definition: unknown,
    managedRun: unknown, bound: unknown, sources: unknown, heldOutputs: unknown, graphs: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramInstalledEffectManagedRestoredModelsHostOpen(
        managedRun, bound, sources, heldOutputs, value, token(definition), graphs));
    },
    restoredInferSourceOriginals(compiled: unknown, definition: unknown, scope: unknown, occurrence: unknown,
    graph: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return Object.freeze((checked(moon.clientProgramRestoredInferSourceOriginals(
        scope, value, token(definition), occurrence, graph)) as readonly unknown[]).map(original =>
        Object.freeze({source: inspectEvidence(runtimeField(original, 0)),
          logicalRelationCid: moon.strategyRunEvidenceIdentity(runtimeField(original, 1))})));
    },
    // Reuse the original compiled/definition token domains. A public wrapper
    // object cannot be passed as a nominal MoonBit compiled Run or contract.
    claimCheckedClientInferNodePreparationLayout(compiled: unknown, definition: unknown, graph: unknown,
    read: unknown, {layout, installation, runtimeArtifactCid, layoutArtifactCid, probability}: SelectedLayout) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramClaimInferNodePreparationLayout(read,
        value, token(definition), graph, layout, installation,
        runtimeArtifactCid, layoutArtifactCid, probability));
    },
    startCheckedClientInferOriginalPreparation(compiled: unknown, definition: unknown, prepared: unknown,
    step: number, graph: unknown, registry: unknown, values: string, provider: unknown, consumer: unknown,
    readRetainedBytes: bigint, readExecutionBytes: bigint, modelRetainedBytes: bigint,
    modelExecutionBytes: bigint, fragment: string, ordered: string) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || (compiled as Readonly<{kind?: unknown}>).kind !== 'infer') {
        throw new TypeError('Foreign Client compiled Infer preparation');
      }
      return checked(moon.clientProgramStartOriginalInferExecution(prepared,
        step, graph, registry, values, provider, value, token(definition), consumer,
        readRetainedBytes, readExecutionBytes, modelRetainedBytes,
        modelExecutionBytes, fragment, ordered));
    },
  };
}
