import {createProjectedTypeSafeDecisionPreflight,requireTypeSafeOriginalTransportLimits} from './typesafe-decision.mjs';
import {fixedInferResponseLimits} from './bounded-response.mjs';

// Private installed adapter composition, not a Model executor or scheduler.
// Common owns the bounded projection and original Plan/Entry/response meaning.
// The caller must fund both cursors, escaped view, callbacks and SDK overlap.
export function createAdmittedTypeSafeDecisionPreflight({moon, admittedProvider,
  request, projectionLimits, signal, ...options}) {
  const keys = ['maxBytes', 'maxDepth', 'maxFrames', 'maxNodes', 'maxWork'];
  const descriptors = projectionLimits !== null && typeof projectionLimits === 'object' &&
    !Array.isArray(projectionLimits) ? Object.getOwnPropertyDescriptors(projectionLimits) : undefined;
  if (descriptors === undefined || Reflect.ownKeys(descriptors).length !== keys.length ||
      keys.some(key => !Object.hasOwn(descriptors[key] ?? {}, 'value'))) {
    throw new TypeError('InvalidNativeDecisionProjectionLimits');
  }
  const bounds = Object.freeze(Object.fromEntries(keys.map(key => [key, descriptors[key].value])));
  if (keys.some(key => !Number.isSafeInteger(bounds[key]) ||
      bounds[key] < (key === 'maxWork' ? 0 : 1) || bounds[key] > 2_147_483_647)) {
    throw new TypeError('InvalidNativeDecisionProjectionLimits');
  }
  const hooks = ['clientProgramStartNativeDecisionProjection',
    'clientProgramAdvanceNativeDecisionProjection', 'clientProgramRetireNativeDecisionProjection',
    'clientProgramRetireNativeDecisionRequest', 'clientProgramNativeDecisionRequestMatches',
    'clientProgramNativeDecisionRequestBinding', 'clientProgramNativeDecisionRequestWires',
    'clientProgramModelRequestPreflight', 'clientProgramModelAsyncNativeDecisionRequestPlan',
    'clientProgramModelPhysicalSavedNativeDecision'];
  if (hooks.some(name => typeof moon?.[name] !== 'function') ||
      admittedProvider === undefined || request === undefined || options.probability === undefined) {
    throw new TypeError('NativeDecisionProjectionRuntimeUnavailable');
  }
  options.responseLimits=fixedInferResponseLimits(options.responseLimits);
  requireTypeSafeOriginalTransportLimits(moon,options.profile,options.maxRequestBytes,options.responseLimits);
  let cursor, projected, physical;
  let refused = false, retired = false;
  const checked = value => {
    if (value?.$tag !== 1) throw new TypeError('OriginalNativeDecisionProjectionRefused');
    return value._0;
  };
  const advance = () => {
    if (retired || refused || signal?.aborted) {refused = true; return {_0: true, _1: undefined};}
    try {
      if (physical === undefined) {
        if (cursor === undefined) {
          cursor = checked(moon.clientProgramStartNativeDecisionProjection(admittedProvider,
            request, bounds.maxBytes, bounds.maxNodes, bounds.maxDepth, bounds.maxFrames, bounds.maxWork));
          if (cursor === undefined) throw new TypeError('MissingOriginalNativeDecisionProjection');
          return {_0: false, _1: undefined};
        }
        projected = checked(moon.clientProgramAdvanceNativeDecisionProjection(cursor));
        if (projected === undefined) return {_0: false, _1: undefined};
        // The emitter and escaped original view have different lifetimes.
        // Retire the emitter before allocating SDK preparation, not the view.
        moon.clientProgramRetireNativeDecisionProjection(cursor);
        cursor = undefined;
        physical = createProjectedTypeSafeDecisionPreflight({...options, moon,
          admittedProvider, request, projected, signal});
        return {_0: false, _1: undefined};
      }
      // ModelRequestPreflight is the existing public-field Common data type.
      // The inner bridge's sole terminal refusal is InvalidProvider. Preserve
      // that refusal through the same outer bridge, without issuing a Plan.
      const result = physical.preflight.advance();
      if (result?.$tag !== 1) {refused = true; return {_0: true, _1: undefined};}
      return {_0: result._0 !== undefined, _1: result._0};
    } catch {
      refused = true;
      return {_0: true, _1: undefined};
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
    admittedProvider = request = signal = options = moon = undefined;
    retired = true;
    return true;
  };
  return Object.freeze({preflight: moon.clientProgramModelRequestPreflight(advance, cleanup)});
}
