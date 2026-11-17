import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {parse} from 'yaml';
import {inventory} from './verification-actions.mjs';
import {approvalPerfDsoMembers, approvalPerfSamples, approvalPerfCallChains, decodeApprovalPerf,
  saveApprovalPerfReport} from './test-native-approval-cpu-diagnostic.mjs';

const selected = [{template: 'deal-review-mock', pid: 101}, {template: 'churn-risk-mock', pid: 202}];
const workflow = parse(readFileSync(new URL('../.github/workflows/performance-matrix.yml', import.meta.url), 'utf8'));
const driver = readFileSync(new URL('./test-native-approval-cpu-diagnostic.mjs', import.meta.url), 'utf8');
const manifest = {platforms: {'linux-x64-gnu': {package: '@actql/cli-linux-x64-gnu'}},
  packages: [{name: '@actql/cli-linux-x64-gnu', files: [
    {path: 'bin/actql-native-client', bytes: 32, sha256: '1'.repeat(64)},
    {path: 'lib/libactql_crypto_component.so', bytes: 32, sha256: '2'.repeat(64)},
    {path: 'lib/libactql_sqlite_component.so', bytes: 32, sha256: '3'.repeat(64)},
  ]}]};

test('flat CPU attribution selects actual approval processes and removes paths and offsets', () => {
  const result = approvalPerfSamples([
    '    101     7f001234abcd _M0_original_journal+0x12 (/private/original/install/actql-native-client)',
    '    101     7f001234abce _M0_original_journal+0x80 (/private/original/install/actql-native-client)',
    '    202     7f001234abcf sqlite3_step (/private/original/install/actql-native-client)',
    '    303     7f001234abd0 private-unselected-payload (/private/foreign/state/key)',
  ].join('\n'), selected);
  assert.equal(result[0].samples, 2);
  assert.deepEqual(result[0].topSymbols, [{dsoRole: 'other', symbol: '_M0_original_journal', samples: 2}]);
  assert.deepEqual(result[1].topSymbols, [{dsoRole: 'other', symbol: 'sqlite3_step', samples: 1}]);
  assert.doesNotMatch(JSON.stringify(result), /private|payload|0x|foreign|7f001234/u);
});

test('unresolved CPU locations stay explicit without publishing addresses or arbitrary text', () => {
  const result = approvalPerfSamples('101 7f001234abcd 0xabcdef ([unknown])\n' +
    '202 0 [unknown] ([unknown])\n', selected);
  assert.deepEqual(result.map(value => [value.samples, value.unresolved]), [[1, 1], [1, 1]]);
  assert(result.every(value => value.topSymbols.length === 0));
  assert.doesNotMatch(JSON.stringify(result), /abcdef|unknown/u);
});

test('foreign lines cannot replace missing approval samples and malformed selected lines refuse', () => {
  assert(approvalPerfSamples('303 symbol (/not-selected)\n', selected).every(value => value.samples === 0));
  assert.throws(() => approvalPerfSamples('101 malformed-selected-sample\n', selected), /Invalid selected/u);
  for (const line of ['101 original_function (/original)', '101 not-hex original_function (/original)',
    '101 fffffffffffffffff original_function (/original)']) {
    assert.throws(() => approvalPerfSamples(line, selected), {code: 'NativeApprovalPerfSelectedLineInvalid'});
  }
  assert.throws(() => approvalPerfSamples('', [selected[0], {...selected[1], pid: 101}]), /Distinct actual/u);
  assert.throws(() => approvalPerfSamples('', [{...selected[0], pid: -1}, selected[1]]));
});

