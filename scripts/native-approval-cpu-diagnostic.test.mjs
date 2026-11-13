import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';
import {approvalPerfSamples} from './test-native-approval-cpu-diagnostic.mjs';

const selected = [{template: 'deal-review-mock', pid: 101}, {template: 'churn-risk-mock', pid: 202}];
const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
const driver = readFileSync(new URL('./test-native-approval-cpu-diagnostic.mjs', import.meta.url), 'utf8');
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');

test('flat CPU attribution selects actual approval processes and removes paths and offsets', () => {
  const result = approvalPerfSamples([
    '101 _M0_original_journal+0x12 (/private/original/install/actql-native-client)',
    '101 _M0_original_journal+0x80 (/private/original/install/actql-native-client)',
    '202 sqlite3_step (/private/original/install/actql-native-client)',
    '303 private-unselected-payload (/private/foreign/state/key)',
  ].join('\n'), selected);
  assert.equal(result[0].samples, 2);
  assert.deepEqual(result[0].topSymbols, [{symbol: '_M0_original_journal', samples: 2}]);
  assert.deepEqual(result[1].topSymbols, [{symbol: 'sqlite3_step', samples: 1}]);
  assert.doesNotMatch(JSON.stringify(result), /private|payload|0x|foreign/u);
});

test('unresolved CPU locations stay explicit without publishing addresses or arbitrary text', () => {
  const result = approvalPerfSamples('101 0xabcdef ([unknown])\n202 [unknown] ([unknown])\n', selected);
  assert.deepEqual(result.map(value => [value.samples, value.unresolved]), [[1, 1], [1, 1]]);
  assert(result.every(value => value.topSymbols.length === 0));
  assert.doesNotMatch(JSON.stringify(result), /abcdef|unknown/u);
});

test('foreign lines cannot replace missing approval samples and malformed selected lines refuse', () => {
  assert(approvalPerfSamples('303 symbol (/not-selected)\n', selected).every(value => value.samples === 0));
  assert.throws(() => approvalPerfSamples('101 malformed-selected-sample\n', selected), /Invalid selected/u);
  assert.throws(() => approvalPerfSamples('', [selected[0], {...selected[1], pid: 101}]), /Distinct actual/u);
  assert.throws(() => approvalPerfSamples('', [{...selected[0], pid: -1}, selected[1]]));
});

test('unrelated non-PID text is skipped explicitly and only fixed line-shape facts survive a selected refusal', () => {
  const counts = {};
  const result = approvalPerfSamples('renderer notice /not-for-report\n303 foreign (/elsewhere)\n' +
    '101 original_function (/original)\n202 other_function (/original)\n', selected, counts);
  assert.deepEqual(result.map(value => value.samples), [1, 1]);
  assert.deepEqual(counts, {nonEmptyLines: 4, nonPidLines: 1, foreignPidLines: 1,
    selectedLines: 2, malformedSelectedLines: 0});
  const refused = {};
  assert.throws(() => approvalPerfSamples('101 malformed-selected-sample\n', selected, refused), error => {
    assert.equal(error.code, 'NativeApprovalPerfSelectedLineInvalid');
    assert.deepEqual(error.lineShape, {characters: 29, whitespaceFields: 2, hasDsoEnvelope: false});
    assert.doesNotMatch(JSON.stringify(error.lineShape), /selected-sample|original|not-for-report/u);
    return true;
  });
  assert.equal(refused.malformedSelectedLines, 1);
});

test('CPU report has bounded top-symbol output and counts unavailable oversized symbols', () => {
  const lines = Array.from({length: 60}, (_, index) => `101 function_${index} (/original)`);
  lines.push(`202 ${'x'.repeat(2049)} (/original)`);
  const result = approvalPerfSamples(lines.join('\n'), selected);
  assert.equal(result[0].samples, 60); assert.equal(result[0].topSymbols.length, 40);
  assert.equal(result[1].unresolved, 1);
});

test('CPU mode is explicit and false by default while all unrelated jobs exclude it', () => {
  for (const event of ['workflow_dispatch', 'workflow_call']) {
    assert.deepEqual(workflow.on[event].inputs['native-approval-cpu-diagnostic'].default, false);
    assert.equal(workflow.on[event].inputs['native-approval-cpu-diagnostic'].type, 'boolean');
  }
  assert(workflow.jobs['native-approval'].if.includes("inputs['native-approval-cpu-diagnostic']"));
  for (const [name, job] of Object.entries(workflow.jobs)) {
    if (name !== 'native-approval') assert(job.if.includes("!inputs['native-approval-cpu-diagnostic']"), name);
  }
});

