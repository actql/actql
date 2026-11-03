import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';
import {readNativeEffectCaptureProgress} from './fixtures/native-effect-capture-progress.mjs';
import {nativeRuntimeReaderCustodyFixture} from './native-runtime-reader-custody-fixture.mjs';
// This file is selected by the canonical CI lint job. Keep the Native fixture
// and compiler/linker regressions on that existing execution path.
import './native-private-host-fixture.test.mjs';
import './native-sqlite-link-driver.test.mjs';
import './native-signature-linux-declarations.test.mjs';

test('Native Effect capture progress preserves partial evidence without reading private files', async t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-capture-progress-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const suffix of ['preparing-0-0', 'prepared-0-0', 'advancing-1-16', 'advancing-2-32']) {
    mkdirSync(join(root, 'original.review-capture-' + suffix));
  }
  writeFileSync(join(root, 'original.review-capture-completed-4-48'), 'not a phase directory');
  writeFileSync(join(root, 'custody.sqlite3'), 'private original receipt');
  const progress = await readNativeEffectCaptureProgress(root);
  assert.equal(progress.status, 'observed');
  assert.deepEqual(progress.phases.map(({phase, advances, logicalWork}) => ({phase, advances, logicalWork})), [
    {phase: 'preparing', advances: '0', logicalWork: '0'},
    {phase: 'prepared', advances: '0', logicalWork: '0'},
    {phase: 'advancing', advances: '1', logicalWork: '16'},
    {phase: 'advancing', advances: '2', logicalWork: '32'},
  ]);
  assert(!JSON.stringify(progress).includes('private original receipt'));
  assert.equal(readFileSync(join(root, 'custody.sqlite3'), 'utf8'), 'private original receipt');
});

test('Native Effect capture progress does not follow a root or completion-marker symlink', async t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-capture-symlink-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const retained = join(root, 'retained'); const external = join(root, 'external');
  mkdirSync(retained); mkdirSync(external);
  writeFileSync(join(external, 'credential'), 'external secret');
  symlinkSync(external, join(root, 'borrowed-root'), 'dir');
  assert.deepEqual(await readNativeEffectCaptureProgress(join(root, 'borrowed-root')),
    {status: 'unavailable', reason: 'unsafe-root'});
  symlinkSync(external, join(retained, 'original.review-capture-completed-1-16'), 'dir');
  assert.deepEqual(await readNativeEffectCaptureProgress(retained), {status: 'observed', phases: []});
  assert.equal(readFileSync(join(external, 'credential'), 'utf8'), 'external secret');
});

test('Native Effect capture progress missing evidence remains unavailable', async () => {
  assert.deepEqual(await readNativeEffectCaptureProgress(join(tmpdir(), 'absent-actql-capture-' + crypto.randomUUID())),
    {status: 'unavailable', reason: 'collection-failed'});
});

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml',
  import.meta.url), 'utf8'));
const coreStep = workflow.jobs.core.steps.find(step => step.name === 'Test common core');

test('Reader custody injection loads across the selected host helper CPU subtypes', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  // Retain the exact generated library and helper binaries with this new
  // component's evidence. None is an installed runtime or a product profile.
  const scratch = mkdtempSync(join(parent, 'loader-'));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  const source = join(scratch, 'helper.c');
  writeFileSync(source, 'int main(void) { return 0; }\n');
  // Apple's compiler/launcher helpers can use arm64e while the Native test
  // binaries use arm64. Exercise the real loader for both, without changing
  // the product's admitted Darwin arm64 profile or its injection semantics.
  const subtypes = process.platform === 'darwin' ? ['arm64', 'arm64e'] : [undefined];
  for (const subtype of subtypes) {
    const helper = join(scratch, 'helper-' + (subtype ?? process.arch));
    const built = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
      ...(subtype ? ['-arch', subtype] : []), source, '-o', helper], {
      encoding: 'utf8', timeout: 30000,
    });
    assert.equal(built.error, undefined);
    assert.equal(built.signal, null);
    assert.equal(built.status, 0, built.stderr);
    const loaded = spawnSync(helper, [], {encoding: 'utf8', timeout: 10000,
      env: {...process.env, ...injected}});
    assert.equal(loaded.error, undefined);
    assert.equal(loaded.signal, null, loaded.stderr);
    assert.equal(loaded.status, 0, loaded.stderr);
  }
});