test('unrelated non-PID text is skipped explicitly and only fixed line-shape facts survive a selected refusal', () => {
  const counts = {};
  const result = approvalPerfSamples('renderer notice /not-for-report\n303 foreign (/elsewhere)\n' +
    '101 7f001234abcd original_function (/original)\n202 7f001234abce other_function (/original)\n', selected, counts);
  assert.deepEqual(result.map(value => value.samples), [1, 1]);
  assert.deepEqual(counts, {nonEmptyLines: 4, nonPidLines: 1, foreignPidLines: 1,
    selectedLines: 2, malformedSelectedLines: 0});
  const refused = {};
  assert.throws(() => approvalPerfSamples('101 malformed-selected-sample\n', selected, refused), error => {
    assert.equal(error.code, 'NativeApprovalPerfSelectedLineInvalid');
    assert.deepEqual(error.lineShape, {characters: 29, whitespaceFields: 2,
      hasHexIpToken: false, hasDsoEnvelope: false});
    assert.doesNotMatch(JSON.stringify(error.lineShape), /selected-sample|original|not-for-report/u);
    return true;
  });
  assert.equal(refused.malformedSelectedLines, 1);
});

test('CPU report has bounded top-symbol output and counts unavailable oversized symbols', () => {
  const lines = Array.from({length: 60}, (_, index) => `101 7f001234abcd function_${index} (/original)`);
  lines.push(`202 7f001234abce ${'x'.repeat(2049)} (/original)`);
  const result = approvalPerfSamples(lines.join('\n'), selected);
  assert.equal(result[0].samples, 60); assert.equal(result[0].topSymbols.length, 40);
  assert.equal(result[1].unresolved, 1);
});

