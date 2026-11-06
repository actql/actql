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
import {failedCoreDriver, diagnoseFailedCoreDriver} from './native-compiler-stop-diagnostic.mjs';
import {runFocusedTests} from './test-execution.mjs';
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
import './native-process-region-fixture.test.mjs';

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

function fixture(t, {scoped = false, http = false} = {}) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-native-namespace-test-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const checkout = join(root, 'checkout');
  const parent = join(root, 'sqlite');
  const bin = join(root, 'bin');
  for (const path of [join(checkout, 'scripts'),
    join(checkout, '.github/workflows'), parent, bin]) mkdirSync(path, {recursive: true});
  for (const name of ['test-native-core.mjs', 'native-completed-restoration-fixture.mjs', 'owned-scratch.mjs',
    'native-core-c-compiler.mjs', 'native-core-test-selection.mjs', 'verification-actions.mjs',
    'native-client-checkpoint-fixture.mjs', 'native-private-host-fixture.mjs',
    'native-filesystem-observation-fixture.mjs',
    'native-runtime-reader-custody-fixture.mjs', 'native-project-configuration-fixture.mjs',
    'local-checks.mjs', 'local-checks-guard.mjs', 'local-checks-supervisor.mjs',
    'local-checks-policy.mjs', 'test-execution.mjs', 'packed-query-evidence.mjs']) {
    copyFileSync(new URL(name, import.meta.url), join(checkout, 'scripts', name));
  }
  // This fixture observes wrapper routing. The original ten process/channel
  // cases exercise the physical C/Rust leaf with the real preparation helper.
  writeFileSync(join(checkout, 'scripts/native-process-region-fixture.mjs'), `
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
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
  copyFileSync(new URL('fixtures/native-effect-resolution-fixture.mjs', import.meta.url),
    join(checkout, 'scripts/fixtures/native-effect-resolution-fixture.mjs'));
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
  if (scoped) {
    mkdirSync(join(checkout, 'src/cmd/native_client'), {recursive: true});
    for (const name of ['ordinary_wbtest.mbt', 'local_command_business_wbtest.mbt',
      'local_command_business_cleanup_wbtest.mbt']) {
      writeFileSync(join(checkout, 'src/cmd/native_client', name), 'Original compiler-input fixture\n');
    }
    mkdirSync(join(checkout, 'src/platform_native/installed_arena_control'), {recursive: true});
    writeFileSync(join(checkout,
      'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt'),
    'Original compiler-input fixture\n');
    // This test observes routing only. Physical compilation is covered by the
    // selected-provider helper and actual Native cases, not this explicit port.
    writeFileSync(join(checkout, 'scripts/native-core-scoped-profile.mjs'), `
import assert from 'node:assert/strict';
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
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
    writeFileSync(join(checkout, 'scripts/native-core-scoped-fixture.mjs'), `
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
export function nativeCoreScopedFixture(namespace, {cryptoLibrary, sqliteLibrary}) {
  const root = join(namespace, 'installed-process'); mkdirSync(root, {mode: 0o700});
  return {ACTQL_TEST_INSTALLED_PROCESS_ROOT: root,
    ACTQL_TEST_CRYPTO_COMPONENT: cryptoLibrary, ACTQL_TEST_SQLITE_COMPONENT: sqliteLibrary};
}
`);
    writeFileSync(join(checkout, 'scripts/native-runtime-bundle-fixture.mjs'), `
import assert from 'node:assert/strict';
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
export function prepareNativeRuntimeBundleLibraries(root, destination, options) {
  assert(destination.startsWith(join(root, '_build/native-core-scoped/')));
  assert.equal(options.seconds, 900);
  mkdirSync(destination);
  return {sqliteLibrary: join(destination, 'sqlite-component.dylib'),
    cryptoLibrary: join(destination, 'crypto-component.dylib')};
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
      [{index:0,name:'original fixture case',attrs:[],line_number:1}]]));
  writeFileSync(metadata, JSON.stringify({tests}));
  process.exit(0);
}
assert.deepEqual(process.argv.slice(2, 5), ['test', '--target', 'native']);
if (process.argv.includes('--dry-run')) {
  if (process.env.ACTQL_FIXTURE_CORE_SCOPED === '1') {
    console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/cmd/native_client/driver.mbt ' +
      '--output-metadata _build/native/release/test/cmd/native_client/info.json ' +
      ['ordinary_wbtest.mbt','local_command_business_wbtest.mbt','local_command_business_cleanup_wbtest.mbt']
        .map(name => 'src/cmd/native_client/' + name).join(' ') +
      ' --target native --pkg-name fixture/native_client --driver-kind whitebox');
    console.log('moon generate-test-driver ' +
      '--output-driver _build/native/release/test/platform_native/installed_arena_control/driver.mbt ' +
      '--output-metadata _build/native/release/test/platform_native/installed_arena_control/info.json ' +
      'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt ' +
      '--target native --pkg-name fixture/arena --driver-kind whitebox');
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
      installedProcess:process.env.ACTQL_TEST_INSTALLED_PROCESS_ROOT}) + '\\n');
}
if (['runtime-values','scoped-review-values'].includes(process.env.ACTQL_FIXTURE_PROFILE)) {
  assert(process.argv.includes('--target-dir'));
  assert(process.env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT);
  assert(process.env.ACTQL_TEST_NATIVE_UNCLOSED_SQLITE_FIXTURE);
  assert.equal(statSync(process.env.ACTQL_TEST_INSTALLED_PROCESS_ROOT).mode & 0o777, 0o700);
  assert(process.env.ACTQL_TEST_SQLITE_COMPONENT.endsWith('/sqlite-component.dylib'));
  assert(process.env.ACTQL_TEST_CRYPTO_COMPONENT.endsWith('/crypto-component.dylib'));
  assert.notEqual(process.env.ACTQL_TEST_SQLITE_COMPONENT, process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY);
  assert.notEqual(process.env.ACTQL_TEST_CRYPTO_COMPONENT, process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY);
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
    ...(http ? {ACTQL_FIXTURE_CORE_HTTP: '1'} : {}),
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
    const command=coreStep.run.replaceAll('${{ matrix.target }}',target);
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
    assert.match(result.stdout, /"ordinary":1,"http":1,"scoped":0/u);
    assert.match(result.stdout, /Native Core HTTP profile: 1 required cases/u);
    assert.match(result.stdout, /ORIGINAL_HTTP_PROFILE_REQUIRED/u);
    if (fail) assert.doesNotMatch(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
    else assert.match(result.stdout, /CORE_TARGET_FIXTURE_PROVISIONED/u);
    f.verifyExternal();
  }
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
    assert.equal(calls.length, fail ? 4 : 6,
      'two original checkpoint producers, ordinary Core and every selected case until failure');
    const [ordinary, ...selectedCases] = calls.slice(2);
    const selected = selectedCases[0];
    assert.equal(ordinary.profile, 'ordinary');
    assert.equal(selected.profile, 'runtime-values');
    assert.deepEqual(ordinary.args.filter(value => value.startsWith('src/')), [
      'src/cmd/native_client/ordinary_wbtest.mbt',
      'src/cmd/native_client/local_command_business_wbtest.mbt',
    ]);
    assert.deepEqual(selectedCases.flatMap(value => value.args.filter(arg => arg.startsWith('src/'))),
      ['src/cmd/native_client/local_command_business_wbtest.mbt',
        ...(!fail ? ['src/cmd/native_client/local_command_business_cleanup_wbtest.mbt',
          'src/platform_native/installed_arena_control/original_read_consumer_scoped_wbtest.mbt'] : [])]);
    assert.equal(new Set(selectedCases.map(value => value.installedProcess)).size, selectedCases.length,
      'every physical case owns a fresh original backing namespace');
    for (const value of selectedCases) {
      assert.equal(value.args[value.args.indexOf('--index') + 1], '0');
    }
    if (!fail) {
      assert.deepEqual(selectedCases.map(value => value.profile),
        ['runtime-values', 'runtime-values', 'scoped-review-values']);
      const targets = selectedCases.map(value => value.args[value.args.indexOf('--target-dir') + 1]);
      assert.equal(targets[0], targets[1], 'reuse the same compiled software within a profile');
      assert.notEqual(targets[0], targets[2], 'distinct allocator profiles require distinct targets');
    }
    assert.match(ordinary.path, /\/test-c-compiler:/u);
    assert.equal(selected.path, f.env.PATH, 'selected preparation starts from the original PATH');
    assert.deepEqual(selected.args.slice(0, 3), ['test', '--target', 'native']);
    const target = selected.args[selected.args.indexOf('--target-dir') + 1];
    assert(target.startsWith(join(f.checkout, '_build/native-core-scoped/profile-')));
    assert.match(result.stdout, /"ordinary":2,"http":0,"scoped":3,"physical":2,"repeatedGeometry":1/u);
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
