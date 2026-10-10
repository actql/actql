import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {parse} from 'yaml';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml',
  import.meta.url), 'utf8'));
const coreStep = workflow.jobs.core.steps.find(step => step.name === 'Test common core');

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-namespace-test-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const checkout = join(root, 'checkout');
  const parent = join(root, 'sqlite');
  const bin = join(root, 'bin');
  for (const path of [join(checkout, 'scripts'),
    join(checkout, '.github/workflows'), parent, bin]) mkdirSync(path, {recursive: true});
  for (const name of ['test-native-core.mjs', 'native-completed-restoration-fixture.mjs', 'owned-scratch.mjs',
    'local-checks.mjs', 'local-checks-guard.mjs', 'local-checks-supervisor.mjs',
    'local-checks-policy.mjs', 'test-execution.mjs', 'packed-query-evidence.mjs']) {
    copyFileSync(new URL(name, import.meta.url), join(checkout, 'scripts', name));
  }
  mkdirSync(join(checkout, 'scripts/fixtures'));
  copyFileSync(new URL('fixtures/native-unclosed-sqlite.c', import.meta.url),
    join(checkout, 'scripts/fixtures/native-unclosed-sqlite.c'));
  symlinkSync(new URL('../node_modules', import.meta.url), join(checkout, 'node_modules'), 'dir');
  writeFileSync(join(checkout, '.github/workflows/ci.yml'),
    JSON.stringify({jobs: {core: {'timeout-minutes': 30, steps: [coreStep]}}}));
  const originals = ['trusted-clock.sqlite', 'trusted-clock.sqlite-wal',
    'trusted-clock.sqlite-shm'];
  for (const name of originals) writeFileSync(join(parent, name), `external ${name}`);
  const moon = join(bin, 'moon');
  writeFileSync(moon, `#!${process.execPath}
const assert = require('node:assert/strict');
const {writeFileSync, existsSync, statSync} = require('node:fs');
const {createHash, verify} = require('node:crypto');
const {join} = require('node:path');
assert.deepEqual(process.argv.slice(2, 5), ['test', '--target', 'native']);
const root = process.env.ACTQL_TEST_NATIVE_SQLITE_ROOT;
console.log('CHILD_ROOT=' + root);
assert.ok(process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY);
assert.ok(process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY);
assert.equal(process.env.ACTQL_TEST_NATIVE_STORE_ROOT, undefined,
  'Core must not activate unrelated shared Store fixtures');
assert.equal(process.env.ACTQL_REQUIRE_NATIVE_RETAINED_TEST, '1');
for (const [variable, child] of [
  ['ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT', 'standard'],
  ['ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT', 'bundles'],
  ['ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT', 'executor-slot'],
  ['ACTQL_TEST_NATIVE_RETAINED_TASK_FILE_ROOT', 'retained-task-file'],
]) {
  assert.equal(process.env[variable], join(root, child));
  const info = statSync(process.env[variable]);
  assert.equal(info.isDirectory(), true);
  assert.equal(info.mode & 0o777, 0o700);
}
const body = process.env.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY;
const cid = 'sha256:' + createHash('sha256').update(body).digest('hex');
assert.equal(process.env.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID, cid);
assert.deepEqual(JSON.parse(body), {
  bundle_name: 'native-runtime',
  components: [{bytes: '14',
    cid: 'sha256:' + createHash('sha256').update('native-runtime').digest('hex'),
    role: 'runtime_executable'}],
  connector_registration: 'local', connector_revision: 'local/1',
  issuer_authority: 'bundle-authority-a', revision: 'native/1',
  strategy_revision: 'strategy/1', target_triple: 'aarch64-apple-darwin',
  version: 'actql-remote-runtime-bundle/0.1',
});
assert.equal(verify(null, Buffer.from(
  'actql-remote-runtime-bundle-signature/0.1' + String.fromCharCode(0) +
  cid + String.fromCharCode(0) + body),
  process.env.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY,
  Buffer.from(process.env.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE, 'base64url')), true);
const db = join(root, 'trusted-clock.sqlite');
assert.equal(existsSync(db), false, 'stale lower bound reused');
writeFileSync(db, '1002');
for (const suffix of ['-wal', '-shm']) writeFileSync(db + suffix, 'child');
if (process.env.PROBE_MODE === 'failed') {
  console.error('original native child failure'); process.exit(7);
}
if (process.env.PROBE_MODE === 'signal') process.kill(process.pid, 'SIGTERM');
setTimeout(() => console.log('child stopped'), 100);
`);
  chmodSync(moon, 0o755);
  writeFileSync(join(checkout, 'scripts', 'test-native-salesforce-effect-preview.mjs'), `
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
assert.equal(process.argv[2], '--core-test-json');
const args = JSON.parse(process.argv[3]);
console.log('CORE_TARGET_FIXTURE_PROVISIONED');
const result = spawnSync('moon', ['test', '--target', 'native', ...args], {stdio: 'inherit'});
process.exit(result.status ?? 1);
`);
  const env = {...process.env, PATH: `${bin}:${process.env.PATH}`,
    HOME: root, RUNNER_TEMP: join(root, 'runner'), ACTQL_TEST_NATIVE_SQLITE_ROOT: parent,
    ACTQL_TEST_PRESERVE_SCRATCH: '',
    ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: parent,
    ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT: parent,
    ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT: parent};
  delete env.ACTQL_TEST_NATIVE_STORE_ROOT;
  delete env.NODE_TEST_CONTEXT;
  function verifyExternal() {
    for (const name of originals) {
      assert.equal(readFileSync(join(parent, name), 'utf8'), `external ${name}`);
    }
  }
  return {root, checkout, parent, bin, env, moon, originals, verifyExternal};
}

