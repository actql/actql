import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';

const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
const source = 'a'.repeat(40);
function temporary(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-priority-ci-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  return root;
}
function run(step, root, extra = {}) {
  return spawnSync('bash', ['-eo', 'pipefail', '-c', step.run], {
    env: {...process.env, GITHUB_SHA: source, RUNNER_TEMP: root, ...extra},
    encoding: 'utf8', timeout: 5000, maxBuffer: 65536,
  });
}
function put(path, value) {
  mkdirSync(dirname(path), {recursive: true});
  writeFileSync(path, JSON.stringify(value));
}

test('priority collector lane reuses the package producer and exposes only explicit sample modes', () => {
  const job = workflow.jobs['ordinary-node-priority'];
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  assert.equal(job.permissions.actions, 'read');
  const inspect = job.steps.findIndex(s => s.name === 'Validate the original normal package producer');
  const download = job.steps.findIndex(s => s.name === 'Reuse the exact existing normal package artifact');
  const prepare = job.steps.findIndex(s => s.name === 'Bind the selected priority protocol to a fresh ordinary consumer');
  const collect = job.steps.findIndex(s => s.name === 'Collect actual varied public priority operations');
  assert(inspect >= 0 && inspect < download && download < prepare && prepare < collect);
  assert.equal(job.steps[inspect].env.PACKAGE_RUN_ID, '${{ inputs.package-run-id }}');
  assert.equal(job.steps[download].with['artifact-ids'], '${{ inputs.package-artifact-id }}');
  assert.equal(job.steps[download].with['run-id'], '${{ inputs.package-run-id }}');
  assert.equal(job.steps[collect]['continue-on-error'], undefined);
  assert.equal(job.steps.at(-1).if, 'always()');
  assert.equal(job.steps.at(-1).with.name, 'ordinary-node-priority-${{ github.sha }}');
  assert.deepEqual(workflow.on.workflow_dispatch.inputs['priority-node-mode'].options, ['diagnostic', 'final']);
  assert.equal(workflow.on.workflow_call.inputs['priority-node-mode'].default, 'diagnostic');
  assert.equal(ci.on.workflow_dispatch.inputs.performance_priority_node_mode.default, 'diagnostic');
  // GitHub.com: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_dispatchinputs
  assert(Object.keys(ci.on.workflow_dispatch.inputs).length <= 25);
  assert.equal(ci.jobs['performance-matrix'].with['priority-node-mode'], '${{ inputs.performance_priority_node_mode }}');
  assert(!job.steps.some(s => /\b(?:moon build|npm pack|pip wheel|benchmark-node-sqlite)\b/u.test(s.run ?? '')));
});

test('priority workflow commands preserve mode and collector failure at the actual shell boundary', t => {
  const root = temporary(t), bin = join(root, 'bin'), argv = join(root, 'argv.jsonl');
  mkdirSync(bin);
  const node = join(bin, 'node');
  writeFileSync(node, `#!${process.execPath}\nrequire('node:fs').appendFileSync(process.env.ARGV,JSON.stringify(process.argv.slice(2))+'\\n');process.exit(Number(process.env.EXIT));\n`);
  chmodSync(node, 0o755);
  const job = workflow.jobs['ordinary-node-priority'];
  const prepare = job.steps.find(s => s.name === 'Bind the selected priority protocol to a fresh ordinary consumer');
  const collect = job.steps.find(s => s.name === 'Collect actual varied public priority operations');
  for (const mode of ['diagnostic', 'final']) {
    const env = {PATH: `${bin}:${process.env.PATH}`, ARGV: argv, PRIORITY_MODE: mode, EXIT: '0'};
    assert.equal(run(prepare, root, env).status, 0);
    const result = run(collect, root, {...env, EXIT: '1'});
    assert.equal(result.status, 1, result.stderr);
  }
  const calls = readFileSync(argv, 'utf8').trim().split('\n').map(JSON.parse);
  for (let i = 0; i < 2; i++) {
    const mode = ['diagnostic', 'final'][i];
    assert.deepEqual(calls[i * 2], ['scripts/ordinary-operation-packages.mjs', 'prepare',
      join(root, 'ordinary-node-priority/packages'), source, join(root, 'ordinary-node-priority/prepared'),
      '--selection', 'priority-transition', '--mode', mode]);
    assert.deepEqual(calls[i * 2 + 1], ['scripts/benchmark-node-operations.mjs',
      '--manifest', join(root, 'ordinary-node-priority/packages/ordinary-operation-packages.json'),
      '--consumer', join(root, 'ordinary-node-priority/prepared/consumer'),
      '--output', join(root, 'ordinary-node-priority/measurement'),
      '--controls', join(root, 'ordinary-node-priority/prepared/controls.json'),
      '--selection', 'priority-transition', '--mode', mode]);
  }
});

