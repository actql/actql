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
for (const name of ['sdk', 'node']) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
  const path = join(root, `actql-${name}-0.0.0-development.tgz`);
  const bytes = await readFile(path);
  tarballs[name] = {path, bytes: bytes.byteLength,
    sha256: createHash('sha256').update(bytes).digest('hex')};
}

const probe = `
import assert from 'node:assert/strict';
const packageName = process.argv[2];
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
const profiles = {};
for (const name of ['sdk', 'node']) {
  const installation = join(root, `install-${name}`);
  await mkdir(installation);
  await writeFile(join(installation, 'package.json'),
    '{"private":true,"type":"module"}\n');
  const install = name === 'sdk' ? [tarballs.sdk.path] :
    [tarballs.sdk.path, tarballs.node.path];
  run('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
    ...install], installation);
  const installed = (await readdir(join(installation, 'node_modules',
    '@actql'))).sort();
  assert.deepEqual(installed, name === 'sdk' ? ['sdk'] : ['node', 'sdk']);
  await writeFile(join(installation, 'probe.mjs'), probe);
  const packageName = name === 'sdk' ? '@actql/sdk' : '@actql/node';
  profiles[name] = {installed_packages: installed,
    installed_bytes: await bytesUnder(join(installation, 'node_modules')),
    samples: Array.from({length: repetitions}, () =>
      measure(process.execPath, ['probe.mjs', packageName], installation))};
}

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
  scope: 'fresh process startup, module import, fixture connect and exit; ' +
    'parent-observed wall time includes the time wrapper; peak process RSS; ' +
    'no provider, Site, network or build time',
  repetitions,
  tarballs,
  profiles,
  native_cli: {bytes: nativeBytes.byteLength,
    sha256: createHash('sha256').update(nativeBytes).digest('hex'),
    scope: 'fresh process --help only', samples: nativeSamples},
};
const output = join(build, 'distribution-artifacts-measurement.json');
await writeFile(output, `${JSON.stringify(report, null, 2)}\n`);
console.log(output);
