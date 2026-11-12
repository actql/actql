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
    env: {...process.env, GITHUB_SHA: source, PACKAGE_BUILD_SOURCE_SHA: source, RUNNER_TEMP: root, ...extra},
    encoding: 'utf8', timeout: 5000, maxBuffer: 65536,
  });
}
function put(path, value) {
  mkdirSync(dirname(path), {recursive: true});
  writeFileSync(path, JSON.stringify(value));
}

function prioritySources(root, node = source, python = source) {
  for (const [platform, sourceSha] of [['node', node], ['python', python]]) {
    put(join(root, 'ordinary-priority', platform, 'source.json'), {sourceSha, eventHeadSha: source});
  }
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

test('Python priority lane reuses the formal wheel producer without changing release routes', () => {
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['ordinary-python-priority'];
  assert.ok(job);
  assert.equal(job['runs-on'], 'macos-15');
  assert.equal(job.permissions.actions, 'read');
  const inspect = job.steps.findIndex(s => s.name === 'Validate the original normal package artifact and producer job');
  const download = job.steps.findIndex(s => s.name === 'Reuse the exact formal package artifact');
  const install = job.steps.findIndex(s => s.id === 'consumer');
  const collect = job.steps.findIndex(s => s.name === 'Collect actual varied Python priority operations');
  assert(inspect >= 0 && inspect < download && download < install && install < collect);
  const originalInstaller = workflow.jobs['ordinary-python'].steps.find(s => s.id === 'consumer');
  assert.equal(job.steps[install].run.replaceAll('ordinary-python-priority', 'ordinary-python'), originalInstaller.run);
  assert.equal(job.steps[inspect].env.PACKAGE_ADAPTER, 'python');
  assert.equal(job.steps[inspect].env.PACKAGE_RUN_ID, '${{ inputs.python-package-run-id }}');
  assert.equal(job.steps[inspect].env.PACKAGE_PRODUCER_JOB, '${{ inputs.python-package-producer-job }}');
  assert.equal(job.steps[download].with['artifact-ids'], '${{ inputs.python-package-artifact-id }}');
  assert.equal(job.steps[download].with['run-id'], '${{ inputs.python-package-run-id }}');
  assert.equal(job.steps[collect]['continue-on-error'], undefined);
  assert.equal(job.steps.at(-1).if, 'always()');
  assert.equal(job.steps.at(-1).with.name, 'ordinary-python-priority-${{ github.sha }}');
  assert.deepEqual(workflow.on.workflow_dispatch.inputs['priority-python-mode'].options, ['diagnostic', 'final']);
  assert.equal(workflow.on.workflow_call.inputs['priority-python-mode'].default, 'diagnostic');
  assert.equal(ci.on.workflow_dispatch.inputs.performance_priority_python_mode.default, 'diagnostic');
  assert.equal(ci.jobs['performance-matrix'].with['priority-python-mode'], '${{ inputs.performance_priority_python_mode }}');
  assert(Object.keys(ci.on.workflow_dispatch.inputs).length <= 25);
  assert(!job.steps.some(s => /\b(?:moon build|npm pack|pip wheel)\b/u.test(s.run ?? '')));
  assert.deepEqual(workflow.jobs['ordinary-python'].strategy.matrix.operation,
    ['first-init', 'cold-existing', 'warm-select', 'warm-result', 'warm-status']);
});

test('Python priority shell command forwards the selected mode and propagates failure', t => {
  const root = temporary(t), bin = join(root, 'bin'), argv = join(root, 'python-argv.jsonl');
  mkdirSync(bin);
  const python = join(bin, 'python3');
  writeFileSync(python, `#!${process.execPath}\nrequire('node:fs').appendFileSync(process.env.ARGV,JSON.stringify(process.argv.slice(2))+'\\n');process.exit(Number(process.env.EXIT));\n`);
  chmodSync(python, 0o755);
  const step = workflow.jobs['ordinary-python-priority'].steps.find(s =>
    s.name === 'Collect actual varied Python priority operations');
  assert.equal(step.env.PRIORITY_MODE, '${{ inputs.priority-python-mode }}');
  assert.equal(step.env.PYTHON_CONSUMER, '${{ steps.consumer.outputs.path }}');
  for (const mode of ['diagnostic', 'final']) {
    const env = {PATH: `${bin}:${process.env.PATH}`, ARGV: argv, PRIORITY_MODE: mode,
      PYTHON_CONSUMER: join(root, 'installed site-packages'), EXIT: '1'};
    const child = run(step, root, env);
    assert.equal(child.status, 1, child.stderr);
  }
  const calls = readFileSync(argv, 'utf8').trim().split('\n').map(JSON.parse);
  for (let i = 0; i < 2; i++) {
    assert.deepEqual(calls[i], ['-I', '-B', 'scripts/benchmark-ordinary-processes.py',
      '--adapter', 'python', '--manifest', join(root, 'ordinary-python-priority/packages/cohort.json'),
      '--consumer', join(root, 'installed site-packages'), '--venv', join(root, 'ordinary-python-priority/venv'),
      '--source', source, '--selection', 'priority-transition', '--mode', ['diagnostic', 'final'][i],
      '--load', 'isolated', '--output', join(root, 'ordinary-python-priority/measurement')]);
  }
});

test('ordinary priority assessment reuses both platform reports without replacing release assessment', () => {
  const job = workflow.jobs['ordinary-priority-assessment'];
  assert(job, 'The controlled lane must assess the ordinary Node/Python priority transition separately');
  assert.deepEqual(job.needs, ['ordinary-node-priority', 'ordinary-python-priority']);
  assert(job.if.includes('always()'), 'Missing or failed collectors must still produce a failed/incomplete assessment');
  const expression = job.if.slice(3, -2).trim();
  for (const [visibility, privateFlag, expected] of [
    ['public', false, true],
    ['private', true, false], ['public', true, false],
    ['public', undefined, false], ['public', false, true],
  ]) {
    assert.equal(runInNewContext(expression, {

      github: {event: {repository: {visibility, private: privateFlag}}},
      inputs: {'native-approval-only': false},
      toJSON: JSON.stringify, always: () => true,
    }, {timeout: 100}), expected);
  }
  assert.deepEqual(workflow.jobs['ordinary-platform-assessment'].needs,
    ['ordinary-operations', 'ordinary-native', 'ordinary-python']);
  for (const name of ['ordinary-operations', 'ordinary-native', 'ordinary-python']) {
    assert.equal(workflow.jobs[name]['runs-on'], name === 'ordinary-operations' ? 'ubuntu-24.04' : 'macos-15');
    const assessments = workflow.jobs[name].steps.filter(step =>
      step.run?.includes('scripts/operation-performance.mjs --input'));
    assert.equal(assessments.length, 1, `${name} must retain its full-release assessment`);
    if (name === 'ordinary-native') {
      const dedicated = workflow.jobs[name].steps.filter(step =>
        step.run?.includes('scripts/operation-performance.mjs --native-operations'));
      assert.equal(dedicated.length, 1);
      assert.equal(assessments[0].if, "always() && matrix.operation != 'native-operations'");
      assert.equal(dedicated[0].if, "always() && matrix.operation == 'native-operations'");
      assert.equal(dedicated[0]['continue-on-error'], undefined);
      // Every Native matrix member retains exactly one required assessment,
      // even after its collector fails; the public-operation lane is distinct.
      for (const operation of workflow.jobs[name].strategy.matrix.operation) {
        const context = {matrix: {operation}, always: () => true};
        const selected = [assessments[0], dedicated[0]].filter(step =>
          runInNewContext(step.if, context, {timeout: 100}));
        assert.equal(selected.length, 1, operation);
        assert.equal(selected[0] === dedicated[0], operation === 'native-operations');
      }
    } else {
      assert.equal(assessments[0].if, 'always()');
    }
    assert.equal(assessments[0]['continue-on-error'], undefined);
  }
  const downloads = job.steps.filter(step => step.uses?.startsWith('actions/download-artifact@'));
  assert.equal(downloads.length, 2);
  assert.equal(downloads[0].with.name, 'ordinary-node-priority-${{ github.sha }}');
  assert.equal(downloads[1].with.name, 'ordinary-python-priority-${{ github.sha }}');
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

test('Native approval only selects its original Native artifact without unrelated package inputs or PR campaigns', () => {
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['native-approval']; assert(job);
  for (const event of ['workflow_dispatch', 'workflow_call']) {
    const inputs = workflow.on[event].inputs;
    assert.equal(inputs['native-approval-only'].default, false);
    for (const field of ['native-package-run-id', 'native-package-artifact-id', 'native-package-producer-job']) {
      assert.equal(inputs[field].required, true);
    }
    for (const field of ['package-run-id', 'package-artifact-id', 'python-package-run-id',
      'python-package-artifact-id', 'python-package-producer-job']) {
      assert.equal(inputs[field].required, false); assert.equal(inputs[field].default, '');
    }
  }
  assert.deepEqual(workflow.on.workflow_dispatch.inputs['native-approval-runner'].options, ['ubuntu-24.04']);
  assert.equal(workflow.on.workflow_call.inputs['native-approval-runner'].default, 'ubuntu-24.04');
  assert.equal(ci.on.workflow_dispatch.inputs.performance_native_approval_only.default, false);
  assert.equal(ci.jobs['performance-matrix'].with['native-approval-only'], '${{ inputs.performance_native_approval_only }}');
  assert.equal(ci.jobs['performance-matrix'].with['native-approval-runner'], '${{ inputs.performance_native_approval_runner }}');
  assert(Object.keys(ci.on.workflow_dispatch.inputs).length <= 25);
  for (const enabled of [false, true]) {
    const context = {github: {event: {repository: {visibility: 'public', private: false}}},
      inputs: {'native-approval-only': enabled}, toJSON: JSON.stringify};
    assert.equal(runInNewContext(job.if.slice(3, -2), context), enabled);
    if (enabled) for (const [name, other] of Object.entries(workflow.jobs)) {
      if (name !== 'native-approval') assert.equal(runInNewContext(other.if.slice(3, -2), context), false, name);
    }
  }
  const inspect = job.steps.findIndex(step => step.env?.PACKAGE_ADAPTER === 'native');
  const download = job.steps.findIndex(step => step.uses?.startsWith('actions/download-artifact@'));
  const collect = job.steps.findIndex(step => step.run?.includes('scripts/test-native-approval-performance.mjs'));
  assert(inspect >= 0 && inspect < download && download < collect);
  assert.equal(job.steps[inspect].env.PACKAGE_PRODUCER_JOB, '${{ inputs.native-package-producer-job }}');
  assert.equal(job.steps[download].with['run-id'], '${{ inputs.native-package-run-id }}');
  assert.equal(job.steps[download].with['artifact-ids'], '${{ inputs.native-package-artifact-id }}');
  assert(!job.steps.some(step => /moon build|npm pack|pip wheel|benchmark-ordinary-processes/u.test(step.run ?? '')));
  assert.equal(job['runs-on'], 'ubuntu-24.04');
  const moon = job.steps.findIndex(step => step.name === 'Install pinned MoonBit for source and generation verification only');
  assert(moon >= 0 && moon < collect);
  assert.equal(job.steps[moon].run, ci.jobs.preflight.steps.find(step => step.name === 'Install pinned MoonBit').run);
});

test('Native approval formal shell keeps the existing thirty-each protocol and actual collector failure', t => {
  const root = temporary(t), bin = join(root, 'bin'), argv = join(root, 'native-argv.jsonl');
  mkdirSync(bin);
  writeFileSync(join(bin, 'node'), `#!${process.execPath}\nconst args=process.argv.slice(2);\nrequire('node:fs').appendFileSync(process.env.ARGV,JSON.stringify(args)+'\\n');\nprocess.exit(Number(args[0]==='--input-type=module' ? process.env.PRECHECK_EXIT ?? '0' : process.env.EXIT));\n`);
  chmodSync(join(bin, 'node'), 0o755);
  const job = workflow.jobs['native-approval'];
  const validate = job.steps.find(step => step.name === 'Validate the selected independent Native runner');
  const collect = job.steps.find(step => step.run?.includes('scripts/test-native-approval-performance.mjs'));
  assert.equal(collect['continue-on-error'], undefined); assert(!collect.run.includes('--diagnostic'));
  for (const runner of ['ubuntu-24.04']) for (const status of [0, 1, 124]) {
    const env = {PATH: `${bin}:${process.env.PATH}`, ARGV: argv, NATIVE_APPROVAL_RUNNER: runner, EXIT: String(status)};
    assert.equal(run(validate, root, env).status, 0);
    assert.equal(run(collect, root, env).status, status);
  }
  assert.equal(run(validate, root, {NATIVE_APPROVAL_RUNNER: 'foreign-runner'}).status, 1);
  assert.equal(run(validate, root, {NATIVE_APPROVAL_RUNNER: 'macos-15'}).status, 1, 'No hosted Darwin Local producer is available');
  const calls = readFileSync(argv, 'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(calls.length, 6, 'Each collector status follows one successful source precheck');
  for (let index = 0; index < 3; index++) {
    assert.deepEqual(calls[index * 2], ['--input-type=module']);
    assert.deepEqual(calls[index * 2 + 1], [
      'scripts/test-native-approval-performance.mjs', '--normal', join(root, 'native-approval/packages/release'),
      '--output', join(root, 'native-approval/assessment.json'), '--runner', 'ubuntu-24.04',
    ]);
  }
  assert.equal(run(collect, root, {PATH: `${bin}:${process.env.PATH}`, ARGV: argv,
    NATIVE_APPROVAL_RUNNER: 'ubuntu-24.04', EXIT: '0', PRECHECK_EXIT: '73'}).status, 73);
  const refused = readFileSync(argv, 'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(refused.length, calls.length + 1, 'Failed source precheck never starts the collector');
  assert.deepEqual(refused.at(-1), ['--input-type=module']);
});

test('Native approval upload always keeps partial assessment and actual receipts without runtime state', () => {
  const job = workflow.jobs['native-approval'], upload = job.steps.at(-1);
  assert.equal(upload.if, 'always()'); assert.equal(upload['continue-on-error'], undefined);
  assert(upload.uses.startsWith('actions/upload-artifact@'));
  assert.equal(upload.with['if-no-files-found'], 'error');
  assert.equal(upload.with.name, 'native-approval-${{ inputs.native-approval-runner }}-${{ github.sha }}');
  assert.deepEqual(upload.with.path.trim().split('\n'), [
    '${{ runner.temp }}/native-approval/producer.json', '${{ runner.temp }}/native-approval/source.json',
    '${{ runner.temp }}/native-approval/assessment.json',
    '${{ runner.temp }}/native-approval/packages/release/release.json', '${{ runner.temp }}/native-approval/packages/release/mock-install-*.json',
  ]);
});

test('Native approval accepts only the successful Linux Local producer artifact namespace', t => {
  const inspect = workflow.jobs['native-approval'].steps.find(step => step.env?.PACKAGE_ADAPTER === 'native');
  for (const [producer, artifactName, expected] of [
    ['native-cli-linux-local', 'native-cli-linux-local-42-3', 0],
    ['native-cli-installed', 'native-cli-linux-local-42-3', 1],
    ['native-cli-linux-local', 'native-cli-installed-42-3', 1],
    ['native-cli-linux-local', 'native-cli-linux-local-99-3', 1],
  ]) {
    const root = temporary(t), bin = join(root, 'bin');mkdirSync(bin);
    writeFileSync(join(bin, 'node'), `#!${process.execPath}\n
      const args=process.argv.slice(2);
      if(args[0]==='scripts/ordinary-operation-packages.mjs'){
        process.stdout.write(process.env.PRODUCER_METADATA);process.exit(0);
      }
      const result=require('node:child_process').spawnSync(process.execPath,args,{stdio:'inherit'});
      process.exit(result.status ?? 1);
    `);
    chmodSync(join(bin, 'node'), 0o755);
    const result = run(inspect, root, {PATH: `${bin}:${process.env.PATH}`, PACKAGE_PRODUCER_JOB: producer,
      PRODUCER_METADATA: JSON.stringify({adapter: 'native', runId: '42', attempt: 3, artifactName})});
    assert.equal(result.status, expected, result.stderr);
  }
});

test('priority report join preserves original collector failures and raw metadata', t => {
  const root = temporary(t); prioritySources(root);
  const node = {sourceSha: source, firstFailure: {step: 'close'}, cleanup: {closed: false},
    packageFailure: {step: 'installed-package'}, samples: [{wallNs: 1}],
    functional: [{passed: true}], controls: {unmatched: true}};
  const python = {sourceSha: source, operation: 'warm-result', firstFailure: null,
    cleanup: {closed: true}, rows: [{original: true}], unknown: null};
  put(join(root, 'ordinary-priority/node/measurement/measurements.json'), node);
  put(join(root, 'ordinary-priority/python/measurement/measurements.json'), python);
  const step = workflow.jobs['ordinary-priority-assessment'].steps.find(step => step.name === 'Join unchanged raw platform reports');
  assert.equal(step.if, 'always()');
  assert.equal(step['continue-on-error'], undefined);
  const child = run(step, root);
  assert.equal(child.status, 0, child.stderr);
  const input = JSON.parse(readFileSync(join(root, 'ordinary-priority/input.json')));
  assert.deepEqual(input, {sourceSha: source, platforms: {node: [node], python: [python]}});
});

test('missing reports stay empty and malformed reports cannot become successful input', t => {
  const root = temporary(t); prioritySources(root);
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
  const root = temporary(t); prioritySources(root);
  const node = {original: 'warm Node report'};
  const python = {original: 'warm Python select report'};
  put(join(root, 'ordinary-priority/node/measurement/measurements.json'), node);
  put(join(root, 'ordinary-priority/node/measurement/cold-existing/measurements.json'), {unrelated: 'cold'});
  put(join(root, 'ordinary-priority/python/measurement/measurements.json'), python);
  for (const operation of ['first-init', 'cold-existing', 'warm-status']) {
    put(join(root, `ordinary-priority/python/ordinary-python-${operation}-${source}/measurement/measurements.json`), {unrelated: operation});
  }
  const step = workflow.jobs['ordinary-priority-assessment'].steps.find(step => step.name === 'Join unchanged raw platform reports');
  const child = run(step, root);
  assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(JSON.parse(readFileSync(join(root, 'ordinary-priority/input.json'))),
    {sourceSha: source, platforms: {node: [node], python: [python]}});
});

test('full-release Python reports cannot replace a missing varied priority population', t => {
  const root = temporary(t); prioritySources(root);
  for (const operation of ['warm-select', 'warm-result']) {
    put(join(root, `ordinary-priority/python/ordinary-python-${operation}-${source}/measurement/measurements.json`),
      {original: operation});
  }
  const step = workflow.jobs['ordinary-priority-assessment'].steps.find(s => s.name === 'Join unchanged raw platform reports');
  const child = run(step, root);
  assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(JSON.parse(readFileSync(join(root, 'ordinary-priority/input.json'))),
    {sourceSha: source, platforms: {node: [], python: []}});
});

test('priority join rejects different adapter build sources despite matching workflow event identity', t => {
  const root = temporary(t); prioritySources(root, source, 'b'.repeat(40));
  const step = workflow.jobs['ordinary-priority-assessment'].steps.find(s => s.name === 'Join unchanged raw platform reports');
  assert.notEqual(run(step, root).status, 0);
  assert.throws(() => readFileSync(join(root, 'ordinary-priority/input.json')), {code: 'ENOENT'});
  prioritySources(root);
  put(join(root, 'ordinary-priority/python/source.json'), {sourceSha: source, eventHeadSha: 'b'.repeat(40)});
  assert.notEqual(run(step, root).status, 0);
  rmSync(join(root, 'ordinary-priority/python/source.json'));
  assert.notEqual(run(step, root).status, 0, 'Missing Source proof cannot fall back to the workflow event');
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
  const root = temporary(t); prioritySources(root);
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
