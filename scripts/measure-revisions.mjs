// Cross-revision A-only execution of the existing mandatory release matrix.
// Supplemental expression profiles share the existing clocks and assertions.
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, realpathSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { platform, release, arch, cpus } from 'node:os';
import { performance } from 'node:perf_hooks';
import { checkedSample, checkedPreparedSample, peakRssBytes } from './layout-measurement-support.mjs';
import { regressionPolicy, revisionCells, supplementalRevisionCells, diagnosticRevisionCells, revisionPairs, regressionMetric, revisionGate, revisionMustStop } from './revision-regression-support.mjs';
import { checkedProfileOverlay } from './revision-profile-overlay.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [before, after, mode] = process.argv.slice(2);
if (!before || !after || !['--smoke', '--matrix', '--diagnostic'].includes(mode) || process.argv.length !== 5) {
  throw new Error('Usage: measure-revisions.mjs BASELINE_WORKTREE CANDIDATE_WORKTREE --smoke|--matrix|--diagnostic');
}
const smoke = mode === '--smoke';
const diagnostic = mode === '--diagnostic';
const paths = { baseline: realpathSync(before), candidate: realpathSync(after) };
if (paths.baseline === paths.candidate) throw new Error('Distinct revision worktrees required');
const moonHome = process.env.MOON_HOME;
if (!moonHome || !['darwin', 'linux'].includes(platform())) throw new Error('Pinned MOON_HOME and supported time/RSS host required');
const env = { ...process.env, PATH: `${moonHome}/bin:${process.env.PATH}` };
for (const name of Object.keys(env)) if (name.startsWith('ACTQL_LAYOUT_')) delete env[name];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const git = (path, args) => execFileSync('git', ['-C', path, ...args], { encoding: 'utf8' }).trim();
const run = (command, args, extra = {}) => {
  const r = spawnSync(command, args, { env, encoding: 'utf8', timeout: 300000, maxBuffer: 32 * 1024 * 1024, ...extra });
  if (r.error || r.status !== 0) throw new Error(`${command}: ${r.error ?? r.status}\n${r.stderr}\n${r.stdout}`);
  return r;
};
const manifestFile = 'benchmarks/local-relation/columnar-experiment.json';
const manifestBytes = readFileSync(resolve(root, manifestFile));
const manifest = JSON.parse(manifestBytes);
const toolchainBytes = readFileSync(resolve(root, 'toolchain.json'));
const compiler = run(`${moonHome}/bin/moonc`, ['-v']).stdout.trim();
if (!compiler.includes(JSON.parse(toolchainBytes).version)) throw new Error('Unpinned compiler');
const sources = {};
const fixtures = git(paths.baseline, ['ls-files', 'src/execution_relation']).split('\n')
  .filter(f => /\/(layout_.*_wbtest|sequence_(profile|scale)_wbtest)\.mbt$/.test(f));
