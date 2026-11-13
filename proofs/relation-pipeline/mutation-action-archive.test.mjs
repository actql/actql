// Controlled ZIP/API fixtures exercise transport refusals, not real Actions or
// MoonBit execution. The plan certificate is produced by the actual pinned Lean.
import assert from 'node:assert/strict';
import test, {before} from 'node:test';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {parse} from 'yaml';
import {storedArchive} from '../ci-evidence/archive-fixture.mjs';
import {hash} from '../ci-evidence/inputs.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {checkPlan} from '../ci-evidence/check.mjs';
import {ArtifactUnavailable, unavailableTransport} from '../ci-evidence/transport.mjs';
import {mutationActionRecords} from './mutation-actions.mjs';
import {cohort} from './fixtures/mutation-action-sample.mjs';
import {sealMutationActionOriginal, readMutationActionOriginal, originalPath} from './mutation-action-archive.mjs';
import {verifyCurrentMutationActions} from './mutation-action-final.mjs';

const revision = 'a'.repeat(40);
const origin = {repository: 'actql/actql', repositoryId: 1, testedRevision: revision, runHeadRevision: revision,
  workflowPath: '.github/workflows/ci.yml', runId: 3, runAttempt: 4, event: 'workflow_dispatch', branch: 'main'};
const expected = {repository: 'actql/actql', repositoryId: 1, workflowId: 2, candidateRevision: revision,
  runHeadRevision: revision, runId: 3, runAttempt: 4, ancestors: [revision]};
let base;
before(() => {
  const c = cohort(), records = mutationActionRecords(c);
  let leanOutput;
  const certificate = checkPlan(records.actions.map(entry => entry.required), records.actions.map(entry => entry.application),
    {onOutput: output => {leanOutput = output;}});
  const admission = {...records, sourceInputs: c.sourceInputs, certificate, leanOutput, admissionMilliseconds: 1};
  const original = sealMutationActionOriginal({origin, source: c.source, decision: c.decision, admission});
  const members = new Map([[originalPath, Buffer.from(`${encode(original)}\n`)]]);
  for (const entry of c.reports) {
    members.set(entry.path.slice('.artifacts/'.length), Buffer.from(`${JSON.stringify(entry.report, null, 2)}\n`));
    for (const result of entry.report.results) for (const ref of [...result.executions, ...result.healthyExecutions, ...result.postRestore.executions])
      members.set(ref.path.slice('.artifacts/'.length), Buffer.from(`${JSON.stringify(ref.receipt)}\n`));
  }
  base = {c, original, members};
});

function api(bytes, mutate = () => {}) {
  const run = {id: 3, run_attempt: 4, workflow_id: 2, path: '.github/workflows/ci.yml',
    repository: {id: 1, full_name: 'actql/actql'}, head_repository: {id: 1}, head_sha: revision,
    event: 'workflow_dispatch', head_branch: 'main', status: 'completed', conclusion: 'success'};
  const jobs = {total_count: 1, jobs: [{id: 5, name: 'pipeline-evidence', run_id: 3, run_attempt: 4,
    head_sha: revision, status: 'completed', conclusion: 'success'}]};
  const artifact = {id: 6, expired: false, expires_at: '2050-01-01T00:00:00Z',
    workflow_run: {id: 3, head_sha: revision, repository_id: 1, head_repository_id: 1},
    name: `pipeline-actions-3-4-${revision}`, digest: `sha256:${hash(bytes)}`, size_in_bytes: bytes.length};
  mutate({run, jobs, artifact});
  return async path => {
    if (path === '/actions/runs/3') return structuredClone(run);
    if (path === '/actions/runs/3/attempts/4/jobs?per_page=100') return structuredClone(jobs);
    if (path === '/actions/artifacts/6') return structuredClone(artifact);
    throw new Error(`Unexpected synthetic API path: ${path}`);
  };
}

