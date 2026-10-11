// Reuse authorized current-only Owner observations and retained original Run
// evidence. No preparation, acquisition, dispatch or control mutation is used.
import {validRunRef, snapshotClientRequest, validWireRunViewShape} from '../../packages/client-wire/index.mjs';

export function installClientRunInspect({authorize, observeOwners, lookupOriginal, control}) {
  if (typeof authorize !== 'function' || typeof observeOwners !== 'function' ||
      typeof lookupOriginal !== 'function' || typeof control?.readCurrentClientRunView !== 'function' ||
      typeof control?.admitRunEvidence !== 'function') {
    throw new TypeError('InvalidClientRunInspectInstallation');
  }
  const denied = () => Object.assign(new Error('RunObservationAccessDenied'),
    {code: 'RunObservationAccessDenied'});
  const unavailable = () => Object.assign(new Error('ClientOperationUnavailable'),
    {code: 'ClientOperationUnavailable'});
  return async request => {
    const {signal, ...data} = request;
    const selected = {...snapshotClientRequest(data), ...(signal === undefined ? {} : {signal})};
    if (!validRunRef(selected.ref) || !Number.isSafeInteger(selected.maxWireBytes) ||
        selected.maxWireBytes < 1024 || selected.maxWireBytes > 65536 ||
        !Number.isSafeInteger(selected.maxNodes) || selected.maxNodes < 1 || selected.maxNodes > 10000 ||
        !Number.isSafeInteger(selected.maxDepth) || selected.maxDepth < 1 || selected.maxDepth > 64) {
      throw new TypeError('InvalidClientRunInspectRequest');
    }
    if (await authorize(selected) !== true) throw denied();
    signal?.throwIfAborted();
    const original = lookupOriginal(selected.ref);
    if (original === undefined) throw denied();
    const evidence = original.runAdmissionEvidence;
    // Older records remain valid original Runs. Missing policy evidence does
    // not authorize reconstruction from today's configuration or compilation.
    if (evidence?.prepared === undefined || evidence.authorization === undefined) throw unavailable();
    const observations = await observeOwners({...selected, cursors: [], maxEntries: 1});
    const owner = observations.owners.find(value => value.kind === 'observed' && value.owner === 'run');
    const vector = observations.revisionVector.find(value => value.owner.kind === 'run' &&
      value.owner.scopeCid === selected.ref.authorityScopeCid &&
      value.owner.streamCid === selected.ref.runDefinitionCid);
    if (owner?.snapshot?.value === undefined || vector?.snapshotCid === undefined) throw unavailable();
    if (await authorize(selected) !== true) throw denied();
    signal?.throwIfAborted();
    const prepared = control.admitRunEvidence('prepared_invocation', evidence.prepared, selected);
    const authorization = control.admitRunEvidence('run_authorization', evidence.authorization, selected);
    const wire = control.readCurrentClientRunView(original.runDefinition, prepared, authorization,
      selected.ref, owner.snapshot.value, vector.snapshotCid, selected);
    if (typeof wire !== 'string' || Buffer.byteLength(wire, 'utf8') > selected.maxWireBytes) {
      throw new TypeError('InvalidClientHostRunView');
    }
    const view = JSON.parse(wire);
    if (!validWireRunViewShape(view)) throw new TypeError('InvalidClientHostRunView');
    if (await authorize(selected) !== true) throw denied();
    signal?.throwIfAborted();
    return view;
  };
}
