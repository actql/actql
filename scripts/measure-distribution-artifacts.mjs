// Measure installed distribution artifacts in fresh processes. Import and
// connect use a local response fixture; no provider or network is contacted.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, stat, writeFile} from
  'node:fs/promises';
import {arch, platform, release} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {gzipSync} from 'node:zlib';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
const repetitions = 5;
const native = join(build, 'native/release/build/cmd/native_client',
  'native_client.exe');
if (!['darwin', 'linux'].includes(platform())) {
  throw new Error('Measurement requires macOS or GNU time on Linux');
}
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'distribution-artifacts-'));
const npmCache = join(root, 'npm-cache');
const environment = {...process.env, npm_config_cache: npmCache};

function run(command, args, cwd, timeout = 30000) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result;
}

async function bytesUnder(path) {
  const entry = await stat(path);
  if (!entry.isDirectory()) return entry.size;
  let size = 0;
  for (const child of await readdir(path)) {
    size += await bytesUnder(join(path, child));
  }
  return size;
}

function measure(command, args, cwd) {
  const started = performance.now();
  const result = run('/usr/bin/time', [platform() === 'darwin' ? '-l' : '-v',
    command, ...args], cwd);
  const wallMs = performance.now() - started;
  const peak = platform() === 'darwin'
    ? result.stderr.match(/(\d+)\s+maximum resident set size/u)
    : result.stderr.match(/Maximum resident set size \(kbytes\):\s*(\d+)/u);
  if (!peak) throw new Error(`Missing process RSS:\n${result.stderr}`);
  assert.ok(Number.isFinite(wallMs) && wallMs >= 0);
  return {wall_ms: Math.round(wallMs * 100) / 100,
    peak_rss_bytes: Number(peak[1]) * (platform() === 'linux' ? 1024 : 1)};
}

const tarballs = {};
for (const name of ['client-wire', 'sdk', 'node', 'run-host-core',
  'local-node']) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
  const path = join(root, `actql-${name}-0.0.0-development.tgz`);
  const bytes = await readFile(path);
  tarballs[name] = {path, bytes: bytes.byteLength,
    sha256: createHash('sha256').update(bytes).digest('hex')};
}
const profiles = {};

// The Run Host compiler is a separate package. Measure its actual import and
// checked Values compilation without pulling it into the remote SDK.
const hostInstallation = join(root, 'install-run-host-core');
await mkdir(hostInstallation);
await writeFile(join(hostInstallation, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
  tarballs['run-host-core'].path], hostInstallation);
await writeFile(join(hostInstallation, 'values.environment.json'),
  await readFile(join(repository, 'packages/sdk/fixtures',
    'values.environment.json')));
await writeFile(join(hostInstallation, 'values.json'),
  await readFile(join(repository, 'packages/sdk/fixtures', 'values.json')));
