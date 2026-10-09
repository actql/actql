// Finite Run-scoped approval acceptance through fixed, installed public packages.
// The existing fixture's reduced profile retains one success, refusal, cancel
// and lost-response recovery; it does not repeat its provider-position matrix.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
assert(process.argv[2], 'usage: test-package-release-effect.mjs <fixed-RC>');
const directory = resolve(process.argv[2]), manifest = await verifyPackageRelease(directory);
const fixtureSourceSha = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
const runtimeSourceDelta = execFileSync('git', ['diff', '--name-only', manifest.sourceSha, fixtureSourceSha,
  '--', 'src', 'adapters', 'spec', 'packages', 'moon.mod', 'toolchain.json'], {cwd: repository, encoding: 'utf8'}).trim();
assert.equal(runtimeSourceDelta, '', 'Retained RC requires unchanged installed runtime/package inputs');
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-release-effect-', label: 'Run-scoped installed approval'});
const registry = await openReleaseTestRegistry([{directory, manifest}]);
const root = scratch.path, records = [], fixtureDigests = {};
await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
await writeFile(join(root, 'npmrc-global'), '');
const env = {...process.env, npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
  npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
  npm_config_proxy: '', npm_config_https_proxy: '', NO_PROXY: '127.0.0.1,localhost', npm_config_update_notifier: 'false'};
delete env.NODE_PATH;
async function run(command, args) {
  const started = Date.now();
  const record = await new Promise((resolve, reject) => {
    const child = spawn(command, args, {cwd: root, env, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '';
    const timer = setTimeout(() => child.kill('SIGTERM'), 120000);
    child.stdout.on('data', bytes => {stdout += bytes;}); child.stderr.on('data', bytes => {stderr += bytes;});
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {clearTimeout(timer); resolve({command, args, code, signal, stdout, stderr, elapsedMs: Date.now() - started});});
  });
  records.push(record); assert.equal(record.code, 0, JSON.stringify(record));
  console.log(record.stdout.trimEnd()); return record;
}
try {
  await run('npm', ['install', '--no-audit', '--no-fund', `@actql/node@${manifest.cohort.packageVersion}`]);
  for (const path of ['scripts/fixtures/installed-effect-inventory-acceptance.mjs',
    'adapters/site-node/https-exchange-fixture.mjs', 'adapters/connectors/github/test/github-graphql.fixture.mjs']) {
    const target = join(root, path); await mkdir(dirname(target), {recursive: true});
    await copyFile(join(repository, path), target);
    const source = await readFile(join(repository, path)); assert.deepEqual(await readFile(target), source);
    fixtureDigests[path] = createHash('sha256').update(source).digest('hex');
  }
  await writeFile(join(root, 'approval.mjs'), `import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {publishEffect} from '@actql/local-node';
import {runInstalledEffectInventoryAcceptance} from './scripts/fixtures/installed-effect-inventory-acceptance.mjs';
const result = await runInstalledEffectInventoryAcceptance({connect, openInstalledRemoteHttpHost, publishEffect, profile:'observability'});
console.log('RELEASE_RUN_APPROVAL', JSON.stringify(result));\n`);
  const observed = await run(process.execPath, ['approval.mjs']);
  const result = JSON.parse(observed.stdout.match(/RELEASE_RUN_APPROVAL (.+)/u)?.[1]);
  assert.equal(result.successfulPluralRuns, 1); assert.equal(result.preparationRefusals, 2);
  assert.equal(result.cancelledWithoutSend, 1); assert.equal(result.unknownAfterRestart, 1);
  await writeFile(join(directory, `approval-${process.platform}-${process.arch}-${Date.now()}.json`), JSON.stringify({
    version:'actql-release-run-approval-acceptance/0.1', artifactSourceSha:manifest.sourceSha, fixtureSourceSha,
    runtimeSourceDelta:[], node:process.version, platform:process.platform, arch:process.arch,
    artifacts:manifest.packages.map(({name,version,sha256})=>({name,version,sha256})),
    fixtureDigests, profile:'existing-reduced-observability-lifecycle', provider:'local-independent-HTTPS-fixture',
    publicServiceWrite:false, result, records}, null, 2)+'\n', {flag:'wx'});
  scratch.passed();
} finally {await registry.close();}
