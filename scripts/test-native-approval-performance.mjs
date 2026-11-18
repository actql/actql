// One final fixed-artifact campaign. Reuse the existing installed README /
// Quickstart consumer and its independent mutation, Result and Saved oracles.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync, writeFileSync} from 'node:fs';
import {arch, cpus, hostname, platform, release, loadavg} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';
import {admitNativeReleaseManifest} from './native-cli-release.mjs';
import {openNativeMockCampaign} from './native-mock-campaign.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {approvalCallCounts, assertApprovalCallCounts, assessNativeApproval, approvalPhases, assertNativeApprovalAcceptanceBinding, assertNativeApprovalObservation, nativeMockWorkflowTiming, nativeReleaseVerificationTiming} from './native-approval-performance.mjs';

const {values} = parseArgs({options: {normal: {type: 'string'}, output: {type: 'string'},
  runner: {type: 'string'}, binding: {type: 'string'}, diagnostic: {type: 'boolean', default: false}}});
assert(values.normal && values.output && values.runner,
  'usage: test-native-approval-performance.mjs --normal <fixed-RC> --output <new-report> --runner <fixed-runner> [--diagnostic]');
assert(values.runner.length <= 128 && !/[\r\n\0]/u.test(values.runner));
if (values.binding) assertNativeApprovalAcceptanceBinding(JSON.parse(readFileSync(values.binding, 'utf8')));
const root = fileURLToPath(new URL('../', import.meta.url));
const directory = realpathSync(resolve(values.normal));
// Preparatory DATA only. The original fixture performs the one complete
// artifact admission before any consumer starts; no copied manifest is proof.
const manifest = admitNativeReleaseManifest(JSON.parse(readFileSync(join(directory, 'release.json'), 'utf8')));
const source = checkoutState(root);
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
  concurrentLoad: 'observed load averages, not an exclusive-machine reservation', loadSnapshots: [], receipts: [], workflowTimings: [], series, failures: [],
  unverified: ['other runners and platforms', 'live providers', 'fault-injection campaign']};
const output = resolve(values.output);
writeFileSync(output, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
const persist = () => writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
const campaign = openNativeMockCampaign({script: fileURLToPath(new URL('./test-native-cli-mock-install.mjs', import.meta.url)),
  directory, count, cwd: root});
try {
  for (let iteration = 0; iteration < count; iteration++) {
    report.loadSnapshots.push({iteration, loadAverage: loadavg()});
    const started = process.hrtime.bigint();
    let result;
    try {result = await campaign.run(iteration);}
    catch (error) {
      report.failures.push({iteration, stage: 'original installed consumer', error: error.message});
      persist(); break;
    }
    const consumerWallNs = Number(process.hrtime.bigint() - started);
    if (result.error || result.signal || result.status !== 0) {
      report.failures.push({iteration, stage: 'original installed consumer',
        code: result.status, signal: result.signal ?? null, error: result.error?.message ?? null, consumerWallNs,
        stdout: result.stdout ?? '', stderr: result.stderr ?? ''});
      persist(); break;
    }
    const match = /^Installed Native mock approval\/recovery passed: (.+)$/mu.exec(result.stdout);
    assert(match && match[1] === result.receiptFile, 'Original installed consumer receipt missing or foreign');
    try {
      const receiptPath = realpathSync(match[1]);
      assert.equal(dirname(receiptPath), directory, 'Foreign consumer receipt');
      const bytes = readFileSync(receiptPath), receipt = JSON.parse(bytes);
      assert.equal(receipt.cliSourceSha, source.revision);
      assert.equal(receipt.scenarios.length, 2);
      report.receipts.push({iteration, path: receiptPath, sha256: hash(bytes)});
      report.workflowTimings.push({iteration, consumerWallNs, ...nativeMockWorkflowTiming(receipt),
        ...nativeReleaseVerificationTiming(result.stderr)});
      for (const selected of series) {
        const scenario = receipt.scenarios.find(value => value.template === selected.template);
        assert(scenario, 'Missing original template workflow');
        const approvals = scenario.commands.filter(command => command.args.includes('approve'));
        assert.equal(approvals.length, 1, 'Approval must execute once per fresh workflow');
        const approval = approvals[0], calls = approvalCallCounts(approval);
        assertNativeApprovalObservation(approval);
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
}
finally {
  try {await campaign.close();}
  catch (error) {
    report.failures.push({stage: 'original fixture process close', error: error.message,
      code: error.status ?? null, signal: error.signal ?? null, stdout: error.stdout ?? '', stderr: error.stderr ?? ''});
    persist();
  }
}
for (const selected of series) selected.assessment = assessNativeApproval(selected);
report.status = report.failures.length || series.some(value => value.assessment.status === 'failed')
  ? 'failed' : series.some(value => value.assessment.status !== 'passed') ? 'incomplete' : 'passed';
persist();
console.log(JSON.stringify({path: output, status: report.status,
  templates: series.map(value => ({template: value.template, ...value.assessment}))}));
process.exitCode = report.status === 'passed' || (mode === 'diagnostic' && report.status === 'incomplete') ? 0 : 1;