test('Reader custody callbacks preserve ordinary FDs and exact pending/acked behavior', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  const scratch = realpathSync(mkdtempSync(join(parent, 'callbacks-')));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  for (const name of ['ordinary.json', 'runtime-constructor-pending/local-runtime.json',
    'runtime-constructor-acked/local-runtime.json']) {
    writeFileSync(join(scratch, name), 'original bounded callback fixture');
  }
  const source = join(scratch, 'callback-helper.c');
  writeFileSync(source, `
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
int main(int argc, char **argv) {
  assert(argc == 2);
  const char *names[] = {"ordinary.json", "runtime-constructor-pending/local-runtime.json",
    "runtime-constructor-acked/local-runtime.json"};
  for (int i = 0; i < 3; i++) {
    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/%s", argv[1], names[i]);
    assert(n > 0 && (size_t)n < sizeof(path));
    int fd = open(path, O_RDONLY); assert(fd >= 0);
    struct stat status; errno = 0;
    int observed = fstat(fd, &status);
    if (i == 0) assert(observed == 0 && S_ISREG(status.st_mode));
    else assert(observed == -1 && errno == EIO);
    assert(fcntl(fd, F_GETFD) >= 0);
    errno = 0;
    int closed = close(fd);
    if (i == 1) assert(closed == -1 && errno == EIO);
    else assert(closed == 0);
    errno = 0;
    assert(fcntl(fd, F_GETFD) == -1 && errno == EBADF);
  }
  puts("reader-callbacks:3");
  return 0;
}
`);
  const subtypes = process.platform === 'darwin' ? ['arm64', 'arm64e'] : [undefined];
  for (const subtype of subtypes) {
    const helper = join(scratch, 'callback-helper-' + (subtype ?? process.arch));
    const built = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
      ...(subtype ? ['-arch', subtype] : []), source, '-o', helper], {
      encoding: 'utf8', timeout: 30000,
    });
    assert.equal(built.error, undefined);
    assert.equal(built.status, 0, built.stderr);
    const observed = spawnSync(helper, [scratch], {encoding: 'utf8', timeout: 10000,
      env: {...process.env, ...injected}});
    writeFileSync(join(scratch, 'callback-' + (subtype ?? process.arch) + '.json'),
      JSON.stringify({status: observed.status, signal: observed.signal,
        stdout: observed.stdout, stderr: observed.stderr}, null, 2) + '\n');
    assert.equal(observed.error, undefined);
    assert.equal(observed.signal, null, observed.stderr);
    assert.equal(observed.status, 0, observed.stderr);
    assert.equal(observed.stdout.trim(), 'reader-callbacks:3');
  }
});

test('Reader custody callbacks preserve the original empty Moon driver command', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  const scratch = realpathSync(mkdtempSync(join(parent, 'driver-')));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  const driver = join(scratch, '__generated_driver_for_internal_test.mbt');
  const metadata = join(scratch, '__internal_test_info.json');
  const command = ['generate-test-driver', '--output-driver', driver,
    '--output-metadata', metadata, '--target', 'native', '--pkg-name',
    'actql/actql', '--driver-kind', 'internal'];
  const observed = spawnSync('moon', command, {cwd: checkout, encoding: 'utf8', timeout: 10000,
    env: {...process.env, ...injected}});
  writeFileSync(join(scratch, 'original-driver-command.json'), JSON.stringify({
    command: ['moon', ...command], status: observed.status, signal: observed.signal,
    stdout: observed.stdout, stderr: observed.stderr}, null, 2) + '\n');
  assert.equal(observed.error, undefined);
  assert.equal(observed.signal, null, observed.stderr);
  assert.equal(observed.status, 0, observed.stderr);
  assert.ok(readFileSync(driver).length > 0);
  assert.doesNotThrow(() => JSON.parse(readFileSync(metadata, 'utf8')));
});

