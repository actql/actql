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
import {sealAcceptance, checkAcceptance, readAcceptance, readyActions, acceptanceName} from './acceptance.mjs';

const jsonBytes = value => Buffer.from(`${encode(value)}\n`);
function fixture() {
  const catalog = readCatalog(); catalog.actions = catalog.actions.filter(action => ['model', 'mutations-js'].includes(action.id));
  catalog.actions.forEach(action => { action.dependencies = []; });
  const context = {repository: 'actql/actql', repositoryId: 1, headRepositoryId: 1, workflowId: 2,
    candidateRevision: 'a'.repeat(40), runHeadRevision: 'a'.repeat(40), runId: 3, runAttempt: 4, ancestors: []};
  const origin = {...context, testedRevision: context.candidateRevision, workflowPath: '.github/workflows/ci.yml',
    event: 'push', branch: 'main', jobId: 5};
  delete origin.candidateRevision; delete origin.ancestors; delete origin.headRepositoryId;
  const files = new Map([...sharedFiles.map(path => [path, path]),
    ...mutationSnapshotExtras.map(path => [path, path]),
    ...['bounded_execution', 'connectors/local', 'query_integration'].map(path => [`src/${path}/moon.pkg`, '']),
    ['src/example/moon.pkg', ''], ['src/example/value.mbt', 'numeric deterministic fixture'],
    ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs', 'mutations.mjs', 'evidence.mjs'].map(name => [`proofs/bounded-session/${name}`, name])]);
  const tree = {entries: new Map([...files].map(([path]) => [path, {kind: 'blob', mode: '100644'}])), read: path => Buffer.from(files.get(path))};
  const required = [], applications = [], receiptDigests = [], members = new Map();
  const scientificDigest = 'e'.repeat(64), sourceArtifact = {id: 6, digest: 'f'.repeat(64)};
  const result = {version: 'actql-verification-family-result/0.1', context, protectedRevision: '0'.repeat(40),
    catalogDigest: hash(encode(catalog)), requiredActions: catalog.actions.map(action => action.id), applications: []};
  for (const action of catalog.actions) {
    const inputs = actionInputs({tree, revision: context.candidateRevision, action, runtime: {profile: 'controlled-test-runtime', unresolved: []}});
    // The deterministic JS observation fixture records all thirteen identities.
    const output = action.id === 'model' ? 'Checked 14 theorems, expected claim types and axiom dependencies\n' :
      ['stale-token-reuse', 'zero-quantum', 'terminal-resume', 'cleanup-changed-as-complete', 'cumulative-as-delta',
        'reset-budget-history', 'accept-backward-work', 'adapter-terminal-resume', 'premature-cleanup-success',
        'cleanup-retry-reruns-callback', 'actual-set-path-reaches-adapter', 'actual-nest-path-reaches-adapter', 'nest-parent-child-ports-swapped']
        .map(id => `${id}: detected by replacement tests`).join('\n');
    const receipt = sealReceipt({origin, action, inputs, output, status: 0, milliseconds: 10});
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
    actions: catalog.actions.map(action => ({actionId: action.id, status: action.id === 'mutations-js' ? 'closed-inputs-match' : 'same-inputs-open'}))};
  const observations = catalog.actions.map(action => ({actionId: action.id,
    status: action.id === 'mutations-js' ? 'scientific-match' : 'counts-match', scientificDigest, originScientificDigest: scientificDigest}));
  const leanOutput = Buffer.from('independent tiny fixture certificate output, no Lean executed locally');
  const lean = {accepted: true, theoremCount: 5, toolchain: 'fixture', inputDigest: hash(leanInput(required, applications)), outputDigest: hash(leanOutput)};
  const certificate = {version: 'actql-verification-family-certificate/0.1', mode: 'scoped-execution', context,
    catalogDigest: result.catalogDigest, receiptDigests, lean,
    comparisonDigest: hash(jsonBytes(comparison)), comparisonObservationsDigest: hash(jsonBytes(observations))};
  members.set('checked.json', jsonBytes(certificate)); members.set('lean-output.log', leanOutput);
  members.set('comparison-plan.json', jsonBytes(comparison)); members.set('comparison-observations.json', jsonBytes(observations));
  result.lean = lean; result.comparison = {baseline: comparison.baseline, confirmation: {status: 'confirmed'}, reuseAuthorized: false,
    recordedStatuses: comparison.actions.map(entry => ({...entry}))};
  const report = sealAcceptance({result, observations, owner: {runId: 3, runAttempt: 4, jobId: 7}, event: 'push', branch: 'main',
    sourceArtifact, certificateDigest: hash(members.get('checked.json'))});
  return {catalog, context, sourceArtifact, report, members,
    sourceZip: {read: async path => { assert(members.has(path), 'Missing actual source member'); return members.get(path); }}};
}

// Independent stored-only ZIP fixture, not an archive writer used by CI.
function zip(members) {
  let offset = 0; const local = [], central = [];
  for (const [path, bytes] of members) {
    const name = Buffer.from(path), data = Buffer.from(bytes); let crc = 0xffffffff;
    for (const byte of data) { crc ^= byte; for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0); }
    crc = (crc ^ 0xffffffff) >>> 0;
    const l = Buffer.alloc(30), c = Buffer.alloc(46);
    l.writeUInt32LE(0x04034b50); l.writeUInt16LE(20, 4); l.writeUInt16LE(0x800, 6);
    l.writeUInt32LE(crc, 14); l.writeUInt32LE(data.length, 18); l.writeUInt32LE(data.length, 22); l.writeUInt16LE(name.length, 26);
    c.writeUInt32LE(0x02014b50); c.writeUInt16LE(0x0314, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0x800, 8);
    c.writeUInt32LE(crc, 16); c.writeUInt32LE(data.length, 20); c.writeUInt32LE(data.length, 24); c.writeUInt16LE(name.length, 28);
    c.writeUInt32LE((0o100644 << 16) >>> 0, 38); c.writeUInt32LE(offset, 42);
    local.push(l, name, data); central.push(c, name); offset += l.length + name.length + data.length;
  }
  const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50); end.writeUInt16LE(members.length, 8); end.writeUInt16LE(members.length, 10);
  end.writeUInt32LE(Buffer.concat(central).length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, ...central, end]);
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

test('the actual acceptance ZIP entrance rejects failed/check owners, wrong attempts, tampered bytes and missing archives', async t => {
  const f = fixture(), directory = await mkdtemp(join(tmpdir(), 'actql-final-acceptance-'));
  t.after(() => rm(directory, {recursive: true}));
  const sourceArchive = join(directory, 'source.zip'), archive = join(directory, 'acceptance.zip');
  // Bind the API to independently written ZIP bytes, not a report's digest.
  const sourceBytes = zip([...f.members]), sourceDigest = hash(sourceBytes);
  await writeFile(sourceArchive, sourceBytes);
  f.sourceArtifact.digest = sourceDigest; f.report.sourceArtifact.digest = sourceDigest;
  f.report.result.applications.forEach(entry => { entry.archiveDigest = sourceDigest; });
  const bytes = zip([['verified-family.json', jsonBytes(f.report)]]); await writeFile(archive, bytes);
  const run = {id: 3, run_attempt: 4, head_sha: f.context.candidateRevision, workflow_id: 2, path: '.github/workflows/ci.yml',
    repository: {id: 1, full_name: 'actql/actql'}, head_repository: {id: 1}, event: 'push', head_branch: 'main', status: 'completed', conclusion: 'success'};
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
  for (const mutate of [
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
