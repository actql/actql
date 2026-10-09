// A private loopback registry serves the exact RC bytes. Consumers name only
// their public entry package; npm must resolve the complete dependency closure.
// This proves registry installation mechanics, not public npm publication.
import assert from 'node:assert/strict';
import {spawn, execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const input = process.argv[2];
assert(input, 'usage: test-package-release-install.mjs <RC-directory>');
const directory = resolve(input), manifest = await verifyPackageRelease(directory);
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-release-install-',
  label: 'fixed release registry installation'});
const root = scratch.path, requested = [];
const artifacts = await Promise.all(manifest.packages.map(async item => ({item,
  metadata: JSON.parse(execFileSync('tar', ['-xOf', join(directory, item.file), 'package/package.json'], {encoding: 'utf8'})),
  bytes: await readFile(join(directory, item.file))})));
const registry = createServer((request, response) => {
  try {
    assert.equal(request.method, 'GET', 'Read-only acceptance registry');
    const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).slice(1);
    requested.push(path);
    const archive = artifacts.find(v => path === `archives/${v.item.file}`);
    if (archive) {
      response.writeHead(200, {'content-type': 'application/octet-stream'}); response.end(archive.bytes); return;
    }
    const artifact = artifacts.find(v => path === v.item.name || path === `${v.item.name}/${v.item.version}`);
    if (!artifact) {response.writeHead(404); response.end('{}'); return;}
    const metadata = {...artifact.metadata, dist: {integrity: artifact.item.integrity,
      tarball: `${registryUrl}archives/${artifact.item.file}`}};
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify(path === artifact.item.name ? {name: artifact.item.name,
      'dist-tags': {latest: artifact.item.version}, versions: {[artifact.item.version]: metadata}} : metadata));
  } catch {response.writeHead(400); response.end('{}');}
});
await new Promise((resolve, reject) => {registry.once('error', reject); registry.listen(0, '127.0.0.1', resolve);});
const registryUrl = `http://127.0.0.1:${registry.address().port}/`;
const environment = {...process.env, npm_config_registry: registryUrl,
  npm_config_cache: join(root, 'npm-cache'), npm_config_update_notifier: 'false'};
environment.npm_config_userconfig = join(root, 'npmrc');
environment.npm_config_globalconfig = join(root, 'npmrc-global');
await writeFile(environment.npm_config_userconfig, `registry=${registryUrl}\n@actql:registry=${registryUrl}\n`);
await writeFile(environment.npm_config_globalconfig, '');
environment.npm_config_proxy = '';
environment.npm_config_https_proxy = '';
environment.NO_PROXY = '127.0.0.1,localhost';
delete environment.NODE_PATH;
delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
delete environment.ACTQL_LOCAL_EFFECT_PROFILE;
async function run(command, args, cwd) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const process = spawn(command, args, {cwd, env: environment, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', bytes = 0;
    const timer = setTimeout(() => {process.kill('SIGTERM');}, 180_000);
    for (const [stream, append] of [[process.stdout, s => {stdout += s;}], [process.stderr, s => {stderr += s;}]]) stream.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024) process.kill('SIGTERM'); else append(chunk.toString());
    });
    process.once('error', error => {clearTimeout(timer); reject(error);});
    process.once('close', (code, signal) => {
      clearTimeout(timer);
      if (code !== 0) {reject(Error(`${command} ${args.join(' ')}: ${code}/${signal}\n${stdout}\n${stderr}`)); return;}
      console.log(stdout.trimEnd()); resolve({command, args, code, elapsedMs: Date.now()-started, stdout});
    });
  });
}
const results = [];
try {
  for (const entry of ['node', 'sdk']) {
    const consumer = join(root, entry); await mkdir(consumer);
    await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
    results.push(await run('npm', ['install', '--no-audit', '--no-fund',
      `@actql/${entry}@${manifest.cohort.packageVersion}`], consumer));
    const names = entry === 'node' ? manifest.cohort.packages : ['client-wire', 'sdk'];
    const {readdir} = await import('node:fs/promises');
    assert.deepEqual((await readdir(join(consumer, 'node_modules/@actql'))).sort(), [...names].sort());
    for (const name of names) {
      const metadata = JSON.parse(await readFile(join(consumer, 'node_modules/@actql', name, 'package.json'), 'utf8'));
      assert.equal(metadata.version, manifest.cohort.packageVersion);
    }
    auditPackedPackages(consumer, names);
  }
  const local = join(root, 'node');
  const localReadme = await readFile(join(local, 'node_modules/@actql/node/README.md'), 'utf8');
  const localExample = /## Short Local queries[\s\S]*?```js\n([\s\S]*?)```/u.exec(localReadme)?.[1];
  assert(localExample, 'Missing standalone Local README example');
  await writeFile(join(local, 'readme-example.mjs'), localExample);
  const readmeResult = await run(process.execPath, ['readme-example.mjs'], local);
  assert.equal(readmeResult.stdout.trim(), '[ { id: 1 } ]', 'Independent README result');
  results.push(readmeResult);
  await copyFile(join(repository, 'packages/sdk/fixtures/values.json'), join(local, 'values.json'));
  await copyFile(join(repository, 'scripts/fixtures/packed-local-without-duckdb.mjs'), join(local, 'acceptance.mjs'));
  results.push(await run(process.execPath, ['acceptance.mjs', 'initial'], local));
  results.push(await run(process.execPath, ['acceptance.mjs', 'restart'], local));
  await copyFile(join(repository, 'scripts/fixtures/packed-short-queries.mjs'), join(local, 'short-queries.mjs'));
  await copyFile(join(repository, 'scripts/fixtures/packed-short-queries.typecheck.mts'), join(local, 'short-queries.typecheck.mts'));
  results.push(await run(process.execPath, [join(repository, 'node_modules/typescript/bin/tsc'),
    '--strict', '--target', 'ES2022', '--module', 'NodeNext', '--moduleResolution', 'NodeNext',
    '--noEmit', 'short-queries.typecheck.mts'], local));
  results.push(await run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], local));
  environment.NODE_EXTRA_CA_CERTS = join(local, 'remote.crt');
  await copyFile(join(repository, 'scripts/fixtures/release-sdk-only.mjs'), join(root, 'sdk/remote-acceptance.mjs'));
  environment.ACTQL_SDK_ONLY_ACCEPTANCE = join(root, 'sdk/remote-acceptance.mjs');
  results.push(await run(process.execPath, ['short-queries.mjs'], local));
  assert(manifest.packages.every(v => requested.includes(`archives/${v.file}`)));
  const receipt = {version: 'actql-release-install-acceptance/0.1', sourceSha: manifest.sourceSha,
    artifacts: manifest.packages.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity})),
    consumer: root, node: process.version, platform: process.platform, arch: process.arch,
    registry: 'private-loopback-fixed-RC', publicRegistryPublication: 'not-tested', results};
  await writeFile(join(directory, `install-${process.platform}-${process.arch}-${Date.now()}.json`),
    `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  scratch.passed();
  console.log(`Fixed RC clean installation passed: ${root}`);
} finally {await new Promise(resolve => registry.close(resolve));}
