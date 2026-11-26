import {runtimeField, runtimeIsError} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import {rememberOriginalSerializationRowLimit} from './dispatch-failure-observation.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';
import {resultOutputLimitFields, validResultOutputLimits} from './result-output-limits.mjs';

type CommonObject = Extract<SynchronousRuntimeData, object>;
type Current = () => boolean;
type Retain = (step: CommonObject) => boolean;
type ValidateResource = (kind: string, wire: string) => boolean;
type ValidateContent = (mediaType: string | undefined, wire: string) => boolean;
type AuthorizeReference = (wire: string) => boolean;
type LimitArguments<Fields extends readonly string[]> = {
  -readonly [Index in keyof Fields]: number;
};
type ResultLimitArguments = LimitArguments<typeof resultOutputLimitFields>;
type ResultLimits = Readonly<Record<typeof resultOutputLimitFields[number], number>>;
type ReferenceLimits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxTextUnits: number}>;
type ContractLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type GenerationLimits = Readonly<{
  maxRows: number; maxBytes: number; maxValueNodes: number; maxValueDepth: number; maxFrames: number;
}>;
type CompletionLimits = Readonly<{
  maxNodes: number; maxTextBytes: number; maxDepth: number; maxWork: number; maxNameBytes: number;
}>;
type PrefixLimits = Readonly<{
  maxRows: number; maxWork: number; maxEntries: number; maxValueBytes: number;
  maxValueNodes: number; maxValueDepth: number; maxFrames: number;
}>;
type ConstructionLimits = Readonly<{
  generation: Pick<GenerationLimits, 'maxBytes' | 'maxValueNodes' | 'maxValueDepth' | 'maxFrames'>;
  reference: Omit<ReferenceLimits, 'maxTextUnits'>;
  contract: ContractLimits;
  output: unknown;
  identitySlots: number;
}>;
type BoundedBodies = Readonly<{registry: unknown; values: string; fragment?: string; ordered?: string}>;
type Coordinates = Readonly<{task: number; step: number}>;
type WorkspaceLimitArguments = [
  generationBytes: number, generationNodes: number, generationDepth: number, generationFrames: number,
  identitySlots: number, referenceBytes: number, referenceNodes: number, referenceDepth: number,
  contractBytes: number, contractNodes: number, contractDepth: number,
];
type Workspace = Readonly<{retainedBytes: bigint; executionBytes: bigint}>;
type Physical = Readonly<{cancel: Current; stopped: Current; cleanup: Current}>;
type ManagedOriginal = Readonly<{
  prepare(workspace: CommonObject, physical: Physical, retain: Retain): CommonObject;
}>;
type ByteCompletion = Readonly<{
  name: string; media_type: string; content_cid: string; size_bytes: number; row_count: number;
}>;
type GeneratedWire = Readonly<{
  media_type: string;
  metadata: Readonly<{effective_data_policy_cid: string}>;
}>;
type CompletionEvidence = Readonly<{input: unknown; derivation: unknown; generation: unknown}>;

type GenerationPublicationBindings = Readonly<{
  completeCheckedClientContentStep(
    compiled: unknown, definition: unknown, step: CommonObject, inputEvidence: unknown,
    candidate: CommonObject, content: CommonObject, available: Current, limits: CompletionLimits,
  ): CommonObject;
  prepareRequestSerializationOutputDemand(
    parent: unknown, input: unknown, compiled: unknown, selection: unknown, fields: readonly number[], output: ResultLimits,
  ): unknown;
  prepareCheckedClientRequestSerializationPlan(
    parent: unknown, input: unknown, request: unknown, compiled: unknown, definition: unknown,
    limits: PrefixLimits, workspace: CommonObject | undefined, sourcePlan?: unknown,
  ): unknown;
  prepareCheckedClientRequestModelSerializationPlan(
    parent: unknown, input: unknown, request: unknown, compiled: unknown, definition: unknown,
    limits: PrefixLimits, workspace: CommonObject | undefined, queryTime: unknown,
  ): unknown;
  bindCheckedClientSerializationInputIdentity(
    compiled: unknown, input: CommonObject, receipt: CommonObject, limits: ContractLimits, captured: unknown,
  ): unknown;
  completeCheckedClientSerializationGeneration(
    compiled: unknown, definition: unknown, input: CommonObject, inputEvidence: unknown,
    candidate: CommonObject, content: CommonObject, available: Current, limits: CompletionLimits,
  ): CommonObject;
  readmitCheckedClientSerializationGeneration(
    compiled: unknown, definition: unknown, graph: unknown, scope: unknown, expectedGenerationCid: string,
    evidence: CompletionEvidence, candidate: CommonObject, content: CommonObject,
  ): CommonObject;
  checkedClientSerializationGenerationOutput(compiled: unknown, generation: unknown): CommonObject;
  checkClientCompiledRunOwner(compiled: unknown, checkedProgram: unknown): void;
  admit(name: 'result_definition', completeWire: string, limits: ContractLimits): CommonObject & Readonly<{
    name: string; identityField: string; identity: string; wire: string;
  }>;
}>;

