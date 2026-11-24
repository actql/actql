// Static planning reuses the installed preparation and compiler owners. This
// service has no request journal, Source acquisition or execution dependency.
import {validWirePlanViewShape, validWireEffectfulStaticPlanViewShape,
  validWireStaticExplanationViewShape, validStaticExplanationBinding,
  withinResultDescriptionLimits, resultDescriptionLimits} from '../../packages/client-wire/index.mjs';
import type {WirePlanView, WireEffectfulStaticPlanView, WireStaticExplanationView} from '../../packages/client-wire/interactive-control.generated.js';

type StaticPlanRequest = Readonly<{
  maxWireBytes: number;
  maxNodes: number;
  maxDepth: number;
  signal?: AbortSignal;
}>;
type StaticPlanKind = 'effects' | 'tasks' | 'values';
type StaticPlanView = WirePlanView | WireEffectfulStaticPlanView;
type StaticPlanInstallation<Request, Prepared> = Readonly<{
  moon: Readonly<{clientProgramRequiresTaskCompilation(prepared: Awaited<Prepared>): boolean}>;
  control: Readonly<{
    readCheckedClientStaticPlan(prepared: Awaited<Prepared>, kind: StaticPlanKind, request: Request): unknown;
  }>;
  prepare: ((request: Request) => Prepared) & Readonly<{
    assertOwned(prepared: Awaited<Prepared>): undefined;
    kindOf(prepared: Awaited<Prepared>): 'effectful' | 'effect_free';
  }>;
  authorize: (request: Request) => boolean | PromiseLike<boolean>;
  readOriginal?: (request: Request) => unknown;
}>;

export function installClientStaticPlan<Request extends StaticPlanRequest, Prepared>(
  {moon, control, prepare, authorize, readOriginal}: StaticPlanInstallation<Request, Prepared>,
): (request: Request) => Promise<StaticPlanView> {
  if (typeof prepare !== 'function' || typeof prepare.assertOwned !== 'function' ||
      typeof prepare.kindOf !== 'function' || typeof authorize !== 'function' ||
      typeof control?.readCheckedClientStaticPlan !== 'function' ||
      typeof moon?.clientProgramRequiresTaskCompilation !== 'function' ||
      readOriginal !== undefined && typeof readOriginal !== 'function') {
    throw new TypeError('InvalidClientStaticPlanInstallation');
  }
  const denied = () => Object.assign(new Error('ClientConnectionDenied'),
    {code: 'ClientConnectionDenied'});
  return async (request: Request) => {
    if (await authorize(request) !== true) throw denied();
    request.signal?.throwIfAborted();
    let kind: StaticPlanKind | undefined, wire: unknown;
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
    const view: unknown = JSON.parse(wire);
    if (!(kind === 'effects' ? validWireEffectfulStaticPlanViewShape(view)
      : validWirePlanViewShape(view) || kind === undefined && validWireEffectfulStaticPlanViewShape(view))) {
      throw new TypeError('InvalidClientHostPlanView');
    }
    // No prepared handle or Plan authority crosses the read boundary. Current
    // access is checked again after asynchronous preparation.
    request.signal?.throwIfAborted();
    if (await authorize(request) !== true) throw denied();
    return view as StaticPlanView;
  };
}

const staticExplanationVersion = 'actql-static-explanation/0.1';
const explanationReplyOverhead = Buffer.byteLength(
  `{"version":"${staticExplanationVersion}","plan":,"facts":,"context":}`, 'utf8');
type StaticExplanationWires = Readonly<{plan: unknown; facts: unknown; context: unknown}>;
type StaticCurrent = () => unknown;
type StaticExplanationInstallation<Request> = Readonly<{
  authorize(request: Request): unknown;
  authorizeEgress(request: Request): unknown;
  withOriginal<Value>(request: Request,
    visit: (wires: StaticExplanationWires, assertCurrent: StaticCurrent) => Promise<Value>): Value | PromiseLike<Value>;
}>;
const staticExplanationFailure = (code: string) => Object.assign(new Error(code), {code});

function assertSynchronousStaticCurrent(assertCurrent: StaticCurrent) {
  const result = assertCurrent();
  if (typeof (result as {then?: unknown} | null | undefined)?.then === 'function') {
    void Promise.resolve(result).catch(() => {});
    throw staticExplanationFailure('StaticExplanationOriginalUnavailable');
  }
}

// A private Host continuation for the structural projection. Its original
// preparation owner backs decoding, the combined response and consumption,
// retains that reservation until this visitor finishes, and supplies a
// synchronous assertion for the same original's current state.
export function installClientStaticEffectExplanation<Request extends StaticPlanRequest>({authorize, authorizeEgress, withOriginal}:
  StaticExplanationInstallation<Request>) {
  if (typeof authorize !== 'function' || typeof authorizeEgress !== 'function' ||
      typeof withOriginal !== 'function') {
    throw new TypeError('InvalidClientStaticExplanationInstallation');
  }
  return async function readStaticEffectExplanation<Value>(request: Request,
    consume: (view: WireStaticExplanationView) => Value | PromiseLike<Value>) {
    if (typeof consume !== 'function') throw new TypeError('InvalidClientStaticExplanationConsumer');
    const {maxWireBytes, maxNodes, maxDepth, signal} = request;
    const limits = {maxWireBytes, maxNodes, maxDepth};
    for (const key of Object.keys(resultDescriptionLimits) as (keyof typeof resultDescriptionLimits)[]) {
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
        if (typeof (decision as {then?: unknown} | null | undefined)?.then === 'function') {
          void Promise.resolve(decision).catch(() => {});
        }
        throw staticExplanationFailure('StaticExplanationAccessDenied');
      }
      assertActive();
      signal?.throwIfAborted();
    };
    await requireConnection();
    requireCurrentEgress();
    async function consumeOriginal(wires: StaticExplanationWires, assertCurrent: StaticCurrent) {
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
        view = {version: staticExplanationVersion,
          plan: JSON.parse(plan as string), facts: JSON.parse(facts as string), context: JSON.parse(context as string)};
      } catch {
        throw staticExplanationFailure('StaticExplanationEncodingRejected');
      }
      if (!withinResultDescriptionLimits(view, limits)) throw staticExplanationFailure('StaticExplanationReadLimit');
      if (!validWireStaticExplanationViewShape(view) || !validStaticExplanationBinding(view)) {
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
