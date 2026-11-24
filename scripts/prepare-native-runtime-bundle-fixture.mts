// One job's exact-source public command/component artifacts. Consumers verify
// the original producer inputs again; private Stores and keys stay per test.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {appendFileSync, mkdirSync, realpathSync, writeFileSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {prepareNativeResidentHttpComponent, prepareNativeResidentSite, prepareNativeRuntimeBundle,
  prepareNativeRuntimeBundleLibraries} from './native-runtime-bundle-fixture.mjs';
import {originalDescriptor} from './native-preparation-originals.mjs';
import {prepareNativeResidentPortableRuntime} from './native-resident-portable-preparation.mjs';
import {prepareNativeParallel, nativePreparationConsumerJobs, nativePreparationOpenSSL} from './native-preparation-lanes.mjs';
import {prepareNativeQuerySoftware} from './native-query-preparation.mjs';
import {withNativePreparationResources} from './native-preparation-resources.mjs';

export function parseNativePreparationOptions(args: readonly string[]) {
  const options: Partial<Record<string, string>> = {};
  for (let i = 0; i < args.length; i += 2) {
    assert(['--destination', '--entries', '--seconds', '--resident-seconds', '--http-jobs', '--lanes'].includes(args[i])
      && args[i + 1] !== undefined);
    assert.equal(options[args[i]], undefined);
    options[args[i]] = args[i + 1];
  }
  const destination = options['--destination'];
  assert(destination);
  const selection = options['--entries'] ?? 'bundle';
  assert(['bundle', 'resident', 'all'].includes(selection));
  const seconds = Number(options['--seconds'] ?? 900);
  assert(Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 1800);
  const residentSeconds = Number(options['--resident-seconds'] ?? seconds);
  assert(Number.isSafeInteger(residentSeconds) && residentSeconds > 0 && residentSeconds <= 1800);
  const httpJobs = Number(options['--http-jobs'] ?? 1);
  assert(Number.isSafeInteger(httpJobs) && [1, 2].includes(httpJobs));
  const lanes = Number(options['--lanes'] ?? 1);
  assert([1, 2].includes(lanes));
  return {destination, selection, seconds, residentSeconds, httpJobs, lanes};
}

type Identity = {destination: string; source: string; target: string};
type TimingPorts = {
  now?: () => number;
  record?: (path: string, bytes: string, options: {flag: 'wx'; mode: number}) => void;
  summarize?: (path: string, text: string) => void;
  report?: (text: string) => void;
  env?: NodeJS.ProcessEnv;
};

export function nativePreparationTimer({destination, source, target}: Identity,
  {now = () => performance.now(), record = writeFileSync, summarize = appendFileSync,
    report = text => console.error(text), env = process.env}: TimingPorts = {}) {
  let phaseNumber = 0;
  return function timed<Value>(phase: string, prepare: () => Value): Value {
    const started = now();
    let succeeded = false;
    try {
      const value = prepare();
      succeeded = true;
      return value;
    } finally {
      const milliseconds = Math.round(now() - started);
      report('ACTQL_NATIVE_CI_PHASE ' + JSON.stringify({phase, milliseconds, succeeded}));
      // Retain bounded diagnostics outside the preparation identity.
      try {
        record(join(destination, `phase-${++phaseNumber}.timing.json`),
          JSON.stringify({source, target, phase, milliseconds, succeeded}) + '\n', {flag: 'wx', mode: 0o600});
      } catch { report('Native timing diagnostic unavailable'); }
      if (env.GITHUB_STEP_SUMMARY) {
        try {
          summarize(env.GITHUB_STEP_SUMMARY,
            `- Native ${phase}: ${milliseconds} ms (${succeeded ? 'success' : 'failed'}).\n`);
        } catch { report('Native timing summary unavailable'); }
      }
    }
  };
}

type FixtureConfiguration = ReturnType<typeof parseNativePreparationOptions> & Identity & {
  repository: string; moonHome: string; clang: string; sdk: string | null;
};
type FixturePorts = {
  env?: NodeJS.ProcessEnv;
  timed?: ReturnType<typeof nativePreparationTimer>;
  bundle?: typeof prepareNativeRuntimeBundle;
  resident?: typeof prepareNativeResidentSite;
  libraries?: typeof prepareNativeRuntimeBundleLibraries;
  http?: typeof prepareNativeResidentHttpComponent;
  portable?: typeof prepareNativeResidentPortableRuntime;
  query?: typeof prepareNativeQuerySoftware;
  parallel?: typeof prepareNativeParallel;
};
type Prepared = Awaited<ReturnType<typeof prepareNativeParallel>>;

