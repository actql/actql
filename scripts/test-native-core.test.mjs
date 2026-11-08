import './native-http-library-lifetime.test.mjs';
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';
import {readNativeEffectCaptureProgress} from './fixtures/native-effect-capture-progress.mjs';
import {nativeRuntimeReaderCustodyFixture} from './native-runtime-reader-custody-fixture.mjs';
import {failedCoreDriver, diagnoseFailedCoreDriver} from './native-compiler-stop-diagnostic.mjs';
import {runFocusedTests} from './test-execution.mjs';
import {nativeCorePartitionProfiles} from './native-core-test-selection.mjs';
// This file is selected by the canonical CI lint job. Keep the Native fixture
// and compiler/linker regressions on that existing execution path.
import './native-private-host-fixture.test.mjs';
import './native-runtime-bundle-fixture.test.mjs';
import './native-sqlite-link-driver.test.mjs';
import './native-signature-linux-declarations.test.mjs';
import './native-core-progress.test.mjs';
import './native-core-c-compiler.test.mjs';
import './native-core-test-selection.test.mjs';
import './native-core-scoped-profile.test.mjs';
import './native-core-scoped-fixture.test.mjs';
import './native-core-relation-work-fixture.test.mjs';
import './native-process-region-fixture.test.mjs';
import './native-project-configuration-fixture.test.mjs';

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

test('Reader custody injection loads on the supported Native host profile', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  // Retain the exact generated library and helper binaries with this new
  // component's evidence. None is an installed runtime or a product profile.
  const scratch = mkdtempSync(join(parent, 'loader-'));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  const source = join(scratch, 'helper.c');
  writeFileSync(source, 'int main(void) { return 0; }\n');
  // The existing Core profile requires Darwin arm64. Extra injected-library
  // slices are checked against the actual pinned tools below; a standalone
  // experimental arm64e executable is not a substitute for those binaries.
  const subtypes = process.platform === 'darwin' ? ['arm64'] : [undefined];
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
    for (const root of [undefined, 'relative-root', '/' + 'x'.repeat(8192)]) {
      const env = {...process.env, ...injected};
      if (root === undefined) delete env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT;
      else env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT = root;
      const invalid = spawnSync(helper, [], {encoding: 'utf8', timeout: 10000, env});
      assert.equal(invalid.error, undefined);
      assert.notEqual(invalid.status, 0, 'invalid constructor scope was treated as an ordinary loaded fixture');
    }
  }
});

test('Reader custody hooks retain the startup paths across a fork and later environment changes', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  const scratch = realpathSync(mkdtempSync(join(parent, 'captured-root-')));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  const original = join(scratch, 'runtime-constructor-pending/local-runtime.json');
  writeFileSync(original, 'same original read-only fixture');
  const source = join(scratch, 'captured-root.c');
  writeFileSync(source, `
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
int main(int argc, char **argv) {
  assert(argc == 2);
  int descriptor = open(argv[1], O_RDONLY); assert(descriptor >= 0);
  assert(setenv("ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT", "/foreign-root", 1) == 0);
  pid_t child = fork(); assert(child >= 0);
  if (child == 0) {
    struct stat status;
    errno = 0; assert(fstat(descriptor, &status) == -1 && errno == EIO);
    assert(fcntl(descriptor, F_GETFD) >= 0);
    errno = 0; assert(close(descriptor) == -1 && errno == EIO);
    errno = 0; assert(fcntl(descriptor, F_GETFD) == -1 && errno == EBADF);
    _exit(0);
  }
  int status; assert(waitpid(child, &status, 0) == child);
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
  errno = 0; assert(close(descriptor) == -1 && errno == EIO);
  errno = 0; assert(fcntl(descriptor, F_GETFD) == -1 && errno == EBADF);
  return 0;
}
`);
  const helper = join(scratch, 'captured-root');
  const built = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    source, '-o', helper], {encoding: 'utf8', timeout: 30000});
  assert.equal(built.status, 0, built.stderr);
  const observed = spawnSync(helper, [original], {encoding: 'utf8', timeout: 10000,
    env: {...process.env, ...injected}});
  assert.equal(observed.error, undefined);
  assert.equal(observed.signal, null, observed.stderr);
  assert.equal(observed.status, 0, observed.stderr);
});

test('Reader custody callbacks preserve the pinned Moon nested Native compiler and executed test', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  const scratch = realpathSync(mkdtempSync(join(parent, 'nested-moon-')));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  const project = join(scratch, 'project');
  mkdirSync(join(project, 'src'), {recursive: true});
  writeFileSync(join(project, 'moon.mod'), 'name = "fixture/reader-custody"\nsource = "src"\npreferred_target = "native"\n');
  writeFileSync(join(project, 'src/moon.pkg'), '\n');
  writeFileSync(join(project, 'src/main_test.mbt'),
    'test "original nested Native compiler" { assert_eq(1, 1) }\n');
  assert.equal(runFocusedTests('moon', ['--target', 'native', '--deny-warn', '-j', '3', '--verbose'],
    {cwd: project, env: {...process.env, ...injected}, timeout: 30000,
      evidenceScratch: join(scratch, 'command-evidence')}), 0);
});

test('Reader custody callbacks preserve Linux x64 dependency constructors before its fixture scope exists',
  {skip: process.platform !== 'linux' || process.arch !== 'x64'}, () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  const scratch = realpathSync(mkdtempSync(join(parent, 'early-constructor-')));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  const earlySource = join(scratch, 'early.c');
  const mainSource = join(scratch, 'main.c');
  writeFileSync(earlySource, `
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
static int observed;
__attribute__((constructor)) static void early(void) {
  struct stat status;
  errno = 0;
  if (fstat(-1, &status) != -1 || errno != EBADF) _exit(81);
  errno = 0;
  if (close(-1) != -1 || errno != EBADF) _exit(82);
  int fd = open("/dev/null", O_RDONLY);
  if (fd < 0 || fstat(fd, &status) != 0 || !S_ISCHR(status.st_mode)) _exit(83);
  if (close(fd) != 0) _exit(84);
  observed = 1;
}
int early_observed(void) { return observed; }
`);
  writeFileSync(mainSource,
    'extern int early_observed(void); int main(void) { return early_observed() == 1 ? 0 : 85; }\n');
  const earlyLibrary = join(scratch, 'libearly.so');
  const preload = join(scratch, 'early-reader-custody.so');
  const helper = join(scratch, 'early-helper');
  const flags = ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror'];
  const linkEarly = ['-L', scratch, '-Wl,--no-as-needed', '-learly', '-Wl,-rpath,' + scratch];
  for (const args of [
    [...flags, '-shared', '-fPIC', earlySource, '-o', earlyLibrary],
    // A direct dependency must initialize before the preloaded fixture. This
    // reproduces the real compiler DSO ordering without relying on its internals.
    [...flags, '-shared', '-fPIC', join(checkout, 'scripts/fixtures/native-runtime-reader-custody.c'),
      ...linkEarly, '-ldl', '-o', preload],
    [...flags, mainSource, ...linkEarly, '-o', helper],
  ]) {
    const built = spawnSync('cc', args, {encoding: 'utf8', timeout: 30000});
    assert.equal(built.error, undefined);
    assert.equal(built.signal, null, built.stderr);
    assert.equal(built.status, 0, built.stderr);
  }
  const observed = spawnSync(helper, [], {encoding: 'utf8', timeout: 10000,
    env: {...process.env, ...injected, LD_PRELOAD: preload}});
  assert.equal(observed.error, undefined);
  assert.equal(observed.signal, null, observed.stderr);
  assert.equal(observed.status, 0, observed.stderr);
});

test('Reader custody callbacks preserve ordinary FDs and exact pending/acked behavior', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  const scratch = realpathSync(mkdtempSync(join(parent, 'callbacks-')));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  if (process.platform === 'darwin') {
    const library = spawnSync('xcrun', ['lipo', '-archs', injected.DYLD_INSERT_LIBRARIES],
      {encoding: 'utf8', timeout: 10000});
    assert.equal(library.status, 0, library.stderr);
    const available = library.stdout.trim().split(/\s+/u);
    assert(available.includes('arm64') && available.includes('arm64e'));
    for (const name of ['moon', 'moonc']) {
      const tool = join(process.env.MOON_HOME, 'bin', name);
      const image = spawnSync('xcrun', ['lipo', '-archs', tool],
        {encoding: 'utf8', timeout: 10000});
      assert.equal(image.status, 0, image.stderr);
      const required = image.stdout.trim().split(/\s+/u);
      assert(required.includes('arm64'), `${name}: ${image.stdout}`);
      assert(required.every(subtype => available.includes(subtype)), `${name}: ${image.stdout}`);
      process.stdout.write(`# Reader custody pinned ${name} image slices: ${required.join(',')}\n`);
    }
  }
  for (const name of ['ordinary.json', 'runtime-constructor-pending/local-runtime.json',
    'runtime-constructor-acked/local-runtime.json']) {
    writeFileSync(join(scratch, name), 'original bounded callback fixture');
  }
  const source = join(scratch, 'callback-helper.c');
  writeFileSync(source, `
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
int main(int argc, char **argv) {
  assert(argc == 3);
  int injected = strcmp(argv[2], "injected") == 0;
  assert(injected || strcmp(argv[2], "ordinary") == 0);
  const char *names[] = {"ordinary.json", "runtime-constructor-pending/local-runtime.json",
    "runtime-constructor-acked/local-runtime.json"};
  for (int i = 0; i < 3; i++) {
    char path[PATH_MAX];
    int n = snprintf(path, sizeof(path), "%s/%s", argv[1], names[i]);
    assert(n > 0 && (size_t)n < sizeof(path));
    int fd = open(path, O_RDONLY); assert(fd >= 0);
    struct stat status; errno = 0;
    int observed = fstat(fd, &status);
    if (i == 0 || !injected) assert(observed == 0 && S_ISREG(status.st_mode));
    else assert(observed == -1 && errno == EIO);
    assert(fcntl(fd, F_GETFD) >= 0);
    errno = 0;
    int closed = close(fd);
    if (i == 1 && injected) assert(closed == -1 && errno == EIO);
    else assert(closed == 0);
    errno = 0;
    assert(fcntl(fd, F_GETFD) == -1 && errno == EBADF);
  }
  puts("reader-callbacks:3");
  return 0;
}
`);
  // The existing Core job requires Darwin arm64. A standalone arm64e user
  // executable is a different diagnostic, not that product profile. Keep both
  // injected-library slices for the actual pinned tools, checked above and by
  // their original entrypoints below; retain every required physical FD check.
  const subtypes = process.platform === 'darwin' ? ['arm64'] : [undefined];
  for (const subtype of subtypes) {
    const helper = join(scratch, 'callback-helper-' + (subtype ?? process.arch));
    const built = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
      ...(subtype ? ['-arch', subtype] : []), source, '-o', helper], {
      encoding: 'utf8', timeout: 30000,
    });
    assert.equal(built.error, undefined);
    assert.equal(built.status, 0, built.stderr);
    // Distinguish the selected executable ABI from the injected callbacks.
    // Both runs use these same original files and actual descriptor assertions.
    const control = spawnSync(helper, [scratch, 'ordinary'], {
      encoding: 'utf8', timeout: 10000, env: process.env,
    });
    writeFileSync(join(scratch, 'callback-control-' + (subtype ?? process.arch) + '.json'),
      JSON.stringify({subtype: subtype ?? process.arch, status: control.status,
        signal: control.signal, stdout: control.stdout, stderr: control.stderr}, null, 2) + '\n');
    assert.equal(control.error, undefined);
    assert.equal(control.signal, null, `${subtype ?? process.arch} control: ${control.stderr}`);
    assert.equal(control.status, 0, `${subtype ?? process.arch} control: ${control.stderr}`);
    assert.equal(control.stdout.trim(), 'reader-callbacks:3');
    process.stdout.write(`# Reader custody injected callback: ${subtype ?? process.arch}\n`);
    const observed = spawnSync(helper, [scratch, 'injected'], {encoding: 'utf8', timeout: 10000,
      env: {...process.env, ...injected}});
    writeFileSync(join(scratch, 'callback-' + (subtype ?? process.arch) + '.json'),
      JSON.stringify({status: observed.status, signal: observed.signal,
        stdout: observed.stdout, stderr: observed.stderr}, null, 2) + '\n');
    assert.equal(observed.error, undefined);
    assert.equal(observed.signal, null, `${subtype ?? process.arch}: ${observed.stderr}`);
    assert.equal(observed.status, 0, `${subtype ?? process.arch}: ${observed.stderr}`);
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