async function consume(t, {members = base.members, mutateApi, acquisition = 'reused', decision = base.c.decision,
  requestFactory, selectedExpected = expected, requiredConsumer = false, expectedDigest} = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-pipeline-original-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const bytes = storedArchive(members), archive = join(directory, 'original.zip');
  writeFileSync(archive, bytes, {flag: 'wx'});
  const request = api(bytes, mutateApi);
  const options = {archive, artifactId: 6, expected: selectedExpected, expectedDecision: decision,
    tree: base.c.tree, request: requestFactory ? requestFactory(request) : request, acquisition};
  return requiredConsumer ? verifyCurrentMutationActions({...options, context: selectedExpected,
    expectedDigest: expectedDigest ?? hash(bytes)}) : readMutationActionOriginal(options);
}

test('a manual-main original retains its actual certificate and originals without authorizing reuse', async t => {
  const before = [...base.members].map(([path, bytes]) => [path, hash(bytes)]);
  const result = await consume(t);
  assert.deepEqual(result.original, base.original);
  assert.equal(result.authority, 'authenticated-successful-pipeline-job');
  assert.equal(result.acquisition, 'original-not-reused');
  assert.equal(result.reuseAuthorized, false);
  assert.equal(result.original.admission.actions.length, 72);
  assert(result.unresolved.length > 0);
  assert.deepEqual([...base.members].map(([path, bytes]) => [path, hash(bytes)]), before);
});

for (const [name, mutate] of Object.entries({
  wrongAttempt: ({run}) => {run.run_attempt++;}, cancelledRun: ({run}) => {run.conclusion = 'cancelled';},
  failedJob: ({jobs}) => {jobs.jobs[0].conclusion = 'failure';},
  skippedJob: ({jobs}) => {jobs.jobs[0].conclusion = 'skipped';},
  missingJob: ({jobs}) => {jobs.jobs = []; jobs.total_count = 0;},
  foreignJob: ({jobs}) => {jobs.jobs[0].name = 'session-evidence';},
  duplicateJob: ({jobs}) => {jobs.jobs.push({...jobs.jobs[0], id: 10}); jobs.total_count++;},
  incompleteJobs: ({jobs}) => {jobs.total_count++;},
  jobWrongAttempt: ({jobs}) => {jobs.jobs[0].run_attempt++;},
  foreignRepository: ({artifact}) => {artifact.workflow_run.repository_id++;},
  wrongArchiveOwner: ({artifact}) => {artifact.workflow_run.id++;},
  wrongArchiveAttempt: ({artifact}) => {artifact.name = `pipeline-actions-3-5-${revision}`;},
  wrongDigest: ({artifact}) => {artifact.digest = `sha256:${'f'.repeat(64)}`;},
  wrongSize: ({artifact}) => {artifact.size_in_bytes++;},
})) test(`pipeline transport rejects ${name}`, async t => {
  await assert.rejects(consume(t, {mutateApi: mutate}));
});

test('expired/unavailable metadata remains distinct from invalid provenance', async t => {
  await assert.rejects(consume(t, {mutateApi: ({artifact}) => {artifact.expired = true;}}), ArtifactUnavailable);
  await assert.rejects(consume(t, {requestFactory: () => async () => {throw new ArtifactUnavailable();}}), ArtifactUnavailable);
  try {await consume(t, {mutateApi: ({run}) => {run.run_attempt++;}}); assert.fail('accepted foreign attempt');}
  catch (error) {assert.equal(unavailableTransport(error), false);}
});

test('a rerun appearing during authentication rejects the carried owner', async t => {
  let reads = 0;
  await assert.rejects(consume(t, {requestFactory: request => async path => {
    const value = await request(path);
    if (path === '/actions/runs/3' && ++reads > 1) value.run_attempt++;
    return value;
  }}));
  assert.equal(reads, 2);
});

test('a rerun during full member verification invalidates the final required verdict', async t => {
  let reads = 0;
  await assert.rejects(consume(t, {requiredConsumer: true, requestFactory: request => async path => {
    const value = await request(path);
    if (path === '/actions/runs/3' && ++reads === 3) value.run_attempt++;
    return value;
  }}));
  assert.equal(reads, 3);
});