test('verified release member names separate equal symbols into only safe DSO roles', () => {
  const members = approvalPerfDsoMembers(manifest);
  const result = approvalPerfSamples([
    '101 7f001234abcd allocate_locked (/not-for-report/bin/actql-native-client)',
    '101 7f001234abcd allocate_locked (libactql_crypto_component.so)',
    '101 7f001234abcd allocate_locked (/not-for-report/libactql_sqlite_component.so)',
    '101 7f001234abcd allocate_locked (/not-for-report/unlisted.so)',
    '101 7f001234abcd allocate_locked ([unknown])',
    '202 7f001234abcd other_symbol (actql-native-client)',
  ].join('\n'), selected, {}, members);
  assert.equal(result[0].samples, 5); assert.equal(result[0].resolvedSymbols, 1);
  assert.equal(result[0].resolvedDsoSymbolGroups, 5);
  assert.deepEqual(result[0].topSymbols.map(value => value.dsoRole).sort(),
    ['crypto-component', 'native-client', 'other', 'sqlite-component', 'unknown']);
  assert(result[0].topSymbols.every(value => value.samples === 1 && value.symbol === 'allocate_locked'));
  assert.doesNotMatch(JSON.stringify(result), /not-for-report|\.so|7f001234|\/bin\//u);
  const missing = structuredClone(manifest); missing.packages[0].files.pop();
  assert.throws(() => approvalPerfDsoMembers(missing), /member missing/u);
});

test('call chains retain only sampled symbols and roles for the actual approval processes', () => {
  const counts = {}, result = approvalPerfCallChains([
    '# perf header',
    '101',
    '  7f001234abcd __getpid+0x7 (/private/lib/libc.so.6)',
    '  7f001234abce current+0x12 (/private/lib/libactql_crypto_component.so)',
    '  7f001234abcf owner_boundary (/private/bin/actql-native-client)',
    '',
    '101',
    '  7f001234abcd __getpid+0x80 (/different/libc.so.6)',
    '  7f001234abce current+0x20 (/different/libactql_crypto_component.so)',
    '  7f001234abcf owner_boundary (/different/actql-native-client)',
    '',
    '303',
    '  invalid foreign private payload',
    '',
    '202',
    '  7f001234abcd getpid (libc.so.6)',
    '  7f001234abce sqlite_current (libactql_sqlite_component.so)',
    '',
  ].join('\n'), selected, counts, approvalPerfDsoMembers(manifest));
  assert.deepEqual(result.map(value => [value.samples, value.getpidSamples, value.unresolvedFrames]),
    [[2, 2, 0], [1, 1, 0]]);
  assert.deepEqual(result[0].getpidCallerChains, [{samples: 2, frames: [
    {symbol: '__getpid', dsoRole: 'other'},
    {symbol: 'current', dsoRole: 'crypto-component'},
    {symbol: 'owner_boundary', dsoRole: 'native-client'},
  ]}]);
  assert.deepEqual(counts, {selectedSamples: 3, foreignSamples: 1,
    nonSampleLines: 1, malformedSelectedLines: 0});
  assert.doesNotMatch(JSON.stringify(result), /private|different|0x|7f001234|\.so|payload/u);
});

test('missing or unresolved caller observations remain explicit without guessing a parent', () => {
  const result = approvalPerfCallChains([
    '101 7f001234abcd __getpid (libc.so.6)',
    '202',
    '  7f001234abcd getpid (libc.so.6)',
    '  7f001234abce 0xabcdef (/private/unknown)',
  ].join('\n'), selected);
  assert.equal(result[0].samples, 1); assert.equal(result[0].incompleteChains, 1);
  assert.equal(result[0].getpidMissingCallers, 1);
  assert.equal(result[1].unresolvedFrames, 1); assert.equal(result[1].getpidMissingCallers, 1);
  assert.deepEqual(result[1].topChains[0].frames[1], {symbol: '[unresolved]', dsoRole: 'unknown'});
  assert.doesNotMatch(JSON.stringify(result), /abcdef|private|0x|7f001234/u);
  assert(approvalPerfCallChains('303\n ffff foreign (/unselected)\n', selected)
    .every(value => value.samples === 0));
});

test('malformed selected chains and finite depth/volume bounds cannot publish raw input', () => {
  const counts = {};
  assert.throws(() => approvalPerfCallChains('101\n secret/private/data\n', selected, counts), error => {
    assert.equal(error.code, 'NativeApprovalPerfCallChainInvalid');
    assert.deepEqual(error.lineShape, {characters: 20, whitespaceFields: 1});
    assert.doesNotMatch(JSON.stringify(error), /secret|private|data/u);
    return true;
  });
  assert.equal(counts.malformedSelectedLines, 1);
  assert.throws(() => approvalPerfCallChains('101\n' + ' ff function (original)\n'.repeat(129), selected),
    {code: 'NativeApprovalPerfCallChainInvalid'});
  assert.throws(() => approvalPerfCallChains('x'.repeat(8 * 1024 ** 2 + 1), selected));
  const bounded = approvalPerfCallChains(Array.from({length: 60}, (_, index) =>
    `101\n ff getpid (libc)\n fe caller_${index} (original)\n\n`).join(''), selected);
  assert.equal(bounded[0].samples, 60); assert.equal(bounded[0].topChains.length, 40);
  assert.equal(bounded[0].getpidCallerChains.length, 40);
  const depth = approvalPerfCallChains('101\n' + ' ff function (original)\n'.repeat(128), selected);
  assert.equal(depth[0].depthLimitChains, 1);
});

test('same-job fallback finishes on the same raw data after a primary parser failure without a consumer replay', t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-perf-decode-test-'));
  t.after(() => rmSync(directory, {recursive: true}));
  const data = join(directory, 'perf.data'); writeFileSync(data, 'decoder fixture only');
  const calls = [], report = {conditions: [], approvals: []};
  const run = args => {
    calls.push(args); assert(existsSync(data)); assert.equal(args[0], 'script'); assert.equal(args[2], data);
    return {status: 0, error: undefined, stderr: '', stdout: !args.includes('-G')
      ? '101\n ff getpid (libc)\n fe caller (original)\n\n202\n ff getpid (libc)\n fe caller (original)\n'
      : args[4] === 'pid,ip,sym,dso' ? '101 malformed-primary\n' : '101 7f001234abcd\n202 7f001234abce\n'};
  };
  assert.throws(() => decodeApprovalPerf(run, data, selected, approvalPerfDsoMembers(manifest), report),
    {code: 'NativeApprovalPerfSelectedLineInvalid'});
  assert.equal(calls.length, 3); assert.equal(report.fallback.complete, true);
  assert.equal(report.callGraph.complete, false);
  assert(calls.slice(0, 2).every(args => args.includes('-G')));
  assert(!calls[2].includes('-G'));
  assert.equal(calls[2][calls[2].indexOf('--pid') + 1], '101,202');
  assert.deepEqual(report.fallback.approvals.map(value => value.samples), [1, 1]);
  assert.equal(report.sampleParsing.malformedSelectedLines, 1);
  assert(existsSync(data), 'The caller retains data through both decodes');
  assert.doesNotMatch(JSON.stringify(report), /malformed-primary|7f001234|decoder fixture/u);
});

