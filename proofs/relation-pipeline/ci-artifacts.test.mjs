import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, readdirSync, rmSync,
  symlinkSync, linkSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { parse } from 'yaml';
import { safePath, inventory, validateEnvelope, requiredStages, contextFromEnvironment,
  packArchive, unpackArchive, verifyArchive, joinEvidence } from './ci-artifacts.mjs';
import { body, boundFixture, executionCommand } from './fixture.mjs';

// Only synthetic evidence is used here. Real compiler execution and source,
// semantic, foundation and capacity acceptance remain in the existing gates.
const digest = value => createHash('sha256').update(value).digest('hex');
function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-pipeline-ci-artifacts-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
}
function put(root, path, bytes = path) {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), bytes);
  return join(root, path);
}
function git(root, ...args) {
  const result = spawnSync('git', args, { cwd: root, encoding: 'utf8',
    env: { ...process.env, GIT_AUTHOR_NAME: 'Fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
      GIT_COMMITTER_NAME: 'Fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid' } });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

test('canonical evidence paths are accepted without normalization', () => {
  for (const path of ['current-foundation.json', 'sources/' + 'a'.repeat(64) + '.json',
    'capacity/backing-core/binaries/native/probe.exe', '123-45-0000-normal-js.fixture.mbt']) {
    assert.doesNotThrow(() => safePath(path), path);
  }
});

for (const path of ['', '.', '..', '../outside', 'a/../outside', './report.json',
  '/tmp/outside', 'a//report.json', 'a/./report.json', 'a/', 'a\\report.json',
  'C:/outside', 'report\u0000.json', 'report\n.json', '_build/report', 'a/_build/report',
  'workspaces/report', 'a/workspaces/report', 'node_modules/report', 'a/node_modules/report']) {
  test(`unsafe evidence path is rejected: ${JSON.stringify(path)}`, () => {
    assert.throws(() => safePath(path));
  });
}

test('inventory binds exact file bytes and sizes in deterministic path order', t => {
  const root = scratch(t);
  const files = { 'z.log': Buffer.from('line\n'), 'sources/a.json': Buffer.from('{}\n'),
    'capacity/binaries/native/a': Buffer.from([0, 255, 0, 128]) };
  for (const [path, bytes] of Object.entries(files)) put(root, path, bytes);
  const expected = Object.keys(files).sort().map(path => ({ path, kind: 'file',
    size: files[path].length, sha256: digest(files[path]) }));
  assert.deepEqual(inventory(root), expected);
  put(root, 'z.log', 'other\n');
  assert.notDeepEqual(inventory(root), expected);
});

for (const kind of ['file', 'directory']) {
  test(`inventory rejects a ${kind} symlink instead of following it`, t => {
    const root = scratch(t), evidence = join(root, 'evidence');
    mkdirSync(evidence);
    const target = kind === 'file' ? put(root, 'outside/report.json', '{}') : dirname(put(root, 'outside/report.json', '{}'));
    symlinkSync(target, join(evidence, 'linked'));
    assert.throws(() => inventory(evidence));
  });
}

test('inventory rejects a symbolic-link evidence root', t => {
  const root = scratch(t);
  put(root, 'actual/report.json', '{}');
  symlinkSync(join(root, 'actual'), join(root, 'linked'));
  assert.throws(() => inventory(join(root, 'linked')));
});

test('inventory rejects a hard-linked file and retained workspace contents', t => {
  const root = scratch(t), evidence = join(root, 'evidence');
  const original = put(root, 'outside', 'unchanged');
  mkdirSync(evidence); linkSync(original, join(evidence, 'report.json'));
  assert.throws(() => inventory(evidence));
  rmSync(join(evidence, 'report.json'));
  mkdirSync(join(evidence, 'workspaces'));
  assert.deepEqual(inventory(evidence), [], 'Only the empty scratch parent may remain after successful closure');
  put(evidence, 'workspaces/mutation/source.mbt', 'retained workspace');
  assert.throws(() => inventory(evidence));
});

test('context records the tested checkout and keeps PR head separate from the event SHA', t => {
  const root = scratch(t);
  git(root, 'init', '-q');
  put(root, 'tracked', 'fixture');
  git(root, 'add', 'tracked');
  git(root, 'commit', '-qm', 'Fixture');
  const testedSha = git(root, 'rev-parse', 'HEAD');
  const prHeadSha = 'b'.repeat(40);
  const eventPath = put(root, 'event.json', JSON.stringify({ pull_request: { head: { sha: prHeadSha } } }));
  const env = { GITHUB_REPOSITORY: 'actql/actql', GITHUB_RUN_ID: '12345',
    GITHUB_RUN_ATTEMPT: '2', GITHUB_SHA: testedSha, GITHUB_EVENT_PATH: eventPath };
  const context = contextFromEnvironment(root, env);
  assert.equal(context.repository, 'actql/actql');
  assert.equal(String(context.runId), '12345');
  assert.equal(String(context.runAttempt), '2');
  assert.equal(context.testedSha, testedSha);
  assert.equal(context.prHeadSha, prHeadSha);
  assert.throws(() => contextFromEnvironment(root, { ...env, GITHUB_SHA: prHeadSha }),
    /Checkout is not the actual CI tested SHA/);
});

function envelope(producer = 'mutations') {
  const boundary = { version: 'actql-pipeline-execution-boundary/0.1',
    workspace: 'original-workspace', root: '/home/runner/work/actql/actql', role: 'normal',
    sourceDigest: digest('source'), toolchainDigest: digest('toolchain'), environmentDigest: digest('environment'),
    fixtureDigest: digest('fixture'), target: 'js',
    command: ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt', '--target', 'js', '--deny-warn'] };
  const expected = { producer, context: { repository: 'actql/actql', runId: '12345', runAttempt: '2',
    testedSha: 'a'.repeat(40), prHeadSha: 'b'.repeat(40) },
    source: { digest: boundary.sourceDigest }, foundation: { digest: digest('foundation') },
    exploration: { required: true, reason: 'CI change', paths: ['.github/workflows/ci.yml'],
      revision: 'a'.repeat(40), base: 'c'.repeat(40), classifierDigest: digest('classifier') },
    toolchain: { moonbit: { version: 'fixture-pin', moonc: 'fixture-compiler' }, lean: 'fixture-lean',
      setupDigest: digest('setup'), leanSetupDigest: digest('lean-setup'), node: '22.22.0' } };
  const manifest = { ...structuredClone(expected), schema: 'actql-pipeline-ci-artifact/0.1',
    completedStages: [...requiredStages[producer]],
    restoration: { sourceRestored: true, fixtureClosed: true, workspacesClosed: true },
    files: [{ path: '1790000000000-123-0000-base-js.json', kind: 'file', size: 123, sha256: digest('receipt') }],
    receipts: [{ path: '1790000000000-123-0000-base-js.json', target: 'js', boundary, buildIdentity: digest(JSON.stringify(boundary)) }] };
  return { expected, manifest };
}

for (const producer of ['mutations', 'capacity']) {
  test(`complete ${producer} envelope preserves the original workspace boundary`, () => {
    const { expected, manifest } = envelope(producer), before = structuredClone(manifest);
    assert.deepEqual(validateEnvelope(manifest, expected), manifest);
    assert.deepEqual(manifest, before, 'Validation must not relocate or rewrite evidence');
  });
}

for (const [name, change] of [
  ['unknown schema', m => { m.schema += '-unreviewed'; }],
  ['unreviewed envelope field', m => { m.unreviewed = true; }],
  ['wrong producer', m => { m.producer = 'capacity'; }],
  ['unknown producer', m => { m.producer = 'other'; }],
  ['different repository', m => { m.context.repository = 'other/actql'; }],
  ['different run', m => { m.context.runId = '12346'; }],
  ['different attempt', m => { m.context.runAttempt = '3'; }],
  ['different tested checkout', m => { m.context.testedSha = 'c'.repeat(40); }],
  ['different PR head', m => { m.context.prHeadSha = 'c'.repeat(40); }],
  ['missing context field', m => { delete m.context.prHeadSha; }],
  ['unexpected context field', m => { m.context.branch = 'main'; }],
  ['different source', m => { m.source.digest = digest('other'); }],
  ['different foundation', m => { m.foundation.digest = digest('other'); }],
  ['different exploration decision', m => { m.exploration.required = false; }],
  ['different toolchain', m => { m.toolchain.node = 'different'; }],
  ['missing stage', m => { m.completedStages.pop(); }],
  ['duplicate stage', m => { m.completedStages.push(m.completedStages.at(-1)); }],
  ['reordered stages', m => { m.completedStages.reverse(); }],
  ['unrestored source', m => { m.restoration.sourceRestored = false; }],
  ['open fixture', m => { m.restoration.fixtureClosed = false; }],
  ['open mutation workspaces', m => { m.restoration.workspacesClosed = false; }],
  ['missing restoration claim', m => { delete m.restoration; }],
  ['empty inventory', m => { m.files = []; }],
  ['duplicate inventory path', m => { m.files.push(structuredClone(m.files[0])); }],
  ['unreviewed inventory field', m => { m.files[0].link = '/tmp/other'; }],
  ['link inventory kind', m => { m.files[0].kind = 'symlink'; }],
  ['unsafe inventory path', m => { m.files[0].path = '../outside'; }],
  ['manifest includes itself', m => { m.files[0].path = 'ci-seal.json'; }],
  ['invalid file digest', m => { m.files[0].sha256 = 'a'.repeat(63); }],
  ['negative file size', m => { m.files[0].size = -1; }],
  ['fractional file size', m => { m.files[0].size = 1.5; }],
  ['oversized file', m => { m.files[0].size = 4 * 1024 ** 3 + 1; }],
  ['oversized inventory', m => { m.files = Array.from({ length: 5 }, (_, i) => ({ ...m.files[0], path: `1790000000000-123-000${i}-base-js.json`, size: 4 * 1024 ** 3 })); }],
  ['noncanonical inventory order', m => { m.files.push({ ...m.files[0], path: '100-1-0000-other-js.json' }); }],
  ['empty receipts', m => { m.receipts = []; }],
  ['duplicate receipt', m => { m.receipts.push(structuredClone(m.receipts[0])); }],
  ['receipt absent from inventory', m => { m.receipts[0].path = 'missing.json'; }],
  ['unknown receipt target', m => { m.receipts[0].target = 'other'; }],
  ['unreviewed receipt field', m => { m.receipts[0].unreviewed = true; }],
  ['substituted receipt target', m => { m.receipts[0].target = 'native'; }],
  ['substituted boundary target', m => { m.receipts[0].boundary.target = 'native'; }],
  ['changed workspace identity', m => { m.receipts[0].boundary.workspace = 'another-workspace'; }],
  ['relocated workspace root', m => { m.receipts[0].boundary.root = '/another-runner'; }],
  ['unknown workspace role', m => { m.receipts[0].boundary.role = 'other'; }],
  ['changed build identity', m => { m.receipts[0].buildIdentity = digest('different'); }],
]) {
  test(`producer envelope rejects ${name}`, () => {
    const { manifest, expected } = envelope();
    change(manifest);
    assert.throws(() => validateEnvelope(manifest, expected));
  });
}

for (const [producer, path] of [
  ['mutations', 'capacity/all.json'], ['mutations', 'js.json'],
  ['mutations', 'final-artifacts/native/test.exe'], ['capacity', 'base-js.json'],
  ['capacity', 'fixed-mutations.json'], ['capacity', 'exploration-decision.json'],
  ['mutations', 'unlisted.json'], ['capacity', 'unlisted.json'],
  ['mutations', 'sources/not-a-digest.json'], ['capacity', 'sources/not-a-digest.json'],
]) {
  test(`${producer} envelope rejects unowned payload ${path}`, () => {
    const { manifest, expected } = envelope(producer);
    manifest.files[0].path = path; manifest.receipts[0].path = path;
    assert.throws(() => validateEnvelope(manifest, expected), /outside producer ownership/);
  });
}

// Independent ustar bytes make hostile-path/entry tests exercise the reader,
// rather than relying on the writer to create inputs it is meant to reject.
function tarMember(path, body = Buffer.alloc(0), { type = '0', link = '', size = body.length } = {}) {
  body = Buffer.from(body);
  const header = Buffer.alloc(512);
  const text = (value, start, length) => header.write(value, start, length, 'utf8');
  const octal = (value, start, length) => text(value.toString(8).padStart(length - 1, '0') + '\0', start, length);
  text(path, 0, 100); octal(0o644, 100, 8); octal(0, 108, 8); octal(0, 116, 8);
  octal(size, 124, 12); octal(0, 136, 12); header.fill(32, 148, 156);
  text(type, 156, 1); text(link, 157, 100); text('ustar\0', 257, 6); text('00', 263, 2);
  const checksum = header.reduce((sum, byte) => sum + byte, 0);
  text(checksum.toString(8).padStart(6, '0') + '\0 ', 148, 8);
  return Buffer.concat([header, body, Buffer.alloc((512 - body.length % 512) % 512)]);
}
const tarBytes = (...members) => Buffer.concat([...members, Buffer.alloc(1024)]);

test('archive extraction preserves arbitrary binary bytes at their relative paths', async t => {
  const root = scratch(t), destination = join(root, 'unpacked');
  const bytes = Buffer.from([0, 255, 128, 10, 0]);
  const archive = put(root, 'valid.tar', tarBytes(tarMember('capacity/binaries/native/example', bytes)));
  await unpackArchive(archive, destination);
  assert.deepEqual(readFileSync(join(destination, 'capacity/binaries/native/example')), bytes);
});

for (const [name, members] of [
  ['parent traversal', [tarMember('../outside', Buffer.from('unsafe'))]],
  ['absolute path', [tarMember('/tmp/actql-absolute-path', Buffer.from('unsafe'))]],
  ['nested parent traversal', [tarMember('capacity/../../outside', Buffer.from('unsafe'))]],
  ['backslash path', [tarMember('capacity\\outside', Buffer.from('unsafe'))]],
  ['duplicate regular entries', [tarMember('same.json', Buffer.from('{}')), tarMember('same.json', Buffer.from('{}'))]],
  ['symbolic link', [tarMember('linked', Buffer.alloc(0), { type: '2', link: '../outside' })]],
  ['hard link', [tarMember('original', Buffer.from('bytes')), tarMember('linked', Buffer.alloc(0), { type: '1', link: 'original' })]],
  ['FIFO', [tarMember('fifo', Buffer.alloc(0), { type: '6' })]],
  ['device', [tarMember('device', Buffer.alloc(0), { type: '3' })]],
]) {
  test(`archive rejects ${name}`, async t => {
    const root = scratch(t), archive = put(root, 'hostile.tar', tarBytes(...members));
    const outside = put(root, 'outside', 'unchanged');
    await assert.rejects(async () => unpackArchive(archive, join(root, 'destination')));
    assert.equal(readFileSync(outside, 'utf8'), 'unchanged');
  });
}

test('archive rejects a truncated header, body and end marker', async t => {
  const root = scratch(t);
  const complete = tarBytes(tarMember('report.json', Buffer.from('payload')));
  const fixtures = [Buffer.from('not a tar'), complete.subarray(0, 515), complete.subarray(0, -513)];
  for (const [index, bytes] of fixtures.entries()) {
    const archive = put(root, `truncated-${index}.tar`, bytes);
    await assert.rejects(async () => unpackArchive(archive, join(root, `destination-${index}`)));
  }
});

test('archive rejects a bad checksum and bytes appended after the end marker', async t => {
  const root = scratch(t), good = tarBytes(tarMember('report.json', Buffer.from('{}')));
  const badChecksum = Buffer.from(good); badChecksum[1] ^= 1;
  for (const [index, bytes] of [badChecksum, Buffer.concat([good, Buffer.from('trailing')])].entries()) {
    const archive = put(root, `invalid-${index}.tar`, bytes);
    await assert.rejects(async () => unpackArchive(archive, join(root, `destination-${index}`)));
  }
});

test('archive rejects high-bit path aliases rather than ASCII-decoding them', async t => {
  const root = scratch(t), member = tarMember('a.json', Buffer.from('{}'));
  member[0] |= 128;
  member.fill(32, 148, 156);
  const checksum = member.subarray(0, 512).reduce((sum, byte) => sum + byte, 0);
  member.write(checksum.toString(8).padStart(6, '0') + '\0 ', 148, 8);
  const archive = put(root, 'high-bit.tar', tarBytes(member));
  await assert.rejects(async () => unpackArchive(archive, join(root, 'destination')));
});

test('archive pack and unpack round-trip without restoring a compiler build tree', async t => {
  const root = scratch(t), evidence = join(root, 'evidence'), restored = join(root, 'restored');
  put(evidence, 'report.json', '{}\n');
  put(evidence, 'ci-seal.json', '{}\n');
  put(evidence, 'capacity/binaries/native/example', Buffer.from([0, 255, 128]));
  const archive = join(root, 'evidence.tar');
  await packArchive(evidence, archive);
  await unpackArchive(archive, restored);
  assert.deepEqual(inventory(restored), inventory(evidence));
  assert.deepEqual(readdirSync(restored).sort(), ['capacity', 'ci-seal.json', 'report.json']);
});

test('transport verifies the exact inner digest and sole expected filename before extraction', t => {
  const root = scratch(t), evidence = join(root, 'evidence'), staging = join(root, 'staging');
  put(evidence, 'ci-seal.json', '{}\n'); put(evidence, 'report.json', '{}\n');
  const actual = packArchive(evidence, join(staging, 'evidence.tar'));
  assert.equal(actual, digest(readFileSync(join(staging, 'evidence.tar'))));
  assert.throws(() => verifyArchive(staging, join(root, 'wrong-digest'), '0'.repeat(64)));
  assert.throws(() => verifyArchive(staging, join(root, 'missing-digest'), undefined));
  put(staging, 'unrequested.json', '{}');
  assert.throws(() => verifyArchive(staging, join(root, 'extra'), actual));
  rmSync(join(staging, 'unrequested.json'));
  verifyArchive(staging, join(root, 'valid'), actual);
  assert.deepEqual(inventory(join(root, 'valid')), inventory(evidence));
  assert.throws(() => verifyArchive(staging, join(root, 'valid'), actual), 'Never overwrite an existing extraction');
});

// These minimal reports satisfy only the custody boundary. The existing
// acceptance auditors deliberately remain responsible for semantic coverage.
const canonical = value => JSON.stringify(value, null, 2) + '\n';
function producerFixture(root, producer, expected, mutate = () => {}) {
  const directory = join(root, producer), refs = [];
  const source = { sources: { 'fixture/source.mbt': digest('source bytes') } };
  source.digest = digest(JSON.stringify(source.sources));
  expected.source = { digest: source.digest };
  const foundation = { sourceRevision: expected.context.testedSha, fixture: true };
  expected.foundation = { digest: digest(canonical(foundation)) };
  function json(path, value) { put(directory, path, canonical(value)); }
  json('current-foundation.json', foundation);
  json(`sources/${source.digest}.json`, source);
  put(directory, 'session-model.log', 'shared session model\n');
  put(directory, 'chain-model.log', 'shared chain model\n');
  function execution(label, target, role = 'normal') {
    const stem = `${producer === 'mutations' ? '1790000000000-123' : '1790000000001-456'}-${String(refs.length).padStart(4, '0')}-${label}-${target}`;
    const path = stem + '.json', prefix = '.artifacts/relation-pipeline/';
    const boundary = { version: 'actql-pipeline-execution-boundary/0.1',
      workspace: `${producer}-${role}-workspace`, root: '/home/runner/work/actql/actql', role,
      sourceDigest: source.digest, toolchainDigest: digest(`${producer}-tools`),
      environmentDigest: digest(`${producer}-environment`), fixtureDigest: digest(body), target,
      command: executionCommand(target) };
    const buildIdentity = digest(JSON.stringify(boundary)), fixture = boundFixture(boundary);
    const receipt = { target, boundary, buildIdentity, compiler: expected.toolchain.moonbit.moonc,
      sourceDigest: source.digest, command: executionCommand(target), exit: 0,
      fixtureDigest: digest(fixture), fixturePath: prefix + stem + '.fixture.mbt', logPath: prefix + stem + '.log',
      cases: [{ id: `${producer}:${label}:${target}` }] };
    put(directory, stem + '.fixture.mbt', fixture);
    put(directory, stem + '.log', `ACTQL_PIPELINE_BUILD:${buildIdentity}\nTotal tests: 1, passed: 1, failed: 0.\n`);
    json(path, receipt);
    const ref = { path: prefix + path, digest: digest(JSON.stringify(receipt)), receipt };
    refs.push(ref); return ref;
  }
  const report = { revision: expected.context.testedSha, source, toolchain: expected.toolchain.moonbit };
  if (producer === 'mutations') {
    json('exploration-decision.json', expected.exploration);
    json('base-js.json', { ...report, target: 'js', executions: [execution('base', 'js')] });
    json('fixed-mutations.json', { ...report, decision: expected.exploration,
      results: [{ executions: [execution('fixed', 'js', 'mutable')],
        healthyExecutions: [execution('healthy', 'js', 'pristine')] }] });
    if (expected.exploration.required) json('mutations.json', { ...report, decision: expected.exploration,
      results: [{ executions: [execution('explore', 'js', 'mutable')],
        healthyExecutions: [execution('restored', 'js', 'pristine')] }] });
  } else {
    json('capacity/all.json', { ...report, executions: [execution('capacity', 'js')] });
    for (const target of ['js', 'wasm', 'native']) {
      json(`${target}.json`, { ...report, target, executions: [execution('normal', target)] });
      put(directory, `final-artifacts/${target}/fixture.${target === 'native' ? 'exe' : target}`, Buffer.from([0, 255, 1]));
    }
  }
  mutate({ directory, refs, json });
  const manifest = syntheticSeal(directory, producer, expected, refs);
  return { producer, directory, result: 'success', artifactId: producer === 'mutations' ? '123' : '456',
    artifactDigest: digest(`${producer}-outer`), archiveDigest: digest(`${producer}-inner`),
    manifestDigest: digest(canonical(manifest)) };
}
function syntheticSeal(directory, producer, expected, refs) {
  const manifest = { ...structuredClone(expected), producer, schema: 'actql-pipeline-ci-artifact/0.1',
    completedStages: [...requiredStages[producer]],
    restoration: { sourceRestored: true, fixtureClosed: true, workspacesClosed: true },
    files: inventory(directory, { excludeManifest: true }),
    receipts: refs.map(({ path, receipt }) => ({ path: path.slice('.artifacts/relation-pipeline/'.length),
      target: receipt.target, boundary: receipt.boundary, buildIdentity: receipt.buildIdentity }))
      .sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0) };
  put(directory, 'ci-seal.json', canonical(manifest));
  return manifest;
}
function joinFixture(t, mutate = {}) {
  const root = scratch(t), expected = envelope().expected;
  delete expected.producer;
  const inputs = ['mutations', 'capacity'].map(producer => producerFixture(root, producer, expected, mutate[producer]));
  return { root, expected, inputs, destination: join(root, 'joined') };
}

test('join accepts only the four exact shared paths and preserves relocated read-only evidence', t => {
  const options = joinFixture(t);
  const snapshots = options.inputs.map(input => inventory(input.directory));
  const report = joinEvidence(options);
  assert.equal(report.receiptCount, 9);
  assert.equal(report.observationCount, 9);
  assert.deepEqual(options.inputs.map(input => inventory(input.directory)), snapshots);
  assert.equal(report.fileCount, snapshots.flat().filter(file => file.path !== 'ci-seal.json').length - 4);
  assert.equal(readdirSync(options.destination).includes('_build'), false);
  for (const file of inventory(options.destination)) {
    assert.equal(statSync(join(options.destination, file.path)).mode & 0o222, 0, file.path);
  }
  const fixed = '1790000000000-123-0001-fixed-js.json';
  assert.deepEqual(JSON.parse(readFileSync(join(options.destination, fixed))).boundary,
    JSON.parse(readFileSync(join(options.inputs[0].directory, fixed))).boundary);
});

for (const result of ['failure', 'cancelled', 'skipped', 'in_progress', undefined]) {
  test(`join cannot succeed when a producer is ${result}`, t => {
    const options = joinFixture(t); options.inputs[0].result = result;
    assert.throws(() => joinEvidence(options), /Producer failed, cancelled or skipped/);
  });
}

for (const [name, change] of [
  ['absent producer', o => { o.inputs.pop(); }],
  ['duplicate producer', o => { o.inputs[1].producer = 'mutations'; }],
  ['repeated artifact ID', o => { o.inputs[1].artifactId = o.inputs[0].artifactId; }],
  ['missing artifact ID', o => { delete o.inputs[0].artifactId; }],
  ['multiple artifact IDs', o => { o.inputs[0].artifactId = '123,456'; }],
  ['changed manifest digest', o => { o.inputs[0].manifestDigest = digest('other'); }],
  ['wrong expected attempt', o => { o.expected.context.runAttempt = '3'; }],
  ['wrong expected checkout', o => { o.expected.context.testedSha = 'e'.repeat(40); }],
  ['tampered archived binary', o => { put(o.inputs[1].directory, 'final-artifacts/native/fixture.exe', 'different'); }],
  ['missing input file', o => { rmSync(join(o.inputs[0].directory, '1790000000000-123-0000-base-js.log')); }],
  ['unmanifested input file', o => { put(o.inputs[0].directory, 'extra.json', '{}'); }],
]) {
  test(`join rejects ${name}`, t => {
    const options = joinFixture(t); change(options);
    assert.throws(() => joinEvidence(options));
  });
}

test('join rejects different bytes even at an allowed shared model-log path', t => {
  const options = joinFixture(t, { capacity: ({ directory }) => put(directory, 'session-model.log', 'different model\n') });
  assert.throws(() => joinEvidence(options), /Shared artifact bytes differ/);
});

test('join rejects equal bytes at an unapproved overlapping path', t => {
  const extra = ({ directory }) => put(directory, '1790000000999-999-0000-extra-js.log', '{}');
  const options = joinFixture(t, { mutations: extra, capacity: extra });
  assert.throws(() => joinEvidence(options), /Evidence path collision/);
});

test('join rejects duplicate receipt paths even when their archived bytes match', t => {
  const options = joinFixture(t);
  const path = '1790000000000-123-0000-base-js.json';
  const first = JSON.parse(readFileSync(join(options.inputs[0].directory, path)));
  const capacity = options.inputs[1].directory;
  const ref = { path: '.artifacts/relation-pipeline/' + path, receipt: first, digest: digest(JSON.stringify(first)) };
  for (const path of ['1790000000000-123-0000-base-js.json', '1790000000000-123-0000-base-js.fixture.mbt', '1790000000000-123-0000-base-js.log']) {
    put(capacity, path, readFileSync(join(options.inputs[0].directory, path)));
  }
  const reportPath = join(capacity, 'capacity/all.json');
  const report = JSON.parse(readFileSync(reportPath)); report.executions = [ref];
  writeFileSync(reportPath, canonical(report));
  const refs = [ref, ...['js', 'wasm', 'native'].flatMap(target => JSON.parse(readFileSync(join(capacity, `${target}.json`))).executions)];
  const manifest = syntheticSeal(capacity, 'capacity', options.expected, refs);
  options.inputs[1].manifestDigest = digest(canonical(manifest));
  assert.throws(() => joinEvidence(options), /Receipt path collides across producers/);
});

test('join rejects a reused observation under a different producer receipt path', t => {
  const options = joinFixture(t);
  const directory = options.inputs[1].directory;
  const report = JSON.parse(readFileSync(join(directory, 'capacity/all.json')));
  const ref = report.executions[0]; ref.receipt.cases[0].id = 'mutations:base:js';
  ref.digest = digest(JSON.stringify(ref.receipt));
  put(directory, ref.path.slice('.artifacts/relation-pipeline/'.length), canonical(ref.receipt));
  put(directory, 'capacity/all.json', canonical(report));
  const refs = [ref, ...['js', 'wasm', 'native'].flatMap(target => JSON.parse(readFileSync(join(directory, `${target}.json`))).executions)];
  const manifest = syntheticSeal(directory, 'capacity', options.expected, refs);
  options.inputs[1].manifestDigest = digest(canonical(manifest));
  assert.throws(() => joinEvidence(options), /Observation identity collides across producers/);
});

test('join independently rejects a capacity report claiming another tested revision', t => {
  const options = joinFixture(t, { capacity: ({ directory, json }) => {
    const report = JSON.parse(readFileSync(join(directory, 'capacity/all.json')));
    report.revision = 'f'.repeat(40); json('capacity/all.json', report);
  } });
  assert.throws(() => joinEvidence(options), /Report is not from the tested checkout/);
});

const repositoryRoot = fileURLToPath(new URL('../../', import.meta.url));
const workflow = parse(readFileSync(join(repositoryRoot, '.github/workflows/ci.yml'), 'utf8'));
const { jobs } = workflow;
const producerJobs = ['pipeline-mutations', 'pipeline-capacity'];
const normalSchedule = '${{ !inputs.performance_matrix && !inputs.packed_query_evidence_probe }}';
const runLines = job => jobs[job].steps.filter(step => step.run).flatMap(step => step.run.trim().split('\n'));
const shell = (script, env) => spawnSync('bash', ['-eo', 'pipefail', '-c', script], {
  cwd: repositoryRoot, env: { ...process.env, ...env }, encoding: 'utf8', timeout: 10_000,
});
function successfulNeeds() {
  return Object.fromEntries(producerJobs.map((name, i) => [name, { result: 'success', outputs: {
    'artifact-id': String(100 + i), 'artifact-digest': digest(name + '-outer'),
    'archive-digest': digest(name + '-inner'), 'manifest-digest': digest(name + '-manifest'),
  } }]));
}

test('workflow partitions the existing campaigns without dropping or changing acceptance commands', () => {
  const commands = name => runLines(name).filter(line => /^node (?:--test proofs\/relation-pipeline\/|proofs\/relation-pipeline\/)/u.test(line)
    && !line.startsWith('node proofs/relation-pipeline/ci-artifacts.mjs'));
  assert.deepEqual(commands('pipeline-mutations'), [
    'node proofs/relation-pipeline/history.mjs --write',
    'node --test proofs/relation-pipeline/*.test.mjs proofs/relation-pipeline/capacity/backing/*.test.mjs',
    'node proofs/relation-pipeline/run.mjs js base',
    'node proofs/relation-pipeline/mutations.mjs verify',
  ]);
  assert.deepEqual(commands('pipeline-capacity'), [
    'node proofs/relation-pipeline/history.mjs --write',
    'node proofs/relation-pipeline/capacity/run.mjs all',
    'node proofs/relation-pipeline/capacity/audit.mjs',
    'node proofs/relation-pipeline/capacity/audit-target-regression.mjs',
    'node proofs/relation-pipeline/run.mjs all',
  ]);
  assert.deepEqual(commands('pipeline-evidence'), [
    'node proofs/relation-pipeline/audit.mjs',
    'node proofs/relation-pipeline/audit-target-regression.mjs',
    'node proofs/relation-pipeline/capacity/audit.mjs',
  ]);
  for (const name of producerJobs) {
    assert.equal(jobs[name].if, normalSchedule);
    assert.equal(jobs[name].needs, undefined, 'Producers must remain independently scheduled');
    assert.equal(jobs[name].strategy, undefined, 'A failed sibling must not cancel the other campaign');
    assert.equal(jobs[name]['runs-on'], 'ubuntu-24.04');
    for (const step of jobs[name].steps.filter(step => step.run)) {
      assert.equal(step.if, undefined, 'Campaign and stage commands are unconditional');
      assert.equal(step['continue-on-error'], undefined);
    }
    const role = name.slice('pipeline-'.length);
    const commands = runLines(name);
    assert(commands.indexOf(`node proofs/relation-pipeline/ci-artifacts.mjs begin ${role}`) > commands.indexOf('node proofs/relation-pipeline/history.mjs --write'));
    assert.deepEqual(commands.filter(line => line.includes(`ci-artifacts.mjs stage ${role} `)),
      requiredStages[role].slice(1).map(stage => `node proofs/relation-pipeline/ci-artifacts.mjs stage ${role} ${stage}`));
    assert.equal(commands.at(-1), `node proofs/relation-pipeline/ci-artifacts.mjs seal ${role}`);
  }
});

test('workflow downloads exact producer IDs only after its success and identity guard', () => {
  const final = jobs['pipeline-evidence'];
  assert.deepEqual(final.needs, producerJobs);
  assert.equal(final.if, '${{ always() && !inputs.performance_matrix && !inputs.packed_query_evidence_probe }}');
  assert.deepEqual(final.steps[0].env, { PIPELINE_NEEDS: '${{ toJSON(needs) }}' });
  assert(final.steps[0].run, 'Guard must run before all downloads');
  for (const producer of ['mutations', 'capacity']) {
    const job = jobs[`pipeline-${producer}`];
    const upload = job.steps.find(step => step.id === 'evidence');
    assert.equal(upload.uses, 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02');
    assert.equal(upload.with.path, `.artifacts/pipeline-ci/${producer}/evidence.tar`);
    assert.equal(upload.with.name, `relation-pipeline-${producer}-` + '${{ github.run_id }}-${{ github.run_attempt }}-${{ github.sha }}');
    assert.equal(upload.with['if-no-files-found'], 'error');
    assert.deepEqual(job.outputs, {
      'artifact-id': '${{ steps.evidence.outputs.artifact-id }}',
      'artifact-digest': '${{ steps.evidence.outputs.artifact-digest }}',
      'archive-digest': '${{ steps.seal.outputs.archive-digest }}',
      'manifest-digest': '${{ steps.seal.outputs.manifest-digest }}',
    });
    const download = final.steps.find(step => step.with?.['artifact-ids'] === '${{ needs.pipeline-' + producer + '.outputs.artifact-id }}');
    assert(download, producer);
    assert.equal(download.uses, 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093');
    assert.deepEqual(download.with, { 'artifact-ids': '${{ needs.pipeline-' + producer + '.outputs.artifact-id }}',
      path: '${{ runner.temp }}/pipeline-ci/' + producer, 'merge-multiple': true });
    assert.equal(download.if, undefined);
    assert.equal(download['continue-on-error'], undefined);
  }
  for (const name of [...producerJobs, 'pipeline-evidence']) {
    assert.equal(jobs[name].permissions, undefined);
    assert(!jobs[name].steps.some(step => /cache@/u.test(step.uses ?? '')), 'Producer evidence cannot be restored from a cache');
    const checkout = jobs[name].steps.find(step => step.uses?.startsWith('actions/checkout@'));
    assert.equal(checkout.with['persist-credentials'], false);
    assert.equal(checkout.with['fetch-depth'], 0);
  }
  assert.deepEqual(workflow.permissions, { contents: 'read' });
});

test('workflow producer guard rejects unsuccessful, missing or ambiguous producer identities', () => {
  const script = jobs['pipeline-evidence'].steps[0].run;
  const invoke = needs => shell(script, { PIPELINE_NEEDS: JSON.stringify(needs) });
  const healthy = invoke(successfulNeeds()); assert.equal(healthy.status, 0, healthy.stderr);
  for (const name of producerJobs) {
    for (const result of ['failure', 'cancelled', 'skipped', 'in_progress', undefined]) {
      const needs = successfulNeeds(); needs[name].result = result;
      assert.notEqual(invoke(needs).status, 0, `${name} ${result}`);
    }
    for (const id of ['', '0', '01', '-1', '1,2', '1\n2', '1.2', undefined]) {
      const needs = successfulNeeds(); needs[name].outputs['artifact-id'] = id;
      assert.notEqual(invoke(needs).status, 0, `${name} ${id}`);
    }
    for (const field of ['artifact-digest', 'archive-digest', 'manifest-digest']) {
      const needs = successfulNeeds(); delete needs[name].outputs[field];
      assert.notEqual(invoke(needs).status, 0, `${name} ${field}`);
    }
  }
  const repeated = successfulNeeds();
  repeated['pipeline-capacity'].outputs['artifact-id'] = repeated['pipeline-mutations'].outputs['artifact-id'];
  assert.notEqual(invoke(repeated).status, 0);
  const missing = successfulNeeds(); delete missing['pipeline-capacity'];
  assert.notEqual(invoke(missing).status, 0);
  assert.notEqual(invoke({ ...successfulNeeds(), unexpected: { result: 'success' } }).status, 0);
});

test('global check continues to require the final pipeline-evidence verdict', () => {
  assert(jobs.check.needs.includes('pipeline-evidence'));
  assert(!producerJobs.some(name => jobs.check.needs.includes(name)), 'Final audited join remains the required check boundary');
  const script = jobs.check.steps[0].run;
  const needs = Object.fromEntries(jobs.check.needs.map(name => [name, { result: 'success' }]));
  for (const result of ['failure', 'cancelled', 'skipped']) {
    const child = shell(script, { RESULTS: JSON.stringify({ ...needs, 'pipeline-evidence': { result } }), MACOS_SCHEDULED: 'true' });
    assert.notEqual(child.status, 0, result);
  }
  assert.equal(shell(script, { RESULTS: JSON.stringify(needs), MACOS_SCHEDULED: 'true' }).status, 0);
});