test('the required consumer uses the exact current artifact and reconstructs every fresh obligation', async t => {
  const result = await consume(t, {requiredConsumer: true});
  assert.equal(result.freshActions, 72);
  assert.equal(result.required.length, 72);
  assert.equal(result.applications.length, 72);
  assert(result.applications.every(entry => !entry.reused && entry.origin === revision));
  assert.equal(result.reuseAuthorized, false);
  assert.deepEqual(result.certificate, base.original.admission.certificate);
  await assert.rejects(consume(t, {requiredConsumer: true, expectedDigest: 'f'.repeat(64)}), /Producer\/API archive digest/);
  await assert.rejects(consume(t, {requiredConsumer: true, selectedExpected: {...expected, runAttempt: 99}}));
  await assert.rejects(consume(t, {requiredConsumer: true, selectedExpected: {...expected, candidateRevision: 'b'.repeat(40)}}));
});

test('current required evidence availability is mandatory and distinct from optional main comparison', async t => {
  await assert.rejects(consume(t, {requiredConsumer: true,
    requestFactory: () => async () => {throw new ArtifactUnavailable();}}), ArtifactUnavailable);
  const members = new Map(base.members); members.delete(originalPath);
  await assert.rejects(consume(t, {requiredConsumer: true, members}), /Missing\/oversized/);
});

test('the required consumer refuses a changed plan even in an API-authenticated ZIP', async t => {
  const record = structuredClone(base.original); record.admission.actions.pop();
  const members = new Map(base.members); members.set(originalPath, Buffer.from(`${encode(record)}\n`));
  await assert.rejects(consume(t, {requiredConsumer: true, members}), /plan or scientific/);
});

for (const [name, change] of Object.entries({
  erasedRuntimeGap: record => {record.admission.sourceInputs.unresolved = [];},
  missingAction: record => {record.admission.actions.pop();},
  substitutedScope: record => {record.admission.actions[0].required.scope = 'f'.repeat(64);},
  changedScientificObservation: record => {record.admission.actions[0].scientificDigest = 'f'.repeat(64);},
  changedLeanOutput: record => {record.admission.leanOutput += 'forged';},
  changedCertificateInput: record => {record.admission.certificate.inputDigest = 'f'.repeat(64);},
  unknownField: record => {record.accepted = true;},
})) test(`authenticated ZIP data still rejects ${name}`, async t => {
  const record = structuredClone(base.original); change(record);
  const members = new Map(base.members); members.set(originalPath, Buffer.from(`${encode(record)}\n`));
  await assert.rejects(consume(t, {members}));
});

test('raw receipt/report bytes and independently required exploration cannot be substituted', async t => {
  const first = base.c.reports[0], reportPath = first.path.slice('.artifacts/'.length);
  const receiptPath = first.report.results[0].executions[0].path.slice('.artifacts/'.length);
  for (const path of [reportPath, receiptPath]) {
    const missing = new Map(base.members); missing.delete(path);
    await assert.rejects(consume(t, {members: missing}));
    const changed = new Map(base.members), data = JSON.parse(changed.get(path)); data.revision = 'b'.repeat(40);
    changed.set(path, Buffer.from(`${JSON.stringify(data, null, 2)}\n`));
    await assert.rejects(consume(t, {members: changed}));
  }
  await assert.rejects(consume(t, {decision: {...base.c.decision, required: false}}), /independent exploration/);
});

test('PR evidence can be fresh but cannot become a main original', async t => {
  const record = structuredClone(base.original), head = 'c'.repeat(40);
  Object.assign(record.origin, {event: 'pull_request', branch: 'feature', runHeadRevision: head});
  const members = new Map(base.members); members.set(originalPath, Buffer.from(`${encode(record)}\n`));
  const mutateApi = ({run, jobs, artifact}) => {
    Object.assign(run, {event: 'pull_request', head_branch: 'feature', head_sha: head});
    jobs.jobs[0].head_sha = head; artifact.workflow_run.head_sha = head;
  };
  const selectedExpected = {...expected, runHeadRevision: head};
  const fresh = await consume(t, {members, mutateApi, selectedExpected, acquisition: 'fresh'});
  assert.equal(fresh.reuseAuthorized, false);
  await assert.rejects(consume(t, {members, mutateApi, selectedExpected, acquisition: 'reused'}), /main integration/);
});