for (const [label, path] of Object.entries(paths)) {
  const status = git(path, ['status', '--porcelain']);
  // Trimming removes the initial space on the first porcelain record only.
  const changed = git(path, ['diff', '--name-only', 'HEAD']).split('\n').filter(Boolean);
  const untracked = git(path, ['ls-files', '--others', '--exclude-standard']).split('\n').filter(Boolean);
  const overlay = checkedProfileOverlay({ label, changed, untracked, fixtures,
    read: f => readFileSync(resolve(path, f), 'utf8') });
  if (!readFileSync(resolve(path, manifestFile)).equals(manifestBytes) ||
      !readFileSync(resolve(path, 'toolchain.json')).equals(toolchainBytes)) throw new Error(`${label}: matrix/toolchain mismatch`);
  sources[label] = { path, commit: git(path, ['rev-parse', 'HEAD']), tree: git(path, ['rev-parse', 'HEAD^{tree}']),
    status, overlay: Object.fromEntries(overlay.map(f => [f, hash(readFileSync(resolve(path, f)))])) };
}
if (sources.baseline.commit === sources.candidate.commit) throw new Error('Comparison requires different revisions');
// Both sides must use identical fixtures and profiling infrastructure. Only
// product source may differ, apart from the exact baseline-only field-reading
// shim checked above. All shared clocks, fixtures and assertions remain equal.
const fixtureHashes = {};
for (const f of fixtures) {
  const bytes = readFileSync(resolve(paths.baseline, f));
  if (!bytes.equals(readFileSync(resolve(paths.candidate, f)))) throw new Error(`Unequal shared fixture: ${f}`);
  fixtureHashes[f] = hash(bytes);
}
const out = resolve(root, '_build/revision-measurements', `${Date.now()}-${process.pid}`);
mkdirSync(out, { recursive: true });
const report = {
  status: 'running', scope: diagnostic ? 'bounded representative diagnostic; not full-matrix gate' : smoke ? 'cross-revision smoke only' : 'mandatory and supplemental A-only historical matrix',
  whole_task_complete: false, started_at: new Date().toISOString(), sources, fixtureHashes,
  policy: regressionPolicy, manifest_sha256: hash(manifestBytes), compiler,
  runner_hashes: Object.fromEntries(['measure-revisions.mjs', 'revision-profile-overlay.mjs', 'revision-regression-support.mjs', 'layout-measurement-support.mjs', 'layout-statistics.mjs']
    .map(f => [f, hash(readFileSync(resolve(root, 'scripts', f)))])),
  host: { platform: platform(), release: release(), arch: arch(), cpu: cpus()[0]?.model, node: process.version },
  units: { time: 'microseconds', rss: 'whole-process peak bytes including warmup/observation/cleanup', build: 'excluded' },
  artifacts: {}, samples: [], decisions: [],
};
const save = () => writeFileSync(resolve(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
const testFile = 'sequence_profile_wbtest.mbt';
const testArgs = JSON.stringify({ package: 'actql/actql/execution_relation', file_and_index: [[testFile, [{ start: 0, end: 1 }]]] });
const assertSourcesUnchanged = () => {
  for (const [label, path] of Object.entries(paths)) {
    if (git(path, ['rev-parse', 'HEAD']) !== sources[label].commit || git(path, ['status', '--porcelain']) !== sources[label].status) {
      throw new Error(`${label}: source changed during measurement`);
    }
    for (const [f, digest] of Object.entries(fixtureHashes)) {
      if (hash(readFileSync(resolve(path, f))) !== digest) throw new Error(`${label}: fixture mutated during measurement`);
    }
  }
};
save();
try {
  for (const target of diagnostic ? ['native', 'js'] : ['native', 'js', 'wasm']) {
    for (const [revision, path] of Object.entries(paths)) {
      const built = run(`${moonHome}/bin/moon`, ['test', '--target', target, `src/execution_relation/${testFile}`, '--release', '--build-only', '--deny-warn'], { cwd: path });
      writeFileSync(resolve(out, `${revision}-${target}-build.log`), built.stdout + built.stderr);
      const extension = target === 'native' ? 'exe' : target;
      const artifact = resolve(path, `_build/${target}/release/test/execution_relation/execution_relation.whitebox_test.${extension}`);
      report.artifacts[`${revision}/${target}`] = { path: artifact, sha256: hash(readFileSync(artifact)),
        runtime: target === 'wasm' ? run(`${moonHome}/bin/moonrun`, ['--version']).stdout.trim() : target === 'js' ? process.version : 'native' };
      save();
    }
  }
  const measure = (cell, from, until) => {
    assertSourcesUnchanged();
    for (const scheduled of revisionPairs(cell, from, until)) {
      const { revision, target } = scheduled;
      const artifact = report.artifacts[`${revision}/${target}`];
      if (hash(readFileSync(artifact.path)) !== artifact.sha256) throw new Error('Binary changed');
      const command = target === 'native' ? artifact.path : target === 'js' ? process.execPath : `${moonHome}/bin/moonrun`;
      const args = target === 'native' ? [`${testFile}:0-1`] : target === 'js' ? [artifact.path, testArgs] : [artifact.path, '--test-args', testArgs];
      const sampleEnv = { ...env, ACTQL_LAYOUT_CANDIDATE: 'A',
        [cell.family === 'legacy' ? 'ACTQL_LAYOUT_CASE' : 'ACTQL_LAYOUT_ADDITIONAL_CASE']: String(cell.case_index) };
      if (cell.mode === 'prepared') sampleEnv.ACTQL_LAYOUT_PREPARED = '1';
      const started = performance.now();
      const r = run('/usr/bin/time', [platform() === 'darwin' ? '-l' : '-v', command, ...args], { cwd: paths[revision], env: sampleEnv });
      const wall = performance.now() - started;
      const raw = `${report.samples.length}-${revision}-${target}`;
      writeFileSync(resolve(out, `${raw}.stdout`), r.stdout);
      writeFileSync(resolve(out, `${raw}.stderr`), r.stderr);
      const sample = (cell.mode === 'prepared' ? checkedPreparedSample : checkedSample)(r.stdout, scheduled);
      report.samples.push({ ...scheduled, measurement: sample, process_wall_ms: wall,
        peak_rss_bytes: peakRssBytes(r.stderr, platform()), raw, captured_at: new Date().toISOString() });
      save();
      process.stderr.write(`${cell.id} pair=${scheduled.repeat} ${revision}: PASS\n`);
    }
  };
  const summarize = cell => ['time', 'rss'].map(metric => {
    const data = revision => report.samples.filter(s => s.id === cell.id && s.revision === revision)
      .sort((a, b) => a.repeat - b.repeat).map(s => metric === 'rss' ? s.peak_rss_bytes
        : cell.mode === 'prepared' ? s.measurement.operation_us : s.measurement.end_to_end_us);
    return regressionMetric(data('baseline'), data('candidate'), metric);
  });
  const cells = diagnostic ? diagnosticRevisionCells(manifest) : [...revisionCells(manifest), ...supplementalRevisionCells()].filter(c => !smoke ||
    c.family === 'supplemental' || (c.family === 'legacy' && c.case_index === (c.target === 'native' ? 0 : 1)));
  for (const cell of cells) {
    measure(cell, 0, smoke ? 1 : regressionPolicy.initialPairs);
    if (smoke) continue;
    let metrics = summarize(cell);
    const screening = metrics;
    if (!diagnostic && metrics.some(m => m.decision === 'extend')) {
      measure(cell, regressionPolicy.initialPairs, regressionPolicy.maximumPairs);
      metrics = summarize(cell);
    }
    report.decisions.push({ id: cell.id, screening, metrics });
    save();
    if (!diagnostic && revisionMustStop(metrics)) {
      report.status = 'stopped';
      report.matrix_gate = 'not_evaluated';
      report.stop_reason = `Twenty-one pairs remain inconclusive: ${cell.id}`;
      save();
      break;
    }
  }
  assertSourcesUnchanged();
  if (report.status !== 'stopped') {
    report.status = 'complete';
    report.matrix_gate = smoke || diagnostic ? 'not_evaluated' : revisionGate(report.decisions);
  }
  report.finished_at = new Date().toISOString();
  save();
  process.stdout.write(`Report: ${out}/report.json\n`);
} catch (error) {
  report.status = 'failed';
  report.error = String(error);
  save();
  throw error;
}
