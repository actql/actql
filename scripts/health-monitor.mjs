import {execFileSync} from 'node:child_process';
import {readFile, mkdir} from 'node:fs/promises';
import {cpus, arch, platform, release} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {compareReports, digest, jsonDigest, finishReport, saveReport, markdown, summarize, measurementProfile} from './health-monitor-report.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const self = fileURLToPath(import.meta.url);
const policy = JSON.parse(await readFile(new URL('../benchmarks/health/config.json', import.meta.url)));
const optionKeys = {'--base': 'base', '--current': 'current', '--output': 'output', '--packages': 'packages',
  '--native-manifest': 'nativeManifest', '--native-consumer': 'nativeConsumer', '--python-manifest': 'pythonManifest',
  '--python-consumer': 'pythonConsumer', '--python-venv': 'pythonVenv', '--python': 'python',
  '--comparison': 'comparison', '--node-controls': 'nodeControls', '--python-controls': 'pythonControls',
  '--load': 'load', '--run': 'run'};

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
  const pythonRuntime = options.pythonVenv
    ? (await import('./health-monitor-release.mjs')).pythonRuntimeIdentity(options.pythonVenv) : undefined;
  return {...(pythonRuntime === undefined ? {} : {pythonRuntime}), platform: platform(), architecture: arch(), osRelease: release(), cpuModel: cpus()[0]?.model ?? 'unavailable',
    logicalCpus: cpus().length, node: process.version, nodeExecutableSha256: digest(await readFile(process.execPath)),
    python: readCommand(options.python ?? 'python3', ['--version']), moon: readCommand('moon', ['version']),
    toolchainSha256: digest(await readFile(join(repository, 'toolchain.json'))),
    buildSettings: {target: 'js', profile: 'release', pack: 'normal npm prepack',
      instrumentation: {nodeOptions: process.env.NODE_OPTIONS ?? '', execArgv: process.execArgv, coverage: process.env.NODE_V8_COVERAGE ?? ''},
      load: options.load ?? 'concurrent', osPageCache: 'not evicted'}};
}

export function requiredQuickMetrics() {
  return measurementProfile('quick').map(row => ({...row, status: 'incomplete', reason: 'Required measurement not yet observed'}));
}

export function missingReleaseInputs(options) {
  return ['nativeManifest', 'nativeConsumer', 'pythonManifest', 'pythonConsumer', 'pythonVenv', 'nodeControls', 'pythonControls']
    .filter(key => !options[key]);
}

export async function verifyPythonInstalledAfter(report, options) {
  const before = report.artifacts.find(row => row.name === 'python-products-installed');
  if (!before) return;
  try {
    const {pythonInstalledInventory} = await import('./health-monitor-release.mjs');
    const after = await pythonInstalledInventory(options.pythonConsumer,
      report.artifacts.filter(row => row.artifactKind === 'wheel'));
    report.pythonInstalledInventoryAfter = after;
    if (after.sha256 !== before.sha256) throw new Error('Python installed product namespaces changed after collection');
    report.pythonInstalledPayloadsUnchanged = true;
  } catch (error) {
    report.pythonInstalledPayloadsUnchanged = false;
    report.installedPayloadsUnchanged = false;
    report.errors.push({target: 'python-package-after', message: error.message});
  }
}

export async function verifyNativeInstalledAfter(report, options, command) {
  const before = report.artifacts.find(row => row.name === 'native-products-installed');
  if (!before) return;
  try {
    const result = await command(options.python ?? 'python3', ['-I', '-B', join(repository, 'scripts/health-release-artifacts.py'),
      '--native-installed', options.nativeManifest, options.nativeConsumer, report.source.sha],
    {cwd: repository, name: 'inspect-native-after'});
    const after = JSON.parse(result.stdout);
    report.nativeInstalledInventoryAfter = after;
    if (jsonDigest(after) !== before.sha256) throw new Error('Native installed product payloads or selected cohort changed after collection');
    report.nativeInstalledPayloadsUnchanged = true;
  } catch (error) {
    report.nativeInstalledPayloadsUnchanged = false;
    report.installedPayloadsUnchanged = false;
    report.errors.push({target: 'native-package-after', message: error.message});
  }
}

