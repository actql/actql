// Consume the current family's immutable ZIP in the final required check.
// The family ran the actual Lean checker; here authenticate that successful
// job and reconstruct its exact submitted Lean input/certificate binding.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mkdir} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {actionsReader} from '../../scripts/ci-main-base.mjs';
import {openArtifactZip} from '../../scripts/ci-artifact-reader.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog, initialRegistrationRevision} from './actions.mjs';
import {hash} from './inputs.mjs';
import {checkApplications} from './applications.mjs';
import {leanInput} from './check.mjs';
import {downloadArtifact} from './transport.mjs';
import {checkRuntimeObservation} from './runtime.mjs';
import {gitTree} from './inputs.mjs';
import {parseReceipt} from './receipts.mjs';
import {compareFreshObservations, verifyComparison} from './plan.mjs';
import {readActionRuntimes, readCandidateActionRuntimes} from './isolated-runtime.mjs';
import {verifyAcquisition} from './acquisition.mjs';
import {readReadyOrigin, sealAcceptance} from './acceptance.mjs';

export function checkCertificate({certificate, output, context, catalog, required, applications, receiptDigests}) {
  assert.equal(certificate.version, 'actql-verification-family-certificate/0.1');
  assert.equal(certificate.mode, 'scoped-execution');
  assert.equal(encode(certificate.context), encode(context), 'Wrong certificate candidate/run/attempt');
  assert.equal(certificate.catalogDigest, hash(encode(catalog)), 'Certificate omitted or relabeled required catalog');
  assert.equal(encode(certificate.receiptDigests), encode(receiptDigests), 'Certificate changed original receipt bytes');
  assert.equal(certificate.lean?.accepted, true);
  assert.equal(certificate.lean.theoremCount, 5);
  const pin = readFileSync(new URL('../bounded-session/lean-toolchain', import.meta.url), 'utf8').trim();
  assert.equal(certificate.lean.toolchain, pin);
  assert.equal(certificate.lean.inputDigest, hash(leanInput(required, applications)), 'Certificate is for a different Lean plan');
  assert.equal(certificate.lean.outputDigest, hash(output), 'Changed Lean output');
  return certificate.lean;
}

