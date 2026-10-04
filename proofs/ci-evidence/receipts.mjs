import assert from 'node:assert/strict';
import {mutationObservation} from './mutation-observation.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {parseTestExecution} from '../../scripts/test-execution.mjs';
import {openArtifactZip} from '../../scripts/ci-artifact-reader.mjs';
import {compareInputs, hash, inputVersion} from './inputs.mjs';
import {validateCatalog, version as catalogVersion} from './actions.mjs';
import {ArtifactUnavailable} from './transport.mjs';
import {mutationIds} from './mutation-inventory.mjs';
export {mutationIds} from './mutation-inventory.mjs';
import {isolatedProfile} from './isolated-runtime.mjs';

export const receiptVersion = 'actql-verification-action-receipt/0.1';
const positive = value => Number.isSafeInteger(value) && value > 0;
const sha = value => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const exact = (value, fields) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort(), 'Missing/extra receipt field');
const artifactPath = path => typeof path === 'string' && /^[a-zA-Z0-9_.\/-]+$/u.test(path) &&
  !path.startsWith('/') && !path.split('/').some(part => ['', '.', '..'].includes(part));

export function canonicalReceipt(receipt) {
  validateReceipt(receipt);
  return Buffer.from(`${encode(receipt)}\n`);
}

export function parseReceipt(bytes) {
  const receipt = JSON.parse(bytes.toString('utf8'));
  assert(Buffer.from(`${encode(receipt)}\n`).equals(bytes), 'Noncanonical/ambiguous receipt bytes');
  return validateReceipt(receipt);
}

export function validateReceipt(receipt) {
  exact(receipt, ['version', 'origin', 'action', 'inputs', 'execution', 'artifacts']);
  assert.equal(receipt.version, receiptVersion);
  // A receipt descriptor is validated independently of its own count labels.
  validateCatalog({version: catalogVersion, family: 'bounded-session',
    actions: [{...receipt.action, dependencies: []}]});
  const origin = receipt.origin;
  exact(origin, ['repository', 'repositoryId', 'testedRevision', 'runHeadRevision', 'workflowId',
    'workflowPath', 'runId', 'runAttempt', 'jobId', 'event', 'branch']);
  assert(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(origin.repository));
  assert(['repositoryId', 'workflowId', 'runId', 'runAttempt', 'jobId'].every(key => positive(origin[key])));
  assert(sha(origin.testedRevision) && sha(origin.runHeadRevision));
  assert.equal(origin.workflowPath, '.github/workflows/ci.yml');
  assert(['push', 'pull_request'].includes(origin.event));
  assert(typeof origin.branch === 'string' && origin.branch.length > 0);
  assert.equal(receipt.inputs.version, inputVersion);
  assert.equal(receipt.inputs.revision, origin.testedRevision);
  assert.equal(encode(receipt.inputs.inputs.action), encode(receipt.action));
  // Verify the complete canonical identity rather than accepting a carried key.
  compareInputs(receipt.inputs, receipt.inputs);
  const execution = receipt.execution;
  exact(execution, ['command', 'target', 'exit', 'passed', 'units', 'milliseconds', 'observationDigest']);
  assert.equal(encode(execution.command), encode(receipt.action.command));
  assert.equal(execution.target, receipt.action.target);
  assert.equal(execution.exit, 0); assert.equal(execution.passed, true);
  assert(positive(execution.units) && execution.units >= receipt.action.minimumUnits, 'Zero/incomplete action');
  assert(Number.isSafeInteger(execution.milliseconds) && execution.milliseconds >= 0);
  assert(digest(execution.observationDigest));
  assert(Array.isArray(receipt.artifacts) && receipt.artifacts.length > 0);
  assert(new Set(receipt.artifacts.map(entry => entry.path)).size === receipt.artifacts.length, 'Duplicate receipt artifact');
  for (const entry of receipt.artifacts) {
    exact(entry, ['path', 'bytes', 'digest']);
    assert(artifactPath(entry.path) && Number.isSafeInteger(entry.bytes) && entry.bytes >= 0 && digest(entry.digest));
  }
  const observation = receipt.artifacts.find(entry => entry.path === `observations/${receipt.action.id}.log`);
  assert(observation && observation.digest === execution.observationDigest, 'Missing bound execution observation');
  if (receipt.inputs.inputs.runtime.profile === isolatedProfile) {
    assert.equal(receipt.action.id, 'mutations-js', 'Isolated profile applied to another action');
    assert(['isolated-inputs.json', 'isolated-observation.json', 'isolated-execution.json'].every(path =>
      receipt.artifacts.some(entry => entry.path === path)), 'Missing bound isolated correspondence');
  }
  return receipt;
}

