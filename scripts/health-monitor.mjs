import {execFileSync} from 'node:child_process';
import {readFile, mkdir} from 'node:fs/promises';
import {cpus, arch, platform, release} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {compareReports, digest, jsonDigest, finishReport, saveReport, markdown, summarize} from './health-monitor-report.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const self = fileURLToPath(import.meta.url);
const policy = JSON.parse(await readFile(new URL('../benchmarks/health/config.json', import.meta.url)));
const optionKeys = {'--base': 'base', '--current': 'current', '--output': 'output', '--packages': 'packages',
  '--native-manifest': 'nativeManifest', '--native-consumer': 'nativeConsumer', '--python-manifest': 'pythonManifest',
  '--python-consumer': 'pythonConsumer', '--python-venv': 'pythonVenv', '--python': 'python',
  '--comparison': 'comparison', '--load': 'load', '--run': 'run'};

export function parseArguments(args) {
  const [mode, ...rest] = args;
  if (!['quick', 'release', 'compare', 'execute-quick', 'execute-release'].includes(mode)) throw new Error('Use quick, release or compare');
  const options = {};
  if (rest.length % 2) throw new Error('Every option requires one value');
  for (let index = 0; index < rest.length; index += 2) {
    const key = optionKeys[rest[index]];
    if (!key || Object.hasOwn(options, key)) throw new Error(`Unknown/duplicate option ${rest[index]}`);
    options[key] = rest[index + 1];
  }
  if (options.load && !['isolated', 'concurrent'].includes(options.load)) throw new Error('load must be isolated or concurrent');
  if (mode === 'compare' && (!options.base || !options.current)) throw new Error('Compare requires --base and --current');
  return {mode, options};
}

function readCommand(command, args) {
  try {return execFileSync(command, args, {cwd: repository, encoding: 'utf8', timeout: 30_000, maxBuffer: 8 * 1024 ** 2}).trim();}
  catch (error) {return `unavailable: ${error.code ?? error.message}`;}
}
export function sourceIdentity(root = repository) {
  const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 ** 2}).trim();
  const status = git(['status', '--porcelain', '--untracked-files=all']);
  return {sha: git(['rev-parse', 'HEAD']), tree: git(['rev-parse', 'HEAD^{tree}']), dirty: status !== '', status,
    diffSha256: digest(git(['diff', 'HEAD', '--binary']))};
}
export async function environmentIdentity(options = {}) {
  return {platform: platform(), architecture: arch(), osRelease: release(), cpuModel: cpus()[0]?.model ?? 'unavailable',
    logicalCpus: cpus().length, node: process.version, nodeExecutableSha256: digest(await readFile(process.execPath)),
    python: readCommand(options.python ?? 'python3', ['--version']), moon: readCommand('moon', ['version']),
    toolchainSha256: digest(await readFile(join(repository, 'toolchain.json'))),
    buildSettings: {target: 'js', profile: 'release', pack: 'normal npm prepack',
      instrumentation: {nodeOptions: process.env.NODE_OPTIONS ?? '', execArgv: process.execArgv, coverage: process.env.NODE_V8_COVERAGE ?? ''},
      load: options.load ?? 'concurrent', osPageCache: 'not evicted'}};
}

const missing = (id, kind, target = 'node-local') => ({id, target, kind, required: true,
  status: 'incomplete', reason: 'Required measurement not yet observed'});
export function requiredQuickMetrics() {
  return [...['client-wire', 'sdk', 'node', 'run-host-core', 'local-node'].map(name => missing('tarball:@actql/' + name, 'size', '@actql/' + name)),
    missing('installed:node-local', 'size'), missing('installed:remote-sdk', 'size', 'remote-sdk'),
    missing('browser-raw', 'size', 'remote-sdk'), missing('browser-gzip', 'size', 'remote-sdk'),
    ...['warm-select', 'warm-join', 'warm-aggregate', 'warm-saved', 'warm-status', 'cold-process-first-result-close',
      'cold-host-initialization', 'cold-first-query', 'cold-first-close', 'mock-workflow'].map(id => missing(id, 'latency')),
    missing('peak-rss', 'rss')];
}

async function applyComparison(report, options) {
  report.comparison = options.base ? compareReports(JSON.parse(await readFile(options.base)), report, policy)
    : {available: false, comparable: false, baselineId: null,
      reason: 'No reviewed baseline selected; measurement-only first run; baseline not created or updated'};
}