test('Native Core selects the admitted Darwin arm64 runner without dropping target coverage', t => {
  const core = workflow.jobs.core;
  const expression = core['runs-on'];
  assert.equal(expression, "${{ matrix.target == 'native' && 'macos-14' || 'ubuntu-24.04' }}");
  for (const [target, runner] of [['native', 'macos-14'], ['js', 'ubuntu-24.04'],
    ['wasm', 'ubuntu-24.04']]) {
    assert.equal(runInNewContext(expression.slice(3, -2), {matrix: {target}},
      {timeout: 100}), runner);
  }
  assert.equal(core.strategy.matrix.target, '${{ fromJSON(needs.select-targets.outputs.targets) }}');
  assert.equal(core.strategy['fail-fast'], false);
  const platform = core.steps.find(step => step.name === 'Require the supported Core Native platform');
  assert.ok(platform);
  assert.equal(platform.if, "${{ matrix.target == 'native' }}");
  assert.ok(core.steps.indexOf(platform) < core.steps.findIndex(step => step.name === 'Check common core'));
  const root = mkdtempSync(join(tmpdir(), 'actql-native-core-platform-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const uname = join(root, 'uname');
  writeFileSync(uname, '#!/bin/sh\ncase "$1" in\n' +
    '  -s) printf "%s\\n" "$ACTQL_FIXTURE_SYSTEM" ;;\n' +
    '  -m) printf "%s\\n" "$ACTQL_FIXTURE_ARCH" ;;\n' +
    '  *) exit 2 ;;\nesac\n');
  chmodSync(uname, 0o755);
  for (const [system, arch, accepted] of [['Darwin', 'arm64', true],
    ['Darwin', 'x86_64', false], ['Linux', 'aarch64', false], ['Linux', 'x86_64', false]]) {
    const result = spawnSync('bash', ['-eo', 'pipefail', '-c', platform.run], {
      encoding: 'utf8', timeout: 5000,
      env: {...process.env, PATH: root + ':' + process.env.PATH,
        ACTQL_FIXTURE_SYSTEM: system, ACTQL_FIXTURE_ARCH: arch},
    });
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    assert.equal(result.status === 0, accepted, `${system}/${arch}: ${result.stderr}`);
  }
  // The runner keeps both the focused prerequisite and the complete Native
  // campaign. The existing harness selects the original platform libraries.
  assert.match(coreStep.run, /node scripts\/test-native-core\.mjs --deny-warn -p platform_native\/trusted_clock/u);
  assert.match(coreStep.run, /node scripts\/test-native-core\.mjs --deny-warn -j/u);
  assert.doesNotMatch(coreStep.run, /ACTQL_TEST_NATIVE_SQLITE_LIBRARY/u);
});

test('common Core stack prerequisite is confined to Linux Native children', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-stack-scope-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const bin = join(root, 'bin');
  mkdirSync(bin);
  // Observe the real shell limits without launching another Core campaign.
  for (const name of ['node', 'moon']) {
    const command = join(bin, name);
    writeFileSync(command, '#!/bin/sh\nprintf "%s:%s\\n" "$(ulimit -S -s)" "$(ulimit -H -s)"\n');
    chmodSync(command, 0o755);
  }
  for (const target of ['js', 'wasm', 'native']) {
    const hardLimit = spawnSync('bash', ['-c', 'ulimit -H -s'], {
      encoding: 'utf8', timeout: 5000,
    });
    assert.equal(hardLimit.status, 0, hardLimit.stderr);
    const script = 'ulimit -S -s 8192\n' +
      coreStep.run.replaceAll('${{ matrix.target }}', target);
    const result = spawnSync('bash', ['-eo', 'pipefail', '-c', script], {
      cwd: root, encoding: 'utf8', timeout: 5000,
      env: {...process.env, PATH: bin + ':' + process.env.PATH},
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.signal, null);
    const observed = result.stdout.trim().split('\n');
    const expected = target === 'native' && process.platform === 'linux' ? 65536 : 8192;
    // Wasm builds the exported-counter fixture and runs both saved-lookup
    // and original-Source restoration entrance harnesses.
    const invocations = {js: 1, wasm: 4, native: 2}[target];
    assert.deepEqual(observed, Array(invocations)
      .fill(`${expected}:${hardLimit.stdout.trim()}`));
  }
});

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-namespace-test-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const checkout = join(root, 'checkout');
  const parent = join(root, 'sqlite');
  const bin = join(root, 'bin');
  for (const path of [join(checkout, 'scripts'),
    join(checkout, '.github/workflows'), parent, bin]) mkdirSync(path, {recursive: true});
  for (const name of ['test-native-core.mjs', 'native-completed-restoration-fixture.mjs', 'owned-scratch.mjs',
    'native-client-checkpoint-fixture.mjs', 'native-private-host-fixture.mjs',
    'native-filesystem-observation-fixture.mjs',
    'native-runtime-reader-custody-fixture.mjs',
    'local-checks.mjs', 'local-checks-guard.mjs', 'local-checks-supervisor.mjs',
    'local-checks-policy.mjs', 'test-execution.mjs', 'packed-query-evidence.mjs']) {
    copyFileSync(new URL(name, import.meta.url), join(checkout, 'scripts', name));
  }
  mkdirSync(join(checkout, 'scripts/fixtures'));
  copyFileSync(new URL('fixtures/native-unclosed-sqlite.c', import.meta.url),
    join(checkout, 'scripts/fixtures/native-unclosed-sqlite.c'));
  copyFileSync(new URL('fixtures/native-runtime-reader-custody.c', import.meta.url),
    join(checkout, 'scripts/fixtures/native-runtime-reader-custody.c'));
  copyFileSync(new URL('fixtures/native-effect-resolution-fixture.mjs', import.meta.url),
    join(checkout, 'scripts/fixtures/native-effect-resolution-fixture.mjs'));
  symlinkSync(new URL('../node_modules', import.meta.url), join(checkout, 'node_modules'), 'dir');
  writeFileSync(join(checkout, '.github/workflows/ci.yml'),
    JSON.stringify({jobs: {core: {'timeout-minutes': 30, steps: [coreStep]}}}));
  const originals = ['trusted-clock.sqlite', 'trusted-clock.sqlite-wal',
    'trusted-clock.sqlite-shm'];
  for (const name of originals) writeFileSync(join(parent, name), `external ${name}`);
  const moon = join(bin, 'moon');
  writeFileSync(moon, `#!${process.execPath}
const assert = require('node:assert/strict');
const {writeFileSync, existsSync, statSync, readlinkSync} = require('node:fs');
const {createHash, verify} = require('node:crypto');
const {join} = require('node:path');
assert.deepEqual(process.argv.slice(2, 5), ['test', '--target', 'native']);
if (['src/platform_native/client_host/run_checkpoint_wbtest.mbt',
     'src/platform_native/client_host/run_effect_receipt_wbtest.mbt'].some(file => process.argv.includes(file)) &&
    process.argv.includes('--index')) {
  assert.equal(process.env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT, undefined,
    'checkpoint producers must not receive Reader injection');
  assert.equal(process.env.DYLD_INSERT_LIBRARIES, undefined);
  assert.equal(process.env.LD_PRELOAD, undefined);
  const fixed = digit => 'sha256:' + digit.repeat(64);
  console.log('ACTQL_CLIENT_CHECKPOINT ' + JSON.stringify({
    checkpoint_id: 'mock-checkpoint', checkpoint_cid: fixed('1'),
    run_id: 'mock-run', run_definition_cid: fixed('2'),
    required_artifact: {artifact_cid: fixed('3')}, review_projection_cid: fixed('4'),
    requirements: ['effect_scope_approved'], created_at: '2026-10-10T00:00:00.000Z',
  }));
  console.log('Total tests: 1, passed: 1, failed: 0.');
  process.exit(0);
}
const root = process.env.ACTQL_TEST_NATIVE_SQLITE_ROOT;
console.log('CHILD_ROOT=' + root);
if (process.env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT) {
  assert.equal(process.env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT, root);
  for (const name of ['runtime-constructor-pending', 'runtime-constructor-acked']) {
    assert.equal(statSync(join(root, name)).mode & 0o777, 0o700);
  }
  const injected = process.platform === 'darwin'
    ? process.env.DYLD_INSERT_LIBRARIES : process.env.LD_PRELOAD;
  assert.equal(existsSync(injected), true);
}
if (process.argv.some(arg => arg.includes('platform_native/filesystem'))) {
  assert.equal(process.env.ACTQL_TEST_NATIVE_PRIVATE_ROOT, join(root, 'private-host-root'));
  assert.equal(process.env.ACTQL_TEST_NATIVE_BROAD_ROOT, join(root, 'broad-host-root'));
  assert.equal(statSync(process.env.ACTQL_TEST_NATIVE_PRIVATE_ROOT).mode & 0o777, 0o700);
  assert.equal(statSync(process.env.ACTQL_TEST_NATIVE_BROAD_ROOT).mode & 0o777, 0o750);
  assert.equal(readlinkSync(process.env.ACTQL_TEST_NATIVE_PRIVATE_ALIAS), process.env.ACTQL_TEST_NATIVE_PRIVATE_ROOT);
  if (process.platform === 'darwin') {
    assert.equal(process.env.ACTQL_TEST_NATIVE_PRIVATE_ACL_ROOT, join(root, 'private-host-acl'));
    assert.equal(statSync(process.env.ACTQL_TEST_NATIVE_PRIVATE_ACL_ROOT).mode & 0o777, 0o700);
  }
  console.log('PRIVATE_HOST_FIXTURE_PROVISIONED');
}
assert.ok(process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY);
assert.ok(process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY);
assert.equal(process.env.ACTQL_TEST_NATIVE_CRYPTO_MISSING_LIBRARY,
  join(root, 'missing-crypto-library'));
assert.equal(existsSync(process.env.ACTQL_TEST_NATIVE_CRYPTO_MISSING_LIBRARY), false);
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

test('selected Native filesystem provisions owned private-root counterexamples', t => {
  const f = fixture(t);
  const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
    '--deny-warn', 'src/platform_native/filesystem/private_root_wbtest.mbt'],
  {cwd: f.checkout, encoding: 'utf8', env: {...f.env,
    ACTQL_TEST_NATIVE_PRIVATE_ROOT: f.parent}});
  const path = /Native core SQLite namespace: (.*)/u.exec(result.stdout)?.[1];
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /PRIVATE_HOST_FIXTURE_PROVISIONED/u);
  assert.doesNotMatch(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
  assert.ok(path && !existsSync(path));
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

test('owned Native namespace uses its canonical path through a caller parent alias', t => {
  const f = fixture(t);
  const alias = join(f.root, 'sqlite-alias');
  symlinkSync(f.parent, alias, 'dir');
  const result = run(f, {ACTQL_TEST_NATIVE_SQLITE_ROOT: alias});
  assert.equal(result.status, 0, result.stderr);
  const path = /CHILD_ROOT=(.*)/u.exec(result.stdout)?.[1];
  assert.ok(path?.startsWith(join(f.parent, 'native-')),
    'existing-only SQLite must receive the canonical owned directory, not its parent alias');
  assert.equal(result.path, path);
  assert.equal(existsSync(path), false);
  assert.equal(realpathSync(alias), f.parent);
  assert.deepEqual(readdirSync(f.parent).sort(), f.originals.sort());
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
