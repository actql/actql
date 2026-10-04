import test from 'node:test';
import assert from 'node:assert/strict';
import {encode} from '../bounded-session/action-inputs.mjs';
import {policyPaths} from '../../scripts/ci-main-base.mjs';
import {readCatalog, catalogPath} from './actions.mjs';
import {actionInputs, sharedFiles, hash} from './inputs.mjs';
import {sealReceipt, canonicalReceipt} from './receipts.mjs';
import {comparisonPlan, selectOriginArtifact, compareFreshObservations, verifyComparison} from './plan.mjs';
import {ArtifactUnavailable} from './transport.mjs';

const base = 'a'.repeat(40), current = 'b'.repeat(40);
const catalog = readCatalog(); catalog.actions = catalog.actions.filter(action => ['model', 'session-js'].includes(action.id));
const context = {candidateRevision: current, repository: 'actql/actql', repositoryId: 1, workflowId: 2,
  runId: 30, runAttempt: 1, runHeadRevision: 'c'.repeat(40), headRepositoryId: 1, ancestors: []};
// This hypothetical closed input exercises the decision model only. Production
// runtime observations keep their residuals and cannot adopt this test seam.
const runtime = {profile: 'controlled-unit-test-runtime', unresolved: []};
const files = new Map([...sharedFiles.map(path => [path, path]), [catalogPath, encode(catalog)],
  ['src/bounded_execution/moon.pkg', ''], ['src/bounded_execution/session.mbt', 'production'],
  ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs'].map(path => [`proofs/bounded-session/${path}`, path])]);
const tree = (source = files) => ({entries: new Map([...source].map(([path]) => [path, {mode: '100644', kind: 'blob'}])),
  read: path => Buffer.from(source.get(path))});
const baseline = {baseSha: base, testedSha: current, runId: 3, runAttempt: 1, workflowId: 2,
  policy: policyPaths.map(path => ({path, object: 'd'.repeat(40)})), reason: 'Cumulative changes since fully verified main ancestor'};
const artifact = {id: 6, name: `session-actions-3-1-${base}`, expired: false, expires_at: '2099-01-01T00:00:00Z',
  size_in_bytes: 100, digest: `sha256:${'e'.repeat(64)}`,
  workflow_run: {id: 3, head_sha: base, repository_id: 1, head_repository_id: 1}};
const mainRun = {id: 3, run_attempt: 1, head_sha: base, workflow_id: 2, path: '.github/workflows/ci.yml',
  repository: {id: 1}, head_repository: {id: 1}, event: 'push', head_branch: 'main', status: 'completed', conclusion: 'success'};
function receipt(action, revision = base, executionRuntime = runtime, source = files) {
  const inputs = actionInputs({tree: tree(source), revision, action, runtime: executionRuntime});
  return sealReceipt({origin: {repository: 'actql/actql', repositoryId: 1, workflowId: 2,
    workflowPath: '.github/workflows/ci.yml', runId: revision === base ? 3 : 30, runAttempt: 1, jobId: 4,
    testedRevision: revision, runHeadRevision: revision, branch: 'main', event: 'push'},
  action, inputs, status: 0, milliseconds: 10,
  output: action.id === 'model' ? 'Checked 14 theorems, expected claim types and axiom dependencies\n' : 'Total tests: 7, passed: 7, failed: 0.\n'});
}
function fixture() {
  const state = {source: new Map(files), artifact: structuredClone(artifact), runtime, checkpoint: baseline,
    originRuntime: runtime, readCount: 0, downloadCount: 0, transform: value => value};
  const options = {context, runtime: state.runtime, root: '/unit-fixture', directory: '/unit-fixture', token: 'fixture-only',
    treeAt: revision => tree(revision === base ? files : state.source),
    resolveBaseline: async request => {
      assert.equal(request.testedSha, current);
      assert(request.requiredJobs.includes('check') && request.requiredJobs.includes('core (native)'));
      return state.checkpoint;
    },
    request: async path => {
      if (path === '/actions/runs/3') return structuredClone(mainRun);
      if (path === '/actions/artifacts/6') return structuredClone(state.artifact);
      assert.equal(path, '/actions/runs/3/artifacts?per_page=100');
      return {total_count: 1, artifacts: [state.artifact]};
    }, download: async () => { state.downloadCount++; return '/unit-fixture/origin.zip'; },
    loadRuntime: async () => ({runtime: state.originRuntime, actionRuntimes: {}}),
    read: async ({action, expected, acquisition}) => {
      assert.equal(acquisition, 'reused'); assert.deepEqual(expected.ancestors, [base]);
      state.readCount++;
      const value = state.transform(receipt(action, base, state.originRuntime));
      return {receipt: value, receiptDigest: hash(canonicalReceipt(value)), artifactId: 6, archiveDigest: 'e'.repeat(64)};
    }};
  return {state, options};
}

test('authenticated closed comparison preserves origins, downloads once, and still executes every action', async () => {
  const {state, options} = fixture(), originalBytes = canonicalReceipt(receipt(catalog.actions[1]));
  const plan = await comparisonPlan(options);
  assert.equal(plan.reuseAuthorized, false); assert.equal(state.downloadCount, 1); assert.equal(state.readCount, 2);
  assert(plan.actions.every(entry => entry.status === 'closed-inputs-match' && entry.acquisition === 'execute'));
  assert(canonicalReceipt(receipt(catalog.actions[1])).equals(originalBytes));
  const fresh = catalog.actions.map(action => receipt(action, current));
  const observations = compareFreshObservations({plan, context, runtime, tree: tree(), receipts: fresh});
  assert(observations.every(entry => entry.status === 'counts-match'));
  await verifyComparison({plan, ...options});
});

test('equal open runtime observations never become a reuse authorization after counts match', async () => {
  const {state, options} = fixture(), open = {...runtime, unresolved: ['unreviewed loader']};
  state.originRuntime = open; options.runtime = open;
  const plan = await comparisonPlan(options);
  assert(plan.actions.every(entry => entry.status === 'same-inputs-open' && entry.equal && !entry.closed));
  const fresh = catalog.actions.map(action => receipt(action, current, open));
  assert(compareFreshObservations({plan, context, runtime: open, tree: tree(), receipts: fresh}).every(entry => entry.status === 'counts-match'));
  assert.equal(plan.reuseAuthorized, false);
});

for (const [name, change] of [
  ['source', source => source.set('src/bounded_execution/session.mbt', 'different body')],
  ['new fixture', source => source.set('src/bounded_execution/new_wbtest.mbt', 'different oracle')],
  ['deleted fixture', source => source.delete('src/bounded_execution/session.mbt')],
  ['renamed fixture', source => { source.delete('src/bounded_execution/session.mbt'); source.set('src/bounded_execution/renamed.mbt', 'production'); }],
]) test(`relevant ${name} affects Session while independent model retains its own comparison`, async () => {
  const {state, options} = fixture(); change(state.source);
  const plan = await comparisonPlan(options);
  assert.equal(plan.actions[0].status, 'closed-inputs-match');
  assert.equal(plan.actions[1].status, 'candidate-inputs-changed');
  assert(plan.actions.every(entry => entry.acquisition === 'execute'));
});

test('policy changes and a main origin without the registry do not download/adopt old artifacts', async () => {
  const a = fixture(); a.state.source.set('proofs/ci-evidence/Reuse.lean', 'weakened policy');
  assert((await comparisonPlan(a.options)).actions.every(entry => entry.status === 'policy-changed'));
  assert.equal(a.state.downloadCount, 0);
  const b = fixture(); const missing = new Map(files); missing.delete(catalogPath);
  b.options.treeAt = revision => tree(revision === base ? missing : files);
  assert((await comparisonPlan(b.options)).actions.every(entry => entry.status === 'origin-catalog-missing'));
  assert.equal(b.state.downloadCount, 0);
});

test('new registration executes without widening the original independently reviewed descriptor', async () => {
  const {state, options} = fixture();
  const added = {...catalog.actions[1], id: 'session-more', profile: 'separate reviewed domain'};
  state.source.set(catalogPath, encode({...catalog, actions: [...catalog.actions, added]}));
  const plan = await comparisonPlan(options);
  assert.equal(plan.actions[2].status, 'registration-changed'); assert.equal(state.readCount, 2);
});

test('removed protected obligation rejects the plan before artifact transfer', async () => {
  const {state, options} = fixture(); state.source.set(catalogPath, encode({...catalog, actions: [catalog.actions[0]]}));
  await assert.rejects(comparisonPlan(options), /Removed required action/u); assert.equal(state.downloadCount, 0);
});

test('whole wrong-target origin, carried input tampering and wrong attempt remain rejected', async () => {
  for (const mutate of [
    value => receipt({...value.action, profile: 'UNCHECKED rows with arbitrary field types'}),
    value => ({...value, origin: {...value.origin, runAttempt: 2}}),
    value => ({...value, inputs: actionInputs({tree: tree(), revision: base, action: value.action,
      runtime: {...runtime, target: 'native'}})}),
  ]) {
    const {state, options} = fixture(); state.transform = mutate;
    assert((await comparisonPlan(options)).actions.every(entry => entry.status === 'origin-rejected' && !entry.closed));
  }
});

test('artifact selection binds main SHA, repository, exact attempt, expiry and complete inventory', () => {
  assert.equal(selectOriginArtifact({total_count: 1, artifacts: [artifact]}, baseline, context).id, 6);
  for (const change of [
    value => value.name = `session-actions-3-2-${base}`,
    value => value.expired = true,
    value => value.expires_at = '2000-01-01T00:00:00Z',
    value => value.workflow_run.head_sha = current,
    value => value.workflow_run.head_repository_id = 99,
    value => value.digest = 'untrusted',
  ]) {
    const changed = structuredClone(artifact); change(changed);
    assert.throws(() => selectOriginArtifact({total_count: 1, artifacts: [changed]}, baseline, context));
  }
  assert.throws(() => selectOriginArtifact({total_count: 2, artifacts: [artifact]}, baseline, context));
  assert.throws(() => selectOriginArtifact({total_count: 2, artifacts: [artifact, artifact]}, baseline, context));
});

test('missing/expired/unavailable transfer schedules fresh execution without a successful origin', async () => {
  for (const change of [state => state.artifact.expired = true]) {
    const {state, options} = fixture(); change(state);
    const plan = await comparisonPlan(options);
    assert.equal(plan.artifact, null); assert(plan.actions.every(entry => entry.status === 'origin-archive-unavailable' && entry.origin === null));
  }
  const {options} = fixture(); options.download = async () => { throw new ArtifactUnavailable(); };
  const plan = await comparisonPlan(options);
  assert(!encode(plan).includes('private-token')); assert(plan.actions.every(entry => entry.acquisition === 'execute'));
});

test('start succeeds, all fresh actions pass, final origin transfer is unavailable without comparison success', async () => {
  const {options} = fixture(), plan = await comparisonPlan(options), original = encode(plan);
  const fresh = catalog.actions.map(action => receipt(action, current));
  assert(compareFreshObservations({plan, context, runtime, tree: tree(), receipts: fresh}).every(entry => entry.status === 'counts-match'));
  options.download = async () => { throw new ArtifactUnavailable(); };
  const result = await verifyComparison({plan, ...options});
  assert.equal(result.status, 'unconfirmed'); assert.equal(result.reason, 'origin-unavailable');
  assert.equal(result.reuseAuthorized, false); assert.equal(encode(plan), original);
});

for (const index of [0, 1]) for (const failure of ['503', 'timeout']) {
  test(`archive succeeds but receipt ${index + 1} authentication ${failure} preserves all fresh obligations`, async () => {
    const {state, options} = fixture(), read = options.read;
    options.read = async args => {
      if (args.action.id === catalog.actions[index].id) {
        if (failure === '503') assert.fail('Actions history unavailable (HTTP 503)');
        throw new DOMException('timeout', 'TimeoutError');
      }
      return read(args);
    };
    const plan = await comparisonPlan(options), original = encode(plan);
    assert.equal(state.downloadCount, 1); assert.deepEqual(plan.artifact, {id: 6, digest: artifact.digest, bytes: 100});
    assert(plan.actions.every(entry => entry.acquisition === 'execute'));
    const unavailable = plan.actions[index];
    assert.equal(unavailable.status, 'origin-receipt-unavailable');
    assert.equal(unavailable.origin, null); assert.equal(unavailable.equal, false); assert.equal(unavailable.closed, false);
    assert.equal(plan.actions[1 - index].status, 'closed-inputs-match');
    const fresh = catalog.actions.map(action => receipt(action, current));
    const observations = compareFreshObservations({plan, context, runtime, tree: tree(), receipts: fresh});
    assert.equal(observations.length, catalog.actions.length);
    assert.equal(observations[index].status, 'not-comparable');
    assert.equal(observations[1 - index].status, 'counts-match');
    for (const recovered of [false, true]) {
      if (recovered) options.read = read;
      const result = await verifyComparison({plan, ...options});
      assert.equal(result.status, 'unconfirmed'); assert.equal(result.reason, 'origin-receipt-unavailable');
      assert.equal(result.reuseAuthorized, false); assert.equal(encode(plan), original);
    }
    const forged = structuredClone(plan); forged.actions[index].equal = true;
    await assert.rejects(verifyComparison({plan: forged, ...options}), /Unavailable receipt/u);
    state.transform = value => ({...value, origin: {...value.origin, runAttempt: 2}});
    await assert.rejects(verifyComparison({plan, ...options}), /Rejected origin|Changed\/invalid/u);
  });
}

test('initial receipt digest, run, attempt and input inconsistencies are rejected rather than unavailable', async () => {
  for (const mutate of [
    value => ({...value, archiveDigest: 'f'.repeat(64)}),
    value => ({...value, receipt: {...value.receipt, origin: {...value.receipt.origin, runId: 99}}}),
    value => ({...value, receipt: {...value.receipt, origin: {...value.receipt.origin, runAttempt: 2}}}),
    value => ({...value, receipt: {...value.receipt, inputs: {...value.receipt.inputs, key: 'f'.repeat(64)}}}),
  ]) {
    const {options} = fixture(), read = options.read;
    options.read = async args => mutate(await read(args));
    const plan = await comparisonPlan(options);
    assert(plan.actions.every(entry => entry.status === 'origin-rejected' && entry.origin === null && !entry.equal && !entry.closed));
  }
});

test('the production group path authenticates once and treats a mid-group outage as wholly unconfirmed', async () => {
  const f = fixture(), individual = f.options.read; let groups = 0;
  f.options.read = null;
  f.options.readGroup = async ({actions, ...options}) => {
    groups++;
    return new Map(await Promise.all(actions.map(async action => [action.id, await individual({...options, action})])));
  };
  const plan = await comparisonPlan(f.options);
  assert.equal(groups, 1); assert(plan.actions.every(entry => entry.equal && entry.closed));
  f.options.readGroup = async ({actions, ...options}) => {
    await individual({...options, action: actions[0]});
    throw new DOMException('timeout', 'TimeoutError');
  };
  const partial = await comparisonPlan(f.options);
  assert(partial.actions.every(entry => entry.status === 'origin-receipt-unavailable' && entry.origin === null && !entry.equal && !entry.closed));
  assert.equal((await verifyComparison({plan: partial, ...f.options})).status, 'unconfirmed');
});

test('late receipt authentication unavailability does not invalidate complete fresh observations', async () => {
  const {options} = fixture(), plan = await comparisonPlan(options), original = encode(plan);
  const fresh = catalog.actions.map(action => receipt(action, current));
  assert(compareFreshObservations({plan, context, runtime, tree: tree(), receipts: fresh}).every(entry => entry.status === 'counts-match'));
  const read = options.read;
  options.read = async args => {
    if (args.action.id === catalog.actions[1].id) throw new ArtifactUnavailable();
    return read(args);
  };
  assert.equal((await verifyComparison({plan, ...options})).status, 'unconfirmed');
  assert.equal(encode(plan), original);
});

test('final API timeout is unconfirmed while digest, run, attempt and repository mismatches reject', async () => {
  const missing = fixture(), plan = await comparisonPlan(missing.options);
  missing.options.request = async () => { throw new DOMException('timeout', 'TimeoutError'); };
  assert.equal((await verifyComparison({plan, ...missing.options})).status, 'unconfirmed');
  for (const patch of [{id: 99}, {run_attempt: 2}, {head_sha: current}, {repository: {id: 9}}, {head_repository: {id: 9}}]) {
    const {options} = fixture(), initial = await comparisonPlan(options), request = options.request;
    options.request = async path => path === '/actions/runs/3' ? {...mainRun, ...patch} : request(path);
    await assert.rejects(verifyComparison({plan: initial, ...options}));
  }
  const {options} = fixture(), initial = await comparisonPlan(options);
  options.loadRuntime = async () => { throw new Error('Invalid artifact ZIP: digest mismatch'); };
  await assert.rejects(verifyComparison({plan: initial, ...options}), /digest mismatch/u);
  const substituted = fixture(), started = await comparisonPlan(substituted.options);
  substituted.state.artifact.expired = true; substituted.state.artifact.digest = `sha256:${'f'.repeat(64)}`;
  await assert.rejects(verifyComparison({plan: started, ...substituted.options}), /Changed original archive digest/u);
});

test('a history lookup timeout swallowed by the shared resolver remains an unconfirmed comparison', async () => {
  const {options} = fixture(), plan = await comparisonPlan(options), request = options.request;
  options.request = async path => {
    if (path.endsWith('/jobs')) throw new DOMException('timeout', 'TimeoutError');
    return request(path);
  };
  options.resolveBaseline = async ({request}) => {
    try { await request('/actions/runs/3/jobs'); return baseline; }
    catch { return {baseSha: null, reason: 'history lookup failed'}; }
  };
  assert.equal((await verifyComparison({plan, ...options})).status, 'unconfirmed');
});

test('wrong artifact attempt and corrupt completed archives are not transport misses', async () => {
  const {state, options} = fixture(); state.artifact.name = `session-actions-3-2-${base}`;
  await assert.rejects(comparisonPlan(options), /Missing\/ambiguous/u);
  const corrupt = fixture(); corrupt.options.loadRuntime = async () => { throw new Error('Invalid artifact ZIP: digest mismatch'); };
  await assert.rejects(comparisonPlan(corrupt.options), /digest mismatch/u);
});

test('cache/history absence remains a fresh result even if a checkpoint becomes available before final check', async () => {
  const {state, options} = fixture(); state.checkpoint = {baseSha: null, reason: 'No full checkpoint'};
  const plan = await comparisonPlan(options); state.checkpoint = baseline;
  await verifyComparison({plan, ...options}); assert.equal(state.downloadCount, 0);
  const forged = structuredClone(plan); forged.actions[0].closed = true;
  await assert.rejects(verifyComparison({plan: forged, ...options}), /No-origin/u);
});

test('final check rejects changed target/owner, origin identity, omission, carried keys and retroactive skip', async () => {
  const {options} = fixture(), plan = await comparisonPlan(options);
  for (const change of [
    value => value.actions.pop(), value => value.actions[0].origin.receiptDigest = 'f'.repeat(64),
    value => value.actions[1].candidateActionKey = 'f'.repeat(64),
    value => value.actions[0].acquisition = 'reuse', value => value.reuseAuthorized = true,
    value => value.context.runAttempt = 2,
  ]) {
    const changed = structuredClone(plan); change(changed);
    await assert.rejects(verifyComparison({plan: changed, ...options}));
  }
  const fresh = catalog.actions.map(action => receipt(action, current));
  assert.throws(() => compareFreshObservations({plan, context, runtime, tree: tree(), receipts: fresh.slice(0, 1)}), /Incomplete fresh/u);
  const changedCount = [...fresh]; changedCount[1] = {...fresh[1], execution: {...fresh[1].execution, units: 8}};
  assert.throws(() => compareFreshObservations({plan, context, runtime, tree: tree(), receipts: changedCount}), /disagreed/u);
});

test('final replay restricts checkpoint selection to the recorded live-API main run', async () => {
  const {options} = fixture(); const calls = [];
  options.request = async path => {
    calls.push(path);
    if (path === '/actions/runs/3') return {...mainRun, from: 'live-api'};
    if (path === '/actions/artifacts/6') return artifact;
    return {total_count: 1, artifacts: [artifact]};
  };
  options.resolveBaseline = async ({request}) => {
    const selected = await request('/actions/workflows/2/runs?branch=main');
    assert.deepEqual(selected.workflow_runs, [{...mainRun, from: 'live-api'}]); return baseline;
  };
  const plan = await comparisonPlan({...options, recordedRunId: 3});
  await verifyComparison({plan, ...options}); assert(calls.includes('/actions/runs/3'));
});
