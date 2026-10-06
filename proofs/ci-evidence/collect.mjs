// Initial comparison collection consumes existing executions, without another
// proof/test campaign. Receipts are not reusable until the Actions job/run is
// independently authenticated as successful by the artifact consumer.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, readFileSync, writeFileSync, existsSync, copyFileSync, constants} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {actionsReader} from '../../scripts/ci-main-base.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog, catalogPath, initialRegistrationRevision, preserveProtectedActions} from './actions.mjs';
import {checkExecutionRecipes} from './execution-recipes.mjs';
import {actionInputs, gitTree, hash} from './inputs.mjs';
import {canonicalReceipt, parseReceipt, sealReceipt} from './receipts.mjs';
import {leanRecords} from './applications.mjs';
import {checkPlan} from './check.mjs';
import {observeRuntime} from './runtime.mjs';
import {comparisonPlan, compareFreshObservations} from './plan.mjs';
import {prepareIsolatedMutation, executeIsolatedMutation} from './isolated-execution.mjs';
import {runtimeForAction} from './isolated-runtime.mjs';
import {acquisitionPlan} from './acquisition.mjs';
import {readReadyOrigin} from './acceptance.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const directory = join(root, '.artifacts/session-actions');
const isolatedDirectory = join(root, '.artifacts/session-isolated-build');
const comparisonDirectory = join(root, '.artifacts/session-comparison-cache');
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
  const catalog = readCatalog();
  preserveProtectedActions(protectedCatalog, catalog);
  checkExecutionRecipes(catalog);
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
  assert(!existsSync(isolatedDirectory), 'Another isolated executor owns the build directory');
  mkdirSync(isolatedDirectory);
  const prepared = prepareIsolatedMutation({root, tree: gitTree(root, revision), origin, directory: isolatedDirectory});
  write(join(isolatedDirectory, 'prepared.json'), prepared);
  write(join(directory, 'isolated-inputs.json'), prepared.manifest);
  const actionRuntimes = {'mutations-js': prepared.runtime};
  write(join(directory, 'context.json'), {context, origin, runtime, actionRuntimes});
  write(join(directory, 'runtime-distributions.json'), distributionInputs);
  write(join(directory, 'runtime-measurement.json'), measurement);
  assert(!existsSync(comparisonDirectory), 'Another comparison owns this cache directory');
  mkdirSync(comparisonDirectory);
  let transport, accepted;
  const comparison = await comparisonPlan({root, context, runtime, actionRuntimes, directory: comparisonDirectory,
    token: process.env.ACTIONS_READ_TOKEN, request, onArchive: value => { transport = value; }});
  write(join(directory, 'comparison-plan.json'), comparison);
  const acquisition = await acquisitionPlan({context, catalog: readCatalog(), comparison, event: origin.event,
    readReady: async () => {
      assert(transport, 'Missing authenticated comparison transport');
      accepted = await readReadyOrigin({root, catalog: readCatalog(), sourceArchive: transport.archive,
        sourceArtifact: {id: transport.artifact.id, digest: transport.artifact.digest.slice('sha256:'.length)},
        baseline: comparison.baseline, candidateContext: context, treeAt: value => gitTree(root, value), request,
        token: process.env.ACTIONS_READ_TOKEN, directory: comparisonDirectory});
      return accepted;
    }});
  write(join(directory, 'acquisition-plan.json'), acquisition);
  write(join(directory, 'collection-costs.json'), {runtimeObservation: measurement,
    isolatedPreparationMilliseconds: prepared.preparationMilliseconds, stagedSourceBytes: prepared.sourceBytes,
    comparison: comparison.costs, acquisitionMilliseconds: acquisition.milliseconds});
  if (acquisition.actions.some(entry => entry.acquisition === 'reused')) {
    mkdirSync(join(directory, 'reused'));
    copyFileSync(transport.archive, join(directory, 'reused/session-origin.zip'), constants.COPYFILE_EXCL);
    copyFileSync(accepted.archive, join(directory, 'reused/session-applicability.zip'), constants.COPYFILE_EXCL);
    // Original canonical bytes, not a relabeled candidate receipt.
    writeFileSync(join(directory, 'receipts/mutations-js.json'), canonicalReceipt(accepted.original.receipt), {flag: 'wx'});
  }
  console.log(`Collection initialized for ${revision}: ${acquisition.actions.filter(entry => entry.acquisition === 'fresh').length} fresh, ` +
    `${acquisition.actions.filter(entry => entry.acquisition === 'reused').length} reused`);
}