export async function executeMonitor({mode, options, report, directory}) {
  const {execute, prepareHealthPackages, distributionMetrics, quickNodeMetrics, mockWorkflowMetrics} = await import('./health-monitor-adapters.mjs');
  const raw = join(directory, 'raw'); await mkdir(raw, {recursive: true});
  const onMetric = async metric => {
    if (metric.kind === 'latency' && metric.samples?.length) metric = {...metric,
      statistics: summarize(metric.samples, metric.temperature === 'cold' ? 30 : 100)};
    const index = report.metrics.findIndex(row => row.id === metric.id && row.target === metric.target);
    if (index < 0) report.metrics.push(structuredClone(metric)); else report.metrics[index] = structuredClone(metric);
    await saveReport(directory, finishReport(report));
  };
  const command = (command, args, settings = {}) => execute(command, args, {...settings, raw,
    env: {...process.env, npm_config_cache: join(directory, 'npm-cache')}});
  const started = process.hrtime.bigint();
  let prepared;
  try {
    prepared = await prepareHealthPackages({repository, root: raw, source: report.source, retained: options.packages, command});
    await onMetric({id: 'build-packaging', kind: 'reference', target: 'distribution', value: Number(process.hrtime.bigint() - started) / 1e6,
      unit: 'ms', required: true, fixtureSha256: jsonDigest({packages: 'canonical5', retained: Boolean(options.packages)}), evidence: raw,
      scope: options.packages ? 'verified retained artifacts plus fresh installation; no build' : 'normal prepack/build, npm pack and fresh installation; excluded from runtime samples'});
    const distribution = await distributionMetrics({repository, prepared, root: raw, command, source: report.source});
    report.artifacts.push(...distribution.artifacts);
    report.installedInventoryBefore = distribution.installedInventory;
    for (const metric of distribution.metrics) await onMetric(metric);
    const counts = policy[mode];
    if (mode === 'quick') {
      await quickNodeMetrics({prepared, root: raw, repository, command, counts, onMetric});
      await mockWorkflowMetrics({prepared, root: raw, repository, command, counts, onMetric});
      for (const target of ['native', 'python']) await onMetric({id: target + '-artifacts', target, kind: 'size', required: false,
        status: 'incomplete', reason: 'Optional platform not selected in Quick; use Release for its required cohort'});
      if (options.nativeManifest || options.pythonManifest) {
        const {releaseArtifacts} = await import('./health-monitor-release.mjs');
        await releaseArtifacts({options, repository, source: report.source, command,
          onArtifact: async artifact => report.artifacts.push(artifact), onMetric: metric => onMetric({...metric, required: false})});
      }
    } else {
      // Quick routes are not relabelled as formal Release samples. Keep original
      // collectors' 100/30, comparison controls, early stop and failed samples.
      report.metrics = report.metrics.filter(row => !['latency', 'rss'].includes(row.kind));
      const {releaseArtifacts, releaseMeasurements} = await import('./health-monitor-release.mjs');
      const ready = await releaseArtifacts({options, repository, source: report.source, command,
        onArtifact: async artifact => report.artifacts.push(artifact), onMetric});
      if (ready && options.comparison) {
        await releaseMeasurements({options, prepared, repository, root: raw, source: report.source, command, onMetric});
        await mockWorkflowMetrics({prepared, root: raw, repository, command, counts, onMetric});
      } else await onMetric({id: 'release-public-collectors', target: 'all', kind: 'latency', required: true, status: 'incomplete',
        reason: 'Required matching Native/Python artifacts or fixed SQLite comparison absent; formal workload not started'});
    }
  } catch (error) {
    report.errors.push({target: 'collector', name: error.name, code: error.code ?? null, message: error.message,
      ...(error.commandResult ? {command: error.commandResult} : {})});
  } finally {
    if (prepared) {
      try {
        const {verifyNodeBenchmarkPackages} = await import('./benchmark-node-operations.mjs');
        await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
        const {inventory} = await import('./package-release.mjs');
        report.installedInventoryAfter = await inventory(join(prepared.consumer, 'node_modules'));
        if (jsonDigest(report.installedInventoryBefore) !== jsonDigest(report.installedInventoryAfter)) throw new Error('Installed package inventory changed');
        report.installedPayloadsUnchanged = true;
      } catch (error) {report.errors.push({target: 'package-after', message: error.message});}
    }
    report.sourceAfter = sourceIdentity(); report.environmentAfter = await environmentIdentity(options);
    report.sourceChanged = jsonDigest(report.source) !== jsonDigest(report.sourceAfter);
    report.environmentChanged = jsonDigest(report.environment) !== jsonDigest(report.environmentAfter);
    try {await applyComparison(report, options);} catch (error) {report.errors.push({target: 'baseline', message: error.message});}
    report.endedAt = new Date().toISOString();
    await saveReport(directory, finishReport(report));
  }
  return report;
}