// Observation interpretation is independent of caller-provided count/target
// labels. The CI runner supplies its actual subprocess status and bytes.
export function observationUnits(action, output, status) {
  assert.equal(status, 0, 'Failed/terminated execution cannot be sealed');
  if (action.command[0] === 'moon') {
    const result = parseTestExecution('moon', output);
    assert(result.success && result.counts.failed === 0 && result.counts.tests === result.counts.passed);
    assert(result.counts.passed >= action.minimumUnits, 'Zero/incomplete executed action');
    return result.counts.passed;
  }
  if (action.id === 'model') {
    const match = /^Checked (\d+) theorems, expected claim types and axiom dependencies$/mu.exec(output);
    assert(match && Number(match[1]) === action.minimumUnits, 'Missing typed theorem/axiom result');
    assert(!/sorryAx/u.test(output));
    return Number(match[1]);
  }
  if (action.id === 'mutations-js') {
    const detected = [...output.matchAll(/^([a-z0-9-]+): detected by replacement tests$/gmu)].map(match => match[1]);
    assert.deepEqual([...detected].sort(), [...mutationIds].sort(), 'Changed/missing mutation identities');
    assert(new Set(detected).size === action.minimumUnits && detected.length === action.minimumUnits,
      'Missing/duplicate mutation observations');
    return detected.length;
  }
  throw new Error('Unreviewed action observation');
}



export function sealReceipt({origin, action, inputs, output, status, milliseconds, artifacts = []}) {
  const observation = Buffer.from(output);
  return validateReceipt({version: receiptVersion, origin, action, inputs,
    execution: {command: action.command, target: action.target, exit: status, passed: true,
      units: observationUnits(action, output, status), milliseconds, observationDigest: hash(observation)},
    artifacts: [{path: `observations/${action.id}.log`, bytes: observation.length, digest: hash(observation)}, ...artifacts]});
}

// API responses are obtained by the caller's read-only Actions client, never
// copied from the receipt itself. The same attempt must own both job and ZIP.
export async function authenticateOrigin({receipt, artifactId, expected, request, acquisition}) {
  validateReceipt(receipt);
  assert(positive(artifactId) && ['fresh', 'reused'].includes(acquisition));
  const origin = receipt.origin;
  assert.equal(origin.repository, expected.repository);
  assert.equal(origin.repositoryId, expected.repositoryId);
  assert.equal(origin.workflowId, expected.workflowId);
  const run = await request(`/actions/runs/${origin.runId}`);
  assert.equal(run.id, origin.runId); assert.equal(run.run_attempt, origin.runAttempt);
  assert.equal(run.workflow_id, origin.workflowId); assert.equal(run.path, origin.workflowPath);
  assert.equal(run.repository?.id, origin.repositoryId); assert.equal(run.repository?.full_name, origin.repository);
  const headRepositoryId = acquisition === 'reused' ? origin.repositoryId : expected.headRepositoryId ?? origin.repositoryId;
  assert.equal(run.head_repository?.id, headRepositoryId);
  assert.equal(run.head_sha, origin.runHeadRevision); assert.equal(run.event, origin.event);
  assert.equal(run.head_branch, origin.branch);
  if (acquisition === 'reused') {
    assert.equal(origin.event, 'push'); assert.equal(origin.branch, 'main');
    assert.equal(origin.testedRevision, origin.runHeadRevision);
    assert.equal(run.status, 'completed'); assert.equal(run.conclusion, 'success');
    assert(expected.ancestors?.includes(origin.testedRevision), 'Origin is not a trusted ancestor');
  } else {
    assert.equal(origin.testedRevision, expected.candidateRevision);
    assert.equal(origin.runHeadRevision, expected.runHeadRevision);
    assert.equal(origin.runId, expected.runId); assert.equal(origin.runAttempt, expected.runAttempt);
    assert(run.status === 'in_progress' || run.status === 'completed' && run.conclusion === 'success');
  }
  const data = await request(`/actions/runs/${origin.runId}/attempts/${origin.runAttempt}/jobs?per_page=100`);
  assert(Array.isArray(data.jobs) && data.total_count === data.jobs.length && data.jobs.length <= 100, 'Incomplete attempt jobs');
  const jobs = data.jobs.filter(job => job.id === origin.jobId);
  assert.equal(jobs.length, 1);
  const job = jobs[0];
  assert.equal(job.name, 'session-evidence');
  assert.equal(job.run_id, origin.runId); assert.equal(job.run_attempt, origin.runAttempt);
  assert.equal(job.head_sha, origin.runHeadRevision);
  assert.equal(job.status, 'completed'); assert.equal(job.conclusion, 'success');
  const artifact = await request(`/actions/artifacts/${artifactId}`);
  assert.equal(artifact.id, artifactId); assert(typeof artifact.expired === 'boolean');
  assert.equal(artifact.workflow_run?.id, origin.runId);
  assert.equal(artifact.workflow_run?.head_sha, origin.runHeadRevision);
  assert.equal(artifact.workflow_run?.repository_id, origin.repositoryId);
  assert.equal(artifact.workflow_run?.head_repository_id, headRepositoryId);
  assert.equal(artifact.name, `session-actions-${origin.runId}-${origin.runAttempt}-${origin.testedRevision}`);
  assert(/^sha256:[a-f0-9]{64}$/u.test(artifact.digest ?? ''), 'Missing authenticated archive digest');
  assert(positive(artifact.size_in_bytes));
  assert(Number.isFinite(Date.parse(artifact.expires_at)), 'Invalid archive expiry');
  if (artifact.expired || Date.parse(artifact.expires_at) <= Date.now()) throw new ArtifactUnavailable();
  // Re-read after inspection: a rerun must not change the attempt underneath us.
  const current = await request(`/actions/runs/${origin.runId}`);
  assert.equal(current.run_attempt, origin.runAttempt);
  assert.equal(current.head_sha, run.head_sha);
  assert.equal(current.status, run.status); assert.equal(current.conclusion, run.conclusion);
  return artifact;
}

