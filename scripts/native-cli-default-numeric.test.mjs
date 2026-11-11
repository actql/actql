import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdir, mkdtemp, readFile, rm, access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeDefaultNumericQueries, observeNativeDefaultNumericQueries}
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
    assert(hosts.has(cwd), 'Each independent case needs its own ordinary Host');
    if (operation === 'sql') {
      hosts.set(cwd, hosts.get(cwd)+1); assert(hosts.get(cwd)<=8);
      return {stdout: '{"total":3}\n'};
    }
    if (file === 'numeric-invalid.sql') {
      assert.equal(operation, 'check');
      return {stdout: JSON.stringify({outcome: 'completed', report: {verdict: 'invalid', runnable: {verdict: 'no'}}})};
    }
    if (operation === 'check' || operation === 'run') {
      const entry = nativeDefaultNumericQueries.find(value => file === `numeric-${value.name}.sql`);
      assert(entry); assert.equal(cwd, join(project, 'numeric-cases', entry.name));
      assert.equal(await readFile(join(cwd, file), 'utf8'), entry.sql);
      if (operation === 'check') return {stdout: JSON.stringify({outcome: 'completed', report: {
        verdict: fault === 'check' ? 'undetermined' : 'verified', runnable: {verdict: fault === 'check' ? 'no' : 'yes'},
      }})};
      assert(!runs.has(entry.name), 'The original Program must be submitted only once');
      hosts.set(cwd, hosts.get(cwd)+1); assert(hosts.get(cwd)<=8);
      runs.set(entry.name, entry);
      return {stdout: JSON.stringify({version: 'actql-run-state/0.1', status: 'succeeded', run_id: entry.name})};
    }
    assert.equal(operation, 'result');
    const entry = runs.get(file); assert(entry);
    let cold = false;
    assert.equal(cwd, join(project, 'numeric-cases', entry.name));
    try {await access(join(cwd, `numeric-${entry.name}.sql`));}
    catch (error) {assert.equal(error.code, 'ENOENT'); cold = true;}
    if (cold) {
      saved.push(entry.name);
      if (entry.parameters) for (const name of ['numeric-declarations.json', 'numeric-parameters.json'])
        await assert.rejects(access(join(cwd, name)), {code: 'ENOENT'});
    }
    const rows = fault === 'live' || (cold && fault === 'saved') ? [{total: 4}] : entry.rows;
    return {stdout: rows.map(value => JSON.stringify(value)).join('\n')+'\n'};
  };
  return {project, cli, calls, runs, saved, hosts};
}

test('default numeric oracle requires runnable checking and same Saved after original input removal', async t => {
  const fixture = await numericFixture(t);
  const observed = await observeNativeDefaultNumericQueries(fixture);
  assert.equal(observed.length, 10); assert.equal(fixture.runs.size, 10);
  assert.equal(fixture.hosts.size, 10); assert([...fixture.hosts.values()].every(value=>value<=2));
  assert.deepEqual(fixture.saved, nativeDefaultNumericQueries.map(entry => entry.name));
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
