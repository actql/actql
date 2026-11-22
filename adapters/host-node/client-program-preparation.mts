// Accept preparation only from the same installed Request owner.
// The returned original handle cannot independently authorize a Run.
import {validSubmitPreparationError} from
  '../../packages/client-wire/index.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsError, runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {types as nodeTypes} from 'node:util';
import {dispatchFailureSnapshot, dispatchFailureCodeSite} from './client-dispatch-diagnostic.mjs';

type CapacityPhase = 'request_snapshot' | 'source_free_plan';
type CapacityDimension = 'retention' | 'execution';
type CapacityRefusal = Readonly<{
  phase: CapacityPhase;
  dimension: CapacityDimension;
  requiredRetentionBytes: string;
  requiredExecutionBytes: string;
  availableRetentionBytes: string;
  availableExecutionBytes: string;
}>;
type OriginalRefusal = (CapacityRefusal & {problemCode?: never; refusalCode?: never}) |
  Readonly<{problemCode: string; refusalCode: string}>;
type IssueProjection = (result: unknown) => string | undefined;
type CapacityProjection = (result: unknown) => unknown;
type PreparationRuntime = Readonly<{
  clientProgramRequestPreparationIssueCode?: IssueProjection;
  clientProgramRequestProgramModuleCapacityRefusal?: CapacityProjection;
}>;
type SnapshotRuntime = Readonly<{clientProgramRequestSnapshotCapacityRefusal?: CapacityProjection}>;
type InstallationRuntime = Readonly<{
  clientProgramValuesMaxRows?(prepared: object): number;
  clientSubmittedIntentEffectCompatible?(intent: unknown, prepared: object): boolean;
}>;
type RestoredInfer = Readonly<{prepared?: object; compiled?: unknown; graph?: unknown; runDefinition?: unknown; then?: unknown}>;
type OriginalInputs = Readonly<{environment?: unknown; parameters?: unknown; inferRun?: RestoredInfer}> &
  Readonly<Record<string, unknown>>;
type FundedOriginal = Readonly<{kind: string; prepared: unknown; originalInputs?: OriginalInputs}>;
type Installation<Request extends object, Policy> = {
  moon: InstallationRuntime;
  environment: unknown;
  allowEffects?: boolean;
  valuesMaxRows?: number;
  verifyRequestValuePolicy?: Policy;
  restoreEffectOriginal?: (original: unknown) => Readonly<{prepared?: object; compilation?: unknown}> | null | undefined;
  restoreInferOriginal?: (original: unknown, definition: unknown, request: unknown, evidence: unknown,
    restorationRequest: unknown) => RestoredInfer | null | undefined;
  getFundedPreparation?: (request: Request, environment: unknown, verifier: Policy | undefined,
    signal: AbortSignal | undefined) => FundedOriginal | null | undefined | Promise<FundedOriginal | null | undefined>;
};
type FailedPreparation<Requested, Refusal> = Readonly<{
  error: unknown; requested: Requested; prepared: unknown; sourceRefusal: Refusal;
}>;
type ObserveFailure = (phase: 'preparation_failed', record: Readonly<{
  boundary: 'request_admission'; available: boolean;
  primaryDiagnostic?: Readonly<Record<string, unknown>>; capacity?: CapacityRefusal;
}>) => unknown;

const preparationErrorType = Error;
const preparationStackFormatter = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace')?.value;

