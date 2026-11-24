import {runtimeField, runtimeIsOk, runtimePair} from './compiler-binding.generated.mjs';
import {createProjectedTypeSafeDecisionPreflight,requireTypeSafeOriginalTransportLimits} from './typesafe-decision.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';

type ProjectedInput = Parameters<typeof createProjectedTypeSafeDecisionPreflight>[0];
type ProjectedRuntime = ProjectedInput['moon'];
interface ProjectionRuntime extends ProjectedRuntime {
  clientProgramStartNativeDecisionProjection(provider: unknown, request: unknown,
    maxBytes: number, maxNodes: number, maxDepth: number, maxFrames: number, maxWork: number): unknown;
  clientProgramAdvanceNativeDecisionProjection(cursor: unknown): unknown;
  clientProgramRetireNativeDecisionProjection(cursor: unknown): unknown;
  clientProgramRetireNativeDecisionRequest(projected: unknown): unknown;
}
type AdmittedInput = Omit<ProjectedInput, 'moon' | 'projected'> & {
  moon: ProjectionRuntime; projectionLimits: unknown;
};
// ModelRequestPreflight's existing public callback fields, not an opaque
// payload decoder or a new issuer. Common and the original checks still own
// every accepted response, Plan, current binding and cleanup observation.
type PhysicalPreflightView = ReturnType<typeof createProjectedTypeSafeDecisionPreflight> & {
  preflight: {advance(): unknown; cleanup(): unknown};
};

// Private installed adapter composition, not a Model executor or scheduler.
// Common owns the bounded projection and original Plan/Entry/response meaning.
// The caller must fund both cursors, escaped view, callbacks and SDK overlap.
export function createAdmittedTypeSafeDecisionPreflight({moon, admittedProvider,
  request, projectionLimits, signal, ...options}: AdmittedInput) {
  const keys = ['maxBytes', 'maxDepth', 'maxFrames', 'maxNodes', 'maxWork'] as const;
  const descriptors = projectionLimits !== null && typeof projectionLimits === 'object' &&
    !Array.isArray(projectionLimits) ? Object.getOwnPropertyDescriptors(projectionLimits) : undefined;
  if (descriptors === undefined || Reflect.ownKeys(descriptors).length !== keys.length ||
      keys.some(key => !Object.hasOwn(descriptors[key] ?? {}, 'value'))) {
    throw new TypeError('InvalidNativeDecisionProjectionLimits');
  }
  const bounds = Object.freeze(Object.fromEntries(keys.map(key => [key, descriptors[key].value]))) as Readonly<Record<typeof keys[number], number>>;
  if (keys.some(key => !Number.isSafeInteger(bounds[key]) ||
      bounds[key] < (key === 'maxWork' ? 0 : 1) || bounds[key] > 2_147_483_647)) {
    throw new TypeError('InvalidNativeDecisionProjectionLimits');
  }
  const hooks = ['clientProgramStartNativeDecisionProjection',
    'clientProgramAdvanceNativeDecisionProjection', 'clientProgramRetireNativeDecisionProjection',
    'clientProgramRetireNativeDecisionRequest', 'clientProgramNativeDecisionRequestMatches',
    'clientProgramNativeDecisionRequestBinding', 'clientProgramNativeDecisionRequestWires',
    'clientProgramModelRequestPreflight', 'clientProgramModelAsyncNativeDecisionRequestPlan',
    'clientProgramModelPhysicalSavedNativeDecision'] as const;
  if (hooks.some(name => typeof moon?.[name] !== 'function') ||
      admittedProvider === undefined || request === undefined || options.probability === undefined) {
    throw new TypeError('NativeDecisionProjectionRuntimeUnavailable');
  }
  options.responseLimits=fixedInferResponseLimits(options.responseLimits!);
  requireTypeSafeOriginalTransportLimits(moon,options.profile,options.maxRequestBytes,options.responseLimits);
  let cursor: unknown, projected: unknown, physical: PhysicalPreflightView | undefined;
  let refused = false, retired = false;
  const checked = (value: unknown): unknown => {
    if (!runtimeIsOk(value)) throw new TypeError('OriginalNativeDecisionProjectionRefused');
    return runtimeField(value, 0);
  };
  const advance = () => {
    if (retired || refused || signal?.aborted) {refused = true; return runtimePair(true, undefined);}
    try {
      if (physical === undefined) {
        if (cursor === undefined) {
          cursor = checked(moon.clientProgramStartNativeDecisionProjection(admittedProvider,
            request, bounds.maxBytes, bounds.maxNodes, bounds.maxDepth, bounds.maxFrames, bounds.maxWork));
          if (cursor === undefined) throw new TypeError('MissingOriginalNativeDecisionProjection');
          return runtimePair(false, undefined);
        }
        projected = checked(moon.clientProgramAdvanceNativeDecisionProjection(cursor));
        if (projected === undefined) return runtimePair(false, undefined);
        // The emitter and escaped original view have different lifetimes.
        // Retire the emitter before allocating SDK preparation, not the view.
        moon.clientProgramRetireNativeDecisionProjection(cursor);
        cursor = undefined;
        physical = createProjectedTypeSafeDecisionPreflight({...options, moon,
          admittedProvider, request, projected, signal}) as PhysicalPreflightView;
        return runtimePair(false, undefined);
      }
      // ModelRequestPreflight is the existing public-field Common data type.
      // The inner bridge's sole terminal refusal is InvalidProvider. Preserve
      // that refusal through the same outer bridge, without issuing a Plan.
      const result = physical.preflight.advance();
      if (!runtimeIsOk(result)) {refused = true; return runtimePair(true, undefined);}
      return runtimePair(runtimeField(result, 0) !== undefined, runtimeField(result, 0));
    } catch {
      refused = true;
      return runtimePair(true, undefined);
    }
  };
  const cleanup = () => {
    if (retired) return true;
    // Common invokes this outer cursor after original physical-call/raw-usage
    // cleanup. The inner call's cleanup must not retire the escaped view early.
    try {
      if (physical !== undefined && physical.preflight.cleanup() !== true) return false;
      if (cursor !== undefined) {
        moon.clientProgramRetireNativeDecisionProjection(cursor);
        cursor = undefined;
      }
      if (projected !== undefined) {
        moon.clientProgramRetireNativeDecisionRequest(projected);
        projected = undefined;
      }
    } catch {return false;}
    physical = undefined;
    // Clear the terminal views in the original assignment order. These erased
    // casts cannot make a live runtime, option record or cleanup receipt.
    admittedProvider = request = signal =
      (options = (moon = undefined as unknown as typeof moon) as unknown as typeof options) as unknown as undefined;
    retired = true;
    return true;
  };
  return Object.freeze({preflight: moon.clientProgramModelRequestPreflight(advance, cleanup)});
}