export function recordGuardExit(report, code) {
  report.guardExitCode = code;
  if (code !== report.exitCode) {
    report.errors.push({target: 'resource/execution guard', message: `Original guard exited ${code}; inspect _build/local-checks/attempts original evidence`});
    finishReport(report);
  }
  return report;
}

export async function applyComparison(report, options, root = repository) {
  const explicit = Object.hasOwn(options, 'base');
  const selection = explicit ? 'explicit' : 'default';
  let baselinePath;
  try {
    if (explicit) baselinePath = resolve(options.base);
    else {
      const {platform, architecture} = report.environment ?? {};
      if (![platform, architecture].every(value => typeof value === 'string' && /^[a-z0-9_-]+$/u.test(value))) {
        throw new Error('Invalid platform/architecture for default health baseline');
      }
      baselinePath = join(root, 'benchmarks/health/baselines', `${platform}-${architecture}.json`);
    }
    const bytes = await readFile(baselinePath);
    report.comparison = {...compareReports(JSON.parse(bytes), report, policy),
      baselineSelection: selection, baselinePath, baselineSha256: digest(bytes)};
  } catch (error) {
    if (!explicit && baselinePath && error.code === 'ENOENT') {
      report.comparison = {available: false, comparable: false, baselineId: null,
        baselineSelection: selection, baselinePath,
        reason: 'Default reviewed baseline absent; measurement-only first run; baseline not created or updated'};
      return;
    }
    report.comparison = {available: true, comparable: false, baselineId: null, status: 'error',
      baselineSelection: selection, baselinePath: baselinePath ?? null, reasons: [error.message], verdicts: []};
    throw error; // Malformed/unreadable evidence and missing explicit overrides never become first-run absence.
  }
}