const issueCodes = Object.freeze({
  invalid_format: 'ClientProgramInvalidInput',
  supplied_syntax: 'ClientParametersInvalid',
  supplied_admission: 'ClientParametersInvalid',
  supplied_too_large: 'ClientParametersTooLarge',
  program_syntax: 'ClientProgramInvalidInput',
  effect_not_supported: 'ClientProgramUnsupported',
  values_profile_unsupported: 'ClientProgramUnsupported',
  debug_profile_unsupported: 'ClientProgramUnsupported',
  debug_graph_construction_overflow: 'ClientProgramAnalysisLimit',
  // Only explicit capability/extent variants above prove a preparation
  // refusal. A foreign or invalid selected graph remains an actual failure.
  debug_graph_rejected: 'ClientProgramPreparationFailure',
  needs_inputs: 'ClientProgramNeedsInputs',
  check_invalid_input: 'ClientProgramInvalidInput',
  ClientProgramParameterUndeclared: 'ClientProgramInvalidInput',
  ClientProgramTimestampPatternInvalid: 'ClientProgramInvalidInput',
  ClientProgramAggregateOrderRequired: 'ClientProgramInvalidInput',
  ClientProgramOrderUnresolved: 'ClientProgramRejected',
  ClientSuppliedParameterUndeclared: 'ClientParametersInvalid',
  // A typed checker configuration refusal precedes submission and Run admission.
  check_invalid_configuration: 'ClientProgramRejected',
  check_unsupported: 'ClientProgramImplementationLimit',
  check_compile_limit: 'ClientProgramAnalysisLimit',
  check_missing_input: 'ClientProgramNeedsInputs',
  check_unclassified: 'ClientProgramPreparationFailure',
  missing_checked_stage: 'ClientProgramRejected',
  missing_stage_identity: 'ClientProgramRejected',
  lowering_rejected: 'ClientProgramRejected',
  binding_rejected: 'ClientProgramRejected',
  graph_rejected: 'ClientProgramRejected',
  source_invalid_input: 'ClientProgramInvalidInput',
  source_rejected: 'ClientProgramRejected',
  source_unresolved: 'ClientProgramRejected',
  source_unsupported: 'ClientProgramRejected',
  // Only the original frontend's typed implementation limits select this
  // category. The submission's current disclosure gate still owns visibility.
  source_implementation_limit: 'ClientProgramImplementationLimit',
  source_analysis_limit: 'ClientProgramAnalysisLimit',
  source_missing_input: 'ClientProgramNeedsInputs',
  source_declarations: 'ClientParametersInvalid',
  source_limit: 'ClientProgramRejected',
  source_encoding: 'ClientProgramPreparationFailure',
  // Exact Common quote failure before provider construction/Run admission.
  // No numeric amounts are available, and unrelated failures stay uncertain.
  source_free_metadata_capacity_unavailable: 'ClientProgramRejected',
});
const effectIssueCodes = Object.freeze({
  invalid_format: 'ClientProgramInvalidInput',
  supplied_syntax: 'ClientParametersInvalid',
  supplied_admission: 'ClientParametersInvalid',
  invalid_input_owner: 'ClientParametersInvalid',
  program_syntax: 'ClientProgramInvalidInput',
  effect_candidate_rejected: 'ClientProgramRejected',
  effect_mapping_rejected: 'ClientProgramRejected',
  effect_static_rejected: 'ClientProgramRejected',
  stage_rejected: 'ClientProgramRejected',
  graph_rejected: 'ClientProgramRejected',
});
if ([...Object.values(issueCodes), ...Object.values(effectIssueCodes)]
  .some(code => code !== 'ClientProgramPreparationFailure' &&
    !validSubmitPreparationError({code}))) {
  throw new Error('StaleClientProgramErrorProjection');
}