export async function main(args = process.argv.slice(2)) {
  let parsed, directory, report;
  try {
    parsed = parseArguments(args);
    if (parsed.mode.startsWith('execute-')) {
      directory = resolve(parsed.options.run);
      report = JSON.parse(await readFile(join(directory, 'report.json')));
      await executeMonitor({...parsed, mode: parsed.mode.slice(8), directory, report});
      console.log(markdown(report)); return report.exitCode;
    }
    directory = resolve(parsed.options.output ?? join(repository, '_build/health', `${new Date().toISOString().replaceAll(':', '-')}-${randomUUID()}`));
    await mkdir(directory, {recursive: false, mode: 0o700}); // Existing run can never be reused.
    if (parsed.mode === 'compare') {
      report = JSON.parse(await readFile(parsed.options.current));
      report = structuredClone(report);
      report.id = randomUUID(); report.measuredMode = report.mode; report.mode = 'compare';
      // Compare original measurement modes, not the output presentation mode.
      const current = JSON.parse(await readFile(parsed.options.current));
      report.comparison = compareReports(JSON.parse(await readFile(parsed.options.base)), current, policy);
      report.compareInputs = {base: resolve(parsed.options.base), current: resolve(parsed.options.current),
        baseSha256: digest(await readFile(parsed.options.base)), currentSha256: digest(await readFile(parsed.options.current))};
      finishReport(report); await saveReport(directory, report); console.log(markdown(report)); return report.exitCode;
    }
    report = {format: 'actql-health/0.1', id: randomUUID(), mode: parsed.mode, startedAt: new Date().toISOString(),
      source: sourceIdentity(), environment: await environmentIdentity(parsed.options), selectedTargets: parsed.mode === 'quick' ? ['remote-sdk', 'node-local', 'run-host-core'] : ['remote-sdk', 'node-local', 'run-host-core', 'native', 'python', 'wasm'],
      methodologySha256: jsonDigest({policy, fixtureFiles: await fixtureIdentities()}), config: policy,
      metrics: requiredQuickMetrics(), artifacts: [], errors: [], formalAcceptance: false,
      comparison: {available: false, reason: 'Comparison not yet performed'}};
    await saveReport(directory, finishReport(report));
    const {runLocalCheck} = await import('./local-checks-guard.mjs');
    const workerArgs = [self, 'execute-' + parsed.mode, '--run', directory, ...args.slice(1)];
    const code = await runLocalCheck({root: repository, heavy: true, timeoutSeconds: parsed.mode === 'quick' ? 1800 : 7200, graceSeconds: 5,
      heavyResources: parsed.options.packages ? {memoryBytes: 2 * 1024 ** 3, diskBytes: 1024 ** 3, cpuThreads: 1}
        : {memoryBytes: 6 * 1024 ** 3, diskBytes: 6 * 1024 ** 3, cpuThreads: 2},
      steps: [{name: `Health ${parsed.mode}: ordinary artifacts and public fixture`, command: process.execPath, args: workerArgs}]});
    report = JSON.parse(await readFile(join(directory, 'report.json')));
    report.guardExitCode = code;
    if (code !== report.exitCode) {
      report.errors.push({target: 'resource/execution guard', message: `Original guard exited ${code}; inspect _build/local-checks/attempts original evidence`});
      finishReport(report); await saveReport(directory, report);
    }
    console.log(`Health report: ${directory}`); console.log(markdown(report)); return report.exitCode;
  } catch (error) {
    // Even malformed input and pre-admission errors get their own immutable run.
    if (!directory) {
      await mkdir(join(repository, '_build/health'), {recursive: true});
      directory = join(repository, '_build/health', 'error-' + randomUUID()); await mkdir(directory);
    } else {
      // Never overwrite an existing output selected by a caller.
      try {if (!report) await readFile(join(directory, 'report.json'));}
      catch { /* The newly created run may have no report yet. */ }
      if (!report) {
        directory = join(repository, '_build/health', 'error-' + randomUUID());
        await mkdir(dirname(directory), {recursive: true}); await mkdir(directory);
      }
    }
    report ??= {format: 'actql-health/0.1', id: randomUUID(), mode: parsed?.mode ?? 'invalid', metrics: [], artifacts: [], errors: []};
    report.errors.push({target: 'runner', name: error.name, message: error.message});
    await saveReport(directory, finishReport(report)); console.error(`Health error: ${error.message}\nReport: ${directory}`); return report.exitCode;
  }
}

async function fixtureIdentities() {
  const files = ['scripts/benchmark-node-operations.mjs', 'adapters/host-node/fixtures/mock-project-effect-public.mjs',
    'packages/native-cli/lib/project-template.mjs', 'scripts/health-monitor-adapters.mjs'];
  return Object.fromEntries(await Promise.all(files.map(async file => [file, digest(await readFile(join(repository, file)))])));
}

if (process.argv[1] && resolve(process.argv[1]) === self) {
  await mkdir(join(repository, '_build/health'), {recursive: true});
  process.exitCode = await main();
}
