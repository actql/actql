import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {startNativeGroups, validateGroups, waitNativeGroups} from './ci-native-background-groups.mjs';

const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-ci-native-groups-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const step = (name, body, extra = {}) => {
    const path = join(root, name + '.cjs');
    writeFileSync(path, body);
    return {name, run: quote(process.execPath) + ' ' + quote(path), ...extra};
  };
  const start = (groups, options = {}) => startNativeGroups({root,
    directory: join(root, 'control'), groups, slots: 2, deadline: Date.now() + 10_000, ...options});
  return {root, step, start};
}

test('two background slots retain original per-group order, complete census and independent output files', async t => {
  const f = fixture(t), messages = [];
  const groups = ['runtime', 'controls', 'product'].map(name => ({name, steps: [
    f.step(name + '-first', "setTimeout(() => console.log('original'), 200);"),
    f.step(name + '-second', "require('fs').appendFileSync(process.env.GITHUB_OUTPUT, 'evidence-directory=' + process.cwd() + '\\n');",
      {id: name + '-evidence', env: {ORIGINAL: 'retained'}}),
  ]}));
  const directory = f.start(groups);
  const result = await waitNativeGroups(directory, {report: value => messages.push(value)});
  assert.equal(result.status, 0);
  assert.deepEqual(result.result.groups.map(group => group.cases.map(item => item.name)),
    groups.map(group => group.steps.map(item => item.name)));
  assert.equal(result.result.groups.flatMap(group => group.cases).length, 6);
  const [first, second, third] = result.result.groups.map(group => group.cases);
  assert(first[0].startedAt < second[0].completedAt && second[0].startedAt < first[0].completedAt);
  assert(third[0].startedAt >= Math.min(first[1].completedAt, second[1].completedAt));
  for (const group of result.result.groups) assert(group.cases[1].startedAt >= group.cases[0].completedAt);
  assert.deepEqual(Object.values(result.outputs), [f.root, f.root, f.root]);
  assert.equal(messages.filter(value => value.startsWith('ACTQL_NATIVE_CI_PHASE ')).length, 6);
});

test('an original failed command never cancels its later case or another group and cannot pass the join', async t => {
  const f = fixture(t);
  const directory = f.start([{name: 'runtime', steps: [f.step('failure', 'process.exitCode=7;'),
    f.step('later', "console.log('later original');")]},
  {name: 'controls', steps: [f.step('independent', "console.log('independent original');")]}]);
  const result = await waitNativeGroups(directory, {report() {}});
  assert.equal(result.status, 1);
  assert.deepEqual(result.result.groups.map(group => group.cases.map(item => item.status)),
    [['failure', 'success'], ['success']]);
  assert.equal(result.result.groups[0].cases[0].code, 7);
});

test('the original deadline marks later commands unexecuted instead of accepting a partial group', async t => {
  const f = fixture(t);
  const directory = f.start([{name: 'runtime', steps: [
    f.step('blocked', 'setTimeout(() => {}, 60000);'), f.step('unexecuted', 'throw new Error("must not execute");'),
  ]}], {deadline: Date.now() + 500});
  const result = await waitNativeGroups(directory, {report() {}});
  assert.equal(result.status, 1);
  assert.equal(result.result.groups[0].cases[0].status, 'failure');
  assert.equal(result.result.groups[0].cases[1].status, 'unexecuted');
});

test('duplicate selection, missing results and foreign result identity remain refusal', async t => {
  const f = fixture(t), step = f.step('original', '');
  assert.throws(() => validateGroups([{name: 'runtime', steps: [step, step]}]), /Duplicate/u);
  const directory = f.start([{name: 'runtime', steps: [step]}]);
  await waitNativeGroups(directory, {report() {}});
  const path = join(directory, 'result.json'), result = JSON.parse(readFileSync(path));
  for (const change of [value => { value.groups = []; }, value => { value.token = 'foreign'; },
    value => { value.groups[0].cases = []; }]) {
    const changed = structuredClone(result); change(changed); writeFileSync(path, JSON.stringify(changed));
    await assert.rejects(waitNativeGroups(directory, {report() {}}));
  }
});
