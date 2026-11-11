// Consumer diagnostics only. No event or retained count grants execution,
// currentness, access or cleanup authority; missing delivery stays incomplete.
import {createHostObservationConnection} from '@actql/local-node/observation';
import assert from 'node:assert/strict';

// Authored no-Model fixture expectations, established by their checked Source
// occurrences and the one-start-per-selected-Source dispatch boundary. Counts
// from a previous execution never supply these expectations.
export function assertRecordWorkflowWork(work, {phase, variant} = {}) {
  assert(['capture', 'approve', 'recover'].includes(phase));
  const sourceStarts = {'whole-input': 1, 'binary-source': 2, 'three-source': 3};
  if (variant !== undefined) assert(Object.hasOwn(sourceStarts, variant));
  assert.equal(work.complete, true, 'Unbound or lost starts cannot establish original-Run reuse');
  assert.equal(work.modelCallStarts, 0, 'These authored record fixtures declare no Models');
  assert.equal(work.totals.modelCallStarts, 0);
  if (phase === 'capture') {
    if (variant === undefined) assert(work.sourceAcquisitionStarts > 0);
    else assert.equal(work.sourceAcquisitionStarts, sourceStarts[variant],
      'One original acquisition start per authored checked Source occurrence');
  } else assert.equal(work.sourceAcquisitionStarts, 0, 'The completed original Source must not reacquire');
  assert.equal(work.effectReplacementReturns, phase === 'approve' ? 1 : 0);
  assert.equal(work.totals.effectReplacementReturns, work.effectReplacementReturns);
}

export function workflowWorkObservation({trackOriginal = false} = {}) {
  const empty = () => ({sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0});
  const counts = empty(), unbound = empty(), runs = new Map();
  let limited = false;
  const cid = value => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/u.test(value);
  const connection = createHostObservationConnection({
    include: ['source', 'infer', 'effect'], correlation: trackOriginal ? {include: ['run']} : false,
    events: {level: 'diagnostic'},
    deliver(record) {
      const field = record.operation === 'source' && record.event === 'attempt_started' ? 'sourceAcquisitionStarts'
        : record.operation === 'infer' && record.event === 'attempt_started' ? 'modelCallStarts'
          : record.operation === 'effect' && record.event === 'write_observed' ? 'effectReplacementReturns' : undefined;
      if (field === undefined) return;
      counts[field]++;
      if (!trackOriginal) return;
      const key = record.attributes?.['actql.run.definition_cid'];
      if (!cid(key)) {unbound[field]++;return;}
      if (!runs.has(key)) {
        if (runs.size === 8) {limited = true;return;}
        runs.set(key, empty());
      }
      runs.get(key)[field]++;
    },
  });
  function snapshot() {
    let status;
    try {status = connection.status();} catch {return {...counts, complete: false, unavailable: true};}
    return {...counts, scope: 'Actual starts and returned Mock replacements; not durability ACK', status,
      complete: status !== undefined && status.closed === true && status.cleanupPending === false &&
        ['dropped', 'budgetUnavailable', 'queueOverflow', 'deliveryFailed', 'limited', 'repeated',
          'queued', 'active', 'activeSegments'].every(name => status[name] === 0) &&
        status.loss !== undefined && Object.values(status.loss).every(value => value === 0)};
  }
  return {connection, snapshot,
    forOriginal(ref) {
      const total = snapshot(), bound = trackOriginal && cid(ref?.runDefinitionCid);
      return {...total, totals: {...counts}, ...(bound ? runs.get(ref.runDefinitionCid) ?? empty() : empty()),
        scope: 'Same installed Host and original Run definition; other fresh verification Runs reported in totals',
        unbound: {...unbound}, complete: total.complete && bound && !limited && Object.values(unbound).every(value => value === 0)};
    }};
}
