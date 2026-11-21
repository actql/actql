// Static planning reuses the installed preparation and compiler owners. This
// service has no request journal, Source acquisition or execution dependency.
import {validWirePlanViewShape, validWireEffectfulStaticPlanViewShape} from '../../packages/client-wire/index.mjs';
import type {WirePlanView, WireEffectfulStaticPlanView} from '../../packages/client-wire/interactive-control.generated.js';

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
