import {spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const preload = fileURLToPath(new URL('./resource-exit.mjs', import.meta.url));
const repetitions = Number.parseInt(process.argv[2] ?? '100', 10);
const build = process.argv[3] ?? 'debug';
if (!['debug', 'release'].includes(build) || process.argv.length > 4) {
  throw new Error('build must be debug or release');
}
const bundle = fileURLToPath(new URL(
  `../../_build/js/${build}/test/query_integration/query_integration.whitebox_test.js`,
  import.meta.url,
));
if (!Number.isSafeInteger(repetitions) || repetitions < 2 ||
    repetitions > 1000 || !existsSync(bundle)) {
  throw new Error('build query_integration JS tests first; repetitions must be 2..1000');
}

function measure(file, index, count) {
  const selection = JSON.stringify({
    file_and_index: Array.from({length: count}, () => [
      file, [{start: index, end: index + 1}],
    ]),
  });
  const child = spawnSync(process.execPath, [
    '--import', preload, bundle, selection,
  ], {encoding: 'utf8', maxBuffer: 4 * 1024 * 1024});
  if (child.error || child.status !== 0) {
    throw new Error(`test ${file}:${index} failed: ${child.error ?? child.stderr}`);
  }
  const results = [...child.stdout.matchAll(/"type":"result"/g)].length;
  if (results !== count) {
    throw new Error(`test ${file}:${index} returned ${results} results, expected ${count}`);
  }
  const plannerMicroseconds = [...child.stdout.matchAll(
    /ACTQL_PLACEMENT_SEARCH ([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/g,
  )].map(match => Number(match[1]));
  if (file === 'placement_scale_wbtest.mbt' &&
      (plannerMicroseconds.length !== count ||
        plannerMicroseconds.some(value => !Number.isFinite(value) || value < 0))) {
    throw new Error('InvalidPlannerIntervalTelemetry');
  }
  const line = child.stderr.split('\n').find(value =>
    value.startsWith('ACTQL_SEARCH_RESOURCE '));
  if (line === undefined) {
    throw new Error(`test ${file}:${index} omitted process resource telemetry`);
  }
  return {...JSON.parse(line.slice('ACTQL_SEARCH_RESOURCE '.length)),
    ...(plannerMicroseconds.length ? {plannerMicroseconds} : {})};
}

const profiles = [
  {file: 'physical_search_wbtest.mbt', index: 5, name: 'seven-task-five-offer'},
  {file: 'physical_search_wbtest.mbt', index: 6, name: 'seven-task-one-and-two-offer'},
  {file: 'placement_scale_wbtest.mbt', index: 0, name: 'twenty-task-standard-host-two-provider'},
];
const results = profiles.map(({file, index, name}) => {
  const single = measure(file, index, 1);
  const repeated = measure(file, index, repetitions);
  const planner = repeated.plannerMicroseconds?.toSorted((a, b) => a - b);
  const plannerMedian = planner
    ? (planner[Math.floor((planner.length - 1) / 2)] +
        planner[Math.floor(planner.length / 2)]) / 2000
    : undefined;
  return {
    name,
    testFile: file,
    testIndex: index,
    repetitions,
    single,
    repeated,
    incrementalFixtureMs: (repeated.elapsedMs - single.elapsedMs) /
      (repetitions - 1),
    ...(planner ? {plannerOnlyMedianMs: plannerMedian,
      plannerOnlyP95Ms: planner[Math.ceil(planner.length * 0.95) - 1] / 1000} : {}),
  };
});
process.stdout.write(`${JSON.stringify({
  kind: 'actql-placement-search-process-diagnostic',
  build,
  node: process.version,
  platform: process.platform,
  arch: process.arch,
  scope: 'compiled JS fixture plus a separately timed 20-task bounded search; no allocator peak',
  results,
}, null, 2)}\n`);
