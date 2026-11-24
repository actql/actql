import assert from 'node:assert/strict';
import {test} from 'node:test';
import type {TestContext} from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nodeTestArguments, cargoTestArguments, parseTestExecution, testExecutionResult}
  from './test-execution.mjs';

const childEnv = {...process.env};
delete childEnv.NODE_TEST_CONTEXT;

test('direct library invocation cannot succeed without executing tests', t => {
  const library = fileURLToPath(new URL('./test-execution.mjs', import.meta.url));
  const linked = join(fixture(t), 'scripts');
  symlinkSync(fileURLToPath(new URL('.', import.meta.url)), linked);
  for (const args of [[library], [library, 'moon', '--', '--target', 'js'],
    ['--preserve-symlinks-main', join(linked, 'test-execution.mjs'), 'moon']]) {
    const result = spawnSync(process.execPath, args,
      {env: childEnv, encoding: 'utf8', timeout: 10000});
    assert.equal(result.status, 1);
    assert.equal(result.signal, null);
    assert.match(result.stderr, /import-only library/u);
    assert.equal(result.stdout, '');
  }
  const imported = spawnSync(process.execPath, ['--input-type=module', '-e',
    "import {pathToFileURL} from 'node:url'; const library = await import(pathToFileURL(process.argv[1])); process.stdout.write(typeof library.runFocusedTests);", library],
  {env: childEnv, encoding: 'utf8', timeout: 10000});
  assert.equal(imported.status, 0, imported.stderr);
  assert.equal(imported.stdout, 'function');
});

type Counts = ReturnType<typeof parseTestExecution>['counts'];
const counts = (values: Partial<Counts> = {}) => ({tests: 0, passed: 0, failed: 0,
  cancelled: 0, skipped: 0, todo: 0, ...values});
const summary = (values: Partial<Counts>, file?: string) => 'ACTQL_TEST_SUMMARY ' + JSON.stringify({
  success: true, counts: counts(values), ...(file ? {file} : {}),
}) + '\n';
const output = (values: Partial<Counts>) => summary(values, 'selected.test.mjs') + summary(values);
const checked = (kind: string, stdout: string, extra: Partial<Parameters<typeof testExecutionResult>[3]> = {}) => testExecutionResult(kind,
  kind, ['--filter', 'selected'], {status: 0, stdout, ...extra});

const cargoOutput = 'running 2 tests\n' +
  'test abi::tests::original_module ... ok\n' +
  'test abi::tests::same_host_owner ... ok\n' +
  'test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s\n';

test('Cargo gate forwards one locked unfiltered library selection without changing argument order', () => {
  const args = ['--locked', '--manifest-path', 'packages/rust/Cargo.toml', '--lib', '--', '--nocapture'];
  for (const manifest of ['packages/rust/Cargo.toml', 'packages/rust/tools/source-inventory/Cargo.toml']) {
    const original = args.map(value => value === 'packages/rust/Cargo.toml' ? manifest : value);
    assert.deepEqual(cargoTestArguments(original), ['test', ...original]);
    const reordered = ['--lib', '--manifest-path', manifest, '--locked', '--', '--nocapture'];
    assert.deepEqual(cargoTestArguments(reordered), ['test', ...reordered]);
  }
  for (const bad of [[], ['--locked', '--lib', '--', '--nocapture'],
    [...args.slice(0, -2), 'only_one_case', '--', '--nocapture'],
    args.map(value => value === 'packages/rust/Cargo.toml' ? '../other/Cargo.toml' : value),
    ['--doc', ...args], ['--no-run', ...args], ['--locked', ...args],
    [...args.slice(0, -1), '--ignored'], [...args.slice(0, -1), '--list']]) {
    assert.throws(() => cargoTestArguments(bad), undefined!, JSON.stringify(bad));
  }
});

test('Cargo gate requires actual unique named cases matching the library totals', () => {
  const actual = checked('cargo', cargoOutput);
  assert.equal(actual.status, 0);
  assert.deepEqual(actual.counts, counts({tests: 2, passed: 2, cancelled: null, skipped: 0, todo: null}));
  for (const bad of [cargoOutput.replace('test abi::tests::same_host_owner ... ok\n', ''),
    cargoOutput.replace('same_host_owner', 'original_module'),
    cargoOutput + cargoOutput, cargoOutput.replace('2 passed', '3 passed'),
    cargoOutput.replace('running 2 tests', 'running 1 test')]) {
    assert.equal(checked('cargo', bad).status, 1);
  }
});

