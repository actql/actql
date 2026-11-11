// One final fixed-artifact campaign. Reuse the existing installed README /
// Quickstart consumer and its independent mutation, Result and Saved oracles.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync, writeFileSync} from 'node:fs';
import {arch, cpus, hostname, platform, release, loadavg} from 'node:os';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {approvalCallCounts, assertApprovalCallCounts, assessNativeApproval, approvalPhases} from './native-approval-performance.mjs';

const {values} = parseArgs({options: {normal: {type: 'string'}, output: {type: 'string'},
  runner: {type: 'string'}, diagnostic: {type: 'boolean', default: false}}});
assert(values.normal && values.output && values.runner,
  'usage: test-native-approval-performance.mjs --normal <fixed-RC> --output <new-report> --runner <fixed-runner> [--diagnostic]');
assert(values.runner.length <= 128 && !/[\r\n\0]/u.test(values.runner));
const root = fileURLToPath(new URL('../', import.meta.url));
const directory = realpathSync(resolve(values.normal));
const manifest = await verifyNativeCliRelease(directory), source = checkoutState(root);
assert(source.clean && source.revision === manifest.sourceSha,
  'Performance consumer and fixed Native artifact require the same clean source');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const runner = {name: values.runner, hostname: hostname(), platform: platform(), arch: arch(),
  release: release(), samplerSha256: hash(readFileSync('/usr/bin/time')), cpuModels: [...new Set(cpus().map(cpu => cpu.model))], node: process.version};
const runnerSha256 = hash(JSON.stringify(runner));
const fixtureSha256 = hash(Buffer.concat([
  readFileSync(new URL('./native-cli-mock-scenario.mjs', import.meta.url)),
  readFileSync(new URL('../packages/native-cli/lib/project-scaffold.mjs', import.meta.url)),
]));
const mode = values.diagnostic ? 'diagnostic' : 'final', count = values.diagnostic ? 3 : 30;
const series = ['deal-review-mock', 'churn-risk-mock'].map(template => ({template, mode,
  sourceSha: source.revision, fixtureSha256, runnerSha256, samples: []}));
const report = {version: 'actql-native-approval-performance/0.1', mode, sourceSha: source.revision,
  runner, runnerSha256, fixtureSha256, observation: 'existing opt-in Native timings and acceptance events',
  timer: 'monotonic parent clock around the complete approve process and OS sampler through exit',
  concurrentLoad: 'observed load averages, not an exclusive-machine reservation', loadSnapshots: [], receipts: [], series, failures: [],
  unverified: ['other runners and platforms', 'live providers', 'fault-injection campaign']};
const output = resolve(values.output);
writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
const persist = () => writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
for (let iteration = 0; iteration < count; iteration++) {
  report.loadSnapshots.push({iteration, loadAverage: loadavg()});
  const result = spawnSync(process.execPath,
    [fileURLToPath(new URL('./test-native-cli-mock-install.mjs', import.meta.url)), directory, '--measure-approval-resources'],
    {cwd: root, env: process.env, encoding: 'utf8', timeout: 240000,
      killSignal: 'SIGKILL', maxBuffer: 8 * 1024 ** 2});
  if (result.error || result.signal || result.status !== 0) {
    report.failures.push({iteration, stage: 'original installed consumer',
      code: result.status, signal: result.signal ?? null, error: result.error?.message ?? null,
      stdout: result.stdout ?? '', stderr: result.stderr ?? ''});
    persist(); break;
  }
  const match = /^Installed Native mock approval\/recovery passed: (.+)$/mu.exec(result.stdout);
  assert(match, 'Original installed consumer receipt missing');
  try {
    const receiptPath = realpathSync(match[1]);
    assert.equal(dirname(receiptPath), directory, 'Foreign consumer receipt');
    const bytes = readFileSync(receiptPath), receipt = JSON.parse(bytes);
    assert.equal(receipt.cliSourceSha, source.revision);
    assert.equal(receipt.scenarios.length, 2);
    report.receipts.push({iteration, path: receiptPath, sha256: hash(bytes)});
    for (const selected of series) {
      const scenario = receipt.scenarios.find(value => value.template === selected.template);
      assert(scenario, 'Missing original template workflow');
      const approvals = scenario.commands.filter(command => command.args.includes('approve'));
      assert.equal(approvals.length, 1, 'Approval must execute once per fresh workflow');
      const approval = approvals[0], calls = approvalCallCounts(approval);
      assertApprovalCallCounts(calls, approval.acceptance.writes.length);
      assert(Number.isSafeInteger(approval.wallNs) && approval.wallNs > 0,
        'Actual monotonic approval timer missing');
      selected.samples.push({iteration, sourceSha: source.revision, fixtureSha256, runnerSha256,
        wallNs: approval.wallNs, completed: true, verified: true, calls, phases: approvalPhases(approval), resourceObservationIssue: approval.resourceObservationIssue ?? null, ...approval.resources});
    }
    persist();
    assert.deepEqual(checkoutState(root), source, 'Performance source changed during campaign');
  } catch (error) {
    report.failures.push({iteration, stage: 'original workflow evidence', error: error.message});
    persist(); break;
  }
}
for (const selected of series) selected.assessment = assessNativeApproval(selected);
report.status = report.failures.length || series.some(value => value.assessment.status === 'failed')
  ? 'failed' : series.some(value => value.assessment.status !== 'passed') ? 'incomplete' : 'passed';
persist();
console.log(JSON.stringify({path: output, status: report.status,
  templates: series.map(value => ({template: value.template, ...value.assessment}))}));
process.exitCode = report.status === 'passed' || (mode === 'diagnostic' && report.status === 'incomplete') ? 0 : 1;
