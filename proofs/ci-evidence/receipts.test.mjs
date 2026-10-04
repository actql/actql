import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {readCatalog, catalogPath} from './actions.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {checkApplications} from './applications.mjs';
import {actionInputs, hash, sharedFiles} from './inputs.mjs';
import {sealReceipt, canonicalReceipt, parseReceipt, authenticateOrigin, readOriginReceipt, readOriginReceipts, observationUnits, mutationIds} from './receipts.mjs';

const revision = 'a'.repeat(40), candidate = 'b'.repeat(40);
const action = readCatalog().actions.find(entry => entry.id === 'session-js');
const output = 'Total tests: 7, passed: 7, failed: 0.\n';
const origin = {repository: 'actql/actql', repositoryId: 1, testedRevision: revision,
  runHeadRevision: revision, workflowId: 2, workflowPath: '.github/workflows/ci.yml',
  runId: 3, runAttempt: 4, jobId: 5, event: 'push', branch: 'main'};
const expected = {repository: 'actql/actql', repositoryId: 1, workflowId: 2,
  ancestors: [revision], candidateRevision: candidate, runHeadRevision: 'c'.repeat(40), runId: 30, runAttempt: 1};
function sourceTree(catalog = null) {
  const files = new Map([...sharedFiles.map(path => [path, path]),
    ['src/bounded_execution/moon.pkg', ''], ['src/bounded_execution/session.mbt', 'kernel'],
    ['proofs/bounded-session/a.mjs', 'proof'],
    ...['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs'].map(name => [`proofs/bounded-session/${name}`, name])]);
  if (catalog) files.set(catalogPath, encode(catalog));
  return {entries: new Map([...files].map(([path]) => [path, {kind: 'blob', mode: '100644'}])),
    read: path => Buffer.from(files.get(path))};
}
function inputs(selected = action, rev = revision) {
  return actionInputs({tree: sourceTree(), revision: rev, action: selected,
    runtime: {profile: 'controlled-test-runtime', unresolved: []}});
}
const receipt = () => sealReceipt({origin, action, inputs: inputs(), output, status: 0, milliseconds: 15});

// A small independent stored-only ZIP fixture, never a production ZIP writer.
function zip(members) {
  let offset = 0;
  const local = [], central = [];
  for (const [path, bytes] of members) {
    const name = Buffer.from(path), data = Buffer.from(bytes);
    let crc = 0xffffffff;
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
  const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(members.length, 8); end.writeUInt16LE(members.length, 10);
  end.writeUInt32LE(Buffer.concat(central).length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, ...central, end]);
}

// Metadata comes from this independent API fixture, not from receipt labels.
function api(archiveDigest = '1'.repeat(64), mutate = () => {}) {
  const run = {id: 3, run_attempt: 4, workflow_id: 2, path: '.github/workflows/ci.yml',
    repository: {id: 1, full_name: 'actql/actql'}, head_repository: {id: 1}, head_sha: revision,
    event: 'push', head_branch: 'main', status: 'completed', conclusion: 'success'};
  const jobs = {total_count: 1, jobs: [{id: 5, name: 'session-evidence', run_id: 3, run_attempt: 4,
    head_sha: revision, status: 'completed', conclusion: 'success'}]};
  const artifact = {id: 6, expired: false, expires_at: '2050-01-01T00:00:00Z',
    workflow_run: {id: 3, head_sha: revision, repository_id: 1, head_repository_id: 1},
    name: `session-actions-3-4-${revision}`, digest: `sha256:${archiveDigest}`, size_in_bytes: 500};
  mutate({run, jobs, artifact});
  return async path => {
    if (path === '/actions/runs/3') return structuredClone(run);
    if (path === '/actions/runs/3/attempts/4/jobs?per_page=100') return structuredClone(jobs);
    if (path === '/actions/artifacts/6') return structuredClone(artifact);
    throw new Error(`Unexpected API path ${path}`);
  };
}

test('canonical immutable receipt binds actual command output and independent execution identities', () => {
  const original = receipt();
  assert.deepEqual(parseReceipt(canonicalReceipt(original)), original);
  assert.throws(() => parseReceipt(Buffer.from(JSON.stringify(original))), /Noncanonical/u);
  assert.throws(() => parseReceipt(Buffer.from(`${JSON.stringify(original).replace('"version":', '"version":"forged","version":')}\n`)), /Noncanonical/u);
  assert.throws(() => sealReceipt({origin, action, inputs: inputs(), output, status: 1, milliseconds: 1}), /Failed/u);
  assert.throws(() => sealReceipt({origin, action, inputs: inputs(), output: 'Total tests: 0, passed: 0, failed: 0.\n', status: 0, milliseconds: 1}));
});

