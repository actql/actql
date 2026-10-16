import {validRunRef, validWireRunViewShape, validOwnerObservations,
  withinResultDescriptionLimits} from '@actql/client-wire';
import {ExplorerReadError} from './presentation-limits.mjs';

// These are one-page presentation limits, not execution/resource permissions.
export const runObservationLimits = Object.freeze({maxEntries: 32,
  maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64});
const refuse = () => {throw new ExplorerReadError('ExplorerInvalidRunObservation');};
const sameRef = (a, b) => ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
  .every(key => a[key] === b[key]);
const frozen = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) frozen(child);
    Object.freeze(value);
  }
  return value;
};
const unavailable = () => ({state: 'unavailable', reason: 'not_in_projection'});
const quantity = item => item.kind === 'unknown'
  ? {kind: item.kind, unit: item.unit, reason: item.reason}
  : {kind: item.kind, value: item.value, unit: item.unit,
    scopeCid: item.scope_cid, basisCid: item.basis_cid};

function historyModel(owners, ref) {
  if (owners !== null && !validOwnerObservations(owners, ref, runObservationLimits)) refuse();
  const histories = owners === null ? {state: 'unavailable', reason: 'capability_unavailable'} : {
    state: 'observed', consistency: owners.consistency, ordering: owners.ordering,
    // Preserve each Owner's returned order and its own revision vector. There
    // is no cross-Owner timestamp sort or synthetic complete-history claim.
    owners: owners.owners.map(item => {
      if (item.kind === 'unavailable') return {owner: item.owner, state: 'unavailable',
        reason: item.problem?.kind ?? 'not_provided'};
      const vector = owners.revisionVector.find(v => v.owner.kind === item.ownerRef.kind &&
        v.owner.scopeCid === item.ownerRef.scopeCid && v.owner.streamCid === item.ownerRef.streamCid);
      return {owner: item.owner, state: 'observed', ownerRef: {...item.ownerRef},
        snapshot: item.snapshot === undefined
          ? {state: 'unavailable', reason: item.snapshotProblem.kind}
          : {state: 'observed', cid: vector.snapshotCid,
            ...(item.snapshot.revision === undefined ? {} : {revision: item.snapshot.revision})},
        history: item.history.kind === 'page' ? {
          state: 'page', entries: item.history.entries.map(entry => ({...entry})),
          head: vector.historyHead === null ? null : {...vector.historyHead},
          cursorAvailable: item.history.cursor !== undefined,
        } : {state: 'unavailable', reason: item.history.kind},
      };
    }),
  };
  return histories;
}

// A presentation projection of two independent authorized observations. It
// neither seals a new identity nor joins Owner history to logical steps.
export function runObservationModel(view, owners, ref) {
  if (!validRunRef(ref) || !withinResultDescriptionLimits(view, runObservationLimits) ||
      !validWireRunViewShape(view) || !sameRef(view.run_ref, ref) ||
      owners !== null && !validOwnerObservations(owners, ref, runObservationLimits)) refuse();
  const state = view.run_state, legacy = state.legacy_state;
  const resultAvailability = legacy === undefined ? unavailable() : {
    state: 'observed', entries: Object.entries(legacy.result_availability).map(([name, item]) => ({
      name, state: item.state, reason: item.reason, observedAt: item.observed_at,
      ...(item.cause_cid === undefined ? {} : {causeCid: item.cause_cid}),
    })),
  };
  const histories = historyModel(owners, ref);
  return frozen({runRef: {...ref}, consistency: view.consistency,
    observationScope: view.observation_scope,
    run: {id: state.run_id, status: state.status, updatedAt: state.updated_at,
      controlRevision: state.control_revision,
      terminal: ['succeeded', 'failed', 'cancelled'].includes(state.status),
      ...(state.stop_reason === undefined ? {} : {stopReason: state.stop_reason}),
      ...(state.boundary === undefined ? {} : {boundary: {...state.boundary}}),
      ...(state.cleanup_pending === undefined ? {} : {cleanupPending: state.cleanup_pending}),
      ...(state.pause_pending === undefined ? {} : {pausePending: state.pause_pending}),
      ...(state.expiry_pending === undefined ? {} : {expiryPending: state.expiry_pending}),
      cancellation: legacy?.control === undefined ? unavailable() : {
        state: 'observed', requested: legacy.control.cancellation_requested,
        physicalStop: legacy.control.physical_stop,
      },
    },
    // Null means no binding was observed, not permission to fill it from a
    // separately read Plan or a newly compiled Program.
    planBinding: {compiledPlanCid: view.compiled_plan_cid, logicalMapCid: view.logical_map_cid},
    components: view.components.map(item => ({...item})),
    quantities: view.quantities.map(quantity), resultAvailability, histories,
    sample: {state: view.sample.state,
      ...('reason' in view.sample ? {reason: view.sample.reason} : {})},
    logicalProgress: unavailable(), elapsed: unavailable(), tokens: unavailable(),
    cost: unavailable(), preview: unavailable(),
  });
}

// Manual refresh and polling both retain this exact Run reference. No start,
// wait, cancellation, reconciliation, sample acquisition or payload read occurs.
export async function readRunObservation(client, ref, ticket) {
  if (!validRunRef(ref)) refuse();
  const original = Object.freeze({...ref});
  const current = async action => {
    ticket.assertCurrent();
    try {const answer = await action(); ticket.assertCurrent(); return answer;}
    catch (error) {ticket.assertCurrent(); throw error;}
  };
  const run = await current(() => client.attach(original));
  if (typeof run.inspect !== 'function') throw new ExplorerReadError('ExplorerCapabilityUnavailable');
  const model = await current(async () => runObservationModel(await run.inspect({
    maxWireBytes: runObservationLimits.maxWireBytes, maxNodes: runObservationLimits.maxNodes,
    maxDepth: runObservationLimits.maxDepth}), null, original));
  const owners = typeof run.observeOwners !== 'function' ? null : await current(() =>
    run.observeOwners({maxEntries: runObservationLimits.maxEntries, maxWireBytes: runObservationLimits.maxWireBytes}));
  ticket.assertCurrent();
  return frozen({...model, histories: historyModel(owners, original)});
}
