// Compare the current ordinary execution with an authenticated full-main
// origin. This module never authorizes skipping or rewrites original receipts.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {encode} from '../bounded-session/action-inputs.mjs';
import {gateJobs} from '../../scripts/ci-targets.mjs';
import {resolveMainBaseline, fullCheckpointJobs, validateMainBaseline} from '../../scripts/ci-main-base.mjs';
import {openArtifactZip} from '../../scripts/ci-artifact-reader.mjs';
import {catalogPath, validateCatalog, compareCatalogs} from './actions.mjs';
import {actionInputs, gitTree, compareInputs, hash} from './inputs.mjs';
import {policyUnchanged} from './applications.mjs';
import {readOriginReceipt} from './receipts.mjs';
import {downloadArtifact} from './transport.mjs';
import {checkRuntimeObservation} from './runtime.mjs';

export const comparisonVersion = 'actql-verification-action-comparison/0.1';
const positive = value => Number.isSafeInteger(value) && value > 0;
const sha = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const identity = value => hash(encode(value));
const exact = (value, fields) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort());
const unchanged = (a, b) => encode(a) === encode(b);

export function selectOriginArtifact(data, baseline, context) {
  assert(Array.isArray(data?.artifacts) && data.total_count === data.artifacts.length && data.artifacts.length <= 100,
    'Incomplete origin artifact inventory');
  const name = `session-actions-${baseline.runId}-${baseline.runAttempt}-${baseline.baseSha}`;
  const selected = data.artifacts.filter(artifact => artifact.name === name);
  assert.equal(selected.length, 1, 'Missing/ambiguous original Session archive');
  const artifact = selected[0];
  assert(positive(artifact.id) && positive(artifact.size_in_bytes) && artifact.size_in_bytes <= 64 * 1024 * 1024,
    'Invalid origin archive size/identity');
  assert.equal(artifact.expired, false);
  assert(Number.isFinite(Date.parse(artifact.expires_at)) && Date.parse(artifact.expires_at) > Date.now());
  assert(/^sha256:[a-f0-9]{64}$/u.test(artifact.digest ?? ''), 'Missing origin archive digest');
  assert.equal(artifact.workflow_run?.id, baseline.runId);
  assert.equal(artifact.workflow_run?.head_sha, baseline.baseSha);
  assert.equal(artifact.workflow_run?.repository_id, context.repositoryId);
  assert.equal(artifact.workflow_run?.head_repository_id, context.repositoryId);
  return artifact;
}

async function readRuntime({archive, artifact, baseline, context}) {
  const zip = await openArtifactZip(archive, {expectedSha256: artifact.digest,
    limits: {maxCompressedBytes: 64 * 1024 * 1024, maxTotalBytes: 256 * 1024 * 1024, maxEntries: 2000}});
  try {
    const state = await zip.json('context.json'), distributionInputs = await zip.json('runtime-distributions.json');
    assert.equal(state.context.repository, context.repository);
    assert.equal(state.context.repositoryId, context.repositoryId);
    assert.equal(state.context.headRepositoryId, context.repositoryId);
    assert.equal(state.context.candidateRevision, baseline.baseSha);
    assert.equal(state.context.runHeadRevision, baseline.baseSha);
    assert.equal(state.context.runId, baseline.runId);
    assert.equal(state.context.runAttempt, baseline.runAttempt);
    assert.equal(state.context.workflowId, context.workflowId);
    checkRuntimeObservation(state.runtime, distributionInputs);
    return state.runtime;
  } finally { await zip.close(); }
}

