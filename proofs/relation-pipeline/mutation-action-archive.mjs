// Immutable fresh pipeline originals. Transport authentication is not permission
// to reuse: runtime closure, full-main qualification and shadow comparison remain.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {encode} from '../bounded-session/action-inputs.mjs';
import {gitTree, hash} from '../ci-evidence/inputs.mjs';
import {authenticateExecutionOrigin} from '../ci-evidence/receipts.mjs';
import {leanInput} from '../ci-evidence/check.mjs';
import {openArtifactZip} from '../../scripts/ci-artifact-reader.mjs';
import {inspectMutationPart, mutationReportPath} from './mutation-parts.mjs';
import {mutationNamesByPart, mutationPartIds} from './proof-parts.mjs';
import {mutationSourceInputs, mutationActionRecords} from './mutation-actions.mjs';
import {createAudit} from './audit.mjs';

export const originalPath = 'pipeline-ci/action-original.json';
const version = 'actql-pipeline-action-original/0.1';
const prefix = '.artifacts/relation-pipeline/';
const member = path => {
  assert(path.startsWith(prefix), 'Foreign original receipt path');
  const relative = path.slice('.artifacts/'.length);
  assert(/^[A-Za-z0-9_.+-]+(?:\/[A-Za-z0-9_.+-]+)*$/u.test(relative) &&
    !relative.split('/').some(part => ['.', '..'].includes(part)), 'Unsafe original member');
  return relative;
};
const exact = (value, keys) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...keys].sort(), 'Unknown/missing original field');

function validateOriginalOwner(origin) {
  exact(origin, ['repository', 'repositoryId', 'testedRevision', 'runHeadRevision', 'workflowPath',
    'runId', 'runAttempt', 'event', 'branch']);
  assert(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(origin.repository));
  assert(['repositoryId', 'runId', 'runAttempt'].every(key => Number.isSafeInteger(origin[key]) && origin[key] > 0));
  assert(['testedRevision', 'runHeadRevision'].every(key => /^[a-f0-9]{40}$/u.test(origin[key])));
  assert.equal(origin.workflowPath, '.github/workflows/ci.yml');
  assert(['push', 'pull_request', 'workflow_dispatch', 'schedule'].includes(origin.event));
  if (origin.event === 'schedule') assert.equal(origin.branch, 'main', 'Scheduled evidence requires main');
  assert(typeof origin.branch === 'string' && origin.branch.length > 0);
}

export function sealMutationActionOriginal({origin, source, decision, admission}) {
  validateOriginalOwner(origin);
  assert.equal(origin.testedRevision, decision.revision, 'Original source owner differs');
  assert.equal(admission.revision, decision.revision, 'Original admission owner differs');
  assert.equal(admission.reuseAuthorized, false, 'Unreviewed pipeline reuse');
  verifyMutationActionCertificate(admission);
  return {version, origin, source, decision, admission};
}

export function verifyMutationActionCertificate(admission) {
  const {certificate, leanOutput, actions} = admission;
  exact(certificate, ['accepted', 'inputDigest', 'outputDigest', 'theoremCount', 'toolchain']);
  assert.equal(certificate.accepted, true);
  assert.equal(certificate.theoremCount, 5);
  assert.equal(certificate.toolchain, readFileSync(new URL('../bounded-session/lean-toolchain', import.meta.url), 'utf8').trim());
  assert.equal(typeof leanOutput, 'string');
  assert.equal(certificate.inputDigest, hash(leanInput(actions.map(entry => entry.required), actions.map(entry => entry.application))),
    'Original checker input differs');
  assert.equal(certificate.outputDigest, hash(leanOutput), 'Original checker output differs');
}