test('same-data fallback agrees with primary counts and retains its own failure separately', () => {
  for (const mode of ['same', 'different', 'failed']) {
    const report = {conditions: [], approvals: []}, calls = [];
    const run = args => {
      calls.push(args); assert.equal(args[0], 'script');
      if (!args.includes('-G')) return {status: 0, stderr: '', stdout:
        '101\n ff getpid (libc)\n fe caller (original)\n\n202\n ff getpid (libc)\n fe caller (original)\n'};
      if (args[4] === 'pid,ip,sym,dso') return {status: 0, stderr: '', stdout:
        '101 7f001234abcd getpid (libc)\n202 7f001234abce getpid (libc)\n'};
      return {status: mode === 'failed' ? 1 : 0, stderr: '', stdout:
        '101 7f001234abcd\n202 7f001234abce\n' + (mode === 'different' ? '101 7f001234abcf\n' : '')};
    };
    decodeApprovalPerf(run, 'same-data', selected, approvalPerfDsoMembers(manifest), report);
    assert.equal(calls.length, 3); assert.equal(report.approvals.length, 2);
    if (mode === 'same') assert.deepEqual(report.conditions, []);
    else assert(report.conditions.length > 0, 'Fallback problems remain incomplete, not zero work');
    assert.equal(report.fallback.complete, mode !== 'failed');
    assert.equal(report.callGraph.complete, mode === 'same');
  }
});

test('caller decoding binds all samples while unresolved attribution stays a separate explicit limit', () => {
  for (const mode of ['failed', 'malformed', 'missing', 'different', 'unresolved', 'no-target', 'wrong-leaf', 'loss', 'partial-other']) {
    const report = {conditions: [], approvals: []}, calls = [];
    const run = args => {
      calls.push(args);
      if (args.includes('-G')) return {status: 0, stderr: '', stdout: args[4] === 'pid,ip'
        ? '101 ff\n202 fe\n' : `101 ff ${mode === 'no-target' ? 'other' : 'getpid'} (libc)\n202 fe getpid (libc)\n`};
      return {status: mode === 'failed' ? 1 : 0, stderr: mode === 'loss' ? 'lost samples' : '',
        stdout: mode === 'malformed' ? '101\n invalid caller\n' :
          mode === 'missing' ? '101 ff getpid (libc)\n202 fe getpid (libc)\n' :
            (mode === 'different' ? '101\n ff getpid (libc)\n fe caller (original)\n\n' : '') +
            `101\n ff ${mode === 'no-target' || mode === 'wrong-leaf' ? 'other' : 'getpid'} (libc)\n fe ${mode === 'wrong-leaf' ? 'getpid' : 'caller'} (original)\n\n` +
            `202\n ff getpid (libc)\n fe ${mode === 'unresolved' ? '[unknown]' : 'caller'} (original)\n` +
            (mode === 'partial-other' ? ' fd [unknown] ([unknown])\n' : '')};
    };
    decodeApprovalPerf(run, 'private-profiler-input/perf.data', selected, approvalPerfDsoMembers(manifest), report);
    assert.equal(calls.length, 3); assert.equal(report.fallback.complete, true);
    const complete = ['missing', 'unresolved', 'no-target', 'partial-other'].includes(mode);
    assert.equal(report.callGraph.complete, complete, mode);
    assert.equal(report.callGraph.getpidCallerAttributionComplete, mode === 'partial-other', mode);
    if (complete) assert.deepEqual(report.conditions, [], mode);
    else assert(report.conditions.length > 0, mode);
    if (mode === 'partial-other') assert.equal(report.callGraph.allFramesResolved, false);
    if (mode === 'missing') assert.equal(report.callGraph.unwindComplete, false);
    assert.doesNotMatch(JSON.stringify(report), /invalid caller|private-profiler-input|0x/u);
  }
});

