import {validWirePlanViewShape} from '../../packages/client-wire/index.mjs';
import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Contract = Readonly<{identity: string; wire: string}>;
type PlanWires = Readonly<{compiledPlanWire: string; planViewWire: string}>;
type PlanEvidence = Readonly<{prepared: unknown; authorization: unknown}>;
type CompiledPlan = Readonly<{
  compiledPlan: Readonly<{wire: string}>;
  preparedEvidence: Readonly<{wire: string}>;
  authorization: Readonly<{wire: string}>;
}>;
type ExecutionOwner = Readonly<{compiled: unknown; program: unknown}>;
type ExplanationState = {
  preparation?: unknown;
  scope?: unknown;
  definition?: unknown;
  plan?: PlanWires;
  factsWire?: unknown;
  contextWire?: string;
  invocationTemplateWire?: string;
  journal?: unknown;
  offered?: boolean;
  acknowledged?: boolean;
  returning?: boolean;
  dispatchReady?: boolean;
  methods?: Readonly<{returnCapture(scope: unknown, definition: unknown, abandoned: boolean): unknown}>;
};
type RunPlanOwner = {
  original?: PlanWires;
  explanation?: ExplanationState;
  runDefinitionCid: string;
  programCid: string;
  prepared: unknown;
  authorization: unknown;
};
type RunPlanControl = Readonly<{
  originalRunPlanAdmissionEvidence(selected: unknown, definition: Contract,
    programCid: string, evidence: PlanEvidence | undefined): PlanWires | undefined;
  admit(name: string, wire: string, limits: Limits): Contract;
  admitRunEvidence(name: string, wire: string, limits: Limits): unknown;
}>;