// Only this projection owns these immutable facts. A copied/mutable error
// property or a lookalike Host exception cannot issue a capacity diagnostic.
const capacityRefusals = new WeakMap<object, OriginalRefusal>();
const originalLimitCodes = new Set<string | undefined>([
  'ClientProgramRuntimeFragmentWorkLimit',
  'ClientProgramNormalizationWorkLimit',
  'ClientProgramNormalizationRetentionLimit',
  'ClientProgramNormalizationExecutionLimit',
  'ClientProgramAuthoringWorkLimit',
  'ClientProgramAuthoringRetentionLimit',
  'ClientProgramAuthoringExecutionLimit',
]);
function originalPreparationRefusal(error: unknown) {
  return error !== null && (typeof error === 'object' || typeof error === 'function')
    ? capacityRefusals.get(error) : undefined;
}
export function requestProgramCapacityRefusal(error: unknown) {
  const original = originalPreparationRefusal(error);
  return original?.problemCode === undefined ? original : undefined;
}
export function requestProgramPreparationProblemCode(error: unknown) {
  const original = originalPreparationRefusal(error);
  return original?.problemCode;
}
export function requestProgramPreparationRefusalCode(error: unknown) {
  return originalPreparationRefusal(error)?.refusalCode;
}
// Preserve the existing failed-admission association BEFORE optional delivery.
// Diagnostics carry only existing original projections, never the thrown
// object/cause or a new acceptance/refusal classification. This always throws
// the SAME primary, including undefined; cleanup remains with its caller.
export function retainPreparedSubmissionFailure<Submission extends object & {preparedProgram?: unknown}, Requested, Refusal>(
  failures: Pick<WeakMap<Submission, FailedPreparation<Requested, Refusal>>, 'set'>,
  submission: Submission, error: unknown, requested: Requested, sourceRefusal: Refusal, observe?: ObserveFailure,
) {
  failures.set(submission, Object.freeze({error, requested,
    prepared: submission.preparedProgram, sourceRefusal}));
  if (observe !== undefined) try {
    let primaryDiagnostic;
    if (!nodeTypes.isProxy(error) && nodeTypes.isNativeError(error)) {
      primaryDiagnostic = dispatchFailureSnapshot(error)?.primaryDiagnostic ??
        dispatchFailureCodeSite(error, preparationErrorType, preparationStackFormatter);
    }
    const capacity = requestProgramCapacityRefusal(error);
    // This phase spelling describes this optional catch observation only;
    // it does not issue a durable submission phase or prove nonacceptance.
    observe('preparation_failed', Object.freeze({boundary: 'request_admission',
      available: primaryDiagnostic !== undefined || capacity !== undefined,
      ...(primaryDiagnostic === undefined ? {} : {primaryDiagnostic}),
      ...(capacity === undefined ? {} : {capacity})}));
  } catch { /* The original failure and awaited cleanup must remain primary. */ }
  throw error;
}

function projectCapacityRefusal(moon: PreparationRuntime, result: unknown) {
  const project = moon.clientProgramRequestProgramModuleCapacityRefusal;
  if (typeof project !== 'function') fail('InvalidHostRuntimeResult');
  const value = Reflect.apply(project, moon, [result]);
  if (value === undefined) fail('InvalidHostRuntimeResult');
  return capacityRefusalValue(value, 'source_free_plan');
}
function capacityRefusalValue(value: unknown, expectedPhase: CapacityPhase): CapacityRefusal {
  const phase = runtimeField(value, 0) as CapacityPhase, dimension = runtimeField(value, 1) as CapacityDimension;
  const amounts = [2, 3, 4, 5].map(index => runtimeField(value, index)) as bigint[];
  if (phase !== expectedPhase || !['retention', 'execution'].includes(dimension) ||
      amounts.some(amount => typeof amount !== 'bigint' || amount < 0n || amount > 9223372036854775807n) ||
      (dimension === 'retention' ? amounts[0] <= amounts[2]
        : amounts[0] > amounts[2] || amounts[1] <= amounts[3])) fail('InvalidHostRuntimeResult');
  return Object.freeze({phase, dimension,
    requiredRetentionBytes: amounts[0].toString(), requiredExecutionBytes: amounts[1].toString(),
    availableRetentionBytes: amounts[2].toString(), availableExecutionBytes: amounts[3].toString()});
}

// Preserve the original checked error and its Core cause. Only the fixed
// snapshot projection can add diagnostic DATA to the existing association.
export function checkedRequestSnapshotPreparation(moon: SnapshotRuntime, result: unknown) {
  const project = moon.clientProgramRequestSnapshotCapacityRefusal;
  if (runtimeIsError(result) && typeof project === 'function') {
    const value = Reflect.apply(project, moon, [result]);
    if (value !== undefined) {
      const capacity = capacityRefusalValue(value, 'request_snapshot');
      try {return checked(result);}
      catch (error) {capacityRefusals.set(error as object, capacity); throw error;}
    }
  }
  return checked(result);
}