test('a completed main origin is authenticated by attempt, job and archive metadata', async () => {
  assert.equal((await authenticateOrigin({receipt: receipt(), artifactId: 6, expected, request: api(), acquisition: 'reused'})).id, 6);
});

for (const [name, mutate] of [
  ['cancelled run', ({run}) => {run.conclusion = 'cancelled';}],
  ['incomplete run', ({run}) => {run.status = 'in_progress'; run.conclusion = null;}],
  ['fork origin', ({run}) => {run.head_repository.id = 7;}],
  ['other workflow', ({run}) => {run.workflow_id = 9;}],
  ['other attempt', ({run}) => {run.run_attempt = 5;}],
  ['failed job', ({jobs}) => {jobs.jobs[0].conclusion = 'failure';}],
  ['mixed job attempt', ({jobs}) => {jobs.jobs[0].run_attempt = 3;}],
  ['truncated jobs', ({jobs}) => {jobs.total_count = 2;}],
  ['expired archive', ({artifact}) => {artifact.expires_at = '2020-01-01T00:00:00Z';}],
  ['wrong artifact attempt', ({artifact}) => {artifact.name = `session-actions-3-3-${revision}`;}],
  ['missing archive digest', ({artifact}) => {delete artifact.digest;}],
  ['other archive repository', ({artifact}) => {artifact.workflow_run.repository_id = 7;}],
]) test(`reject ${name} without satisfying an obligation`, async () => {
  await assert.rejects(authenticateOrigin({receipt: receipt(), artifactId: 6, expected, request: api(undefined, mutate), acquisition: 'reused'}));
});

test('current PR checkout SHA and run HEAD SHA are different independent bindings', async () => {
  const current = receipt();
  current.origin = {...origin, testedRevision: candidate, runHeadRevision: 'c'.repeat(40), event: 'pull_request', branch: 'feature'};
  current.inputs = inputs(action, candidate);
  const request = api(undefined, ({run, jobs, artifact}) => {
    Object.assign(run, {head_sha: 'c'.repeat(40), event: 'pull_request', head_branch: 'feature', status: 'in_progress', conclusion: null});
    jobs.jobs[0].head_sha = 'c'.repeat(40);
    artifact.workflow_run.head_sha = 'c'.repeat(40); artifact.name = `session-actions-3-4-${candidate}`;
  });
  const context = {...expected, runId: 3, runAttempt: 4};
  await authenticateOrigin({receipt: current, artifactId: 6, expected: context, request, acquisition: 'fresh'});
  await assert.rejects(authenticateOrigin({receipt: current, artifactId: 6,
    expected: {...context, candidateRevision: 'c'.repeat(40)}, request, acquisition: 'fresh'}));
  await assert.rejects(authenticateOrigin({receipt: current, artifactId: 6, expected: context, request, acquisition: 'reused'}));
});

