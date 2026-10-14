// Static planning reuses the installed preparation and compiler owners. This
// service has no request journal, Source acquisition or execution dependency.
import {validWirePlanViewShape} from '../../packages/client-wire/index.mjs';

export function installClientStaticPlan({moon, control, prepare, authorize}) {
  if (typeof prepare !== 'function' || typeof prepare.assertOwned !== 'function' ||
      typeof prepare.kindOf !== 'function' || typeof authorize !== 'function' ||
      typeof control?.readCheckedClientStaticPlan !== 'function' ||
      typeof moon?.clientProgramRequiresTaskCompilation !== 'function') {
    throw new TypeError('InvalidClientStaticPlanInstallation');
  }
  const denied = () => Object.assign(new Error('ClientConnectionDenied'),
    {code: 'ClientConnectionDenied'});
  return async request => {
    if (await authorize(request) !== true) throw denied();
    request.signal?.throwIfAborted();
    const prepared = await prepare(request);
    prepare.assertOwned(prepared);
    if (prepare.kindOf(prepared) !== 'effect_free') {
      throw Object.assign(new Error('ClientOperationUnavailable'),
        {code: 'ClientOperationUnavailable'});
    }
    const kind = moon.clientProgramRequiresTaskCompilation(prepared) ? 'tasks' : 'values';
    const wire = control.readCheckedClientStaticPlan(prepared, kind, request);
    if (typeof wire !== 'string' || Buffer.byteLength(wire, 'utf8') > request.maxWireBytes) {
      throw new TypeError('InvalidClientHostPlanView');
    }
    const view = JSON.parse(wire);
    if (!validWirePlanViewShape(view)) throw new TypeError('InvalidClientHostPlanView');
    // No prepared handle or Plan authority crosses the read boundary. Current
    // access is checked again after asynchronous preparation.
    request.signal?.throwIfAborted();
    if (await authorize(request) !== true) throw denied();
    return view;
  };
}
