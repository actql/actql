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
import {readOriginReceipts} from './receipts.mjs';
import {downloadArtifact, ArtifactUnavailable, unavailableTransport} from './transport.mjs';
import {checkRuntimeObservation} from './runtime.mjs';
import {runtimeForAction, readActionRuntimes} from './isolated-runtime.mjs';
import {mutationObservation} from './mutation-observation.mjs';

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
  if (selected.length === 0 && !data.artifacts.some(artifact => artifact.name?.startsWith('session-actions-'))) throw new ArtifactUnavailable();
  assert.equal(selected.length, 1, 'Missing/ambiguous original Session archive');
  const artifact = selected[0];
  assert(positive(artifact.id) && positive(artifact.size_in_bytes) && artifact.size_in_bytes <= 64 * 1024 * 1024,
    'Invalid origin archive size/identity');
  assert(typeof artifact.expired === 'boolean' && Number.isFinite(Date.parse(artifact.expires_at)), 'Invalid artifact expiry');
  assert(/^sha256:[a-f0-9]{64}$/u.test(artifact.digest ?? ''), 'Missing origin archive digest');
  assert.equal(artifact.workflow_run?.id, baseline.runId);
  assert.equal(artifact.workflow_run?.head_sha, baseline.baseSha);
  assert.equal(artifact.workflow_run?.repository_id, context.repositoryId);
  assert.equal(artifact.workflow_run?.head_repository_id, context.repositoryId);
  if (artifact.expired || Date.parse(artifact.expires_at) <= Date.now()) throw new ArtifactUnavailable();
  return artifact;
}

async function readRuntime({archive, artifact, baseline, context, tree}) {
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
    return {runtime: state.runtime, actionRuntimes: await readActionRuntimes({zip, state, tree})};
  } finally { await zip.close(); }
}

