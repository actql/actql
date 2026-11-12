// Closed CI command groups beside the original inline Resident diagnostic steps.
// This does not create or adopt a product Run, preparation or cleanup owner.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {appendFileSync, closeSync, createReadStream, existsSync, mkdirSync, openSync, readFileSync,
  realpathSync, renameSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const entry = fileURLToPath(import.meta.url);
const write = (path, value) => {
  const temporary = path + '.pending';
  writeFileSync(temporary, JSON.stringify(value) + '\n', {mode: 0o600});
  renameSync(temporary, path);
};
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

export function validateGroups(groups) {
  assert(Array.isArray(groups) && groups.length > 0 && groups.length <= 4, 'Finite Native groups required');
  const names = new Set(), cases = new Set(), ids = new Set();
  for (const group of groups) {
    assert(/^[a-z][a-z-]+$/u.test(group.name) && !names.has(group.name), 'Duplicate/invalid Native group');
    names.add(group.name);
    assert(Array.isArray(group.steps) && group.steps.length > 0);
    for (const step of group.steps) {
      assert(typeof step.name === 'string' && step.name && !cases.has(step.name), 'Duplicate/invalid Native case');
      cases.add(step.name);
      assert(typeof step.run === 'string' && step.run.length > 0);
      assert(step.timeoutMinutes === undefined || Number.isSafeInteger(step.timeoutMinutes) && step.timeoutMinutes > 0);
      assert(step.id === undefined || /^[a-z][a-z-]+$/u.test(step.id));
      if (step.id !== undefined) { assert(!ids.has(step.id), 'Duplicate Native case id'); ids.add(step.id); }
      assert(Object.values(step.env ?? {}).every(value => typeof value === 'string'));
    }
  }
  return groups;
}

export function startNativeGroups({root, directory, groups, deadline, slots = 2}) {
  validateGroups(groups);
  assert(Number.isSafeInteger(slots) && slots >= 1 && slots <= 2, 'At most two background Native groups');
  assert(Number.isSafeInteger(deadline) && deadline > Date.now(), 'Original Native deadline required');
  mkdirSync(directory, {mode: 0o700});
  directory = realpathSync(directory); root = realpathSync(root);
  const control = {root, groups, deadline, slots, token: randomUUID()};
  writeFileSync(join(directory, 'control.json'), JSON.stringify(control) + '\n', {mode: 0o600, flag: 'wx'});
  const log = openSync(join(directory, 'controller.log'), 'wx', 0o600);
  let child;
  try { child = spawn(process.execPath, [entry, 'worker', directory], {
    cwd: root, env: process.env, detached: true, stdio: ['ignore', log, log],
  }); } finally { closeSync(log); }
  assert(Number.isSafeInteger(child.pid) && child.pid > 0, 'Native group controller did not start');
  writeFileSync(join(directory, 'worker.json'), JSON.stringify({pid: child.pid, token: control.token}),
    {mode: 0o600, flag: 'wx'});
  child.unref();
  return directory;
}

async function executeCase(control, directory, group, step, index) {
  const startedAt = Date.now(), remaining = control.deadline - startedAt;
  if (remaining <= 0) return {name: step.name, id: step.id, group, status: 'unexecuted', outputs: {}};
  const output = join(directory, `${group}-${index}.outputs`);
  const summary = join(directory, `${group}-${index}.summary`);
  const log = openSync(join(directory, group + '.log'), 'a', 0o600);
  const substitute = text => text.replaceAll('${{ runner.temp }}', process.env.RUNNER_TEMP ?? '')
    .replaceAll('${{ github.workspace }}', control.root);
  const env = {...process.env, ...Object.fromEntries(Object.entries(step.env ?? {})
    .map(([key, value]) => [key, substitute(value)])), GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary};
  let code, signal, failure, timedOut = false, stopAt, forceStopRequested = false;
  let groupStop = 'not-requested';
  try {
    const child = spawn('/bin/bash', ['-e', '-o', 'pipefail', '-c', step.run], {
      cwd: control.root, env, detached: true, stdio: ['ignore', log, log],
    });
    const budget = Math.min(remaining, (step.timeoutMinutes ?? Infinity) * 60_000);
    let grace;
    const requestGroupStop = () => {
      if (stopAt !== undefined) return;
      stopAt = Date.now();
      try { process.kill(-child.pid, 'SIGTERM'); } catch (error) { if (error.code !== 'ESRCH') failure = error.code; }
      grace = setTimeout(() => {
        try { process.kill(-child.pid, 'SIGKILL'); forceStopRequested = true; }
        catch (error) { if (error.code !== 'ESRCH') failure = error.code; }
      }, 5000);
    };
    const timer = setTimeout(() => {
      timedOut = true; failure ??= 'ETIMEDOUT';
      requestGroupStop();
    }, budget);
    await new Promise(done => {
      child.once('error', error => { failure = error.code; });
      child.once('close', (status, receivedSignal) => { code = status; signal = receivedSignal; done(); });
    });
    clearTimeout(timer);
    if (timedOut || failure || signal || code !== 0) {
      const groupExists = () => {
        try { process.kill(-child.pid, 0); return true; }
        catch (error) { if (error.code === 'ESRCH') return false; failure = error.code; return true; }
      };
      // The leader's closed FDs do not account for its other group members.
      // Keep the original grace/escalation alive until this known group ends.
      if (groupExists()) requestGroupStop();
      while (groupExists() && Date.now() < stopAt + 6000) await pause(25);
      groupStop = groupExists() ? 'unconfirmed' : 'observed-gone';
    }
    clearTimeout(grace);
  } finally { closeSync(log); }
  const outputs = {};
  if (existsSync(output)) for (const line of readFileSync(output, 'utf8').split('\n').filter(Boolean)) {
    // Only the existing packed-evidence action consumes this output. Other
    // original step outputs stay in the case-owned file, never shared globally.
    const match = /^evidence-directory=([^\r\n]*)$/u.exec(line);
    if (match) outputs['evidence-directory'] = match[1];
  }
  return {name: step.name, id: step.id, group, status: !timedOut && !failure && !signal && code === 0 ? 'success' : 'failure',
    code, signal, failure, timedOut, groupStop, forceStopRequested, startedAt, completedAt: Date.now(), outputs};
}