test('ordinary priority assessment reuses both platform reports without replacing release assessment', () => {
  const job = workflow.jobs['ordinary-priority-assessment'];
  assert(job, 'The controlled lane must assess the ordinary Node/Python priority transition separately');
  assert.deepEqual(job.needs, ['ordinary-node-priority', 'ordinary-python']);
  assert(job.if.includes('always()'), 'Missing or failed collectors must still produce a failed/incomplete assessment');
  const expression = job.if.slice(3, -2).trim();
  for (const [enabled, visibility, privateFlag, expected] of [
    [undefined, 'public', false, false], ['false', 'public', false, false],
    ['true', 'private', true, false], ['true', 'public', true, false],
    ['true', 'public', undefined, false], ['true', 'public', false, true],
  ]) {
    assert.equal(runInNewContext(expression, {
      vars: {ACTQL_MAIN_CI_ENABLED: enabled},
      github: {event: {repository: {visibility, private: privateFlag}}},
      toJSON: JSON.stringify, always: () => true,
    }, {timeout: 100}), expected);
  }
  assert.deepEqual(workflow.jobs['ordinary-platform-assessment'].needs,
    ['ordinary-operations', 'ordinary-native', 'ordinary-python']);
  for (const name of ['ordinary-operations', 'ordinary-native', 'ordinary-python']) {
    const assessments = workflow.jobs[name].steps.filter(step =>
      step.run?.includes('scripts/operation-performance.mjs --input'));
    assert.equal(assessments.length, 1, `${name} must retain its full-release assessment`);
    assert.equal(assessments[0].if, 'always()');
    assert.equal(assessments[0]['continue-on-error'], undefined);
  }
  const downloads = job.steps.filter(step => step.uses?.startsWith('actions/download-artifact@'));
  assert.equal(downloads.length, 2);
  assert.equal(downloads[0].with.name, 'ordinary-node-priority-${{ github.sha }}');
  assert.equal(downloads[1].with.pattern, 'ordinary-python-*-${{ github.sha }}');
  assert.equal(downloads[1].with['merge-multiple'], false);
  for (const step of downloads) {
    assert.equal(step.if, 'always()');
    assert.equal(step['continue-on-error'], undefined);
    assert.equal(step.with['run-id'], undefined, 'Reports come from this controlled workflow run');
  }
  assert(!job.steps.some(step => /\b(?:moon build|npm pack|pip wheel)\b/u.test(step.run ?? '')));
  assert.equal(job.steps.at(-1).if, 'always()');
  assert(job.steps.at(-1).uses.startsWith('actions/upload-artifact@'));
});

test('priority report join preserves original collector failures and raw metadata', t => {
  const root = temporary(t);
  const node = {sourceSha: source, firstFailure: {step: 'close'}, cleanup: {closed: false},
    packageFailure: {step: 'installed-package'}, samples: [{wallNs: 1}],
    functional: [{passed: true}], controls: {unmatched: true}};
  const python = {sourceSha: source, operation: 'warm-result', firstFailure: null,
    cleanup: {closed: true}, rows: [{original: true}], unknown: null};
  put(join(root, 'ordinary-priority/node/measurement/measurements.json'), node);
  put(join(root, `ordinary-priority/python/ordinary-python-warm-result-${source}/measurement/measurements.json`), python);
  const step = workflow.jobs['ordinary-priority-assessment'].steps.find(step => step.name === 'Join unchanged raw platform reports');
  assert.equal(step.if, 'always()');
  assert.equal(step['continue-on-error'], undefined);
  const child = run(step, root);
  assert.equal(child.status, 0, child.stderr);
  const input = JSON.parse(readFileSync(join(root, 'ordinary-priority/input.json')));
  assert.deepEqual(input, {sourceSha: source, platforms: {node: [node], python: [python]}});
});

test('missing reports stay empty and malformed reports cannot become successful input', t => {
  const root = temporary(t);
  const step = workflow.jobs['ordinary-priority-assessment'].steps.find(step => step.name === 'Join unchanged raw platform reports');
  assert.equal(run(step, root).status, 0);
  const path = join(root, 'ordinary-priority/input.json');
  assert.deepEqual(JSON.parse(readFileSync(path)), {sourceSha: source, platforms: {node: [], python: []}});
  rmSync(path);
  const raw = join(root, 'ordinary-priority/node/measurement/measurements.json');
  mkdirSync(dirname(raw), {recursive: true});
  writeFileSync(raw, '{invalid raw report');
  assert.notEqual(run(step, root).status, 0);
  assert.throws(() => readFileSync(path), {code: 'ENOENT'});
});

