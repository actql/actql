// Reuse authorized current-only Owner observations and retained original Run
// evidence. No preparation, acquisition, dispatch or control mutation is used.
import {validRunRef, snapshotClientRequest, validWireRunViewShape} from '../../packages/client-wire/index.mjs';

export function installClientRunInspect({authorize, authorizeCurrent, observeOwners, lookupOriginal, control,
  observeDebugPause, readWorkspace}) {
  if (typeof authorize !== 'function' || typeof authorizeCurrent !== 'function' || typeof observeOwners !== 'function' ||
      typeof lookupOriginal !== 'function' || typeof control?.readCurrentClientRunView !== 'function' ||
      typeof control?.admitRunEvidence !== 'function' ||
      observeDebugPause !== undefined && [observeDebugPause, readWorkspace?.begin, readWorkspace?.metadata,
        readWorkspace?.close].some(method => typeof method !== 'function')) {
    throw new TypeError('InvalidClientRunInspectInstallation');
  }
  const denied = () => Object.assign(new Error('RunObservationAccessDenied'),
    {code: 'RunObservationAccessDenied'});
  const unavailable = () => Object.assign(new Error('ClientOperationUnavailable'),
    {code: 'ClientOperationUnavailable'});
  return async (request, consume) => {
    if (typeof consume !== 'function') throw new TypeError('InvalidClientRunInspectConsumer');
    const {signal, ...data} = request;
    const selected = Object.freeze({...snapshotClientRequest(data), ...(signal === undefined ? {} : {signal})});
    if (!validRunRef(selected.ref) || !Number.isSafeInteger(selected.maxWireBytes) ||
        selected.maxWireBytes < 1024 || selected.maxWireBytes > 65536 ||
        !Number.isSafeInteger(selected.maxNodes) || selected.maxNodes < 1 || selected.maxNodes > 10000 ||
        !Number.isSafeInteger(selected.maxDepth) || selected.maxDepth < 1 || selected.maxDepth > 64) {
      throw new TypeError('InvalidClientRunInspectRequest');
    }
    signal?.throwIfAborted();
    const operation = Object.freeze({principalId: selected.principalId, indexKey: selected.ref, purpose: 'inspect'});
    const requireCurrent = () => {
      signal?.throwIfAborted();
      const allowed = authorizeCurrent(selected, operation);
      if (allowed !== true) {
        if (typeof allowed?.then === 'function') void Promise.resolve(allowed).catch(() => {});
        throw denied();
      }
      signal?.throwIfAborted();
    };
    if (await authorize(selected, operation) !== true) throw denied();
    requireCurrent();
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
    requireCurrent();
    const prepared = control.admitRunEvidence('prepared_invocation', evidence.prepared, selected);
    const authorization = control.admitRunEvidence('run_authorization', evidence.authorization, selected);
    const state = owner.snapshot.value;
    const project = debugParkWire => {
      const wire = control.readCurrentClientRunView(original.runDefinition, prepared, authorization,
        selected.ref, state, vector.snapshotCid, selected, debugParkWire);
      if (typeof wire !== 'string' || Buffer.byteLength(wire, 'utf8') > selected.maxWireBytes) {
        throw new TypeError('InvalidClientHostRunView');
      }
      const view = JSON.parse(wire);
      if (!validWireRunViewShape(view) ||
          Object.keys(selected.ref).some(key => view.run_ref[key] !== selected.ref[key])) {
        throw new TypeError('InvalidClientHostRunView');
      }
      return view;
    };
    const current = () => {requireCurrent(); return true;};
    const pause = observeDebugPause?.(selected, current);
    if (pause === undefined || pause.logicalMapCid === undefined) {
      const view = project('');
      requireCurrent();
      return await consume(view);
    }
    let primary;
    readWorkspace.begin(request);
    try {
      // Bound the two nested RunRefs and shown run ID using their actual
      // string lengths. Six bytes per UTF-16 unit covers JSON escapes.
      // Fixed space includes scalar framing, CIDs, timestamps and delivery.
      const names = selected.ref.namespaceId.length + (typeof state.run_id === 'string' ? state.run_id.length : 0);
      readWorkspace.metadata(request, 2 * (2048 + 6 * names));
      requireCurrent();
      const step = pause.controlRevision !== undefined;
      const debugParkWire = JSON.stringify({kind: step ? 'logical_step' : 'entry',
        run_ref: pause.runRef, revision: pause.revision, logical_map_cid: pause.logicalMapCid,
        paused_at: new Date(pause.pausedAt).toISOString(), expires_at: new Date(pause.expiresAt).toISOString(),
        ttl_policy: pause.ttlPolicy,
        ...(step ? {start_revision: pause.startRevision, control_revision: pause.controlRevision,
          committed_generation: pause.committedGeneration, completed_step_id: pause.completedStepId,
          next_step_id: pause.nextStepId ?? null} : {})});
      const view = project(debugParkWire);
      const live = observeDebugPause(selected, current);
      if (live === undefined || Object.keys(pause).some(key => live[key] !== pause[key])) throw unavailable();
      requireCurrent();
      return await consume(view);
    } catch (error) {primary = error; throw error;}
    finally {readWorkspace.close(request, primary);}
  };
}
