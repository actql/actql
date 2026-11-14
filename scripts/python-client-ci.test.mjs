import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {parse} from 'yaml';
import {pythonClientSteps, remotePythonClientTests, sourceLocalPythonClientTests} from './check-python-client.mjs';

test('reviewed source-only Python callers reach the original nonzero runner once each', () => {
  const candidates = readdirSync(new URL('../packages/python-sdk/tests/', import.meta.url))
    .filter(name => /^test_.*\.py$/u.test(name) && !/^test_(?:local|release)_/u.test(name)).sort();
  assert.deepEqual([...remotePythonClientTests].sort(), candidates,
    'New callers need an explicit dependency/profile review before joining this selection');
  const steps = pythonClientSteps('selected-python', {remoteOnly: true}).slice(1);
  assert.equal(steps.length, 16);
  assert.equal(new Set(steps.map(step => step.args.at(-1))).size, 16);
  for (const step of steps) {
    assert.equal(step.command, 'selected-python');
    assert.deepEqual(step.args.slice(0, -1), ['-B', 'packages/python-sdk/tests/run.py', '--pattern']);
  }
  const full = pythonClientSteps('selected-python');
  assert.deepEqual(full[1].args, ['packages/python-sdk/tests/run.py']);
  assert.deepEqual(full[2].args, ['-m', 'mypy', '--config-file',
    'packages/python-sdk/pyproject.toml', 'scripts/fixtures/python-client-types.py']);
});

test('reviewed Local-source callers keep their explicit Source facade and no physical runtime selection', () => {
  const steps = pythonClientSteps('selected-python', {sourceOnly: true}).slice(1);
  assert.equal(steps.length, 41);
  assert.equal(new Set(steps.map(step => step.args.at(-1))).size, 41);
  assert.equal(sourceLocalPythonClientTests.length, 25);
  assert.deepEqual(steps.slice(0, 16).map(step => step.args.at(-1)), [...remotePythonClientTests]);
  assert.deepEqual(steps.slice(16).map(step => step.args.at(-1)), [...sourceLocalPythonClientTests]);
  for (const [index, step] of steps.entries()) {
    assert.equal(step.command, 'selected-python');
    assert.deepEqual(step.args.slice(0, -1), ['-B', 'packages/python-sdk/tests/run.py', '--pattern']);
    if (index < 16) assert.equal(step.env, undefined);
    else assert.deepEqual(step.env, {PYTHONPATH: fileURLToPath(new URL('../packages/python-product/src', import.meta.url))});
    assert.ok(!['test_local_closed_publisher.py', 'test_local_closed_reconciliation_prepare.py',
      'test_local_closed_wasm_sql.py', 'test_local_journal_row_transport.py',
      'test_local_native_initial_custody.py'].includes(step.args.at(-1)));
  }
  assert.throws(() => pythonClientSteps('selected-python', {remoteOnly: true, sourceOnly: true}));
});

test('Linux lint owns source Python callers without a package producer or installed Local profile', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const lint = workflow.jobs.lint;
  assert.equal(lint['runs-on'], 'ubuntu-24.04');
  assert.deepEqual(lint.needs, ['select-targets', 'preflight']);
  const consumers = lint.steps.filter(step => step.run?.includes('scripts/check-python-client.mjs'));
  assert.equal(consumers.length, 1);
  assert.equal(consumers[0].run, 'node scripts/check-python-client.mjs --source-only');
  assert.match(consumers[0].if, /!startsWith\(needs\.select-targets\.outputs\.profile, 'draft'\)/u);
  const preparation = lint.steps.find(step => step.name === 'Install the pinned Python row-schema dependency');
  assert.ok(preparation);
  const pyproject = readFileSync(new URL('../packages/python-sdk/pyproject.toml', import.meta.url), 'utf8');
  const pin = pyproject.match(/"(pydantic==[^"\s]+)"/u)?.[1];
  assert.ok(pin);
  assert.equal(preparation.run, `python3 -m pip install --disable-pip-version-check ${pin}`);
  assert.ok(lint.steps.some(step => step.run?.includes('pip install --disable-pip-version-check -e ./packages/python-sdk')),
    'The preceding cross-host packaging control prepares the same lightweight SDK');
});