export async function executeMonitor({mode, options, report, directory}) {
  const {execute, prepareHealthPackages, distributionMetrics, quickNodeMetrics, mockWorkflowMetrics} = await import('./health-monitor-adapters.mjs');
  const raw = join(directory, 'raw'); await mkdir(raw, {recursive: true});
  const onMetric = async metric => {
    if (metric.kind === 'latency' && metric.samples?.length) metric = {...metric,
      statistics: summarize(metric.samples, mode === 'release' ? metric.requiredSamples
        : metric.temperature === 'cold' ? 30 : 100)};
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
    const {inventory} = await import('./package-release.mjs');
    report.installedInventoryBefore = await inventory(join(prepared.consumer, 'node_modules'));
    await onMetric({id: 'build-packaging', kind: 'reference', target: 'distribution', value: Number(process.hrtime.bigint() - started) / 1e6,
      unit: 'ms', required: true, fixtureSha256: jsonDigest({packages: 'canonical5', retained: Boolean(options.packages)}), evidence: raw,
      scope: options.packages ? 'verified retained artifacts plus fresh installation; no build' : 'normal prepack/build, npm pack and fresh installation; excluded from runtime samples'});
    const distribution = await distributionMetrics({repository, prepared, root: raw, command, source: report.source,
      installedInventory: report.installedInventoryBefore});
    report.artifacts.push(...distribution.artifacts);
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
      report.metrics = report.metrics.filter(row => row.kind !== 'latency');
      const {releaseArtifacts, releaseMeasurements} = await import('./health-monitor-release.mjs');
      const ready = await releaseArtifacts({options, repository, source: report.source, command,
        onArtifact: async artifact => report.artifacts.push(artifact), onMetric});
      if (ready) {
        await releaseMeasurements({options, prepared, repository, root: raw, source: report.source, command, onMetric});
        const {assessLatency} = await import('./operation-performance.mjs');
        const {nodeBenchmarkInstrumentation} = await import('./benchmark-node-operations.mjs');
        await mockWorkflowMetrics({prepared, root: raw, repository, command, counts,
          onMetric: async metric => {
            const binding = {cohortSha256: digest(await readFile(prepared.manifestPath)), fixtureSha256: metric.fixtureSha256};
            const assessment = assessLatency({operation: 'mock-workflow', mode: 'final', ...binding,
              environmentSha256: jsonDigest(report.environment), ...nodeBenchmarkInstrumentation(), load: options.load ?? 'concurrent',
              samples: metric.samples.map(row => ({...row, ...binding}))});
            await onMetric({...metric, formalAssessment: assessment,
              ...(assessment.status === 'passed' ? {} : {status: assessment.status === 'failed' ? 'regression' : 'incomplete',
                reason: 'Existing formal Mock assessment: ' + [...assessment.failures, ...assessment.missing].join('; ')})});
          }});
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
    await verifyNativeInstalledAfter(report, options, command);
    await verifyPythonInstalledAfter(report, options);
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
    const methodologyFiles = await fixtureIdentities(parsed.mode);
    report = {format: 'actql-health/0.1', id: randomUUID(), mode: parsed.mode, startedAt: new Date().toISOString(),
      source: sourceIdentity(), environment: await environmentIdentity(parsed.options), selectedTargets: parsed.mode === 'quick' ? ['remote-sdk', 'node-local', 'run-host-core'] : ['remote-sdk', 'node-local', 'run-host-core', 'native', 'python', 'wasm'],
      methodologyFiles, methodologySha256: jsonDigest({policy, fixtureFiles: methodologyFiles}), config: policy,
      metrics: requiredQuickMetrics(), artifacts: [], errors: [], formalAcceptance: false,
      comparison: {available: false, reason: 'Comparison not yet performed'}};
    await saveReport(directory, finishReport(report));
    if (parsed.mode === 'release' && missingReleaseInputs(parsed.options).length) {
      report.metrics.push({id: 'required-release-inputs', target: 'native/python', kind: 'reference', required: true,
        status: 'incomplete', reason: 'Missing required Release inputs: ' + missingReleaseInputs(parsed.options).join(', ') + '; no build or formal workload started'});
      report.sourceAfter = sourceIdentity(); report.environmentAfter = await environmentIdentity(parsed.options);
      report.sourceChanged = jsonDigest(report.source) !== jsonDigest(report.sourceAfter);
      report.environmentChanged = jsonDigest(report.environment) !== jsonDigest(report.environmentAfter);
      report.endedAt = new Date().toISOString();
      await saveReport(directory, finishReport(report)); console.log(markdown(report)); return report.exitCode;
    }
    const {runLocalCheck} = await import('./local-checks-guard.mjs');
    const workerArgs = [self, 'execute-' + parsed.mode, '--run', directory, ...args.slice(1)];
    const code = await runLocalCheck({root: repository, heavy: true, timeoutSeconds: parsed.mode === 'quick' ? 1800 : 7200, graceSeconds: 5,
      heavyResources: parsed.options.packages ? {memoryBytes: 2 * 1024 ** 3, diskBytes: 1024 ** 3, cpuThreads: 1}
        : {memoryBytes: 6 * 1024 ** 3, diskBytes: 6 * 1024 ** 3, cpuThreads: 2},
      steps: [{name: `Health ${parsed.mode}: ordinary artifacts and public fixture`, command: process.execPath, args: workerArgs}]});
    report = JSON.parse(await readFile(join(directory, 'report.json')));
    recordGuardExit(report, code);
    await saveReport(directory, report);
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

async function fixtureIdentities(mode = 'quick') {
  if (!['quick', 'release'].includes(mode)) throw new Error('Unknown measurement methodology mode');
  // Bind the actual selected entry collectors, timing/statistics and artifact
  // inspection code. This is a fixed source inventory, not a dependency scanner.
  const files = ['scripts/benchmark-node-operations.mjs', 'adapters/host-node/fixtures/mock-project-effect-public.mjs',
    'packages/native-cli/lib/project-template.mjs', 'scripts/health-monitor-adapters.mjs',
    'scripts/health-monitor.mjs', 'scripts/health-monitor-report.mjs', 'scripts/measure-distribution-artifacts.mjs',
    'scripts/package-release.mjs', 'scripts/operation-performance.mjs', 'scripts/ordinary-operation-packages.mjs'];
  if (mode === 'release') files.push('scripts/benchmark-node-process-operations.mjs', 'scripts/benchmark-ordinary-processes.py',
    'scripts/health-monitor-release.mjs', 'scripts/health-release-artifacts.py', 'scripts/native-cli-release.mjs');
  return Object.fromEntries(await Promise.all(files.map(async file => [file, digest(await readFile(join(repository, file)))])));
}

if (process.argv[1] && resolve(process.argv[1]) === self) {
  await mkdir(join(repository, '_build/health'), {recursive: true});
  process.exitCode = await main();
}
