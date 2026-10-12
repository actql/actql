// Read the original compiler evidence of an admitted Run. Authorization is
// current; the stored map never creates an inspection or control permission.
import {validClientBody, snapshotClientRequest, validWireRunPlanViewShape} from
  '../../packages/client-wire/index.mjs';
const failure = code => Object.assign(new Error(code), {code});
export function installClientRunPlan({authorize, lookupOriginal, control}) {
  if (typeof authorize !== 'function' || typeof lookupOriginal !== 'function' ||
      typeof control?.readStoredRunPlanOriginal !== 'function') {
    throw new TypeError('InvalidClientRunPlanInstallation');
  }
  return async request => {
    const {signal, ...data} = request;
    const selected = Object.freeze({...snapshotClientRequest(data),
      ...(signal === undefined ? {} : {signal})});
    const {connection, ref, maxWireBytes, maxNodes, maxDepth} = selected;
    if (!validClientBody('run-plan', {connection, ref, maxWireBytes, maxNodes, maxDepth})) {
      throw new TypeError('InvalidRunPlanRequest');
    }
    if (await authorize(selected) !== true) throw failure('RunObservationAccessDenied');
    signal?.throwIfAborted();
    const original = lookupOriginal(ref);
    if (original === undefined) throw failure('RunObservationAccessDenied');
    const saved = original.runAdmissionEvidence?.logicalPlanOriginal;
    if (saved === undefined) throw failure('ClientOperationUnavailable');
    const wire = control.readStoredRunPlanOriginal(saved, original.runDefinition,
      original.programDefinitionCid, selected);
    if (wire !== saved.planViewWire) throw failure('InvalidClientHostRunPlanView');
    const view = {version: 'actql-run-plan-view/0.1', run_ref: {...ref},
      plan_view: JSON.parse(wire)};
    if (!validWireRunPlanViewShape(view) ||
        Buffer.byteLength(JSON.stringify(view)) > maxWireBytes) {
      throw failure('InvalidClientHostRunPlanView');
    }
    if (await authorize(selected) !== true) throw failure('RunObservationAccessDenied');
    signal?.throwIfAborted();
    // Recheck the exact original after the awaited current-authority callback.
    const current = lookupOriginal(ref)?.runAdmissionEvidence?.logicalPlanOriginal;
    if (current?.compiledPlanWire !== saved.compiledPlanWire ||
        current?.planViewWire !== saved.planViewWire) throw failure('InvalidClientHostRunPlanView');
    return view;
  };
}