// The expected decision and tree come from the caller's independent source/policy
// resolution, not the archive's carried required list. Only authenticated successful
// producer execution establishes the full scientific audit preceding this record.
export async function readMutationActionOriginal({archive, artifactId, expected, expectedDecision, tree, request,
  acquisition = 'fresh'}) {
  const started = performance.now();
  let zip = await openArtifactZip(archive);
  let carried;
  try {
    const entry = zip.entries.find(entry => entry.path === originalPath && !entry.directory);
    assert(entry && entry.bytes <= 8 * 1024 * 1024, 'Missing/oversized pipeline action original');
    const bytes = await zip.read(originalPath);
    assert(bytes.length <= 8 * 1024 * 1024, 'Oversized pipeline action original');
    carried = JSON.parse(bytes);
    assert(bytes.equals(Buffer.from(`${encode(carried)}\n`)), 'Noncanonical original record');
    exact(carried, ['version', 'origin', 'source', 'decision', 'admission']);
    assert.equal(carried.version, version);
    validateOriginalOwner(carried.origin);
  } finally { await zip.close(); }
  // Resolve the successful owner from API facts rather than making an API call
  // during fresh publication. Optional comparison availability must not block it.
  const jobs = await request(`/actions/runs/${carried.origin.runId}/attempts/${carried.origin.runAttempt}/jobs?per_page=100`);
  assert(Array.isArray(jobs.jobs) && jobs.total_count === jobs.jobs.length && jobs.jobs.length <= 100, 'Incomplete pipeline jobs');
  const owners = jobs.jobs.filter(job => job.name === 'pipeline-evidence');
  assert.equal(owners.length, 1, 'Ambiguous pipeline original owner');
  const origin = {...carried.origin, workflowId: expected.workflowId, jobId: owners[0].id};
  const metadata = await authenticateExecutionOrigin({origin, family: 'pipeline',
    artifactId, expected, request, acquisition});
  zip = await openArtifactZip(archive, {expectedSha256: metadata.digest});
  try {
    assert.equal(zip.compressedBytes, metadata.size_in_bytes, 'Original archive size differs');
    const originalBytes = await zip.read(originalPath);
    assert(originalBytes.equals(Buffer.from(`${encode(carried)}\n`)), 'Original record changed between reads');
    assert.deepEqual(carried.decision, expectedDecision, 'Original independent exploration decision differs');
    assert.equal(carried.origin.testedRevision, expectedDecision.revision, 'Original decision owner differs');
    const sourceInputs = mutationSourceInputs({tree, source: carried.source});
    const reports = [], auditedReceipts = new Map();
    for (const part of Object.keys(mutationNamesByPart)) {
      for (const mode of expectedDecision.required ? ['fixed', 'explore'] : ['fixed']) {
        const path = mutationReportPath(part, mode), bytes = await zip.read(member(path));
        const report = JSON.parse(bytes);
        assert(bytes.equals(Buffer.from(`${JSON.stringify(report, null, 2)}\n`)), 'Noncanonical original report');
        reports.push({path, bytesDigest: hash(bytes), report});
        for (const ref of inspectMutationPart(report, {source: carried.source, decision: expectedDecision})) {
          assert(!auditedReceipts.has(ref.path), 'Original receipt shared across reports');
          const receiptBytes = await zip.read(member(ref.path));
          assert.deepEqual(JSON.parse(receiptBytes), ref.receipt, 'Original raw receipt differs from report');
          auditedReceipts.set(ref.path, {receiptDigest: hash(JSON.stringify(ref.receipt)), bytesDigest: hash(receiptBytes)});
        }
      }
    }
    const records = mutationActionRecords({reports, source: carried.source, decision: expectedDecision, sourceInputs, auditedReceipts});
    const {sourceInputs: recordedInputs, certificate, leanOutput, admissionMilliseconds, ...recorded} = carried.admission;
    assert(Number.isSafeInteger(admissionMilliseconds) && admissionMilliseconds >= 0, 'Invalid admission cost');
    assert.deepEqual(recordedInputs, sourceInputs, 'Original input inventory differs');
    assert.deepEqual(recorded, records, 'Original action plan or scientific observations differ');
    verifyMutationActionCertificate(carried.admission);
    // Surround all ZIP/member/certificate processing with the actual attempt,
    // not only the earlier metadata fetch. A concurrent rerun invalidates it.
    const current = await request(`/actions/runs/${origin.runId}`);
    assert.equal(current.id, origin.runId); assert.equal(current.run_attempt, origin.runAttempt);
    assert.equal(current.head_sha, origin.runHeadRevision); assert.equal(current.workflow_id, origin.workflowId);
    assert.equal(current.path, origin.workflowPath); assert.equal(current.repository?.id, origin.repositoryId);
    assert.equal(current.repository?.full_name, origin.repository);
    assert.equal(current.head_repository?.id, acquisition === 'reused' ? origin.repositoryId : expected.headRepositoryId ?? origin.repositoryId);
    assert.equal(current.event, origin.event); assert.equal(current.head_branch, origin.branch);
    assert(acquisition === 'fresh' && current.status === 'in_progress' ||
      current.status === 'completed' && current.conclusion === 'success', 'Original run no longer successful/current');
    return {original: carried, originalDigest: hash(originalBytes), artifactId, archiveDigest: metadata.digest,
      authority: 'authenticated-successful-pipeline-job', acquisition: 'original-not-reused', reuseAuthorized: false,
      unresolved: sourceInputs.unresolved, verificationMilliseconds: Math.round(performance.now() - started)};
  } finally { await zip.close(); }
}

// Local diagnostics call the pure functions above. This publication command uses
// the actual Actions run/job identity; it is never enabled by a local override.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Original publication is Actions-only');
  assert.equal(process.argv[2], 'seal', 'Usage: mutation-action-archive.mjs seal');
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  assert.equal(revision, process.env.GITHUB_SHA);
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH));
  const repository = process.env.GITHUB_REPOSITORY;
  const runId = Number(process.env.GITHUB_RUN_ID), runAttempt = Number(process.env.GITHUB_RUN_ATTEMPT);
  const admission = createAudit(root)();
  const report = JSON.parse(readFileSync(join(root, `.artifacts/relation-pipeline/fixed-mutations-${mutationPartIds[0]}.json`)));
  const origin = {repository, repositoryId: event.repository.id, testedRevision: revision,
    runHeadRevision: event.pull_request?.head?.sha ?? revision, workflowPath: '.github/workflows/ci.yml', runId, runAttempt,
    event: process.env.GITHUB_EVENT_NAME, branch: event.pull_request?.head?.ref ?? process.env.GITHUB_REF_NAME};
  const original = sealMutationActionOriginal({origin, source: report.source, decision: report.decision, admission});
  // Owned, derived output only. Never overwrite an original or passing log.
  writeFileSync(join(root, '.artifacts', originalPath), `${encode(original)}\n`, {flag: 'wx', mode: 0o600});
}
