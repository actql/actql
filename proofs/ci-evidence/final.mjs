// Consume the current family's immutable ZIP in the final required check.
// The family ran the actual Lean checker; here authenticate that successful
// job and reconstruct its exact submitted Lean input/certificate binding.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {mkdir} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
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

export function checkCertificate({certificate, output, context, catalog, required, applications, receiptDigests}) {
  assert.equal(certificate.version, 'actql-verification-family-certificate/0.1');
  assert.equal(certificate.mode, 'comparison');
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
  // Independently validate the API metadata again for each receipt below. This
  // first open only reads data needed to reconstruct the current obligation.
  const metadata = await request(`/actions/artifacts/${artifactId}`);
  assert.equal(metadata.id, artifactId); assert.equal(metadata.expired, false);
  assert(typeof expectedDigest === 'string' && /^(?:sha256:)?[a-f0-9]{64}$/u.test(expectedDigest));
  assert.equal(metadata.digest, `sha256:${expectedDigest.replace(/^sha256:/u, '')}`, 'Job output/API archive digest mismatch');
  const zip = await openArtifactZip(archive, {expectedSha256: metadata.digest,
    limits: {maxCompressedBytes: 64 * 1024 * 1024, maxTotalBytes: 256 * 1024 * 1024, maxEntries: 2000}});
  let state, certificate, output, distributionInputs, comparison, comparisonObservations, receipts;
  try {
    distributionInputs = await zip.json('runtime-distributions.json');
    state = await zip.json('context.json'); certificate = await zip.json('checked.json'); output = await zip.read('lean-output.log');
    const planBytes = await zip.read('comparison-plan.json'), observationsBytes = await zip.read('comparison-observations.json');
    assert.equal(certificate.comparisonDigest, hash(planBytes), 'Changed comparison plan');
    assert.equal(certificate.comparisonObservationsDigest, hash(observationsBytes), 'Changed fresh comparison observations');
    comparison = JSON.parse(planBytes); comparisonObservations = JSON.parse(observationsBytes);
    const catalog = readCatalog(join(root, 'proofs/ci-evidence/bounded-session-actions.json'));
    receipts = await Promise.all(catalog.actions.map(async action => parseReceipt(await zip.read(`receipts/${action.id}.json`))));
  } finally { await zip.close(); }
  assert.equal(encode(state.context), encode(context), 'Wrong collection candidate/run/attempt');
  checkRuntimeObservation(state.runtime, distributionInputs);
  assert(state.runtime.unresolved.includes('comparison only: distribution/core, loader, runtime configuration and external dependencies require reviewed closure'),
    'Comparison cannot silently claim a closed runtime');
  const catalog = readCatalog(join(root, 'proofs/ci-evidence/bounded-session-actions.json'));
  const entries = catalog.actions.map(action => ({actionId: action.id, acquisition: 'fresh', archive, artifactId}));
  const result = await checkApplications({root, context, runtime: state.runtime,
    // Independent published inventory for bootstrap, not the candidate's own
    // edited inventory. Activation will use the verified main checkpoint.
    protectedRevision: initialRegistrationRevision, entries, request,
    prove: (required, applications, {receiptDigests}) =>
      checkCertificate({certificate, output, context, catalog, required, applications, receiptDigests})});
  // Compare actual parsed immutable receipt digests with the certificate,
  // rather than checking a certificate's hashes against itself.
  assert.deepEqual(result.applications.map(entry => ({actionId: entry.actionId, digest: entry.originReceiptDigest})), certificate.receiptDigests);
  assert(result.applications.every(entry => entry.acquisition === 'fresh'));
  assert.equal(encode(comparisonObservations), encode(compareFreshObservations({plan: comparison, context,
    runtime: state.runtime, tree: gitTree(root, context.candidateRevision), receipts})), 'Wrong comparison of actual fresh executions');
  const confirmation = await verifyComparison({plan: comparison, root, context, runtime: state.runtime, request, token, directory});
  result.comparison = {baseline: comparison.baseline, recordedStatuses: comparison.actions.map(entry => ({actionId: entry.actionId, status: entry.status})),
    producerCosts: comparison.costs, confirmation, reuseAuthorized: false};
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
  const archive = await downloadArtifact({repository, artifactId, token, directory});
  const checked = await verifyCurrentFamily({root, artifactId, expectedDigest: process.env.SESSION_ARTIFACT_DIGEST,
    context, request, archive, token, directory});
  console.log(`PASS bounded-session: ${checked.applications.length} current fresh actions, exact run/attempt and executed Lean certificate`);
  console.log(`Main comparison: ${checked.comparison.confirmation.status}; reuse is not authorized`);
}
