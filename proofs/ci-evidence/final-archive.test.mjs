import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog, protectedRegistrationRevision} from './actions.mjs';
import {gitTree, hash, actionInputs} from './inputs.mjs';
import {isolatedEnvironment, mutationSourcePaths, scratchDockerfile, isolatedRunArguments} from './isolation.mjs';
import {isolatedExperimentDigest} from './isolated-contract.mjs';
import {imageRuntime, snapshotFromGit, runtimeForAction} from './isolated-runtime.mjs';
import {runtimeResiduals, distributionSummary} from './runtime.mjs';
import {mutationIds, mutationContracts} from './mutation-inventory.mjs';
import {sealReceipt, canonicalReceipt} from './receipts.mjs';
import {leanRecords} from './applications.mjs';
import {checkPlan} from './check.mjs';
import {acquisitionPlan} from './acquisition.mjs';
import {comparisonVersion, compareFreshObservations} from './plan.mjs';
import {verifyCurrentFamily} from './final.mjs';
import {sealAcceptance} from './acceptance.mjs';
import {storedArchive} from './archive-fixture.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const jsonBytes = value => Buffer.from(`${encode(value)}\n`);

// Independent image-observation fixture. Source entries bind real immutable
// Git bytes; executable/image/physical-run facts remain synthetic and OPEN.
// No process, Docker execution or Actions authority is inferred from them.
function observedImage(tree) {
  const byPath = new Map();
  function file(path, bytes, mode) {
    const parts = path.split('/');
    for (let n = 1; n < parts.length; n++) {
      const directory = parts.slice(0, n).join('/');
      if (!byPath.has(directory)) byPath.set(directory, {path: directory, kind: 'directory', mode: 0o755, members: []});
    }
    byPath.set(path, {path, kind: 'file', mode, bytes: bytes.length, digest: hash(bytes)});
  }
  const paths = mutationSourcePaths(tree); tree.prefetch(paths);
  for (const path of paths) file(`source/${path}`, tree.read(path), Number.parseInt(tree.entries.get(path).mode.slice(-3), 8));
  const executables = ['runtime/node', ...['moon', 'moonc', 'moonrun'].map(name => `runtime/moonbit/bin/${name}`), 'bin/sh'];
  for (const path of executables) file(path, Buffer.from(`synthetic executable ${path}`), 0o755);
  for (const entry of byPath.values()) {
    const parent = entry.path.slice(0, entry.path.lastIndexOf('/'));
    if (entry.path.includes('/')) byPath.get(parent).members.push(entry.path.slice(parent.length + 1));
  }
  for (const entry of byPath.values()) if (entry.members) entry.members.sort();
  return {version: 'actql-isolated-mutation-inputs/0.1', environment: isolatedEnvironment,
    dockerfile: scratchDockerfile(), root: {entries: [...byPath.values()].sort((a, b) => a.path.localeCompare(b.path)), unresolved: [], links: []},
    platformInputs: {platform: 'linux', architecture: 'x64', kernelRelease: 'controlled-archive-fixture'},
    loaderObservations: executables.map(executable => ({executable, digest: byPath.get(executable).digest, static: true, paths: []})),
    sourceSnapshotDigest: snapshotFromGit(tree).digest, experimentDigest: isolatedExperimentDigest(tree),
    toolchainDigest: hash(tree.read('toolchain.json')), hostImage: 'controlled-archive-fixture'};
}

