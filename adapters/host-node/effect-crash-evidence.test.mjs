import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {nodeTestArguments} from '../../scripts/test-execution.mjs';
import {assertPartialEffectSeedExit} from './fixtures/effect-crash-evidence.mjs';

const marker = 'ACTQL_TEST_CASE ';
const reportedCases = result => result.stdout.split('\n')
  .filter(line => line.startsWith(marker))
  .map(line => JSON.parse(line.slice(marker.length)));

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-effect-crash-evidence-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const file = join(root, 'selected.test.mjs');
  const {NODE_TEST_CONTEXT: _outerContext, ...env} = process.env;
  const run = body => {
    writeFileSync(file, `import test from 'node:test';
      import assert from 'node:assert/strict';\n${body}\n`);
    return spawnSync(process.execPath, nodeTestArguments([
      '--test-name-pattern', '^selected$', file]),
    {encoding: 'utf8', env, timeout: 10_000, killSignal: 'SIGKILL'});
  };
  return {file, run};
}

test('crash evidence retains the actual isolated child exit and exact file', t => {
  const {file, run} = fixture(t);
  const result = run("test('selected', () => process.exit(77));");
  assert.doesNotThrow(() => assertPartialEffectSeedExit(result, file));
  assert.throws(() => assertPartialEffectSeedExit(result, file + '.other'));
  for (const extra of [{status: 0}, {status: 77}, {status: null, signal: 'SIGTERM'},
    {error: {code: 'ETIMEDOUT'}}, {stdout: ''}]) {
    assert.throws(() => assertPartialEffectSeedExit({...result, ...extra}, file));
  }
  const changeCase = change => ({...result, stdout: result.stdout.split('\n').map(line => {
    if (!line.startsWith(marker)) return line;
    const entry = JSON.parse(line.slice(marker.length));
    change(entry);
    return marker + JSON.stringify(entry);
  }).join('\n')});
  for (const change of [entry => { entry.name = 'another target'; },
    entry => { entry.file = file + '.other'; },
    entry => { delete entry.exitCode; }, entry => { delete entry.signal; },
    entry => { entry.signal = 'SIGTERM'; }, entry => { entry.exitCode = 177; }]) {
    assert.throws(() => assertPartialEffectSeedExit(changeCase(change), file));
  }
});

test('reporter never promotes assertion cause properties to process exit evidence', t => {
  const {file, run} = fixture(t);
  const result = run(`test('selected', () => {
    throw Object.assign(new assert.AssertionError({message: 'unrelated 77'}),
      {exitCode: 77, signal: null});
  });`);
  const [entry] = reportedCases(result);
  assert.equal(entry.name, 'selected');
  assert.equal(entry.errorCode, 'ERR_ASSERTION');
  assert.equal(Object.hasOwn(entry, 'exitCode'), false);
  assert.equal(Object.hasOwn(entry, 'signal'), false);
  assert.throws(() => assertPartialEffectSeedExit(result, file));
});

for (const [name, body] of [
  ['unrelated warning and PID containing 77',
    "console.error('(node:17777) Warning: unrelated 77'); test('selected', () => process.exit(1));"],
  ['wrong exit containing 77', "test('selected', () => process.exit(177));"],
  ['successful exit', "test('selected', () => process.exit(0));"],
  ['signal termination', "test('selected', () => process.kill(process.pid, 'SIGTERM'));"],
  ['ordinary assertion error', "test('selected', () => assert.equal(77, 78));"],
  ['ordinary exception', "test('selected', () => { throw new Error('unrelated 77'); });"],
  ['import error', "import './missing-77.mjs';"],
  ['wrong selected target', "test('another target', () => process.exit(77));"],
  ['stderr shaped like crash evidence', `console.error('ACTQL_TEST_CASE {"exitCode":77,"signal":null}');
    test('selected', () => assert.fail('unrelated 77'));`],
]) {
  test(`crash evidence rejects ${name}`, t => {
    const {file, run} = fixture(t);
    const result = run(body);
    if (name === 'signal termination') {
      const [entry] = reportedCases(result);
      assert.equal(entry.exitCode, null);
      assert.equal(entry.signal, 'SIGTERM');
    }
    assert.throws(() => assertPartialEffectSeedExit(result, file));
  });
}