// All injection points are internal test seams. The CI caller supplies actual
// Git, the existing Actions client and transport; request JSON cannot override
// authentication, history, source extraction or runtime validation.
export async function comparisonPlan({root, context, runtime, actionRuntimes = {}, directory, token, request,
  recordedRunId = null, treeAt = revision => gitTree(root, revision),
  git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024}),
  resolveBaseline = resolveMainBaseline, download = downloadArtifact, read = null,
  loadRuntime = readRuntime, onArchive = null, readGroup = readOriginReceipts}) {
  assert(sha(context.candidateRevision) && positive(context.repositoryId) && positive(context.workflowId));
  assert(recordedRunId === null || positive(recordedRunId));
  const start = performance.now(), tree = treeAt(context.candidateRevision);
  const catalog = validateCatalog(JSON.parse(tree.read(catalogPath)));
  const actions = catalog.actions.map(action => ({actionId: action.id, acquisition: 'execute',
    candidateActionKey: actionInputs({tree, revision: context.candidateRevision, action, runtime: runtimeForAction(action, runtime, actionRuntimes)}).key,
    status: 'checkpoint-unavailable', origin: null, equal: false, closed: false, unresolved: []}));
  // At the final consumer validate the originally selected checkpoint again,
  // rather than changing the origin when another old run finishes meanwhile.
  // The restricted list still comes from the live API, not carried JSON.
  let checkpointUnavailable = false;
  const checkpointRequest = async path => {
    try {
      if (recordedRunId !== null && /^\/actions\/workflows\/\d+\/runs\?/u.test(path)) {
        return {workflow_runs: [await request(`/actions/runs/${recordedRunId}`)]};
      }
      return await request(path);
    } catch (error) { checkpointUnavailable ||= unavailableTransport(error); throw error; }
  };
  const baseline = await resolveBaseline({testedSha: context.candidateRevision, repository: context.repository,
    repositoryId: context.repositoryId, requiredJobs: fullCheckpointJobs(gateJobs), git, request: checkpointRequest});
  // The shared resolver reports lookup failures instead of throwing. Retain
  // typed transport failure for the final optional-comparison boundary.
  if (recordedRunId !== null && checkpointUnavailable) throw new ArtifactUnavailable();
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
    originRuntime = await loadRuntime({archive, artifact, baseline, context, tree: originTree});
    plan.artifact = {id: artifact.id, digest: artifact.digest, bytes: artifact.size_in_bytes};
  } catch (error) {
    if (!unavailableTransport(error)) throw error;
    // No API body, signed URL, filesystem path, token or arbitrary exception
    // message is copied into scientific evidence or diagnostics.
    actions.forEach(action => action.status = 'origin-archive-unavailable');
    plan.costs.transferMilliseconds = Math.round(performance.now() - transferStart);
    return finish();
  }
  plan.costs.transferMilliseconds = Math.round(performance.now() - transferStart);
  const inspectionStart = performance.now();
  const matched = catalog.actions.filter(action => {
    const registered = originalCatalog.actions.find(value => value.id === action.id);
    return registered && unchanged(registered, action);
  });
  let originals = null, groupFailure;
  if (read === null && matched.length > 0) {
    try {
      originals = await readGroup({archive, artifactId: artifact.id, actions: matched,
        acquisition: 'reused', request, expected: {...context, ancestors: [baseline.baseSha]}});
    } catch (error) { groupFailure = error; }
  }
  for (const [index, action] of catalog.actions.entries()) {
    const entry = actions[index], registered = originalCatalog.actions.find(value => value.id === action.id);
    if (!registered || !unchanged(registered, action)) { entry.status = 'registration-changed'; continue; }
    try {
      if (groupFailure) throw groupFailure;
      const original = read === null ? originals.get(action.id) : await read({archive, artifactId: artifact.id, action,
        acquisition: 'reused', request, expected: {...context, ancestors: [baseline.baseSha]}});
      const receipt = original.receipt;
      assert(unchanged(receipt.action, action), 'Wrong origin action/target/scope');
      assert.equal(receipt.origin.testedRevision, baseline.baseSha);
      assert.equal(receipt.origin.runId, baseline.runId); assert.equal(receipt.origin.runAttempt, baseline.runAttempt);
      assert.equal(original.artifactId, artifact.id);
      assert.equal(original.archiveDigest, artifact.digest.replace(/^sha256:/u, ''));
      const originalRuntime = runtimeForAction(action, originRuntime.runtime, originRuntime.actionRuntimes);
      assert(unchanged(receipt.inputs.inputs.runtime, originalRuntime), 'Receipt runtime differs from authenticated observation');
      const reconstructed = actionInputs({tree: originTree, revision: baseline.baseSha, action, runtime: originalRuntime});
      assert(unchanged(reconstructed, receipt.inputs), 'Original carried inputs do not match actual Git');
      const current = actionInputs({tree, revision: context.candidateRevision, action, runtime: runtimeForAction(action, runtime, actionRuntimes)});
      const comparison = compareInputs(reconstructed, current);
      entry.status = comparison.eligible ? 'closed-inputs-match' : comparison.equal ? 'same-inputs-open' : 'candidate-inputs-changed';
      entry.equal = comparison.equal; entry.closed = comparison.eligible; entry.unresolved = comparison.reasons;
      entry.origin = {receiptDigest: original.receiptDigest, actionKey: reconstructed.key,
        revision: receipt.origin.testedRevision, runId: receipt.origin.runId, runAttempt: receipt.origin.runAttempt,
        units: receipt.execution.units, milliseconds: receipt.execution.milliseconds,
        scientificDigest: original.scientificDigest ?? null};
    } catch (error) {
      // Optional origin authentication must not prevent any fresh action from
      // running. Keep authenticated earlier entries; this entry has no origin
      // or equality claim and cannot authorize reuse.
      entry.status = unavailableTransport(error) ? 'origin-receipt-unavailable' : 'origin-rejected';
    }
  }
  // A private transport handle, never serialized in scientific evidence. It
  // lets the execution selector retain exactly the already inspected archive.
  onArchive?.({archive, artifact, baseline});
  plan.costs.inspectionMilliseconds = Math.round(performance.now() - inspectionStart);
  return finish();
}