function run(f, env = {}, local = false) {
  const result = spawnSync(process.execPath, local
    ? ['scripts/local-checks.mjs', 'run', 'core', '--target', 'native', '--allow-heavy']
    : ['scripts/test-native-core.mjs', '--deny-warn', '-p', 'platform_native/trusted_clock'],
  {cwd: f.checkout, encoding: 'utf8', env: {...f.env, ...env}});
  return {...result, path: /Native core SQLite namespace: (.*)/u.exec(result.stdout)?.[1]};
}

test('two local native verification invocations own fresh roots', t => {
  const f = fixture(t);
  const results = [run(f, {}, true), run(f, {}, true)];
  const paths = [];
  for (const result of results) {
    assert.equal(result.status, 0, result.stderr);
    const invocationPaths = [...result.stdout.matchAll(/Native core SQLite namespace: (.*)/gu)]
      .map(match => match[1]);
    assert.equal(invocationPaths.length, 2);
    for (const path of invocationPaths) assert.equal(existsSync(path), false);
    paths.push(...invocationPaths);
    assert.match(result.stdout, /child stopped/u);
    assert.match(result.stdout, /Native core SQLite: removed/u);
    assert.match(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
  }
  assert.equal(new Set(paths).size, 4);
  assert.deepEqual(readdirSync(f.parent).sort(), f.originals.sort());
  f.verifyExternal();
});

test('selected Native tests do not activate the unrelated target fixture', t => {
  const f = fixture(t);
  const result = run(f);
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
  assert.match(result.stdout, /child stopped/u);
  f.verifyExternal();
});

test('Core retained-file fixture never adopts a caller-owned root', t => {
  const f = fixture(t);
  const result = run(f, {ACTQL_TEST_NATIVE_RETAINED_TASK_FILE_ROOT: f.parent});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(result.path), false);
  assert.deepEqual(readdirSync(f.parent).sort(), f.originals.sort());
  f.verifyExternal();
});

test('concurrent invocations never share a SQLite namespace', async t => {
  const f = fixture(t);
  const start = () => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['scripts/test-native-core.mjs'],
      {cwd: f.checkout, env: {...f.env, ACTQL_TEST_PRESERVE_SCRATCH: '1'}});
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; });
    child.stderr.on('data', data => { stderr += data; });
    child.on('error', reject);
    child.on('close', status => resolve({status, stdout, stderr}));
  });
  const results = await Promise.all([start(), start()]);
  const paths = results.map(result => {
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /preservation requested/u);
    const path = /CHILD_ROOT=(.*)/u.exec(result.stdout)?.[1];
    assert.ok(path);
    assert.equal(readFileSync(join(path, 'trusted-clock.sqlite'), 'utf8'), '1002');
    return path;
  });
  assert.notEqual(paths[0], paths[1]);
  f.verifyExternal();
});

