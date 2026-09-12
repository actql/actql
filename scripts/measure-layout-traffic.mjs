// Supplementary deterministic data-container traffic, not time/RSS measurements.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { additionalSchedule, legacySchedule } from './layout-measurement-support.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
if (process.argv.length !== 2) throw new Error('No workload overrides: run the fixed traffic matrix');
const moonHome = process.env.MOON_HOME;
if (!moonHome) throw new Error('Set MOON_HOME to the pinned toolchain');
const env = { ...process.env, PATH: `${moonHome}/bin:${process.env.PATH}` };
const run = (cmd, args, extra = {}) => execFileSync(cmd, args, {
  encoding: 'utf8', env, timeout: 600000, maxBuffer: 32 * 1024 * 1024, ...extra,
});
const git = args => run('git', args).trim();
const hash = data => createHash('sha256').update(data).digest('hex');
if (git(['status', '--porcelain']) !== '') throw new Error('Commit diagnostic source before measurement');
const manifestBytes = readFileSync('benchmarks/local-relation/columnar-experiment.json');
const manifest = JSON.parse(manifestBytes);
const compiler = run(`${moonHome}/bin/moonc`, ['-v']).trim();
if (!compiler.includes(JSON.parse(readFileSync('toolchain.json')).version)) throw new Error('Unpinned compiler');
const report = {
  status: 'running', source_commit: git(['rev-parse', 'HEAD']),
  script_sha256: hash(readFileSync('scripts/measure-layout-traffic.mjs')),
  manifest_sha256: hash(manifestBytes), compiler, build: 'release',
  scope: 'Successful data-array construction and cell/reference/index transfer events; not allocator-wide traffic, scratch totals, deep copies, timing, RSS or an adoption gate',
  targets: [],
};
const out = resolve('_build/layout-measurements/traffic-samples.json');
mkdirSync(dirname(out), { recursive: true });
const save = () => writeFileSync(out, JSON.stringify(report, null, 2) + '\n');
save();
const testArgs = JSON.stringify({ package: 'actql/actql/execution_relation',
  file_and_index: [['sequence_profile_wbtest.mbt', [{ start: 0, end: 1 }]]] });
const fields = ['data_arrays', 'validity_arrays', 'validity_capacity', 'column_cell_transfers',
  'selection_arrays', 'selection_index_copies', 'row_cell_transfers', 'row_reference_copies'];
for (const target of ['native', 'js', 'wasm']) {
  run(`${moonHome}/bin/moon`, ['test', '--target', target, 'src/execution_relation/sequence_profile_wbtest.mbt',
    '--release', '--build-only', '--deny-warn']);
  const artifact = resolve(`_build/${target}/release/test/execution_relation/execution_relation.whitebox_test.${target === 'native' ? 'exe' : target}`);
  const command = target === 'native' ? artifact : target === 'js' ? process.execPath : `${moonHome}/bin/moonrun`;
  const args = target === 'native' ? ['sequence_profile_wbtest.mbt:0-1']
    : target === 'js' ? [artifact, testArgs] : [artifact, '--test-args', testArgs];
  const result = { target, artifact_sha256: hash(readFileSync(artifact)), samples: [] };
  report.targets.push(result);
  for (const [family, schedule] of [['additional', additionalSchedule], ['legacy', legacySchedule]]) {
    for (const item of schedule(manifest, target, false).filter(item => item.repeat === 0)) {
      const sampleEnv = { ...env, ACTQL_LAYOUT_TRAFFIC: '1', ACTQL_LAYOUT_CANDIDATE: item.candidate };
      delete sampleEnv.ACTQL_LAYOUT_PREPARED;
      delete sampleEnv.ACTQL_LAYOUT_CASE;
      delete sampleEnv.ACTQL_LAYOUT_ADDITIONAL_CASE;
      sampleEnv[family === 'additional' ? 'ACTQL_LAYOUT_ADDITIONAL_CASE' : 'ACTQL_LAYOUT_CASE'] = String(item.case_index);
      const events = run(command, args, { env: sampleEnv }).split('\n')
        .filter(line => line.startsWith('{')).map(line => JSON.parse(line));
      const samples = events.filter(e => e.kind === 'layout-traffic');
      const passed = events.filter(e => e.type === 'result');
      if (samples.length !== 1 || passed.length !== 1 || passed[0].message !== '' ||
          passed[0].file !== 'sequence_profile_wbtest.mbt' || Number(passed[0].index) !== 0) throw new Error('Missing independent success');
      const sample = samples[0];
      if (['candidate', 'rows', 'columns', 'same_keys'].some(k => sample[k] !== item[k]) ||
          fields.some(k => !Number.isSafeInteger(sample[k]) || sample[k] < 0) ||
          'end_to_end_us' in sample || 'phases_us' in sample) throw new Error('Invalid traffic measurement');
      result.samples.push({ family, case_index: item.case_index, ...sample });
      save();
      process.stdout.write(`${target} ${family}/${item.case_index} ${item.candidate}: PASS\n`);
    }
  }
}
report.status = 'complete';
save();
console.log(out);
