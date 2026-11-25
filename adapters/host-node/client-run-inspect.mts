// Reuse authorized current-only Owner observations and retained original Run
// evidence. No preparation, acquisition, dispatch or control mutation is used.
import {validRunRef, snapshotClientRequest, validWireRunViewShape} from '../../packages/client-wire/index.mjs';

import type {WireClientBodyByOperation, WireOwnerCursor, WireOwnerRef, WireRunRef, WireRunView} from
  '../../packages/client-wire/index.js';

type InspectRequest = WireClientBodyByOperation['inspect-run'] & Readonly<{
  principalId: string;
  signal?: AbortSignal;
}>;
type InspectOperation = Readonly<{principalId: string; indexKey: WireRunRef; purpose: 'inspect'}>;
type DebugPause = Readonly<{
  runRef: WireRunRef; revision: number; logicalMapCid?: string; pausedAt: number; expiresAt: number;
  ttlPolicy?: string; startRevision?: number; controlRevision?: number; committedGeneration?: number;
  completedStepId?: string; nextStepId?: string; resumeAvailable?: boolean;
}>;
type InspectReadWorkspace = Readonly<{
  begin(request: InspectRequest): unknown;
  metadata(request: InspectRequest, bytes: number): unknown;
  close(request: InspectRequest, error?: unknown): unknown;
}>;
type Observations<RunState> = Readonly<{
  owners: readonly Readonly<{
    kind: string;
    owner: string;
    snapshot?: Readonly<{value: RunState}>;
  }>[];
  revisionVector: readonly Readonly<{owner: WireOwnerRef; snapshotCid?: string}>[];
}>;
type InspectInstallation<Definition, Prepared, Authorization, RunState> = Readonly<{
  authorize(request: InspectRequest, operation: InspectOperation): boolean | PromiseLike<boolean>;
  authorizeCurrent(request: InspectRequest, operation: InspectOperation): boolean | PromiseLike<boolean> | undefined;
  authorizeResume?(request: InspectRequest): boolean;
  observeDebugPause?(request: InspectRequest, current: () => boolean, canResume?: () => boolean): DebugPause | undefined;
  readWorkspace?: InspectReadWorkspace;
  observeOwners(request: InspectRequest & Readonly<{cursors: readonly WireOwnerCursor[]; maxEntries: number}>):
    Observations<RunState> | PromiseLike<Observations<RunState>>;
  lookupOriginal(ref: WireRunRef): Readonly<{
    runDefinition: Definition;
    runAdmissionEvidence?: Readonly<{prepared?: string; authorization?: string}>;
  }> | undefined;
  control: Readonly<{
    admitRunEvidence(kind: 'prepared_invocation', wire: string, limits: InspectRequest): Prepared;
    admitRunEvidence(kind: 'run_authorization', wire: string, limits: InspectRequest): Authorization;
    readCurrentClientRunView(definition: Definition, prepared: Prepared, authorization: Authorization,
      ref: WireRunRef, state: RunState, snapshotCid: string, limits: InspectRequest, debugParkWire?: string): string;
  }>;
}>;

const sameDebugPause = (observed: DebugPause, current: DebugPause | undefined) =>
  current !== undefined && (Object.keys(observed) as (keyof DebugPause)[]).every(key => observed[key] === current[key]);

export function installClientRunInspect<Definition, Prepared, Authorization, RunState>(
  {authorize, authorizeCurrent, observeOwners, lookupOriginal, control, observeDebugPause, authorizeResume, readWorkspace}:
    InspectInstallation<Definition, Prepared, Authorization, RunState>) {
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
  return async <Result,>(request: InspectRequest, consume: (view: WireRunView) => Result) => {
    if (typeof consume !== 'function') throw new TypeError('InvalidClientRunInspectConsumer');
    const {signal, ...data} = request;
    const selected = Object.freeze({...snapshotClientRequest(data) as typeof data, ...(signal === undefined ? {} : {signal})});
    if (!validRunRef(selected.ref) || !Number.isSafeInteger(selected.maxWireBytes) ||
        selected.maxWireBytes < 1024 || selected.maxWireBytes > 65536 ||
        !Number.isSafeInteger(selected.maxNodes) || selected.maxNodes < 1 || selected.maxNodes > 10000 ||
        !Number.isSafeInteger(selected.maxDepth) || selected.maxDepth < 1 || selected.maxDepth > 64) {
      throw new TypeError('InvalidClientRunInspectRequest');
    }
    signal?.throwIfAborted();
    const operation = Object.freeze({principalId: selected.principalId, indexKey: selected.ref, purpose: 'inspect' as const});
    const requireCurrent = () => {
      signal?.throwIfAborted();
      const allowed = authorizeCurrent(selected, operation);
      if (allowed !== true) {
        if (typeof allowed === 'object' && typeof allowed?.then === 'function') void Promise.resolve(allowed).catch(() => {});
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
    const project = (debugParkWire: string) => {
      const wire = control.readCurrentClientRunView(original.runDefinition, prepared, authorization,
        selected.ref, state, vector.snapshotCid!, selected, debugParkWire);
      if (typeof wire !== 'string' || Buffer.byteLength(wire, 'utf8') > selected.maxWireBytes) {
        throw new TypeError('InvalidClientHostRunView');
      }
      const view = JSON.parse(wire);
      if (!validWireRunViewShape(view) ||
          (Object.keys(selected.ref) as (keyof WireRunRef)[]).some(key => view.run_ref[key] !== selected.ref[key])) {
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
    readWorkspace!.begin(request);
    try {
      // Bound the two nested RunRefs and shown run ID using their actual
      // string lengths. Six bytes per UTF-16 unit covers JSON escapes.
      // Fixed space includes scalar framing, CIDs, timestamps and delivery.
      const {run_id: runId} = state as {run_id?: unknown};
      const names = selected.ref.namespaceId.length + (typeof runId === 'string' ? runId.length : 0);
      readWorkspace!.metadata(request, 2 * (2112 + 6 * names));
      requireCurrent();
      const canResume = authorizeResume === undefined ? undefined : () => authorizeResume(selected) === true;
      const capability = canResume === undefined ? pause : observeDebugPause!(selected, current, canResume);
      if (capability === undefined || !sameDebugPause(pause, capability)) throw unavailable();
      const step = capability.controlRevision !== undefined;
      const debugParkWire = JSON.stringify({kind: step ? 'logical_step' : 'entry',
        run_ref: capability.runRef, revision: capability.revision, logical_map_cid: capability.logicalMapCid,
        paused_at: new Date(capability.pausedAt).toISOString(), expires_at: new Date(capability.expiresAt).toISOString(),
        ttl_policy: capability.ttlPolicy,
        ...(capability.resumeAvailable === undefined ? {} : {resume_available: capability.resumeAvailable}),
        ...(step ? {start_revision: capability.startRevision, control_revision: capability.controlRevision,
          committed_generation: capability.committedGeneration, completed_step_id: capability.completedStepId,
          next_step_id: capability.nextStepId ?? null} : {})});
      const view = project(debugParkWire);
      const live = observeDebugPause!(selected, current, canResume);
      if (!sameDebugPause(capability, live)) throw unavailable();
      requireCurrent();
      return await consume(view);
    } catch (error) {primary = error; throw error;}
    finally {readWorkspace!.close(request, primary);}
  };
}
