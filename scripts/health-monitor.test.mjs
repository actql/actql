import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, writeFile, mkdir, readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {compareReports, finishReport, markdown, summarize, exitStatus, digest, measurementProfile} from './health-monitor-report.mjs';
import {parseArguments, requiredQuickMetrics, missingReleaseInputs, recordGuardExit} from './health-monitor.mjs';
import {packDistributionPackages} from './measure-distribution-artifacts.mjs';
import {formalCollectorVerdict} from './health-monitor-release.mjs';
import {quickNodeMetrics} from './health-monitor-adapters.mjs';
import {nodeWarmSmallQueryFixtures} from './benchmark-node-operations.mjs';

const policy = JSON.parse(await readFile(new URL('../benchmarks/health/config.json', import.meta.url)));
const samples = (ms, count = 10) => Array.from({length: count}, (_, iteration) => ({iteration,
  wallNs: ms * 1e6, cpuUserUs: 1, cpuSystemUs: 1, verified: true, completed: true}));
function fixture() {
  const report = {format: 'actql-health/0.1', mode: 'quick', source: {sha: 'a'.repeat(40), dirty: false},
    environment: {platform: 'linux', architecture: 'x64', osRelease: 'test-os', cpuModel: 'unit CPU', logicalCpus: 2,
      node: 'test-node', nodeExecutableSha256: '0'.repeat(64), python: 'test-python', moon: 'test-moon',
      toolchainSha256: '1'.repeat(64), buildSettings: {profile: 'release', load: 'isolated'}},
    methodologySha256: '2'.repeat(64), baseline: {id: 'synthetic-unit-only', reviewed: true, reason: 'test vector, never a product baseline'},
    artifacts: [{name: 'test', sourceSha: 'a'.repeat(40), sha256: '3'.repeat(64)}], errors: [],
    metrics: []};
  report.metrics = measurementProfile('quick').map(row => ({...row, evidence: 'synthetic unit only',
    fixtureSha256: '4'.repeat(64), ...(row.kind === 'latency' ? {samples: samples(10, row.requiredSamples)} : {value: 1000})}));
  report.sourceAfter = structuredClone(report.source); report.environmentAfter = structuredClone(report.environment);
  report.installedPayloadsUnchanged = true; return report;
}
test('size thresholds retain target, absolute and relative growth', () => {
  for (const [growth, expected] of [[0.09, 'pass'], [0.10, 'warning'], [0.25, 'regression']]) {
    const base = fixture(), current = fixture(); current.metrics[0].value = 1000 * (1 + growth);
    const result = compareReports(base, current, policy);
    assert.equal(result.status, expected); assert.equal(result.verdicts[0].target, '@actql/client-wire');
    assert.equal(result.verdicts[0].absoluteDelta, growth * 1000);
  }
});
test('Browser gzip has its own 5/15 percent thresholds', () => {
  const base = fixture(), current = fixture();
  const metric = current.metrics.find(row => row.id === 'browser-gzip');
  metric.value = 1050; assert.equal(compareReports(base, current, policy).status, 'warning');
  metric.value = 1150; assert.equal(compareReports(base, current, policy).status, 'regression');
});
test('Quick latency requires both relative and absolute warning conditions; warning exits zero', () => {
  for (const [cold, before, after, expected] of [[false, 1, 2, 'pass'], [false, 10, 13, 'warning'],
    [true, 10, 40, 'pass'], [true, 100, 150, 'warning']]) {
    const base = fixture(), current = fixture();
    for (const [report, ms] of [[base, before], [current, after]]) {
      const metric = report.metrics.find(row => row.id === (cold ? 'cold-host-initialization' : 'warm-select'));
      metric.samples = samples(ms, metric.requiredSamples);
    }
    const comparison = compareReports(base, current, policy); assert.equal(comparison.status, expected);
    current.comparison = comparison; assert.equal(finishReport(current).exitCode, 0);
  }
});
test('RSS 20 percent is a warning, not a CI failure', () => {
  const base = fixture(), current = fixture();
  current.metrics.find(row => row.id === 'peak-rss').value = 1200;
  assert.equal(compareReports(base, current, policy).status, 'warning');
  assert.equal(exitStatus('warning'), 0);
});
test('CPU, toolchain, fixture, build or dirty mismatch refuses comparison', () => {
  for (const mutate of [r => r.environment.cpuModel = 'other CPU', r => r.environment.node = 'other version',
    r => r.environment.buildSettings.profile = 'debug', r => r.methodologySha256 = 'different', r => r.source.dirty = true,
    r => r.artifacts[0].sourceSha = 'b'.repeat(40), r => r.environment.moon = null]) {
    const current = fixture(); mutate(current);
    const result = compareReports(fixture(), current, policy);
    assert.equal(result.status, 'incomplete'); assert.equal(result.comparable, false);
  }
});
test('different source SHAs compare when each artifact is bound to its actual source', () => {
  const current = fixture(); current.source.sha = current.artifacts[0].sourceSha = 'b'.repeat(40);
  current.sourceAfter = structuredClone(current.source);
  assert.equal(compareReports(fixture(), current, policy).comparable, true);
});
test('missing samples, required observations and unreviewed baselines cannot pass', () => {
  const report = fixture(); report.metrics = requiredQuickMetrics();
  assert.equal(finishReport(report).status, 'incomplete'); assert.equal(report.exitCode, 2);
  const base = fixture(); delete base.baseline;
  assert.equal(compareReports(base, fixture(), policy).comparable, false);
  report.metrics = fixture().metrics;
  const metric = report.metrics.find(row => row.id === 'warm-select'); metric.samples = samples(1, 9);
  assert.equal(finishReport(report).status, 'incomplete');
  metric.samples[0].verified = false; assert.equal(finishReport(report).status, 'error');
});
test('first run has no invented baseline or regression-free claim; optional platform missing is explicit', () => {
  const report = fixture(); report.comparison = {available: false};
  report.metrics.push({id: 'native', target: 'native', kind: 'size', required: false, status: 'incomplete', reason: 'unmeasured'});
  assert.equal(finishReport(report).exitCode, 0);
  assert.match(markdown(report), /Comparison unavailable/); assert.match(markdown(report), /unmeasured/);
  assert.equal(report.formalAcceptance, false);
});
test('summary keeps all samples/range and withholds small-sample formal p95', () => {
  const rows = [1, 2, 3, 4, 20].map(ms => samples(ms, 1)[0]);
  const summary = summarize(rows, 30);
  assert.equal(summary.medianMs, 3); assert.equal(summary.p95Ms, null);
  assert.deepEqual(summary.referenceRangeMs, [1, 20]); assert.equal(rows.length, 5);
});
test('normal pack adapter uses actual JSON filenames/versions, not a development filename', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-pack-unit-'));
  const names = ['client-wire', 'sdk', 'node', 'run-host-core', 'local-node']; let calls = 0;
  const packages = await packDistributionPackages({repository: root, destination: root,
    run: async (cmd, args, cwd) => {
      const name = names[calls++], file = `actual-${name}-1.2.3.tgz`;
      assert.equal(cmd, 'npm'); assert.equal(args[0], 'pack'); assert.equal(cwd, join(root, 'packages', name));
      await writeFile(join(root, file), 'unit');
      return {stdout: 'lifecycle output\n' + JSON.stringify([{name: '@actql/' + name, version: '1.2.3', filename: file, size: 4}])};
    }});
  assert.equal(calls, 5); assert(packages.every(row => row.file.endsWith('1.2.3.tgz') && row.sha256 === digest('unit')));
});
test('Compare runs offline with no git/npm/moon executables and never changes its inputs', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-compare-unit-'));
  const base = join(root, 'base.json'), current = join(root, 'current.json'), output = join(root, 'out');
  const before = JSON.stringify(fixture()); await writeFile(base, before); await writeFile(current, before);
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'compare', '--base', base, '--current', current, '--output', output], {env: {...process.env, PATH: '/nonexistent'}, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr); assert.equal(await readFile(base, 'utf8'), before);
  assert.equal(await readFile(current, 'utf8'), before);
  assert.deepEqual((await readdir(output)).sort(), ['report.json', 'summary.md']);
});
test('source/config and gated workflow declare exact Quick 10/5 and fail closed', async () => {
  assert.deepEqual(policy.quick, {warmSamples: 10, coldSamples: 5});
  assert.deepEqual(policy.release, {warmSamples: 100, coldSamples: 30});
  const workflow = await readFile(new URL('../.github/workflows/health-monitor.yml', import.meta.url), 'utf8');
  assert.match(workflow, /ACTQL_MAIN_CI_ENABLED == 'true'/);
  assert.match(workflow, /repository.visibility == 'public'/);
  assert.match(workflow, /toJSON\(github.event.repository.private\) == 'false'/);
  assert.match(workflow, /retention-days: 30/); assert.match(workflow, /npm run health:quick/);
  assert.doesNotMatch(workflow, /ACTQL_HEALTH_MONITOR_ENABLED/);
  const guard = "vars.ACTQL_MAIN_CI_ENABLED == 'true' && github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false'";
  for (const job of Object.values(parse(workflow).jobs)) {
    assert(job.if.startsWith('${{ ' + guard));
    for (const [enabled, visibility, privateFlag, expected] of [
      [undefined, 'public', false, false], ['false', 'public', false, false],
      ['true', undefined, false, false], ['true', 'private', true, false],
      ['true', 'public', undefined, false], ['true', 'public', null, false],
      ['true', 'public', 'false', false], ['true', 'public', false, true]]) {
      assert.equal(runInNewContext(guard, {vars: {ACTQL_MAIN_CI_ENABLED: enabled},
        github: {event: {repository: {visibility, private: privateFlag}}}, toJSON: JSON.stringify}), expected);
    }
  }
});
test('invalid flags and missing Release fixtures are explicit rather than a successful stub', () => {
  assert.throws(() => parseArguments(['compare', '--base', 'x']));
  assert.throws(() => parseArguments(['quick', '--cap', '0']));
  assert.equal(parseArguments(['release']).mode, 'release');
});
test('empty reports and missing before/after evidence cannot qualify a baseline', () => {
  const current = fixture(); current.metrics = [];
  assert.equal(finishReport(current).status, 'incomplete');
  assert.equal(compareReports(fixture(), current, policy).comparable, false);
  const base = fixture(); delete base.sourceAfter;
  assert.equal(compareReports(base, fixture(), policy).comparable, false);
});
test('CLI parse failure still saves JSON/Markdown and preserves an existing output', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-error-unit-'));
  const output = join(root, 'existing'); await mkdir(output); await writeFile(join(output, 'sentinel'), 'keep');
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'compare', '--base', join(root, 'absent'), '--current', join(root, 'absent'), '--output', output], {encoding: 'utf8'});
  assert.equal(result.status, 3); assert.equal(await readFile(join(output, 'sentinel'), 'utf8'), 'keep');
  const path = result.stderr.match(/Report: (.+)/u)?.[1]; assert.ok(path, result.stderr);
  const report = JSON.parse(await readFile(join(path, 'report.json')));
  assert.equal(report.status, 'error'); assert.ok(report.errors[0].message);
  assert.match(await readFile(join(path, 'summary.md'), 'utf8'), /Error \(runner\)/);
});
test('original failed formal observations are errors; incomplete assessments stay incomplete', () => {
  assert.equal(formalCollectorVerdict({firstFailure: {message: 'original arithmetic refusal'}, latency: []}).status, 'error');
  assert.equal(formalCollectorVerdict({latency: [{samples: [{verified: false}]}]}).status, 'error');
  assert.equal(formalCollectorVerdict({latency: [], assessments: []}).status, 'incomplete');
  assert.equal(formalCollectorVerdict({latency: [{samples: samples(1)}]}).status, 'incomplete');
  assert.equal(formalCollectorVerdict({latency: [{samples: samples(1)}], assessments: [{status: 'failed'}]}).status, 'regression');
});
test('original failed warm samples are retained without a cold retry or new public operation', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-health-failed-unit-')), emitted = [];
  const original = new Error('original synthetic unit failure'); let commands = 0;
  await assert.rejects(quickNodeMetrics({root, prepared: {consumer: 'unit-only'}, counts: {warmSamples: 10, coldSamples: 5},
    command: async () => {
      commands++;
      await writeFile(join(root, 'warm-observation.json'), JSON.stringify({cleanup: {closed: true},
        metrics: [{id: 'warm-select', samples: [{...samples(1, 1)[0], verified: false, completed: false, error: 'original'}]}]}));
      throw original;
    }, onMetric: async row => emitted.push(row)}), error => error === original);
  assert.equal(commands, 1); assert.equal(emitted[0].samples[0].error, 'original');
  assert.equal(emitted[0].samples[0].verified, false);
});
test('Release missing mandatory platform inputs exits incomplete before any Runtime build', async () => {
  assert.equal(missingReleaseInputs({}).length, 7);
  const root = await mkdtemp(join(tmpdir(), 'actql-health-release-unit-')), output = join(root, 'run');
  const result = spawnSync(process.execPath, [new URL('./health-monitor.mjs', import.meta.url).pathname,
    'release', '--output', output], {encoding: 'utf8'});
  assert.equal(result.status, 2, result.stderr);
  const report = JSON.parse(await readFile(join(output, 'report.json')));
  assert.equal(report.status, 'incomplete');
  assert.match(report.metrics.find(row => row.id === 'required-release-inputs').reason, /no build or formal workload started/);
  assert.equal(report.artifacts.length, 0); assert.equal(report.guardExitCode, undefined);
});
test('original guard exit is recorded for both normal success and admission refusal', () => {
  const success = finishReport(fixture()); recordGuardExit(success, 0);
  assert.equal(success.guardExitCode, 0); assert.equal(success.status, 'pass');
  const refused = finishReport(fixture()); recordGuardExit(refused, 1);
  assert.equal(refused.guardExitCode, 1); assert.equal(refused.status, 'error');
  assert.match(refused.errors[0].message, /Original guard exited 1/);
});
test('collector errors disqualify a reviewed baseline even with complete measurements', () => {
  const base = fixture(); base.errors.push({target: 'collector', message: 'original cleanup failure'});
  finishReport(base); assert.equal(base.status, 'error');
  const result = compareReports(base, fixture(), policy);
  assert.equal(result.comparable, false); assert.match(result.reasons.join(';'), /collector\/guard/);
});
test('fixed Quick inventory cannot lose Aggregate or mark all required observations optional', () => {
  const current = fixture(); current.metrics = current.metrics.filter(row => row.id !== 'warm-aggregate');
  for (const row of current.metrics) row.required = false;
  assert.equal(finishReport(current).status, 'incomplete');
  assert.equal(compareReports(fixture(), current, policy).comparable, false);
});
test('saved reports cannot reduce fixed ten warm or five cold samples to one', () => {
  for (const id of ['warm-select', 'cold-process-first-result-close']) {
    const current = fixture(), metric = current.metrics.find(row => row.id === id);
    metric.samples = metric.samples.slice(0, 1); metric.requiredSamples = 1; metric.required = false;
    assert.equal(finishReport(current).status, 'incomplete');
    assert.equal(compareReports(fixture(), current, policy).comparable, false);
  }
});
test('build and artifact-reuse reference timing never gates compatible size or runtime metrics', () => {
  const base = fixture(), current = fixture();
  base.metrics.push({id: 'build-packaging', target: 'distribution', kind: 'reference', value: 100, unit: 'ms',
    required: true, evidence: 'unit', fixtureSha256: digest('normal prepack')});
  current.metrics.push({...base.metrics.at(-1), value: 1, fixtureSha256: digest('verified artifact reuse')});
  const result = compareReports(base, current, policy);
  assert.equal(result.status, 'pass'); assert.equal(result.comparable, true);
  assert(!result.verdicts.some(row => row.metric === 'build-packaging'));
});
test('saved size regression preserves its expected guard exit and remains comparable on round trip', () => {
  const base = fixture(), current = fixture(); current.metrics[0].value = 1250;
  current.comparison = compareReports(base, current, policy); finishReport(current); recordGuardExit(current, 1);
  const restored = JSON.parse(JSON.stringify(current));
  assert.equal(restored.status, 'regression'); assert.equal(restored.errors.length, 0);
  const result = compareReports(base, restored, policy);
  assert.equal(result.comparable, true); assert.equal(result.status, 'regression');
  const mismatch = finishReport(fixture()); mismatch.guardExitCode = 1;
  assert.equal(compareReports(base, mismatch, policy).comparable, false);
});
test('ordinary Python JOIN/Aggregate fixtures exactly match the existing Node literal oracles', () => {
  const script = new URL('./benchmark-ordinary-processes.py', import.meta.url).pathname;
  const result = spawnSync('python3', ['-I', '-B', '-c',
    'import json,runpy,sys;print(json.dumps(runpy.run_path(sys.argv[1])["SMALL_QUERIES"]))', script], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  const fixtures = JSON.parse(result.stdout);
  for (const operation of ['warm-join', 'warm-decimal-sum']) {
    assert.deepEqual(fixtures[operation], nodeWarmSmallQueryFixtures.find(row => row.operation === operation));
  }
});