// All injection points are internal test seams. The CI caller supplies actual
// Git, the existing Actions client and transport; request JSON cannot override
// authentication, history, source extraction or runtime validation.
export async function comparisonPlan({root, context, runtime, directory, token, request,
  recordedRunId = null, treeAt = revision => gitTree(root, revision),
  git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024}),
  resolveBaseline = resolveMainBaseline, download = downloadArtifact, read = readOriginReceipt,
  loadRuntime = readRuntime}) {
  assert(sha(context.candidateRevision) && positive(context.repositoryId) && positive(context.workflowId));
  assert(recordedRunId === null || positive(recordedRunId));
  const start = performance.now(), tree = treeAt(context.candidateRevision);
  const catalog = validateCatalog(JSON.parse(tree.read(catalogPath)));
  const actions = catalog.actions.map(action => ({actionId: action.id, acquisition: 'execute',
    candidateActionKey: actionInputs({tree, revision: context.candidateRevision, action, runtime}).key,
    status: 'checkpoint-unavailable', origin: null, equal: false, closed: false, unresolved: []}));
  // At the final consumer validate the originally selected checkpoint again,
  // rather than changing the origin when another old run finishes meanwhile.
  // The restricted list still comes from the live API, not carried JSON.
  const checkpointRequest = recordedRunId === null ? request : async path => {
    if (/^\/actions\/workflows\/\d+\/runs\?/u.test(path)) {
      return {workflow_runs: [await request(`/actions/runs/${recordedRunId}`)]};
    }
    return request(path);
  };
  const baseline = await resolveBaseline({testedSha: context.candidateRevision, repository: context.repository,
    repositoryId: context.repositoryId, requiredJobs: fullCheckpointJobs(gateJobs), git, request: checkpointRequest});
  const checkpointMilliseconds = Math.round(performance.now() - start);
  const plan = {version: comparisonVersion, mode: 'comparison', reuseAuthorized: false, context,
    catalogDigest: identity(catalog), baseline, artifact: null, actions,
    costs: {checkpointMilliseconds, transferMilliseconds: 0, inspectionMilliseconds: 0, totalMilliseconds: 0}};
  const finish = () => { plan.costs.totalMilliseconds = Math.round(performance.now() - start); return plan; };
  if (baseline.baseSha === null) return finish();
  validateMainBaseline(baseline);
  assert.equal(baseline.testedSha, context.candidateRevision);
  assert.equal(baseline.workflowId, context.workflowId);
  const originTree = treeAt(baseline.baseSha);
  // Missing initial registration is a bootstrap miss, never a reusable origin.
  if (!originTree.entries.has(catalogPath)) {
    actions.forEach(action => action.status = 'origin-catalog-missing'); return finish();
  }
  const originalCatalog = validateCatalog(JSON.parse(originTree.read(catalogPath)));
  compareCatalogs(originalCatalog, catalog); // Missing required registration must fail, not shrink the inventory.
  if (!policyUnchanged(originTree, tree)) {
    actions.forEach(action => action.status = 'policy-changed'); return finish();
  }
  let archive, originRuntime, artifact;
  const transferStart = performance.now();
  try {
    artifact = selectOriginArtifact(await request(`/actions/runs/${baseline.runId}/artifacts?per_page=100`), baseline, context);
    archive = await download({repository: context.repository, artifactId: artifact.id, token, directory});
    originRuntime = await loadRuntime({archive, artifact, baseline, context});
    plan.artifact = {id: artifact.id, digest: artifact.digest, bytes: artifact.size_in_bytes};
  } catch {
    // No API body, signed URL, filesystem path, token or arbitrary exception
    // message is copied into scientific evidence or diagnostics.
    actions.forEach(action => action.status = 'origin-archive-unavailable');
    plan.costs.transferMilliseconds = Math.round(performance.now() - transferStart);
    return finish();
  }
  plan.costs.transferMilliseconds = Math.round(performance.now() - transferStart);
  const inspectionStart = performance.now();
  for (const [index, action] of catalog.actions.entries()) {
    const entry = actions[index], registered = originalCatalog.actions.find(value => value.id === action.id);
    if (!registered || !unchanged(registered, action)) { entry.status = 'registration-changed'; continue; }
    try {
      const original = await read({archive, artifactId: artifact.id, action, acquisition: 'reused', request,
        expected: {...context, ancestors: [baseline.baseSha]}});
      const receipt = original.receipt;
      assert(unchanged(receipt.action, action), 'Wrong origin action/target/scope');
      assert.equal(receipt.origin.testedRevision, baseline.baseSha);
      assert.equal(receipt.origin.runId, baseline.runId); assert.equal(receipt.origin.runAttempt, baseline.runAttempt);
      assert.equal(original.artifactId, artifact.id);
      assert.equal(original.archiveDigest, artifact.digest.replace(/^sha256:/u, ''));
      assert(unchanged(receipt.inputs.inputs.runtime, originRuntime), 'Receipt runtime differs from authenticated observation');
      const reconstructed = actionInputs({tree: originTree, revision: baseline.baseSha, action, runtime: originRuntime});
      assert(unchanged(reconstructed, receipt.inputs), 'Original carried inputs do not match actual Git');
      const current = actionInputs({tree, revision: context.candidateRevision, action, runtime});
      const comparison = compareInputs(reconstructed, current);
      entry.status = comparison.eligible ? 'closed-inputs-match' : comparison.equal ? 'same-inputs-open' : 'candidate-inputs-changed';
      entry.equal = comparison.equal; entry.closed = comparison.eligible; entry.unresolved = comparison.reasons;
      entry.origin = {receiptDigest: original.receiptDigest, actionKey: reconstructed.key,
        revision: receipt.origin.testedRevision, runId: receipt.origin.runId, runAttempt: receipt.origin.runAttempt,
        units: receipt.execution.units, milliseconds: receipt.execution.milliseconds};
    } catch { entry.status = 'origin-rejected'; }
  }
  plan.costs.inspectionMilliseconds = Math.round(performance.now() - inspectionStart);
  return finish();
}