export function recordExistingAction({id, command, output, status, milliseconds, result = null, extraArtifacts = []}) {
  if (process.env.ACTQL_SESSION_COLLECT !== 'true') return;
  const state = json(join(directory, 'context.json'));
  assert.equal(git(['rev-parse', 'HEAD']), state.context.candidateRevision);
  assert.equal(git(['diff', '--name-only', 'HEAD']), '', 'Unrestored tracked source');
  const action = readCatalog().actions.find(entry => entry.id === id);
  assert(action, `Unregistered execution: ${id}`);
  assert.equal(encode(action.command), encode(command), 'Executed command differs from registration');
  tree ??= gitTree(root, state.context.candidateRevision);
  const inputs = actionInputs({tree, revision: state.context.candidateRevision, action,
    runtime: runtimeForAction(action, state.runtime, state.actionRuntimes)});
  const distributionPath = 'runtime-distributions.json';
  const distributionBytes = readFileSync(join(directory, distributionPath));
  const artifacts = [{path: distributionPath, bytes: distributionBytes.length, digest: hash(distributionBytes)}];
  if (id === 'mutations-js') {
    for (const path of ['isolated-inputs.json', ...extraArtifacts]) {
      const bytes = readFileSync(join(directory, path)); artifacts.push({path, bytes: bytes.length, digest: hash(bytes)});
    }
  } else assert.equal(extraArtifacts.length, 0, 'Only the actual isolated action may acquire isolated artifacts');
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
  const state = json(join(directory, 'context.json')), prepared = json(join(isolatedDirectory, 'prepared.json'));
  const revision = git(['rev-parse', 'HEAD']); assert.equal(revision, state.context.candidateRevision);
  const acquisition = json(join(directory, 'acquisition-plan.json')).actions.find(entry => entry.actionId === 'mutations-js');
  assert(acquisition, 'Missing independent mutation execution obligation');
  if (acquisition.acquisition === 'reused') {
    assert.equal(acquisition.reason, 'verified-main-comparison');
    console.log(`REUSED mutations-js from main ${acquisition.origin.revision}, run ${acquisition.origin.runId}/${acquisition.origin.runAttempt}; not executed on candidate`);
    return;
  }
  assert.equal(acquisition.acquisition, 'fresh');
  assert.equal(prepared.owner, `${state.origin.runId}:${state.origin.runAttempt}:${state.origin.jobId}`);
  const result = executeIsolatedMutation({root, tree: gitTree(root, revision), prepared});
  process.stdout.write(result.output);
  // Preserve the original mutation artifacts at the existing upload boundary.
  const originalDirectory = join(root, '.artifacts/bounded-session');
  mkdirSync(originalDirectory, {recursive: true});
  writeFileSync(join(originalDirectory, 'mutations.json'), `${JSON.stringify(result.payload.report, null, 2)}\n`, {flag: 'wx'});
  for (const [id, output] of Object.entries(result.payload.logs)) writeFileSync(join(originalDirectory, `mutation-${id}.log`), output, {flag: 'wx'});
  write(join(directory, 'isolated-observation.json'), result.payload);
  write(join(directory, 'isolated-execution.json'), {imageId: result.imageId, imageDefinition: result.imageDefinition,
    owner: result.owner, arguments: result.arguments, costs: result.costs});
  recordExistingAction({id: 'mutations-js', command: ['node', 'proofs/bounded-session/mutations.mjs'], output: result.output,
    status: 0, milliseconds: Object.values(result.costs).reduce((sum, value) => sum + value, 0),
    extraArtifacts: ['isolated-observation.json', 'isolated-execution.json'],
    result: {...result.payload.report, sourceRestored: true, revision}});
}

