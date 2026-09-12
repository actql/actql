// Release harness for the fixed layout experiment. Outputs go to ignored _build,
// never /tmp. --smoke validates A/B/C wiring, not adoption.
import { spawnSync, execFileSync } from 'node:child_process';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cpus, platform, release, arch } from 'node:os';
import { performance } from 'node:perf_hooks';
import { legacySchedule, additionalSchedule, peakRssBytes, checkedSample } from './layout-measurement-support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
const mode = process.argv[2];
const smoke = ['--smoke', '--additional-smoke'].includes(mode);
const additional = ['--additional', '--additional-smoke'].includes(mode);
if (process.argv.length !== 3 || !['--smoke', '--legacy', '--additional', '--additional-smoke'].includes(mode)) {
  throw new Error('Use --smoke, --legacy, --additional-smoke or --additional; none is the complete adoption matrix');
}
if (!['darwin', 'linux'].includes(platform())) throw new Error('RSS requires macOS or GNU time on Linux');
const manifestPath = 'benchmarks/local-relation/columnar-experiment.json';
const manifest = JSON.parse(readFileSync(manifestPath));
const toolchain = JSON.parse(readFileSync('toolchain.json'));
const moonHome = process.env.MOON_HOME;
if (!moonHome) throw new Error('Set MOON_HOME to the pinned toolchain directory');
const env = { ...process.env, PATH: `${moonHome}/bin:${process.env.PATH}` };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const git = args => execFileSync('git', args, { encoding: 'utf8' }).trim();
const sourceFiles = git(['ls-files', '--cached', '--others', '--exclude-standard',
  'src', 'scripts', 'spec', 'vendor', 'moon.mod', 'moon.mod.json', 'moon.lock', 'toolchain.json', manifestPath]).split('\n').sort();
const tree = createHash('sha256');
for (const file of sourceFiles) tree.update(file + '\0').update(readFileSync(file));
const outputDirectory = resolve('_build/layout-measurements');
mkdirSync(outputDirectory, { recursive: true });
const run = (command, args, extra = {}) => {
  const result = spawnSync(command, args, {
    env, encoding: 'utf8', timeout: 300000, maxBuffer: 16 * 1024 * 1024, ...extra,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${command} failed: ${result.error ?? result.stderr}\n${result.stdout}`);
  }
  return result;
};
const version = run(`${moonHome}/bin/moonc`, ['-v']).stdout.trim();
if (!version.includes(toolchain.version)) throw new Error(`Unpinned compiler: ${version}`);
const report = {
  scope: additional ? 'twelve fixed additional cases; producer, prepared repeats and complete accounting pending'
    : smoke ? 'three-layout-harness-smoke' : 'fixed-legacy-subset; additional cases and complete accounting pending',
  status: 'running', adoption_eligible: false, started_at: new Date().toISOString(),
  baseline_commit: manifest.row_baseline_commit,
  source_commit: git(['rev-parse', 'HEAD']),
  working_tree_status: git(['status', '--porcelain']),
  source_tree_sha256: tree.digest('hex'),
  script_sha256: hash(readFileSync('scripts/measure-layouts.mjs')),
  manifest_sha256: hash(readFileSync(manifestPath)),
  toolchain, compiler: version,
  host: { platform: platform(), release: release(), arch: arch(), cpu: cpus()[0]?.model },
  warmups: 1, measured_repetitions: smoke ? 1 : manifest.sampling.measured_repetitions,
  process_wall_scope: 'runtime startup, warmup, measured invocation and test reporting; excludes build',
  phase_scope: 'one measured invocation; clocks report microseconds; phase 3 includes invocation input checks and physical import',
  rss_scope: 'whole fresh process peak including startup, warmup, measured invocation, observation and cleanup; never subtract phase peaks',
  targets: [],
};
const reportPath = resolve(outputDirectory, additional
  ? smoke ? 'additional-smoke.json' : 'additional-samples.json'
  : smoke ? 'harness-smoke.json' : 'legacy-samples.json');
const save = () => writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n');
save();
const testArgs = JSON.stringify({ package: 'actql/actql/execution_relation',
  file_and_index: [['sequence_profile_wbtest.mbt', [{ start: 0, end: 1 }]]] });
for (const target of ['native', 'js', 'wasm']) {
  const build = run(`${moonHome}/bin/moon`, ['test', '--target', target,
    'src/execution_relation/sequence_profile_wbtest.mbt', '--release', '--build-only', '--deny-warn']);
  writeFileSync(resolve(outputDirectory, `${target}-build.log`), build.stdout + build.stderr);
  const extension = target === 'native' ? 'exe' : target;
  const artifact = resolve(`_build/${target}/release/test/execution_relation/execution_relation.whitebox_test.${extension}`);
  const command = target === 'native' ? artifact : target === 'js' ? process.execPath : `${moonHome}/bin/moonrun`;
  const args = target === 'native' ? ['sequence_profile_wbtest.mbt:0-1']
    : target === 'js' ? [artifact, testArgs] : [artifact, '--test-args', testArgs];
  const samples = [];
  report.targets.push({ target, artifact_sha256: hash(readFileSync(artifact)),
    runtime: target === 'js' ? process.version : target === 'wasm'
      ? run(`${moonHome}/bin/moonrun`, ['--version']).stdout.trim() : 'native', samples });
  for (const scheduled of (additional ? additionalSchedule : legacySchedule)(manifest, target, smoke)) {
    const { candidate, case_index, repeat } = scheduled;
    const started = performance.now();
    const sampleEnv = { ...env, ACTQL_LAYOUT_CANDIDATE: candidate };
    delete sampleEnv.ACTQL_LAYOUT_CASE;
    delete sampleEnv.ACTQL_LAYOUT_ADDITIONAL_CASE;
    sampleEnv[additional ? 'ACTQL_LAYOUT_ADDITIONAL_CASE' : 'ACTQL_LAYOUT_CASE'] = String(case_index);
    const sample = run('/usr/bin/time', [platform() === 'darwin' ? '-l' : '-v', command, ...args],
      { env: sampleEnv });
    const wall = performance.now() - started;
    const measurement = checkedSample(sample.stdout, scheduled);
    samples.push({ ...measurement, case_index, repeat, process_wall_ms: wall,
      peak_rss_bytes: peakRssBytes(sample.stderr, platform()), captured_at: new Date().toISOString() });
    save();
    process.stderr.write(`${target} case=${case_index} repeat=${repeat} ${candidate}: PASS\n`);
  }
}
report.status = 'complete';
report.finished_at = new Date().toISOString();
save();
process.stdout.write('Measurements saved under _build/layout-measurements; full adoption gate remains incomplete.\n');
