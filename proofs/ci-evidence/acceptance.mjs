// An immutable final-consumer observation, separate from original receipts.
// A successful producer or count match alone never opens the reuse boundary.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {encode} from '../bounded-session/action-inputs.mjs';
import {openArtifactZip} from '../../scripts/ci-artifact-reader.mjs';
import {hash} from './inputs.mjs';
import {parseReceipt, readOriginReceipt} from './receipts.mjs';
import {leanRecords, applicationVersion} from './applications.mjs';
import {leanInput} from './check.mjs';
import {ArtifactUnavailable, downloadArtifact, unavailableTransport} from './transport.mjs';
import {readActionRuntimes} from './isolated-runtime.mjs';
import {resolveMainBaseline, fullCheckpointJobs, validateMainBaseline, isMainEvidenceEvent} from '../../scripts/ci-main-base.mjs';
import {gateJobs} from '../../scripts/ci-targets.mjs';
import {catalogPath, validateCatalog, compareCatalogs} from './actions.mjs';
import {checkCostObservation} from './costs.mjs';

export const acceptanceVersion = 'actql-verification-family-acceptance/0.1';
export const acceptanceName = context => `session-applicability-${context.runId}-${context.runAttempt}-${context.candidateRevision}`;
const same = (a, b) => encode(a) === encode(b);
const exact = (value, fields) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort());
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0;

export function readyActions({result, observations, event, branch}) {
  // Main always executes fresh. Only the independently checked, completed
  // comparison period may qualify its evidence for a later PR.
  if (!isMainEvidenceEvent(event, branch) || result.context.candidateRevision !== result.context.runHeadRevision ||
      result.comparison.confirmation.status !== 'confirmed' ||
      !result.applications.every(entry => entry.acquisition === 'fresh')) return [];
  const application = result.applications.find(entry => entry.actionId === 'mutations-js');
  const comparison = result.comparison.recordedStatuses.find(entry => entry.actionId === 'mutations-js');
  const observation = observations.find(entry => entry.actionId === 'mutations-js');
  if (!application || comparison?.status !== 'closed-inputs-match' || observation?.status !== 'scientific-match') return [];
  assert(digest(observation.scientificDigest) && observation.scientificDigest === observation.originScientificDigest,
    'Ready evidence lacks matching scientific observations');
  return [{actionId: application.actionId, actionKey: application.candidateActionKey,
    receiptDigest: application.originReceiptDigest, scientificDigest: observation.scientificDigest}];
}

export function sealAcceptance({result, observations, owner, event, branch, sourceArtifact, certificateDigest}) {
  assert(positive(owner.jobId) && owner.runId === result.context.runId && owner.runAttempt === result.context.runAttempt);
  assert(positive(sourceArtifact.id) && digest(sourceArtifact.digest) && digest(certificateDigest));
  return {version: acceptanceVersion, context: result.context, owner, event, branch,
    sourceArtifact, certificateDigest, result, observations,
    ready: readyActions({result, observations, event, branch})};
}