test('Cargo gate refuses compilation-only, zero tests, ignored tests and filtered subsets', () => {
  const empty = 'running 0 tests\ntest result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s\n';
  for (const bad of ['', 'Finished test profile\n', '{"reason":"build-finished","success":true}\n',
    empty, cargoOutput.replace('0 filtered out', '1 filtered out'),
    cargoOutput.replace('2 passed; 0 failed; 0 ignored', '1 passed; 0 failed; 1 ignored')
      .replace('same_host_owner ... ok', 'same_host_owner ... ignored')]) {
    assert.equal(checked('cargo', bad).status, 1);
  }
});

test('Cargo process failure and signals remain primary even with green execution text', () => {
  for (const extra of [{status: 101}, {status: 0, signal: 'SIGTERM'},
    {status: 0, error: {code: 'ETIMEDOUT'}}]) assert.notEqual(checked('cargo', cargoOutput, extra as Partial<Parameters<typeof testExecutionResult>[3]>).status, 0);
  const failed = cargoOutput.replace('same_host_owner ... ok', 'same_host_owner ... FAILED')
    .replace('result: ok. 2 passed; 0 failed', 'result: FAILED. 1 passed; 1 failed');
  assert.equal(checked('cargo', failed).status, 1);
});

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
] as const) {
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
  ] as const) {
    const result = checked('moon', text);
    assert.equal(result.status, status);
    assert.equal(result.counts!.tests, total);
    assert.equal(result.counts!.skipped, null, 'the tool does not report skipped counts');
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

function fixture(t: TestContext) {
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
  ] as const) {
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
  for (const [pattern, status] of [['selected', 0], ['missing-selection', 1]] as const) {
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
  ] as const) {
    const args = ['test', '--target', 'js', '--filter', filter];
    const child = spawnSync('moon', args, {cwd: root, encoding: 'utf8'});
    const result = testExecutionResult('moon', 'moon', args, child);
    assert.equal(result.status === 0, success, result.diagnostic + '\n' + child.stderr);
    assert.equal(result.counts?.tests, total, result.diagnostic);
  }
});

import {readFileSync, readdirSync} from 'node:fs';

function runRecorded(root: string, file: string, extra: Record<string, unknown> = {}) {
  const helper = new URL('./test-execution.mjs', import.meta.url).href;
  return spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {runFocusedTests} from ${JSON.stringify(helper)};
     process.exitCode = runFocusedTests('node', [${JSON.stringify(file)}],
       ${JSON.stringify({cwd: root, evidenceScratch: join(root, 'evidence'), ...extra})});`],
    {encoding: 'utf8', env: childEnv, timeout: 10_000});
}

test('required execution count rejects a passing subset and is recorded as failure', t => {
  const root = fixture(t), file = join(root, 'selected.mjs');
  writeFileSync(file, "import {test} from 'node:test'; test('one actual case', () => {});\n");
  const passed = runRecorded(root, file, {expectedTests: 1});
  assert.equal(passed.status, 0, passed.stderr);
  const subset = runRecorded(root, file, {expectedTests: 2});
  assert.equal(subset.status, 1, subset.stderr);
  assert.match(subset.stderr, /expected tests=2/u);
  const summaries = readdirSync(join(root, 'evidence')).map(name =>
    JSON.parse(readFileSync(join(root, 'evidence', name, 'summary.json')) as unknown as string) as {complete: boolean; commands: {verificationStatus: number}[]});
  assert.equal(summaries.filter(value => value.complete).length, 1);
  assert.equal(summaries.filter(value => value.commands[0].verificationStatus === 1).length, 1);
  for (const expectedTests of [0, -1, 1.5, '1']) {
    const invalid = runRecorded(root, file, {expectedTests});
    assert.equal(invalid.status, 1);
    assert.match(invalid.stderr, /Expected test count must be a positive safe integer/u);
  }
});

test('whole-file execution requires every discovered case without a historical count', t => {
  const root = fixture(t), file = join(root, 'selected.mjs');
  const check = (body: string, status: number) => {
    writeFileSync(file, "import {test} from 'node:test';\n" + body);
    const result = runRecorded(root, file, {requireAllPassed: true});
    assert.equal(result.status, status, result.stderr);
  };
  check("test('first', () => {}); test('second', () => {});", 0);
  check("test('first', () => {}); test('second', () => {}); test('new case', () => {});", 0);
  check('', 1);
  check("test('pass', () => {}); test.skip('missing regression', () => {});", 1);
  check("test('pass', () => {}); test.todo('unfinished regression');", 1);
  check("test('failed regression', () => { throw new Error('original failure'); });", 1);
});

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
  const summaries = readdirSync(join(root, 'evidence')).map(name => JSON.parse(readFileSync(join(root, 'evidence', name, 'summary.json')) as unknown as string) as {complete: boolean; commands: {verificationStatus: number}[]});
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