// The generated Common JS entries own the handles and raw Result shapes.
type CommonContentGenerationBindings = {
  clientProgramContentStepAcknowledgePiece(active: unknown, revision: number): boolean;
  clientProgramContentStepByteCompletion(active: unknown): ByteCompletion | undefined;
  clientProgramContentStepGenerationInput(active: unknown): readonly [unknown, unknown, unknown] | undefined;
  clientProgramContentStepPendingPiece(active: unknown): readonly [number, string] | undefined;
  clientProgramContentStepWorkspace(
    generationBytes: number, generationNodes: number, generationDepth: number,
    generationFrames: number, identitySlots: number, referenceBytes: number, referenceNodes: number,
    referenceDepth: number, contractBytes: number, contractNodes: number, contractDepth: number,
    exportLimits: unknown,
  ): CommonObject | undefined;
  clientProgramEffectContentLocalProvider(
    prepared: unknown, task: number, step: number, sequenceContracts: unknown, values: string,
    fragment: string | undefined, ordered: string | undefined, workspace: unknown, cancel: Current,
    stopped: Current, cleanup: Current, retain: Retain, recovery: CommonObject | undefined,
  ): CommonObject | undefined;
  clientProgramEffectInputExportLimits(...limits: ResultLimitArguments): CommonObject | undefined;
  clientProgramGeneratedContentCandidate(
    encoder: unknown, bindingWire: string, maxBytes: number, maxNodes: number, maxDepth: number,
    maxTextUnits: number,
  ): unknown;
  clientProgramGeneratedContentCandidateCid(candidate: unknown): string;
  clientProgramGeneratedContentCandidateWire(candidate: unknown): string;
  clientProgramGeneratedContentStorage(candidate: unknown): readonly [string, string, string, number];
  clientProgramInstalledEffectContentPreparationProvider(original: unknown): CommonObject;
  clientProgramInstalledManagedAcquiredSerializationPrefixStart(
    run: unknown, prepared: unknown, selected: unknown, capture: unknown,
  ): unknown;
  clientProgramInstalledManagedWholeSerializationPrefixStart(
    run: unknown, prepared: unknown, selected: unknown, captures: readonly unknown[],
  ): unknown;
  clientProgramInstalledManagedKeyedSerializationPrefixCleanup(run: unknown, selected: unknown): unknown;
  clientProgramInstalledManagedKeyedSerializationPrefixStart(
    run: unknown, prepared: unknown, selected: unknown, source: unknown, lookup: unknown,
  ): unknown;
  clientProgramInstalledManagedSerializationPrefixCleanup(run: unknown, selected: unknown): unknown;
  clientProgramInstalledManagedSerializationPrefixStart(
    run: unknown, prepared: unknown, selected: unknown,
  ): unknown;
  clientProgramIssueGeneratedContent(
    candidate: unknown, issuer: unknown, maxBytes: number, maxNodes: number, maxDepth: number,
    maxTextUnits: number,
  ): unknown;
  clientProgramIssueStoredGeneratedContent(
    candidate: unknown, issuer: unknown, maxBytes: number, maxNodes: number, maxDepth: number,
    maxTextUnits: number,
  ): unknown;
  clientProgramPrepareRequestKeyedContentPlan(
    parent: unknown, input: unknown, request: unknown, keyed: unknown, directDeclaration: unknown,
    contentDeclaration: unknown, maxPageBytes: number, maxTextBytes: number, rowWork: number,
    queryContractBody: string, evidenceContractBody: string, transportBytes: readonly bigint[],
    transportExecutionBytes: readonly bigint[], maxBytes: number, maxWork: number, contracts: unknown,
    task: number, step: number, prefixMaxRows: number, prefixMaxWork: number, maxEntries: number,
    maxValueBytes: number, maxValueNodes: number, maxValueDepth: number, maxFrames: number,
    workspace: CommonObject | undefined,
  ): unknown;
  clientProgramPrepareRequestSerializationOutputDemand(
    parent: unknown, input: unknown, compiled: unknown, component: unknown, generationRows: number,
    generationBytes: number, generationNodes: number, generationDepth: number,
    generationFrames: number, identitySlots: number, referenceBytes: number, referenceNodes: number,
    referenceDepth: number, contractBytes: number, contractNodes: number, contractDepth: number,
    maxResultFields: number, maxResultMappingWork: number, maxResultOrderWork: number,
    maxResultWorkspaceEntries: number, maxRows: number, maxValueNodes: number,
    maxValueTextBytes: number, maxValueDepth: number, maxValueWork: number, maxWireBytes: number,
    maxWireNodes: number, maxWireDepth: number, maxColumns: number, maxOrderWork: number,
    maxLogicalWireBytes: number, maxLogicalWireNodes: number, maxLogicalWireDepth: number,
    maxSchemaFields: number, maxSchemaBytes: number, maxSchemaNodes: number, maxSchemaDepth: number,
    maxBatchBytes: number,
  ): unknown;
  clientProgramPrepareSerialization(owner: unknown, task: number, step: number, maxWork: number): unknown;
  clientProgramPreparedInstalledKeyedPrefixRequirements(selected: unknown): unknown;
  clientProgramPreparedInstalledSerializationPrefixRequirements(selected: unknown): unknown;
  clientProgramRowReferenceIssuer(
    validateResource: ValidateResource, validateContent: ValidateContent,
    authorize: AuthorizeReference,
  ): CommonObject;
  clientProgramSerializationAdvance(
    encoder: unknown, quantum: number,
  ): readonly [boolean, string, number, unknown];
  clientProgramSerializationBindInput(barrier: unknown, input: unknown, encoder: unknown): unknown;
  clientProgramSerializationInputIsRowLimit(issue: unknown): boolean;
  clientProgramSerializationCancel(encoder: unknown): void;
  clientProgramSerializationCapacityBytes(capacity: unknown): readonly [bigint, bigint];
  clientProgramSerializationEncoder(
    barrier: unknown, maxRows: number, maxBytes: number, maxValueNodes: number,
    maxValueDepth: number, maxFrames: number,
  ): unknown;
  clientProgramSerializationFinish(encoder: unknown): unknown;
  clientProgramSerializationInputIdentityAdvance(
    scan: unknown, quantum: number,
  ): readonly [boolean, bigint, unknown];
  clientProgramSerializationInputIdentityCancel(scan: unknown): boolean;
  clientProgramSerializationInputIdentityFinish(scan: unknown): unknown;
  clientProgramSerializationInputIdentityReceiptCancel(receipt: unknown): void;
  clientProgramSerializationInputIdentityStart(
    input: unknown, limits: unknown, maxWork: number, maxWorkspaceSlots: number,
  ): unknown;
  clientProgramSerializationInputRow(input: unknown, row: number): unknown;
  clientProgramSerializationInputRows(input: unknown): number;
  clientProgramSerializationOutput(
    input: unknown, candidate: unknown, content: unknown, available: Current, maxNodes: number,
    maxTextBytes: number, maxDepth: number, maxWork: number, maxNameBytes: number,
  ): unknown;
  clientProgramSerializationOutputAvailable(output: unknown): boolean;
  clientProgramSerializationOutputIssueCode(issue: unknown): string;
  clientProgramSerializationOutputRowWire(
    output: unknown, maxBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  clientProgramSerializationPrefixAdvance(prefix: unknown, quantum: number): unknown;
  clientProgramSerializationPrefixCancel(prefix: unknown): boolean;
  clientProgramSerializationPrefixCapacity(
    program: unknown, task: number, step: number, sequenceContracts: unknown, values: string,
    fragment: string | undefined, ordered: string | undefined, maxRows: number, maxWork: number,
    maxEntries: number, maxValueBytes: number, maxValueNodes: number, maxValueDepth: number,
    maxFrames: number, acquired: boolean,
  ): readonly [bigint, bigint] | undefined;
  clientProgramSerializationPrefixCleanup(prefix: unknown): unknown;
  clientProgramSerializationPrefixWork(prefix: unknown): unknown;
  clientProgramSerializationResultCancel(value: unknown): boolean;
  clientProgramSerializationResultFinish(value: unknown): unknown;
  clientProgramSerializationResultOccurrence(
    program: unknown, result: number, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  clientProgramSerializationResultProgress(
    value: unknown, quantum: number,
  ): readonly [boolean, number, unknown];
  clientProgramSerializationResultStart(
    program: unknown, result: number, output: unknown, limits: unknown,
  ): unknown;
  clientProgramSerializationRow(barrier: unknown, input: unknown, row: number, encoder: unknown): unknown;
  clientProgramSerializationWorkspaceCapacity(
    generationBytes: number, generationNodes: number, generationDepth: number,
    generationFrames: number, identitySlots: number, referenceBytes: number, referenceNodes: number,
    referenceDepth: number, contractBytes: number, contractNodes: number, contractDepth: number,
    exportLimits: unknown,
  ): CommonObject | undefined;
  clientProgramStartSerializationPrefix(
    program: unknown, task: number, step: number, sequenceContracts: unknown, values: string,
    fragment: string | undefined, ordered: string | undefined, maxRows: number, maxWork: number,
    maxEntries: number, maxValueBytes: number, maxValueNodes: number, maxValueDepth: number,
    maxFrames: number, ledger: unknown, workspace: CommonObject | undefined,
    source: CommonObject | undefined, keyed: CommonObject | undefined,
  ): unknown;
  clientProgramStoredGeneratedContentCandidate(
    originalWire: string, bindingWire: string, maxBytes: number, maxNodes: number, maxDepth: number,
    maxTextUnits: number,
  ): unknown;
  clientProgramStoredGeneratedContentCandidateWire(candidate: unknown): string;
  clientProgramStoredGeneratedContentStorage(
    candidate: unknown,
  ): readonly [string, string, string, string, number];
  strategyPublicationContractJson(contract: unknown): string;
};

// Trusted assembly only. Standard entries bind this to their generated runtime;
// execution requests cannot supply a verifier, SQL or replacement runtime.
export function contentGenerationControl(
  moon: CommonContentGenerationBindings, publications: GenerationPublicationBindings,
) {
  const barriers = new WeakSet<CommonObject>();
  const encoders = new WeakSet<CommonObject>();
  const candidates = new WeakSet<CommonObject>();
  const storedCandidates = new WeakSet<CommonObject>();
  const issuers = new WeakSet<CommonObject>();
  const inputs = new WeakMap<CommonObject, CommonObject>();
  const prefixes = new WeakSet<CommonObject>();
  const workspaces = new WeakMap<Workspace, CommonObject>();
  const issued = new WeakSet<CommonObject>();
  const outputs = new WeakSet<CommonObject>();
  const resultPreparations = new WeakSet<CommonObject>();
  const identityScans = new WeakMap<CommonObject, CommonObject>();
  const familySteps = new WeakSet<CommonObject>();
  const quantity = (value: unknown, minimum = 0): value is number =>
    Number.isInteger(value) && (value as number) >= minimum && (value as number) <= 2147483647;
  const owned = (set: WeakSet<CommonObject>, value: CommonObject, name: string) => {
    if (value === null || typeof value !== 'object' || !set.has(value)) {
      throw new TypeError(`Foreign ${name}`);
    }
    return value;
  };
  const referenceLimits = (limits: ReferenceLimits): [number, number, number, number] => {
    if (limits === null || typeof limits !== 'object' ||
        !['maxBytes', 'maxNodes', 'maxDepth', 'maxTextUnits'].every(
          key => quantity(limits[key as keyof ReferenceLimits], 1))) {
      throw new TypeError('Invalid Content reference limits');
    }
    return [limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxTextUnits];
  };
  return Object.freeze({
    effectFamily(
      program: unknown, graph: Coordinates, bodies: BoundedBodies,
      {generation, reference, contract, output, identitySlots}: ConstructionLimits,
      physical: Physical, retain: Retain, recovery?: CommonObject, managedOriginal?: ManagedOriginal,
    ) {
      const fields: WorkspaceLimitArguments = [generation?.maxBytes, generation?.maxValueNodes,
        generation?.maxValueDepth, generation?.maxFrames, identitySlots,
        reference?.maxBytes, reference?.maxNodes, reference?.maxDepth,
        contract?.maxWireBytes, contract?.maxNodes, contract?.maxDepth];
      if (!fields.every(value => quantity(value)) || !validResultOutputLimits(output) ||
          !resultOutputLimitFields.every(name => quantity(output[name])) ||
          !['cancel', 'stopped', 'cleanup'].every(name => typeof physical?.[name as keyof Physical] === 'function') ||
          typeof retain !== 'function' || !quantity(graph?.task) || !quantity(graph?.step)) {
        throw new TypeError('Invalid installed Content family');
      }
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => output[name]) as ResultLimitArguments);
      const workspace = exported === undefined ? undefined
        : moon.clientProgramContentStepWorkspace(...fields, exported);
      const retainOriginal = (active: CommonObject) => {
        familySteps.add(active);
        return retain(active) === true;
      };
      if (managedOriginal !== undefined) {
        if (recovery !== undefined || workspace === undefined) throw new TypeError('Invalid managed Content original');
        const preparation = managedOriginal.prepare(workspace, physical, retainOriginal);
        const provider = moon.clientProgramInstalledEffectContentPreparationProvider(preparation);
        return Object.freeze({provider, preparation});
      }
      const provider = workspace === undefined ? undefined
        : moon.clientProgramEffectContentLocalProvider(program, graph.task, graph.step,
          bodies.registry, bodies.values, bodies.fragment, bodies.ordered, workspace,
          physical.cancel, physical.stopped, physical.cleanup, retainOriginal, recovery);
      if (provider === undefined) throw new TypeError('Installed Content family unavailable');
      return provider;
    },
    familyPendingPiece(step: CommonObject) {
      const value = moon.clientProgramContentStepPendingPiece(owned(familySteps, step, 'Content step'));
      return value === undefined ? undefined : Object.freeze({revision: runtimeField(value, 0) as number,
        piece: runtimeField(value, 1) as string});
    },
    familyAcknowledgePiece(step: CommonObject, revision: number) {
      if (!quantity(revision, 1)) throw new TypeError('Invalid Content piece revision');
      return moon.clientProgramContentStepAcknowledgePiece(
        owned(familySteps, step, 'Content step'), revision);
    },
    familyInput(step: CommonObject) {
      const value = moon.clientProgramContentStepGenerationInput(owned(familySteps, step, 'Content step'));
      if (value === undefined) throw new TypeError('Content step input unavailable');
      inputs.set(runtimeField(value, 0) as CommonObject, runtimeField(value, 2) as CommonObject);
      encoders.add(runtimeField(value, 2) as CommonObject);
      return Object.freeze({input: runtimeField(value, 0) as CommonObject,
        receipt: runtimeField(value, 1) as CommonObject, encoder: runtimeField(value, 2) as CommonObject});
    },
    familyByteCompletion(step: CommonObject) {
      const value = moon.clientProgramContentStepByteCompletion(owned(familySteps, step, 'Content step'));
      if (value === undefined) throw new TypeError('Content step completion unavailable');
      return Object.freeze({name: value.name, mediaType: value.media_type,
        contentCid: value.content_cid, sizeBytes: value.size_bytes, rowCount: value.row_count});
    },
    familyComplete(
      compiled: unknown, definition: unknown, step: CommonObject, inputEvidence: unknown,
      candidate: CommonObject, content: CommonObject, available: Current, limits: CompletionLimits,
    ) {
      owned(familySteps, step, 'Content step');
      if (typeof available !== 'function' || !quantity(limits?.maxNodes, 1) ||
          !quantity(limits?.maxTextBytes) || !quantity(limits?.maxDepth) ||
          !quantity(limits?.maxWork, 1) || !quantity(limits?.maxNameBytes)) {
        throw new TypeError('Invalid compiled Content step completion');
      }
      return publications.completeCheckedClientContentStep(compiled, definition, step,
        inputEvidence, owned(candidates, candidate, 'Content candidate'),
        owned(issued, content, 'issued Content'), available, limits);
    },
    workspaceCapacity({generation, reference, contract, output, identitySlots}: ConstructionLimits) {
      const fields: WorkspaceLimitArguments = [generation?.maxBytes, generation?.maxValueNodes,
        generation?.maxValueDepth, generation?.maxFrames, identitySlots,
        reference?.maxBytes, reference?.maxNodes, reference?.maxDepth,
        contract?.maxWireBytes, contract?.maxNodes, contract?.maxDepth];
      if (!fields.every(value => quantity(value)) || !validResultOutputLimits(output) ||
          !resultOutputLimitFields.every(name => quantity(output[name]))) {
        throw new TypeError('Invalid Content workspace limits');
      }
      const exported = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => output[name]) as ResultLimitArguments);
      const token = exported === undefined ? undefined
        : moon.clientProgramSerializationWorkspaceCapacity(...fields, exported);
      if (token === undefined) throw new TypeError('Content workspace unavailable');
      const bytes = moon.clientProgramSerializationCapacityBytes(token);
      const workspace = Object.freeze({retainedBytes: runtimeField(bytes, 0) as bigint, executionBytes: runtimeField(bytes, 1) as bigint});
      workspaces.set(workspace, token);
      return workspace;
    },
    prefixCapacity(
      program: unknown, task: number, step: number, bodies: BoundedBodies, limits: PrefixLimits,
      workspace?: Workspace, source?: unknown,
    ) {
      if (!quantity(limits?.maxRows) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxEntries, 1) || !quantity(limits?.maxValueBytes) ||
          !quantity(limits?.maxValueNodes, 1) || !quantity(limits?.maxValueDepth) ||
          !quantity(limits?.maxFrames, 1)) {
        throw new TypeError('Invalid Content prefix limits');
      }
      const capacity = moon.clientProgramSerializationPrefixCapacity(program, task,
        step, bodies.registry, bodies.values, bodies.fragment, bodies.ordered,
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames,
        source !== undefined);
      if (capacity === undefined) throw new TypeError('Content prefix unavailable');
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      const retainedBytes = (runtimeField(capacity, 0) as bigint) + (workspace?.retainedBytes ?? 0n);
      const executionBytes = (runtimeField(capacity, 1) as bigint) + (workspace?.executionBytes ?? 0n);
      if (retainedBytes > 9223372036854775807n || executionBytes > 9223372036854775807n) {
        throw new TypeError('Content capacity overflow');
      }
      return Object.freeze({retainedBytes, executionBytes});
    },
    prepareRequestOutputDemand(
      parent: unknown, input: unknown, compiled: unknown, selection: unknown, generation: GenerationLimits,
      reference: Omit<ReferenceLimits, 'maxTextUnits'>, contract: ContractLimits, output: unknown, identitySlots: number,
    ) {
      const method = moon.clientProgramPrepareRequestSerializationOutputDemand;
      const fields = [generation?.maxRows, generation?.maxBytes, generation?.maxValueNodes, generation?.maxValueDepth,
        generation?.maxFrames, identitySlots, reference?.maxBytes, reference?.maxNodes,
        reference?.maxDepth, contract?.maxWireBytes, contract?.maxNodes, contract?.maxDepth];
      if (typeof method !== 'function' || !fields.every(value => quantity(value)) ||
          !validResultOutputLimits(output)) throw new TypeError('Content demand unavailable');
      // Only the same compiled token enters the funded Request constructor.
      // The template is fixed DATA; no Graph wire, parser or Host formula runs.
      const selected = publications.prepareRequestSerializationOutputDemand(
        parent, input, compiled, selection, fields, output);
      const capacity = runtimeField(selected, 0);
      const quantities = Array.from({length: 8}, (_, index) => runtimeField(selected, index + 1));
      if (!quantities.every(value => quantity(value))) throw new TypeError('Invalid Content output demand');
      const [generationRows, generationBytes, outputRows, valueNodes, wireNodes, logicalNodes, columns, slots] = quantities;
      const bytes = moon.clientProgramSerializationCapacityBytes(capacity);
      const workspace = Object.freeze({retainedBytes: runtimeField(bytes, 0) as bigint, executionBytes: runtimeField(bytes, 1) as bigint});
      workspaces.set(workspace, capacity as CommonObject);
      return Object.freeze({
        generationLimits: Object.freeze({...generation, maxRows: generationRows, maxBytes: generationBytes}),
        outputLimits: Object.freeze({...output, maxRows: outputRows, maxValueNodes: valueNodes,
          maxWireNodes: wireNodes, maxLogicalWireNodes: logicalNodes, maxColumns: columns}),
        identitySlots: slots, workspace,
      });
    },
    prepareRequestPrefix(
      parent: unknown, input: unknown, request: unknown, compiled: unknown, definition: unknown,
      limits: PrefixLimits, workspace?: Workspace, sourcePlan?: unknown,
    ) {
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      return publications.prepareCheckedClientRequestSerializationPlan(parent, input, request, compiled,
        definition, limits, workspace === undefined ? undefined : workspaces.get(workspace), sourcePlan);
    },
    prepareModelRequestPrefix(
      parent: unknown, input: unknown, request: unknown, compiled: unknown, definition: unknown,
      limits: PrefixLimits, workspace: Workspace | undefined, queryTime: unknown,
    ) {
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      return publications.prepareCheckedClientRequestModelSerializationPlan(parent, input, request, compiled,
        definition, limits, workspace === undefined ? undefined : workspaces.get(workspace), queryTime);
    },
    prepareRequestKeyedPlan(
      parent: unknown, input: unknown, request: unknown, keyed: unknown, directDeclaration: unknown,
      contentDeclaration: unknown, maxBytes: number, maxWork: number, queryContract: string, evidenceContract: string,
      transfers: readonly bigint[], executions: readonly bigint[], contracts: unknown, task: number, step: number,
      limits: PrefixLimits, workspace?: Workspace,
    ) {
      const prepare = moon.clientProgramPrepareRequestKeyedContentPlan;
      if (typeof prepare !== 'function') throw new TypeError('Request keyed Content constructor unavailable');
      if (!quantity(maxBytes) || !quantity(maxWork, 1) ||
          !quantity(limits?.maxRows) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxEntries, 1) || !quantity(limits?.maxValueBytes) ||
          !quantity(limits?.maxValueNodes, 1) || !quantity(limits?.maxValueDepth) ||
          !quantity(limits?.maxFrames, 1)) throw new TypeError('Invalid Content prefix limits');
      if (workspace !== undefined && !workspaces.has(workspace)) {
        throw new TypeError('Foreign Content workspace capacity');
      }
      return checked(Reflect.apply(prepare, moon, [parent, input, request, keyed,
        directDeclaration, contentDeclaration, maxBytes, maxBytes, maxWork,
        queryContract, evidenceContract, transfers, executions, maxBytes, maxWork,
        contracts, task, step, limits.maxRows, limits.maxWork, limits.maxEntries,
        limits.maxValueBytes, limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames,
        workspace === undefined ? undefined : workspaces.get(workspace)]));
    },
    requestPrefixCapacity(selected: unknown) {
      const value = moon.clientProgramPreparedInstalledSerializationPrefixRequirements(selected);
      if (!Array.isArray(value) || value.length !== 6 ||
          value.some(n => typeof n !== 'bigint' || n < 0n || n > 9223372036854775807n) ||
          value[0] !== 0n || value[1] !== 1n || value[2] !== 0n || value[3] !== 0n) {
        throw new TypeError('Invalid Content prefix requirements');
      }
      return Object.freeze({retainedBytes: value[4] as bigint, executionBytes: value[5] as bigint});
    },
    startRequestPrefix(run: unknown, program: unknown, selected: unknown) {
      const prefix = checked(moon.clientProgramInstalledManagedSerializationPrefixStart(run, program, selected)) as CommonObject;
      prefixes.add(prefix); return prefix;
    },
    startRequestAcquiredPrefix(run: unknown, program: unknown, selected: unknown, capture: unknown) {
      const prefix = checked(moon.clientProgramInstalledManagedAcquiredSerializationPrefixStart(
        run, program, selected, capture)) as CommonObject;
      prefixes.add(prefix); return prefix;
    },
    startRequestWholePrefix(run: unknown, program: unknown, selected: unknown, captures: readonly unknown[]) {
      const start = moon.clientProgramInstalledManagedWholeSerializationPrefixStart;
      if (typeof start !== 'function') throw new TypeError('Request Whole Content prefix unavailable');
      const prefix = checked(Reflect.apply(start, moon, [run, program, selected, captures])) as CommonObject;
      prefixes.add(prefix); return prefix;
    },
    cleanupRequestPrefix(run: unknown, selected: unknown) {
      return checked(moon.clientProgramInstalledManagedSerializationPrefixCleanup(run, selected)) as boolean;
    },
    requestKeyedPrefixCapacity(selected: unknown) {
      const value = checked(moon.clientProgramPreparedInstalledKeyedPrefixRequirements(selected));
      if (!Array.isArray(value) || value.length !== 6 ||
          value.some(n => typeof n !== 'bigint' || n < 0n || n > 9223372036854775807n) ||
          value[0] !== 0n || value[1] !== 1n || value[2] !== 0n || value[3] !== 0n) {
        throw new TypeError('Invalid keyed Content prefix requirements');
      }
      return Object.freeze({retainedBytes: value[4] as bigint, executionBytes: value[5] as bigint});
    },
    startRequestKeyedPrefix(run: unknown, program: unknown, selected: unknown, source: unknown, lookup: unknown) {
      const prefix = checked(moon.clientProgramInstalledManagedKeyedSerializationPrefixStart(
        run, program, selected, source, lookup)) as CommonObject;
      prefixes.add(prefix); return prefix;
    },
    cleanupRequestKeyedPrefix(run: unknown, selected: unknown) {
      return checked(moon.clientProgramInstalledManagedKeyedSerializationPrefixCleanup(run, selected)) as boolean;
    },
    prefix(
      program: unknown, task: number, step: number, bodies: BoundedBodies, limits: PrefixLimits,
      ledger: unknown, workspace?: Workspace, source?: CommonObject, keyed?: CommonObject,
    ) {
      // Revalidate through the same provider before reserve/start. Capacity
      // inspection alone is neither a reservation nor permission to execute.
      this.prefixCapacity(program, task, step, bodies, limits, workspace, source);
      if (ledger === undefined) throw new TypeError('Content prefix requires the Run ledger');
      const prefix = checked(moon.clientProgramStartSerializationPrefix(program, task,
        step, bodies.registry, bodies.values, bodies.fragment, bodies.ordered,
        limits.maxRows, limits.maxWork, limits.maxEntries, limits.maxValueBytes,
        limits.maxValueNodes, limits.maxValueDepth, limits.maxFrames, ledger,
        workspace === undefined ? undefined : workspaces.get(workspace), source, keyed)) as CommonObject;
      prefixes.add(prefix);
      return prefix;
    },
    prefixAdvance(prefix: CommonObject, quantum: number) {
      const value = checked(moon.clientProgramSerializationPrefixAdvance(
        owned(prefixes, prefix, 'Content prefix'), quantum));
      return Object.freeze({output: runtimeField(value, 0) as CommonObject | undefined,
        progress: runtimeField(value, 1) as bigint, work: runtimeField(value, 2) as bigint,
        stopped: runtimeField(value, 3) as boolean, issue: runtimeField(value, 4)});
    },
    prefixWork(prefix: CommonObject) {
      return checked(moon.clientProgramSerializationPrefixWork(
        owned(prefixes, prefix, 'Content prefix'))) as bigint;
    },
    prefixCancel(prefix: CommonObject) {
      return moon.clientProgramSerializationPrefixCancel(
        owned(prefixes, prefix, 'Content prefix'));
    },
    prefixCleanup(prefix: CommonObject) {
      return checked(moon.clientProgramSerializationPrefixCleanup(
        owned(prefixes, prefix, 'Content prefix'))) as boolean;
    },
    prepare(program: unknown, task: number, step: number, maxWork: number) {
      const barrier = checked(moon.clientProgramPrepareSerialization(
        program, task, step, maxWork)) as CommonObject;
      barriers.add(barrier);
      return barrier;
    },
    encoder(barrier: CommonObject, limits: GenerationLimits) {
      owned(barriers, barrier, 'Content barrier');
      if (!quantity(limits?.maxRows) || !quantity(limits?.maxBytes) ||
          !quantity(limits?.maxValueNodes, 1) || !quantity(limits?.maxValueDepth) ||
          !quantity(limits?.maxFrames, 1)) {
        throw new TypeError('Invalid Content encoder limits');
      }
      const encoder = checked(moon.clientProgramSerializationEncoder(barrier,
        limits.maxRows, limits.maxBytes, limits.maxValueNodes,
        limits.maxValueDepth, limits.maxFrames)) as CommonObject;
      encoders.add(encoder);
      return encoder;
    },
    row(barrier: CommonObject, input: unknown, row: number, encoder: CommonObject) {
      return checked(moon.clientProgramSerializationRow(
        owned(barriers, barrier, 'Content barrier'), input, row,
        owned(encoders, encoder, 'Content encoder'))) as undefined;
    },
    bindInput(barrier: CommonObject, output: unknown, encoder: CommonObject) {
      const result = moon.clientProgramSerializationBindInput(
        owned(barriers, barrier, 'Content barrier'), output,
        owned(encoders, encoder, 'Content encoder'));
      let input: CommonObject;
      try {
        input = checked(result) as CommonObject;
      } catch (cause) {
        try {
          if (runtimeIsError(result) &&
              moon.clientProgramSerializationInputIsRowLimit(runtimeField(result, 0))) {
            rememberOriginalSerializationRowLimit(cause as object);
          }
        } catch { /* Optional diagnostic DATA cannot replace the original failure. */ }
        throw cause;
      }
      inputs.set(input, encoder);
      return input;
    },
    inputRows(input: CommonObject) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return moon.clientProgramSerializationInputRows(input);
    },
    inputIdentityStart(input: CommonObject, limits: unknown, maxWork: number, maxWorkspaceSlots: number) {
      if (!inputs.has(input) || !validResultOutputLimits(limits) ||
          !quantity(maxWork) || !quantity(maxWorkspaceSlots) ||
          !resultOutputLimitFields.every(name => quantity(limits[name]))) {
        throw new TypeError('Invalid Content input identity limits');
      }
      const exportLimits = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => limits[name]) as ResultLimitArguments);
      if (exportLimits === undefined) throw new TypeError('Invalid Content input identity limits');
      const scan = checked(moon.clientProgramSerializationInputIdentityStart(
        input, exportLimits, maxWork, maxWorkspaceSlots)) as CommonObject;
      identityScans.set(scan, input);
      return scan;
    },
    inputIdentityAdvance(scan: CommonObject, quantum: number) {
      if (!identityScans.has(scan) || !quantity(quantum, 1)) {
        throw new TypeError('Foreign or invalid Content input identity scan');
      }
      const next = moon.clientProgramSerializationInputIdentityAdvance(scan, quantum);
      return Object.freeze({ready: runtimeField(next, 0) as boolean, work: runtimeField(next, 1) as bigint, issue: runtimeField(next, 2)});
    },
    inputIdentityFinish(compiled: unknown, scan: CommonObject, limits: ContractLimits, captured: unknown) {
      const input = identityScans.get(scan);
      if (input === undefined) throw new TypeError('Foreign Content input identity scan');
      const receipt = checked(moon.clientProgramSerializationInputIdentityFinish(scan)) as CommonObject;
      try {
        return publications.bindCheckedClientSerializationInputIdentity(compiled, input, receipt, limits, captured);
      } finally { moon.clientProgramSerializationInputIdentityReceiptCancel(receipt); }
    },
    inputIdentityCancel(scan: CommonObject) {
      if (!identityScans.has(scan)) throw new TypeError('Foreign Content input identity scan');
      return moon.clientProgramSerializationInputIdentityCancel(scan);
    },
    inputRow(input: CommonObject, row: number) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return checked(moon.clientProgramSerializationInputRow(input, row)) as undefined;
    },
    inputAdvance(input: CommonObject, quantum: number) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return this.advance(inputs.get(input)!, quantum);
    },
    inputFinish(input: CommonObject) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      return this.finish(inputs.get(input)!);
    },
    inputCancel(input: CommonObject) {
      if (!inputs.has(input)) throw new TypeError('Foreign Content input');
      moon.clientProgramSerializationCancel(inputs.get(input));
    },
    output(
      input: CommonObject, candidate: CommonObject, content: CommonObject, available: Current, limits: CompletionLimits,
    ) {
      if (!inputs.has(input) || typeof available !== 'function' ||
          !quantity(limits?.maxNodes, 1) || !quantity(limits?.maxTextBytes) ||
          !quantity(limits?.maxDepth) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxNameBytes)) {
        throw new TypeError('Invalid Content output binding');
      }
      const result = moon.clientProgramSerializationOutput(input,
        owned(candidates, candidate, 'Content candidate'),
        owned(issued, content, 'issued Content'), available,
        limits.maxNodes, limits.maxTextBytes, limits.maxDepth,
        limits.maxWork, limits.maxNameBytes);
      if (runtimeIsError(result)) {
        const causeCode = moon.clientProgramSerializationOutputIssueCode(runtimeField(result, 0));
        throw Object.assign(new Error(`Content output rejected: ${causeCode}`,
          {cause: runtimeField(result, 0)}), {code: 'MoonBitHostFailure', causeCode});
      }
      const output = checked(result) as CommonObject;
      outputs.add(output);
      return output;
    },
    outputRowWire(output: CommonObject, limits: ReferenceLimits) {
      return checked(moon.clientProgramSerializationOutputRowWire(
        owned(outputs, output, 'Content output'), ...referenceLimits(limits).slice(0, 3) as [number, number, number])) as string;
    },
    outputAvailable(output: CommonObject) {
      return moon.clientProgramSerializationOutputAvailable(
        owned(outputs, output, 'Content output'));
    },
    complete(
      compiled: unknown, definition: unknown, input: CommonObject, inputEvidence: unknown,
      candidate: CommonObject, content: CommonObject, available: Current, limits: CompletionLimits,
    ) {
      if (!inputs.has(input) || typeof available !== 'function' ||
          !quantity(limits?.maxNodes, 1) || !quantity(limits?.maxTextBytes) ||
          !quantity(limits?.maxDepth) || !quantity(limits?.maxWork, 1) ||
          !quantity(limits?.maxNameBytes)) {
        throw new TypeError('Invalid compiled Content completion');
      }
      return publications.completeCheckedClientSerializationGeneration(compiled,
        definition, input, inputEvidence, owned(candidates, candidate, 'Content candidate'),
        owned(issued, content, 'issued Content'), available, limits);
    },
    recover(
      compiled: unknown, definition: unknown, graph: unknown, scope: unknown, expectedGenerationCid: string,
      evidence: CompletionEvidence, candidate: CommonObject, content: CommonObject,
    ) {
      return publications.readmitCheckedClientSerializationGeneration(compiled, definition,
        graph, scope, expectedGenerationCid, evidence,
        owned(storedCandidates, candidate, 'stored Content candidate'),
        owned(issued, content, 'issued Content'));
    },
    completedOutput(compiled: unknown, generation: unknown) {
      const output = publications.checkedClientSerializationGenerationOutput(compiled, generation);
      outputs.add(output);
      return output;
    },
    resultOccurrence(compiled: Readonly<{kind: string}>, program: unknown, result: number, limits: ContractLimits) {
      publications.checkClientCompiledRunOwner(compiled, program);
      if (compiled.kind !== 'serialization' || !quantity(result) ||
          !quantity(limits?.maxWireBytes, 1) || !quantity(limits?.maxNodes, 1) ||
          !quantity(limits?.maxDepth)) {
        throw new TypeError('Invalid Content Result occurrence');
      }
      const occurrence = checked(moon.clientProgramSerializationResultOccurrence(
        program, result, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
      const definitionContract = publications.admit('result_definition',
        moon.strategyPublicationContractJson(runtimeField(occurrence, 2)), limits);
      return Object.freeze({name: runtimeField(occurrence, 0) as string,
        task: runtimeField(occurrence, 1) as number, definitionContract});
    },
    resultStart(program: unknown, result: number, output: CommonObject, limits: unknown) {
      if (!quantity(result) || !validResultOutputLimits(limits) ||
          !resultOutputLimitFields.every(name => quantity(limits[name]))) {
        throw new TypeError('Invalid Content Result export limits');
      }
      // This existing builder creates only shared finite export limits; it
      // supplies no Effect or publication authority.
      const exportLimits = moon.clientProgramEffectInputExportLimits(
        ...resultOutputLimitFields.map(name => limits[name]) as ResultLimitArguments);
      if (exportLimits === undefined) throw new TypeError('Invalid Content Result export limits');
      const preparation = checked(moon.clientProgramSerializationResultStart(
        program, result, owned(outputs, output, 'Content output'), exportLimits)) as CommonObject;
      resultPreparations.add(preparation);
      return preparation;
    },
    resultAdvance(preparation: CommonObject, quantum: number) {
      if (!quantity(quantum, 1)) throw new TypeError('Invalid Content Result quantum');
      const result = moon.clientProgramSerializationResultProgress(
        owned(resultPreparations, preparation, 'Content Result preparation'), quantum);
      return Object.freeze({ready: runtimeField(result, 0) as boolean, work: runtimeField(result, 1) as number, issue: runtimeField(result, 2)});
    },
    resultFinish(preparation: CommonObject) {
      return checked(moon.clientProgramSerializationResultFinish(
        owned(resultPreparations, preparation, 'Content Result preparation'))) as CommonObject;
    },
    resultCancel(preparation: CommonObject) {
      return moon.clientProgramSerializationResultCancel(
        owned(resultPreparations, preparation, 'Content Result preparation'));
    },
    advance(encoder: CommonObject, quantum: number) {
      const value = moon.clientProgramSerializationAdvance(
        owned(encoders, encoder, 'Content encoder'), quantum);
      // Charge the reported delta before handling failure. Converting a failed
      // poll directly to an exception would discard its already consumed work.
      return Object.freeze({ready: runtimeField(value, 0) as boolean, piece: runtimeField(value, 1) as string,
        work: runtimeField(value, 2) as number,
        issue: runtimeField(value, 3)});
    },
    finish(encoder: CommonObject) {
      const value = checked(moon.clientProgramSerializationFinish(
        owned(encoders, encoder, 'Content encoder')));
      return Object.freeze({name: runtimeField(value, 0) as string, mediaType: runtimeField(value, 1) as string,
        contentCid: runtimeField(value, 2) as string, sizeBytes: runtimeField(value, 3) as number,
        rowCount: runtimeField(value, 4) as number});
    },
    candidate(encoder: CommonObject, binding: unknown, limits: ReferenceLimits) {
      const value = checked(moon.clientProgramGeneratedContentCandidate(
        owned(encoders, encoder, 'Content encoder'), JSON.stringify(binding),
        ...referenceLimits(limits))) as CommonObject;
      candidates.add(value);
      return value;
    },
    recoveryCandidate(originalWire: string, binding: unknown, limits: ReferenceLimits) {
      const value = checked(moon.clientProgramStoredGeneratedContentCandidate(
        originalWire, JSON.stringify(binding), ...referenceLimits(limits))) as CommonObject;
      storedCandidates.add(value);
      return value;
    },
    inspect(candidate: CommonObject) {
      if (storedCandidates.has(candidate)) {
        const value = moon.clientProgramStoredGeneratedContentStorage(candidate);
        const wire = moon.clientProgramStoredGeneratedContentCandidateWire(candidate);
        const body = JSON.parse(wire) as GeneratedWire;
        return Object.freeze({wire, identity: runtimeField(value, 0) as string,
          storeCid: runtimeField(value, 1) as string, workspaceScopeCid: runtimeField(value, 2) as string,
          contentCid: runtimeField(value, 3) as string, sizeBytes: runtimeField(value, 4) as number, mediaType: body.media_type,
          effectiveDataPolicyCid: body.metadata.effective_data_policy_cid});
      }
      owned(candidates, candidate, 'Content candidate');
      const value = moon.clientProgramGeneratedContentStorage(candidate);
      const wire = moon.clientProgramGeneratedContentCandidateWire(candidate);
      // This body was constructed by the common owner, not admitted from
      // provider/author JSON. No identity is computed or normalized here.
      const body = JSON.parse(wire) as GeneratedWire;
      return Object.freeze({wire,
        identity: moon.clientProgramGeneratedContentCandidateCid(candidate),
        storeCid: runtimeField(value, 0) as string, workspaceScopeCid: runtimeField(value, 1) as string,
        contentCid: runtimeField(value, 2) as string, sizeBytes: runtimeField(value, 3) as number,
        mediaType: body.media_type,
        effectiveDataPolicyCid: body.metadata.effective_data_policy_cid});
    },
    issuer(validate: ValidateContent, authorize: AuthorizeReference) {
      if (typeof validate !== 'function' || typeof authorize !== 'function') {
        throw new TypeError('Invalid Content issuer callbacks');
      }
      const issuer = moon.clientProgramRowReferenceIssuer(() => false,
        validate, authorize);
      issuers.add(issuer);
      return issuer;
    },
    issue(candidate: CommonObject, issuer: CommonObject, limits: ReferenceLimits) {
      const restored = storedCandidates.has(candidate);
      const content = checked((restored ? moon.clientProgramIssueStoredGeneratedContent
        : moon.clientProgramIssueGeneratedContent)(
        owned(restored ? storedCandidates : candidates, candidate, 'Content candidate'),
        owned(issuers, issuer, 'Content issuer'), ...referenceLimits(limits))) as CommonObject;
      issued.add(content);
      return content;
    },
  });
}