test('actual ZIP entrance accepts bound original bytes and rejects missing, tampered and whole-target-swapped evidence', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-action-origin-'));
  try {
    const filename = join(directory, 'origin.zip');
    const normal = receipt();
    const check = async (members, requested = action, archiveDigest) => {
      const bytes = zip(members); await writeFile(filename, bytes);
      return readOriginReceipt({archive: filename, artifactId: 6, action: requested, expected,
        request: api(archiveDigest ?? hash(bytes)), acquisition: 'reused'});
    };
    const members = [['receipts/session-js.json', canonicalReceipt(normal)], ['observations/session-js.log', output]];
    assert.equal((await check(members)).receipt.execution.units, 7);
    await assert.rejects(check(members.slice(0, 1)), /Missing/u);
    await assert.rejects(check([members[0], ['observations/session-js.log', 'forged']]), /wrong artifact size|digest mismatch/ui);
    await assert.rejects(check(members, action, 'f'.repeat(64)), /SHA-256 mismatch/u);
    const native = readCatalog().actions.find(entry => entry.id === 'session-native');
    const other = sealReceipt({origin, action: native, inputs: inputs(native), output, status: 0, milliseconds: 1});
    await assert.rejects(check([['receipts/session-js.json', canonicalReceipt(other)], ['observations/session-native.log', output]]), /target\/scope/u);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('the mutation observation inventory cannot be replaced by thirteen unrelated labels', () => {
  const mutation = readCatalog().actions.find(entry => entry.id === 'mutations-js');
  assert.equal(observationUnits(mutation, mutationIds.map(id => `${id}: detected by replacement tests`).join('\n'), 0), 13);
  assert.throws(() => observationUnits(mutation, mutationIds.map((_, i) => `unrelated-${i}: detected by replacement tests`).join('\n'), 0), /mutation identities/u);
});

test('one archive group authenticates a common owner while retaining each independent target and receipt bytes', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-action-group-'));
  t.after(() => rm(directory, {recursive: true}));
  const filename = join(directory, 'origin.zip');
  const native = readCatalog().actions.find(entry => entry.id === 'session-native');
  const other = sealReceipt({origin, action: native, inputs: inputs(native), output, status: 0, milliseconds: 17});
  const members = [['receipts/session-js.json', canonicalReceipt(receipt())], ['observations/session-js.log', output],
    ['receipts/session-native.json', canonicalReceipt(other)], ['observations/session-native.log', output]];
  const bytes = zip(members); await writeFile(filename, bytes);
  const calls = [], request = api(hash(bytes));
  const options = {archive: filename, artifactId: 6, actions: [action, native], expected, acquisition: 'reused',
    request: async path => { calls.push(path); return request(path); }};
  const result = await readOriginReceipts(options);
  assert.deepEqual([...result.keys()], ['session-js', 'session-native']);
  assert.deepEqual(result.get('session-native').receipt, other);
  assert.equal(result.get('session-js').receiptDigest, hash(members[0][1]));
  assert.equal(result.get('session-native').receiptDigest, hash(members[2][1]));
  assert.equal(calls.filter(path => path.includes('/jobs?')).length, 1);
  assert.equal(calls.filter(path => path === '/actions/artifacts/6').length, 1);
  assert.equal(calls.filter(path => path === '/actions/runs/3').length, 3);
  for (const actions of [[], [action, action]]) await assert.rejects(readOriginReceipts({...options, actions}));

  const wrongOwner = structuredClone(other); wrongOwner.origin.jobId = 99;
  const mixed = zip([...members.slice(0, 2), ['receipts/session-native.json', canonicalReceipt(wrongOwner)], members[3]]);
  await writeFile(filename, mixed);
  await assert.rejects(readOriginReceipts({...options, request: api(hash(mixed))}), /Mixed receipt archive owners/u);
  await writeFile(filename, zip(members.slice(0, 2)));
  await assert.rejects(readOriginReceipts(options), /member not found/u);
});

test('an attempt transition after all grouped member inspections refuses the entire group', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-action-group-transition-'));
  t.after(() => rm(directory, {recursive: true}));
  const filename = join(directory, 'origin.zip');
  const bytes = zip([['receipts/session-js.json', canonicalReceipt(receipt())], ['observations/session-js.log', output]]);
  await writeFile(filename, bytes);
  const request = api(hash(bytes)); let reads = 0;
  await assert.rejects(readOriginReceipts({archive: filename, artifactId: 6, actions: [action], expected, acquisition: 'reused',
    request: async path => {
      const value = await request(path);
      if (path === '/actions/runs/3' && ++reads === 3) value.run_attempt++;
      return value;
    }}));
  assert.equal(reads, 3);
});

test('the actual family application path consumes one authenticated archive without dropping obligations', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-family-group-'));
  t.after(() => rm(directory, {recursive: true}));
  const archive = join(directory, 'origin.zip'), catalog = readCatalog();
  catalog.actions = catalog.actions.filter(value => ['model', 'session-js', 'session-native'].includes(value.id));
  const members = catalog.actions.flatMap(action => {
    const observation = action.id === 'model' ? 'Checked 14 theorems, expected claim types and axiom dependencies\n' : output;
    const original = sealReceipt({origin, action, inputs: inputs(action), output: observation, status: 0, milliseconds: 1});
    return [[`receipts/${action.id}.json`, canonicalReceipt(original)], [`observations/${action.id}.log`, observation]];
  });
  const bytes = zip(members); await writeFile(archive, bytes);
  const request = api(hash(bytes)), calls = [];
  const result = await checkApplications({root: directory, context: expected,
    runtime: {profile: 'controlled-test-runtime', unresolved: []}, protectedRevision: revision,
    entries: catalog.actions.map(action => ({actionId: action.id, acquisition: 'reused', archive, artifactId: 6})),
    treeAt: () => sourceTree(catalog), request: async path => { calls.push(path); return request(path); },
    prove: (required, applications) => {
      assert.deepEqual(required.map(value => value.action), catalog.actions.map(value => value.id));
      assert.deepEqual(applications.map(value => value.target), ['model', 'js', 'native']);
      assert(applications.every(value => value.authenticated && value.successful && value.reused && value.closed));
      return {accepted: true};
    }});
  assert.equal(result.applications.length, 3);
  assert.equal(calls.filter(path => path.includes('/jobs?')).length, 1);
  assert.equal(calls.filter(path => path === '/actions/artifacts/6').length, 1);
});