for (const mode of ['failed', 'signal']) {
  test(`${mode} child retains its namespace and original failure`, t => {
    const f = fixture(t);
    const result = run(f, {PROBE_MODE: mode});
    assert.equal(result.status, mode === 'failed' ? 7 : 1);
    assert.equal(readFileSync(join(result.path, 'trusted-clock.sqlite'), 'utf8'), '1002');
    assert.match(result.stderr, mode === 'failed' ? /original native child failure/u : /SIGTERM/u);
    assert.match(result.stderr, /test failed; scratch kept:/u);
    assert.doesNotMatch(result.stderr, /cleanup failed/u);
    f.verifyExternal();
  });
}

test('WAL fixture compilation failure stops before Native execution and retains its owned root', t => {
  const f = fixture(t);
  writeFileSync(join(f.checkout, 'scripts/fixtures/native-unclosed-sqlite.c'),
    '#error deliberately invalid fixture\n');
  const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
    '--deny-warn', 'src/platform_native/remote_journal'],
  {cwd: f.checkout, encoding: 'utf8', env: f.env});
  const path = /Native core SQLite namespace: (.*)/u.exec(result.stdout)?.[1];
  assert.equal(result.status, 1);
  assert.ok(path && existsSync(path));
  assert.match(result.stderr, /Native WAL fixture compilation failed/u);
  assert.doesNotMatch(result.stdout, /CHILD_ROOT=/u);
  f.verifyExternal();
});

test('spawn failure retains a diagnosable owned root', t => {
  const f = fixture(t);
  rmSync(f.moon);
  const result = run(f, {PATH: f.bin});
  assert.equal(result.status, 1);
  assert.ok(existsSync(result.path));
  assert.match(result.stderr, /spawnSync moon ENOENT/u);
  assert.match(result.stderr, /scratch kept:/u);
  f.verifyExternal();
});

test('default root is below runner temp and successful child is reaped before cleanup', t => {
  const f = fixture(t);
  delete f.env.ACTQL_TEST_NATIVE_SQLITE_ROOT;
  const result = run(f);
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.path.startsWith(join(f.env.RUNNER_TEMP, 'core-sqlite', 'native-')));
  assert.equal(existsSync(result.path), false);
  assert.ok(result.stdout.indexOf('child stopped') < result.stdout.indexOf('SQLite: removed'));
  f.verifyExternal();
});


test('relative caller roots resolve before changing the child working directory', t => {
  const f = fixture(t);
  const result = spawnSync(process.execPath,
    [join(f.checkout, 'scripts/test-native-core.mjs')], {cwd: f.root,
      encoding: 'utf8', env: {...f.env, ACTQL_TEST_NATIVE_SQLITE_ROOT: 'relative-sqlite'}});
  assert.equal(result.status, 0, result.stderr);
  const path = /CHILD_ROOT=(.*)/u.exec(result.stdout)?.[1];
  assert.ok(path?.startsWith(join(f.root, 'relative-sqlite', 'native-')));
  assert.equal(existsSync(path), false);
  f.verifyExternal();
});

// Check the actual native owner with strict C declarations. Feature selection
// belongs to the source, not a developer's compiler wrapper.
test('native journal inspection declares required interfaces', () => {
  const home = process.env.MOON_HOME;
  assert.ok(home, 'MOON_HOME must select the pinned MoonBit installation');
  const include = join(home, 'include');
  assert.ok(existsSync(join(include, 'moonbit.h')), 'pinned moonbit.h is required');
  const source = fileURLToPath(new URL(
    '../src/platform_native/remote_journal/inspection_stub.c', import.meta.url));
  const result = spawnSync('cc', ['-std=c11', '-fsyntax-only',
    '-Werror=implicit-function-declaration', '-Werror=int-conversion',
    '-I', include, source], {encoding: 'utf8', timeout: 10_000});
  assert.ifError(result.error);
  assert.equal(result.signal, null, result.stderr);
  assert.equal(result.status, 0, result.stderr);
});
