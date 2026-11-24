import {runtimeField, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type ContractIdentity = Readonly<{identity: string; wire: string}>;
type Contract = ContractIdentity & Readonly<{name: string; identityField: string}>;
type Evidence = ContractIdentity & Readonly<{name: string}>;
type Admission = Readonly<{kind: 'run-publication-admission'}>;
type SourceUnit = Readonly<{
  invocation: unknown;
  bodies: readonly unknown[];
  catalogBodies: readonly unknown[];
  catalogDeferred?: boolean;
}>;
type SourceContext = Readonly<{
  authorityScopeCid: string;
  dataPolicyCid: string;
  // The Node selection can be unbound. Core retains the existing validation
  // at each issuance boundary where the generated signature requires String.
  captureStartedAt?: string;
  captureCompletedAt?: string;
}>;
type CapturedSourceFacts = Readonly<Required<SourceContext> & {
  sourceRef: string;
  sourceContractCid: string;
  sourceEvidenceWire: string;
  inputLogicalWire: string;
}>;
type CapturedSource = Readonly<{
  captured: Readonly<{
    capture: Readonly<{source(): unknown}>;
    identity: unknown;
    requirement?: unknown;
    logicalInput?: unknown;
  }>;
  sourceEvidenceWire?: string;
}>;
type ProgramRetentionTimes = Readonly<{availableUntil: string; deleteBy: string; metadataDeleteBy: string}>;
type EffectRetentionSelection = ProgramRetentionTimes & Readonly<{
  retentionContractCid: string; metadataRetentionPolicyCid: string; clockContractCid: string;
}>;
type EffectDependencyOwner =
  | Readonly<{kind: 'keyed_source'; issued: unknown; parent: unknown; plan: unknown; request: unknown}>
  | Readonly<{kind: 'acquired'; issued: unknown}>
  | Readonly<{kind: 'combined_source'; issued: unknown; unit: number}>;

// The actual Common ABI retains nominal handles and unchecked Result variants.
type CommonEffectPreparationBindings = Readonly<{
  clientProgramAdmitEffectPublication(prepared: unknown, template: unknown, invocation: unknown,
    authorization: unknown, plan: unknown): unknown;
  clientProgramAllowedEffectRunAdmission(value: unknown): unknown;
  clientProgramBindInstalledEffectModelInvocation(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, compilation: unknown, admission: unknown,
    definition: unknown, compiled: unknown, binding: unknown): unknown;
  clientProgramBindInstalledEffectSourceFreeInvocation(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, admission: unknown, definition: unknown,
    issued: unknown): unknown;
  clientProgramCheckRunBinding(prepared: unknown, admission: unknown, definition: unknown): boolean;
  clientProgramCombinedEffectSourceUnitCatalogBodies(value: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramCombinedEffectSourceUnitDependencyBodies(value: unknown): unknown;
  clientProgramCombinedEffectSourceUnitInvocation(value: unknown): unknown;
  clientProgramEffectDependencyBodyCid(body: unknown): string;
  clientProgramEffectDependencyBodyJson(body: unknown): string;
  clientProgramEffectDependencyBodyKind(body: unknown): string;
  clientProgramEffectDirectSourcesPublicationInvocation(value: unknown): unknown;
  clientProgramEffectDirectSourcesPublicationObservation(value: unknown): unknown;
  clientProgramEffectKeyedCachedDependencyBodies(original: unknown, lookup: unknown,
    retention: unknown): unknown;
  clientProgramEffectKeyedSourceUnitInvocation(value: unknown): unknown;
  clientProgramEffectKeyedSourceUnitMetadataBodies(value: unknown): unknown;
  clientProgramEffectSourceFreeInvocationOriginalInvocation(value: unknown): unknown;
  clientProgramEffectSourceFreeInvocationOriginalObservation(value: unknown): unknown;
  clientProgramIssueAcquiredEffectEvidence(owner: unknown, captured: unknown, identity: unknown,
    requirement: unknown, input: unknown, observation: unknown, authorityScopeCid: string,
    dataPolicyCid: string, retention: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueAcquiredEffectEvidenceAt(owner: unknown, unit: number, captured: unknown,
    identity: unknown, requirement: unknown, input: unknown, observation: unknown,
    authorityScopeCid: string, dataPolicyCid: string, retention: unknown,
    publicationRetention: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueAcquiredLocalEffectInvocation(owner: unknown, captured: unknown,
    identity: unknown, requirement: unknown, input: unknown, observation: unknown,
    authorityScopeCid: string, dataPolicyCid: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramIssueEffectCapturedInvocation(prepared: unknown, compilation: unknown,
    admission: unknown, runDefinition: unknown, source: unknown, sourceEvidenceWire: string,
    inputLogicalWire: string, sourceRef: string, sourceContractCid: string,
    authorityScopeCid: string, dataPolicyCid: string, captureStartedAt: string,
    captureCompletedAt: string, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueEffectMultiCapturedInvocation(prepared: unknown, compilation: unknown,
    admission: unknown, runDefinition: unknown, captures: unknown, identities: unknown,
    requirements: unknown, sourceEvidenceWires: unknown, inputLogicalWires: unknown,
    authorityScopeCid: string, dataPolicyCid: string, captureStartedAt: string,
    captureCompletedAt: string, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueEffectSourceFreeInvocationOriginal(compilation: unknown, policy: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueInstalledEffectCapturedInvocation(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, compilation: unknown, admission: unknown,
    definition: unknown, source: unknown, sourceEvidence: string, inputLogical: string,
    sourceRef: string, sourceContract: string, authority: string, policy: string, started: string,
    completed: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueInstalledEffectContentInvocation(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, compilation: unknown, admission: unknown,
    definition: unknown, compiled: unknown, generation: unknown, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramIssueInstalledEffectInitialRetention(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, retentionContractCid: string, effectiveDataPolicyCid: string,
    availableUntil: string, deleteBy: string, extensionCeilingAt: string,
    metadataRetentionPolicyCid: string, metadataDeleteBy: string, clockContractCid: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueInstalledEffectKeyedInvocation(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, compilation: unknown, admission: unknown,
    definition: unknown, lookup: unknown, started: string, completed: string, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueInstalledEffectMultiCapturedInvocation(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, compilation: unknown, admission: unknown,
    definition: unknown, sources: unknown, identities: unknown, requirements: unknown,
    sourceEvidence: unknown, inputLogical: unknown, authority: string, policy: string,
    started: string, completed: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueInstalledWholeEffectSourceUnit(plan: unknown, prepared: unknown,
    request: unknown, slot: number, captured: unknown, identity: unknown, capacity: unknown,
    input: unknown, observation: unknown, authorityScopeCid: string, retention: unknown,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueOriginalEffectDirectSourcesInvocation(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, compilation: unknown, admission: unknown,
    definition: unknown, sources: unknown, identities: unknown, sourceEvidence: unknown,
    inputLogical: unknown, authority: string, policy: string, started: string, completed: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramIssueProgramInitialRetention(owner: unknown, prepared: unknown, request: unknown,
    retentionContractCid: string, effectiveDataPolicyCid: string, availableUntil: string,
    deleteBy: string, extensionCeilingAt: string, metadataRetentionPolicyCid: string,
    metadataDeleteBy: string, clockContractCid: string, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramPrepareCombinedEffectSourceUnit(publication: unknown, unit: number,
    retention: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectDirectSourcesPublication(plan: unknown, prepared: unknown,
    request: unknown, compilation: unknown, admission: unknown, definition: unknown,
    captures: unknown, identities: unknown, sources: unknown, inputs: unknown,
    authorityScopeCid: string, dataPolicyCid: string, captureStartedAt: string,
    captureCompletedAt: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectKeyedSourceUnit(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, host: unknown, lookup: unknown, retention: unknown,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectModelSourceUnit(run: unknown, plan: unknown, request: unknown,
    inputs: unknown, unit: number, retention: unknown, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectModelSourceUnitCatalog(run: unknown, plan: unknown,
    request: unknown, inputs: unknown, unit: unknown, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramPrepareInstalledEffectSourceUnitInputs(plan: unknown, prepared: unknown,
    request: unknown, compilation: unknown, admission: unknown, definition: unknown,
    captures: unknown, identities: unknown, sources: unknown, inputs: unknown,
    authorityScopeCid: string, dataPolicyCid: string, maxBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  clientProgramRebindInstalledEffectResultRetention(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, original: unknown, policy: string, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  strategyRunEvidenceJson(value: unknown): string;
}>;

type EffectPreparationPorts = Readonly<{
  admissionToken: (value: unknown) => unknown;
  token: (value: unknown) => unknown;
  evidenceToken: (value: unknown) => unknown;
  inspectAdmission: (value: unknown) => Admission;
  inspect: (value: unknown, limits?: Limits) => Contract;
  inspectEvidence: (value: unknown) => Evidence;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  captureContractLimits: (limits: Limits, label: string) => Limits;
  localEffectDependencyTokens: {set(key: object, value: EffectDependencyOwner): void};
  inferInvocationTokens: WeakMap<object, Readonly<{compiled: unknown}>>;
  compiledRunTokens: WeakMap<object, unknown>;
  serializationGenerationTokens: WeakMap<object, unknown>;
  inspectAcquiredEffectEvidence: (issued: unknown, retention: unknown, limits: Limits,
    deferCatalogs?: boolean) => SourceUnit;
}>;

export function createEffectPreparationControls(moon: CommonEffectPreparationBindings, {
  admissionToken, token, evidenceToken, inspectAdmission, inspect, inspectEvidence,
  issuanceLimits, captureContractLimits, localEffectDependencyTokens, inferInvocationTokens,
  compiledRunTokens, serializationGenerationTokens, inspectAcquiredEffectEvidence,
}: EffectPreparationPorts) {
  return {
    checkClientRunDefinitionBinding(checkedProgram: unknown, admission: unknown, definition: unknown) {
      if (typeof moon.clientProgramCheckRunBinding !== 'function' ||
          !moon.clientProgramCheckRunBinding(checkedProgram,
            admissionToken(admission), token(definition))) {
        throw new TypeError('Run Definition differs from checked Program');
      }
    },
    admitCheckedClientEffectRunPublication(checkedEffect: unknown, template: unknown, prepared: unknown,
      authorization: unknown, compiledPlan: unknown) {
      if (typeof moon.clientProgramAdmitEffectPublication !== 'function') {
        throw new TypeError('Client Effect admission is unavailable');
      }
      const admission = moon.clientProgramAdmitEffectPublication(
        checkedEffect,
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      );
      if (admission === undefined) {
        throw new TypeError('Publication evidence differs from checked Effect');
      }
      return inspectAdmission(admission);
    },
    // Inspect originals already admitted by this exact Allow/Definition owner.
    // No second evidence admission or byte/CID replacement supplies custody.
    originalCheckedClientEffectPublication(allowed: unknown, definition: unknown, limits: Limits) {
      issuanceLimits(limits, 'Original Effect publication');
      return Object.freeze({
        admission: inspectAdmission(moon.clientProgramAllowedEffectRunAdmission(allowed)),
        runDefinition: inspect(definition, limits),
      });
    },
    issueCheckedClientEffectSourceFreeInvocationOriginal(compilation: unknown, policy: string, limits: Limits) {
      issuanceLimits(limits, 'Original source-free Effect Invocation');
      const original = checked(moon.clientProgramIssueEffectSourceFreeInvocationOriginal(
        compilation, policy, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const owner = moon.clientProgramEffectSourceFreeInvocationOriginalInvocation(original);
      return Object.freeze({original, owner,
        observation: inspectEvidence(moon.clientProgramEffectSourceFreeInvocationOriginalObservation(original)),
        invocation: inspect(owner, limits)});
    },
    bindCheckedInstalledEffectSourceFreeInvocation(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, admission: unknown, definition: unknown, original: unknown): undefined {
      checked(moon.clientProgramBindInstalledEffectSourceFreeInvocation(
        parent, prepared, request, plan, host, admissionToken(admission), token(definition), original));
    },
    issueCheckedInstalledEffectKeyedInvocation(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, compilation: unknown, admission: unknown, definition: unknown,
      lookup: unknown, started: string | undefined, completed: string | undefined, limits: Limits) {
      issuanceLimits(limits, 'Original installed keyed Source Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectKeyedInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), token(definition),
        lookup, started as string, completed as string, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    prepareInstalledEffectKeyedSourceUnit(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, original: unknown, lookup: unknown, retention: unknown, limits: Limits,
      deferCatalogs = false) {
      issuanceLimits(limits, 'Original installed keyed Source Unit');
      const issued = checked(moon.clientProgramPrepareInstalledEffectKeyedSourceUnit(
        parent, prepared, request, plan, host, lookup, token(retention),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      // Borrow exactly the completed inventory. Core performs current and
      // retention-bound checks; this never exports or admits lookup DATA again.
      let cached = moon.clientProgramEffectKeyedCachedDependencyBodies(original, lookup, token(retention));
      // This actual compiled export returns boxed Option<Array<Body>>. Borrow
      // its SAME payload through the pinned binding; None never means empty.
      cached = runtimeIsBoxedSome(cached) ? runtimeField(cached, 0) : undefined;
      if (!Array.isArray(cached)) throw new TypeError('OriginalEffectKeyedInventoryUnavailable');
      const bodies = cached.map(body => Object.freeze({
        kind: moon.clientProgramEffectDependencyBodyKind(body),
        cid: moon.clientProgramEffectDependencyBodyCid(body),
        wire: moon.clientProgramEffectDependencyBodyJson(body)}));
      for (const body of moon.clientProgramEffectKeyedSourceUnitMetadataBodies(issued) as readonly unknown[]) {
        bodies.push(Object.freeze({kind: runtimeField(body, 0) as string,
          cid: runtimeField(body, 1) as string, wire: runtimeField(body, 2) as string}));
      }
      const value = Object.freeze({invocation: moon.clientProgramEffectKeyedSourceUnitInvocation(issued),
        ...(deferCatalogs ? {catalogDeferred: true} : {}), bodies: Object.freeze(bodies),
        catalogBodies: Object.freeze(bodies.filter(body => {
          switch (body.kind) {
            case 'source_contract': case 'source_view_contract': case 'data_policy':
            case 'request_schema': case 'carrier_schema': case 'schema_evidence':
            case 'capability_evidence': return true;
            default: return false;
          }
        }))});
      localEffectDependencyTokens.set(value, {kind: 'keyed_source', issued, parent, plan, request});
      return value;
    },
    issueCheckedInstalledEffectCapturedInvocation(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, compilation: unknown, admission: unknown, definition: unknown,
      capturedSource: unknown, source: CapturedSourceFacts, limits: Limits) {
      issuanceLimits(limits, 'Original installed Effect Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectCapturedInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        capturedSource, source.sourceEvidenceWire, source.inputLogicalWire,
        source.sourceRef, source.sourceContractCid, source.authorityScopeCid, source.dataPolicyCid,
        source.captureStartedAt, source.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    issueCheckedInstalledEffectMultiCapturedInvocation(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, compilation: unknown, admission: unknown, definition: unknown,
      sources: readonly CapturedSource[], context: SourceContext, limits: Limits) {
      issuanceLimits(limits, 'Original installed plural Effect Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectMultiCapturedInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        sources.map(value => value.captured.capture.source()),
        sources.map(value => value.captured.identity), sources.map(value => value.captured.requirement),
        sources.map(value => value.sourceEvidenceWire),
        sources.map(value => moon.strategyRunEvidenceJson(value.captured.logicalInput)),
        context.authorityScopeCid, context.dataPolicyCid, context.captureStartedAt as string, context.captureCompletedAt as string,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    issueCheckedOriginalEffectDirectSourcesInvocation(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, compilation: unknown, admission: unknown, definition: unknown,
      sources: readonly CapturedSource[], sourceEvidence: readonly unknown[], context: SourceContext,
      limits: Limits) {
      issuanceLimits(limits, 'Original installed Direct Effect Invocation');
      const issued = checked(moon.clientProgramIssueOriginalEffectDirectSourcesInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        sources.map(({captured}) => captured.capture.source()), sources.map(({captured}) => captured.identity),
        sourceEvidence.map(evidenceToken), sources.map(({captured}) => captured.logicalInput),
        context.authorityScopeCid, context.dataPolicyCid, context.captureStartedAt as string, context.captureCompletedAt as string,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const invocation = moon.clientProgramEffectDirectSourcesPublicationInvocation(issued);
      return Object.freeze({observation: inspectEvidence(moon.clientProgramEffectDirectSourcesPublicationObservation(issued)),
        invocation: inspect(invocation, limits), owner: invocation, sourcePublication: issued});
    },
    bindCheckedInstalledEffectModelInvocation(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, compilation: unknown, admission: unknown, definition: unknown,
      issued: unknown) {
      const retained = inferInvocationTokens.get(issued as object);
      if (retained === undefined) throw new TypeError('Foreign Effect Infer Invocation');
      const value = checked(moon.clientProgramBindInstalledEffectModelInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        retained.compiled, (issued as Readonly<{binding: unknown}>).binding));
      return Object.freeze({observation: inspectEvidence(runtimeField(value, 0)),
        invocation: inspect(runtimeField(value, 1)), owner: runtimeField(value, 1)});
    },
    issueCheckedInstalledEffectContentInvocation(parent: unknown, prepared: unknown, request: unknown,
      plan: unknown, host: unknown, compilation: unknown, admission: unknown, definition: unknown,
      compiled: unknown, generation: unknown, limits: Limits) {
      const value = compiledRunTokens.get(compiled as object), completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) throw new TypeError('Foreign Client Content generation');
      limits = captureContractLimits(limits, 'Original installed Content Invocation');
      const issued = checked(moon.clientProgramIssueInstalledEffectContentInvocation(
        parent, prepared, request, plan, host, compilation, admissionToken(admission), definition,
        value, completion, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
    issueCheckedClientEffectCapturedInvocation(checkedEffect: unknown, compilation: unknown,
      admission: unknown, definition: unknown, capturedSource: unknown, source: CapturedSourceFacts,
      limits: Limits) {
      issuanceLimits(limits, 'Client Effect Invocation');
      const issued = checked(moon.clientProgramIssueEffectCapturedInvocation(
        checkedEffect, compilation, admissionToken(admission), definition,
        capturedSource, source.sourceEvidenceWire, source.inputLogicalWire,
        source.sourceRef, source.sourceContractCid,
        source.authorityScopeCid, source.dataPolicyCid,
        source.captureStartedAt, source.captureCompletedAt,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1)), owner: runtimeField(issued, 1)});
    },
    issueCheckedInstalledEffectDirectSourcesInvocation(plan: unknown, checkedEffect: unknown,
      request: unknown, compilation: unknown, admission: unknown, definition: unknown,
      sources: readonly CapturedSource[], sourceEvidence: readonly unknown[], context: SourceContext,
      limits: Limits) {
      issuanceLimits(limits, 'Client original Effect Sources Invocation');
      if (!Array.isArray(sources) || sources.length < 1 ||
          !Array.isArray(sourceEvidence) || sourceEvidence.length !== sources.length) {
        throw new TypeError('Incomplete Effect Source coverage');
      }
      const issued = checked(moon.clientProgramPrepareInstalledEffectDirectSourcesPublication(
        plan, checkedEffect, request, compilation, admissionToken(admission), definition,
        sources.map(({captured}) => captured.capture.source()),
        sources.map(({captured}) => captured.identity),
        sourceEvidence.map(evidenceToken),
        sources.map(({captured}) => captured.logicalInput),
        context.authorityScopeCid, context.dataPolicyCid,
        context.captureStartedAt as string, context.captureCompletedAt as string,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const invocation = moon.clientProgramEffectDirectSourcesPublicationInvocation(issued);
      const observation = moon.clientProgramEffectDirectSourcesPublicationObservation(issued);
      return Object.freeze({observation: inspectEvidence(observation),
        invocation: inspect(invocation), owner: invocation, sourcePublication: issued});
    },
    prepareCheckedInstalledEffectSourceUnits(plan: unknown, checkedEffect: unknown, request: unknown,
      compilation: unknown, admission: unknown, definition: unknown, sources: readonly CapturedSource[],
      sourceEvidence: readonly unknown[], context: SourceContext, limits: Limits) {
      issuanceLimits(limits, 'Client original Effect Source Units');
      if (!Array.isArray(sources) || sources.length < 1 ||
          !Array.isArray(sourceEvidence) || sourceEvidence.length !== sources.length) {
        throw new TypeError('Incomplete Effect Source coverage');
      }
      return checked(moon.clientProgramPrepareInstalledEffectSourceUnitInputs(
        plan, checkedEffect, request, compilation, admissionToken(admission), definition,
        sources.map(({captured}) => captured.capture.source()),
        sources.map(({captured}) => captured.identity), sourceEvidence.map(evidenceToken),
        sources.map(({captured}) => captured.logicalInput),
        context.authorityScopeCid, context.dataPolicyCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueCheckedClientEffectMultiCapturedInvocation(checkedEffect: unknown, compilation: unknown,
      admission: unknown, definition: unknown, sources: readonly CapturedSource[], context: SourceContext,
      limits: Limits) {
      issuanceLimits(limits, 'Client plural Effect Invocation');
      if (!Array.isArray(sources) || sources.length < 1) {
        throw new TypeError('Incomplete Effect Source coverage');
      }
      const issued = checked(moon.clientProgramIssueEffectMultiCapturedInvocation(
        checkedEffect, compilation, admissionToken(admission), definition,
        sources.map(value => value.captured.capture.source()),
        sources.map(value => value.captured.identity),
        sources.map(value => value.captured.requirement),
        sources.map(value => value.sourceEvidenceWire),
        sources.map(value => moon.strategyRunEvidenceJson(value.captured.logicalInput)),
        context.authorityScopeCid, context.dataPolicyCid,
        context.captureStartedAt as string, context.captureCompletedAt as string,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1)), owner: runtimeField(issued, 1)});
    },
    issueCheckedAcquiredLocalEffectInvocation(checkedEffect: unknown, capturedSource: unknown,
      identity: unknown, requirement: unknown, input: unknown, observation: unknown,
      authorityScopeCid: string, dataPolicyCid: string, limits: Limits) {
      issuanceLimits(limits, 'Acquired local Effect Invocation');
      return checked(moon.clientProgramIssueAcquiredLocalEffectInvocation(
        checkedEffect, capturedSource, identity, requirement, input,
        evidenceToken(observation), authorityScopeCid, dataPolicyCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    },
    issueProgramInitialRetention(owner: unknown, prepared: unknown, request: unknown, policy: string,
      selection: ProgramRetentionTimes, contracts: readonly Readonly<{cid: string}>[], limits: Limits) {
      if (owner === undefined || prepared === undefined || request === undefined) {
        throw new TypeError('OriginalProgramRetentionOwnerRequired');
      }
      limits = captureContractLimits(limits, 'Initial Program retention');
      return inspect(checked(moon.clientProgramIssueProgramInitialRetention(owner, prepared, request,
        contracts[0].cid, policy, selection.availableUntil, selection.deleteBy, selection.metadataDeleteBy,
        contracts[1].cid, selection.metadataDeleteBy, contracts[2].cid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth)), limits);
    },
    issueInstalledEffectInitialRetention(owner: unknown, prepared: unknown, request: unknown, plan: unknown,
      policy: string, selection: EffectRetentionSelection, limits: Limits) {
      if (owner === undefined || prepared === undefined || request === undefined || plan === undefined) {
        throw new TypeError('OriginalEffectRetentionOwnerRequired');
      }
      limits = captureContractLimits(limits, 'Initial Effect retention');
      return inspect(checked(moon.clientProgramIssueInstalledEffectInitialRetention(owner, prepared, request, plan,
        selection.retentionContractCid, policy, selection.availableUntil, selection.deleteBy, selection.metadataDeleteBy,
        selection.metadataRetentionPolicyCid, selection.metadataDeleteBy, selection.clockContractCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth)), limits);
    },
    rebindInstalledEffectResultRetention<Retention extends ContractIdentity>(managedRun: unknown,
      prepared: unknown, request: unknown, plan: unknown, retention: Retention, policy: string,
      limits: Limits) {
      if (managedRun == null || prepared == null || request == null || plan == null) {
        throw new TypeError('OriginalEffectRetentionPreparationRequired');
      }
      limits = captureContractLimits(limits, 'Original Effect retention policy');
      const original = token(retention);
      const value = checked(moon.clientProgramRebindInstalledEffectResultRetention(
        managedRun, prepared, request, plan, original, policy,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      return value === original ? retention : inspect(value, limits);
    },
    issueCheckedAcquiredEffectEvidence(checkedEffect: unknown, capturedSource: unknown, identity: unknown,
      requirement: unknown, input: unknown, observation: unknown, authorityScopeCid: string,
      dataPolicyCid: string, retention: unknown, limits: Limits, unit = 0,
      publicationRetention: unknown = retention, deferCatalogs = false) {
      issuanceLimits(limits, 'Acquired Effect evidence');
      if (!Number.isSafeInteger(unit) || unit < 0) {
        throw new TypeError('Invalid acquired Effect Unit');
      }
      const issued = checked(unit === 0 && publicationRetention === retention
        ? moon.clientProgramIssueAcquiredEffectEvidence(
          checkedEffect, capturedSource, identity, requirement, input,
          evidenceToken(observation), authorityScopeCid, dataPolicyCid,
          token(retention), limits.maxWireBytes, limits.maxNodes, limits.maxDepth)
        : moon.clientProgramIssueAcquiredEffectEvidenceAt(
          checkedEffect, unit, capturedSource, identity, requirement, input,
          evidenceToken(observation), authorityScopeCid, dataPolicyCid,
          token(retention), token(publicationRetention),
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = inspectAcquiredEffectEvidence(issued, publicationRetention, limits, deferCatalogs);
      localEffectDependencyTokens.set(value, {kind: 'acquired', issued});
      return value;
    },
    issueCheckedWholeEffectSourceUnit(plan: unknown, prepared: unknown, request: unknown, slot: number,
      captured: unknown, identity: unknown, capacity: unknown, input: unknown, observation: unknown,
      authorityScopeCid: string, retention: unknown, limits: Limits, deferCatalogs = false) {
      issuanceLimits(limits, 'Whole Effect Source Unit');
      if (!Number.isSafeInteger(slot) || slot < 0) {
        throw new TypeError('Invalid acquired Effect Source slot');
      }
      const issued = checked(moon.clientProgramIssueInstalledWholeEffectSourceUnit(
        plan, prepared, request, slot, captured, identity, capacity, input,
        evidenceToken(observation), authorityScopeCid, token(retention),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = inspectAcquiredEffectEvidence(issued, retention, limits, deferCatalogs);
      localEffectDependencyTokens.set(value, {kind: 'acquired', issued});
      return value;
    },
    prepareCombinedEffectSourceUnit(publication: unknown, unit: number, retention: unknown, limits: Limits,
      deferCatalogs = false) {
      issuanceLimits(limits, 'Combined Effect Source Unit');
      if (!Number.isSafeInteger(unit) || unit < 0) {
        throw new TypeError('Invalid acquired Effect Unit');
      }
      const prepared = checked(moon.clientProgramPrepareCombinedEffectSourceUnit(
        publication, unit, token(retention), limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramCombinedEffectSourceUnitInvocation(prepared),
        bodies: Object.freeze((moon.clientProgramCombinedEffectSourceUnitDependencyBodies(prepared) as readonly unknown[])
          .map(body => Object.freeze({kind: runtimeField(body, 0) as string, cid: runtimeField(body, 1) as string, wire: runtimeField(body, 2) as string}))),
        ...(deferCatalogs ? {catalogDeferred: true, catalogBodies: Object.freeze([])} : {catalogBodies: Object.freeze((checked(moon.clientProgramCombinedEffectSourceUnitCatalogBodies(
          prepared, limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as readonly unknown[])
          .map(body => Object.freeze({kind: runtimeField(body, 0) as string, cid: runtimeField(body, 1) as string, wire: runtimeField(body, 2) as string})))}),
      });
      // This is semantic preparation, not a completed producer. Only the
      // actual Result export/receipt issuer below can mint its Artifact.
      localEffectDependencyTokens.set(value, {kind: 'combined_source', issued: prepared, unit});
      return value;
    },
    prepareInstalledEffectModelSourceUnit(managedRun: unknown, plan: unknown, request: unknown,
      inputs: unknown, unit: number, retention: unknown, limits: Limits, deferCatalogs = false) {
      issuanceLimits(limits, 'Installed preconsumer Effect Source Unit');
      if (!Number.isSafeInteger(unit) || unit < 0) {
        throw new TypeError('Invalid acquired Effect Unit');
      }
      const prepared = checked(moon.clientProgramPrepareInstalledEffectModelSourceUnit(
        managedRun, plan, request, inputs, unit, token(retention),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const value = Object.freeze({
        invocation: moon.clientProgramCombinedEffectSourceUnitInvocation(prepared),
        bodies: Object.freeze((moon.clientProgramCombinedEffectSourceUnitDependencyBodies(prepared) as readonly unknown[])
          .map(body => Object.freeze({kind: runtimeField(body, 0) as string, cid: runtimeField(body, 1) as string, wire: runtimeField(body, 2) as string}))),
        ...(deferCatalogs ? {catalogDeferred: true, catalogBodies: Object.freeze([])} : {catalogBodies: Object.freeze((checked(moon.clientProgramPrepareInstalledEffectModelSourceUnitCatalog(
          managedRun, plan, request, inputs, prepared,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as readonly unknown[])
          .map(body => Object.freeze({kind: runtimeField(body, 0) as string, cid: runtimeField(body, 1) as string, wire: runtimeField(body, 2) as string})))}),
      });
      localEffectDependencyTokens.set(value, {kind: 'combined_source', issued: prepared, unit});
      return value;
    },
  };
}
