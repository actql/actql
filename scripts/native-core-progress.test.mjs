import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {coreChildProgress, observeCoreChildProgress} from './native-compiler-stop-diagnostic.mjs';

test('Core progress admits only original descendants and exposes generated compile paths, never raw arguments', () => {
  const root = '/checkout/original';
  const snapshot = [
    '100 1 00:10 /node --input-type=module -e secret-wrapper',
    '101 100 00:09 /pinned/bin/moon test --target native --release secret-token',
    '102 101 00:08 /clang -cc1 -O2 -o /checkout/original/_build/native/release/test/check_environment/check_environment.blackbox_test.o /checkout/original/_build/native/release/test/check_environment/check_environment.blackbox_test.c',
    '103 1 00:07 /clang /foreign/_build/native/release/test/private.c',
    '104 101 00:06 /checkout/original/_build/native/release/test/execution_relation/execution_relation.whitebox_test.exe private-request',
    '105 101 00:05 /pinned/bin/moonc build-package /checkout/original/src/execution_relation/a.mbt secret-key',
  ].join('\n');
  const records = coreChildProgress(snapshot, 100, root);
  assert.equal(records[2].command, 'clang');
  assert.deepEqual(records[2].flags, ['-O2']);
  assert.deepEqual(records.map(({pid, phase, source}) => ({pid, phase, source})), [
    {pid: 100, phase: 'wrapper', source: undefined},
    {pid: 101, phase: 'moon', source: undefined},
    {pid: 102, phase: 'c-compile', source: '_build/native/release/test/check_environment/check_environment.blackbox_test.c'},
    {pid: 104, phase: 'test', source: '_build/native/release/test/execution_relation/execution_relation.whitebox_test.exe'},
    {pid: 105, phase: 'moon-compile', source: 'src/execution_relation/a.mbt'},
  ]);
  const serialized = JSON.stringify(records);
  for (const forbidden of ['secret', 'private-request', '/foreign', '/pinned', ' -O2', 'args']) {
    assert(!serialized.includes(forbidden), forbidden);
  }
  assert.deepEqual(coreChildProgress(snapshot, 999, root), []);
  assert.deepEqual(coreChildProgress('100 101 00:01 /node\n101 100 00:01 /moon', 999, root), []);
});

test('Core progress reports a live original child before exit and stops naturally without changing its result', async () => {
  const child = spawn(process.execPath, ['-e', 'setTimeout(() => process.exit(7), 750)'],
    {stdio: 'ignore'});
  const records = [];
  const stop = observeCoreChildProgress(child, {
    root: fileURLToPath(new URL('../', import.meta.url)), intervalMs: 25,
    write: value => records.push({value, beforeExit: child.exitCode === null}),
  });
  const [code, signal] = await once(child, 'close');
  stop();
  assert.equal(code, 7);
  assert.equal(signal, null);
  assert(records.some(({value, beforeExit}) => beforeExit &&
    value.observation === 'observed' && value.processes.some(p => p.pid === child.pid)));
  const count = records.length;
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(records.length, count);
});

test('Core progress keeps unavailable process metadata observational and never signals the original child', async () => {
  const child = {pid: 123, exitCode: null, signalCode: null, once() {},
    kill() { throw new Error('Observer must never signal'); }};
  const records = [];
  const stop = observeCoreChildProgress(child, {root: '/checkout', intervalMs: 1000,
    run(_command, _args, _options, callback) { callback(Object.assign(new Error('private'), {code: 'EPERM'})); },
    write: value => records.push(value)});
  stop();
  assert.equal(records.length, 1);
  assert.equal(records[0].observation, 'unavailable');
  assert(!JSON.stringify(records).includes('private'));
});

test('Core progress observer and output failures cannot replace the original caller result', async () => {
  const child = {pid: 123, exitCode: null, signalCode: null, once() {}};
  for (const run of [() => {throw new Error('snapshot failed');},
    (_command, _args, _options, callback) => callback(null, '123 1 00:01 /node')]) {
    const stop = observeCoreChildProgress(child, {root: '/checkout', run,
      write() {throw new Error('output failed');}});
    stop();
  }
  const source = readFileSync(new URL('test-native-salesforce-effect-preview.mjs', import.meta.url), 'utf8');
  const begin = source.indexOf('  const stopProgress = compilerDriver');
  const end = source.indexOf('  if (code !== 0 && compilerDriver)', begin);
  assert(begin >= 0 && end > begin);
  for (const compilerDriver of [false, true]) {
    const original = spawn(process.execPath, ['-e', 'process.exit(7)'], {stdio: 'ignore'});
    let starts = 0, stops = 0;
    const result = await runInNewContext('(async () => {\n' + source.slice(begin, end) +
      '\n return {code, signal}; })()', {
      child: original, compilerDriver, once, process: {
        cwd: () => '/original', stdout: process.stdout, stderr: process.stderr,
      },
      observeCoreChildProgress(child, {root}) {
        assert.equal(child, original); assert.equal(root, '/original'); starts++;
        return () => {stops++;};
      },
    });
    assert.equal(result.code, 7);
    assert.equal(result.signal, null);
    assert.equal(starts, compilerDriver ? 1 : 0);
    assert.equal(stops, starts);
  }
});