// The installed Common namespace keeps its opaque compiler and evidence types.
type CommonRunPlanBindings = Readonly<{
  clientProgramAcknowledgeOriginalExplanationCapture(original: unknown): unknown;
  clientProgramCaptureRequestOriginalExplanation(original: unknown, compiled: unknown,
    definition: unknown): unknown;
  clientProgramCheckCompiledRunDefinition(compiled: unknown, definition: unknown): boolean;
  clientProgramCheckLogicalMapBinding(map: unknown, plan: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramCompileLocalEffects(prepared: unknown): unknown;
  clientProgramCompileLocalTasks(prepared: unknown): unknown;
  clientProgramCompileLocalValues(prepared: unknown): unknown;
  clientProgramCompiledRunMatches(value: unknown, prepared: unknown): boolean;
  clientProgramCompiledRunStaticPlanView(compiled: unknown, original: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramCurrentRunView(run: unknown, prepared: unknown, authorization: unknown,
    runRefWire: string, stateWire: string, snapshotCid: string, maxBytes: number, maxNodes: number,
    maxDepth: number, debugParkWire: string): unknown;
  clientProgramLocalDebugResumeReceiptConstructionBytes(maxBytes: number, maxNodes: number, maxDepth: number,
    issuing: boolean): unknown;
  clientProgramIssueLocalDebugResumeReceipt(run: unknown, command: unknown, parkWire: string, revision: number,
    acceptedAt: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramDefinitionCid(prepared: unknown): string;
  clientProgramEffectDefinitionCid(value: unknown): string;
  clientProgramEffectfulStaticPlanView(prepared: unknown, compiled: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramObserveOriginalDispatchFailure(original: unknown, host: unknown): unknown;
  clientProgramOriginalExplanationFactsWire(original: unknown): unknown;
  clientProgramOriginalExplanationPlanWire(original: unknown): unknown;
  clientProgramPrepareLogicalObservation(run: unknown, prepared: unknown, compiled: unknown,
    definition: unknown, bytes: number, nodes: number, depth: number): unknown;
  clientProgramReturnOriginalExplanationCapture(original: unknown): unknown;
  clientProgramTaskStaticPlanView(prepared: unknown, compiled: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  clientProgramValuesStaticPlanView(prepared: unknown, compiled: unknown, maxBytes: number,
    maxNodes: number, maxDepth: number): unknown;
  strategyPublicationContractIdentity(contract: unknown): string;
  strategyPublicationContractJson(contract: unknown): string;
}>;

type RunPlanPorts = Readonly<{
  compiledRunTokens: WeakMap<object, unknown>;
  originalRunPlanTokens: WeakMap<object, Readonly<RunPlanOwner>>;
  compiledRunResult: (result: unknown, code: string) => unknown;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  token: (value: unknown) => unknown;
  evidenceToken: (value: unknown) => unknown;
  currentControl: () => RunPlanControl;
  prepareLogicalObservation: CommonRunPlanBindings['clientProgramPrepareLogicalObservation'] | undefined;
  captureRequestExplanation: CommonRunPlanBindings['clientProgramCaptureRequestOriginalExplanation'] | undefined;
  originalExplanationPlanWire: CommonRunPlanBindings['clientProgramOriginalExplanationPlanWire'] | undefined;
  originalExplanationFactsWire: CommonRunPlanBindings['clientProgramOriginalExplanationFactsWire'] | undefined;
  returnExplanationCapture: CommonRunPlanBindings['clientProgramReturnOriginalExplanationCapture'] | undefined;
  acknowledgeExplanationCapture: CommonRunPlanBindings['clientProgramAcknowledgeOriginalExplanationCapture'] | undefined;
  observeOriginalDispatchFailure: CommonRunPlanBindings['clientProgramObserveOriginalDispatchFailure'] | undefined;
}>;

export function createRunPlanControls(moon: CommonRunPlanBindings, {
  compiledRunTokens, originalRunPlanTokens, compiledRunResult, issuanceLimits, token, evidenceToken,
  captureRequestExplanation, originalExplanationPlanWire, originalExplanationFactsWire, returnExplanationCapture,
  acknowledgeExplanationCapture, observeOriginalDispatchFailure, prepareLogicalObservation, currentControl,
}: RunPlanPorts) {
  return {
    readCurrentClientRunView(runDefinition: unknown, prepared: unknown, authorization: unknown,
      ref: unknown, state: unknown, snapshotCid: string, limits: Limits, debugParkWire = '') {
      if (typeof moon.clientProgramCurrentRunView !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'),
          {code: 'ClientOperationUnavailable'});
      }
      return compiledRunResult(moon.clientProgramCurrentRunView(
        token(runDefinition), evidenceToken(prepared), evidenceToken(authorization),
        JSON.stringify(ref), JSON.stringify(state), snapshotCid,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth, debugParkWire),
      'RunHostInspectRejected') as string;
    },
    readCheckedClientStaticPlan(checkedProgram: unknown, kind: string, limits: Limits) {
      if (!['values', 'tasks', 'effects'].includes(kind) ||
          !Number.isSafeInteger(limits?.maxWireBytes) || limits.maxWireBytes < 1 ||
          !Number.isSafeInteger(limits?.maxNodes) || limits.maxNodes < 1 ||
          !Number.isSafeInteger(limits?.maxDepth) || limits.maxDepth < 1) {
        throw new TypeError('InvalidClientStaticPlanRequest');
      }
      const compile = kind === 'effects' ? moon.clientProgramCompileLocalEffects
        : kind === 'values' ? moon.clientProgramCompileLocalValues
          : moon.clientProgramCompileLocalTasks;
      const project = kind === 'effects' ? moon.clientProgramEffectfulStaticPlanView
        : kind === 'values' ? moon.clientProgramValuesStaticPlanView
          : moon.clientProgramTaskStaticPlanView;
      if (typeof compile !== 'function' || typeof project !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'),
          {code: 'ClientOperationUnavailable'});
      }
      // Compile the original checked owner only. In particular, do not issue
      // an allowed Run, allocate a request identity or open an execution.
      const compiled = compiledRunResult(compile(checkedProgram),
        'RunHostCompilationRejected');
      return compiledRunResult(project(checkedProgram, compiled,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
      'RunHostStaticPlanRejected');
    },
    prepareClientLogicalObservation(run: unknown, executionOwner: ExecutionOwner | undefined,
      definition: unknown, limits: Limits) {
      issuanceLimits(limits, 'Original logical boundary');
      const compiled = compiledRunTokens.get(executionOwner?.compiled as object);
      const prepared = executionOwner?.program;
      if (compiled === undefined || prepared === undefined ||
          !moon.clientProgramCompiledRunMatches(compiled, prepared) ||
          !moon.clientProgramCheckCompiledRunDefinition(compiled, token(definition))) {
        throw new TypeError('Foreign Client logical boundary original');
      }
      if (typeof prepareLogicalObservation !== 'function') {
        throw new TypeError('ClientLogicalObservationUnavailable');
      }
      // Keep this actual typed Result intact so the receiving owner can take
      // its original failed-constructor cleanup token without parsing Errors.
      return Reflect.apply(prepareLogicalObservation, moon,
        [run, prepared, compiled, token(definition), limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth]);
    },
    captureOriginalClientRunPlan(compiled: CompiledPlan, original: unknown, definition: Contract,
      limits: Limits, explanation?: ExplanationState) {
      issuanceLimits(limits, 'Original Run plan');
      if (limits.maxWireBytes < 1 || limits.maxNodes < 1 || limits.maxDepth < 1) {
        throw new TypeError('Invalid Original Run plan issuance limits');
      }
      const value = compiledRunTokens.get(compiled);
      if (value === undefined ||
          !moon.clientProgramCompiledRunMatches(value, original) ||
          !moon.clientProgramCheckCompiledRunDefinition(value, token(definition))) {
        throw new TypeError('Foreign Client original plan compilation');
      }
      if (typeof moon.clientProgramCompiledRunStaticPlanView !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      let wire;
      if (explanation === undefined) {
        wire = compiledRunResult(moon.clientProgramCompiledRunStaticPlanView(
          value, original, limits.maxWireBytes, limits.maxNodes, limits.maxDepth),
        'RunHostOriginalPlanRejected');
      } else {
        if (explanation.preparation === undefined || explanation.scope !== undefined ||
            typeof captureRequestExplanation !== 'function' ||
            typeof originalExplanationPlanWire !== 'function' ||
            typeof originalExplanationFactsWire !== 'function' ||
            typeof returnExplanationCapture !== 'function') {
          throw new TypeError('Foreign Client original explanation preparation');
        }
        // Retain in the SAME managed Run before another current getter can
        // fail. The Core issuer validates the actual Request/Run/compiler;
        // neither this record nor equal wires supplies admission authority.
        explanation.scope = compiledRunResult(Reflect.apply(captureRequestExplanation, moon, [
          explanation.preparation, value, token(definition)]), 'RunHostOriginalExplanationRejected');
        explanation.preparation = undefined;
        wire = compiledRunResult(Reflect.apply(originalExplanationPlanWire, moon, [
          explanation.scope]), 'RunHostOriginalExplanationRejected');
        explanation.factsWire = compiledRunResult(Reflect.apply(originalExplanationFactsWire, moon, [
          explanation.scope]), 'RunHostOriginalExplanationRejected');
        if (typeof explanation.factsWire !== 'string' ||
            Buffer.byteLength(explanation.factsWire) > limits.maxWireBytes) {
          throw new TypeError('Invalid Client original explanation evidence');
        }
      }
      if (typeof compiled.compiledPlan.wire !== 'string' || typeof wire !== 'string' ||
          Buffer.byteLength(compiled.compiledPlan.wire) > limits.maxWireBytes ||
          Buffer.byteLength(wire) > limits.maxWireBytes) {
        throw new TypeError('Invalid Client original plan evidence');
      }
      const originalBytes = Object.freeze({compiledPlanWire: compiled.compiledPlan.wire,
        planViewWire: wire});
      const programCid = moon.clientProgramDefinitionCid(original);
      // The nominal compiler projection already bound its map to this Plan
      // and Program. Capture those immutable outputs, not a second stored-input
      // admission. Independent durable reads still use the full reader below.
      const selected = Object.freeze({});
      const retained: RunPlanOwner = {original: originalBytes,
        runDefinitionCid: definition.identity, programCid,
        prepared: compiled.preparedEvidence.wire, authorization: compiled.authorization.wire};
      if (explanation !== undefined) retained.explanation = explanation;
      originalRunPlanTokens.set(selected, Object.freeze(retained));
      return selected;
    },
    captureOriginalEffectRunPlan(explanation: ExplanationState, definition: Contract, prepared: unknown,
      evidence: PlanEvidence) {
      token(definition);
      if (explanation.scope === undefined || explanation.plan === undefined ||
          moon.strategyPublicationContractIdentity(explanation.definition) !== definition.identity ||
          moon.strategyPublicationContractJson(explanation.definition) !== definition.wire) {
        throw new TypeError('Foreign Client original Effect plan admission');
      }
      const selected = Object.freeze({});
      originalRunPlanTokens.set(selected, Object.freeze({explanation,
        runDefinitionCid: definition.identity, programCid: moon.clientProgramEffectDefinitionCid(prepared),
        prepared: evidence.prepared, authorization: evidence.authorization}));
      return selected;
    },
    originalRunPlanAdmissionEvidence(selected: unknown, definition: Contract, programCid: string,
      evidence: PlanEvidence | undefined) {
      const retained = originalRunPlanTokens.get(selected as object);
      // Exact first-admission provenance is independent of current read or
      // control permission. A copied wire/CID cannot create this selection.
      token(definition);
      if (retained === undefined || retained.runDefinitionCid !== definition.identity ||
          retained.programCid !== programCid || retained.prepared !== evidence?.prepared ||
          retained.authorization !== evidence?.authorization) {
        throw new TypeError('Foreign Client original plan admission');
      }
      return retained.original ?? retained.explanation?.plan;
    },
    originalRunExplanationAdmissionEvidence(selected: unknown, definition: Contract, programCid: string,
      evidence: PlanEvidence | undefined) {
      // Reuse the existing nominal original-Plan selection, not another
      // identity registry or a caller's structural wire/CID.
      currentControl().originalRunPlanAdmissionEvidence(selected, definition, programCid, evidence);
      const explanation = originalRunPlanTokens.get(selected as object)!.explanation;
      if (explanation === undefined || explanation.acknowledged ||
          typeof explanation.factsWire !== 'string' || explanation.scope === undefined) {
        throw new TypeError('Foreign Client original explanation admission');
      }
      explanation.offered = true;
      return Object.freeze(explanation.definition === undefined ? {factsWire: explanation.factsWire} : {
        factsWire: explanation.factsWire, contextWire: explanation.contextWire,
        invocationTemplateWire: explanation.invocationTemplateWire,
      });
    },
    originalRunExplanationAdmissionAcknowledged(selected: unknown, definition: Contract, programCid: string,
      evidence: PlanEvidence | undefined) {
      currentControl().originalRunPlanAdmissionEvidence(selected, definition, programCid, evidence);
      const explanation = originalRunPlanTokens.get(selected as object)!.explanation;
      if (explanation === undefined || !explanation.offered) {
        throw new TypeError('Foreign Client original explanation acknowledgement');
      }
      if (explanation.acknowledged && (explanation.scope === undefined || explanation.dispatchReady)) return;
      if (explanation.returning) throw new TypeError('RunHostOriginalExplanationCleanupPending');
      // The Journal has already dropped its transient Facts aliases after
      // actual COMMIT. Cut the last new managed payload BEFORE lower return
      // can settle/refund; retain the exact cleanup token on a declined return.
      explanation.factsWire = undefined;
      explanation.journal = undefined;
      explanation.acknowledged = true;
      explanation.returning = true;
      try {
        if (explanation.definition !== undefined) {
          explanation.contextWire = explanation.invocationTemplateWire = explanation.plan = undefined;
          compiledRunResult(explanation.methods!.returnCapture(explanation.scope, explanation.definition, true),
            'RunHostOriginalExplanationCleanupPending');
          explanation.scope = undefined;
        } else if (typeof acknowledgeExplanationCapture === 'function') {
          // The existing manager owns this SAME borrow through execution.
          // Journal ACK drops only committed payload aliases, not that owner.
          compiledRunResult(Reflect.apply(acknowledgeExplanationCapture, moon, [
            explanation.scope]), 'RunHostOriginalExplanationCleanupPending');
          explanation.dispatchReady = true;
        } else {
          // Old namespaces cannot supply a post-ACK original observation.
          compiledRunResult(Reflect.apply(returnExplanationCapture!, moon, [
            explanation.scope]), 'RunHostOriginalExplanationCleanupPending');
          explanation.scope = undefined;
        }
      } finally {explanation.returning = false;}
    },
    originalClientDispatchFailureAvailable(selected: unknown) {
      // Facility DATA only: the actual read still checks current and the SAME
      // Core owners. Unselected/old profiles allocate no observation callback.
      const explanation = originalRunPlanTokens.get(selected as object)?.explanation;
      return explanation?.dispatchReady === true && !explanation.returning &&
        explanation.scope !== undefined && typeof observeOriginalDispatchFailure === 'function';
    },
    observeOriginalClientDispatchFailure(selected: unknown, host: object) {
      const explanation = originalRunPlanTokens.get(selected as object)?.explanation;
      if (explanation?.dispatchReady !== true || explanation.returning ||
          explanation.scope === undefined || typeof observeOriginalDispatchFailure !== 'function') return undefined;
      return checked(Reflect.apply(observeOriginalDispatchFailure, moon, [explanation.scope, host]));
    },
    readStoredRunPlanOriginal(original: PlanWires, definition: Contract, programCid: string, limits: Limits) {
      token(definition);
      issuanceLimits(limits, 'Original Run plan');
      if (original === null || typeof original !== 'object' || Array.isArray(original) ||
          Object.keys(original).sort().join(',') !== 'compiledPlanWire,planViewWire' ||
          limits.maxWireBytes < 1 || limits.maxNodes < 1 || limits.maxDepth < 1 ||
          ['compiledPlanWire', 'planViewWire'].some(field =>
            typeof original[field as keyof PlanWires] !== 'string' || Buffer.byteLength(original[field as keyof PlanWires]) > limits.maxWireBytes)) {
        throw new TypeError('Invalid Client original plan evidence');
      }
      const plan = currentControl().admit('compiled_plan', original.compiledPlanWire, limits);
      const view = JSON.parse(original.planViewWire);
      if (!validWirePlanViewShape(view) ||
          plan.identity !== JSON.parse(definition.wire).compiled_plan_cid ||
          view.compiled_plan_cid !== plan.identity ||
          JSON.parse(plan.wire).program_definition_cid !== programCid) {
        throw new TypeError('Foreign Client original plan evidence');
      }
      if (typeof moon.clientProgramCheckLogicalMapBinding !== 'function') {
        throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
      }
      const map = currentControl().admitRunEvidence('logical_map', JSON.stringify(view.logical_map), limits);
      compiledRunResult(moon.clientProgramCheckLogicalMapBinding(evidenceToken(map), token(plan),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostOriginalMapRejected');
      return original.planViewWire;
    },
  };
}
