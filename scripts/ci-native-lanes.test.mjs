import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {gateJobs, gateJobRequired, selectTargets} from './ci-targets.mjs';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const original = JSON.parse(readFileSync(new URL('./fixtures/ci-native-obligations.json', import.meta.url), 'utf8'));
const runCondition = (expression, group) => runInNewContext(expression
  .replace(/^\$\{\{\s*|\s*\}\}$/gu, '').replace(/\.([a-z]+(?:-[a-z]+)+)/gu, "['$1']"), {
  matrix: {group}, cancelled: () => false, always: () => true,
  steps: new Proxy({}, {get: () => ({outcome: 'success', outputs: {'evidence-directory': '/owned'}})}),
}, {timeout: 100});

test('every original Native command and environment has one independent execution owner', () => {
  for (const [family, obligations] of Object.entries(original.jobs)) {
    const http = family === 'native' ? 'native-http' : 'native-http-macos';
    const jobs = [workflow.jobs[family], workflow.jobs[http]];
    const cases = jobs.flatMap(job => job.steps.filter(step => step.run && /^(?:Test |Verify registered)/u.test(step.name ?? '')));
    assert.deepEqual(cases.map(step => step.name).sort(), obligations.map(step => step.name).sort());
    for (const expected of obligations) {
      const matches = jobs.flatMap(job => job.steps.filter(step => step.name === expected.name).map(step => ({job, step})));
      assert.equal(matches.length, 1, expected.name);
      const {job, step} = matches[0];
      assert.equal(createHash('sha256').update(step.run).digest('hex'), expected.commandSha256, expected.name);
      assert.deepEqual(step.env ?? {}, expected.env, expected.name);
      if (job.strategy) assert.equal(job.strategy.matrix.group.filter(group => runCondition(step.if, group)).length, 1, expected.name);
    }
  }
});

test('Native HTTP does not await or duplicate the unrelated software preparation', () => {
  const httpSource = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  assert(!httpSource.includes('native-runtime-bundle-fixture.mjs'));
  assert(!httpSource.includes('ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION'));
  for (const job of ['native-http', 'native-http-macos']) {
    assert.deepEqual(workflow.jobs[job].needs, ['select-targets', 'preflight']);
    assert(!workflow.jobs[job].steps.some(step => step.id === 'native-preparation'));
    assert(gateJobs.includes(job));
    assert(workflow.jobs.check.needs.includes(job));
  }
});

test('one immutable Native preparation per platform feeds every independent software consumer', () => {
  for (const family of ['native', 'native-macos']) {
    const producer = family + '-preparation', job = workflow.jobs[family];
    assert(job.needs.includes(producer));
    assert.equal(job.strategy['fail-fast'], false);
    assert.equal(job['continue-on-error'], undefined);
    const preparation = workflow.jobs[producer];
    assert.equal(preparation.steps.filter(step => step.run?.includes('prepare-native-runtime-bundle-fixture.mjs')).length, 1);
    assert.equal(job.steps.filter(step => step.run?.includes('prepare-native-runtime-bundle-fixture.mjs')).length, 0);
    const download = job.steps.find(step => step.name === 'Download the exact Native software producer artifact');
    assert.equal(download.with['artifact-id'], '${{ needs.' + producer + '.outputs.artifact-id }}');
    assert.equal(download.with['client-environment'], 'false');
    assert.equal(job.steps.find(step => step.id === 'native-preparation').run,
      'python3 -B scripts/native-ci-artifact.py restore --artifact "${{ runner.temp }}/native-prepared-artifact"');
    assert(gateJobs.includes(producer)); assert(workflow.jobs.check.needs.includes(producer));
  }
  const portable = selectTargets(['README.md']);
  for (const job of ['native-macos', 'native-macos-preparation', 'native-http-macos'])
    assert.equal(gateJobRequired(portable, job), portable.macos);
});

test('Native download keeps exact-ID validation and cannot activate Client npm inputs', () => {
  const action = parse(readFileSync(new URL('../.github/actions/download-client-packages/action.yml', import.meta.url), 'utf8'));
  assert.equal(action.inputs['client-environment'].default, 'true');
  const guard = action.runs.steps.find(step => step.name === 'Require exactly one producer artifact');
  const source = /^node -e '\n([\s\S]*)'\n?$/u.exec(guard.run)?.[1];
  assert(source);
  for (const id of ['1', '', '0', '1,2', 'other']) for (const mode of ['true', 'false', 'invalid']) {
    const result = spawnSync(process.execPath, ['-e', source], {
      env: {...process.env, ARTIFACT_ID: id, CLIENT_ENVIRONMENT: mode},
      encoding: 'utf8', timeout: 5000,
    });
    assert.equal(result.status, id === '1' && mode !== 'invalid' ? 0 : 1);
  }
  const activation = action.runs.steps.find(step => step.name === 'Use verified Client inputs in subsequent acceptance steps');
  assert.equal(activation.if, "${{ inputs.client-environment == 'true' }}");
  assert.equal(action.runs.steps[1].with['artifact-ids'], '${{ inputs.artifact-id }}');
  assert.equal(action.runs.steps[1]['continue-on-error'], undefined);
});

test('the existing local Native route still contains every original case without fake Actions context', () => {
  const output = execFileSync(process.execPath, ['scripts/local-checks.mjs', 'run', 'native', '--dry-run'], {
    cwd: new URL('../', import.meta.url), encoding: 'utf8', timeout: 5000,
  });
  for (const {name} of original.jobs.native)
    assert.equal(output.split(`== native: ${name}\n`).length - 1, 1, name);
  assert.equal(output.split('node scripts/prepare-native-runtime-bundle-fixture.mjs').length - 1, 1);
  assert(!output.includes('native-ci-artifact.py'));
  assert(!output.includes('GITHUB_RUN_ID'));
  const helper = readFileSync(new URL('./local-checks.mjs', import.meta.url), 'utf8');
  assert(helper.includes('Incomplete local Native composition; retain all original consumers'));
  assert(helper.includes('ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION: join(scratch'));
});
