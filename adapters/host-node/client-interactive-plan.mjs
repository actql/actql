// Static planning reuses the installed preparation and compiler owners. This
// service has no request journal, Source acquisition or execution dependency.
import {validWirePlanViewShape, validWireEffectfulStaticPlanViewShape,
  validWireExplanationFactsShape, validWireExplanationContextShape,
  withinResultDescriptionLimits, resultDescriptionLimits} from '../../packages/client-wire/index.mjs';

export function installClientStaticPlan({moon, control, prepare, authorize, readOriginal}) {
  if (typeof prepare !== 'function' || typeof prepare.assertOwned !== 'function' ||
      typeof prepare.kindOf !== 'function' || typeof authorize !== 'function' ||
      typeof control?.readCheckedClientStaticPlan !== 'function' ||
      typeof moon?.clientProgramRequiresTaskCompilation !== 'function' ||
      readOriginal !== undefined && typeof readOriginal !== 'function') {
    throw new TypeError('InvalidClientStaticPlanInstallation');
  }
  const denied = () => Object.assign(new Error('ClientConnectionDenied'),
    {code: 'ClientConnectionDenied'});
  return async request => {
    if (await authorize(request) !== true) throw denied();
    request.signal?.throwIfAborted();
    let kind, wire;
    if (readOriginal !== undefined) wire = await readOriginal(request);
    else {
      // Explicit compiler ports used by component callers. The installed
      // ordinary service always selects its held original read above.
      const prepared = await prepare(request);
      prepare.assertOwned(prepared);
      kind = prepare.kindOf(prepared) === 'effectful' ? 'effects'
        : moon.clientProgramRequiresTaskCompilation(prepared) ? 'tasks' : 'values';
      wire = control.readCheckedClientStaticPlan(prepared, kind, request);
    }
    if (typeof wire !== 'string' || Buffer.byteLength(wire, 'utf8') > request.maxWireBytes) {
      throw new TypeError('InvalidClientHostPlanView');
    }
    const view = JSON.parse(wire);
    if (!(kind === 'effects' ? validWireEffectfulStaticPlanViewShape(view)
      : validWirePlanViewShape(view) || kind === undefined && validWireEffectfulStaticPlanViewShape(view))) {
      throw new TypeError('InvalidClientHostPlanView');
    }
    // No prepared handle or Plan authority crosses the read boundary. Current
    // access is checked again after asynchronous preparation.
    request.signal?.throwIfAborted();
    if (await authorize(request) !== true) throw denied();
    return view;
  };
}

const explanationReplyOverhead = Buffer.byteLength('{"plan":,"facts":,"context":}', 'utf8');
const staticExplanationFailure = code => Object.assign(new Error(code), {code});

function assertSynchronousStaticCurrent(assertCurrent) {
  const result = assertCurrent();
  if (typeof result?.then === 'function') {
    void Promise.resolve(result).catch(() => {});
    throw staticExplanationFailure('StaticExplanationOriginalUnavailable');
  }
}

// The structural facets use the same already-issued Plan and Map. This is a
// consistency check of the typed compiler projection, never a permission.
function originalStaticExplanation({plan, facts, context}) {
  const view = plan.computation.plan_view;
  const binding = context.binding;
  return facts.program_definition_cid === plan.program_definition_cid &&
    binding.program_definition_cid === plan.program_definition_cid &&
    facts.parameter_values_cid === plan.parameter_values_cid &&
    binding.parameter_values_cid === plan.parameter_values_cid &&
    binding.check_environment_cid === plan.check_environment_cid &&
    facts.compiled_plan_cid === view.compiled_plan_cid &&
    binding.compiled_plan_cid === view.compiled_plan_cid &&
    facts.logical_map_cid === view.logical_map.self_cid &&
    binding.logical_map_cid === view.logical_map.self_cid;
}