// Reconstruct all certificate/applicability bindings from the immutable source
// archive. The report cannot define its own mandatory inventory or source ZIP.
export async function checkAcceptance({report, catalog, sourceZip, sourceArtifact, context}) {
  exact(report, ['version', 'context', 'owner', 'event', 'branch', 'sourceArtifact', 'certificateDigest', 'result', 'observations', 'ready']);
  assert.equal(report.version, acceptanceVersion);
  assert(same(report.context, context), 'Wrong acceptance owner/context');
  assert(same(report.sourceArtifact, sourceArtifact), 'Acceptance substituted the source archive');
  assert.equal(report.result.sourceArtifactBytes, sourceZip.compressedBytes, 'Wrong accepted source archive byte observation');
  assert(positive(sourceZip.compressedBytes), 'Missing accepted source archive byte observation');
  assert(isMainEvidenceEvent(report.event, report.branch), 'Acceptance is not from protected main integration');
  assert.equal(context.candidateRevision, context.runHeadRevision);
  exact(report.owner, ['runId', 'runAttempt', 'jobId']);
  assert.equal(report.owner.runId, context.runId); assert.equal(report.owner.runAttempt, context.runAttempt);
  assert(positive(report.owner.jobId));
  const bytes = await sourceZip.read('checked.json'), certificate = JSON.parse(bytes);
  assert.equal(hash(bytes), report.certificateDigest, 'Acceptance changed executed certificate');
  assert(same(certificate.context, context) && same(report.result.context, context));
  assert.equal(certificate.mode, 'scoped-execution');
  assert.equal(certificate.catalogDigest, hash(encode(catalog)));
  assert.equal(report.result.catalogDigest, certificate.catalogDigest);
  assert.deepEqual(report.result.requiredActions, catalog.actions.map(action => action.id));
  assert.equal(report.result.applications.length, catalog.actions.length, 'Incomplete accepted family');
  const required = [], applications = [], receiptDigests = [], receipts = [];
  let mutationInputs;
  for (const [index, action] of catalog.actions.entries()) {
    const receiptBytes = await sourceZip.read(`receipts/${action.id}.json`), receipt = parseReceipt(receiptBytes);
    receipts.push(receipt);
    assert(same(receipt.action, action), 'Wrong accepted action/target/scope');
    assert.equal(receipt.origin.testedRevision, context.candidateRevision);
    assert.equal(receipt.origin.runId, context.runId); assert.equal(receipt.origin.runAttempt, context.runAttempt);
    assert.equal(receipt.origin.event, report.event); assert.equal(receipt.origin.branch, report.branch);
    if (action.id === 'mutations-js') mutationInputs = receipt.inputs;
    const records = leanRecords(action, receipt.inputs, {receipt}, context, 'fresh');
    required.push(records.required); applications.push(records.application);
    const receiptDigest = hash(receiptBytes); receiptDigests.push({actionId: action.id, digest: receiptDigest});
    assert(same(report.result.applications[index], {version: applicationVersion,
      candidateRevision: context.candidateRevision, actionId: action.id, acquisition: 'fresh',
      originReceiptDigest: receiptDigest, originRevision: receipt.origin.testedRevision,
      originRunId: receipt.origin.runId, originRunAttempt: receipt.origin.runAttempt,
      artifactId: sourceArtifact.id, archiveDigest: sourceArtifact.digest,
      candidateActionKey: receipt.inputs.key, originActionKey: receipt.inputs.key,
      kind: action.kind, target: action.target, scopeDigest: hash(encode({profile: action.profile, premises: action.premises})),
      checkerResult: 'accepted'}), 'Acceptance does not bind the actual complete fresh family');
  }
  assert(same(certificate.receiptDigests, receiptDigests));
  assert(same(certificate.lean, report.result.lean) && certificate.lean.accepted === true && certificate.lean.theoremCount === 5);
  assert.equal(certificate.lean.inputDigest, hash(leanInput(required, applications)));
  assert.equal(certificate.lean.outputDigest, hash(await sourceZip.read('lean-output.log')));
  assert.equal(certificate.comparisonDigest, hash(await sourceZip.read('comparison-plan.json')));
  const observationBytes = await sourceZip.read('comparison-observations.json');
  assert.equal(certificate.comparisonObservationsDigest, hash(observationBytes));
  assert(same(report.observations, JSON.parse(observationBytes)), 'Wrong accepted scientific observations');
  const comparison = JSON.parse(await sourceZip.read('comparison-plan.json'));
  const acquisitionBytes = await sourceZip.read('acquisition-plan.json'), acquisition = JSON.parse(acquisitionBytes);
  assert.equal(certificate.acquisitionDigest, hash(acquisitionBytes), 'Wrong accepted acquisition cost binding');
  const state = JSON.parse(await sourceZip.read('context.json'));
  assert(same(state.context, context), 'Wrong accepted cost context');
  assert(same(report.result.acquisition, acquisition), 'Wrong accepted acquisition costs');
  assert(acquisition.actions.every(entry => entry.acquisition === 'fresh'), 'Main original must execute every cost observation fresh');
  assert(same(report.result.costObservation, checkCostObservation({
    collectionBytes: await sourceZip.read('collection-costs.json'), certificate, state, catalog,
    acquisition, comparison, receipts,
    isolatedExecution: JSON.parse(await sourceZip.read('isolated-execution.json')),
  })), 'Wrong accepted cost correspondence');
  assert(same(comparison.context, context) && comparison.reuseAuthorized === false);
  assert(same(report.result.comparison.baseline, comparison.baseline));
  assert(same(report.result.comparison.recordedStatuses, comparison.actions.map(entry => ({actionId: entry.actionId, status: entry.status}))));
  assert.equal(report.result.comparison.reuseAuthorized, false);
  assert(same(report.ready, readyActions(report)), 'Unconfirmed comparison cannot authorize reuse');
  if (report.ready.length) assert(mutationInputs?.unresolved.length === 0, 'Open input boundary cannot qualify for reuse');
  return report.ready;
}

