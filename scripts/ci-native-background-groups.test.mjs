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
    f.step(name + '-second', "require('fs').appendFileSync(process.env.GITHUB_OUTPUT, 'evidence-directory=' + process.cwd() + '\\n');require('fs').appendFileSync(process.env.GITHUB_STEP_SUMMARY, " + JSON.stringify(name + ' original summary\n') + ");",
      {id: name + '-evidence', env: {ORIGINAL: 'retained'}}),
  ]}));
  const directory = f.start(groups);
  const summaryFile = join(f.root, 'joined-summary.md');
  const result = await waitNativeGroups(directory, {report: value => messages.push(value), summaryFile});
  assert.equal(result.status, 0);
  assert.deepEqual(result.result.groups.map(group => group.cases.map(item => item.name)),
    groups.map(group => group.steps.map(item => item.name)));
  assert.equal(result.result.groups.flatMap(group => group.cases).length, 6);
  const [first, second, third] = result.result.groups.map(group => group.cases);
  assert(first[0].startedAt < second[0].completedAt && second[0].startedAt < first[0].completedAt);
  assert(third[0].startedAt >= Math.min(first[1].completedAt, second[1].completedAt));
  for (const group of result.result.groups) assert(group.cases[1].startedAt >= group.cases[0].completedAt);
  assert.deepEqual(Object.values(result.outputs), [f.root, f.root, f.root]);
  assert.equal(readFileSync(summaryFile, 'utf8'), ['runtime', 'controls', 'product']
    .map(name => name + ' original summary\n').join(''));
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

test('joined Native HTTP outcome comes from its original complete child rather than a selected label', async t => {
  for (const code of [0, 7]) {
    const f = fixture(t);
    const directory = f.start([{name: 'runtime', steps: [
      f.step('http', `process.exitCode=${code};`, {id: 'native-http'}),
    ]}]);
    const result = await waitNativeGroups(directory, {report() {}});
    assert.equal(result.status, code === 0 ? 0 : 1);
    assert.equal(result.outputs['native-http-result'], code === 0 ? 'success' : 'failure');
    assert.equal(result.result.groups[0].cases[0].code, code);
  }
});

test('the original deadline marks later commands unexecuted instead of accepting a partial group', async t => {
  const f = fixture(t);
  const directory = f.start([{name: 'runtime', steps: [
    f.step('blocked', 'setTimeout(() => {}, 60000);'), f.step('unexecuted', 'throw new Error("must not execute");', {id: 'native-http'}),
  ]}], {deadline: Date.now() + 500});
  const result = await waitNativeGroups(directory, {report() {}});
  assert.equal(result.status, 1);
  assert.equal(result.result.groups[0].cases[0].status, 'failure');
  assert.equal(result.result.groups[0].cases[1].status, 'unexecuted');
  assert.equal(result.outputs['native-http-result'], 'unexecuted');
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

test('a successful join requires the original case identity and actual zero exit, not a success label alone', async t => {
  const f = fixture(t);
  const directory = f.start([{name: 'runtime', steps: [f.step('original', '', {id: 'original-case'})]}]);
  await waitNativeGroups(directory, {report() {}});
  const path = join(directory, 'result.json'), result = JSON.parse(readFileSync(path));
  for (const change of [value => { value.code = 7; }, value => { value.signal = 'SIGTERM'; },
    value => { value.failure = 'original'; }, value => { value.id = 'foreign'; },
    value => { value.group = 'foreign'; }, value => { value.status = 'skipped'; },
    value => { delete value.completedAt; }]) {
    const changed = structuredClone(result); change(changed.groups[0].cases[0]);
    writeFileSync(path, JSON.stringify(changed));
    await assert.rejects(waitNativeGroups(directory, {report() {}}));
  }
});

test('timeout waits for the known TERM-ignoring descendant after its leader exits and cannot accept exit zero', async t => {
  const f = fixture(t), pidFile = join(f.root, 'original-descendant.pid');
  let descendant;
  t.after(() => {
    if (descendant) try { process.kill(descendant, 'SIGKILL'); } catch (error) {
      if (error.code !== 'ESRCH') throw error;
    }
  });
  const body = 'process.on("SIGTERM",()=>process.exit(0));' +
    'require("child_process").spawn(process.execPath,["-e",' + JSON.stringify(
      'process.on("SIGTERM",()=>{});require("fs").writeFileSync(' + JSON.stringify(pidFile) + ',String(process.pid));setInterval(()=>{},1000);') +
    '],{stdio:"ignore"});setInterval(()=>{},1000);';
  const directory = f.start([{name: 'runtime', steps: [f.step('owned-leader', body)]}],
    {deadline: Date.now() + 1500});
  const result = await waitNativeGroups(directory, {report() {}});
  descendant = Number(readFileSync(pidFile, 'utf8'));
  assert(Number.isSafeInteger(descendant) && descendant > 0);
  let alive;
  try { process.kill(descendant, 0); alive = true; } catch (error) {
    if (error.code !== 'ESRCH') throw error;
    alive = false;
  }
  assert.equal(alive, false, 'Joining the closed leader must not abandon its known live descendant');
  assert.equal(result.status, 1, 'A timed out leader exiting zero is still a failed original command');
  const item = result.result.groups[0].cases[0];
  assert.equal(item.timedOut, true);
  assert.equal(item.forceStopRequested, true);
  assert.equal(item.groupStop, 'observed-gone');
});

test('a failed original leader also closes its known group without changing the original exit code', async t => {
  const f = fixture(t), pidFile = join(f.root, 'failed-descendant.pid');
  let descendant;
  t.after(() => { if (descendant) try { process.kill(descendant, 'SIGKILL'); } catch (error) {
    if (error.code !== 'ESRCH') throw error;
  }});
  const body = 'require("child_process").spawn(process.execPath,["-e",' + JSON.stringify(
    'process.on("SIGTERM",()=>{});require("fs").writeFileSync(' + JSON.stringify(pidFile) + ',String(process.pid));setInterval(()=>{},1000);') +
    '],{stdio:"ignore"});setInterval(()=>{if(require("fs").existsSync(' + JSON.stringify(pidFile) + '))process.exit(7)},5);';
  const directory = f.start([{name: 'runtime', steps: [f.step('failed-owned-leader', body)]}]);
  const result = await waitNativeGroups(directory, {report() {}});
  descendant = Number(readFileSync(pidFile, 'utf8'));
  assert(Number.isSafeInteger(descendant) && descendant > 0);
  assert.throws(() => process.kill(descendant, 0), {code: 'ESRCH'});
  assert.equal(result.status, 1);
  const item = result.result.groups[0].cases[0];
  assert.equal(item.code, 7); assert.equal(item.timedOut, false);
  assert.equal(item.forceStopRequested, true); assert.equal(item.groupStop, 'observed-gone');
});
