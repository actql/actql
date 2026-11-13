import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdir, mkdtemp, readFile, rm, access, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeDefaultNumericQueries, observeNativeDefaultNumericQueries, observeNativeFileSourceNumeric}
  from './test-native-cli-source-free-install.mjs';

// Explicit command ports exercise the acceptance oracle, not Native execution.
async function numericFixture(t, fault) {
  const project = await mkdtemp(join(tmpdir(), 'native-default-numeric-oracle-'));
  t.after(() => rm(project, {recursive: true, force: true}));
  const runs = new Map(), calls = [], saved = [], hosts = new Map();
  const cli = async (args, cwd) => {
    calls.push(args);
    const [operation, file] = args;
    if (operation === 'init') {
      assert.equal(cwd, project); assert(!hosts.has(file));
      await mkdir(file); hosts.set(file, 0); return {stdout: ''};
    }
    assert(hosts.has(cwd), 'All submissions must use the one initialized ordinary Host');
    if (operation === 'sql') {
      hosts.set(cwd, hosts.get(cwd)+1);
      return {stdout: '{"total":3}\n'};
    }
    if (file === 'numeric-invalid.sql' || file === 'numeric-invalid-syntax.sql') {
      assert.equal(operation, 'check');
      return {stdout: JSON.stringify({outcome: 'completed', report: {verdict: 'invalid', runnable: {verdict: 'no'}}})};
    }
    if (operation === 'check' || operation === 'run') {
      const entry = nativeDefaultNumericQueries.find(value => file === `numeric-${value.name}.sql`);
      assert(entry); assert.equal(cwd, join(project, 'numeric-cases', 'ordinary'));
      assert.equal(await readFile(join(cwd, file), 'utf8'), entry.sql);
      if (operation === 'check') return {stdout: JSON.stringify({outcome: 'completed', report: {
        verdict: fault === 'check' ? 'undetermined' : 'verified', runnable: {verdict: fault === 'check' ? 'no' : 'yes'},
      }})};
      assert(!runs.has(entry.name), 'The original Program must be submitted only once');
      hosts.set(cwd, hosts.get(cwd)+1);
      runs.set(entry.name, entry);
      return {stdout: JSON.stringify({version: 'actql-run-state/0.1', status: 'succeeded', run_id: entry.name})};
    }
    assert.equal(operation, 'result');
    const entry = runs.get(file); assert(entry);
    let cold = false;
    assert.equal(cwd, join(project, 'numeric-cases', 'ordinary'));
    try {await access(join(cwd, `numeric-${entry.name}.sql`));}
    catch (error) {assert.equal(error.code, 'ENOENT'); cold = true;}
    if (cold) {
      saved.push(entry.name);
      if (entry.parameters) for (const name of ['numeric-declarations.json', 'numeric-parameters.json'])
        await assert.rejects(access(join(cwd, name)), {code: 'ENOENT'});
    }
    const rows = fault === 'live' || (cold && fault === 'saved') ||
      (fault === 'old-saved' && hosts.get(cwd) === 11) ? [{total: 4}] : entry.rows;
    return {stdout: rows.map(value => JSON.stringify(value)).join('\n')+'\n'};
  };
  return {project, cli, calls, runs, saved, hosts};
}

test('default numeric oracle requires runnable checking and same Saved after original input removal', async t => {
  const fixture = await numericFixture(t);
  const observed = await observeNativeDefaultNumericQueries(fixture);
  assert.equal(observed.length, 10); assert.equal(fixture.runs.size, 10);
  assert.equal(fixture.hosts.size, 1); assert.equal([...fixture.hosts.values()][0], 11);
  const names = nativeDefaultNumericQueries.map(entry => entry.name);
  assert.deepEqual(fixture.saved, [...names, ...names]);
  assert(observed.every(entry => entry.savedAfterLaterSubmissions));
  assert.deepEqual(observed[0].rows, [{total: 3}]);
  assert.deepEqual(observed[1].rows, [{total: 1.5}]);
  assert.deepEqual(observed[2].rows, [{total: '4.00'}]);
});