await writeFile(join(hostInstallation, 'host-probe.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
globalThis.fetch = async () => { throw new Error('NetworkOnHostImport'); };
const {admitEnvironment, prepare, compileValues,
  privateCompilationWires} = await import('@actql/run-host-core');
const body = readFileSync('values.environment.json', 'utf8').trimEnd();
const environment = admitEnvironment(body,
  JSON.parse(body).evidence_bundle_cid, {rela: true});
const prepared = prepare(readFileSync('values.json', 'utf8'), 'json',
  environment);
const plan = JSON.parse(privateCompilationWires(
  compileValues(prepared)).executablePlan);
assert.equal(plan.version, 'actql-executable-plan/0.1');
`);
profiles.run_host_core = {
  installed_packages: ['run-host-core'],
  installed_bytes: await bytesUnder(join(hostInstallation, 'node_modules')),
  scope: 'fresh process import, checked Values compilation and exit',
  samples: Array.from({length: repetitions}, () =>
    measure(process.execPath, ['host-probe.mjs'], hostInstallation)),
};

const probe = `
import assert from 'node:assert/strict';
const packageName = process.argv[2];
globalThis.fetch = async () => { throw new Error('NetworkOnImport'); };
const {connect} = await import(packageName);
let calls = 0;
globalThis.fetch = async () => {
  calls++;
  return Response.json({version: 'actql-client-host/0.1',
    mode: 'remote', owner: 'remote', durability: 'volatile',
    scopeRef: 'measure-scope', capabilities: [],
    limits: {maxReadWireBytes: 1024, maxRowWireBytes: 512,
      maxRowRetainedValueBytes: 512, maxRetainedValueBytes: 1024,
      maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 1024}});
};
const client = await connect({mode: 'remote',
  endpoint: 'https://measure.invalid/', token: 'fixture-token'});
assert.equal(client.profile.mode, 'remote');
assert.equal(calls, 1);
client.close();
`;
for (const name of ['sdk', 'node']) {
  const installation = join(root, `install-${name}`);
  await mkdir(installation);
  await writeFile(join(installation, 'package.json'),
    '{"private":true,"type":"module"}\n');
  const install = name === 'sdk'
    ? [tarballs['client-wire'].path, tarballs.sdk.path]
    : [tarballs['client-wire'].path, tarballs.sdk.path,
      tarballs['run-host-core'].path, tarballs['local-node'].path,
      tarballs.node.path];
  run('npm', ['install', ...(name === 'sdk' ? ['--offline'] : []),
    '--ignore-scripts', '--no-save',
    ...install], installation);
  const installed = (await readdir(join(installation, 'node_modules',
    '@actql'))).sort();
  assert.deepEqual(installed, name === 'sdk'
    ? ['client-wire', 'sdk'] :
      ['client-wire', 'local-node', 'node', 'run-host-core', 'sdk']);
  await writeFile(join(installation, 'probe.mjs'), probe);
  const packageName = name === 'sdk' ? '@actql/sdk' : '@actql/node';
  profiles[name] = {installed_packages: installed,
    installed_bytes: await bytesUnder(join(installation, 'node_modules')),
    samples: Array.from({length: repetitions}, () =>
      measure(process.execPath, ['probe.mjs', packageName], installation))};
}

const localInstallation = join(root, 'install-node');
await writeFile(join(localInstallation, 'values.json'),
  await readFile(join(repository, 'packages/sdk/fixtures/values.json')));
await writeFile(join(localInstallation, 'local-probe.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {performance} from 'node:perf_hooks';
process.env.ACTQL_LOCAL_STATE_DIR = join(process.cwd(),
  process.argv[2] === 'connect' ? 'local-connect-state' : 'local-run-state');
globalThis.fetch = () => { throw new Error('NetworkOnLocalMeasurement'); };
const started = performance.now();
const {connect} = await import('@actql/node');
const imported = performance.now();
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable'});
const connected = performance.now();
let firstRunMs = null, followingRunMs = null;
if (process.argv[2] === 'run') {
  const document = readFileSync('values.json', 'utf8');
  for (const requestId of ['local-measure-first',
    'local-measure-following']) {
    const before = performance.now();
    const execution = await client.aql(document, {format: 'json', requestId});
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 1}, {id: 2}]);
    const elapsed = performance.now() - before;
    if (firstRunMs === null) firstRunMs = elapsed;
    else followingRunMs = elapsed;
  }
}
client.close();
console.log(JSON.stringify({import_ms: imported - started,
  first_local_connect_ms: connected - imported,
  first_run_to_result_ms: firstRunMs,
  following_run_to_result_ms: followingRunMs}));
`);
function measureLocal(kind) {
  const result = run('/usr/bin/time', [platform() === 'darwin' ? '-l' : '-v',
    process.execPath, 'local-probe.mjs', kind], localInstallation, 120000);
  const peak = platform() === 'darwin'
    ? result.stderr.match(/(\d+)\s+maximum resident set size/u)
    : result.stderr.match(/Maximum resident set size \(kbytes\):\s*(\d+)/u);
  if (!peak) throw new Error('Missing Local process RSS');
  return {...JSON.parse(result.stdout.trim()),
    peak_rss_bytes: Number(peak[1]) * (platform() === 'linux' ? 1024 : 1)};
}
profiles.standard_local = {
  installed_packages: profiles.node.installed_packages,
  installed_bytes: profiles.node.installed_bytes,
  scope: 'fresh packed Node process; real Local Site and named Result',
  connect_only: measureLocal('connect'),
  two_runs_one_session: measureLocal('run'),
};

// Bundle the installed remote package exactly as a browser ESM consumer would.
// The metadata must contain only the two public lightweight packages and no
// output imports, so Local kernel and native bindings cannot hide behind a
// deferred module reference.
const browser = join(root, 'actql-sdk-browser.mjs');
const browserMetadata = join(root, 'actql-sdk-browser-meta.json');
run(join(repository, 'node_modules/.bin/esbuild'), [
  join(root, 'install-sdk/node_modules/@actql/sdk/index.mjs'),
  '--bundle', '--platform=browser', '--format=esm', '--target=es2022',
  `--outfile=${browser}`, `--metafile=${browserMetadata}`,
], root);
const bundleMap = JSON.parse(await readFile(browserMetadata, 'utf8'));
const browserInputs = Object.keys(bundleMap.inputs).sort();
assert(browserInputs.length >= 2 && browserInputs.every(path =>
  /node_modules\/@actql\/(?:sdk|client-wire)\//u.test(path)));
assert(Object.values(bundleMap.outputs).every(output =>
  output.imports.length === 0));
await writeFile(join(root, 'browser-probe.mjs'), probe);
run(process.execPath, ['browser-probe.mjs', './actql-sdk-browser.mjs'], root);
const browserBytes = await readFile(browser);

const nativeBytes = await readFile(native);
const nativeSamples = Array.from({length: repetitions}, () =>
  measure(native, ['--help'], root));
const report = {
  format: 'actql-distribution-artifacts/0.1',
  source_sha: run('git', ['rev-parse', 'HEAD'], repository).stdout.trim(),
  working_tree_status: run('git', ['status', '--porcelain'],
    repository).stdout.trim(),
  host: {platform: platform(), arch: arch(), release: release(),
    node: process.version},
  scope: 'fresh packed process measurements; remote samples use a local ' +
    'response fixture; standard Local samples execute a real checked Values ' +
    'Site and read its named Result without network; no build time',
  repetitions,
  tarballs,
  profiles,
  browser_esm: {
    bytes: browserBytes.byteLength,
    gzip_bytes: gzipSync(browserBytes).byteLength,
    sha256: createHash('sha256').update(browserBytes).digest('hex'),
    inputs: browserInputs,
    output_imports: 0,
    smoke: 'fixture connect after import without network during import',
  },
  native_cli: {bytes: nativeBytes.byteLength,
    sha256: createHash('sha256').update(nativeBytes).digest('hex'),
    scope: 'fresh process --help only', samples: nativeSamples},
};
const output = join(build, 'distribution-artifacts-measurement.json');
await writeFile(output, `${JSON.stringify(report, null, 2)}\n`);
console.log(output);
