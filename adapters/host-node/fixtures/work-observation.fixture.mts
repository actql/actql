// Consumer diagnostics only. No event or retained count grants execution,
// currentness, access or cleanup authority; missing delivery stays incomplete.
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import type {createHostObservationConnection, HostObservationConnection} from '@actql/local-node/observation';
import type {DynamicRow, Execution, RunReference} from '../../../packages/sdk/index.d.ts';

type ObservationStatus = ReturnType<HostObservationConnection['status']>;
type CreateObservation = typeof createHostObservationConnection;
type Counts = {sourceAcquisitionStarts: number; modelCallStarts: number; effectReplacementReturns: number};
type Failure = Readonly<{available: true; code: string; kind: string; phase: string}>;
type AttributedFailure = Failure & {occurrence: Readonly<{task: number; unit: number; step: number}>};
type RunCounts = Counts & {primaryFailure?: AttributedFailure; effectPreflightFailure?: Failure};
type RecordWork = Counts & {complete: boolean; totals: Counts};
type RecordVariant = 'whole-input' | 'binary-source' | 'three-source';
type ResultReader = Pick<Execution, 'result'>;
// The authored row oracles assert the exact values and resource shape below.
type OrderedRow = DynamicRow & {id: string};
type JoinedRow = OrderedRow & {resource: Readonly<Record<string, string>>};
type ReviewRow = OrderedRow & {confirmation?: unknown};

export function workflowObservationComplete(status: ObservationStatus | null) {
  // Suppressed repeats of the same charged Owner fact are not lost delivery.
  return status !== undefined && status !== null && status.closed === true && status.cleanupPending === false &&
    Number.isSafeInteger(status.repeated) && status.repeated >= 0 &&
    ['dropped', 'budgetUnavailable', 'queueOverflow', 'deliveryFailed', 'limited',
      'queued', 'active', 'activeSegments'].every(name => status[name as keyof NonNullable<ObservationStatus>] === 0) &&
    status.loss !== undefined && status.loss !== null && Object.values(status.loss).every(value => value === 0);
}