test('unrelated release routes cannot add conditions or substitute priority evidence', t => {
  const root = temporary(t);
  const node = {original: 'warm Node report'};
  const python = {original: 'warm Python select report'};
  put(join(root, 'ordinary-priority/node/measurement/measurements.json'), node);
  put(join(root, 'ordinary-priority/node/measurement/cold-existing/measurements.json'), {unrelated: 'cold'});
  put(join(root, `ordinary-priority/python/ordinary-python-warm-select-${source}/measurement/measurements.json`), python);
  for (const operation of ['first-init', 'cold-existing', 'warm-status']) {
    put(join(root, `ordinary-priority/python/ordinary-python-${operation}-${source}/measurement/measurements.json`), {unrelated: operation});
  }
  const step = workflow.jobs['ordinary-priority-assessment'].steps.find(step => step.name === 'Join unchanged raw platform reports');
  const child = run(step, root);
  assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(JSON.parse(readFileSync(join(root, 'ordinary-priority/input.json'))),
    {sourceSha: source, platforms: {node: [node], python: [python]}});
});

test('checkpoint command propagates assessor failure without replacing full release checks', t => {
  const root = temporary(t);
  const job = workflow.jobs['ordinary-priority-assessment'];
  const step = job.steps.find(step => step.name === 'Require the measured public priority checkpoint');
  assert.equal(step.if, 'always()');
  assert.equal(step['continue-on-error'], undefined);
  const bin = join(root, 'bin'); mkdirSync(bin);
  const argv = join(root, 'argv.json');
  const node = join(bin, 'node');
  writeFileSync(node, `#!${process.execPath}\nrequire('node:fs').writeFileSync(process.env.ARGV,JSON.stringify(process.argv.slice(2)));process.exit(1);\n`);
  chmodSync(node, 0o755);
  const child = run(step, root, {PATH: `${bin}:${process.env.PATH}`, ARGV: argv});
  assert.equal(child.status, 1, child.stderr);
  assert.deepEqual(JSON.parse(readFileSync(argv)), ['scripts/operation-performance.mjs',
    '--priority-transition', join(root, 'ordinary-priority/input.json'),
    '--output', join(root, 'ordinary-priority/assessment.json')]);
});

test('controlled job executes the composed assessor on missing and failed original reports', t => {
  const root = temporary(t);
  const job = workflow.jobs['ordinary-priority-assessment'];
  const collect = job.steps.find(step => step.name === 'Join unchanged raw platform reports');
  const assess = job.steps.find(step => step.name === 'Require the measured public priority checkpoint');
  const output = join(root, 'ordinary-priority/assessment.json');
  assert.equal(run(collect, root).status, 0);
  const missing = run(assess, root);
  assert.equal(missing.status, 1, missing.stderr);
  const incomplete = JSON.parse(readFileSync(output));
  assert.equal(incomplete.status, 'incomplete');
  assert.equal(incomplete.releaseAccepted, false);
  assert.equal(incomplete.fullPerformanceAccepted, false);
  rmSync(output);
  const hash = 'b'.repeat(64);
  put(join(root, 'ordinary-priority/node/measurement/measurements.json'), {
    sourceSha: source, cohortSha256: hash, environmentSha256: hash,
    historyProtocolSha256: hash, executionPath: 'node-sdk',
    installedPayloadsUnchanged: false, packageFailure: 'changed after samples',
    firstFailure: {step: 'await original close'}, cleanup: {closed: false},
  });
  assert.equal(run(collect, root).status, 0);
  const failed = run(assess, root);
  assert.equal(failed.status, 1, failed.stderr);
  const result = JSON.parse(readFileSync(output));
  assert.equal(result.status, 'failed');
  assert(result.failures.some(reason => reason.includes('reported public/package/cleanup failure')));
  assert.equal(result.releaseAccepted, false);
  const closedAlternative = spawnSync(process.execPath,
    ['scripts/operation-performance.mjs', '--priority-transition',
      join(root, 'ordinary-priority/input.json'), '--native-sqlite-control', 'unused',
      '--native-sqlite-protocol', 'unused'], {encoding: 'utf8', timeout: 5000});
  assert.equal(closedAlternative.status, 2);
  assert.match(closedAlternative.stderr, /Unknown or duplicate assessment option/u);
});