export async function readOriginReceipts({archive, artifactId, actions, expected, request, acquisition}) {
  assert(Array.isArray(actions) && actions.length > 0 && actions.length <= 256, 'Empty/unbounded receipt group');
  assert(new Set(actions.map(action => action.id)).size === actions.length, 'Duplicate requested action');
  // First read permits no execution/extraction. Authenticate its carried IDs,
  // then reopen against the API's ZIP digest before accepting any bytes.
  let zip = await openArtifactZip(archive, {limits: {maxCompressedBytes: 64 * 1024 * 1024, maxTotalBytes: 256 * 1024 * 1024, maxEntries: 2000}});
  const receipts = new Map();
  try {
    for (const action of actions) {
      const receipt = parseReceipt(await zip.read(`receipts/${action.id}.json`));
      assert.equal(encode(receipt.action), encode(action), 'Origin target/scope/premises/command mismatch');
      receipts.set(action.id, receipt);
    }
  }
  finally { await zip.close(); }
  const receipt = receipts.get(actions[0].id);
  // Only receipts owned by the same actual run/attempt/job/archive share API
  // authentication. Similar scope, bytes or repository names are insufficient.
  for (const original of receipts.values()) assert.equal(encode(original.origin), encode(receipt.origin), 'Mixed receipt archive owners');
  const artifact = await authenticateOrigin({receipt, artifactId, expected, request, acquisition});
  zip = await openArtifactZip(archive, {expectedSha256: artifact.digest,
    limits: {maxCompressedBytes: 64 * 1024 * 1024, maxTotalBytes: 256 * 1024 * 1024, maxEntries: 2000}});
  try {
    const checked = new Map(), digests = new Map();
    for (const action of actions) {
      const receipt = receipts.get(action.id), bytes = await zip.read(`receipts/${action.id}.json`);
      assert.equal(encode(parseReceipt(bytes)), encode(receipt), 'Receipt changed during authentication');
      for (const entry of receipt.artifacts) {
        const member = zip.entries.find(value => value.path === entry.path);
        assert(member && member.bytes === entry.bytes, 'Missing/wrong artifact size');
        if (!digests.has(entry.path)) digests.set(entry.path, await zip.digest(entry.path));
        assert.equal(digests.get(entry.path), entry.digest, 'Original artifact digest mismatch');
      }
      const observation = await zip.read(`observations/${action.id}.log`);
      assert.equal(observationUnits(action, observation.toString('utf8'), receipt.execution.exit), receipt.execution.units);
      let scientificDigest = null;
      if (action.id === 'mutations-js') {
        const path = 'results/mutations-js.json';
        assert(receipt.artifacts.some(entry => entry.path === path), 'Missing mutation result artifact');
        const result = await zip.json(path);
        assert.deepEqual(result.results?.map(entry => entry.id).sort(), [...mutationIds].sort());
        assert(result.results.every(entry => entry.killed === true && positive(entry.failureCount) && entry.target === 'js'));
        assert.equal(result.sourceRestored, true, 'Unconfirmed mutation source restoration');
        assert.equal(result.revision, receipt.origin.testedRevision, 'Wrong mutation source revision');
        scientificDigest = mutationObservation(result).digest;
      }
      checked.set(action.id, {receipt, receiptDigest: hash(bytes), artifactId, archiveDigest: zip.sha256, scientificDigest});
    }
    // A rerun or head transition during the bounded ZIP inspection invalidates
    // the entire group. The before/after check surrounds all member validation.
    const current = await request(`/actions/runs/${receipt.origin.runId}`);
    assert.equal(current.id, receipt.origin.runId); assert.equal(current.run_attempt, receipt.origin.runAttempt);
    assert.equal(current.head_sha, receipt.origin.runHeadRevision);
    assert.equal(current.workflow_id, receipt.origin.workflowId);
    assert.equal(current.repository?.id, receipt.origin.repositoryId);
    assert.equal(current.repository?.full_name, receipt.origin.repository);
    assert.equal(current.head_repository?.id, acquisition === 'reused' ? receipt.origin.repositoryId : expected.headRepositoryId ?? receipt.origin.repositoryId);
    assert.equal(current.path, receipt.origin.workflowPath); assert.equal(current.event, receipt.origin.event);
    assert.equal(current.head_branch, receipt.origin.branch);
    if (acquisition === 'reused') assert(current.status === 'completed' && current.conclusion === 'success');
    else assert(current.status === 'in_progress' || current.status === 'completed' && current.conclusion === 'success');
    return checked;
  } finally { await zip.close(); }
}

export async function readOriginReceipt({action, ...options}) {
  return (await readOriginReceipts({...options, actions: [action]})).get(action.id);
}