test('Reader custody callbacks preserve the original pinned Moonc loader', () => {
  const checkout = fileURLToPath(new URL('../', import.meta.url));
  const parent = join(checkout, '_build', 'native-reader-helper-tests');
  mkdirSync(parent, {recursive: true});
  const scratch = realpathSync(mkdtempSync(join(parent, 'compiler-loader-')));
  const injected = nativeRuntimeReaderCustodyFixture(checkout, scratch);
  const tool = join(process.env.MOON_HOME, 'bin', 'moonc');
  const observed = spawnSync(tool, ['-v'], {cwd: checkout, encoding: 'utf8', timeout: 10000,
    env: {...process.env, ...injected}});
  assert.equal(observed.error, undefined);
  assert.equal(observed.signal, null, observed.stderr);
  assert.equal(observed.status, 0, observed.stderr);
  assert.match(observed.stdout.trim(), /^v[0-9]+\.[0-9]+\.[0-9]+/u);
});

test('Native Core full campaign remains selected after callback diagnosis failure', () => {
  const core = workflow.jobs.core;
  const start = core.steps.findIndex(step => step.id === 'native-compiler-diagnostic-start');
  const campaign = core.steps.indexOf(coreStep);
  assert.deepEqual(core.steps.slice(start + 1, campaign).map(step => step.name),
    ['Test actual Native Reader callbacks and original empty compiler driver']);
  assert.equal(core['continue-on-error'], undefined);
  assert.equal(core.steps[start + 1]['continue-on-error'], undefined);
  assert.equal(coreStep['continue-on-error'], undefined);
  assert.equal(typeof coreStep.if, 'string');
  const expression = coreStep.if.trim().slice(3, -2);
  for (const [target, previousSuccess, startOutcome, cancelled, expected] of [
    ['native', true, 'success', false, true],
    ['native', false, 'success', false, true],
    ['native', false, 'skipped', false, false],
    ['native', false, 'failure', false, false],
    ['native', false, 'success', true, false],
    ['js', true, 'skipped', false, true],
    ['js', false, 'skipped', false, false],
    ['wasm', true, 'skipped', false, true],
    ['wasm', false, 'skipped', false, false],
  ]) {
    const selected = runInNewContext(expression, {matrix: {target},
      steps: {'native-compiler-diagnostic-start': {outcome: startOutcome}},
      success: () => previousSuccess && !cancelled, cancelled: () => cancelled},
    {timeout: 100});
    assert.equal(selected, expected, `${target}/${previousSuccess}/${startOutcome}/${cancelled}`);
  }
});

