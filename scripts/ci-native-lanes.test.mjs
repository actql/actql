import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {gateJobs, gateJobRequired, selectTargets} from './ci-targets.mjs';
import {validateGroups} from './ci-native-background-groups.mjs';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const original = JSON.parse(readFileSync(new URL('./fixtures/ci-native-obligations.json', import.meta.url), 'utf8'));
const background = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));

test('every original Native command and environment has one same-VM execution owner', () => {
  for (const [family, obligations] of Object.entries(original.jobs)) {
    validateGroups(background[family]);
    const workload = workflow.jobs[family + '-workloads'];
    const http = workflow.jobs[family === 'native' ? 'native-http' : 'native-http-macos'];
    const cases = [...workload.steps, ...http.steps, ...background[family].flatMap(group => group.steps)]
      .filter(step => step.run && /^(?:Test |Verify registered)/u.test(step.name ?? ''));
    assert.deepEqual(cases.map(step => step.name).sort(), obligations.map(step => step.name).sort());
    for (const expected of obligations) {
      const matches = cases.filter(step => step.name === expected.name);
      assert.equal(matches.length, 1, expected.name);
      assert.equal(createHash('sha256').update(matches[0].run).digest('hex'), expected.commandSha256, expected.name);
      assert.deepEqual(matches[0].env ?? {}, expected.env, expected.name);
    }
  }
});

test('HTTP remains independent while all other consumers retain the same physical preparation', () => {
  const httpSource = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  assert(!httpSource.includes('native-runtime-bundle-fixture.mjs'));
  assert(!httpSource.includes('ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION'));
  for (const family of ['native', 'native-macos']) {
    const workload = workflow.jobs[family + '-workloads'];
    const http = family === 'native' ? 'native-http' : 'native-http-macos';
    assert.deepEqual(workflow.jobs[http].needs, ['select-targets', 'preflight']);
    assert.deepEqual(workload.needs, ['select-targets', 'preflight']);
    assert.equal(workload.strategy, undefined);
    assert.equal(workload.steps.filter(step => step.run?.includes('prepare-native-runtime-bundle-fixture.mjs')).length, 1);
    assert(!workload.steps.some(step => step.uses === './.github/actions/download-client-packages'));
    const preparation = workload.steps.findIndex(step => step.id === 'native-preparation');
    const start = workload.steps.findIndex(step => step.id === 'native-background-start');
    const effect = workload.steps.findIndex(step => step.id === 'native-effect');
    const site = workload.steps.findIndex(step => step.id === 'native-runtime-test');
    const join = workload.steps.findIndex(step => step.id === 'native-background');
    assert(preparation < start && start < effect && effect < site && site < join);
    if (family === 'native') {
      const retained = workload.steps.findIndex(step => step.name === 'Verify registered Native retained product path');
      assert(retained > join, 'The long retained compiler cannot hold the global Moon lock during npm prepack');
      assert.equal(workload.steps[retained].if, "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}");
      assert(!background[family].flatMap(group => group.steps).some(step =>
        step.name === 'Verify registered Native retained product path'));
    }
    assert.equal(workload.steps[start].if, "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}");
    assert(workload.steps[join].if.includes("steps.native-background-start.outcome == 'success'"));
    assert(workload.steps[join].run.includes('steps.native-background-start.outputs.directory'));
    assert(workflow.jobs[family].needs.includes(family + '-workloads'));
    assert(workflow.jobs[family].needs.includes(http));
    assert(gateJobs.includes(family)); assert(workflow.jobs.check.needs.includes(family));
  }
  const portable = selectTargets(['README.md']);
  assert.equal(gateJobRequired(portable, 'native-macos'), portable.macos);
});

test('original Native aggregate refuses every missing failed cancelled or skipped required child', () => {
  for (const family of ['native', 'native-macos']) {
    const job = workflow.jobs[family];
    assert(job.if.includes('always()'));
    const code = /^node -e '\n([\s\S]*)'\n?$/u.exec(job.steps[0].run)?.[1];
    assert(code);
    const complete = Object.fromEntries(job.needs.map(name => [name, {result: 'success'}]));
    const evaluate = results => {
      const process = {env: {RESULTS: JSON.stringify(results)}};
      runInNewContext(code, {process, console: {error() {}}});
      return process.exitCode ?? 0;
    };
    assert.equal(evaluate(complete), 0);
    for (const dependency of [family + '-workloads', family === 'native' ? 'native-http' : 'native-http-macos']) {
      for (const result of ['failure', 'cancelled', 'skipped', undefined])
        assert.equal(evaluate({...complete, [dependency]: {result}}), 1, `${dependency}:${result}`);
      const missing = {...complete}; delete missing[dependency]; assert.equal(evaluate(missing), 1);
    }
  }
});

test('local Native route retains every original case serially with one preparation and no hosted worker', () => {
  const output = execFileSync(process.execPath, ['scripts/local-checks.mjs', 'run', 'native', '--dry-run'], {
    cwd: new URL('../', import.meta.url), encoding: 'utf8', timeout: 5000,
  });
  for (const {name} of original.jobs.native)
    assert.equal(output.split(`== native: ${name}\n`).length - 1, 1, name);
  assert.equal(output.split('node scripts/prepare-native-runtime-bundle-fixture.mjs').length - 1, 1);
  assert(!output.includes('ci-native-background-groups.mjs'));
  assert(!output.includes('native-ci-artifact.py'));
});