async function archiveFixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-final-archive-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  const tree = gitTree(root, revision), catalog = readCatalog();
  const context = {repository: 'actql/actql', repositoryId: 1, headRepositoryId: 1, workflowId: 2,
    candidateRevision: revision, runHeadRevision: revision, runId: 3, runAttempt: 4, ancestors: []};
  const origin = {repository: context.repository, repositoryId: 1, workflowId: 2, workflowPath: '.github/workflows/ci.yml',
    testedRevision: revision, runHeadRevision: revision, runId: 3, runAttempt: 4, jobId: 5, event: 'workflow_dispatch', branch: 'main'};
  const inventory = {entries: [], observedBytes: 0, unresolved: ['missing input: .']};
  const distributionInputs = Object.fromEntries(['nodeExecutable', 'moonbit', 'lean'].map(name => [name, inventory]));
  const runtime = {profile: 'comparison-linux-runtime', distributions: Object.fromEntries(Object.entries(distributionInputs)
    .map(([name, value]) => [name, distributionSummary(value)])),
    unresolved: [...runtimeResiduals, ...Object.keys(distributionInputs).map(name => `${name}: missing input: .`)]};
  const manifest = observedImage(tree), isolatedRuntime = imageRuntime(manifest), before = snapshotFromGit(tree);
  assert.equal(isolatedRuntime.contract, null); assert(isolatedRuntime.unresolved.length > 0);
  const actionRuntimes = {'mutations-js': isolatedRuntime};
  const report = {source: before, results: mutationIds.map(id => ({id, ...mutationContracts[id], killed: true, target: 'js', failureCount: 1}))};
  const payload = {version: 'actql-isolated-mutation-observation/0.1', root: manifest.root, platformInputs: manifest.platformInputs,
    environment: isolatedEnvironment, readOnlyConfirmed: true, shellStartupConfirmed: true, restored: true, report,
    logs: Object.fromEntries(mutationIds.map(id => [id, 'Total tests: 1, passed: 0, failed: 1.\n']))};
  const imageId = `sha256:${'b'.repeat(64)}`, owner = '3:4:5';
  const execution = {imageId, owner, arguments: isolatedRunArguments({imageId, owner, cidFile: '/controlled.cid'}),
    imageDefinition: {Id: imageId, Os: 'linux', Architecture: 'amd64', Config: {
      Labels: {'org.actql.ci.owner': owner}, Env: Object.entries(isolatedEnvironment).map(([name, value]) => `${name}=${value}`),
      User: '1000:1000', WorkingDir: '/workspace', Entrypoint: ['/runtime/node', '/source/proofs/ci-evidence/isolated-mutations.mjs']}},
    costs: {preparationMilliseconds: 1, buildMilliseconds: 2, executionMilliseconds: 3, inspectionMilliseconds: 4, closeMilliseconds: 5}};
  const members = new Map([
    ['context.json', jsonBytes({context, origin, runtime, actionRuntimes})],
    ['runtime-distributions.json', jsonBytes(distributionInputs)], ['isolated-inputs.json', jsonBytes(manifest)],
    ['isolated-observation.json', jsonBytes(payload)], ['isolated-execution.json', jsonBytes(execution)],
    ['results/mutations-js.json', jsonBytes({...report, sourceRestored: true, revision})],
  ]);
  const comparison = {version: comparisonVersion, mode: 'comparison', reuseAuthorized: false, context,
    catalogDigest: hash(encode(catalog)), baseline: {baseSha: null, reason: 'Controlled missing checkpoint'}, artifact: null,
    actions: catalog.actions.map(action => ({actionId: action.id, acquisition: 'execute',
      candidateActionKey: actionInputs({tree, revision, action, runtime: runtimeForAction(action, runtime, actionRuntimes)}).key,
      status: 'checkpoint-unavailable', origin: null, equal: false, closed: false, unresolved: []})),
    costs: {checkpointMilliseconds: 0, transferMilliseconds: 0, inspectionMilliseconds: 0, totalMilliseconds: 0}};
  const acquisition = await acquisitionPlan({context, catalog, comparison, event: origin.event,
    readReady: async () => assert.fail('A missing main comparison cannot read ready evidence')});
  const receipts = [], required = [], applications = [], receiptDigests = [];
  for (const action of catalog.actions) {
    const output = action.kind === 'formal-model' ? `Checked ${action.minimumUnits} theorems, expected claim types and axiom dependencies\n`
      : action.id === 'mutations-js' ? mutationIds.map(id => `${id}: detected by replacement tests`).join('\n')
        : `Total tests: ${action.minimumUnits}, passed: ${action.minimumUnits}, failed: 0.\n`;
    const paths = ['runtime-distributions.json', 'comparison-plan.json'];
    if (action.id === 'mutations-js') paths.push('isolated-inputs.json', 'isolated-observation.json', 'isolated-execution.json', 'results/mutations-js.json');
    members.set('comparison-plan.json', jsonBytes(comparison));
    const inputs = actionInputs({tree, revision, action, runtime: runtimeForAction(action, runtime, actionRuntimes)});
    const receipt = sealReceipt({origin, action, inputs, output, status: 0, milliseconds: action.id === 'mutations-js' ? 15 : 10,
      artifacts: paths.map(path => ({path, bytes: members.get(path).length, digest: hash(members.get(path))}))});
    members.set(`observations/${action.id}.log`, Buffer.from(output));
    members.set(`receipts/${action.id}.json`, canonicalReceipt(receipt)); receipts.push(receipt);
    const records = leanRecords(action, inputs, {receipt}, context, 'fresh');
    required.push(records.required); applications.push(records.application);
    receiptDigests.push({actionId: action.id, digest: hash(canonicalReceipt(receipt))});
  }
  const observations = compareFreshObservations({plan: comparison, context, runtime, actionRuntimes, tree, receipts,
    mutationResult: {...report, sourceRestored: true, revision}, acquisitions: acquisition.actions});
  // Controlled cost observations accompany the existing controlled API/image
  // facts. They do not establish physical execution or runner savings.
  const collection = {runtimeObservation: {milliseconds: 2, entries: 0, bytes: 0,
    inputDigest: hash(encode(runtime))}, isolatedPreparationMilliseconds: 1,
    stagedSourceBytes: manifest.root.entries.filter(entry => entry.kind === 'file' && entry.path.startsWith('source/'))
      .reduce((total, entry) => total + entry.bytes, 0),
    comparison: comparison.costs, acquisitionMilliseconds: acquisition.milliseconds};
  members.set('collection-costs.json', jsonBytes(collection));
  let output;
  // Real Git identities and all thirty obligations use the same kernel proof.
  // Bound this local fixture explicitly; production keeps its existing 30s limit.
  const lean = checkPlan(required, applications, {timeout: 60000, onOutput: value => {output = Buffer.from(value);}});
  const certificate = {version: 'actql-verification-family-certificate/0.1', mode: 'scoped-execution', context,
    catalogDigest: hash(encode(catalog)), receiptDigests, lean, comparisonDigest: hash(jsonBytes(comparison)),
    comparisonObservationsDigest: hash(jsonBytes(observations)), acquisitionDigest: hash(jsonBytes(acquisition)),
    collectionCostsDigest: hash(jsonBytes(collection)), milliseconds: 13};
  members.set('checked.json', jsonBytes(certificate)); members.set('lean-output.log', output);
  members.set('comparison-observations.json', jsonBytes(observations)); members.set('acquisition-plan.json', jsonBytes(acquisition));
  const archive = join(directory, 'source.zip'), bytes = storedArchive(members);
  await writeFile(archive, bytes);
  const run = {id: 3, run_attempt: 4, head_sha: revision, workflow_id: 2, path: origin.workflowPath,
    repository: {id: 1, full_name: context.repository}, head_repository: {id: 1},
    event: origin.event, head_branch: origin.branch, status: 'completed', conclusion: 'success'};
  const job = {id: 5, name: 'session-evidence', run_id: 3, run_attempt: 4, head_sha: revision, status: 'completed', conclusion: 'success'};
  const artifact = {id: 6, name: `session-actions-3-4-${revision}`, size_in_bytes: bytes.length,
    digest: `sha256:${hash(bytes)}`, expired: false, expires_at: '2050-01-01T00:00:00Z',
    workflow_run: {id: 3, head_sha: revision, repository_id: 1, head_repository_id: 1}};
  const requests = [];
  const request = async path => {
    requests.push(path);
    if (path === '/actions/runs/3') return structuredClone(run);
    if (path === '/actions/runs/3/attempts/4/jobs?per_page=100') return {total_count: 1, jobs: [structuredClone(job)]};
    if (path === '/actions/artifacts/6') return structuredClone(artifact);
    throw new Error(`Unexpected controlled API request: ${path}`);
  };
  return {options: {root, directory, archive, artifactId: 6, expectedDigest: hash(bytes), context, request},
    members, requests, artifact, run, job, catalog, observations, original: bytes};
}