export function compareFreshObservations({plan, context, runtime, actionRuntimes = {}, tree, receipts, mutationResult = null,
  acquisitions = null}) {
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
    assert(unchanged(receipt.action, action));
    const current = actionInputs({tree, revision: context.candidateRevision, action, runtime: runtimeForAction(action, runtime, actionRuntimes)});
    assert.equal(entry.candidateActionKey, current.key, 'Changed candidate comparison inputs');
    const acquisition = acquisitions?.find(value => value.actionId === action.id);
    if (acquisition?.acquisition === 'reused') {
      assert.equal(action.id, 'mutations-js');
      assert.equal(receipt.origin.testedRevision, acquisition.origin.revision);
      assert.equal(receipt.inputs.key, current.key);
      assert.equal(hash(Buffer.from(`${encode(receipt)}\n`)), acquisition.origin.receiptDigest);
      return {actionId: action.id, status: 'reused-not-executed', freshUnits: null, originUnits: receipt.execution.units,
        freshMilliseconds: null, originMilliseconds: receipt.execution.milliseconds,
        scientificDigest: null, originScientificDigest: acquisition.origin.scientificDigest};
    }
    assert.equal(receipt.origin.testedRevision, context.candidateRevision);
    assert(unchanged(receipt.inputs, current), 'Fresh receipt does not match comparison candidate');
    const comparable = entry.equal && entry.origin !== null;
    const scientificDigest = action.id === 'mutations-js' ? mutationObservation(mutationResult).digest : null;
    const matches = comparable && receipt.execution.units === entry.origin.units &&
      (action.id !== 'mutations-js' || scientificDigest === entry.origin.scientificDigest);
    // For mutations compare the registered experiment selections and actual
    // detection results too. This is finite correspondence, not a proof of
    // determinism; matching results cannot close an unreviewed input boundary.
    if (entry.closed) assert(matches, 'Closed equal-input action disagreed with normal execution');
    return {actionId: action.id, status: !comparable ? 'not-comparable' : matches ?
      action.id === 'mutations-js' ? 'scientific-match' : 'counts-match' :
      action.id === 'mutations-js' ? 'scientific-mismatch' : 'counts-mismatch',
      freshUnits: receipt.execution.units, originUnits: comparable ? entry.origin.units : null,
      freshMilliseconds: receipt.execution.milliseconds, originMilliseconds: entry.origin?.milliseconds ?? null,
      scientificDigest, originScientificDigest: comparable ? entry.origin.scientificDigest : null};
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
  // An already completed integrity rejection is permanent for this recorded
  // comparison. A repeated rejection, later repair or transport outage cannot
  // confirm it or downgrade it to optional unavailability.
  assert(Array.isArray(plan.actions) && !plan.actions.some(entry => entry.status === 'origin-rejected'),
    'Rejected origin receipt');
  // A cache/history miss consumed no original. Do not turn later availability
  // into a retroactive adoption or fail an otherwise valid complete fresh run.
  // This records that no origin was used, not a claim that absence is permanent.
  if (plan.artifact === null) {
    assert(plan.actions.every(entry => entry.origin === null && !entry.equal && !entry.closed && entry.acquisition === 'execute' &&
      ['checkpoint-unavailable', 'origin-catalog-missing', 'policy-changed', 'origin-archive-unavailable'].includes(entry.status)),
    'No-origin plan carried a successful original');
    return {status: 'not-compared', reuseAuthorized: false,
      costs: {checkpointMilliseconds: 0, transferMilliseconds: 0, inspectionMilliseconds: 0, totalMilliseconds: 0}};
  }
  const started = performance.now();
  let replay;
  try {
    // The resolver deliberately discards unsuitable checkpoints. Check the
    // recorded identity separately so a changed run/attempt cannot masquerade
    // as a transport miss during optional comparison.
    const run = await options.request(`/actions/runs/${plan.baseline.runId}`);
    assert.equal(run.id, plan.baseline.runId); assert.equal(run.run_attempt, plan.baseline.runAttempt);
    assert.equal(run.head_sha, plan.baseline.baseSha); assert.equal(run.workflow_id, options.context.workflowId);
    assert.equal(run.repository?.id, options.context.repositoryId); assert.equal(run.head_repository?.id, options.context.repositoryId);
    assert.equal(run.path, '.github/workflows/ci.yml'); assert.equal(run.event, 'push'); assert.equal(run.head_branch, 'main');
    assert.equal(run.status, 'completed'); assert.equal(run.conclusion, 'success');
    const artifact = await options.request(`/actions/artifacts/${plan.artifact.id}`);
    assert.equal(artifact.id, plan.artifact.id); assert.equal(artifact.digest, plan.artifact.digest, 'Changed original archive digest');
    assert.equal(artifact.size_in_bytes, plan.artifact.bytes, 'Changed original archive size');
    // Identity checks precede expiry, so an expired but substituted object is
    // still an integrity rejection rather than an availability downgrade.
    selectOriginArtifact({total_count: 1, artifacts: [artifact]}, plan.baseline, options.context);
    replay = await comparisonPlan({...options, recordedRunId: plan.baseline.runId});
  } catch (error) {
    if (!unavailableTransport(error)) throw error;
    return {status: 'unconfirmed', reason: 'origin-unavailable', reuseAuthorized: false,
      costs: {totalMilliseconds: Math.round(performance.now() - started)}};
  }
  assert(!replay.actions.some(entry => entry.status === 'origin-rejected'), 'Rejected origin receipt');
  // A genuine cache miss after a valid start is informational: all candidate
  // obligations were independently executed fresh. Preserve the original plan.
  if (replay.artifact === null && replay.actions.every(entry => entry.status === 'origin-archive-unavailable')) {
    return {status: 'unconfirmed', reason: 'origin-unavailable', reuseAuthorized: false, costs: replay.costs};
  }
  for (const field of ['version', 'mode', 'reuseAuthorized', 'context', 'catalogDigest', 'baseline', 'artifact']) {
    assert(unchanged(plan[field], replay[field]), `Changed/invalid comparison ${field}`);
  }
  assert.equal(plan.actions.length, replay.actions.length, 'Changed/invalid comparison actions');
  let receiptUnavailable = false;
  for (const [index, entry] of plan.actions.entries()) {
    const current = replay.actions[index];
    for (const value of [entry, current]) exact(value,
      ['actionId', 'acquisition', 'candidateActionKey', 'status', 'origin', 'equal', 'closed', 'unresolved']);
    for (const field of ['actionId', 'acquisition', 'candidateActionKey']) {
      assert(unchanged(entry[field], current[field]), `Changed/invalid comparison ${field}`);
    }
    if ([entry, current].some(value => value.status === 'origin-receipt-unavailable')) {
      for (const value of [entry, current].filter(value => value.status === 'origin-receipt-unavailable')) {
        assert(value.origin === null && value.equal === false && value.closed === false && value.acquisition === 'execute' &&
          unchanged(value.unresolved, []), 'Unavailable receipt carried a successful original');
      }
      // A completed but inconsistent authentication is never a transport miss.
      assert(![entry, current].some(value => value.status === 'origin-rejected'), 'Rejected origin receipt');
      receiptUnavailable = true;
    } else assert(unchanged(entry, current), 'Changed/invalid comparison actions');
  }
  // Initial partial comparisons stay partial even when the final read recovers.
  // Do not rewrite the recorded plan or retroactively adopt recovered receipts.
  if (receiptUnavailable) return {status: 'unconfirmed', reason: 'origin-receipt-unavailable',
    reuseAuthorized: false, costs: replay.costs};
  return {status: 'confirmed', reuseAuthorized: false, costs: replay.costs};
}