export async function runNativeGroups(directory) {
  const control = JSON.parse(readFileSync(join(directory, 'control.json'), 'utf8'));
  validateGroups(control.groups);
  const results = new Array(control.groups.length); let next = 0;
  await Promise.all(Array.from({length: Math.min(control.slots, control.groups.length)}, async () => {
    while (next < control.groups.length) {
      const index = next++, group = control.groups[index], cases = [];
      // Preserve failure continuation: every later original case still runs
      // after a failed case while the same original job deadline permits it.
      for (const [ordinal, step] of group.steps.entries()) {
        try { cases.push(await executeCase(control, directory, group.name, step, ordinal)); }
        catch (error) { cases.push({name: step.name, id: step.id, group: group.name,
          status: 'failure', failure: error.code ?? error.name, outputs: {}}); }
        write(join(directory, group.name + '.json'), {token: control.token, cases});
      }
      results[index] = {name: group.name, cases};
    }
  }));
  const result = {token: control.token, groups: results};
  write(join(directory, 'result.json'), result);
  return result;
}

export async function waitNativeGroups(directory, {report = value => process.stdout.write(value), summaryFile} = {}) {
  const control = JSON.parse(readFileSync(join(directory, 'control.json'), 'utf8'));
  const worker = JSON.parse(readFileSync(join(directory, 'worker.json'), 'utf8'));
  assert.equal(worker.token, control.token);
  while (!existsSync(join(directory, 'result.json'))) {
    assert(Date.now() < control.deadline + 10_000, 'Native group result unavailable at the original deadline');
    try { process.kill(worker.pid, 0); } catch { throw new Error('Native group controller exited without complete results'); }
    await pause(50);
  }
  const result = JSON.parse(readFileSync(join(directory, 'result.json'), 'utf8'));
  assert.equal(result.token, control.token);
  assert.deepEqual(result.groups.map(value => value.name), control.groups.map(value => value.name));
  const outputs = {}; let failed = false;
  for (const [index, group] of result.groups.entries()) {
    assert.deepEqual(group.cases.map(value => value.name), control.groups[index].steps.map(value => value.name));
    const log = join(directory, group.name + '.log');
    if (existsSync(log)) for await (const chunk of createReadStream(log, {encoding: 'utf8'})) report(chunk);
    for (const [ordinal, item] of group.cases.entries()) {
      const expected = control.groups[index].steps[ordinal];
      assert.equal(item.id, expected.id);
      assert.equal(item.group, group.name);
      assert(['success', 'failure', 'unexecuted'].includes(item.status));
      if (item.status === 'success') {
        assert.equal(item.code, 0);
        assert.equal(item.signal, null);
        assert.equal(item.failure, undefined);
        assert.equal(item.timedOut, false);
        assert(Number.isSafeInteger(item.startedAt) && Number.isSafeInteger(item.completedAt) &&
          item.completedAt >= item.startedAt);
      }
      failed ||= item.status !== 'success';
      if (item.id && item.outputs['evidence-directory']) outputs[item.id + '-evidence-directory'] = item.outputs['evidence-directory'];
      const summary = join(directory, `${group.name}-${ordinal}.summary`);
      if (summaryFile && existsSync(summary)) for await (const chunk of createReadStream(summary))
        appendFileSync(summaryFile, chunk);
      report('ACTQL_NATIVE_CI_PHASE ' + JSON.stringify({phase: 'consumer', group: group.name,
        name: item.name, milliseconds: item.completedAt === undefined ? null : item.completedAt - item.startedAt,
        outcome: item.status}) + '\n');
    }
  }
  return {status: failed ? 1 : 0, outputs, result};
}

if (process.argv[1] && resolve(process.argv[1]) === entry) {
  const [operation, value] = process.argv.slice(2);
  if (operation === 'worker') {
    await runNativeGroups(value);
  } else if (operation === 'start') {
    assert(['native', 'native-macos'].includes(value));
    const root = fileURLToPath(new URL('../', import.meta.url));
    const plan = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));
    const directory = join(process.env.RUNNER_TEMP, 'native-ci-groups-' + randomUUID());
    startNativeGroups({root, directory, groups: plan[value], deadline: Number(process.env.ACTQL_NATIVE_CI_DEADLINE)});
    appendFileSync(process.env.GITHUB_OUTPUT, 'directory=' + directory + '\n');
  } else if (operation === 'wait') {
    const result = await waitNativeGroups(value, {summaryFile: process.env.GITHUB_STEP_SUMMARY});
    for (const [key, value] of Object.entries(result.outputs)) appendFileSync(process.env.GITHUB_OUTPUT, key + '=' + value + '\n');
    process.exitCode = result.status;
  } else throw new Error('Expected Native groups start, wait or internal worker');
}