test('private profiler data is removed only after its complete sanitized report was written', t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-perf-report-test-'));
  t.after(() => {if (existsSync(directory)) rmSync(directory, {recursive: true});});
  const data = join(directory, 'perf.data'); writeFileSync(data, 'decoder fixture only');
  const output = join(directory, 'report.json'); writeFileSync(output, 'original report');
  assert.throws(() => saveApprovalPerfReport(output, directory, {}), {code: 'EEXIST'});
  assert(existsSync(data), 'Report failure retains private data without re-executing the product');
  const separate = mkdtempSync(join(tmpdir(), 'actql-perf-sanitized-test-'));
  t.after(() => rmSync(separate, {recursive: true}));
  const destination = join(separate, 'report.json'), report = {primary: 'failed', fallback: {complete: true}};
  saveApprovalPerfReport(destination, directory, report);
  assert.deepEqual(JSON.parse(readFileSync(destination, 'utf8')), report);
  assert.equal(existsSync(directory), false);
});

test('CPU mode is explicit and false by default while all unrelated jobs exclude it', () => {
  const ci = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const actions = inventory({workflowText: JSON.stringify({jobs: {lint: ci.jobs.lint}}),
    packageText: readFileSync(new URL('../package.json', import.meta.url), 'utf8')}).actions;
  const unit = actions.find(action => action.origin === 'workflow' && action.job === 'lint' &&
    action.invocation?.kind === 'node-test' && action.invocation.argv.includes('scripts/native-approval-cpu-diagnostic.test.mjs'));
  assert(unit, 'CPU decoder regressions must run in the required lint job');
  assert.equal(unit.condition.step, null, 'Small decoder tests also run during Draft preparation');
  assert.equal(unit.condition.continueOnError, false);
  for (const event of ['workflow_dispatch', 'workflow_call']) {
    assert.deepEqual(workflow.on[event].inputs['native-approval-cpu-diagnostic'].default, false);
    assert.equal(workflow.on[event].inputs['native-approval-cpu-diagnostic'].type, 'boolean');
  }
  assert(workflow.jobs['native-approval'].if.includes("inputs['native-approval-cpu-diagnostic']"));
  for (const [name, job] of Object.entries(workflow.jobs)) {
    if (name === 'node-wait-cpu') assert(job.if.includes("inputs['node-wait-cpu-diagnostic'] == true"));
    else if (name !== 'native-approval') assert(job.if.includes("!inputs['native-approval-cpu-diagnostic']"), name);
  }
});

test('CPU diagnosis selects a distinct producer path while formal collection stays gated', () => {
  const steps = workflow.jobs['native-approval'].steps;
  const validation = steps.find(step => step.name === 'Validate the original normal Native artifact and producer job');
  assert(validation.run.includes('inspect-native-approval-cpu-producer'));
  assert(validation.run.includes('inspect-native-approval-producer'));
  const download = steps.find(step => step.name === 'Reuse the digest-verified original artifact for CPU diagnosis only');
  assert(download.if.includes("inputs['native-approval-cpu-diagnostic']"));
  const formal = steps.find(step => step.name === 'Measure thirty complete approvals for each original Native template');
  assert(formal.if.includes("!inputs['native-approval-cpu-diagnostic']"));
  assert(formal.run.includes('scripts/test-native-approval-performance.mjs'));
  for (const step of [validation, download, steps.find(value => value.name === 'Bind the original Native build source before collection')]) {
    const result = spawnSync('/bin/bash', ['-n'], {input: step.run, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
  }
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
  assert(driver.includes("'-F', 'pid,ip,sym,dso'"));
  assert(driver.includes("'--call-graph', 'dwarf,8192'"));
  assert.doesNotMatch(driver, /--user-regs|--user-stack|sysctl|setcap|sudo/u);
  assert.equal([...driver.matchAll(/join\(root, 'scripts\/test-native-cli-mock-install\.mjs'\)/gu)].length, 1);
  assert(driver.includes('approvalCallCounts(approval).pid'));
  assert(driver.includes("'--measure-approval-resources'"));
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