function metadata(artifact, context) {
  assert(positive(artifact?.id) && positive(artifact.size_in_bytes) && artifact.size_in_bytes <= 1024 * 1024);
  assert.equal(artifact.name, acceptanceName(context));
  assert.equal(artifact.workflow_run?.id, context.runId); assert.equal(artifact.workflow_run?.head_sha, context.runHeadRevision);
  assert.equal(artifact.workflow_run?.repository_id, context.repositoryId);
  assert.equal(artifact.workflow_run?.head_repository_id, context.repositoryId);
  assert(/^sha256:[a-f0-9]{64}$/u.test(artifact.digest ?? ''));
  assert(typeof artifact.expired === 'boolean' && Number.isFinite(Date.parse(artifact.expires_at)));
  if (artifact.expired || Date.parse(artifact.expires_at) <= Date.now()) throw new ArtifactUnavailable();
  return artifact;
}

export async function readAcceptance({catalog, sourceArchive, sourceArtifact, context, request, token, directory,
  artifactId = null, archive = null, expectedDigest = null, download = downloadArtifact}) {
  const run = await request(`/actions/runs/${context.runId}`);
  const checkRun = value => {
    assert.equal(value.id, context.runId); assert.equal(value.run_attempt, context.runAttempt);
    assert.equal(value.head_sha, context.candidateRevision); assert.equal(value.workflow_id, context.workflowId);
    assert.equal(value.path, '.github/workflows/ci.yml');
    assert(isMainEvidenceEvent(value.event, value.head_branch), 'Acceptance is not from protected main integration');
    assert.equal(value.event, run.event, 'Acceptance trigger changed during inspection');
    assert.equal(value.repository?.id, context.repositoryId); assert.equal(value.repository?.full_name, context.repository);
    assert.equal(value.head_repository?.id, context.repositoryId);
    assert.equal(value.status, 'completed'); assert.equal(value.conclusion, 'success');
  };
  checkRun(run);
  let artifact;
  if (artifactId === null) {
    const data = await request(`/actions/runs/${context.runId}/artifacts?per_page=100`);
    assert(Array.isArray(data.artifacts) && data.total_count === data.artifacts.length && data.artifacts.length <= 100);
    const found = data.artifacts.filter(entry => entry.name === acceptanceName(context));
    if (found.length === 0) throw new ArtifactUnavailable();
    assert.equal(found.length, 1, 'Ambiguous final acceptance archive'); artifact = metadata(found[0], context);
  } else artifact = metadata(await request(`/actions/artifacts/${artifactId}`), context);
  if (expectedDigest !== null) assert.equal(artifact.digest, `sha256:${expectedDigest.replace(/^sha256:/u, '')}`, 'Changed acceptance archive digest');
  archive ??= await download({repository: context.repository, artifactId: artifact.id, token, directory});
  const zip = await openArtifactZip(archive, {expectedSha256: artifact.digest,
    limits: {maxCompressedBytes: 1024 * 1024, maxTotalBytes: 2 * 1024 * 1024, maxEntries: 1}});
  let sourceZip;
  try {
    sourceZip = await openArtifactZip(sourceArchive, {expectedSha256: sourceArtifact.digest,
      limits: {maxCompressedBytes: 64 * 1024 * 1024, maxTotalBytes: 256 * 1024 * 1024, maxEntries: 2000}});
    assert.deepEqual(zip.entries.map(entry => entry.path), ['verified-family.json']);
    const bytes = await zip.read('verified-family.json'), report = JSON.parse(bytes);
    assert(Buffer.from(`${encode(report)}\n`).equals(bytes), 'Noncanonical acceptance report');
    assert.equal(report.event, run.event, 'Acceptance changed the authenticated run trigger');
    const ready = await checkAcceptance({report, catalog, sourceZip, sourceArtifact, context});
    const jobs = await request(`/actions/runs/${context.runId}/attempts/${context.runAttempt}/jobs?per_page=100`);
    assert(Array.isArray(jobs.jobs) && jobs.total_count === jobs.jobs.length && jobs.jobs.length <= 100);
    const owned = jobs.jobs.filter(job => job.id === report.owner.jobId);
    assert.equal(owned.length, 1); const job = owned[0];
    assert.equal(job.name, 'check'); assert.equal(job.run_id, context.runId); assert.equal(job.run_attempt, context.runAttempt);
    assert.equal(job.head_sha, context.runHeadRevision); assert.equal(job.status, 'completed'); assert.equal(job.conclusion, 'success');
    checkRun(await request(`/actions/runs/${context.runId}`));
    return {ready, artifactId: artifact.id, archiveDigest: artifact.digest.slice('sha256:'.length), archive};
  } finally { await zip.close(); await sourceZip?.close(); }
}