test('default numeric oracle refuses a successful check command with undetermined report before execution', async t => {
  const fixture = await numericFixture(t, 'check');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), /verified check required/u);
  assert.equal(fixture.calls.length, 2); assert.equal(fixture.runs.size, 0);
});

test('default numeric oracle refuses incorrect live rows without submitting a replacement Run', async t => {
  const fixture = await numericFixture(t, 'live');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.runs.size, 1); assert.deepEqual(fixture.saved, []);
});

test('default numeric oracle refuses changed Saved rows without reprepare or reexecution', async t => {
  const fixture = await numericFixture(t, 'saved');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.runs.size, 1); assert.deepEqual(fixture.saved, ['sum']);
});

test('same-project numeric oracle refuses an old Saved changed by later submissions', async t => {
  const fixture = await numericFixture(t, 'old-saved');
  await assert.rejects(observeNativeDefaultNumericQueries(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.hosts.size, 1); assert.equal(fixture.runs.size, 10);
  assert.equal(fixture.calls.filter(args => args[0] === 'init').length, 1);
});

async function fileFixture(t, fault) {
  const root = await mkdtemp(join(tmpdir(), 'native-file-numeric-oracle-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const project = join(root, 'numeric-file-source');
  const program = join(project, 'numeric-source.sql'), source = join(project, 'mock/data.json');
  const original = '{"items":[{"trend":"down"},{"trend":"up"}]}\n';
  const calls = [];
  let reads = 0;
  const cli = async (args, cwd) => {
    calls.push(args);
    if (args[0] === 'init') {
      assert.deepEqual(args, ['init', '--template', 'churn-risk-mock', project]);
      assert.equal(cwd, root);
      await mkdir(join(project, 'mock'), {recursive: true});
      await writeFile(source, original, {flag: 'wx'});
      return {stdout: ''};
    }
    assert.equal(cwd, project);
    if (args[0] === 'check') return {stdout: JSON.stringify({outcome: 'completed',
      report: {verdict: 'verified', runnable: {verdict: 'yes'}}})};
    if (args[0] === 'run') {
      assert.equal(calls.filter(value => value[0] === 'run').length, 1);
      if (fault === 'source') await writeFile(source, 'changed');
      return {stdout: JSON.stringify({status: 'succeeded', run_id: 'original-file-run'})};
    }
    assert.deepEqual(args, ['result', 'original-file-run', '--format', 'jsonl']);
    if (++reads === 1) {await access(program); await access(source);}
    else for (const path of [program, source]) await assert.rejects(access(path), {code: 'ENOENT'});
    const wrong = (fault === 'live' && reads === 1) || (fault === 'saved' && reads === 2);
    return {stdout: JSON.stringify({total: wrong ? 12 : 16, average: 8}) + '\n'};
  };
  return {root, cli, calls, reads: () => reads};
}

test('File CASE oracle verifies complete 16/8 before input removal and same cold Saved', async t => {
  const fixture = await fileFixture(t);
  const observed = await observeNativeFileSourceNumeric(fixture);
  assert.equal(fixture.reads(), 2);
  assert.equal(observed.completeResultBeforeInputRemoval, true);
  assert.equal(observed.coldSavedWithoutProgramOrSource, true);
  assert.deepEqual(observed.rows, [{total: 16, average: 8}]);
});

for (const fault of ['live', 'saved', 'source']) test(`File CASE oracle refuses changed ${fault} without another Run`, async t => {
  const fixture = await fileFixture(t, fault);
  await assert.rejects(observeNativeFileSourceNumeric(fixture), {code: 'ERR_ASSERTION'});
  assert.equal(fixture.calls.filter(args => args[0] === 'run').length, 1);
  assert.equal(fixture.calls.filter(args => args[0] === 'init').length, 1);
});
