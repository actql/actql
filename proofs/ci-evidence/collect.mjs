// Initial comparison collection consumes existing executions, without another
// proof/test campaign. Receipts are not reusable until the Actions job/run is
// independently authenticated as successful by the artifact consumer.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdirSync, readFileSync, writeFileSync, existsSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {actionsReader} from '../../scripts/ci-main-base.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {snapshot} from '../bounded-session/evidence.mjs';
import {readCatalog, catalogPath, initialRegistrationRevision, compareCatalogs} from './actions.mjs';
import {actionInputs, gitTree, hash} from './inputs.mjs';
import {canonicalReceipt, parseReceipt, sealReceipt} from './receipts.mjs';
import {leanRecords} from './applications.mjs';
import {checkPlan} from './check.mjs';
import {observeRuntime} from './runtime.mjs';
import {comparisonPlan, compareFreshObservations} from './plan.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const directory = join(root, '.artifacts/session-actions');
const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024}).trim();
const json = path => JSON.parse(readFileSync(path, 'utf8'));
const write = (path, value) => writeFileSync(path, `${encode(value)}\n`, {flag: 'wx'});
let tree;

export async function initialize() {
  assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Collection requires the actual Actions context');
  const event = json(process.env.GITHUB_EVENT_PATH);
  const repository = process.env.GITHUB_REPOSITORY, revision = git(['rev-parse', 'HEAD']);
  assert.equal(revision, process.env.GITHUB_SHA, 'Wrong CI checkout');
  assert.equal(git(['status', '--porcelain', '--untracked-files=normal']), '', 'Dirty comparison checkout');
  const protectedCatalog = JSON.parse(gitTree(root, initialRegistrationRevision).read(catalogPath));
  assert.equal(compareCatalogs(protectedCatalog, readCatalog()).unchanged, true, 'Comparison requires the complete initial catalog');
  const request = actionsReader({repository, token: process.env.ACTIONS_READ_TOKEN});
  const runId = Number(process.env.GITHUB_RUN_ID), runAttempt = Number(process.env.GITHUB_RUN_ATTEMPT);
  const run = await request(`/actions/runs/${runId}`);
  assert.equal(run.run_attempt, runAttempt); assert.equal(run.path, '.github/workflows/ci.yml');
  const headRepositoryId = event.pull_request?.head?.repo?.id ?? event.repository?.id;
  assert.equal(run.repository?.id, event.repository?.id); assert.equal(run.head_repository?.id, headRepositoryId);
  const jobs = await request(`/actions/runs/${runId}/attempts/${runAttempt}/jobs?per_page=100`);
  assert.equal(jobs.total_count, jobs.jobs?.length, 'Incomplete current attempt');
  const current = jobs.jobs.filter(job => job.name === 'session-evidence' && job.status === 'in_progress');
  assert.equal(current.length, 1, 'Ambiguous live Session owner');
  const job = current[0];
  assert.equal(job.run_attempt, runAttempt); assert.equal(job.run_id, runId); assert.equal(job.head_sha, run.head_sha);
  const context = {repository, repositoryId: event.repository.id, candidateRevision: revision,
    workflowId: run.workflow_id, runId, runAttempt, runHeadRevision: run.head_sha, headRepositoryId, ancestors: []};
  const origin = {repository, repositoryId: context.repositoryId, testedRevision: revision, runHeadRevision: run.head_sha,
    workflowId: run.workflow_id, workflowPath: run.path, runId, runAttempt, jobId: job.id, event: run.event, branch: run.head_branch};
  // This first collection reports the open boundary honestly. It does not turn
  // the earlier report-only runtime inventory into a closure witness. Reviewed
  // runtime capture and comparison must precede the later activation commit.
  const {runtime, distributionInputs, measurement} = observeRuntime({root});
  assert(!existsSync(directory), 'Another collection already owns this directory');
  for (const path of ['receipts', 'observations', 'results']) mkdirSync(join(directory, path), {recursive: true});
  write(join(directory, 'context.json'), {context, origin, runtime});
  write(join(directory, 'runtime-distributions.json'), distributionInputs);
  write(join(directory, 'runtime-measurement.json'), measurement);
  const comparison = await comparisonPlan({root, context, runtime, directory,
    token: process.env.ACTIONS_READ_TOKEN, request});
  write(join(directory, 'comparison-plan.json'), comparison);
  console.log(`Comparison collection initialized for ${revision}; all actions still execute`);
}

