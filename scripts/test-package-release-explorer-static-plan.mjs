// Consumer-only: serve exact retained archives through the existing loopback
// registry, then install the public Explorer entry into an empty environment.
// Never rebuild, rewrite a manifest, or overlay installed product adapters.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';

const [releaseInput, evidenceInput] = process.argv.slice(2);
assert(releaseInput && evidenceInput && process.argv.length === 4,
  'usage: test-package-release-explorer-static-plan.mjs <release-directory> <new-evidence-directory>');
assert.equal(process.version, 'v22.22.0');
assert(process.env.ACTQL_TEST_PLAYWRIGHT_MODULE && process.env.ACTQL_TEST_BROWSER_EXECUTABLE,
  'Explicit test-only browser tooling required');
const repository = fileURLToPath(new URL('../', import.meta.url));
const release = resolve(releaseInput), evidence = resolve(evidenceInput);
await mkdir(evidence, {recursive: true});
const manifest = await verifyPackageRelease(release);
assert.deepEqual([...manifest.cohort.packages].sort(),
  ['client-wire', 'sdk', 'local-node', 'node', 'explorer-ui', 'explorer'].sort());
const scratch = await createOwnedScratch({parent: '/private/tmp', prefix: 'actql-installed-static-effect-',
  label: 'installed static Effectful Plan'});
const consumer = scratch.path;
const registry = await openReleaseTestRegistry([{directory: release, manifest}]);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const receipt = {source: manifest.sourceSha, consumer, node: process.version, platform: process.platform,
  arch: process.arch, compiler: 0, producer: 0, normalNpmPublish: false, complete: false,
  manifestSha256: hash(await readFile(join(release, 'release.json'))),
  packages: manifest.packages.map(({name, file, sha256, integrity}) => ({name, file, sha256, integrity})),
  commands: [], children: [], cleanup: []};
const env = {PATH: `${dirname(process.execPath)}:/usr/bin:/bin:/usr/sbin:/sbin`,
  HOME: join(consumer, 'home'), TMPDIR: join(consumer, 'tmp'),
  npm_config_cache: join(consumer, 'npm-cache'), npm_config_userconfig: join(consumer, 'npmrc'),
  npm_config_globalconfig: join(consumer, 'npmrc-global'), npm_config_update_notifier: 'false',
  ACTQL_TEST_PLAYWRIGHT_MODULE: process.env.ACTQL_TEST_PLAYWRIGHT_MODULE,
  ACTQL_TEST_BROWSER_EXECUTABLE: process.env.ACTQL_TEST_BROWSER_EXECUTABLE,
  ACTQL_TEST_EVIDENCE_DIRECTORY: evidence};
await mkdir(env.HOME); await mkdir(env.TMPDIR);
await writeFile(env.npm_config_userconfig, `registry=https://registry.npmjs.org/\n@actql:registry=${registry.url}\n`);
await writeFile(env.npm_config_globalconfig, '');
await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
async function run(command, args, timeout) {
  const started = Date.now();
  const child = spawn(command, args, {cwd: consumer, env, stdio: ['ignore', 'pipe', 'pipe']});
  receipt.children.push(child.pid);
  let stdout = '', stderr = '', bytes = 0, timedOut = false, overflow = false, hard;
  const stop = () => {child.kill('SIGTERM'); hard ??= setTimeout(() => child.kill('SIGKILL'), 5000);};
  const timer = setTimeout(() => {timedOut = true; stop();}, timeout);
  for (const [stream, append] of [[child.stdout, b => stdout += b], [child.stderr, b => stderr += b]]) {
    stream.on('data', chunk => {
      bytes += chunk.byteLength;
      if (bytes > 8388608) {overflow = true; stop();} else append(chunk.toString());
    });
  }
  let result;
  try {result = await new Promise((resolve, reject) => {
    child.once('error', reject); child.once('close', (code, signal) => resolve({code, signal}));
  });} finally {clearTimeout(timer); clearTimeout(hard);}
  receipt.commands.push({command, args, elapsedMs: Date.now() - started, ...result, timedOut, overflow, stdout, stderr});
  process.stdout.write(stdout); process.stderr.write(stderr);
  assert(!timedOut && !overflow && result.code === 0 && result.signal === null, 'InstalledStaticPlanCommandFailed');
  return stdout;
}
try {
  await run('npm', ['install', '--no-audit', '--no-fund', `@actql/explorer@${manifest.cohort.packageVersion}`], 180000);
  assert.deepEqual((await readdir(join(consumer, 'node_modules/@actql'))).sort(), [...manifest.cohort.packages].sort());
  auditPackedPackages(consumer, manifest.cohort.packages);
  for (const name of manifest.cohort.packages) {
    const metadata = JSON.parse(await readFile(join(consumer, 'node_modules/@actql', name, 'package.json')));
    assert.equal(metadata.version, manifest.cohort.packageVersion);
    for (const section of ['dependencies', 'peerDependencies', 'optionalDependencies']) {
      for (const [name, value] of Object.entries(metadata[section] ?? {})) {
        assert(!/^(?:file:|link:|workspace:)/u.test(value));
        if (name.startsWith('@actql/')) assert.equal(value, manifest.cohort.packageVersion);
      }
    }
  }
  assert(manifest.packages.every(item => registry.requested.includes(`archives/${item.file}`)));
  receipt.registryRequests = [...registry.requested];
  receipt.reactTree = JSON.parse(await run('npm', ['ls', 'react', 'react-dom', '--all', '--json'], 15000));
  receipt.packageLockSha256 = hash(await readFile(join(consumer, 'package-lock.json')));
  for (const path of ['scripts/fixtures/packed-explorer-effectful-static-plan.mjs',
    'adapters/site-node/https-exchange-fixture.mjs']) {
    const target = join(consumer, path);
    await mkdir(resolve(target, '..'), {recursive: true}); await copyFile(join(repository, path), target);
  }
  await run(process.execPath, ['--test', '--test-concurrency=1', 'scripts/fixtures/packed-explorer-effectful-static-plan.mjs'], 120000);
  const actual = JSON.parse(await readFile(join(evidence, 'installed-effectful-static-plan-receipt.json')));
  assert(actual.complete && actual.cases.length === 1 && actual.cases.every(item => item.passed));
  assert.equal(actual.newRuns, 0); assert.equal(actual.newSubmissions, 0); assert.equal(actual.ProviderIOWhilePlanning, 0);
  receipt.actualNewInstalledScenarios = 1; receipt.complete = true;
} catch (error) {receipt.failure = {kind: error.name, message: error.message}; process.exitCode = 1;}
finally {
  try {await registry.close(); receipt.cleanup.push({name: 'registry', acknowledged: true});}
  catch {receipt.complete = false; process.exitCode = 1; receipt.cleanup.push({name: 'registry', acknowledged: false});}
  await writeFile(join(evidence, 'consumer-receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
  if (receipt.complete) {scratch.passed(); console.log('Installed Effectful static Plan scenario passed: 1');}
}
