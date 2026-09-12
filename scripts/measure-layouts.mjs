// Release harness for the fixed layout experiment. Outputs go to ignored _build,
// never /tmp. At this stage --smoke validates the A harness, not adoption.
import { spawnSync, execFileSync } from 'node:child_process';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cpus, platform, release, arch } from 'node:os';
import { performance } from 'node:perf_hooks';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
const smoke = process.argv.includes('--smoke');
if (!smoke || process.argv.some(arg => arg.startsWith('--') && arg !== '--smoke')) {
  throw new Error('Only --smoke is enabled until B/C and the full fixed matrix are connected');
}
const manifestPath = 'benchmarks/local-relation/columnar-experiment.json';
const manifest = JSON.parse(readFileSync(manifestPath));
const toolchain = JSON.parse(readFileSync('toolchain.json'));
const moonHome = process.env.MOON_HOME;
if (!moonHome) throw new Error('Set MOON_HOME to the pinned toolchain directory');
const env = { ...process.env, PATH: `${moonHome}/bin:${process.env.PATH}` };
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const git = args => execFileSync('git', args, { encoding: 'utf8' }).trim();
const sourceFiles = git(['ls-files', '--cached', '--others', '--exclude-standard',
  'src', 'scripts', 'spec', 'vendor', 'moon.mod', 'toolchain.json', manifestPath]).split('\n').sort();
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
  scope: 'baseline-harness-smoke; no layout comparison or adoption evidence',
  baseline_commit: manifest.row_baseline_commit,
  source_commit: git(['rev-parse', 'HEAD']),
  working_tree_status: git(['status', '--porcelain']),
  source_tree_sha256: tree.digest('hex'),
  script_sha256: hash(readFileSync('scripts/measure-layouts.mjs')),
  manifest_sha256: hash(readFileSync(manifestPath)),
  toolchain, compiler: version,
  host: { platform: platform(), release: release(), arch: arch(), cpu: cpus()[0]?.model },
  warmups: 1, measured_repetitions: 1,
  process_wall_scope: 'runtime startup, warmup, measured invocation and test reporting; excludes build',
  phase_scope: 'one measured invocation; clocks report microseconds; phase 3 includes invocation input checks and physical import',
  rss_scope: 'not measured in harness smoke; retained slots are counters, not RSS bytes',
  targets: [],
};
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
  const started = performance.now();
  const sample = run(command, args, { env: { ...env, ACTQL_LAYOUT_CASE: '0' } });
  const wall = performance.now() - started;
  const events = sample.stdout.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line));
  const measurements = events.filter(event => event.kind === 'layout-sample');
  const results = events.filter(event => event.type === 'result');
  if (measurements.length !== 1 || results.length !== 1 ||
      results[0].file !== 'sequence_profile_wbtest.mbt' || Number(results[0].index) !== 0 || results[0].message !== '') {
    throw new Error(`Missing measurement or independent test success: ${sample.stdout}`);
  }
  const measurement = measurements[0];
  if (measurement.candidate !== 'A' || measurement.rows !== 100 || measurement.columns !== 2 ||
      !measurement.same_keys || measurement.phases_us.length !== 5 ||
      measurement.phases_us.some(n => !Number.isFinite(n) || n < 0) ||
      !Number.isFinite(measurement.end_to_end_us) || measurement.end_to_end_us <= 0) {
    throw new Error(`Invalid phase measurement: ${JSON.stringify(measurement)}`);
  }
  if (measurement.phases_us.reduce((a, b) => a + b, 0) > measurement.end_to_end_us + 1) {
    throw new Error('Phase clocks overlap or omit their enclosing interval');
  }
  report.targets.push({ target, artifact_sha256: hash(readFileSync(artifact)),
    runtime: target === 'js' ? process.version : target === 'wasm'
      ? run(`${moonHome}/bin/moonrun`, ['--version']).stdout.trim() : 'native',
    sample: { ...measurement, process_wall_ms: wall },
  });
  process.stderr.write(`${target}: release phase smoke and independent output assertions PASS\n`);
}
writeFileSync(resolve(outputDirectory, 'harness-smoke.json'), JSON.stringify(report, null, 2) + '\n');
process.stdout.write('Harness smoke saved under _build/layout-measurements; not adoption evidence.\n');