export async function readReadyOrigin({root, catalog, sourceArchive, sourceArtifact, baseline, candidateContext,
  treeAt, request, token, directory, artifactId = null, archive = null, expectedDigest = null}) {
  validateMainBaseline(baseline);
  const actualRun = await request(`/actions/runs/${baseline.runId}`);
  assert.equal(actualRun.id, baseline.runId); assert.equal(actualRun.run_attempt, baseline.runAttempt);
  assert.equal(actualRun.head_sha, baseline.baseSha); assert.equal(actualRun.workflow_id, candidateContext.workflowId);
  assert.equal(actualRun.repository?.id, candidateContext.repositoryId); assert.equal(actualRun.head_repository?.id, candidateContext.repositoryId);
  assert.equal(actualRun.path, '.github/workflows/ci.yml');
  assert(isMainEvidenceEvent(actualRun.event, actualRun.head_branch), 'Ready origin is not protected main integration');
  assert.equal(actualRun.status, 'completed'); assert.equal(actualRun.conclusion, 'success');
  let unavailable = false;
  const verified = await resolveMainBaseline({testedSha: candidateContext.candidateRevision,
    repository: candidateContext.repository, repositoryId: candidateContext.repositoryId,
    requiredJobs: fullCheckpointJobs(gateJobs),
    git: args => execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024}),
    request: async path => {
      try { return /^\/actions\/workflows\/\d+\/runs\?/u.test(path) ?
        {workflow_runs: [await request(`/actions/runs/${baseline.runId}`)]} : await request(path); }
      catch (error) { unavailable ||= unavailableTransport(error); throw error; }
    }});
  if (verified.baseSha === null && unavailable) throw new ArtifactUnavailable();
  assert(verified.baseSha !== null, 'Required full main checkpoint no longer verifies');
  assert(same(verified, baseline), 'Changed trusted main checkpoint');
  const originTree = treeAt(baseline.baseSha), originalCatalog = validateCatalog(JSON.parse(originTree.read(catalogPath)));
  compareCatalogs(originalCatalog, catalog);
  const zip = await openArtifactZip(sourceArchive, {expectedSha256: sourceArtifact.digest,
    limits: {maxCompressedBytes: 64 * 1024 * 1024, maxTotalBytes: 256 * 1024 * 1024, maxEntries: 2000}});
  let state;
  try {
    state = await zip.json('context.json'); const context = state.context;
    assert.equal(context.repository, candidateContext.repository); assert.equal(context.repositoryId, candidateContext.repositoryId);
    assert.equal(context.headRepositoryId, candidateContext.repositoryId); assert.equal(context.workflowId, candidateContext.workflowId);
    assert.equal(context.candidateRevision, baseline.baseSha); assert.equal(context.runHeadRevision, baseline.baseSha);
    assert.equal(context.runId, baseline.runId); assert.equal(context.runAttempt, baseline.runAttempt);
    await readActionRuntimes({zip, state, tree: originTree});
  } finally { await zip.close(); }
  const action = catalog.actions.find(entry => entry.id === 'mutations-js');
  assert(action, 'Missing independent reusable registration');
  const original = await readOriginReceipt({archive: sourceArchive, artifactId: sourceArtifact.id, action,
    acquisition: 'reused', request, expected: {...candidateContext, ancestors: [baseline.baseSha]}});
  assert.equal(original.receipt.origin.event, actualRun.event, 'Ready origin trigger changed during inspection');
  assert.equal(original.archiveDigest, sourceArtifact.digest);
  const accepted = await readAcceptance({catalog: originalCatalog, sourceArchive, sourceArtifact, context: state.context, request, token, directory,
    artifactId, archive, expectedDigest});
  for (const ready of accepted.ready) {
    assert.equal(ready.actionId, action.id); assert.equal(ready.receiptDigest, original.receiptDigest);
    assert.equal(ready.actionKey, original.receipt.inputs.key); assert.equal(ready.scientificDigest, original.scientificDigest);
  }
  return {...accepted, original};
}