export function finish() {
  const state = json(join(directory, 'context.json')), catalog = readCatalog();
  checkExecutionRecipes(catalog);
  const acquisition = json(join(directory, 'acquisition-plan.json'));
  assert.deepEqual(acquisition.actions.map(entry => entry.actionId), catalog.actions.map(action => action.id));
  assert.equal(encode(acquisition.context), encode(state.context));
  assert.equal(git(['diff', '--name-only', 'HEAD']), '', 'Unrestored final source');
  const requirements = [], applications = [], receiptDigests = [], receipts = [];
  const candidateTree = gitTree(root, state.context.candidateRevision);
  for (const action of catalog.actions) {
    const bytes = readFileSync(join(directory, `receipts/${action.id}.json`)), receipt = parseReceipt(bytes);
    const entry = acquisition.actions.find(value => value.actionId === action.id);
    if (entry.acquisition === 'fresh') assert.equal(encode(receipt.origin), encode(state.origin), 'Mixed fresh collection owner');
    else {
      assert.equal(entry.actionId, 'mutations-js'); assert.equal(entry.acquisition, 'reused');
      assert.equal(receipt.origin.testedRevision, entry.origin.revision); assert.equal(hash(bytes), entry.origin.receiptDigest);
    }
    assert.equal(encode(receipt.action), encode(action), 'Wrong collected descriptor');
    receipts.push(receipt);
    const manifest = actionInputs({tree: candidateTree, revision: state.context.candidateRevision,
      action, runtime: runtimeForAction(action, state.runtime, state.actionRuntimes)});
    assert.equal(manifest.key, entry.candidateActionKey, 'Changed execution-plan inputs');
    const records = leanRecords(action, manifest, {receipt}, state.context, entry.acquisition);
    requirements.push(records.required); applications.push(records.application);
    receiptDigests.push({actionId: action.id, digest: hash(bytes)});
  }
  const comparison = json(join(directory, 'comparison-plan.json'));
  const observations = compareFreshObservations({plan: comparison, context: state.context, runtime: state.runtime,
    actionRuntimes: state.actionRuntimes,
    tree: candidateTree, receipts,
    acquisitions: acquisition.actions,
    mutationResult: existsSync(join(directory, 'results/mutations-js.json')) ? json(join(directory, 'results/mutations-js.json')) : null});
  write(join(directory, 'comparison-observations.json'), observations);
  const start = performance.now();
  const lean = checkPlan(requirements, applications, {onOutput: output => writeFileSync(join(directory, 'lean-output.log'), output, {flag: 'wx'})});
  write(join(directory, 'checked.json'), {version: 'actql-verification-family-certificate/0.1',
    mode: 'scoped-execution', context: state.context, catalogDigest: hash(encode(catalog)), receiptDigests,
    acquisitionDigest: hash(readFileSync(join(directory, 'acquisition-plan.json'))),
    collectionCostsDigest: hash(readFileSync(join(directory, 'collection-costs.json'))),
    comparisonDigest: hash(readFileSync(join(directory, 'comparison-plan.json'))),
    comparisonObservationsDigest: hash(readFileSync(join(directory, 'comparison-observations.json'))),
    lean, milliseconds: Math.round(performance.now() - start)});
  console.log(`Checked ${receiptDigests.length} obligations: ${acquisition.actions.filter(entry => entry.acquisition === 'fresh').length} fresh, ` +
    `${acquisition.actions.filter(entry => entry.acquisition === 'reused').length} reused`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const operation = process.argv[2];
  assert(['init', 'mutations', 'finish'].includes(operation), 'Use init, mutations or finish');
  if (operation === 'init') await initialize();
  else if (operation === 'mutations') await mutations();
  else finish();
}