// Read only the original typed Request result. The existing Common projection
// owns categories; JS never decodes an error constructor or checks input again.
// Foreign/current/general capacity/Host failures stay uncertain. Only the exact
// configured source-free Plan refusal below proves pre-admission nonexecution.
export function checkedRequestProgramPreparation(moon: PreparationRuntime, result: unknown,
  projectIssue: IssueProjection | undefined = moon.clientProgramRequestPreparationIssueCode) {
  if (runtimeIsError(result)) {
    const category = projectIssue!.call(moon, result);
    if (originalLimitCodes.has(category)) {
      // Keep the existing trusted submit-refusal code. Only the same typed
      // result may supply its reached Core cause on the open Problem surface.
      const error = Object.assign(new Error('ClientProgramRejected', {cause: runtimeField(result, 0)}),
        {code: 'ClientProgramRejected'});
      capacityRefusals.set(error, Object.freeze({problemCode: category!,
        refusalCode: 'ClientProgramRejected'}));
      throw error;
    }
    if (category === 'source_free_capacity_exceeded') {
      const capacity = projectCapacityRefusal(moon, result);
      // Existing operation_failed refusal: no claim that the Program is
      // semantically invalid or unsupported, and no public wire extension.
      const error = Object.assign(new Error('ClientProgramRejected', {cause: runtimeField(result, 0)}),
        {code: 'ClientProgramRejected', capacity});
      capacityRefusals.set(error, capacity);
      throw error;
    }
    const code = issueCodes[category as keyof typeof issueCodes] ?? effectIssueCodes[category as keyof typeof effectIssueCodes];
    if (code !== undefined) {
      const error = Object.assign(new Error(code, {cause: runtimeField(result, 0)}), {code});
      if (category === 'ClientSuppliedParameterUndeclared' ||
          category === 'ClientProgramParameterUndeclared' ||
          category === 'ClientProgramTimestampPatternInvalid' ||
          category === 'ClientProgramAggregateOrderRequired' ||
          category === 'ClientProgramOrderUnresolved') {
        // Core has proved the original fixed cause and its refusal category.
        // Preserve both facts, including operation_failed for unresolved order;
        // mutable error properties cannot change either original fact.
        capacityRefusals.set(error, Object.freeze({problemCode: category, refusalCode: code}));
      }
      throw error;
    }
  }
  return checked(result);
}

function fail(code: string, cause?: unknown): never {
  throw Object.assign(new Error(code, {cause}), {code});
}

