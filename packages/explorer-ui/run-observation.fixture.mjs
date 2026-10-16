// Independent semantic presentation fixture, not a Host/Store acceptance.
export const observationCid = n => `sha256:${n.repeat(64)}`;
export const observationRef = () => ({namespaceId: 'original',
  authorityScopeCid: observationCid('a'), runDefinitionCid: observationCid('b')});
export function runObservationFixture() {
  return {version: 'actql-run-view/0.1', run_ref: observationRef(),
    run_state: {version: 'actql-controlled-run-state/0.1', run_id: 'original-run',
      status: 'running', updated_at: '2026-10-15T00:00:00.000Z', control_revision: 7},
    compiled_plan_cid: null, logical_map_cid: null, consistency: 'non_atomic',
    observation_scope: 'owner_local', components: [], quantities: [],
    sample: {state: 'unavailable', reason: 'not_supported'}, available_operations: ['inspect'],
    capabilities: {static_plan: true, inspect: true, durable_control: false,
      sample_capture: [], full_intermediate_retention: [], cost_guard: false,
      execution_batch: false, policy_revision_cid: observationCid('c')}};
}
export function ownerObservationFixture() {
  const owner = {kind: 'run', scopeCid: observationCid('a'), streamCid: observationCid('b')};
  return {ref: observationRef(), consistency: 'non_atomic', ordering: 'owner_local',
    owners: [{owner: 'run', kind: 'observed', ownerRef: {...owner},
      snapshot: {revision: 3, value: {version: 'actql-run-state/0.1', run_id: 'original-run',
        status: 'running', updated_at: '2026-10-15T00:00:00.000Z', next_action: {kind: 'none'},
        result_available: false, result_availability: {}}},
      history: {kind: 'page', entries: [
        {revision: 2, entryCid: observationCid('2'), state: 'dispatching'},
        {revision: 3, entryCid: observationCid('3'), state: 'unknown'}],
      cursor: {owner: {...owner}, value: 'original-opaque-cursor'}}},
      {owner: 'publication', kind: 'unavailable', problem: {kind: 'acquisition_failed'}}],
    revisionVector: [{owner, snapshotCid: observationCid('4'),
      historyHead: {generation: observationCid('1'), revision: 3, entryCid: observationCid('3')}}]};
}