export async function prepareNativeFixture(configuration: FixtureConfiguration, checkSource: () => void,
  {env = process.env, timed = nativePreparationTimer(configuration, {env}), bundle = prepareNativeRuntimeBundle,
    resident = prepareNativeResidentSite, libraries = prepareNativeRuntimeBundleLibraries,
    http = prepareNativeResidentHttpComponent, portable = prepareNativeResidentPortableRuntime,
    query = prepareNativeQuerySoftware, parallel = prepareNativeParallel}: FixturePorts = {}) {
  const {destination, repository, source, target, moonHome, clang, sdk, selection, seconds, residentSeconds,
    httpJobs, lanes} = configuration;
  mkdirSync(destination, {mode: 0o700});
  function serialPreparation(): Prepared {
    const entries: NonNullable<Prepared['entries']> = {};
    for (const [name, prepare, selected] of [
      ['native_runtime_bundle', bundle, selection !== 'resident'],
      ['native_remote_resident_site', resident, selection !== 'bundle'],
    ] as const) {
      if (!selected) continue;
      const directory = join(destination, name);
      timed(name, () => prepare(repository, directory, {moonHome,
        seconds: name === 'native_remote_resident_site' ? residentSeconds : seconds, preparation: null}));
      entries[name] = originalDescriptor(join(directory, 'build.json'));
    }
    const components = join(destination, 'components');
    timed('runtime_libraries', () =>
      libraries(repository, components, {moonHome, seconds, preparation: null}));
    const sharedOpenSSL = nativePreparationOpenSSL(components, target, env);
    const httpReceipt = selection === 'bundle' ? undefined : timed('http_component', () =>
      http(repository, join(destination, 'http'), {seconds, tlsArchive: sharedOpenSSL, tlsJobs: httpJobs}));
    const portableReceipt = selection === 'all' ? join(destination, 'portable-runtime.json') : undefined;
    if (portableReceipt !== undefined) timed('portable_runtime', () => portable(repository, portableReceipt));
    return {entries, components, httpReceipt, portableReceipt};
  }

  // Observation stays outside all software input inventories and the Ready index.
  const observation = env.ACTQL_NATIVE_PREPARATION_RESOURCE_OBSERVER === '1'
    ? {rootPid: process.pid, source, target, deadline: Number(env.ACTQL_NATIVE_CI_DEADLINE),
      output: join(destination, 'preparation-resources.observation.json')} : undefined;
  return withNativePreparationResources(observation, async () => {
    const {entries, components, httpReceipt, portableReceipt, queryReceipt} = lanes === 2
      ? await parallel({repository, destination, source, target, selection, seconds, residentSeconds,
        httpJobs, moonHome, clang, sdk})
      : serialPreparation();
    let selectedQuery = queryReceipt;
    if (target === 'darwin-arm64' && selection === 'all') {
      if (lanes === 1) {
        timed('query_software', () => {
          selectedQuery = query(repository, destination, {moonHome});
        });
      } else assert.equal(queryReceipt, join(destination, 'query-software.json'));
    }
    checkSource();
    return {entries: entries!, components: components!, httpReceipt, portableReceipt, queryReceipt: selectedQuery};
  }, ({entries, components, httpReceipt, portableReceipt, queryReceipt}) => {
    const jobs = nativePreparationConsumerJobs({target, selection, lanes, destination, queryReceipt, portableReceipt});
    writeFileSync(join(destination, 'preparation.json'), JSON.stringify({source, target, moon_home: moonHome,
      clang, sdk, entries, components: originalDescriptor(join(components, 'bundle-components.json')),
      http: httpReceipt === undefined ? null : originalDescriptor(join(destination, 'http/preparation.json'))}, null, 2)
      + '\n', {flag: 'wx', mode: 0o600});
    if (env.GITHUB_ENV !== undefined) {
      appendFileSync(env.GITHUB_ENV, 'ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION=' + destination + '\n'
        + (queryReceipt === undefined ? '' : 'ACTQL_TEST_NATIVE_QUERY_PREPARATION=' + queryReceipt + '\n')
        + Object.entries(jobs).map(([name, value]) => name + '=' + value + '\n').join('')
        + (portableReceipt === undefined ? '' : 'ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION=' + portableReceipt + '\n')
        + (httpReceipt === undefined ? '' : 'ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT=' + httpReceipt + '\n'));
    }
    return {source, target, preparation: destination, entries: Object.keys(entries)};
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const options = parseNativePreparationOptions(process.argv.slice(2));
  const target = process.platform === 'darwin' && process.arch === 'arm64' ? 'darwin-arm64'
    : process.platform === 'linux' && process.arch === 'x64' ? 'linux-x64' : undefined;
  assert(target, 'No selected native preparation target');
  const repository = realpathSync(fileURLToPath(new URL('../', import.meta.url)));
  const destination = join(realpathSync(dirname(resolve(options.destination))), basename(options.destination));
  assert(!/[\r\n]/u.test(destination));
  const run = (command: string, args: readonly string[]) =>
    execFileSync(command, args, {cwd: repository, encoding: 'utf8', timeout: 60000});
  const source = run('git', ['rev-parse', 'HEAD']).trim();
  assert.match(source, /^[a-f0-9]{40}$/u);
  assert.equal(run('git', ['status', '--porcelain']), '');
  const moonHome = realpathSync(process.env.MOON_HOME!);
  const clang = realpathSync(process.platform === 'darwin' ? run('xcrun', ['--find', 'clang']).trim()
    : run('sh', ['-c', 'command -v clang']).trim());
  const sdk = process.platform === 'darwin' ? realpathSync(run('xcrun', ['--show-sdk-path']).trim()) : null;
  const result = await prepareNativeFixture({...options, repository, destination, source, target, moonHome, clang, sdk}, () => {
    assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), source);
    assert.equal(run('git', ['status', '--porcelain']), '');
  });
  console.log(JSON.stringify(result));
}