test('Native partition caller passes the complete compiler inventory before selecting the original profile', () => {
  const source = readFileSync(new URL('test-native-core.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('const selection = full ? nativeCoreTestSelection');
  const end = source.indexOf('if (selection) console.log', start);
  assert(start >= 0 && end > start);
  const parts = [{args: ['src/a'], cases: 2}, {args: ['src/b'], cases: 3}];
  const profiles = {ordinary: {cases: 5, partitions: parts},
    http: {args: ['src/http'], cases: 1}, source: {args: ['src/source'], cases: 1},
    scoped: {args: ['src/scoped'], cases: 1, tests: []}};
  for (const partition of ['1/2', '2/2']) {
    let discoveries = 0;
    const args = ['--release', '--strip'], env = {original: true};
    const selected = runInNewContext(source.slice(start, end) + '\nselection;', {
      full: true, root: '/original', args, compilerEnvironment: env, partition, executionPackages: undefined,
      nativeCorePartitionProfiles,
      nativeCoreTestSelection(root, originalArgs, options) {
        discoveries++;
        assert.equal(root, '/original'); assert.equal(originalArgs, args);
        assert.equal(options.env, env); assert.equal(options.partitionProfiles, true);
        assert.equal(options.ordinaryPartitions, true);
        assert.equal(options.timeoutMs, 300_000);
        assert.equal(options.executionPackages, undefined, 'Unscoped local fixture retains the complete inventory');
        return {profiles};
      }, console: {log() {}},
    });
    assert.equal(discoveries, 1);
    assert.equal(selected.profiles.ordinary, parts[Number(partition[0]) - 1]);
    assert.equal(selected.profiles.http.args === null, partition === '2/2');
  }
});

test('Native partition target oracle keeps original mandatory requests once and refuses every sibling request', () => {
  const source = readFileSync(new URL('test-native-salesforce-effect-preview.mjs', import.meta.url), 'utf8');
  const begin = source.indexOf('const corePartition = process.env.ACTQL_TEST_NATIVE_CORE_PARTITION;');
  const end = source.indexOf('// The complete file has', begin);
  const startOracle = source.indexOf('  assert.equal(code, 0, `Native target observation failed:');
  const endOracle = source.indexOf('  console.log(`Native Salesforce target observation receipt:', startOracle);
  assert(begin >= 0 && end > begin && startOracle >= 0 && endOracle > startOracle);
  const expected = '/services/data/v66.0/sobjects/ActQL_Test_Record__c/';
  const originalPaths = [
    ...['001', '001', '002'].map(id => ({method: 'GET', path: expected + '001000000000' + id})),
    ...['001', '002', '003'].map(id => ({method: 'PATCH', path: expected + '001000000000' + id})),
  ];
  const check = (partition, selected, changes = {}) => {
    const context = {assert, process: {env: {ACTQL_TEST_NATIVE_CORE_PARTITION: partition}},
      coreArgs: selected ? ['src/platform_native/salesforce_effect_preview/native_test'] : ['src/other'],
      residentProposals: false, originalLocalReview: false, directLocalClaimCustody: false,
      residentMappedCreate: false, residentOriginalHolder: false,
      code: 0, signal: null, expected, paths: selected ? originalPaths : [],
      writes: selected ? 2 : 0, rejectedWrites: selected ? 1 : 0,
      writeBodies: Array(selected ? 2 : 0).fill('{"Optional_Value__c":"new"}'),
      resolutionRequests: 0, reviewUploads: 0, checkpointReportRequests: 0, ...changes};
    // Values inside the actual assertion body belong to its VM realm.
    const body = 'const paths=JSON.parse(pathsWire), writeBodies=JSON.parse(bodiesWire);\n' +
      source.slice(begin, end) + source.slice(startOracle, endOracle);
    const pathsWire = JSON.stringify(context.paths), bodiesWire = JSON.stringify(context.writeBodies);
    delete context.paths; delete context.writeBodies;
    return runInNewContext(body, {...context, pathsWire, bodiesWire});
  };
  for (const partition of ['1/2', '2/2']) {
    assert.doesNotThrow(() => check(partition, true));
    assert.doesNotThrow(() => check(partition, false));
    assert.throws(() => check(partition, true, {writes: 0, rejectedWrites: 0, writeBodies: [], paths: []}));
    assert.throws(() => check(partition, false, {writes: 1}));
    assert.throws(() => check(partition, false, {paths: [originalPaths[0]]}));
    assert.throws(() => check(partition, false, {code: 7}));
  }
  assert.throws(() => check('3/3', false), /original selected case inventory/u);
});

test('Native partition marker reaches only its ordinary oracle and never other fixture or compiler children', () => {
  const source = readFileSync(new URL('test-native-core.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('  const runProfile = (profile, environment) => {');
  const end = source.indexOf('  // The Source package', start);
  assert(start >= 0 && end > start);
  for (const partition of ['1/2', '2/2']) {
    const process = {env: {ACTQL_TEST_NATIVE_CORE_PARTITION: partition, original: 'preserved'}, execPath: '/node'};
    const compilerLine = source.match(/^const compilerEnvironment = .+;$/mu)?.[0];
    assert(compilerLine);
    const compiler = runInNewContext(compilerLine + '\ncompilerEnvironment;', {process, testCompiler: {PATH: '/original-compiler'}});
    assert.equal(compiler.ACTQL_TEST_NATIVE_CORE_PARTITION, undefined);
    const beforeFixture = source.indexOf('const fixtureEnvironment = {');
    const afterFixture = source.indexOf('  // A full selection', beforeFixture);
    assert(beforeFixture >= 0 && afterFixture > beforeFixture);
    const fixtureEnvironment = runInNewContext(source.slice(beforeFixture, afterFixture) + '\n};\nfixtureEnvironment;', {process});
    assert.equal(fixtureEnvironment.ACTQL_TEST_NATIVE_CORE_PARTITION, undefined);
    assert.equal(fixtureEnvironment.original, 'preserved');
    const original = {args: ['--release', 'src/selected'], cases: 3};
    let calls = 0;
    runInNewContext(source.slice(start, end), {
      process, root: '/original', fixtureEnvironment, ordinaryProcess: {physical: 'original'},
      testCompiler: {PATH: '/original-compiler'}, partition,
      selection: {profiles: {ordinary: original}}, console: {log() {}}, checkChild() {},
      spawnSync(command, args, options) {
        calls++;
        assert.equal(command, '/node'); assert.equal(args[0], 'scripts/test-native-salesforce-effect-preview.mjs');
        assert.deepEqual(JSON.parse(args[2]), original.args); assert.equal(args[4], '3');
        assert.equal(options.env.ACTQL_TEST_NATIVE_CORE_PARTITION, partition);
        assert.equal(options.env.physical, 'original'); assert.equal(options.env.PATH, '/original-compiler');
        return {status: 0};
      },
    });
    assert.equal(calls, 1);
  }
});

test('Compiler stop diagnostic requires the actual failed blackbox input', () => {
  const driver = failedCoreDriver('/checkout', '/pinned');
  const line = 'failed: /pinned/bin/moon generate-test-driver --output-driver ' +
    '/checkout/_build/native/debug/test/__generated_driver_for_blackbox_test.mbt ' +
    '--output-metadata /checkout/_build/native/debug/test/__blackbox_test_info.json ' +
    '/checkout/src/environment_test.mbt --target native --pkg-name actql/actql --driver-kind blackbox';
  driver.write(line.replace('blackbox', 'internal') + '\n');
  assert.equal(driver.observed, false);
  driver.write(line.slice(0, 30));
  driver.write('unrelated partial stdout', 'stdout');
  driver.write(line.slice(30) + '\n');
  assert.equal(driver.observed, true);
});

test('Compiler stop diagnostic refuses unobserved failure without a child', () => {
  let calls = 0;
  const result = diagnoseFailedCoreDriver({driver: failedCoreDriver('/checkout', '/pinned')},
    () => { calls++; });
  assert.equal(calls, 0);
  assert.deepEqual(result, {attempted: false, cause: 'original-failure-not-observed'});
});

test('Compiler stop diagnostic preserves inputs and private environment with fresh outputs', t => {
  const namespace = mkdtempSync(join(tmpdir(), 'actql-compiler-stop-control-'));
  t.after(() => rmSync(namespace, {recursive: true, force: true}));
  const driver = failedCoreDriver('/checkout', '/pinned');
  driver.write('failed: /pinned/bin/moon generate-test-driver --output-driver ' +
    '/checkout/_build/native/debug/test/__generated_driver_for_blackbox_test.mbt ' +
    '--output-metadata /checkout/_build/native/debug/test/__blackbox_test_info.json ' +
    '/checkout/src/environment_test.mbt --target native --pkg-name actql/actql --driver-kind blackbox\n');
  const env = {PATH: '/pinned/bin', DYLD_INSERT_LIBRARIES: '/original/injection.dylib',
    ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT: '/original/root', TOKEN: 'PRIVATE_TOKEN'};
  let calls = 0;
  const result = diagnoseFailedCoreDriver({driver, root: '/checkout', namespace, env},
    (command, args, options) => {
      calls++;
      if (command === driver.tool) {
        assert.deepEqual(options.env, env);
        assert.equal(options.cwd, '/checkout');
        assert.equal(options.stdio, 'ignore');
        assert.equal(options.timeout, 15000);
        assert.deepEqual(args.filter((_, i) => i !== 2 && i !== 4),
          driver.args.filter((_, i) => i !== 2 && i !== 4));
        assert.equal(args[2], args[4].replace('serial-metadata.json', 'serial-driver.mbt'));
        return {status: 0, signal: null};
      }
      assert.equal(command, 'xcrun');
      assert.equal(options.timeout, 60000);
      assert.equal(options.env.DYLD_INSERT_LIBRARIES, undefined);
      const program = JSON.parse(options.input.slice('script exec('.length,
        options.input.indexOf(')\nquit')));
      const encoded = /SetEnvironmentEntries\(json.loads\(base64.b64decode\("([^"]+)"/u.exec(program)[1];
      assert.deepEqual(JSON.parse(Buffer.from(encoded, 'base64')), Object.entries(env)
        .map(([key, value]) => `${key}=${value}`));
      const actual = args.slice(args.indexOf('--') + 2);
      assert.deepEqual(actual.filter((_, i) => i !== 2 && i !== 4),
        ['generate-test-driver', '--output-driver', '--output-metadata',
          '/checkout/src/environment_test.mbt', '--target', 'native', '--pkg-name',
          'actql/actql', '--driver-kind', 'blackbox']);
      assert(actual[2].startsWith(namespace + '/compiler-stop-'));
      assert(actual[4].startsWith(namespace + '/compiler-stop-'));
      assert(!args.join(' ').includes('PRIVATE_TOKEN'));
      return {status: 0, signal: null, stdout: 'PRIVATE_HEADER\nACTQL_COMPILER_STOP ' +
        JSON.stringify({attempted: true, cause: 'SIGTRAP', cleanup: 'exited',
          frames: [{module: 'dyld', symbol: 'observed_symbol', registers: 'PRIVATE_REGISTERS'}],
          environment: 'PRIVATE_TOKEN'}) + '\n', stderr: 'PRIVATE_STDERR'};
    });
  assert.equal(calls, 2);
  assert.equal(result.cause, 'SIGTRAP');
  assert.deepEqual(result.serial, {attempted: true, exitStatus: 0, signal: null,
    timedOut: false, errorCode: null});
  assert.deepEqual(result.frames, [{module: 'dyld', symbol: 'observed_symbol'}]);
  assert(!JSON.stringify(result).includes('PRIVATE_'));
});

test('Compiler stop diagnostic validates launch input and distinguishes inferior exit from cleanup', t => {
  const namespace = mkdtempSync(join(tmpdir(), 'actql-compiler-launch-control-'));
  t.after(() => rmSync(namespace, {recursive: true, force: true}));
  const driver = failedCoreDriver('/checkout', '/pinned');
  driver.write('failed: ' + [driver.tool, ...driver.args].join(' ') + '\n');
  for (const scenario of ['exit', 'arguments-mismatch', 'image-mismatch', 'stopped',
    'stopped-environment-mismatch', 'stopped-environment-unobserved', 'stopped-reader-unobserved']) {
    const env = {TOKEN: 'PRIVATE_TOKEN', DYLD_INSERT_LIBRARIES: '/original/runtime-reader-custody.dylib',
      ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT: '/original/root'};
    const result = diagnoseFailedCoreDriver({driver, root: '/checkout', namespace,
      env}, (command, args, options) => {
      if (command === driver.tool) return scenario === 'exit'
        ? {status: null, signal: 'SIGTRAP'} : {status: 0, signal: null};
      const program = JSON.parse(options.input.slice('script exec('.length,
        options.input.indexOf(')\nquit')));
      const expected = args.slice(args.indexOf('--') + 1);
      // Execute the actual embedded program with an explicit LLDB API port.
      // This launches no debugger or compiler and reads no process memory.
      const port = `import sys, json, types, os
payload = json.load(sys.stdin)
scenario = payload["scenario"]
expected = payload["expected"]
class FileSpec:
    def __init__(self, path): self.path = path
    def GetDirectory(self): return os.path.dirname(self.path)
    def GetFilename(self): return os.path.basename(self.path)
class LaunchInfo:
    def __init__(self): self.args = ["stale-default"]
    def SetArguments(self, args, append):
        assert append is False
        self.args = list(args)
    def SetExecutableFile(self, spec, first):
        assert first is False
        self.exe = spec
    def GetNumArguments(self): return len(self.args)
    def GetArgumentAtIndex(self, i):
        return "wrong" if scenario == "arguments-mismatch" and i == 1 else self.args[i]
    def GetExecutableFile(self): return self.exe
    def SetEnvironmentEntries(self, entries, append):
        assert entries == payload["environment"] and append is False
        self.env = entries
    def GetNumEnvironmentEntries(self): return len(self.env)
    def GetEnvironmentEntryAtIndex(self, index): return self.env[index]
    def SetWorkingDirectory(self, path): assert path == "/checkout"
    def GetLaunchFlags(self): return 7
    def SetLaunchFlags(self, flags): assert flags == 4
    def SetDetachOnError(self, value): assert value is False
    def AddSuppressFileAction(self, fd, read, write): assert fd in (1, 2) and not read and write
class Error:
    def Success(self): return True
class ExpressionError:
    def Success(self): return scenario != "stopped-environment-unobserved"
class ExpressionOptions:
    def SetTimeoutInMicroSeconds(self, value): assert value == 1000000
    def SetIgnoreBreakpoints(self, value): assert value is True
    def SetUnwindOnError(self, value): assert value is True
    def SetLanguage(self, value): assert value == 17
class Value:
    def __init__(self, expression): self.expression = expression
    def IsValid(self): return True
    def GetError(self): return ExpressionError()
    def GetValueAsUnsigned(self):
        return 0 if scenario == "stopped-environment-mismatch" and 'getenv("DYLD_INSERT_LIBRARIES")' in self.expression else 1
class Module:
    def GetFileSpec(self): return FileSpec("/original/runtime-reader-custody.dylib")
class Frame:
    def IsValid(self): return False
class Thread:
    def GetStopDescription(self, size): return "signal SIGTRAP PRIVATE_DETAIL"
    def GetFrameAtIndex(self, index): return Frame()
class Process:
    def __init__(self, valid=False):
        self.valid = valid
        self.state = 1 if scenario.startswith("stopped") else 3
    def IsValid(self): return self.valid
    def GetState(self): return self.state
    def GetExitStatus(self):
        assert self.state == 3
        return 43 if scenario == "exit" else 9
    def GetSelectedThread(self): return Thread()
    def Kill(self):
        self.state = 3
        return Error()
class Target:
    launches = 0
    def GetLaunchInfo(self): return LaunchInfo()
    def GetExecutable(self):
        return FileSpec("/foreign/moon" if scenario == "image-mismatch" else expected[0])
    def Launch(self, info, error):
        assert info.args == expected and info.exe.path == expected[0]
        self.launches += 1
        return Process(True)
    def GetNumModules(self): return 1
    def GetModuleAtIndex(self, index): return Module()
    def IsLoaded(self, module): return scenario != "stopped-reader-unobserved"
    def EvaluateExpression(self, expression, options):
        assert 'getenv(' in expression and 'PRIVATE_TOKEN' not in expression
        return Value(expression)
target = Target()
sys.modules["lldb"] = types.SimpleNamespace(
    debugger=types.SimpleNamespace(GetSelectedTarget=lambda: target, SetAsync=lambda value: None),
    SBFileSpec=FileSpec, SBError=Error, SBProcess=Process, SBExpressionOptions=ExpressionOptions,
    eLanguageTypeC=17,
    eLaunchFlagDisableASLR=1, eLaunchFlagStopAtEntry=2,
    eStateStopped=1, eStateCrashed=2, eStateExited=3, eStateDetached=4, eStateInvalid=5)
exec(payload["program"])
assert target.launches == (0 if scenario in ("arguments-mismatch", "image-mismatch") else 1)
`;
      const control = spawnSync('python3', ['-c', port], {encoding: 'utf8', timeout: 10000,
        input: JSON.stringify({program, expected, scenario,
          environment: Object.entries(env).map(([key, value]) => key + '=' + value)})});
      assert.equal(control.status, 0, control.stderr);
      return control;
    });
    assert.equal(result.launchArgumentsMatch, scenario !== 'arguments-mismatch');
    assert.equal(result.launchImageMatch, scenario !== 'image-mismatch');
    assert.equal(result.launchSucceeded, !['arguments-mismatch', 'image-mismatch'].includes(scenario));
    assert.equal(result.inferiorExitStatus, scenario === 'exit' ? 43 : null);
    assert.equal(result.serial.signal, scenario === 'exit' ? 'SIGTRAP' : null);
    assert.equal(result.serial.exitStatus, scenario === 'exit' ? null : 0);
    assert.equal(result.terminatedByDiagnostic, scenario.startsWith('stopped'));
    assert.equal(result.cause, scenario.startsWith('stopped') ? 'SIGTRAP' : 'unobserved');
    assert.deepEqual(result.launchEnvironmentMatches, {DYLD_INSERT_LIBRARIES: true,
      LD_PRELOAD: true, ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT: true});
    const observed = scenario.startsWith('stopped') && scenario !== 'stopped-environment-unobserved';
    assert.deepEqual(result.targetEnvironmentMatches, {
      DYLD_INSERT_LIBRARIES: observed ? scenario !== 'stopped-environment-mismatch' : null,
      LD_PRELOAD: observed ? true : null,
      ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT: observed ? true : null});
    assert.equal(result.readerLibraryLoaded,
      scenario.startsWith('stopped') && scenario !== 'stopped-reader-unobserved' ? true : null);
    assert(!JSON.stringify(result).includes('PRIVATE_'));
  }
});

test('Compiler stop diagnostic timeout stays unobserved without raw debugger payload', t => {
  const namespace = mkdtempSync(join(tmpdir(), 'actql-compiler-timeout-control-'));
  t.after(() => rmSync(namespace, {recursive: true, force: true}));
  const driver = failedCoreDriver('/checkout', '/pinned');
  driver.write('failed: /pinned/bin/moon generate-test-driver --output-driver ' +
    '/checkout/_build/native/debug/test/__generated_driver_for_blackbox_test.mbt ' +
    '--output-metadata /checkout/_build/native/debug/test/__blackbox_test_info.json ' +
    '/checkout/src/environment_test.mbt --target native --pkg-name actql/actql --driver-kind blackbox\n');
  const result = diagnoseFailedCoreDriver({driver, root: '/checkout', namespace,
    env: {TOKEN: 'PRIVATE_TOKEN'}}, (command, args, options) => {
    if (command === driver.tool) return {status: null, signal: 'SIGKILL', error: {code: 'ETIMEDOUT', message: 'PRIVATE_SERIAL'}};
    const program = JSON.parse(options.input.slice('script exec('.length,
      options.input.indexOf(')\nquit')));
    const syntax = spawnSync('python3', ['-c', 'import ast,sys; ast.parse(sys.stdin.read())'],
      {input: program, encoding: 'utf8', timeout: 10000});
    assert.equal(syntax.status, 0, syntax.stderr);
    assert.equal(options.timeout, 60000);
    assert(options.input.includes('time.monotonic() + 52'));
    assert(options.input.includes('process.Kill()'));
    assert(args.includes('--no-lldbinit'));
    return {status: null, signal: 'SIGKILL', error: {code: 'ETIMEDOUT'},
      stdout: 'PRIVATE_MEMORY', stderr: 'PRIVATE_ENV'};
  });
  assert.equal(result.cause, 'unobserved');
  assert.equal(result.cleanup, 'unobserved');
  assert.equal(result.timedOut, true);
  assert.deepEqual(result.serial, {attempted: true, exitStatus: null, signal: 'SIGKILL',
    timedOut: true, errorCode: 'ETIMEDOUT'});
  assert(!JSON.stringify(result).includes('PRIVATE_'));
});

test('Native Core selects the admitted Darwin arm64 runner without dropping target coverage', t => {
  const core = workflow.jobs.core;
  const expression = core['runs-on'];
  assert.equal(expression, "${{ matrix.target == 'native' && 'macos-15' || 'ubuntu-24.04' }}");
  for (const [target, runner] of [['native', 'macos-15'], ['js', 'ubuntu-24.04'],
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
  assert.match(coreStep.run, /node scripts\/test-native-core\.mjs --deny-warn --release --strip -j 2 --no-parallelize/u);
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
      coreStep.run.replaceAll('${{ matrix.target }}', target)
        .replaceAll('${{ needs.select-targets.outputs.moon_test_selection }}', 'false');
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

function fixture(t, {scoped = false, http = false, sourcePeers = false, relationWork = false} = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-namespace-test-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const checkout = join(root, 'checkout');
  const parent = join(root, 'sqlite');
  const bin = join(root, 'bin');
  for (const path of [join(checkout, 'scripts'),
    join(checkout, '.github/workflows'), parent, bin]) mkdirSync(path, {recursive: true});
  for (const name of ['test-native-core.mjs', 'native-completed-restoration-fixture.mjs', 'owned-scratch.mjs',
    'native-client-file-fixture.mjs', 'native-core-c-compiler.mjs', 'native-core-test-selection.mjs', 'native-http-lifetime-fixture.mjs', 'native-core-scoped-fixture.mjs', 'verification-actions.mjs',
    'native-client-checkpoint-fixture.mjs', 'native-private-host-fixture.mjs',
    'native-filesystem-observation-fixture.mjs',
    'native-runtime-reader-custody-fixture.mjs', 'native-project-configuration-fixture.mjs',
    'local-checks.mjs', 'local-checks-guard.mjs', 'local-checks-supervisor.mjs',
    'local-checks-policy.mjs', 'test-execution.mjs', 'packed-query-evidence.mjs']) {
    copyFileSync(new URL(name, import.meta.url), join(checkout, 'scripts', name));
  }
  // Keep the public authored template import real in the copied wrapper
  // checkout; no second handwritten Mock project fixture is maintained here.
  mkdirSync(join(checkout, 'packages/native-cli/lib'), {recursive: true});
  copyFileSync(new URL('../packages/native-cli/lib/project-template.mjs', import.meta.url),
    join(checkout, 'packages/native-cli/lib/project-template.mjs'));
  mkdirSync(join(checkout, 'spec/contracts'), {recursive: true});
  for (const name of ['actql-query-acquisition.json', 'actql-query-process-evidence.json']) {
    copyFileSync(new URL('../spec/contracts/' + name, import.meta.url),
      join(checkout, 'spec/contracts', name));
  }
  // This fixture observes wrapper routing. The original ten process/channel
  // cases exercise the physical C/Rust leaf with the real preparation helper.
  writeFileSync(join(checkout, 'scripts/native-process-region-fixture.mjs'), `
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
export function nativeProcessRegionFixture(repository, namespace) {
  const root = join(namespace, 'process-region'); mkdirSync(root, {mode: 0o700});
  return {ACTQL_TEST_NATIVE_PROCESS_REGION_ROOT: root,
    ACTQL_TEST_NATIVE_HANDLER_PROCESS_CHILD: join(root, 'handler-process-child'),
    ACTQL_TEST_NATIVE_HANDLER_LIBRARY: join(root, 'handler-thread.dylib')};
}
`);
  mkdirSync(join(checkout, 'scripts/fixtures'));
  copyFileSync(new URL('fixtures/native-unclosed-sqlite.c', import.meta.url),
    join(checkout, 'scripts/fixtures/native-unclosed-sqlite.c'));
  copyFileSync(new URL('fixtures/native-runtime-reader-custody.c', import.meta.url),
    join(checkout, 'scripts/fixtures/native-runtime-reader-custody.c'));
  copyFileSync(new URL('fixtures/native-http-lifetime-library.c', import.meta.url),
    join(checkout,'scripts/fixtures/native-http-lifetime-library.c'));
  copyFileSync(new URL('fixtures/native-effect-resolution-fixture.mjs', import.meta.url),
    join(checkout, 'scripts/fixtures/native-effect-resolution-fixture.mjs'));
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const aoa = JSON.parse(readFileSync(join(repository, 'spec/contracts/actql-aoa.json'), 'utf8'));
  for (const path of ['spec/contracts/actql-aoa.json', aoa.pipeline_registry_file]) {
    const target = join(checkout, path);
    mkdirSync(dirname(target), {recursive: true});
    copyFileSync(join(repository, path), target);
  }
  symlinkSync(new URL('../node_modules', import.meta.url), join(checkout, 'node_modules'), 'dir');
  writeFileSync(join(checkout, '.github/workflows/ci.yml'),
    JSON.stringify({jobs: {core: {'timeout-minutes': 30, steps: [coreStep]}}}));
  const originals = ['trusted-clock.sqlite', 'trusted-clock.sqlite-wal',
    'trusted-clock.sqlite-shm'];
  for (const name of originals) writeFileSync(join(parent, name), `external ${name}`);
  const moon = join(bin, 'moon');
  for (const name of ['fixture-native', 'fixture-empty']) {
    mkdirSync(join(checkout, 'src', name), {recursive: true});
    writeFileSync(join(checkout, 'src', name, 'main.mbt'), 'Original compiler-input fixture\n');
  }
  if (http) {
    const source = join(checkout, 'src/platform_native/http_client');
    mkdirSync(source, {recursive: true});
    writeFileSync(join(source, 'main.mbt'), 'Original compiler-input fixture\n');
    // Explicit wrapper-routing port, not physical HTTPS acceptance.
    writeFileSync(join(checkout, 'scripts/test-native-http-client.mjs'), `
import assert from 'node:assert/strict';
assert.equal(process.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'core-http');
assert.equal(process.env.ACTQL_TEST_NATIVE_CORE_HTTP_COUNT, '1');
assert.deepEqual(JSON.parse(process.env.ACTQL_TEST_NATIVE_CORE_HTTP_ARGS),
  ['--deny-warn', 'src/platform_native/http_client']);
assert.equal(process.env.ACTQL_TEST_NATIVE_HTTP_URL, undefined);
assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1');
console.log('ORIGINAL_HTTP_PROFILE_REQUIRED');
process.exitCode = process.env.ACTQL_FIXTURE_HTTP_FAILED === '1' ? 9 : 0;
`);
  }
  if(sourcePeers) {
    const directory=join(checkout,'src/platform_native/remote_resident_source_compute_tests');
    mkdirSync(directory,{recursive:true});
    for(const file of ['retained_compute_wbtest.mbt','ordinary_wbtest.mbt'])
      writeFileSync(join(directory,file),'Original compiler-input fixture\n');
    // Explicit routing port; real Source/HTTP fixture execution is separate.
    writeFileSync(join(checkout,'scripts/test-native-http-client.mjs'), `
import assert from 'node:assert/strict';
import {appendFileSync} from 'node:fs';
assert.equal(process.env.ACTQL_TEST_NATIVE_HTTP_FOCUS,'core-source');
assert.equal(process.env.ACTQL_TEST_NATIVE_CORE_SOURCE_COUNT,'2');
const args=JSON.parse(process.env.ACTQL_TEST_NATIVE_CORE_SOURCE_ARGS);
assert.deepEqual(args,['--deny-warn','--release','--strip','-j','2','--no-parallelize',
  'src/platform_native/remote_resident_source_compute_tests']);
assert.equal(process.env.ACTQL_TEST_NATIVE_HTTP_URL,undefined);
assert.equal(process.env.ACTQL_TEST_NATIVE_HTTP_BEARER_URL,undefined);
assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH,'1');
appendFileSync(process.env.ACTQL_FIXTURE_NATIVE_COMMANDS,JSON.stringify({
  args:['test','--target','native',...args],path:process.env.PATH,profile:'source-peers'})+'\\n');
console.log('ORIGINAL_SOURCE_PROFILE_REQUIRED');
process.exitCode=process.env.ACTQL_FIXTURE_SOURCE_FAILED==='1'?9:0;
`);
  }
  if (scoped) {
    mkdirSync(join(checkout, 'src/cmd/native_client'), {recursive: true});
    for (const name of ['ordinary_wbtest.mbt', 'local_command_business_wbtest.mbt',
      'local_command_business_cleanup_wbtest.mbt']) {
      writeFileSync(join(checkout, 'src/cmd/native_client', name), 'Original compiler-input fixture\n');
    }
    mkdirSync(join(checkout, 'src/platform_native/host_bootstrap'), {recursive: true});
    for (const name of ['root_control_unavailable_wbtest.mbt', 'root_control_physical_scoped_wbtest.mbt']) {
      writeFileSync(join(checkout, 'src/platform_native/host_bootstrap', name), 'Original compiler-input fixture\n');
    }
    mkdirSync(join(checkout, 'src/platform_native/installed_arena_control'), {recursive: true});
    writeFileSync(join(checkout,
      'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt'),
    'Original compiler-input fixture\n');
    mkdirSync(join(checkout, 'src/platform_native/row_source'), {recursive: true});
    writeFileSync(join(checkout, 'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt'),
      'Original compiler-input fixture\n');
    // This test observes routing only. Physical compilation is covered by the
    // selected-provider helper and actual Native cases, not this explicit port.
    writeFileSync(join(checkout, 'scripts/native-core-scoped-profile.mjs'), `
import assert from 'node:assert/strict';
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
export function prepareNativeCoreScopedProfile(root, scratch, args, {env, profile}) {
  assert.deepEqual(args.slice(0, 2), ['--target', 'native']);
  assert.equal(env.PATH.includes('/test-c-compiler:'), false);
  assert.equal(env.ACTQL_REQUIRE_NATIVE_RETAINED_TEST, '1');
  assert(env.ACTQL_TEST_NATIVE_UNCLOSED_SQLITE_FIXTURE);
  const targetDirectory = join(scratch, 'selected-target'); mkdirSync(targetDirectory);
  assert(['runtime-values', 'scoped-review-values'].includes(profile));
  return {targetDirectory, environment: {...env, ACTQL_FIXTURE_PROFILE: profile}};
}
`);

    writeFileSync(join(checkout, 'scripts/native-runtime-bundle-fixture.mjs'), `
import assert from 'node:assert/strict';
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
export function prepareNativeRuntimeBundleLibraries(root, destination, options) {
  assert(destination.startsWith(join(root, '_build/native-core-scoped/')));
  assert.equal(options.seconds, 900);
  mkdirSync(destination);
  return {sqliteLibrary: join(destination, 'sqlite-component.dylib'),
    cryptoLibrary: join(destination, 'crypto-component.dylib')};
}
`);
  }
  if (relationWork) {
    assert(scoped);
    const path = 'src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt';
    mkdirSync(dirname(join(checkout, path)), {recursive: true});
    writeFileSync(join(checkout, path), 'Original compiler-input fixture\n');
    // Explicit routing port, not a runtime manifest, producer receipt, or
    // physical Work acceptance. Real assembly has independent refusal tests.
    writeFileSync(join(checkout, 'scripts/native-core-relation-work-fixture.mjs'), `
import assert from 'node:assert/strict';
import {closeSync, ftruncateSync, mkdirSync, openSync} from 'node:fs';
import {join} from 'node:path';
export async function prepareNativeCoreRelationRuntime(repository, destination, components, {env}) {
  assert(destination.startsWith(join(repository, '_build/native-core-scoped/')));
  assert(components.sqliteLibrary.endsWith('/sqlite-component.dylib'));
  assert(components.cryptoLibrary.endsWith('/crypto-component.dylib'));
  assert.equal(env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT, undefined);
  mkdirSync(destination, {mode: 0o700});
  console.log('CURRENT_RELATION_COMPONENT_INPUTS_REQUIRED');
  return {destination};
}
export async function nativeRelationOriginalWorkFixture(namespace, prepared) {
  const input = join(namespace, 'relation-original'); mkdirSync(input, {mode: 0o700});
  const fd = openSync(join(input, 'backing'), 'wx', 0o600);
  try { ftruncateSync(fd, 768 * 1024 ** 2); } finally { closeSync(fd); }
  return {ACTQL_TEST_RELATION_ORIGINAL_ROOT: input,
    ACTQL_TEST_RELATION_RUNTIME_ROOT: prepared.destination,
    ACTQL_TEST_RELATION_RUNTIME_SOURCE: 'a'.repeat(40),
    ACTQL_TEST_RELATION_RUNTIME_DIGEST: 'b'.repeat(64),
    ACTQL_TEST_RELATION_RUNTIME_PLATFORM: 'darwin-arm64',
    ACTQL_TEST_RELATION_ORIGINAL_MODE: 'positive'};
}
`);
  }
  writeFileSync(moon, `#!${process.execPath}
const assert = require('node:assert/strict');
const {writeFileSync, existsSync, statSync, readlinkSync} = require('node:fs');
const {createHash, verify} = require('node:crypto');
const {join} = require('node:path');
if (process.argv[2] === 'generate-test-driver') {
  const args = process.argv.slice(2), metadata = args[args.indexOf('--output-metadata') + 1];
  require('node:fs').mkdirSync(require('node:path').dirname(metadata), {recursive:true});
  const tests = Object.fromEntries(args.filter(value => value.startsWith('src/') && value.endsWith('.mbt'))
    .map(value => [require('node:path').basename(value), value.startsWith('src/fixture-empty/') ? [] :
      Array.from({length: value.endsWith('/root_control_physical_scoped_wbtest.mbt') ? 3 : 1},
        (_, index) => ({index,name:'original fixture case '+index,attrs:[],line_number:index+1}))]));
  writeFileSync(metadata, JSON.stringify({tests}));
  process.exit(0);
}
assert.deepEqual(process.argv.slice(2, 5), ['test', '--target', 'native']);
if (process.argv.includes('--dry-run')) {
  if(process.env.ACTQL_FIXTURE_CORE_SOURCE==='1') {
    const source='src/platform_native/remote_resident_source_compute_tests';
    for(const [directory,files] of [['src/fixture-native',['main.mbt']],
      [source,['ordinary_wbtest.mbt','retained_compute_wbtest.mbt']]])
      console.log('moon generate-test-driver --output-driver _build/'+directory+'/driver.mbt '+
        '--output-metadata _build/'+directory+'/info.json '+files.map(file=>directory+'/'+file).join(' ')+
        ' --target native --pkg-name fixture/'+directory+' --driver-kind whitebox');
    process.exit(0);
  }
  if (process.env.ACTQL_FIXTURE_CORE_SCOPED === '1') {
    console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/cmd/native_client/driver.mbt ' +
      '--output-metadata _build/native/release/test/cmd/native_client/info.json ' +
      ['ordinary_wbtest.mbt','local_command_business_wbtest.mbt','local_command_business_cleanup_wbtest.mbt']
        .map(name => 'src/cmd/native_client/' + name).join(' ') +
      ' --target native --pkg-name fixture/native_client --driver-kind whitebox');
    console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/platform_native/host_bootstrap/driver.mbt ' +
      '--output-metadata _build/native/release/test/platform_native/host_bootstrap/info.json ' +
      ['root_control_unavailable_wbtest.mbt', 'root_control_physical_scoped_wbtest.mbt']
        .map(name => 'src/platform_native/host_bootstrap/' + name).join(' ') +
      ' --target native --pkg-name fixture/host_bootstrap --driver-kind whitebox');
    console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/platform_native/installed_arena_control/driver.mbt ' +
      '--output-metadata _build/native/release/test/platform_native/installed_arena_control/info.json ' +
      'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt ' +
      '--target native --pkg-name fixture/arena --driver-kind whitebox');
    console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/platform_native/row_source/driver.mbt ' +
      '--output-metadata _build/native/release/test/platform_native/row_source/info.json ' +
      'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt ' +
      '--target native --pkg-name fixture/row_source --driver-kind whitebox');
    if (process.env.ACTQL_FIXTURE_CORE_RELATION_WORK === '1') console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/platform_native/relation_file_work_tests/driver.mbt ' +
      '--output-metadata _build/native/release/test/platform_native/relation_file_work_tests/info.json ' +
      'src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt ' +
      '--target native --pkg-name fixture/relation_file_work_tests --driver-kind blackbox');
    process.exit(0);
  }
  for (const name of process.argv.includes('src/fixture-native') ? ['fixture-native',
    ...(process.argv.includes('src/platform_native/http_client') ? ['platform_native/http_client'] : [])]
    : ['fixture-native','fixture-empty',
      ...(process.env.ACTQL_FIXTURE_CORE_HTTP === '1' ? ['platform_native/http_client'] : [])]) console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/'+name+'/driver.mbt '+
      '--output-metadata _build/native/release/test/'+name+'/info.json '+
      'src/'+name+'/main.mbt --target native --pkg-name fixture/'+name+' --driver-kind internal');
  process.exit(0);
}
if (process.env.ACTQL_FIXTURE_NATIVE_COMMANDS) {
  require('node:fs').appendFileSync(process.env.ACTQL_FIXTURE_NATIVE_COMMANDS,
    JSON.stringify({args:process.argv.slice(2),path:process.env.PATH,
      allocator:process.env.MOONBIT_ALLOCATOR,compiler:process.env.MOON_CC,
      backend:process.env.MOONBIT_NEW_NATIVE,profile:process.env.ACTQL_FIXTURE_PROFILE ?? 'ordinary',
      relationRoot:process.env.ACTQL_TEST_RELATION_ORIGINAL_ROOT,
      relationRuntime:process.env.ACTQL_TEST_RELATION_RUNTIME_ROOT,
      installedProcess:process.env.ACTQL_TEST_INSTALLED_PROCESS_ROOT,
      sqliteComponent:process.env.ACTQL_TEST_SQLITE_COMPONENT,cryptoComponent:process.env.ACTQL_TEST_CRYPTO_COMPONENT}) + '\\n');
}
if (['runtime-values','scoped-review-values'].includes(process.env.ACTQL_FIXTURE_PROFILE)) {
  assert(process.argv.includes('--target-dir'));
  assert(process.env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT);
  assert(process.env.ACTQL_TEST_NATIVE_UNCLOSED_SQLITE_FIXTURE);
  if (process.argv.includes('src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt')) {
    assert.equal(process.env.ACTQL_FIXTURE_PROFILE, 'scoped-review-values');
    const relation = process.env.ACTQL_TEST_RELATION_ORIGINAL_ROOT;
    assert.equal(statSync(relation).mode & 0o777, 0o700);
    assert.equal(statSync(join(relation, 'backing')).size, 768 * 1024 ** 2);
    assert.equal(statSync(join(relation, 'backing')).mode & 0o777, 0o600);
    assert.equal(process.env.ACTQL_TEST_RELATION_RUNTIME_SOURCE, 'a'.repeat(40));
    assert.equal(process.env.ACTQL_TEST_RELATION_RUNTIME_DIGEST, 'b'.repeat(64));
    assert.equal(process.env.ACTQL_TEST_RELATION_RUNTIME_PLATFORM, 'darwin-arm64');
    assert.equal(process.env.ACTQL_TEST_RELATION_ORIGINAL_MODE, 'positive');
    assert.equal(process.env.ACTQL_TEST_INSTALLED_PROCESS_ROOT, undefined);
    if (process.env.ACTQL_FIXTURE_RELATION_ZERO === '1') console.log('Total tests: 0, passed: 0, failed: 0.');
    else console.log('Total tests: 1, passed: 1, failed: 0.');
    process.exit(0);
  }
  assert.equal(statSync(process.env.ACTQL_TEST_INSTALLED_PROCESS_ROOT).mode & 0o777, 0o700);
  if (process.argv.includes('src/platform_native/row_source/capture_physical_scoped_wbtest.mbt')) {
    assert.equal(process.env.ACTQL_TEST_SQLITE_COMPONENT, undefined);
    assert.equal(process.env.ACTQL_TEST_CRYPTO_COMPONENT, undefined);
  } else {
    assert(process.env.ACTQL_TEST_SQLITE_COMPONENT.endsWith('/sqlite-component.dylib'));
    assert(process.env.ACTQL_TEST_CRYPTO_COMPONENT.endsWith('/crypto-component.dylib'));
    assert.notEqual(process.env.ACTQL_TEST_SQLITE_COMPONENT, process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY);
    assert.notEqual(process.env.ACTQL_TEST_CRYPTO_COMPONENT, process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY);
  }
  if (process.env.ACTQL_FIXTURE_SCOPED_FAIL === '1') process.exit(7);
  console.log('Total tests: 1, passed: 1, failed: 0.'); process.exit(0);
}
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
const cliParent = process.env.ACTQL_TEST_NATIVE_CLI_PARENT_ROOT;
assert.equal(cliParent, join(root, 'cli-parent'));
assert.equal(statSync(cliParent).mode & 0o777, 0o700);
assert.deepEqual(require('node:fs').readdirSync(cliParent), []);
console.log('CLI_PARENT_FIXTURE_PROVISIONED');
if (process.env.ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT) {
  const project = process.env.ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT;
  assert.equal(project, join(root, 'project-configuration'));
  assert.equal(statSync(project).mode & 0o777, 0o700);
  assert.equal(JSON.parse(require('node:fs').readFileSync(join(project, 'actql.config.json'), 'utf8')).version, 'actql-config/0.1');
  assert.equal(statSync(join(project, 'nearer/child')).isDirectory(), true);
  assert.equal(statSync(join(project, 'oversize/actql.config.json')).size, 65537);
  assert.equal(readlinkSync(join(project, 'symlink/actql.config.json')), '../actql.config.json');
  assert.equal(existsSync(join(project, 'missing-bindings/connectors.json')), false);
  assert.equal(JSON.parse(require('node:fs').readFileSync(join(project, 'plain/connectors.json'), 'utf8')).version, 'actql-connectors/0.1');
  assert.equal(JSON.parse(require('node:fs').readFileSync(join(project, 'plain/model-tasks.json'), 'utf8')).version, 'actql-model-tasks/0.1');
  assert.equal(existsSync(join(project, 'never-created')), false);
  console.log('PROJECT_CONFIGURATION_FIXTURE_PROVISIONED');
}
if (process.env.ACTQL_TEST_NATIVE_BOUNDED_FILES_ROOT) {
  assert.equal(process.env.ACTQL_TEST_NATIVE_BOUNDED_FILES_ROOT, join(root, 'bounded-files'));
  assert.equal(statSync(process.env.ACTQL_TEST_NATIVE_BOUNDED_FILES_ROOT).mode & 0o777, 0o700);
  console.log('BOUNDED_FILES_INPUT_PROVISIONED');
}
if (process.env.ACTQL_TEST_NATIVE_HTTP_LIFETIME_LIBRARY) {
  assert.equal(existsSync(process.env.ACTQL_TEST_NATIVE_HTTP_LIFETIME_LIBRARY), true);
  assert.equal(process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY, undefined);
  assert.equal(process.env.ACTQL_TEST_NATIVE_HTTP_URL, undefined);
  console.log('HTTP_LIFETIME_INPUT_PROVISIONED');
}
if (process.env.ACTQL_TEST_NATIVE_OUTPUT_VERIFY_ROOT) {
  const output = process.env.ACTQL_TEST_NATIVE_OUTPUT_VERIFY_ROOT;
  const runtime = process.env.ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_ROOT;
  assert.equal(output, join(root, 'output-verification'));
  assert.equal(runtime, join(root, 'runtime-namespace'));
  assert.equal(statSync(output).mode & 0o777, 0o700);
  assert.equal(require('node:fs').readFileSync(join(output, 'data.bin'), 'utf8'), 'data');
  const receipt = JSON.parse(require('node:fs').readFileSync(join(output, 'single.json'), 'utf8'));
  assert.equal(receipt.result_delivery_receipt_cid,
    'sha256:653b739f7a85f39a048ed77fe1d38f8fc5e1edcf1ab50a867a83216e76a1d146');
  const manifest = require('node:fs').readFileSync(join(runtime, 'unchanged/local-runtime.json'));
  assert.equal(createHash('sha256').update(manifest).digest('hex'),
    process.env.ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_MANIFEST_SHA256);
  assert.equal(JSON.parse(manifest).sourceSha, 'a'.repeat(40));
  assert.equal(require('node:fs').readFileSync(join(runtime, 'unchanged/lib/sqlite.bin'), 'utf8'), 'abc');
  assert.equal(readlinkSync(join(runtime, 'alias')), 'unchanged');
  assert.equal(existsSync(join(runtime, 'never-acquired')), false);
  console.log('CLI_FILE_INPUTS_PROVISIONED');
}
if (process.env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT) {
  assert.equal(process.env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT, root);
  for (const name of ['runtime-constructor-pending', 'runtime-constructor-acked']) {
    assert.equal(statSync(join(root, name)).mode & 0o777, 0o700);
    const manifest = join(root, name, 'local-runtime.json');
    assert.equal(require('node:fs').readFileSync(manifest, 'utf8'), '{}');
    assert.equal(statSync(manifest).mode & 0o777, 0o600);
  }
  const injected = process.platform === 'darwin'
    ? process.env.DYLD_INSERT_LIBRARIES : process.env.LD_PRELOAD;
  assert.equal(existsSync(injected), true);
}
if (process.argv.some(arg => arg.includes('platform_native/filesystem') || arg.includes('platform_native/client_host'))) {
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
if (process.env.ACTQL_TEST_ORIGINAL_SIGNING_ROOT) {
  const signingRoot = process.env.ACTQL_TEST_ORIGINAL_SIGNING_ROOT;
  assert.equal(signingRoot, join(root, 'original-signing'));
  assert.equal(statSync(signingRoot).mode & 0o777, 0o700);
  assert.equal(statSync(join(signingRoot, 'key.pem')).mode & 0o777, 0o600);
  assert.match(require('node:fs').readFileSync(join(signingRoot, 'key.pem'), 'utf8'),
    /^-----BEGIN PRIVATE KEY-----/u);
  console.log('ORIGINAL_SIGNING_FIXTURE_PROVISIONED');
}
assert.equal(process.env.ACTQL_TEST_DUCKDB_LIBRARY, join(process.cwd(),
  'adapters', 'connectors', 'duckdb', 'node', 'node_modules', '@duckdb',
  'node-bindings-' + process.platform + '-' + process.arch,
  process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so'));
assert.equal(process.env.ACTQL_TEST_NATIVE_CRYPTO_MISSING_LIBRARY,
  join(root, 'missing-crypto-library'));
assert.equal(existsSync(process.env.ACTQL_TEST_NATIVE_CRYPTO_MISSING_LIBRARY), false);
assert.equal(process.env.ACTQL_TEST_NATIVE_STORE_ROOT, undefined,
  'Core must not activate unrelated shared Store fixtures');
assert.equal(process.env.ACTQL_REQUIRE_NATIVE_RETAINED_TEST, '1');
if (process.env.ACTQL_TEST_NATIVE_PROCESS_REGION_ROOT) {
  assert.equal(process.env.ACTQL_TEST_NATIVE_PROCESS_REGION_ROOT, join(root, 'process-region'));
  assert.equal(process.env.ACTQL_TEST_NATIVE_HANDLER_PROCESS_CHILD, join(root, 'process-region/handler-process-child'));
  assert.equal(process.env.ACTQL_TEST_NATIVE_HANDLER_LIBRARY, join(root, 'process-region/handler-thread.dylib'));
  console.log('PROCESS_REGION_INPUTS_PROVISIONED');
}
for (const [variable, child] of [
  ['ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT', 'standard'],
  ['ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT', 'bundles'],
  ['ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT', 'executor-slot'],
  ['ACTQL_TEST_NATIVE_RETAINED_TASK_FILE_ROOT', 'retained-task-file'],
  ['ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT', 'retained-task'],
]) {
  assert.equal(process.env[variable], join(root, child));
  const info = statSync(process.env[variable]);
  assert.equal(info.isDirectory(), true);
  assert.equal(info.mode & 0o777, 0o700);
}
const body = process.env.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY;
const cid = 'sha256:' + createHash('sha256').update(body).digest('hex');
assert.equal(process.env.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID, cid);
assert.equal(process.env.ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET,JSON.parse(body).target_triple);
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
assert.equal(process.argv[4], '--core-test-count');
assert(Number(process.argv[5]) > 0);
console.log('CORE_TARGET_FIXTURE_PROVISIONED');
const result = spawnSync('moon', ['test', '--target', 'native', ...args], {stdio: 'inherit'});
process.exit(result.status ?? 1);
`);
  const env = {...process.env, PATH: `${bin}:${process.env.PATH}`,
    ...(scoped ? {ACTQL_FIXTURE_CORE_SCOPED: '1'} : {}),
    ...(relationWork ? {ACTQL_FIXTURE_CORE_RELATION_WORK: '1'} : {}),
    ...(http ? {ACTQL_FIXTURE_CORE_HTTP: '1'} : {}),
    ...(sourcePeers ? {ACTQL_FIXTURE_CORE_SOURCE:'1'} : {}),
    HOME: root, RUNNER_TEMP: join(root, 'runner'), ACTQL_TEST_NATIVE_SQLITE_ROOT: parent,
    ACTQL_TEST_PRESERVE_SCRATCH: '',
    ACTQL_TEST_NATIVE_REMOTE_STANDARD_ROOT: parent,
    ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT: parent,
    ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT: parent,
    ACTQL_TEST_NATIVE_CLI_PARENT_ROOT: parent};
  delete env.ACTQL_TEST_NATIVE_STORE_ROOT;
  delete env.ACTQL_TEST_DUCKDB_LIBRARY;
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
    assert.match(result.stdout, /CLI_PARENT_FIXTURE_PROVISIONED/u);
    assert.match(result.stdout, /ORIGINAL_SIGNING_FIXTURE_PROVISIONED/u);
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
  assert.doesNotMatch(result.stdout, /PRIVATE_HOST_FIXTURE_PROVISIONED/u);
  assert.doesNotMatch(result.stdout, /ORIGINAL_SIGNING_FIXTURE_PROVISIONED/u);
  assert.match(result.stdout, /child stopped/u);
  f.verifyExternal();
});

test('selected Native signing receives its fresh original key without adopting caller files', t => {
  const f = fixture(t);
  const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
    '--deny-warn', 'src/platform_native/signature'], {
    cwd: f.checkout, encoding: 'utf8',
    env: {...f.env, ACTQL_TEST_ORIGINAL_SIGNING_ROOT: f.parent},
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /ORIGINAL_SIGNING_FIXTURE_PROVISIONED/u);
  assert.doesNotMatch(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
  f.verifyExternal();
});

test('focused ordinary Arena inputs do not select components or reach unrelated Native callers', t => {
  const f=fixture(t),commands=join(f.root,'native-commands.jsonl');
  for(const file of ['src/platform_native/installed_arena_control/process_transport_wbtest.mbt',
    'src/platform_native/trusted_clock/clock_wbtest.mbt']) {
    const result=spawnSync(process.execPath,['scripts/test-native-core.mjs','--deny-warn',file],
      {cwd:f.checkout,encoding:'utf8',timeout:10000,
        env:{...f.env,ACTQL_FIXTURE_NATIVE_COMMANDS:commands}});
    assert.equal(result.status,0,result.stdout+result.stderr);
  }
  const [arena,unrelated]=readFileSync(commands,'utf8').trim().split('\n').map(JSON.parse);
  assert(arena.installedProcess.endsWith('/installed-process'));
  assert.equal(unrelated.installedProcess,undefined);
  for(const call of [arena,unrelated]) {
    assert.equal(call.profile,'ordinary');
    assert.equal(call.sqliteComponent,undefined);assert.equal(call.cryptoComponent,undefined);
    assert.equal(call.allocator,f.env.MOONBIT_ALLOCATOR);
  }
  f.verifyExternal();
});

test('selected Native bounded files and loader cleanup receive only their owned inputs', t => {
  for (const [source, expected] of [
    ['src/platform_native/bounded_files/owned_close_custody_wbtest.mbt', 'BOUNDED_FILES_INPUT_PROVISIONED'],
    ['src/cmd/native_remote_resident_site/control_terminal_cleanup_native_wbtest.mbt', 'HTTP_LIFETIME_INPUT_PROVISIONED'],
  ]) {
    const f = fixture(t);
    const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs', '--deny-warn', source],
      {cwd: f.checkout, encoding: 'utf8', timeout: 10_000, env: f.env});
    assert.equal(result.status, 0, result.stderr);
    assert(result.stdout.includes(expected));
    assert.doesNotMatch(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
    f.verifyExternal();
  }
});

test('selected Native filesystem and client Host provision owned private-root counterexamples', t => {
  for (const source of ['src/platform_native/filesystem/private_root_wbtest.mbt',
    'src/platform_native/client_host/local_adoption_open_custody_wbtest.mbt']) {
    const f = fixture(t);
    const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
      '--deny-warn', source],
    {cwd: f.checkout, encoding: 'utf8', env: {...f.env,
      ACTQL_TEST_NATIVE_PRIVATE_ROOT: f.parent}});
    const path = /Native core SQLite namespace: (.*)/u.exec(result.stdout)?.[1];
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /PRIVATE_HOST_FIXTURE_PROVISIONED/u);
    assert.doesNotMatch(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
    assert.ok(path && !existsSync(path));
    f.verifyExternal();
  }
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


test('full Native Core selects release code generation while retaining the complete strict serial selection and failures', t => {
  const root=mkdtempSync(join(tmpdir(),'actql-core-strip-routing-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const bin=join(root,'bin');mkdirSync(bin);
  for(const name of ['node','moon']){
    const command=join(bin,name);
    writeFileSync(command,`#!${process.execPath}
console.log(JSON.stringify({args:process.argv.slice(2),native:process.env.MOONBIT_NEW_NATIVE}));
if(process.env.ACTQL_FIXTURE_FAIL_FULL==='1'&&process.argv.includes('--strip'))process.exit(7);
`);
    chmodSync(command,0o755);
  }
  writeFileSync(join(bin,'getconf'),'#!/bin/sh\nprintf "3\\n"\n');
  chmodSync(join(bin,'getconf'),0o755);
  for(const target of ['native','js','wasm']){
    const command=coreStep.run.replaceAll('${{ matrix.target }}',target)
      .replaceAll('${{ needs.select-targets.outputs.moon_test_selection }}','false');
    const result=spawnSync('bash',['-eo','pipefail','-c',command],{
      cwd:root,encoding:'utf8',timeout:5000,env:{...process.env,PATH:bin+':'+process.env.PATH,MOONBIT_NEW_NATIVE:'1'},
    });
    assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(result.status,0,result.stderr);
    const records=result.stdout.trim().split('\n').map(line=>JSON.parse(line));
    const calls=records.map(record=>record.args);
    if(target==='native'){
      assert.deepEqual(calls,[
        ['scripts/test-native-core.mjs','--deny-warn','-p','platform_native/trusted_clock'],
        ['scripts/test-native-core.mjs','--deny-warn','--release','--strip','-j','2','--no-parallelize','--verbose'],
      ]);
      assert.deepEqual(records.map(record=>record.native),['1','0']);
      const failed=spawnSync('bash',['-eo','pipefail','-c',command],{
        cwd:root,encoding:'utf8',timeout:5000,
        env:{...process.env,PATH:bin+':'+process.env.PATH,ACTQL_FIXTURE_FAIL_FULL:'1'},
      });
      assert.equal(failed.error,undefined);assert.equal(failed.signal,null);assert.equal(failed.status,7);
    }else{
      assert.equal(calls.length,target==='js'?1:4);
      assert(records.every(record=>record.native==='1'));
      assert(calls.every(args=>!args.includes('--strip')));
      assert.deepEqual(calls[0],['test','--target',target,'--deny-warn','-j','3']);
    }
  }
});

test('failed Native compiler forwarding drains original pipe tails before its unchanged failure', async () => {
  const source = readFileSync(new URL('test-native-salesforce-effect-preview.mjs', import.meta.url), 'utf8');
  const spawnAt = source.indexOf("child = spawn(process.execPath, ['--input-type=module', '-e',");
  const start = source.indexOf('  if (compilerDriver) {', spawnAt);
  const end = source.indexOf('  // This observer', start);
  const settled = source.indexOf("  const [code, signal] = await once(child, 'close');", end);
  const failure = source.indexOf('  if (code !== 0 && compilerDriver)', settled);
  assert(spawnAt >= 0 && start > spawnAt && end > start && settled > end && failure > settled);
  const bytes = 2 * 1024 * 1024, stdout = 'O'.repeat(bytes) + '\nFINAL_NATIVE_SUMMARY\n',
    stderr = 'E'.repeat(bytes) + '\nORIGINAL_CHILD_FAILURE_END\n';
  const producer = `process.stdout.write('O'.repeat(${bytes})+'\\nFINAL_NATIVE_SUMMARY\\n');` +
    `process.stderr.write('E'.repeat(${bytes})+'\\nORIGINAL_CHILD_FAILURE_END\\n');process.exitCode=7;`;
  const script = `import {spawn} from 'node:child_process';import {once} from 'node:events';import assert from 'node:assert/strict';
const compilerDriver={write(){}},stopProgress=()=>{};
let child=spawn(process.execPath,['--input-type=module','-e',${JSON.stringify(producer)}],{stdio:['ignore','pipe','pipe']});
${source.slice(start, end)}
${source.slice(settled, failure)}
assert.equal(code,0,\`Native target observation failed: \${signal??code}\`);`;
  const env = {...process.env}; delete env.NODE_TEST_CONTEXT;
  const child = spawn(process.execPath, ['--input-type=module', '-e', script],
    {env, stdio:['ignore', 'pipe', 'pipe']});
  const output = [], errors = [];
  let delayed = false, resume;
  const collect = (target, chunk) => {
    target.push(chunk);
    if (!delayed) {
      delayed = true; child.stdout.pause(); child.stderr.pause();
      resume = setTimeout(() => {child.stdout.resume(); child.stderr.resume();}, 1000);
    }
  };
  child.stdout.on('data', chunk => collect(output, chunk));
  child.stderr.on('data', chunk => collect(errors, chunk));
  const timeout = setTimeout(() => child.kill('SIGKILL'), 10000);
  let status, signal;
  try {
    [status, signal] = await new Promise((resolve, reject) => {
      child.once('error', reject); child.once('close', (code, signal) => resolve([code, signal]));
    });
  } finally {clearTimeout(timeout); clearTimeout(resume);}
  assert.equal(signal, null); assert.equal(status, 1, 'the original failed child must still fail its wrapper');
  const observed = Buffer.concat(output), diagnostic = Buffer.concat(errors);
  assert.equal(observed.length, Buffer.byteLength(stdout), 'queued stdout tail was lost');
  assert.equal(observed.toString(), stdout);
  assert(diagnostic.length >= Buffer.byteLength(stderr), 'queued stderr tail was lost');
  assert(diagnostic.toString().startsWith(stderr));
  assert.match(diagnostic.toString(), /Native target observation failed: 7/u);
});

test('Native target child keeps a finite cold Core budget without widening ordinary fixture timeouts', () => {
  const source = readFileSync(new URL('test-native-salesforce-effect-preview.mjs', import.meta.url), 'utf8');
  const start = source.indexOf("child = spawn(process.execPath, ['--input-type=module', '-e',");
  const end = source.indexOf('\n  if (compilerDriver)', start);
  assert(start >= 0 && end > start);
  const moonArgs = ['--target', 'native', '--deny-warn', '--release', '--strip', '-j', '1', '--verbose'];
  for (const [coreArgs, originalLocalReview, timeout, coreExpectedTests] of [
    [undefined, false, 180000, undefined],
    [undefined, true, 600000, undefined],
    [moonArgs.slice(2), false, 3600000, 33],
  ]) {
    let invocation;
    runInNewContext('let child;\n' + source.slice(start, end), {
      process: {execPath: process.execPath}, coreArgs, coreExpectedTests, originalLocalReview,
      moonArgs, root: '/original/owned/fixture', testEnv: {}, compilerDriver: false,
      spawn(command, args) { invocation = {command, args: Array.from(args)}; return {}; },
    });
    assert.equal(invocation.command, process.execPath);
    assert.deepEqual(invocation.args.slice(0, 2), ['--input-type=module', '-e']);
    const prefix = "import {runFocusedTests} from './scripts/test-execution.mjs'; ";
    assert(invocation.args[2].startsWith(prefix));
    const execution = {};
    runInNewContext(invocation.args[2].slice(prefix.length), {
      process: execution,
      runFocusedTests(kind, args, options) {
        assert.equal(kind, 'moon');
        assert.deepEqual(Array.from(args), moonArgs);
        assert.equal(options.timeout, timeout);
        assert.equal(options.evidenceScratch, '/original/owned/fixture');
        assert.equal(options.expectedTests, coreExpectedTests);
        return 7;
      },
    });
    assert.equal(execution.exitCode, 7, 'the original child failure must propagate');
  }
});


test('Native checkpoint producers retain the selected optimization and debug mode before the same full Core command', () => {
  const source=readFileSync(new URL('native-client-checkpoint-fixture.mjs',import.meta.url),'utf8');
  const before=source.indexOf('function originalReference(');
  const after=source.indexOf('export function nativeClientCheckpointFixture(',before);
  assert(before>=0&&after>before);
  for(const strip of [false,true]) for(const denyWarn of [false,true]) for(const release of [false,true]){
    const calls=[];
    const original=runInNewContext('('+source.slice(before,after).trim()+')',{
      spawnSync(node,args,options){
        assert.equal(node,process.execPath);assert.equal(options.cwd,'/original/root');
        const prefix='import {runFocusedTests} from "./scripts/test-execution.mjs"; ';
        assert(args[2].startsWith(prefix));
        const execution={argv:['node',...args.slice(3)],cwd:()=>'/original/root'};
        runInNewContext(args[2].slice(prefix.length),{process:execution,
          runFocusedTests(kind,argv,settings){assert.equal(kind,'moon');
            calls.push(Array.from(argv));assert.equal(settings.cwd,'/original/root');return 0;}});
        assert.equal(execution.exitCode,0);
        return {status:0,signal:null,stdout:'ACTQL_CLIENT_CHECKPOINT original-reference\n',stderr:''};
      },process:{execPath:process.execPath,stdout:{write(){}},stderr:{write(){}}},
    });
    assert.equal(original('/original/root',{},'original_wbtest.mbt',strip,denyWarn,release),'original-reference');
    assert.deepEqual(calls,[['--target','native',...(strip?['--strip']:[]),
      ...(denyWarn?['--deny-warn']:[]),...(release?['--release']:[]),'original_wbtest.mbt','--index','0']]);
  }
});

test('strict Native checkpoint producers share the full release child compilation mode without changing its selection', t => {
  const f = fixture(t);
  const commands = join(f.root, 'native-commands.jsonl');
  const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
    '--deny-warn', '--release', '--strip', '-j', '3', '--verbose'], {
    cwd: f.checkout, encoding: 'utf8', timeout: 10000,
    env: {...f.env, ACTQL_FIXTURE_NATIVE_COMMANDS: commands, MOONBIT_NEW_NATIVE:'0'},
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  const records = readFileSync(commands, 'utf8').trim().split('\n').map(JSON.parse);
  const calls = records.map(record => record.args);
  assert.equal(calls.length, 3);
  assert.deepEqual(records.map(record => record.backend), ['0', '0', '0']);
  const compilation = args => args.filter(arg =>
    ['--target', 'native', '--strip', '--deny-warn', '--release'].includes(arg)).sort();
  assert.deepEqual(calls[2], ['test', '--target', 'native',
    '--deny-warn', '--release', '--strip', '-j', '3', '--verbose', 'src/fixture-native']);
  assert(records[0].path === records[1].path);
  assert.equal(records[0].path, records[2].path,
    'the same selected compiler executable must populate and reuse the test cache');
  assert.match(records[0].path, /\/test-c-compiler:/u);
  assert.equal(records[2].compiler, records[0].compiler);
  assert.equal(records[2].allocator, records[0].allocator);
  for (const [index, file] of [
    'src/platform_native/client_host/run_checkpoint_wbtest.mbt',
    'src/platform_native/client_host/run_effect_receipt_wbtest.mbt',
  ].entries()) {
    assert.deepEqual(compilation(calls[index]), compilation(calls[2]),
      'original producer must not invalidate the full child compilation cache');
    assert.deepEqual(calls[index].slice(-3), [file, '--index', '0']);
  }
  f.verifyExternal();
});

test('full Native Core requires every HTTP case in its own peer profile and propagates transport failure', t => {
  for (const fail of [false, true]) {
    const f = fixture(t, {http: true});
    const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs', '--deny-warn'], {
      cwd: f.checkout, encoding: 'utf8', timeout: 10000,
      env: {...f.env, ACTQL_FIXTURE_HTTP_FAILED: fail ? '1' : '0'},
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null);
    assert.equal(result.status, fail ? 9 : 0, result.stdout + result.stderr);
    assert.match(result.stdout, /"ordinary":1,"http":1,"source":0,"scoped":0/u);
    assert.match(result.stdout, /Native Core HTTP profile: 1 required cases/u);
    assert.match(result.stdout, /ORIGINAL_HTTP_PROFILE_REQUIRED/u);
    if (fail) assert.doesNotMatch(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
    else assert.match(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
    f.verifyExternal();
  }
});

test('full Native Core routes the complete Source package to its existing peer owner and preserves failure',t=>{
  for(const fail of [false,true]) {
    const f=fixture(t,{sourcePeers:true}),commands=join(f.root,'native-commands.jsonl');
    const flags=['--deny-warn','--release','--strip','-j','2','--no-parallelize'];
    const result=spawnSync(process.execPath,['scripts/test-native-core.mjs',...flags],
      {cwd:f.checkout,encoding:'utf8',timeout:10000,
        env:{...f.env,ACTQL_FIXTURE_NATIVE_COMMANDS:commands,ACTQL_FIXTURE_SOURCE_FAILED:fail?'1':'0'}});
    assert.equal(result.status,fail?9:0,result.stdout+result.stderr);
    const calls=readFileSync(commands,'utf8').trim().split('\n').map(JSON.parse);
    assert.equal(calls.length,4,'two original checkpoint producers plus ordinary and Source children');
    const [ordinary,source]=calls.slice(2);
    assert.deepEqual(ordinary.args.filter(arg=>arg.startsWith('src/')),['src/fixture-native']);
    assert.deepEqual(source.args,['test','--target','native',...flags,
      'src/platform_native/remote_resident_source_compute_tests']);
    assert.equal(source.profile,'source-peers');
    assert.equal(source.path,ordinary.path,'same selected compiler profile');
    assert.match(result.stdout,/"ordinary":1,"http":0,"source":2,"scoped":0/u);
    assert.equal((result.stdout.match(/CORE_TARGET_FIXTURE_PROVISIONED/gu)??[]).length,1);
    assert.equal((result.stdout.match(/ORIGINAL_SOURCE_PROFILE_REQUIRED/gu)??[]).length,1);
    f.verifyExternal();
  }
});

function checkpointControlReplayFixture(t) {
  const sourceUrl = new URL('test-native-http-client.mjs', import.meta.url).href;
  const source = readFileSync(new URL(sourceUrl), 'utf8');
  const start = source.indexOf('  const runCheckpointControlReplay = async environment => {');
  const end = source.indexOf("  if (focus === 'core-http')", start);
  assert(start >= 0 && end > start);
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-checkpoint-control-handoff-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const calls = [], child = {};
  let exitCode = 0;
  const run = runInNewContext(source.slice(start, end).replaceAll('import.meta.url', 'sourceUrl') +
    '\nrunCheckpointControlReplay', {
    root, mkdtemp, join, URL, sourceUrl, moon: '/selected/moon', process: {execPath: process.execPath},
    nativeHttpLifetimeFixture(parent) {
      const library = join(parent, 'owned-no-network-transport');
      writeFileSync(library, 'Explicit source wiring fixture; not an actual Runtime');
      return {ACTQL_TEST_NATIVE_HTTP_LIFETIME_LIBRARY: library};
    },
    performance: {now: () => 0}, console: {error: () => {}},
    execFileSync: (command, args, options) => {calls.push({command, args: Array.from(args), options});},
    spawn: (command, args, options) => {calls.push({command, args: Array.from(args), options}); return child;},
    once: async (original, event) => {assert.equal(original, child); assert.equal(event, 'exit'); return [exitCode, null];},
  });
  return {root, calls, run, failRun: () => {exitCode = 2;}};
}

test('Native Checkpoint control replay supplies one owned Slot root to compilation and all selected cases', async t => {
  const f = checkpointControlReplayFixture(t);
  const environment = Object.freeze({ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT: '/unowned/ambient', ORIGINAL_PEER: 'retained'});
  await f.run(environment);
  assert.equal(f.calls.length, 2);
  const [compiled, executed] = f.calls;
  const selected = ['--target', 'native', '--jobs', '1',
    'src/cmd/native_remote_resident_site/effect_checkpoint_replay_wbtest.mbt'];
  assert.equal(compiled.command, '/selected/moon');
  assert.deepEqual(compiled.args, ['test', ...selected, '--build-only']);
  assert.equal(executed.command, process.execPath);
  assert.deepEqual(JSON.parse(executed.args.at(-1)), selected);
  assert.equal(compiled.options.env, executed.options.env);
  const slotRoot = executed.options.env.ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT;
  assert.equal(dirname(slotRoot), f.root);
  const stat = lstatSync(slotRoot);
  assert(stat.isDirectory() && !stat.isSymbolicLink());
  assert.equal(stat.mode & 0o777, 0o700);
  assert.equal(executed.options.env.ORIGINAL_PEER, 'retained');
  const image = executed.options.env.ACTQL_TEST_NATIVE_HTTP_LIFETIME_LIBRARY;
  assert.equal(dirname(image), slotRoot);
  assert.equal(readFileSync(image, 'utf8'), 'Explicit source wiring fixture; not an actual Runtime');
  assert.equal(environment.ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT, '/unowned/ambient');
  assert.deepEqual(readdirSync(f.root), [slotRoot.slice(f.root.length + 1)]);
});

test('Native Checkpoint control replay preserves child failure and leaves its Slot root with the invocation cleanup owner', async t => {
  const f = checkpointControlReplayFixture(t);
  f.failRun();
  await assert.rejects(f.run({}), /native Checkpoint control replay failed: 2/u);
  assert.equal(f.calls.length, 2);
  const slotRoot = f.calls[1].options.env.ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT;
  assert.equal(dirname(slotRoot), f.root);
  assert(lstatSync(slotRoot).isDirectory());
});

test('Core Source peer entrance retains complete package, Native target and nonzero count',()=>{
  const source=readFileSync(new URL('test-native-http-client.mjs',import.meta.url),'utf8');
  const start=source.indexOf("  if (focus === 'core-source') {"),end=source.indexOf('    const child = spawn(',start);
  assert(start>=0 && end>start);
  const body=source.slice(source.indexOf('    const args = ',start),end);
  const core=['--deny-warn','--release','--strip','-j','2','--no-parallelize',
    'src/platform_native/remote_resident_source_compute_tests'];
  const check=(args,count)=>runInNewContext(body,{assert,process:{env:{
    ACTQL_TEST_NATIVE_CORE_SOURCE_ARGS:JSON.stringify(args),ACTQL_TEST_NATIVE_CORE_SOURCE_COUNT:String(count)}}});
  check(core,78);
  for(const args of [[...core,'src/foreign'],[...core,'--index','0'],[...core,'--filter=one'],
    [...core,'--target','js'],[...core.slice(0,-1),core.at(-1)+'/retained_compute_wbtest.mbt']])
    assert.throws(()=>check(args,78));
  for(const count of [0,-1,1.5,'unknown'])assert.throws(()=>check(core,count));
  const completed=source.indexOf('    assert.equal(code, 0, `Native Core Source fixture failed:',end);
  const closed=source.indexOf('    break verification;',completed);
  assert(completed>=0 && closed>completed);
  const peer=(targets,created,code=0)=>runInNewContext(source.slice(completed,closed),{
    assert:{equal:assert.equal,deepEqual:(actual,expected)=>
      assert.deepEqual(actual,JSON.parse(JSON.stringify(expected)))},code,signal:null,
    bearerServers:{effectTargets:()=>targets,effectCreatedValues:()=>created}});
  const created=[{Id:'001000000000001AAA',Count__c:3}];
  peer({reads:3,writes:1},created);
  for(const targets of [{reads:2,writes:1},{reads:3,writes:0},{reads:3,writes:2}])
    assert.throws(()=>peer(targets,created));
  for(const rows of [[],[{Id:'001000000000001AAA',Count__c:4}],[...created,...created]])
    assert.throws(()=>peer({reads:3,writes:1},rows));
  assert.throws(()=>peer({reads:3,writes:1},created,1));

});

test('focused retained proposal modes preserve independently authored reads and no writes',()=>{
  const source=readFileSync(new URL('test-native-salesforce-effect-preview.mjs',import.meta.url),'utf8');
  const observation=/^    assert.deepEqual\(bearer.effectTargets\(\),.*$/mu.exec(source)?.[0];assert(observation);
  for(const [complete,runtime,reads] of [[true,false,2],[false,false,1],[false,true,0]])
    runInNewContext(observation,{assert:{deepEqual:(actual,expected)=>
      assert.deepEqual(actual,JSON.parse(JSON.stringify(expected)))},bearer:{effectTargets:()=>({reads,writes:0})},
      completeRetainedProposals:complete,residentMappedCreate:false,residentEffectRuntimeCapture:runtime,
      residentApprovedRow:false});
});

test('full Native Core requires both ordinary and selected profiles and propagates selected failure', t => {
  for (const fail of [false, true]) {
    const f = fixture(t, {scoped: true}), commands = join(f.root, 'native-commands.jsonl');
    const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
      '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize'], {
      cwd: f.checkout, encoding: 'utf8', timeout: 10000,
      env: {...f.env, ACTQL_FIXTURE_NATIVE_COMMANDS: commands,
        ACTQL_FIXTURE_SCOPED_FAIL: fail ? '1' : '0'},
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null);
    assert.equal(result.status, fail ? 7 : 0, result.stdout + result.stderr);
    const calls = readFileSync(commands, 'utf8').trim().split('\n').map(JSON.parse);
    assert.equal(calls.length, fail ? 4 : 10,
      'two original checkpoint producers, ordinary Core and every selected case until failure');
    const [ordinary, ...selectedCases] = calls.slice(2);
    const selected = selectedCases[0];
    assert.equal(ordinary.profile, 'ordinary');
    assert.equal(ordinary.installedProcess.endsWith('/installed-process'), true);
    assert.equal(ordinary.sqliteComponent, undefined);
    assert.equal(ordinary.cryptoComponent, undefined);
    for (const producer of calls.slice(0, 2)) assert.equal(producer.installedProcess, undefined);
    for (const selected of selectedCases) assert.notEqual(selected.installedProcess, ordinary.installedProcess);
    assert.equal(selected.profile, 'runtime-values');
    assert.deepEqual(ordinary.args.filter(value => value.startsWith('src/')), [
      'src/cmd/native_client/ordinary_wbtest.mbt',
      'src/cmd/native_client/local_command_business_wbtest.mbt',
      'src/platform_native/host_bootstrap/root_control_unavailable_wbtest.mbt',
    ]);
    assert.deepEqual(selectedCases.flatMap(value => value.args.filter(arg => arg.startsWith('src/'))),
      ['src/cmd/native_client/local_command_business_wbtest.mbt',
        ...(!fail ? ['src/cmd/native_client/local_command_business_cleanup_wbtest.mbt',
          ...Array(3).fill('src/platform_native/host_bootstrap/root_control_physical_scoped_wbtest.mbt'),
          'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt',
          'src/platform_native/row_source/capture_physical_scoped_wbtest.mbt'] : [])]);
    assert.equal(new Set(selectedCases.map(value => value.installedProcess)).size, selectedCases.length,
      'every physical case owns a fresh original backing namespace');
    for (const value of selectedCases) {
      const rootControlIndex = selectedCases.filter(candidate => candidate.args.includes(
        'src/platform_native/host_bootstrap/root_control_physical_scoped_wbtest.mbt')).indexOf(value);
      assert.equal(value.args[value.args.indexOf('--index') + 1], String(Math.max(0, rootControlIndex)));
    }
    if (!fail) {
      assert.deepEqual(selectedCases.map(value => value.profile),
        ['runtime-values', 'runtime-values', ...Array(5).fill('scoped-review-values')]);
      const targets = selectedCases.map(value => value.args[value.args.indexOf('--target-dir') + 1]);
      assert.equal(targets[0], targets[1], 'reuse the same compiled software within a profile');
      assert.notEqual(targets[0], targets[2], 'distinct allocator profiles require distinct targets');
      assert.equal(targets[2], targets[3], 'file capture retains the Read-owned allocation profile');
    }
    assert.match(ordinary.path, /\/test-c-compiler:/u);
    assert.equal(selected.path, f.env.PATH, 'selected preparation starts from the original PATH');
    assert.deepEqual(selected.args.slice(0, 3), ['test', '--target', 'native']);
    const target = selected.args[selected.args.indexOf('--target-dir') + 1];
    assert(target.startsWith(join(f.checkout, '_build/native-core-scoped/profile-')));
    assert.match(result.stdout, /"ordinary":3,"http":0,"source":0,"scoped":7,"physical":6,"repeatedGeometry":1/u);
    assert.equal((result.stdout.match(/CORE_TARGET_FIXTURE_PROVISIONED/gu) ?? []).length, 1,
      'only ordinary Core executes the Salesforce target oracle');
    const namespace = /Native core SQLite namespace: (.*)/u.exec(result.stdout)?.[1];
    assert(namespace);
    assert.equal(existsSync(namespace), fail);
    assert.equal(existsSync(target), true, 'preserve selected compiler outputs for diagnosis');
    f.verifyExternal();
  }
});


test('Native project configuration inputs belong only to the selected fresh child', t => {
  const f = fixture(t);
  for (const args of [[], ['--deny-warn', 'src/cmd/native_client/local_project_configuration_wbtest.mbt']]) {
    const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs', ...args], {
      cwd: f.checkout, encoding: 'utf8', timeout: 10000,
      env: {...f.env, ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: f.parent},
    });
    assert.ifError(result.error); assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /PROJECT_CONFIGURATION_FIXTURE_PROVISIONED/u);
    const owned = /CHILD_ROOT=(.*)/u.exec(result.stdout)?.[1];
    assert(owned); assert.equal(existsSync(owned), false);
    assert.equal(existsSync(join(f.parent, 'project-configuration')), false);
    f.verifyExternal();
  }
  const unrelated = run(f, {ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: f.parent});
  assert.equal(unrelated.status, 0, unrelated.stderr);
  assert.doesNotMatch(unrelated.stdout, /PROJECT_CONFIGURATION_FIXTURE_PROVISIONED/u);
  f.verifyExternal();
});

test('failed Native project child retains its own fixtures and cannot adopt caller input', t => {
  const f = fixture(t);
  const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
    '--deny-warn', 'src/cmd/native_client/local_project_configuration_wbtest.mbt'], {
    cwd: f.checkout, encoding: 'utf8', timeout: 10000,
    env: {...f.env, PROBE_MODE: 'failed', ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: f.parent},
  });
  assert.ifError(result.error); assert.equal(result.signal, null); assert.equal(result.status, 7);
  const owned = /CHILD_ROOT=(.*)/u.exec(result.stdout)?.[1];
  assert(owned); assert.equal(existsSync(join(owned, 'project-configuration/actql.config.json')), true);
  assert.match(result.stderr, /original native child failure/u);
  assert.match(result.stderr, /test failed; scratch kept:/u);
  f.verifyExternal();
});


test('Native checkpoint and full child keep the selected backend and explicit compiler profile', t => {
  for (const backend of ['0', '1']) {
    const f = fixture(t), commands = join(f.root, 'native-commands.jsonl');
    const compiler = join(f.bin, 'explicit-original-cc');
    const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
      '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose'], {
      cwd: f.checkout, encoding: 'utf8', timeout: 10000,
      env: {...f.env, ACTQL_FIXTURE_NATIVE_COMMANDS: commands,
        MOONBIT_NEW_NATIVE: backend, MOON_CC: compiler},
    });
    assert.ifError(result.error); assert.equal(result.signal, null); assert.equal(result.status, 0, result.stderr);
    const records = readFileSync(commands, 'utf8').trim().split('\n').map(JSON.parse);
    assert.equal(records.length, 3);
    for (const record of records) {
      assert.equal(record.backend, backend);
      assert.equal(record.compiler, compiler);
      assert.equal(record.path, f.env.PATH);
      assert.equal(record.allocator, records[0].allocator);
    }
    assert.deepEqual(records[2].args, ['test', '--target', 'native',
      '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize', '--verbose', 'src/fixture-native']);
    f.verifyExternal();
  }
});

test('Core Native prepares existing scoped producer dependencies before expensive consumers', () => {
  const steps = workflow.jobs.core.steps;
  const dependencies = steps.find(step => step.name === 'Install existing scoped component producer dependencies');
  assert(dependencies, 'the Native scoped component producer imports the pinned Python dependencies');
  const existing = workflow.jobs['native-macos'].steps.find(step => step.name === dependencies.name);
  assert(existing);
  assert.equal(dependencies.run, existing.run, 'use the same existing pinned selection, not another version list');
  assert.equal(dependencies.if, "${{ matrix.target == 'native' }}");
  assert.equal(dependencies['continue-on-error'], undefined);
  const setup = steps.find(step => step.uses === './.github/actions/setup-toolchain');
  assert.equal(setup.with.python, 'true');
  const platform = steps.findIndex(step => step.name === 'Require the supported Core Native platform');
  const preparation = steps.indexOf(dependencies);
  assert(steps.indexOf(setup) < platform && platform < preparation);
  for (const name of ['Check common core', 'Test actual Native Reader callbacks and original empty compiler driver',
    'Test common core']) {
    assert(preparation < steps.findIndex(step => step.name === name), name);
  }
  for (const target of ['js', 'wasm', 'native']) {
    assert.equal(runInNewContext(dependencies.if.slice(3, -2), {matrix: {target}}, {timeout: 100}),
      target === 'native');
  }
});

test('full Native Core provisions exact current relation Work inputs and rejects zero selected execution', t => {
  for (const zero of [false, true]) {
    const f = fixture(t, {scoped: true, relationWork: true});
    const commands = join(f.root, 'relation-commands.jsonl');
    const result = spawnSync(process.execPath, ['scripts/test-native-core.mjs',
      '--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize'], {
      cwd: f.checkout, encoding: 'utf8', timeout: 20000,
      env: {...f.env, ACTQL_FIXTURE_NATIVE_COMMANDS: commands,
        ACTQL_FIXTURE_RELATION_ZERO: zero ? '1' : '0',
        ACTQL_TEST_RELATION_ORIGINAL_ROOT: f.parent,
        ACTQL_TEST_RELATION_RUNTIME_ROOT: f.parent,
        ACTQL_TEST_RELATION_ORIGINAL_MODE: 'wrong-resource'},
    });
    assert.ifError(result.error); assert.equal(result.signal, null);
    assert.equal(result.status === 0, !zero, result.stdout + result.stderr);
    const calls = readFileSync(commands, 'utf8').trim().split('\n').map(JSON.parse);
    const physical = calls.slice(3);
    // Preserve the three original root-control cases alongside relation Work.
    assert.deepEqual(physical.map(call => [call.args.find(arg => arg.startsWith('src/')),
      call.args[call.args.indexOf('--index') + 1]]), [
      ['src/cmd/native_client/local_command_business_wbtest.mbt', '0'],
      ['src/cmd/native_client/local_command_business_cleanup_wbtest.mbt', '0'],
      ...['0', '1', '2'].map(index =>
        ['src/platform_native/host_bootstrap/root_control_physical_scoped_wbtest.mbt', index]),
      ['src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt', '0'],
      ['src/platform_native/row_source/capture_physical_scoped_wbtest.mbt', '0'],
      ['src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt', '0'],
    ]);
    const selected = physical.find(call => call.args.includes(
      'src/platform_native/relation_file_work_tests/relation_file_original_physical_scoped_test.mbt'));
    assert(selected);
    assert.equal(selected.profile, 'scoped-review-values');
    assert.equal(selected.args[selected.args.indexOf('--index') + 1], '0');
    assert.equal(selected.installedProcess, undefined);
    assert.notEqual(selected.relationRoot, f.parent);
    assert.notEqual(selected.relationRuntime, f.parent);
    for (const call of calls.slice(2).filter(call => call !== selected)) {
      assert.equal(call.relationRoot, undefined);
      assert.equal(call.relationRuntime, undefined);
    }
    assert.deepEqual(physical.map(call => call.profile), ['runtime-values', 'runtime-values',
      ...Array(6).fill('scoped-review-values')]);
    assert.equal((result.stdout.match(/CURRENT_RELATION_COMPONENT_INPUTS_REQUIRED/gu) ?? []).length, 1);
    assert.match(result.stdout, /"scoped":8,"physical":7,"repeatedGeometry":1/u);
    assert.equal(existsSync(selected.relationRoot), zero, 'failure preserves originals; no reset or reuse');
    f.verifyExternal();
  }
});
