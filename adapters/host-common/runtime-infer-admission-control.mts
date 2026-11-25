import {runtimeField, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Definition = Readonly<{identity: string}>;
type Wire = Readonly<{wire: string}>;
type Contract = Wire & Readonly<{name: string; identityField: string; identity: string}>;
type Evidence = Wire & Readonly<{name: string; identity: string}>;
type EvidenceWires = Readonly<{prepared: unknown; authorization: unknown}>;
type ResultPolicy = Readonly<{kind: string; cid: string; wire: string}>;
type StoredMaterials = Readonly<{materialsWire: string; resultPolicyOriginal: ResultPolicy}>;
type CompiledInfer = Readonly<{kind: string; preparedEvidence: Wire; authorization: Wire}>;
type MaterialReservation = Readonly<{parent: unknown; input: unknown}>;
type Profiles = readonly [boolean, boolean, boolean, boolean, boolean, boolean, boolean];
type RetainedRun = EvidenceWires & Readonly<{original: StoredMaterials; runDefinitionCid: string; request: unknown}>;
type RestoredRun = Readonly<{compiled: CompiledInfer; prepared: unknown}>;
type InferAdmissionControl = Readonly<{
  compiledInferEvaluationPolicy(compiled: CompiledInfer): ResultPolicy | undefined;
  checkClientCompiledRunOwner(compiled: CompiledInfer, program: unknown): unknown;
}>;

// Common owns the material, compilation, Request, and graph handles.
type CommonInferAdmissionBindings = Readonly<{
  clientProgramAdmitInferRunMaterials(wire: string, expectedRunCid: string, textTime: boolean,
    veca: boolean, rela: boolean, sga: boolean, tea: boolean, calendar: boolean, textRank: boolean): unknown;
  clientProgramAdmitRequestInferRunMaterials(parent: unknown, input: unknown, request: unknown,
    definition: unknown, wire: string, textTime: boolean, veca: boolean, rela: boolean, sga: boolean,
    tea: boolean, calendar: boolean, textRank: boolean): unknown;
  clientProgramBindCompiledInferResultPolicy(compiled: unknown, cid: string, wire: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramCheckCompiledRunDefinition(compiled: unknown, definition: unknown): boolean;
  clientProgramCompiledInferOriginal(compiled: unknown, prepared: unknown): unknown;
  clientProgramCompiledInferOriginals(compiled: unknown, prepared: unknown): unknown;
  clientProgramCompiledRunAdmission(value: unknown): unknown;
  clientProgramCompiledRunAuthorization(value: unknown): unknown;
  clientProgramCompiledRunEvaluationPolicy(compiled: unknown): unknown;
  clientProgramCompiledRunMatches(value: unknown, prepared: unknown): boolean;
  clientProgramCompiledRunPlan(value: unknown): unknown;
  clientProgramCompiledRunPrepared(value: unknown): unknown;
  clientProgramCompiledRunTemplate(value: unknown): unknown;
  clientProgramInferRunMaterialsCompiled(materials: unknown): unknown;
  clientProgramInferRunMaterialsGraph(materials: unknown): unknown;
  clientProgramInferRunMaterialsGraphs(materials: unknown): unknown;
  clientProgramInferRunMaterialsPrepared(materials: unknown): unknown;
  clientProgramIssueInferRunMaterials(compiled: unknown, definition: unknown, environment: unknown,
    parameters: string | undefined): unknown;
  clientProgramIssueRequestInferRunMaterials(parent: unknown, input: unknown, compiled: unknown,
    definition: unknown): unknown;
  clientProgramMatchesRequestIdentity(prepared: unknown, request: unknown): boolean;
}>;

type InferAdmissionPorts = Readonly<{
  originalInferRunTokens: WeakMap<object, RetainedRun>;
  compiledRunTokens: WeakMap<object, unknown>;
  restoredInferRuns: WeakSet<object>;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  compiledRunResult: (result: unknown, code: string) => unknown;
  token: (contract: unknown) => unknown;
  inspect: (value: unknown) => Contract;
  inspectEvidence: (value: unknown) => Evidence;
  inspectAdmission: (value: unknown) => Readonly<{kind: 'run-publication-admission'}>;
  currentControl: () => InferAdmissionControl;
}>;

export function createInferAdmissionControls(moon: CommonInferAdmissionBindings, {
  originalInferRunTokens, compiledRunTokens, restoredInferRuns, issuanceLimits,
  compiledRunResult, token, inspect, inspectEvidence, inspectAdmission, currentControl,
}: InferAdmissionPorts) {
  return {
    // First admission retains only the actual compiler owner and its original
    // Result policy. A copied wire cannot supply the journal's original ticket.
    captureOriginalClientInferRun(compiled: CompiledInfer, checkedProgram: unknown, definition: Definition,
      request: unknown, environment: string | undefined, parameters: string | undefined, funded?: MaterialReservation) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCompiledRunMatches(value, checkedProgram) ||
          !moon.clientProgramMatchesRequestIdentity(checkedProgram, request) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original Infer Run');
      }
      const resultPolicyOriginal = currentControl().compiledInferEvaluationPolicy(compiled);
      if (resultPolicyOriginal === undefined) throw new TypeError('Missing Client original Infer Result policy');
      // Installed capture has a required same-Request constructor. A missing
      // funded port must never fall back to the standalone wire projection.
      let materialsWire;
      if (funded === undefined) {
        materialsWire = compiledRunResult(moon.clientProgramIssueInferRunMaterials(
          value, token(definition), environment!, parameters!), 'RunHostInferMaterialsRejected') as string;
      } else {
        if (funded?.parent === undefined || funded.input === undefined ||
            typeof moon.clientProgramIssueRequestInferRunMaterials !== 'function') {
          throw new TypeError('Missing Client original Infer material reservation');
        }
        materialsWire = compiledRunResult(moon.clientProgramIssueRequestInferRunMaterials(
          funded.parent, funded.input, value, token(definition)), 'RunHostInferMaterialsRejected') as string;
      }
      const selected = Object.freeze({});
      originalInferRunTokens.set(selected, Object.freeze({
        original: Object.freeze({materialsWire, resultPolicyOriginal}),
        runDefinitionCid: definition.identity,
        request,
        prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire,
      }));
      return selected;
    },
    originalInferRunAdmissionEvidence(selected: unknown, definition: Definition, request: unknown, evidence: EvidenceWires | undefined) {
      const retained = originalInferRunTokens.get(selected as object);
      token(definition);
      if (retained === undefined || retained.runDefinitionCid !== definition.identity ||
          retained.request !== request || retained.prepared !== evidence?.prepared ||
          retained.authorization !== evidence?.authorization) {
        throw new TypeError('Foreign Client original Infer admission');
      }
      return retained.original;
    },
    // The same journal's already selected Run supplies the expected original.
    // Current installation, authority and physical input custody are not read or
    // issued here. The returned preparation and graph must stay together.
    admitStoredClientInferRunOriginal(original: StoredMaterials, definition: Definition, request: unknown,
      evidence: EvidenceWires | undefined, profiles: Profiles, limits: Limits, recovery?: MaterialReservation) {
      token(definition);
      issuanceLimits(limits, 'Original Infer Run');
      const keys = original === null || typeof original !== 'object' || Array.isArray(original)
        ? [] : Object.keys(original);
      if (keys.length !== 2 || !keys.includes('materialsWire') || !keys.includes('resultPolicyOriginal') ||
          typeof original.materialsWire !== 'string' || original.materialsWire.length === 0 ||
          Buffer.byteLength(original.materialsWire) > limits.maxWireBytes ||
          !Array.isArray(profiles) || profiles.length !== 7 || profiles.some(value => typeof value !== 'boolean')) {
        throw new TypeError('Invalid Client original Infer materials');
      }
      // A Source-backed Run retains its checked publication policy, not the
      // source-free unknown policy. This copy is evidence only: after restoring
      // the original compiler Owner, compare its complete policy below.
      const savedPolicy = original.resultPolicyOriginal;
      if (savedPolicy === null || typeof savedPolicy !== 'object' || Array.isArray(savedPolicy) ||
          Object.keys(savedPolicy).sort().join(',') !== 'cid,kind,wire' ||
          savedPolicy.kind !== 'data_policy' || typeof savedPolicy.cid !== 'string' ||
          typeof savedPolicy.wire !== 'string' || savedPolicy.wire.length === 0 ||
          Buffer.byteLength(savedPolicy.cid) > limits.maxWireBytes ||
          Buffer.byteLength(savedPolicy.wire) > limits.maxWireBytes) {
        throw new TypeError('Invalid Client original Infer Result policy');
      }
      const policy = Object.freeze({kind: savedPolicy.kind, cid: savedPolicy.cid, wire: savedPolicy.wire});
      let materials, authoringContextOriginal;
      if (recovery === undefined) {
        // Existing explicit standalone consumers retain their separate path.
        materials = compiledRunResult(moon.clientProgramAdmitInferRunMaterials(
          original.materialsWire, definition.identity, ...(profiles as Profiles)), 'RunHostInferMaterialsRejected');
      } else {
        const admit = moon.clientProgramAdmitRequestInferRunMaterials;
        if (typeof admit !== 'function' || recovery.parent === undefined || recovery.input === undefined) {
          throw new TypeError('Installed Model recovery material constructor unavailable');
        }
        const originals = compiledRunResult(Reflect.apply(admit, moon, [
          recovery.parent, recovery.input, request, token(definition), original.materialsWire, ...profiles,
        ]), 'RunHostInferMaterialsRejected');
        materials = runtimeField(originals, 0);
        authoringContextOriginal = runtimeField(originals, 1);
        if (materials === undefined || authoringContextOriginal === undefined) {
          throw new TypeError('Missing Client original Infer material custody');
        }
      }
      let value = compiledRunResult(moon.clientProgramInferRunMaterialsCompiled(materials),
        'RunHostInferMaterialsRejected');
      const prepared = moon.clientProgramInferRunMaterialsPrepared(materials);
      const graphs = typeof moon.clientProgramInferRunMaterialsGraphs === 'function'
        ? moon.clientProgramInferRunMaterialsGraphs(materials)
        : [moon.clientProgramInferRunMaterialsGraph(materials)];
      if (!Array.isArray(graphs) || graphs.length < 1 || graphs.length > 128 ||
          graphs.some(graph => graph === undefined || graph === null) ||
          !moon.clientProgramMatchesRequestIdentity(prepared, request) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition)) ||
          inspectEvidence(moon.clientProgramCompiledRunPrepared(value)).wire !== evidence?.prepared ||
          inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)).wire !== evidence?.authorization) {
        throw new TypeError('Foreign Client original Infer materials');
      }
      value = compiledRunResult(moon.clientProgramBindCompiledInferResultPolicy(value,
        policy.cid, policy.wire, limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostResultPolicyRejected');
      const actualPolicy = moon.clientProgramCompiledRunEvaluationPolicy(value);
      if (actualPolicy === undefined || runtimeField(actualPolicy, 0) !== policy.kind ||
          runtimeField(actualPolicy, 1) !== policy.cid || runtimeField(actualPolicy, 2) !== policy.wire) {
        throw new TypeError('Foreign Client original Infer Result policy');
      }
      const compiled = Object.freeze({kind: 'infer',
        template: inspectEvidence(moon.clientProgramCompiledRunTemplate(value)),
        compiledPlan: inspect(moon.clientProgramCompiledRunPlan(value)),
        preparedEvidence: inspectEvidence(moon.clientProgramCompiledRunPrepared(value)),
        authorization: inspectEvidence(moon.clientProgramCompiledRunAuthorization(value)),
        admission: inspectAdmission(moon.clientProgramCompiledRunAdmission(value))});
      compiledRunTokens.set(compiled, value);
      // The copied outer inventory is metadata for these same opaque members.
      // It grants no new preparation, current authority, budget or execution.
      const graph = graphs.length === 1 ? graphs[0] : Object.freeze([...graphs]);
      const restored = Object.freeze({compiled, prepared, graph, runDefinition: definition,
        ...(authoringContextOriginal === undefined ? {} : {authoringContextOriginal})});
      restoredInferRuns.add(restored);
      return restored;
    },
    checkRestoredClientInferRunOwner<Restored extends RestoredRun>(restored: Restored, checkedProgram: unknown) {
      if (!restoredInferRuns.has(restored) || restored.prepared !== checkedProgram) {
        throw new TypeError('Foreign Client restored Infer Run');
      }
      currentControl().checkClientCompiledRunOwner(restored.compiled, checkedProgram);
      return restored;
    },
    checkedClientCompiledInferOriginal(compiled: CompiledInfer, checkedProgram: unknown, definition: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original Infer compilation');
      }
      const original = moon.clientProgramCompiledInferOriginal(value, checkedProgram);
      if (original === undefined) throw new TypeError('Foreign Client original Infer preparation');
      return Object.freeze({graph: runtimeField(original, 0), execution: runtimeField(original, 1)});
    },
    checkedClientCompiledInferOriginals(compiled: CompiledInfer, checkedProgram: unknown, definition: unknown) {
      const value = compiledRunTokens.get(compiled);
      if (value === undefined || compiled.kind !== 'infer' ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition)) ||
          typeof moon.clientProgramCompiledInferOriginals !== 'function') {
        throw new TypeError('Foreign Client original Infer compilation');
      }
      const originalOption = moon.clientProgramCompiledInferOriginals(value, checkedProgram);
      // This exact export specializes Option<Array<Tuple>> as a boxed Option.
      // The singular tuple export above has a different, unboxed layout.
      const originals = runtimeIsBoxedSome(originalOption)
        ? runtimeField(originalOption, 0) : undefined;
      if (!Array.isArray(originals) || originals.length < 1 || originals.length > 128 ||
          originals.some(original => runtimeField(original, 0) === undefined ||
            runtimeField(original, 1) === undefined)) {
        throw new TypeError('Foreign Client original Infer preparation');
      }
      return Object.freeze(originals.map(original => Object.freeze({
        graph: runtimeField(original, 0), execution: runtimeField(original, 1)})));
    },
  };
}