// A private Host continuation for the structural projection. Its original
// preparation owner backs decoding, the combined response and consumption,
// retains that reservation until this visitor finishes, and supplies a
// synchronous assertion for the same original's current state.
export function installClientStaticEffectExplanation({authorize, authorizeEgress, withOriginal}) {
  if (typeof authorize !== 'function' || typeof authorizeEgress !== 'function' ||
      typeof withOriginal !== 'function') {
    throw new TypeError('InvalidClientStaticExplanationInstallation');
  }
  return async function readStaticEffectExplanation(request, consume) {
    if (typeof consume !== 'function') throw new TypeError('InvalidClientStaticExplanationConsumer');
    const {maxWireBytes, maxNodes, maxDepth, signal} = request;
    const limits = {maxWireBytes, maxNodes, maxDepth};
    for (const key of Object.keys(resultDescriptionLimits)) {
      if (!Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > resultDescriptionLimits[key]) {
        throw staticExplanationFailure('StaticExplanationReadLimit');
      }
    }
    let active = true;
    let entered = false;
    let completed = false;
    const assertActive = () => {
      if (!active) throw staticExplanationFailure('StaticExplanationOriginalUnavailable');
    };
    const requireConnection = async () => {
      assertActive();
      signal?.throwIfAborted();
      const connected = await authorize(request);
      assertActive();
      if (connected !== true) {
        throw staticExplanationFailure('StaticExplanationAccessDenied');
      }
      signal?.throwIfAborted();
    };
    const requireCurrentEgress = () => {
      assertActive();
      signal?.throwIfAborted();
      const decision = authorizeEgress(request);
      if (decision !== true) {
        if (typeof decision?.then === 'function') {
          void Promise.resolve(decision).catch(() => {});
        }
        throw staticExplanationFailure('StaticExplanationAccessDenied');
      }
      assertActive();
      signal?.throwIfAborted();
    };
    await requireConnection();
    requireCurrentEgress();
    async function consumeOriginal(wires, assertCurrent) {
      assertActive();
      if (entered || typeof assertCurrent !== 'function') {
        throw staticExplanationFailure('StaticExplanationOriginalUnavailable');
      }
      entered = true;
      await requireConnection();
      assertActive();
      assertSynchronousStaticCurrent(assertCurrent);
      requireCurrentEgress();
      if (wires === null || typeof wires !== 'object') {
        throw staticExplanationFailure('StaticExplanationEncodingRejected');
      }
      const {plan, facts, context} = wires;
      let remaining = maxWireBytes - explanationReplyOverhead;
      for (const value of [plan, facts, context]) {
        if (typeof value !== 'string') throw staticExplanationFailure('StaticExplanationEncodingRejected');
        if (value.length > remaining) {
          throw staticExplanationFailure('StaticExplanationReadLimit');
        }
        remaining -= Buffer.byteLength(value, 'utf8');
        if (remaining < 0) {
          throw staticExplanationFailure('StaticExplanationReadLimit');
        }
      }
      let view;
      try {
        view = {plan: JSON.parse(plan), facts: JSON.parse(facts), context: JSON.parse(context)};
      } catch {
        throw staticExplanationFailure('StaticExplanationEncodingRejected');
      }
      if (!withinResultDescriptionLimits(view, limits)) throw staticExplanationFailure('StaticExplanationReadLimit');
      if (!validWireEffectfulStaticPlanViewShape(view.plan) || !validWireExplanationFactsShape(view.facts) ||
          !validWireExplanationContextShape(view.context) || !originalStaticExplanation(view)) {
        throw staticExplanationFailure('StaticExplanationEncodingRejected');
      }
      await requireConnection();
      assertActive();
      assertSynchronousStaticCurrent(assertCurrent);
      // Keep the current Account observation in the same turn as the sink.
      requireCurrentEgress();
      const delivery = await consume(view);
      assertActive();
      completed = true;
      return delivery;
    }
    try {
      const result = await withOriginal(request, function visitOriginal(wires, assertCurrent) {
        const delivery = consumeOriginal(wires, assertCurrent);
        // An invalid owner can abandon the visit. Keep the same rejecting
        // promise available to an owner that awaits it.
        void delivery.catch(() => {});
        return delivery;
      });
      if (!completed) throw staticExplanationFailure('StaticExplanationOriginalUnavailable');
      return result;
    } finally {
      active = false;
    }
  };
}
