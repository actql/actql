import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nodeTestArguments, parseTestExecution, testExecutionResult}
  from './test-execution.mjs';

const childEnv = {...process.env};
delete childEnv.NODE_TEST_CONTEXT;

const counts = (values = {}) => ({tests: 0, passed: 0, failed: 0,
  cancelled: 0, skipped: 0, todo: 0, ...values});
const summary = (values, file) => 'ACTQL_TEST_SUMMARY ' + JSON.stringify({
  success: true, counts: counts(values), ...(file ? {file} : {}),
}) + '\n';
const output = values => summary(values, 'selected.test.mjs') + summary(values);
const checked = (kind, stdout, extra = {}) => testExecutionResult(kind,
  kind, ['--filter', 'selected'], {status: 0, stdout, ...extra});

test('Node fixture counts cases, not nested suite/TAP headings or synthetic files', () => {
  const nested = '# Subtest: suite\n    ok 1 - pass\nok 1 - suite\n' +
    output({tests: 2, passed: 1, skipped: 1});
  assert.deepEqual(parseTestExecution('node', nested).counts,
    counts({tests: 2, passed: 1, skipped: 1}));
  assert.equal(checked('node', nested).status, 0);
  const synthetic = summary({}, 'empty.test.mjs') + summary({tests: 1, passed: 1});
  assert.equal(checked('node', synthetic).status, 1);
  assert.deepEqual(checked('node', synthetic).counts, counts());
});

for (const [name, values, status] of [
  ['zero', {}, 1], ['pass', {tests: 2, passed: 2}, 0],
  ['failure', {tests: 2, passed: 1, failed: 1}, 1],
  ['skip-only', {tests: 2, skipped: 2}, 1],
  ['todo-only', {tests: 1, todo: 1}, 1],
  ['cancellation', {tests: 1, cancelled: 1}, 1],
]) {
  test(`Node ${name} fixture`, () => {
    const result = checked('node', output(values));
    assert.equal(result.status, status);
    assert.deepEqual(result.counts, counts(values));
    assert.match(result.diagnostic, /--filter.*selected.*counts=/u);
  });
}

test('Node missing, malformed, inconsistent and duplicate summaries fail closed', () => {
  for (const text of ['', 'ACTQL_TEST_SUMMARY {\n', summary({}),
    summary({tests: 1, passed: -1}, 'a') + summary({}),
    output({tests: 1, passed: 2}), output({}) + summary({}),
    summary({}, 'a') + summary({}, 'a') + summary({})]) {
    assert.equal(checked('node', text).status, 1);
    assert.equal(checked('node', text).counts, null);
  }
});

test('MoonBit exact pinned summary, zero/skip-only and failure fixtures', () => {
  for (const [text, status, total] of [
    ['Total tests: 0, passed: 0, failed: 0.\n', 1, 0],
    ['Total tests: 0, passed: 0, failed: 0.\nWarning: no test entry found.\n', 1, 0],
    ['Total tests: 2, passed: 2, failed: 0.\n', 0, 2],
    ['Total tests: 2, passed: 1, failed: 1.\n', 1, 2],
  ]) {
    const result = checked('moon', text);
    assert.equal(result.status, status);
    assert.equal(result.counts.tests, total);
    assert.equal(result.counts.skipped, null, 'the tool does not report skipped counts');
  }
  const mixed = 'Total tests: 1, passed: 1, failed: 0.\nTotal tests: 0, passed: 0, failed: 0.\n';
  assert.equal(checked('moon', mixed).status, 1, 'one target cannot hide another zero target');
  for (const text of ['', 'Total tests: unknown\n', 'Total tests: 2, passed: 1, failed: 0.\n']) {
    assert.equal(checked('moon', text).status, 1);
  }
});

test('process exit codes, signals and spawn errors cannot be replaced by a green summary', () => {
  const pass = output({tests: 1, passed: 1});
  assert.equal(checked('node', pass.replaceAll('"success":true', '"success":false')).status, 1);
  assert.equal(checked('node', pass, {status: 7}).status, 7);
  assert.equal(checked('node', '', {status: 3}).status, 3);
  assert.equal(checked('node', pass, {status: null, signal: 'SIGTERM'}).status, 143);
  assert.equal(checked('moon', '', {status: null, error: {code: 'ENOENT'}}).status, 1);
});

test('unsupported reporter, watch and isolation overrides cannot bypass the guard', () => {
  for (const argument of ['--test-reporter=spec', '--test-reporter-destination=out',
    '--test-isolation=none', '--watch']) {
    assert.throws(() => nodeTestArguments([argument]), /Focused verification/u);
  }
});

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-test-execution-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  return root;
}