test('real ZIP consumer reconstructs actual Git and the executed complete certificate while retaining open boundaries', async t => {
  const f = await archiveFixture(t), result = await verifyCurrentFamily(f.options);
  assert.deepEqual(result.requiredActions, f.catalog.actions.map(action => action.id));
  assert.equal(result.protectedRevision, protectedRegistrationRevision);
  assert(result.applications.every(value => value.acquisition === 'fresh'));
  assert.equal(result.lean.accepted, true); assert.equal(result.comparison.confirmation.status, 'not-compared');
  assert.equal(result.comparison.reuseAuthorized, false);
  assert.equal(result.sourceArtifactBytes, f.original.length);
  assert.equal(result.costObservation.actions.length, 30);
  assert.deepEqual(result.costObservation.producerOwner, {runId: 3, runAttempt: 4, jobId: 5});
  assert(f.requests.filter(path => path === '/actions/runs/3').length >= 3);
  const {acceptanceInputs, ...acceptedResult} = result;
  const acceptance = sealAcceptance({result: acceptedResult, observations: acceptanceInputs.observations, event: 'workflow_dispatch', branch: 'main',
    owner: {runId: 3, runAttempt: 4, jobId: 7}, sourceArtifact: {id: 6, digest: hash(f.original)},
    certificateDigest: hash(f.members.get('checked.json'))});
  assert.deepEqual(acceptance.ready, [], 'Fixture success and an open/missing comparison cannot authorize reuse');

  f.job.conclusion = 'failure';
  await assert.rejects(verifyCurrentFamily(f.options), {name: 'AssertionError', actual: 'failure', expected: 'success'}); f.job.conclusion = 'success';
  f.run.run_attempt++;
  await assert.rejects(verifyCurrentFamily(f.options), {name: 'AssertionError', actual: 5, expected: 4}); f.run.run_attempt--;
  f.artifact.digest = `sha256:${'e'.repeat(64)}`;
  await assert.rejects(verifyCurrentFamily(f.options), /archive digest mismatch/u); f.artifact.digest = `sha256:${hash(f.original)}`;

  // Rebind transport to changed real ZIP bytes: deeper semantic validation
  // must refuse even when the independent API digest matches that new archive.
  for (const [change, refusal] of [
    [members => members.delete('receipts/events-connection-native.json'), /Artifact ZIP member not found/u],
    [members => members.set('lean-output.log', Buffer.from('changed actual certificate output')), /Changed Lean output/u],
    [members => {
      const state = JSON.parse(members.get('context.json'));
      state.actionRuntimes['mutations-js'].unresolved = [];
      members.set('context.json', jsonBytes(state));
    }, /Wrong isolated runtime inputs or erased residual/u],
  ]) {
    const members = new Map(f.members); change(members);
    const bytes = storedArchive(members), digest = hash(bytes);
    await writeFile(f.options.archive, bytes); f.artifact.digest = `sha256:${digest}`; f.artifact.size_in_bytes = bytes.length;
    await assert.rejects(verifyCurrentFamily({...f.options, expectedDigest: digest}), refusal);
  }
});