export async function verifyCurrentFamily({root, artifactId, expectedDigest, context, request, archive, token, directory}) {
  const started = performance.now();
  // Independently validate the API metadata again for each receipt below. This
  // first open only reads data needed to reconstruct the current obligation.
  const metadata = await request(`/actions/artifacts/${artifactId}`);
  assert.equal(metadata.id, artifactId); assert.equal(metadata.expired, false);
  assert(typeof expectedDigest === 'string' && /^(?:sha256:)?[a-f0-9]{64}$/u.test(expectedDigest));
  assert.equal(metadata.digest, `sha256:${expectedDigest.replace(/^sha256:/u, '')}`, 'Job output/API archive digest mismatch');
  const zip = await openArtifactZip(archive, {expectedSha256: metadata.digest,
    limits: {maxCompressedBytes: 64 * 1024 * 1024, maxTotalBytes: 256 * 1024 * 1024, maxEntries: 2000}});
  let state, certificate, certificateDigest, output, distributionInputs, comparison, comparisonObservations, receipts, actionRuntimes, mutationResult, acquisition;
  const catalog = readCatalog(join(root, 'proofs/ci-evidence/bounded-session-actions.json'));
  try {
    distributionInputs = await zip.json('runtime-distributions.json');
    state = await zip.json('context.json'); const certificateBytes = await zip.read('checked.json');
    certificate = JSON.parse(certificateBytes); certificateDigest = hash(certificateBytes); output = await zip.read('lean-output.log');
    const acquisitionBytes = await zip.read('acquisition-plan.json'); acquisition = JSON.parse(acquisitionBytes);
    assert.equal(certificate.acquisitionDigest, hash(acquisitionBytes), 'Changed execution/reuse plan');
    const reused = acquisition.actions.filter(entry => entry.acquisition === 'reused');
    assert(reused.length <= 1 && reused.every(entry => entry.actionId === 'mutations-js'), 'Unreviewed reuse scope');
    actionRuntimes = await (reused.length ? readCandidateActionRuntimes : readActionRuntimes)({zip, state, tree: gitTree(root, context.candidateRevision)});
    const planBytes = await zip.read('comparison-plan.json'), observationsBytes = await zip.read('comparison-observations.json');
    assert.equal(certificate.comparisonDigest, hash(planBytes), 'Changed comparison plan');
    assert.equal(certificate.comparisonObservationsDigest, hash(observationsBytes), 'Changed fresh comparison observations');
    comparison = JSON.parse(planBytes); comparisonObservations = JSON.parse(observationsBytes);
    receipts = await Promise.all(catalog.actions.map(async action => parseReceipt(await zip.read(`receipts/${action.id}.json`))));
    mutationResult = reused.length ? null : await zip.json('results/mutations-js.json');
    if (reused.length) {
      // Retained original ZIP bytes are copied, never extracted over current
      // observations. Once used, these API-authenticated origins are required.
      for (const [path, limit] of [['reused/session-origin.zip', 64 * 1024 * 1024], ['reused/session-applicability.zip', 1024 * 1024]]) {
        const entry = zip.entries.find(value => value.path === path);
        assert(entry && entry.bytes > 0 && entry.bytes <= limit, 'Missing/unbounded retained original');
      }
      writeFileSync(join(directory, 'retained-session-origin.zip'), await zip.read('reused/session-origin.zip'), {flag: 'wx', mode: 0o600});
      writeFileSync(join(directory, 'retained-session-applicability.zip'), await zip.read('reused/session-applicability.zip'), {flag: 'wx', mode: 0o600});
    }
  } finally { await zip.close(); }
  assert.equal(encode(state.context), encode(context), 'Wrong collection candidate/run/attempt');
  checkRuntimeObservation(state.runtime, distributionInputs);
  assert(state.runtime.unresolved.includes('comparison only: distribution/core, loader, runtime configuration and external dependencies require reviewed closure'),
    'Comparison cannot silently claim a closed runtime');
  const reused = acquisition.actions.find(entry => entry.acquisition === 'reused');
  await verifyAcquisition({plan: acquisition, context, catalog, comparison, event: state.origin.event,
    readReady: async () => readReadyOrigin({root, catalog, sourceArchive: join(directory, 'retained-session-origin.zip'),
      sourceArtifact: {id: reused.origin.artifactId, digest: reused.origin.archiveDigest},
      baseline: comparison.baseline, candidateContext: context, treeAt: revision => gitTree(root, revision), request, token, directory,
      artifactId: reused.origin.acceptanceArtifactId, archive: join(directory, 'retained-session-applicability.zip'),
      expectedDigest: reused.origin.acceptanceArchiveDigest})});
  const entries = catalog.actions.map(action => {
    const entry = acquisition.actions.find(value => value.actionId === action.id);
    return {actionId: action.id, acquisition: entry.acquisition,
      archive: entry.acquisition === 'reused' ? join(directory, 'retained-session-origin.zip') : archive,
      artifactId: entry.acquisition === 'reused' ? entry.origin.artifactId : artifactId};
  });
  for (const [index, receipt] of receipts.entries()) if (acquisition.actions[index].acquisition === 'fresh')
    assert.equal(encode(receipt.origin), encode(state.origin), 'Mixed fresh collection owner');
  const applicationContext = reused ? {...context, ancestors: [reused.origin.revision]} : context;
  const result = await checkApplications({root, context: applicationContext, runtime: state.runtime, actionRuntimes,
    // Independent published inventory for bootstrap, not the candidate's own
    // edited inventory. Activation will use the verified main checkpoint.
    protectedRevision: initialRegistrationRevision, entries, request,
    prove: (required, applications, {receiptDigests}) =>
      checkCertificate({certificate, output, context, catalog, required, applications, receiptDigests})});
  // The ancestor authorization is derived above from the live resolver and
  // immutable retained origin; it is not part of the carried current owner.
  result.context = context;
  // Compare actual parsed immutable receipt digests with the certificate,
  // rather than checking a certificate's hashes against itself.
  assert.deepEqual(result.applications.map(entry => ({actionId: entry.actionId, digest: entry.originReceiptDigest})), certificate.receiptDigests);
  assert.equal(encode(comparisonObservations), encode(compareFreshObservations({plan: comparison, context,
    runtime: state.runtime, actionRuntimes, tree: gitTree(root, context.candidateRevision), receipts, mutationResult,
    acquisitions: acquisition.actions})), 'Wrong comparison of actual executions');
  const confirmation = await verifyComparison({plan: comparison, root, context, runtime: state.runtime, actionRuntimes, request, token, directory});
  result.comparison = {baseline: comparison.baseline, recordedStatuses: comparison.actions.map(entry => ({actionId: entry.actionId, status: entry.status})),
    producerCosts: comparison.costs, confirmation, reuseAuthorized: false};
  result.acquisition = acquisition;
  result.consumerVerificationMilliseconds = Math.round(performance.now() - started);
  result.acceptanceInputs = {certificateDigest, observations: comparisonObservations};
  return result;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.env.GITHUB_ACTIONS, 'true');
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  assert.equal(revision, process.env.GITHUB_SHA);
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const repository = process.env.GITHUB_REPOSITORY, token = process.env.ACTIONS_READ_TOKEN;
  const request = actionsReader({repository, token});
  const runId = Number(process.env.GITHUB_RUN_ID), runAttempt = Number(process.env.GITHUB_RUN_ATTEMPT);
  const run = await request(`/actions/runs/${runId}`);
  assert.equal(run.run_attempt, runAttempt); assert.equal(run.repository?.id, event.repository?.id);
  const context = {repository, repositoryId: event.repository.id, candidateRevision: revision,
    workflowId: run.workflow_id, runId, runAttempt, runHeadRevision: run.head_sha,
    headRepositoryId: event.pull_request?.head?.repo?.id ?? event.repository.id, ancestors: []};
  const artifactId = Number(process.env.SESSION_ARTIFACT_ID), directory = join(root, '.artifacts/session-consumer');
  await mkdir(directory, {recursive: true});
  const transferStarted = performance.now();
  const archive = await downloadArtifact({repository, artifactId, token, directory});
  const archiveTransferMilliseconds = Math.round(performance.now() - transferStarted);
  const checked = await verifyCurrentFamily({root, artifactId, expectedDigest: process.env.SESSION_ARTIFACT_DIGEST,
    context, request, archive, token, directory});
  const jobs = await request(`/actions/runs/${runId}/attempts/${runAttempt}/jobs?per_page=100`);
  assert(Array.isArray(jobs.jobs) && jobs.total_count === jobs.jobs.length);
  const owners = jobs.jobs.filter(job => job.name === 'check' && job.status === 'in_progress');
  assert.equal(owners.length, 1); const owner = owners[0];
  assert.equal(owner.run_id, runId); assert.equal(owner.run_attempt, runAttempt); assert.equal(owner.head_sha, run.head_sha);
  const {acceptanceInputs, ...result} = checked;
  result.archiveTransferMilliseconds = archiveTransferMilliseconds;
  const report = sealAcceptance({result, observations: acceptanceInputs.observations, event: run.event, branch: run.head_branch,
    owner: {runId, runAttempt, jobId: owner.id},
    sourceArtifact: {id: artifactId, digest: process.env.SESSION_ARTIFACT_DIGEST.replace(/^sha256:/u, '')},
    certificateDigest: acceptanceInputs.certificateDigest});
  const acceptanceDirectory = join(root, '.artifacts/session-applicability');
  await mkdir(acceptanceDirectory, {recursive: true});
  writeFileSync(join(acceptanceDirectory, 'verified-family.json'), `${encode(report)}\n`, {flag: 'wx'});
  console.log(`PASS bounded-session: ${checked.applications.length} obligations, ` +
    `${checked.applications.filter(entry => entry.acquisition === 'fresh').length} fresh, ` +
    `${checked.applications.filter(entry => entry.acquisition === 'reused').length} reused; exact run/attempt and executed Lean certificate`);
  console.log(`Main comparison: ${checked.comparison.confirmation.status}; ${report.ready.length} accepted reusable action observations`);
}
