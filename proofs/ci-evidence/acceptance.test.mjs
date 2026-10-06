import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog} from './actions.mjs';
import {actionInputs, hash, sharedFiles, mutationSnapshotExtras} from './inputs.mjs';
import {sealReceipt, canonicalReceipt} from './receipts.mjs';
import {leanRecords, applicationVersion} from './applications.mjs';
import {leanInput} from './check.mjs';
import {storedArchive as zip} from './archive-fixture.mjs';
import {sealAcceptance, checkAcceptance, readAcceptance, readyActions, acceptanceName} from './acceptance.mjs';
import {checkCostObservation} from './costs.mjs';

const jsonBytes = value => Buffer.from(`${encode(value)}\n`);
function fixture(event = 'push', fullCatalog = false) {
  const catalog = readCatalog();
  if (!fullCatalog) {
    catalog.actions = catalog.actions.filter(action => ['model', 'mutations-js'].includes(action.id));
    catalog.actions.forEach(action => { action.dependencies = []; });
  }
  const context = {repository: 'actql/actql', repositoryId: 1, headRepositoryId: 1, workflowId: 2,
    candidateRevision: 'a'.repeat(40), runHeadRevision: 'a'.repeat(40), runId: 3, runAttempt: 4, ancestors: []};
  const origin = {...context, testedRevision: context.candidateRevision, workflowPath: '.github/workflows/ci.yml',
    event, branch: 'main', jobId: 5};
  delete origin.candidateRevision; delete origin.ancestors; delete origin.headRepositoryId;
  const files = new Map([...sharedFiles.map(path => [path, path]),
    ...mutationSnapshotExtras.map(path => [path, path]),
    ...['bounded_execution', 'connectors/local', 'query_integration'].map(path => [`src/${path}/moon.pkg`, '']),
    ['src/example/moon.pkg', ''], ['src/example/value.mbt', 'numeric deterministic fixture'],
    ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs', 'mutations.mjs', 'evidence.mjs'].map(name => [`proofs/bounded-session/${name}`, name])]);
  for (const name of ['check.mjs', 'Composition.lean', 'CompositionClaims.lean', 'Events.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs'])
    files.set(`proofs/events-bridge/${name}`, name);
  for (const action of catalog.actions) if (action.package) files.set(`${action.package}/moon.pkg`, '');
  const tree = {entries: new Map([...files].map(([path]) => [path, {kind: 'blob', mode: '100644'}])), read: path => Buffer.from(files.get(path))};
  const required = [], applications = [], receiptDigests = [], members = new Map(), receipts = [];
  const runtime = {profile: 'controlled-test-runtime', unresolved: []};
  const scientificDigest = 'e'.repeat(64), sourceArtifact = {id: 6, digest: 'f'.repeat(64)};
  const result = {version: 'actql-verification-family-result/0.1', context, protectedRevision: '0'.repeat(40),
    catalogDigest: hash(encode(catalog)), requiredActions: catalog.actions.map(action => action.id), applications: [], sourceArtifactBytes: 1};
  for (const action of catalog.actions) {
    const inputs = actionInputs({tree, revision: context.candidateRevision, action, runtime});
    // The deterministic JS observation fixture records all thirteen identities.
    const output = action.kind === 'formal-model' ? `Checked ${action.minimumUnits} theorems, expected claim types and axiom dependencies\n` :
      action.id !== 'mutations-js' ? `Total tests: ${action.minimumUnits}, passed: ${action.minimumUnits}, failed: 0.\n` :
      ['stale-token-reuse', 'zero-quantum', 'terminal-resume', 'cleanup-changed-as-complete', 'cumulative-as-delta',
        'reset-budget-history', 'accept-backward-work', 'adapter-terminal-resume', 'premature-cleanup-success',
        'cleanup-retry-reruns-callback', 'actual-set-path-reaches-adapter', 'actual-nest-path-reaches-adapter', 'nest-parent-child-ports-swapped']
        .map(id => `${id}: detected by replacement tests`).join('\n');
    const receipt = sealReceipt({origin, action, inputs, output, status: 0, milliseconds: 10});
    receipts.push(receipt);
    const bytes = canonicalReceipt(receipt), receiptDigest = hash(bytes);
    members.set(`receipts/${action.id}.json`, bytes);
    const records = leanRecords(action, inputs, {receipt}, context, 'fresh');
    required.push(records.required); applications.push(records.application); receiptDigests.push({actionId: action.id, digest: receiptDigest});
    result.applications.push({version: applicationVersion, candidateRevision: context.candidateRevision, actionId: action.id,
      acquisition: 'fresh', originReceiptDigest: receiptDigest, originRevision: context.candidateRevision,
      originRunId: 3, originRunAttempt: 4, artifactId: 6, archiveDigest: sourceArtifact.digest,
      candidateActionKey: inputs.key, originActionKey: inputs.key, kind: action.kind, target: action.target,
      scopeDigest: hash(encode({profile: action.profile, premises: action.premises})), checkerResult: 'accepted'});
  }
  const comparison = {context, reuseAuthorized: false, baseline: {baseSha: '0'.repeat(40)},
    costs: {checkpointMilliseconds: 0, transferMilliseconds: 0, inspectionMilliseconds: 0, totalMilliseconds: 0},
    actions: catalog.actions.map(action => ({actionId: action.id, status: action.id === 'mutations-js' ? 'closed-inputs-match' : 'same-inputs-open'}))};
  const observations = catalog.actions.map(action => ({actionId: action.id,
    status: action.id === 'mutations-js' ? 'scientific-match' : 'counts-match', scientificDigest, originScientificDigest: scientificDigest}));
  const leanOutput = Buffer.from('independent tiny fixture certificate output, no Lean executed locally');
  const lean = {accepted: true, theoremCount: 5, toolchain: 'fixture', inputDigest: hash(leanInput(required, applications)), outputDigest: hash(leanOutput)};
  const certificate = {version: 'actql-verification-family-certificate/0.1', mode: 'scoped-execution', context,
    milliseconds: 0,
    catalogDigest: result.catalogDigest, receiptDigests, lean,
    comparisonDigest: hash(jsonBytes(comparison)), comparisonObservationsDigest: hash(jsonBytes(observations))};
  const state = {context, origin, runtime};
  const acquisition = {context, milliseconds: 0, actions: receipts.map(receipt => ({actionId: receipt.action.id,
    acquisition: 'fresh', candidateActionKey: receipt.inputs.key}))};
  const collectionBytes = jsonBytes({runtimeObservation: {milliseconds: 1, entries: 1, bytes: 1, inputDigest: hash(encode(runtime))},
    isolatedPreparationMilliseconds: 1, stagedSourceBytes: 1, comparison: comparison.costs, acquisitionMilliseconds: 0});
  const isolatedExecution = {owner: '3:4:5', costs: {preparationMilliseconds: 1, buildMilliseconds: 2,
    executionMilliseconds: 3, inspectionMilliseconds: 2, closeMilliseconds: 2}};
  certificate.collectionCostsDigest = hash(collectionBytes); certificate.acquisitionDigest = hash(jsonBytes(acquisition));
  result.acquisition = acquisition;
  result.costObservation = checkCostObservation({collectionBytes, certificate, state, catalog, acquisition, comparison, receipts, isolatedExecution});
  members.set('collection-costs.json', collectionBytes); members.set('context.json', jsonBytes(state));
  members.set('acquisition-plan.json', jsonBytes(acquisition)); members.set('isolated-execution.json', jsonBytes(isolatedExecution));
  members.set('checked.json', jsonBytes(certificate)); members.set('lean-output.log', leanOutput);
  members.set('comparison-plan.json', jsonBytes(comparison)); members.set('comparison-observations.json', jsonBytes(observations));
  result.lean = lean; result.comparison = {baseline: comparison.baseline, confirmation: {status: 'confirmed'}, reuseAuthorized: false,
    recordedStatuses: comparison.actions.map(entry => ({...entry}))};
  const report = sealAcceptance({result, observations, owner: {runId: 3, runAttempt: 4, jobId: 7}, event, branch: 'main',
    sourceArtifact, certificateDigest: hash(members.get('checked.json'))});
  return {catalog, context, sourceArtifact, report, members,
    sourceZip: {compressedBytes: 1, read: async path => { assert(members.has(path), 'Missing actual source member'); return members.get(path); }}};
}

test('final applicability binds actual source receipts, scientific observations and the executed certificate', async () => {
  const f = fixture(); assert.equal((await checkAcceptance(f)).length, 1);
  const before = encode(f.report);
  for (const change of [
    report => report.context.runAttempt++,
    report => report.sourceArtifact.id++,
    report => report.certificateDigest = '9'.repeat(64),
    report => report.result.applications.pop(),
    report => report.result.applications[1].target = 'native',
    report => report.result.comparison.confirmation.status = 'unconfirmed',
    report => report.observations[1].scientificDigest = '9'.repeat(64),
    report => report.ready[0].actionKey = '9'.repeat(64),
  ]) {
    const report = structuredClone(f.report); change(report);
    await assert.rejects(checkAcceptance({...f, report}));
  }
  assert.equal(encode(f.report), before);
});
test('manual acceptance preserves actual receipt triggers and cannot relabel a push original', async () => {
  const manual = fixture('workflow_dispatch');
  assert.equal((await checkAcceptance(manual)).length, 1);
  const push = fixture(); push.report.event = 'workflow_dispatch';
  await assert.rejects(checkAcceptance(push));
});

test('main applicability reconstructs costs for all 30 obligations and rejects omitted Bridge costs or receipts', async () => {
  // Controlled admission fixture: this executes the actual cost/acceptance
  // consumers, not the MoonBit commands or the Lean kernel.
  const f = fixture('workflow_dispatch', true);
  assert.equal((await checkAcceptance(f)).length, 1);
  assert.equal(f.report.result.costObservation.actions.length, 30);
  assert.equal(f.report.result.costObservation.knownProducerMilliseconds, 301);
  for (const id of ['events-model', 'events-connection-js', 'events-connection-wasm', 'events-connection-native']) {
    const absentCost = fixture('workflow_dispatch', true);
    absentCost.report.result.costObservation.actions = absentCost.report.result.costObservation.actions.filter(row => row.actionId !== id);
    await assert.rejects(checkAcceptance(absentCost), /Wrong accepted cost correspondence/u);
    const absentReceipt = fixture('workflow_dispatch', true);
    absentReceipt.members.delete(`receipts/${id}.json`);
    await assert.rejects(checkAcceptance(absentReceipt), /Missing actual source member/u);
  }
});

test('main acceptance rejects missing or substituted costs and historical costs presented as current execution', async () => {
  const changes = [
    [f => f.members.delete('collection-costs.json'), /Missing actual source member/u],
    [f => f.members.set('collection-costs.json', Buffer.from('{}\n')), /Changed collection cost bytes/u],
    [f => f.members.delete('isolated-execution.json'), /Missing actual source member/u],
    [f => { const value = JSON.parse(f.members.get('isolated-execution.json')); value.owner = '3:5:5';
      f.members.set('isolated-execution.json', jsonBytes(value)); }, /Wrong isolated cost owner/u],
    [f => { const value = JSON.parse(f.members.get('acquisition-plan.json')); value.milliseconds++;
      f.members.set('acquisition-plan.json', jsonBytes(value)); }, /Wrong accepted acquisition cost binding/u],
    [f => { f.report.result.costObservation.knownProducerMilliseconds++; }, /Wrong accepted cost correspondence/u],
    [f => { f.report.result.costObservation.producerOwner.jobId++; }, /Wrong accepted cost correspondence/u],
    [f => { f.report.result.costObservation.actions[1].currentMilliseconds = null; }, /Wrong accepted cost correspondence/u],
    [f => { f.report.result.costObservation.actions[1].observation = 'reused-not-executed'; }, /Wrong accepted cost correspondence/u],
    [f => { f.report.result.costObservation.netRunnerSavingsMilliseconds = 10; }, /Wrong accepted cost correspondence/u],
    [f => { f.report.result.costObservation.residual = []; }, /Wrong accepted cost correspondence/u],
    [f => { f.report.result.sourceArtifactBytes++; }, /Wrong accepted source archive byte observation/u],
  ];
  for (const [change, expected] of changes) {
    const f = fixture(); change(f);
    await assert.rejects(checkAcceptance(f), expected);
  }
  // Even resealing the outer certificate does not turn malformed source costs
  // into a valid current observation. This fixture does not execute mutations.
  const f = fixture(), value = JSON.parse(f.members.get('collection-costs.json'));
  value.runtimeObservation.milliseconds = -1;
  f.members.set('collection-costs.json', jsonBytes(value));
  const certificate = JSON.parse(f.members.get('checked.json'));
  certificate.collectionCostsDigest = hash(f.members.get('collection-costs.json'));
  f.members.set('checked.json', jsonBytes(certificate));
  f.report.certificateDigest = hash(f.members.get('checked.json'));
  await assert.rejects(checkAcceptance(f), /Invalid cost observation/u);
});

test('only a fresh main comparison qualifies; recovered partial comparison and prior PR acceptance do not', () => {
  for (const change of [
    report => report.event = 'pull_request',
    report => report.branch = 'feature',
    report => report.result.comparison.confirmation.status = 'unconfirmed',
    report => report.result.applications[1].acquisition = 'reused',
    report => report.result.context.runHeadRevision = '9'.repeat(40),
    report => report.observations[1].status = 'counts-match',
  ]) { const f = fixture(); change(f.report); assert.deepEqual(readyActions(f.report), []); }
});

for (const event of ['push', 'workflow_dispatch']) test(`actual ${event} acceptance ZIP rejects failed owners, wrong attempts, tampered bytes and missing archives`, async t => {
  const f = fixture(event), directory = await mkdtemp(join(tmpdir(), 'actql-final-acceptance-'));
  t.after(() => rm(directory, {recursive: true}));
  const sourceArchive = join(directory, 'source.zip'), archive = join(directory, 'acceptance.zip');
  // Bind the API to independently written ZIP bytes, not a report's digest.
  const sourceBytes = zip([...f.members]), sourceDigest = hash(sourceBytes);
  await writeFile(sourceArchive, sourceBytes);
  f.sourceArtifact.digest = sourceDigest; f.report.sourceArtifact.digest = sourceDigest;
  f.report.result.sourceArtifactBytes = sourceBytes.length;
  f.report.result.applications.forEach(entry => { entry.archiveDigest = sourceDigest; });
  const bytes = zip([['verified-family.json', jsonBytes(f.report)]]); await writeFile(archive, bytes);
  const run = {id: 3, run_attempt: 4, head_sha: f.context.candidateRevision, workflow_id: 2, path: '.github/workflows/ci.yml',
    repository: {id: 1, full_name: 'actql/actql'}, head_repository: {id: 1}, event, head_branch: 'main', status: 'completed', conclusion: 'success'};
  const job = {id: 7, name: 'check', run_id: 3, run_attempt: 4, head_sha: f.context.runHeadRevision, status: 'completed', conclusion: 'success'};
  const artifact = {id: 8, name: acceptanceName(f.context), size_in_bytes: bytes.length, digest: `sha256:${hash(bytes)}`,
    expired: false, expires_at: '2050-01-01T00:00:00Z', workflow_run: {id: 3, head_sha: f.context.runHeadRevision, repository_id: 1, head_repository_id: 1}};
  const request = (mutate = () => {}) => async path => {
    const values = structuredClone({run, job, artifact}); mutate(values);
    if (path === '/actions/runs/3') return values.run;
    if (path === '/actions/runs/3/artifacts?per_page=100') return {total_count: 1, artifacts: [values.artifact]};
    if (path === '/actions/artifacts/8') return values.artifact;
    if (path === '/actions/runs/3/attempts/4/jobs?per_page=100') return {total_count: 1, jobs: [values.job]};
    throw new Error('Unexpected API path');
  };
  const options = {...f, sourceArchive, archive, directory, artifactId: 8, request: request(), expectedDigest: hash(bytes)};
  assert.equal((await readAcceptance(options)).ready.length, 1);
  let runReads = 0;
  await assert.rejects(readAcceptance({...options, request: async path => {
    const value = await request()(path);
    if (path === '/actions/runs/3' && ++runReads > 1) value.event = event === 'push' ? 'workflow_dispatch' : 'push';
    return value;
  }}), /trigger changed/u);
  assert.equal(runReads, 2);
  for (const mutate of [
    value => value.run.event = event === 'push' ? 'workflow_dispatch' : 'push',
    value => value.run.head_branch = 'feature',
    value => value.run.run_attempt++, value => value.run.conclusion = 'cancelled',
    value => value.job.conclusion = 'failure', value => value.job.name = 'session-evidence',
    value => value.artifact.workflow_run.repository_id++, value => value.artifact.digest = `sha256:${'9'.repeat(64)}`,
    value => value.artifact.expired = true,
  ]) await assert.rejects(readAcceptance({...options, request: request(mutate)}));
  await assert.rejects(readAcceptance({...options, artifactId: null, request: async path => path.endsWith('/artifacts?per_page=100') ?
    {total_count: 0, artifacts: []} : request()(path)}), /unavailable/u);
  await writeFile(archive, zip([['verified-family.json', jsonBytes({...f.report, ready: []})]]));
  await assert.rejects(readAcceptance(options), /SHA-256 mismatch/u);
});