test('normal Native and all other job bodies preserve the original performance matrix', () => {
  const native = structuredClone(workflow.jobs['native-approval']);
  native.if = native.if.replace("(inputs['native-approval-only'] || inputs['native-approval-cpu-diagnostic'])", "inputs['native-approval-only']");
  native.steps = native.steps.filter(step => ![
    'Prepare the opt-in unprivileged flat CPU diagnostic',
    'Sample one unchanged installed Native workflow by actual approval PID',
    'Retain only sanitized CPU attribution and original artifact metadata',
  ].includes(step.name));
  delete native.steps.find(step => step.name === 'Measure thirty complete approvals for each original Native template').if;
  native.steps.find(step => step.name === 'Retain Native approval failures partial samples and actual receipts').if = 'always()';
  assert.equal(hash(native), 'f7df7463e4f64be21597375edf49013b83db843ba8a228e8d37b45f9fe8232fb');
  const others = Object.fromEntries(Object.entries(workflow.jobs).filter(([name]) => name !== 'native-approval')
    .map(([name, original]) => {const job = structuredClone(original);
      job.if = job.if.replace(" && !inputs['native-approval-cpu-diagnostic']", ''); return [name, job];}));
  assert.equal(hash(others), 'e241961270d1a120521425289d5e6cba999bafe6c2ad098c5323cb755da731bc');
});

test('diagnostic uploads only sanitized attribution and original artifact metadata', () => {
  const steps = workflow.jobs['native-approval'].steps;
  const upload = steps.find(step => step.name === 'Retain only sanitized CPU attribution and original artifact metadata');
  assert.deepEqual(upload.with.path.trim().split('\n').map(path => path.trim()), [
    '${{ runner.temp }}/native-approval/cpu.json', '${{ runner.temp }}/native-approval/profiler-setup.json',
    '${{ runner.temp }}/native-approval/producer.json',
    '${{ runner.temp }}/native-approval/source.json', '${{ runner.temp }}/native-approval/packages/release/release.json',
  ]);
  assert(steps.find(step => step.name === 'Retain Native approval failures partial samples and actual receipts')
    .if.includes("!inputs['native-approval-cpu-diagnostic']"));
  assert(driver.includes("process.getuid() !== 0"));
  assert(driver.includes("['stat', '-e', 'cpu-clock:u', '--', '/usr/bin/true']"));
  assert(driver.includes("'-F', '49'"));
  assert.doesNotMatch(driver, /--call-graph|--user-regs|--user-stack|sysctl|setcap|sudo/u);
  assert.equal([...driver.matchAll(/join\(root, 'scripts\/test-native-cli-mock-install\.mjs'\)/gu)].length, 1);
  assert(driver.includes('approvalCallCounts(approvals[0]).pid'));
  assert(driver.includes("ACTQL_TEST_PRESERVE_SCRATCH: '1'"));
  assert(driver.includes('rmSync(scratch, {recursive: true})'));
});

test('isolated profiler setup changes only a denied restrictive measurement setting and restores it', () => {
  const step = workflow.jobs['native-approval'].steps.find(value =>
    value.name === 'Sample one unchanged installed Native workflow by actual approval PID');
  assert(step.if.includes("inputs['native-approval-cpu-diagnostic']"));
  assert(step.run.includes('if "$NATIVE_APPROVAL_PERF" stat -e cpu-clock:u -- /usr/bin/true'));
  assert(step.run.includes('[ "$original_paranoid" -gt 1 ] && grep -Eiq'));
  assert(step.run.includes('sudo sysctl -w kernel.perf_event_paranoid=1'));
  assert(step.run.includes('trap finish_profiler_setup EXIT'));
  assert(step.run.includes('sudo sysctl -w "kernel.perf_event_paranoid=$original_paranoid"'));
  assert(step.run.includes('restorationVerified: restoreStatus === 0 && restored === original'));
  assert.doesNotMatch(step.run, /kptr|setcap|paranoid=(?:-1|0)|sudo (?:perf|node|actql)/u);
});

test('diagnostic setup shell and restoration trap parse without executing any command', () => {
  for (const name of ['Prepare the opt-in unprivileged flat CPU diagnostic',
    'Sample one unchanged installed Native workflow by actual approval PID']) {
    const step = workflow.jobs['native-approval'].steps.find(value => value.name === name);
    const result = spawnSync('/bin/bash', ['-n'], {input: step.run, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
  }
});