export function recordExistingAction({id, command, output, status, milliseconds, result = null}) {
  if (process.env.ACTQL_SESSION_COLLECT !== 'true') return;
  const state = json(join(directory, 'context.json'));
  assert.equal(git(['rev-parse', 'HEAD']), state.context.candidateRevision);
  assert.equal(git(['diff', '--name-only', 'HEAD']), '', 'Unrestored tracked source');
  const action = readCatalog().actions.find(entry => entry.id === id);
  assert(action, `Unregistered execution: ${id}`);
  assert.equal(encode(action.command), encode(command), 'Executed command differs from registration');
  tree ??= gitTree(root, state.context.candidateRevision);
  const inputs = actionInputs({tree, revision: state.context.candidateRevision, action, runtime: state.runtime});
  const distributionPath = 'runtime-distributions.json';
  const distributionBytes = readFileSync(join(directory, distributionPath));
  const artifacts = [{path: distributionPath, bytes: distributionBytes.length, digest: hash(distributionBytes)}];
  const comparisonBytes = readFileSync(join(directory, 'comparison-plan.json'));
  artifacts.push({path: 'comparison-plan.json', bytes: comparisonBytes.length, digest: hash(comparisonBytes)});
  if (result !== null) {
    const path = `results/${id}.json`, bytes = Buffer.from(`${encode(result)}\n`);
    writeFileSync(join(directory, path), bytes, {flag: 'wx'});
    artifacts.push({path, bytes: bytes.length, digest: hash(bytes)});
  }
  const receipt = sealReceipt({origin: state.origin, action, inputs, output, status, milliseconds, artifacts});
  writeFileSync(join(directory, `observations/${id}.log`), output, {flag: 'wx'});
  writeFileSync(join(directory, `receipts/${id}.json`), canonicalReceipt(receipt), {flag: 'wx'});
}

async function mutations() {
  const before = snapshot(root), start = performance.now();
  const result = spawnSync(process.execPath, ['proofs/bounded-session/mutations.mjs'],
    {cwd: root, env: process.env, encoding: 'utf8', timeout: 10 * 60 * 1000, maxBuffer: 16 * 1024 * 1024});
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  process.stdout.write(output);
  if (result.error || result.status !== 0) throw result.error ?? new Error('Existing Session mutations failed');
  assert.equal(snapshot(root).digest, before.digest, 'Mutation source bytes were not restored');
  const report = json(join(root, '.artifacts/bounded-session/mutations.json'));
  assert.equal(report.source.digest, before.digest);
  recordExistingAction({id: 'mutations-js', command: ['node', 'proofs/bounded-session/mutations.mjs'], output,
    status: result.status, milliseconds: Math.round(performance.now() - start),
    result: {...report, sourceRestored: true, revision: git(['rev-parse', 'HEAD'])}});
}

export function finish() {
  const state = json(join(directory, 'context.json')), catalog = readCatalog();
  assert.equal(git(['diff', '--name-only', 'HEAD']), '', 'Unrestored final source');
  const requirements = [], applications = [], receiptDigests = [], receipts = [];
  for (const action of catalog.actions) {
    const bytes = readFileSync(join(directory, `receipts/${action.id}.json`)), receipt = parseReceipt(bytes);
    assert.equal(encode(receipt.origin), encode(state.origin), 'Mixed collection owner');
    assert.equal(encode(receipt.action), encode(action), 'Wrong collected descriptor');
    receipts.push(receipt);
    const records = leanRecords(action, receipt.inputs, {receipt}, state.context, 'fresh');
    requirements.push(records.required); applications.push(records.application);
    receiptDigests.push({actionId: action.id, digest: hash(bytes)});
  }
  const comparison = json(join(directory, 'comparison-plan.json'));
  const observations = compareFreshObservations({plan: comparison, context: state.context, runtime: state.runtime,
    tree: gitTree(root, state.context.candidateRevision), receipts});
  write(join(directory, 'comparison-observations.json'), observations);
  const start = performance.now();
  const lean = checkPlan(requirements, applications, {onOutput: output => writeFileSync(join(directory, 'lean-output.log'), output, {flag: 'wx'})});
  write(join(directory, 'checked.json'), {version: 'actql-verification-family-certificate/0.1',
    mode: 'comparison', context: state.context, catalogDigest: hash(encode(catalog)), receiptDigests,
    comparisonDigest: hash(readFileSync(join(directory, 'comparison-plan.json'))),
    comparisonObservationsDigest: hash(readFileSync(join(directory, 'comparison-observations.json'))),
    lean, milliseconds: Math.round(performance.now() - start)});
  console.log(`Checked ${receiptDigests.length} fresh actions; runtime closure and reuse remain pending`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const operation = process.argv[2];
  assert(['init', 'mutations', 'finish'].includes(operation), 'Use init, mutations or finish');
  if (operation === 'init') await initialize();
  else if (operation === 'mutations') await mutations();
  else finish();
}
