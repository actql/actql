import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runMeasuredNativeTests} from './native-core-measured-tests.mjs';
import {runFocusedTests} from './test-execution.mjs';

test('Native compilation and execution share original arguments, environment and one deadline', () => {
  const args = ['--target', 'native', '--release', '--strip', 'src/original'];
  const env = {original: 'unchanged'}, phases = [], calls = [];
  let clock = 0;
  const code = runMeasuredNativeTests(args, {timeout: 1000, env, expectedTests: 7, evidenceScratch: '/owned'}, {
    now: () => clock, report: value => phases.push(value),
    evidence(options) {
      assert.equal(options.env, env);
      return {capture(command, selected, options) {
        calls.push('compile');
        assert.equal(command, 'moon');
        assert.deepEqual(selected, ['test', ...args, '--build-only']);
        assert.equal(options.env, env); assert.equal(options.timeout, 1000);
        clock = 700;
        return {result: {status: 0, signal: null}};
      }, finish(outcome) { assert.equal(outcome, 'passed'); }};
    },
    execute(kind, selected, options) {
      calls.push('execute');
      assert.equal(kind, 'moon'); assert.equal(selected, args);
      assert.equal(options.env, env); assert.equal(options.expectedTests, 7);
      assert.equal(options.timeout, 300, 'Compilation cannot grant another execution budget');
      clock = 900;
      return 9;
    },
  });
  assert.equal(code, 9, 'Failed tests remain failed after successful compilation');
  assert.deepEqual(calls, ['compile', 'execute']);
  assert.deepEqual(phases, [{phase: 'compile', milliseconds: 700, succeeded: true},
    {phase: 'execute', milliseconds: 200, succeeded: false}]);
});

test('Native failed compilation, timeout and incomplete evidence never enter execution', () => {
  for (const failure of [{status: 4}, {status: null, signal: 'SIGTERM'},
    {status: null, error: {code: 'ETIMEDOUT'}}, {status: 0, writeFailure: new Error('full')}]) {
    const code = runMeasuredNativeTests(['--target', 'native'], {timeout: 10, evidenceScratch: '/owned'}, {
      now: () => 0, report() {}, execute() { assert.fail('Uncompiled tests cannot execute'); },
      evidence: () => ({capture: () => ({result: failure, writeFailure: failure.writeFailure}),
        finish: status => assert.equal(status, 'failed')}),
    });
    assert.equal(code, failure.status || 1);
  }
  let clock = 0;
  assert.equal(runMeasuredNativeTests(['--target', 'native'], {timeout: 10, evidenceScratch: '/owned'}, {
    now: () => clock, report() {}, execute() { assert.fail('Expired budget cannot execute'); },
    evidence: () => ({capture() { clock = 10; return {result: {status: 0}}; }, finish() {}}),
  }), 1);
});

test('actual Native execution reuses every compiled original and executes one original case', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-ci-phase-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  writeFileSync(join(root, 'moon.mod'), 'name = "fixture/native_ci_phase"\nversion = "0.0.0"\n');
  writeFileSync(join(root, 'moon.pkg'), '');
  writeFileSync(join(root, 'main.mbt'), 'test "original once" { assert_eq(42, 42) }\n');
  const outputs = () => readdirSync(join(root, '_build'), {recursive: true}).filter(path =>
    /\.(?:exe|o|c|core)$/u.test(path)).sort().map(path => {
    const full = join(root, '_build', path), stat = statSync(full);
    return [path, stat.mtimeMs, stat.size, createHash('sha256').update(readFileSync(full)).digest('hex')];
  });
  const phases = [];
  let executions = 0;
  const code = runMeasuredNativeTests(['--target', 'native', '--release', '--deny-warn'], {
    cwd: root, timeout: 60_000, expectedTests: 1, evidenceScratch: join(root, 'evidence'),
  }, {report: value => phases.push(value), execute(kind, args, options) {
    const before = outputs();
    assert(before.some(([path]) => path.endsWith('.exe')), 'The first phase must really compile a test executable');
    const code = runFocusedTests(kind, args, options);
    executions++;
    assert.deepEqual(outputs(), before, 'Execution must not regenerate C, Core, objects or executable originals');
    return code;
  }});
  assert.equal(code, 0);
  assert.equal(executions, 1);
  assert.deepEqual(phases.map(value => [value.phase, value.succeeded]), [['compile', true], ['execute', true]]);
  assert(phases.every(value => Number.isSafeInteger(value.milliseconds) && value.milliseconds >= 0));
});