test('publication has no API dependency and retains the full audit before an exclusive derived output', () => {
  const script = readFileSync(new URL('./mutation-action-archive.mjs', import.meta.url), 'utf8');
  const cli = script.slice(script.indexOf("if (process.argv[1]"));
  assert(cli.includes("process.env.GITHUB_ACTIONS, 'true'"));
  assert(!cli.includes('request(') && !cli.includes('actionsReader'));
  assert(cli.indexOf('createAudit(root)()') < cli.indexOf('writeFileSync('));
  assert(cli.includes("flag: 'wx'"));
  const workflow = parse(readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const steps = workflow.jobs['pipeline-evidence'].steps;
  const seal = steps.find(step => step.run === 'node proofs/relation-pipeline/mutation-action-archive.mjs seal');
  assert(seal && !seal['continue-on-error']);
  assert(steps.some(step => step.run === 'node proofs/relation-pipeline/capacity/audit.mjs'));
  assert(steps.find(step => step.uses?.startsWith('actions/upload-artifact@')).with.path.includes('.artifacts/pipeline-ci/action-original.json'));
});

test('the workflow binds the small original to the required consumer without changing selection or full diagnostics', () => {
  const workflow = parse(readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const producer = workflow.jobs['pipeline-evidence'], gate = workflow.jobs.check;
  assert.deepEqual(producer.outputs, {'artifact-id': '${{ steps.pipeline-actions.outputs.artifact-id }}',
    'artifact-digest': '${{ steps.pipeline-actions.outputs.artifact-digest }}'});
  const upload = producer.steps.find(step => step.id === 'pipeline-actions');
  assert.equal(upload.with.name, 'pipeline-actions-${{ github.run_id }}-${{ github.run_attempt }}-${{ github.sha }}');
  for (const pattern of ['pipeline-ci/action-original.json', 'relation-pipeline/fixed-mutations-L-M*.json',
    'relation-pipeline/mutations-L-M*.json', 'relation-pipeline/L-M*.json']) assert(upload.with.path.includes(`.artifacts/${pattern}`));
  assert(!upload.with.path.includes('capacity') && !upload.with.path.includes('_build'));
  assert.equal(upload.with['include-hidden-files'], true);
  assert.equal(upload.with['if-no-files-found'], 'error');
  assert(producer.steps.some(step => step.with?.name?.startsWith('relation-pipeline-evidence-') && step.if === 'always()'));
  const consumer = gate.steps.find(step => step.id === 'pipeline-action-check');
  assert.equal(consumer.run, 'node proofs/relation-pipeline/mutation-action-final.mjs');
  assert.equal(consumer.if, "${{ needs.pipeline-evidence.result == 'success' }}");
  assert.equal(consumer.env.PIPELINE_ACTION_ARTIFACT_ID, '${{ needs.pipeline-evidence.outputs.artifact-id }}');
  assert.equal(consumer.env.PIPELINE_ACTION_ARTIFACT_DIGEST, '${{ needs.pipeline-evidence.outputs.artifact-digest }}');
  assert.equal(consumer['continue-on-error'], undefined);
  assert(gate.steps.findIndex(step => step.run === 'node scripts/ci-targets.mjs gate') < gate.steps.indexOf(consumer));
  const retained = gate.steps.find(step => step.with?.name?.startsWith('pipeline-action-acceptance-'));
  assert(retained.if.includes('steps.pipeline-action-check.outcome'));
  assert.equal(retained.with['if-no-files-found'], 'error');
  assert.deepEqual(gate.permissions, {contents: 'read', actions: 'read'});
});

test('scheduled mutation originals retain main-only provenance and the complete action certificate', () => {
  const args = {origin: {...base.original.origin, event: 'schedule'}, source: base.original.source,
    decision: base.original.decision, admission: base.original.admission};
  const scheduled = sealMutationActionOriginal(args);
  assert.equal(scheduled.origin.event, 'schedule');
  assert.deepEqual(scheduled.admission, base.original.admission);
  assert.throws(() => sealMutationActionOriginal({...args, origin: {...args.origin, branch: 'feature'}}));
});