test('real Node focused selection passes, unmatched/empty/skip/cancel/failure do not', t => {
  const root = fixture(t);
  const file = join(root, 'selected.mjs');
  writeFileSync(file, `import {test, describe} from 'node:test';
    describe('nested suite', () => {
      test('selected pass', () => {});
      test.skip('selected skip', () => {});
      test('selected failure', () => { throw new Error('expected failure'); });
      test('selected cancel', {timeout: 20}, () => new Promise(() => {}));
    });\n`);
  for (const [pattern, success, expected] of [
    ['selected pass', true, {tests: 1, passed: 1}],
    ['selected (pass|skip)', true, {tests: 2, passed: 1, skipped: 1}],
    ['does-not-exist', false, {}],
    ['selected skip', false, {tests: 1, skipped: 1}],
    ['selected failure', false, {tests: 1, failed: 1}],
    ['selected cancel', false, {tests: 1, cancelled: 1}],
  ]) {
    const args = nodeTestArguments(['--test-name-pattern', pattern, file]);
    const child = spawnSync(process.execPath, args, {encoding: 'utf8', env: childEnv, timeout: 10_000});
    const result = testExecutionResult('node', process.execPath, args, child);
    assert.equal(result.status === 0, success, result.diagnostic + '\n' + child.stdout);
    assert.deepEqual(result.counts, counts(expected), pattern);
  }
  writeFileSync(file, `import {describe} from 'node:test'; describe('empty suite', () => {});\n`);
  const args = nodeTestArguments([file]);
  assert.equal(testExecutionResult('node', process.execPath, args,
    spawnSync(process.execPath, args, {encoding: 'utf8', env: childEnv, timeout: 10_000})).status, 1);
});

test('local-checks integrates real selected and unmatched Node tests', t => {
  const root = fixture(t);
  const file = join(root, 'selected.mjs');
  writeFileSync(file, `import {test} from 'node:test'; test('selected', () => {});\n`);
  const script = fileURLToPath(new URL('./local-checks.mjs', import.meta.url));
  for (const [pattern, status] of [['selected', 0], ['missing-selection', 1]]) {
    const child = spawnSync(process.execPath, [script, 'test', 'node', '--',
      '--test-name-pattern', pattern, file], {encoding: 'utf8', env: {...childEnv, HOME: root}, timeout: 10_000});
    assert.equal(child.status, status, child.stdout + child.stderr);
    assert.match(child.stdout + child.stderr, /counts=/u);
  }
});

test('pinned MoonBit real pass, unmatched, skip-only and failure selections', t => {
  const root = fixture(t);
  mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'moon.mod'), 'name = "test/execution"\nsource = "src"\n');
  writeFileSync(join(root, 'src/moon.pkg'), '');
  writeFileSync(join(root, 'src/selected_test.mbt'),
    'test "selected pass" { assert_eq(1, 1) }\n' +
    '#skip\ntest "selected skip" { assert_eq(1, 1) }\n' +
    'test "selected failure" { assert_eq(1, 2) }\n');
  for (const [filter, success, total] of [
    ['selected pass', true, 1], ['does-not-exist', false, 0],
    ['selected skip', false, 0], ['selected failure', false, 1],
  ]) {
    const args = ['test', '--target', 'js', '--filter', filter];
    const child = spawnSync('moon', args, {cwd: root, encoding: 'utf8'});
    const result = testExecutionResult('moon', 'moon', args, child);
    assert.equal(result.status === 0, success, result.diagnostic + '\n' + child.stderr);
    assert.equal(result.counts?.tests, total, result.diagnostic);
  }
});

import {readFileSync, readdirSync} from 'node:fs';

function runRecorded(root, file, extra = {}) {
  const helper = new URL('./test-execution.mjs', import.meta.url).href;
  return spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {runFocusedTests} from ${JSON.stringify(helper)};
     process.exitCode = runFocusedTests('node', [${JSON.stringify(file)}],
       ${JSON.stringify({cwd: root, evidenceScratch: join(root, 'evidence'), ...extra})});`],
    {encoding: 'utf8', env: childEnv, timeout: 10_000});
}

test('focused assertion failure survives an explicitly requested successful rerun', t => {
  const root = fixture(t), file = join(root, 'selected.mjs');
  writeFileSync(file, "import {test} from 'node:test'; import assert from 'node:assert/strict'; test('selected', () => assert.equal(1, 2));");
  const failed = runRecorded(root, file);
  assert.equal(failed.status, 1, failed.stderr);
  const [original] = readdirSync(join(root, 'evidence'));
  const path = join(root, 'evidence', original, 'summary.json');
  const before = readFileSync(path, 'utf8');
  const observed = JSON.parse(before);
  assert.equal(observed.complete, false);
  assert.equal(observed.commands[0].verificationStatus, 1);
  assert.match(readFileSync(join(root, 'evidence', original, '001.stdout.log'), 'utf8'), /AssertionError/u);
  writeFileSync(file, "import {test} from 'node:test'; test('selected', () => {});");
  const passed = runRecorded(root, file);
  assert.equal(passed.status, 0, passed.stderr);
  assert.equal(readdirSync(join(root, 'evidence')).length, 2);
  assert.equal(readFileSync(path, 'utf8'), before, 'failed attempt bytes are immutable across reruns');
  const summaries = readdirSync(join(root, 'evidence')).map(name => JSON.parse(readFileSync(join(root, 'evidence', name, 'summary.json'))));
  assert.equal(summaries.filter(summary => summary.complete).length, 1);
});

test('unwritable focused evidence destination preserves failure and fails a green attempt', t => {
  const root = fixture(t), file = join(root, 'selected.mjs');
  const blocked = join(root, 'not-a-directory');
  writeFileSync(blocked, 'unrelated');
  for (const fail of [true, false]) {
    writeFileSync(file, `import {test} from 'node:test'; test('selected', () => {${fail ? "throw new Error('expected assertion failure')" : ''}});`);
    const child = runRecorded(root, file, {evidenceScratch: join(blocked, 'child')});
    assert.equal(child.status, 1);
    assert.match(child.stderr, /evidence write failed/u);
    assert.match(child.stderr, new RegExp('primary test status: ' + (fail ? 1 : 0)));
  }
  assert.equal(readFileSync(blocked, 'utf8'), 'unrelated');
});