// Authored no-Model fixture expectations, established by their checked Source
// occurrences and the one-start-per-selected-Source dispatch boundary. Counts
// from a previous execution never supply these expectations.
export function assertRecordWorkflowWork(work: RecordWork, {phase, variant}: {
  phase?: 'capture' | 'approve' | 'recover'; variant?: RecordVariant;
} = {}) {
  assert(['capture', 'approve', 'recover'].includes(phase!));
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

export function workflowWorkObservation({trackOriginal = false, createObservation}: {
  trackOriginal?: boolean; createObservation?: CreateObservation;
} = {}) {
  // DATA-only oracles also run before runtime staging. Only an actual observer
  // resolves the same installed observation namespace used by the public Host.
  const makeConnection: CreateObservation = createObservation ??
    createRequire(import.meta.url)('@actql/local-node/observation').createHostObservationConnection;
  const empty = () => ({sourceAcquisitionStarts: 0, modelCallStarts: 0, effectReplacementReturns: 0});
  const counts = empty(), unbound = empty(), runs = new Map<string, RunCounts>();
  let limited = false, primaryFailure: AttributedFailure | undefined, effectPreflightFailure: Failure | undefined;
  const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/u.test(value);
  const connection = makeConnection({
    include: ['source', 'infer', 'effect'],
    correlation: {include: trackOriginal ? ['run', 'task'] : ['task']},
    // This collector consumes starts, returned writes and typed failure DATA.
    // It does not request selected-row measurements from asynchronous dispatch.
    measurements: {include: []},
    events: {level: 'diagnostic'},
    deliver(record) {
      if (record.operation === 'effect' && record.event === 'dispatch_failed') {
        const a = record.attributes;
        if (a?.['error.type'] !== 'EffectTargetVersionMismatch' ||
            a['actql.failure.kind'] !== 'target_version_mismatch' ||
            a['actql.failure.phase'] !== 'effect_apply_preflight') return;
        const failure = Object.freeze({available: true, code: a['error.type'],
          kind: a['actql.failure.kind'], phase: a['actql.failure.phase']});
        effectPreflightFailure ??= failure;
        if (trackOriginal) {
          const key = a['actql.run.definition_cid'];
          if (!cid(key)) return;
          if (!runs.has(key)) {
            if (runs.size === 8) {limited = true;return;}
            runs.set(key, empty());
          }
          runs.get(key)!.effectPreflightFailure ??= failure;
        }
        return;
      }
      if (record.operation === 'infer' && record.event === 'dispatch_failed') {
        const a = record.attributes;
        if (typeof a?.['error.type'] !== 'string' ||
            typeof a?.['actql.failure.kind'] !== 'string' ||
            typeof a?.['actql.failure.phase'] !== 'string' ||
            !['actql.task.ordinal', 'actql.unit.ordinal', 'actql.step.ordinal']
              .every(key => Number.isSafeInteger(a[key]) && (a[key] as number) >= 0)) return;
        const failure = Object.freeze({available: true, code: a['error.type'],
          kind: a['actql.failure.kind'], phase: a['actql.failure.phase'],
          occurrence: Object.freeze({task: a['actql.task.ordinal'] as number,
            unit: a['actql.unit.ordinal'] as number, step: a['actql.step.ordinal'] as number})});
        primaryFailure ??= failure;
        if (trackOriginal) {
          const key = a['actql.run.definition_cid'];
          if (!cid(key)) return;
          if (!runs.has(key)) {
            if (runs.size === 8) {limited = true;return;}
            runs.set(key, empty());
          }
          runs.get(key)!.primaryFailure ??= failure;
        }
        return;
      }
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
      runs.get(key)![field]++;
    },
  });
  function snapshot() {
    let status;
    try {status = connection.status();} catch {return {...counts, complete: false, unavailable: true};}
    return {...counts, primaryFailure: primaryFailure ?? {available: false},
      ...(effectPreflightFailure === undefined ? {} : {effectPreflightFailure}),
      scope: 'Actual starts and returned Mock replacements; not durability ACK', status,
      complete: workflowObservationComplete(status)};
  }
  return {connection, snapshot,
    forOriginal(ref: Pick<RunReference, 'runDefinitionCid'>) {
      const total = snapshot(), bound = trackOriginal && cid(ref?.runDefinitionCid);
      return {...total, totals: {...counts}, ...(bound ? runs.get(ref.runDefinitionCid) ?? empty() : empty()),
        primaryFailure: bound ? runs.get(ref.runDefinitionCid)?.primaryFailure ?? {available: false}
          : {available: false},
        effectPreflightFailure: bound ? runs.get(ref.runDefinitionCid)?.effectPreflightFailure : undefined,
        scope: 'Same installed Host and original Run definition; other fresh verification Runs reported in totals',
        unbound: {...unbound}, complete: total.complete && bound && !limited && Object.values(unbound).every(value => value === 0)};
    }};
}

export async function readWholeResults(execution: ResultReader, updates: readonly ReviewRow[]) {
  const sourceRows = await execution.result('answer').all();
  assert.deepEqual([...sourceRows].sort((left, right) => (left.id as string).localeCompare(right.id as string)), [
    {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
    {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
  ]);
  const reviewed = await execution.result('main').all();
  const ordered = (rows: readonly DynamicRow[]) => [...rows].sort((left, right) => (left.id as string).localeCompare(right.id as string));
  assert.deepEqual(ordered(reviewed), ordered(updates.map(({confirmation, ...row}) => row)));
  return {answer: sourceRows, main: reviewed};
}

export function checkJoinedSourceRows(rows: readonly DynamicRow[]) {
  const expected = [
    {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null,
      version: 'sha256:3fdf0d901072bf1f3660dc0dfdbf5f6161cec18c459fdac7fed8b4c47d0fdd4e'},
    {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review',
      version: 'sha256:ee260c4ffcd3129c8950438225a62d46fa6078f63464ba4aed6f0d034f7ebdb2'},
  ];
  const fileIds = ['file-acme-notes', 'file-globex-notes'];
  const ordered = [...rows as readonly JoinedRow[]].sort((left, right) => (left.id as string).localeCompare(right.id as string));
  assert.equal(ordered.length, expected.length);
  const identities = new Set();
  for (const [index, row] of ordered.entries()) {
    assert.deepEqual(Object.keys(row).sort(), ['id', 'name', 'StageName', 'NextStep', 'resource', 'version'].sort());
    const {resource, ...values} = row;
    assert.deepEqual(values, expected[index]);
    assert.deepEqual(Object.keys(resource).sort(), ['$actql_ref', 'version', 'provider_namespace',
      'resource_kind', 'provider_identity_cid', 'authority_scope_cid', 'boundary_cid', 'identity_cid'].sort());
    assert.equal(resource.$actql_ref, 'resource');
    assert.equal(resource.version, 'actql-resource-ref/0.1');
    assert.equal(resource.provider_namespace, 'drive');
    assert.equal(resource.resource_kind, 'file');
    for (const field of ['provider_identity_cid', 'authority_scope_cid', 'boundary_cid', 'identity_cid']) {
      assert.match(resource[field], /^sha256:[0-9a-f]{64}$/u);
    }
    assert.equal(resource.provider_identity_cid, resource.boundary_cid);
    const identityWire = JSON.stringify({collection: 'files', identity: fileIds[index], scope: resource.boundary_cid});
    assert.equal(resource.identity_cid, 'sha256:' + createHash('sha256').update(identityWire).digest('hex'));
    identities.add(resource.identity_cid);
  }
  assert.equal(identities.size, 2);
}
export async function readJoinedWholeResults(execution: ResultReader, updates: readonly ReviewRow[]) {
  const answer = await execution.result('answer').all();
  checkJoinedSourceRows(answer);
  const main = await execution.result('main').all();
  const ordered = (rows: readonly DynamicRow[]) => [...rows].sort((left, right) => (left.id as string).localeCompare(right.id as string));
  assert.deepEqual(ordered(main), ordered(updates.map(({confirmation, ...row}) => row)));
  return {answer, main};
}