export function compareFreshObservations({plan, context, runtime, tree, receipts}) {
  assert.equal(plan.version, comparisonVersion); assert.equal(plan.mode, 'comparison');
  assert.equal(plan.reuseAuthorized, false, 'Comparison cannot authorize skip');
  assert(unchanged(plan.context, context), 'Different comparison owner');
  const catalog = validateCatalog(JSON.parse(tree.read(catalogPath)));
  assert.equal(plan.catalogDigest, identity(catalog));
  assert.deepEqual(plan.actions.map(entry => entry.actionId), catalog.actions.map(action => action.id), 'Incomplete comparison inventory');
  assert.deepEqual(receipts.map(receipt => receipt.action.id), catalog.actions.map(action => action.id), 'Incomplete fresh comparison');
  return catalog.actions.map((action, index) => {
    const entry = plan.actions[index], receipt = receipts[index];
    assert.equal(entry.acquisition, 'execute');
    assert(unchanged(receipt.action, action) && receipt.origin.testedRevision === context.candidateRevision);
    const current = actionInputs({tree, revision: context.candidateRevision, action, runtime});
    assert.equal(entry.candidateActionKey, current.key, 'Changed candidate comparison inputs');
    assert(unchanged(receipt.inputs, current), 'Fresh receipt does not match comparison candidate');
    const comparable = entry.equal && entry.origin !== null;
    const matches = comparable && receipt.execution.units === entry.origin.units;
    // This measures count correspondence only. It is not a proof of output
    // determinism, and an open runtime cannot become closed because counts match.
    if (entry.closed) assert(matches, 'Closed equal-input action disagreed with normal execution');
    return {actionId: action.id, status: !comparable ? 'not-comparable' : matches ? 'counts-match' : 'counts-mismatch',
      freshUnits: receipt.execution.units, originUnits: comparable ? entry.origin.units : null,
      freshMilliseconds: receipt.execution.milliseconds, originMilliseconds: entry.origin?.milliseconds ?? null};
  });
}

// Reconstruct the scientific comparison at the final check. Differences in
// transfer timings are expected; origin identity, inputs and decisions are not.
export async function verifyComparison({plan, ...options}) {
  exact(plan, ['version', 'mode', 'reuseAuthorized', 'context', 'catalogDigest', 'baseline', 'artifact', 'actions', 'costs']);
  assert.equal(plan.version, comparisonVersion); assert.equal(plan.mode, 'comparison'); assert.equal(plan.reuseAuthorized, false);
  assert(unchanged(plan.context, options.context), 'Different final comparison owner');
  exact(plan.costs, ['checkpointMilliseconds', 'transferMilliseconds', 'inspectionMilliseconds', 'totalMilliseconds']);
  assert(Object.values(plan.costs).every(value => Number.isSafeInteger(value) && value >= 0), 'Invalid comparison costs');
  // A cache/history miss consumed no original. Do not turn later availability
  // into a retroactive adoption or fail an otherwise valid complete fresh run.
  // This records that no origin was used, not a claim that absence is permanent.
  if (plan.artifact === null) {
    assert(plan.actions.every(entry => entry.origin === null && !entry.equal && !entry.closed && entry.acquisition === 'execute' &&
      ['checkpoint-unavailable', 'origin-catalog-missing', 'policy-changed', 'origin-archive-unavailable'].includes(entry.status)),
    'No-origin plan carried a successful original');
    return {checkpointMilliseconds: 0, transferMilliseconds: 0, inspectionMilliseconds: 0, totalMilliseconds: 0};
  }
  const replay = await comparisonPlan({...options, recordedRunId: plan.baseline.baseSha === null ? null : plan.baseline.runId});
  for (const field of ['version', 'mode', 'reuseAuthorized', 'context', 'catalogDigest', 'baseline', 'artifact', 'actions']) {
    assert(unchanged(plan[field], replay[field]), `Changed/invalid comparison ${field}`);
  }
  return replay.costs;
}