export function installNodeClientProgramPreparation<Request extends object, Policy = never>({moon, environment,
  allowEffects = false, valuesMaxRows, verifyRequestValuePolicy,
  restoreEffectOriginal, restoreInferOriginal, getFundedPreparation}: Installation<Request, Policy>) {
  if (!moon || environment === undefined || typeof allowEffects !== 'boolean' ||
      typeof getFundedPreparation !== 'function' ||
      (restoreEffectOriginal !== undefined && typeof restoreEffectOriginal !== 'function') ||
      (restoreInferOriginal !== undefined && typeof restoreInferOriginal !== 'function') ||
      (verifyRequestValuePolicy !== undefined && typeof verifyRequestValuePolicy !== 'function')) {
    throw new TypeError('InvalidClientProgramPreparationInstallation');
  }
  if (valuesMaxRows !== undefined && (!Number.isSafeInteger(valuesMaxRows) ||
      valuesMaxRows < 1 || valuesMaxRows > 2147483647 ||
      typeof moon.clientProgramValuesMaxRows !== 'function' || allowEffects)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  const owned = new WeakMap<object, OriginalInputs>();
  const retiredOriginals = new WeakSet<object>();
  const effectOwned = new WeakSet<object>();
  let retired = false;
  const prepare = async (request: Request, selectedEnvironment = environment) => {
    if (retired) fail('ClientProgramPreparationFailure');
    try {
      const signal = (request as Request & {signal?: AbortSignal}).signal;
      const original = await getFundedPreparation!(request, selectedEnvironment,
        verifyRequestValuePolicy, signal);
      if (retired) fail('ClientProgramPreparationFailure');
      signal?.throwIfAborted();
      if (original === undefined || original === null ||
          !['effect_free', 'effectful'].includes(original.kind) ||
          original.prepared === null || typeof original.prepared !== 'object' ||
          original.originalInputs?.environment !== selectedEnvironment ||
          original.originalInputs!.parameters !== undefined &&
            typeof original.originalInputs!.parameters !== 'string') {
        fail('ClientProgramPreparationFailure');
      }
      const prepared = original.prepared;
      if (original.kind === 'effectful') {
        if (!allowEffects) fail('ClientProgramUnsupported');
        effectOwned.add(prepared);
      } else {
        if (valuesMaxRows !== undefined &&
            moon.clientProgramValuesMaxRows!(prepared) !== valuesMaxRows) {
          fail('ClientProgramPreparationFailure');
        }
        // This is original DATA from the same fixed Request owner. It neither
        // certifies a Run nor supplies a second preparation/cleanup authority.
        owned.set(prepared, Object.freeze({...original.originalInputs}));
      }
      return prepared;
    } catch (error) {
      // A foreign constructor can throw any JS value. Keep that exact cause
      // in this attempt's failure carrier so even undefined/null cannot fall
      // through to a second public check or old preparation path.
      const failure = error !== null && (typeof error === 'object' || typeof error === 'function')
        ? error : Object.assign(new Error('ClientProgramPreparationFailure', {cause: error}),
          {code: 'ClientProgramPreparationFailure'});
      throw failure;
    }
  };
  // Trusted policy verification belongs to the funded Request before compile.
  // No completed-input reprepare or externally substituted Environment remains.
  return Object.freeze(Object.assign(prepare, {
    retireReferences() {
      if (retired) return;
      retired = true;
      environment = getFundedPreparation = undefined;
      // Installation callbacks may themselves retain the same Environment.
      verifyRequestValuePolicy = restoreEffectOriginal = restoreInferOriginal = undefined;
    },
    // Private installing Local cleanup owner only. This releases the exact
    // Pure preparation metadata, not the shared Environment or another Run.
    // Call only after all original borrowers have confirmed cleanup.
    retireOriginal(prepared: object) {
      if (retiredOriginals.has(prepared)) return;
      const original = owned.get(prepared);
      if (original === undefined || original.inferRun !== undefined) {
        throw new TypeError('Foreign Pure Client preparation');
      }
      owned.delete(prepared);
      retiredOriginals.add(prepared);
    },
    originalInputs(prepared: object) {
      const original = owned.get(prepared);
      if (original === undefined || original.inferRun !== undefined) {
        fail('ClientProgramPreparationFailure');
      }
      return original;
    },
    originalInferRun(prepared: object) {return owned.get(prepared)?.inferRun;},
    restoreInferOriginal(original: unknown, definition: unknown, request: unknown, evidence: unknown, restorationRequest: unknown) {
      if (restoreInferOriginal === undefined) fail('ClientProgramUnsupported');
      const restored = restoreInferOriginal(original, definition, request, evidence, restorationRequest);
      if (typeof restored?.then === 'function') {
        void Promise.resolve(restored).catch(() => {});
        fail('ClientProgramPreparationFailure');
      }
      if (restored?.prepared === undefined || restored?.compiled === undefined ||
          restored?.graph === undefined || restored?.runDefinition !== definition) {
        fail('ClientProgramPreparationFailure');
      }
      // This trusted callback uses the existing Common saved-material reader.
      // One entry retains its exact nominal pair; no copied public preparation
      // is admitted by adding an identity or a caller-provided ownership flag.
      owned.set(restored.prepared, Object.freeze({inferRun: restored}));
      return restored.prepared;
    },
    // Only the installed Host passes an original from its existing verified
    // Checkpoint custody. Public submit objects never enter this method.
    restoreOriginal(original: unknown) {
      if (!allowEffects || restoreEffectOriginal === undefined) fail('ClientProgramUnsupported');
      const restored = restoreEffectOriginal(original);
      if (restored?.prepared === undefined || restored?.compilation === undefined) {
        fail('ClientProgramPreparationFailure');
      }
      effectOwned.add(restored.prepared);
      return restored.prepared;
    },
    // Only the same installation's prepared owner reaches this boundary. The
    // submitted intent is the opaque original retained by the request journal;
    // no emitted row, final-stage inspection or Account decision stands in for
    // its complete Common Effect inventory.
    assertSubmittedIntent(prepared: object, intent: unknown) {
      if (!owned.has(prepared) && !effectOwned.has(prepared)) {
        throw new TypeError('Foreign Client preparation');
      }
      if (effectOwned.has(prepared) &&
          !moon.clientSubmittedIntentEffectCompatible!(intent, prepared)) {
        fail('ClientProgramRejected');
      }
    },
    assertOwned(prepared: object) {
      if (!owned.has(prepared) && !effectOwned.has(prepared)) {
        throw new TypeError('Foreign Client preparation');
      }
    },
    kindOf(prepared: object) {
      if (owned.has(prepared)) return 'effect_free';
      if (effectOwned.has(prepared)) return 'effectful';
      throw new TypeError('Foreign Client preparation');
    },
  }));
}
