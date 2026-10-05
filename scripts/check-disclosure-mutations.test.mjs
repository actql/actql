import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';
import {nodeTestArguments} from './test-execution.mjs';

const expected = [{name: 'selected', assertions: [{id: 'expected', operator: 'strictEqual'}]}];
test('an unmatched disclosure mutation selection refuses before changing source', () => {
  const path = 'src/connectors_builtin_node/client_check.mbt';
  const before = readFileSync(path, 'utf8');
  const result = spawnSync(process.execPath,
    ['scripts/check-disclosure-mutations.mjs', '--match', 'nonexistent-mutation-fixture'],
    {encoding: 'utf8', timeout: 10000});
  assert.equal(result.status, 1);
  assert.match(result.stderr, /No disclosure mutations selected/u);
  assert.equal(readFileSync(path, 'utf8'), before);
});
function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-mutation-evidence-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const file = join(directory, 'selected.test.mjs');
  const run = (body, options = {}) => {
    writeFileSync(file, `import test from 'node:test';
      import assert from 'node:assert/strict';\n${body}\n`);
    const env = {...process.env};
    delete env.NODE_TEST_CONTEXT;
    if (options.directTimeout) {
      return spawnSync(process.execPath, ['-e', 'setInterval(() => {}, 1000)'],
        {encoding: 'utf8', env, timeout: 200, killSignal: 'SIGKILL'});
    }
    return spawnSync(process.execPath, nodeTestArguments([
      '--test-name-pattern', options.pattern ?? '^selected$', file]),
    {encoding: 'utf8', env, timeout: options.timeout ?? 10000,
      killSignal: 'SIGKILL'});
  };
  return {file, run};
}

test('mutation evidence requires the named expected assertion, or a genuine pass', t => {
  const {file, run} = fixture(t);
  assert.equal(mutationAcceptance(run("test('selected', () => {});"), expected, file), true);
  assert.throws(() => mutationAcceptance(run("test('selected', () => {});"), [], file),
    /infrastructure failure/u);
  const rejected = run("test('selected', () => assert.equal(1, 2, '[check-mutation:expected]')); ");
  assert.equal(rejected.status, 1);
  assert.equal(mutationAcceptance(rejected, expected, file), false);
  assert.throws(() => mutationAcceptance({...rejected, signal: 'SIGTERM'}, expected, file),
    /infrastructure failure/u);
  for (const stderr of ['Local check stopped: command left running descendants',
    'Focused test evidence write failed; evidence is incomplete']) {
    assert.throws(() => mutationAcceptance({...rejected, stderr}, expected, file), /infrastructure failure/u);
  }
  assert.throws(() => mutationAcceptance({...rejected, stdout: rejected.stdout
    .split('\n').filter(line => !line.startsWith('ACTQL_TEST_CASE ')).join('\n')}, expected, file),
  /infrastructure failure/u);
});

for (const [name, body, options] of [
  ['import failure with TAP fail 1', "import './missing-module.mjs';", {}],
  ['unexpected test exception', "test('selected', () => { throw new Error('unexpected'); });", {}],
  ['uncaught exception', "test('selected', async () => { setImmediate(() => { throw new Error('uncaught'); }); await new Promise(resolve => setTimeout(resolve, 50)); });", {}],
  ['unexpected assertion', "test('selected', () => assert.equal(1, 2, 'unrelated'));", {}],
  ['unexpected assertion operator', "test('selected', () => assert.ok(false, '[check-mutation:expected]'));", {}],
  ['different equality operator with the expected identifier', "test('selected', () => assert.deepEqual({n: 1}, {n: 2}, '[check-mutation:expected]'));", {}],
  ['timeout', '', {directTimeout: true}],
  ['test cancellation', "test('selected', {timeout: 20}, () => new Promise(() => {}));", {}],
  ['unselected test', "test('other', () => assert.equal(1, 2, '[check-mutation:expected]'));", {}],
  ['skipped test', "test.skip('selected', () => {});", {}],
  ['todo test', "test.todo('selected');", {}],
  ['duplicate names', "test('selected', () => {}); test('selected', () => {});", {}],
  ['post-test exception after expected assertion', "test('selected', () => assert.equal(1, 2, '[check-mutation:expected]')); setTimeout(() => { throw new Error('after test'); }, 20);", {}],
  ['post-test unhandled rejection after expected assertion', "test('selected', () => assert.equal(1, 2, '[check-mutation:expected]')); setTimeout(() => { Promise.reject(new Error('after test')); }, 20);", {}],
]) {
  test(`mutation infrastructure fails separately: ${name}`, t => {
    const {file, run} = fixture(t);
    const result = run(body, options);
    if (name.startsWith('import')) assert.match(result.stdout, /# fail 1/u);
    assert.throws(() => mutationAcceptance(result, expected, file), /infrastructure failure/u);
  });
}

test('an assertion in another named test or file is not the mutation target', t => {
  const {file, run} = fixture(t);
  const result = run("test('selected', () => assert.equal(1, 2, '[check-mutation:expected]')); ");
  assert.throws(() => mutationAcceptance(result, [{...expected[0], name: 'other'}], file),
    /infrastructure failure/u);
  assert.throws(() => mutationAcceptance(result, expected, file + '.other'), /infrastructure failure/u);
});
