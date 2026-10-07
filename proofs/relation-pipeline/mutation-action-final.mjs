// Required current-run consumer. Historical comparison availability never enters
// this path; it verifies the exact current producer's original and certificate.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {mkdir} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {encode} from '../bounded-session/action-inputs.mjs';
import {gitTree} from '../ci-evidence/inputs.mjs';
import {downloadArtifact} from '../ci-evidence/transport.mjs';
import {actionsReader} from '../../scripts/ci-main-base.mjs';
import {readMutationActionOriginal} from './mutation-action-archive.mjs';
import {decision} from './exploration-impact.mjs';

export async function verifyCurrentMutationActions({root, context, artifactId, expectedDigest, archive, request,
  expectedDecision = decision(root), tree = gitTree(root, context.candidateRevision)}) {
  assert(typeof expectedDigest === 'string' && /^(?:sha256:)?[a-f0-9]{64}$/u.test(expectedDigest), 'Missing producer artifact digest');
  assert(Number.isSafeInteger(artifactId) && artifactId > 0, 'Missing producer artifact ID');
  assert.equal(expectedDecision.revision, context.candidateRevision, 'Independent policy has another checkout');
  const metadata = await request(`/actions/artifacts/${artifactId}`);
  assert.equal(metadata.id, artifactId);
  assert.equal(metadata.digest, `sha256:${expectedDigest.replace(/^sha256:/u, '')}`, 'Producer/API archive digest differs');
  const result = await readMutationActionOriginal({archive, artifactId, expected: context, expectedDecision, tree,
    request, acquisition: 'fresh'});
  assert.equal(result.archiveDigest, metadata.digest, 'Artifact changed during consumer verification');
  const admission = result.original.admission;
  assert(admission.actions.every(entry => !entry.application.reused && !entry.application.closed &&
    !entry.application.mainOrigin), 'Unreviewed current pipeline acquisition');
  return {version: 'actql-pipeline-current-action-acceptance/0.1', context,
    sourceArtifact: {id: artifactId, digest: result.archiveDigest}, originalDigest: result.originalDigest,
    authority: result.authority, freshActions: admission.actions.length,
    required: admission.actions.map(entry => entry.required),
    applications: admission.actions.map(entry => entry.application), certificate: admission.certificate,
    scientificObservations: admission.actions.map(entry => ({action: entry.action.id, digest: entry.scientificDigest})),
    unresolved: result.unresolved, verificationMilliseconds: result.verificationMilliseconds, reuseAuthorized: false};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Required consumer publication is Actions-only');
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  assert.equal(revision, process.env.GITHUB_SHA);
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH));
  const repository = process.env.GITHUB_REPOSITORY, token = process.env.ACTIONS_READ_TOKEN;
  const request = actionsReader({repository, token});
  const runId = Number(process.env.GITHUB_RUN_ID), runAttempt = Number(process.env.GITHUB_RUN_ATTEMPT);
  const run = await request(`/actions/runs/${runId}`);
  assert.equal(run.id, runId); assert.equal(run.run_attempt, runAttempt);
  assert.equal(run.repository?.id, event.repository.id); assert.equal(run.event, process.env.GITHUB_EVENT_NAME);
  const context = {repository, repositoryId: event.repository.id, candidateRevision: revision,
    workflowId: run.workflow_id, runId, runAttempt, runHeadRevision: run.head_sha,
    headRepositoryId: event.pull_request?.head?.repo?.id ?? event.repository.id};
  const artifactId = Number(process.env.PIPELINE_ACTION_ARTIFACT_ID);
  const directory = join(root, '.artifacts/pipeline-action-consumer');
  await mkdir(directory, {recursive: true});
  const started = performance.now();
  const archive = await downloadArtifact({repository, artifactId, token, directory});
  const transferMilliseconds = Math.round(performance.now() - started);
  const result = await verifyCurrentMutationActions({root, context, artifactId, archive, request,
    expectedDigest: process.env.PIPELINE_ACTION_ARTIFACT_DIGEST});
  writeFileSync(join(directory, 'verified-actions.json'), `${encode({...result, transferMilliseconds})}\n`, {flag: 'wx'});
  console.log(`PASS pipeline mutations: ${result.freshActions} independent fresh obligations; ` +
    'original bytes, current run/attempt and executed Lean certificate verified; reuse unauthorized');
}
