// Consumer-only release entry. It never packs packages or supplies product
// runtime files; npm installs the four unmodified archives through a registry.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {selectReleaseSourcefreeQueryCases} from './release-sourcefree-query-cases.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [input, receiptPath, ...extra] = process.argv.slice(2);
assert(input && receiptPath && extra.length === 0 && isAbsolute(receiptPath),
  'usage: test-package-release-sourcefree-query.mjs <fixed-RC> <new-absolute-receipt.json>');
const directory = resolve(input), manifest = await verifyPackageRelease(directory);
assert.deepEqual(manifest.cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
assert.ok(!resolve(receiptPath).startsWith(directory + '/'), 'Keep the original RC unchanged');
const source = checkoutState(repository);
assert(source.clean, 'Release case fixtures require clean committed source');
execFileSync('git', ['--no-replace-objects', 'merge-base', '--is-ancestor', manifest.sourceSha, source.revision],
  {cwd: repository});
const runtimeSourceDelta = execFileSync('git', ['--no-replace-objects', 'diff', '--name-only',
  manifest.sourceSha, source.revision, '--', 'src', 'adapters', 'spec', 'packages',
  'moon.mod', 'moon.lock', 'toolchain.json', 'package.json', 'package-lock.json'],
{cwd: repository, encoding: 'utf8'}).trim();
assert.equal(runtimeSourceDelta, '', 'Retained RC runtime/package inputs differ from fixture source');
const cases = selectReleaseSourcefreeQueryCases();
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-release-sourcefree-',
  label: 'Installed source-free query acceptance'});
const registry = await openReleaseTestRegistry([{directory, manifest}]);
const root = scratch.path, records = [], fixtureDigests = {};
const env = {...process.env, npm_config_registry: registry.url,
  npm_config_cache: join(root, 'npm-cache'), npm_config_userconfig: join(root, 'npmrc'),
  npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_update_notifier: 'false',
  npm_config_proxy: '', npm_config_https_proxy: '', NO_PROXY: '127.0.0.1,localhost'};
for (const key of ['NODE_PATH', 'ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE',
  'ACTQL_PACKED_CLIENT_PACKAGES', 'ACTQL_TEST_NPM_CACHE']) delete env[key];
async function run(command, args) {
  const started = Date.now();
  const record = await new Promise((resolve, reject) => {
    const child = spawn(command, args, {cwd: root, env, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', bytes = 0;
    const timer = setTimeout(() => child.kill('SIGTERM'), 180000);
    for (const [stream, append] of [[child.stdout, value => {stdout += value;}],
      [child.stderr, value => {stderr += value;}]]) stream.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024) child.kill('SIGTERM'); else append(chunk.toString());
    });
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {clearTimeout(timer);
      resolve({command, args, code, signal, stdout, stderr, elapsedMs: Date.now() - started});});
  });
  records.push(record);
  assert.equal(record.code, 0, JSON.stringify(record));
  console.log(record.stdout.trimEnd());
}
try {
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  await writeFile(env.npm_config_userconfig, `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
  await writeFile(env.npm_config_globalconfig, '');
  await run('npm', ['install', '--no-audit', '--no-fund', `@actql/node@${manifest.cohort.packageVersion}`]);
  auditPackedPackages(root, manifest.cohort.packages);
  // These are test code and independent input fixtures only. Nothing is
  // copied into node_modules, and no adapter/Store/runtime is supplied later.
  for (const path of ['scripts/release-sourcefree-query-cases.mjs',
    'scripts/fixtures/release-sourcefree-query.mjs', 'scripts/fixtures/release-sourcefree-io.mjs',
    'scripts/fixtures/in-unnest-literal-array-source-input.mjs', 'scripts/fixtures/public-query-input.mjs']) {
    const target = join(root, path); await mkdir(dirname(target), {recursive: true});
    await copyFile(join(repository, path), target);
    const bytes = await readFile(join(repository, path));
    assert.deepEqual(await readFile(target), bytes);
    fixtureDigests[path] = createHash('sha256').update(bytes).digest('hex');
  }
  await run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);
  env.NODE_EXTRA_CA_CERTS = join(root, 'remote.crt');
  const transports = [];
  for (const mode of ['local', 'https']) {
    await run(process.execPath, ['scripts/fixtures/release-sourcefree-query.mjs', mode]);
    const observed = JSON.parse(await readFile(join(root, `sourcefree-${mode}.json`), 'utf8'));
    assert.deepEqual(observed.successNames, cases.successes.map(value => value.name));
    assert.deepEqual(observed.refusalNames, cases.refusals.map(value => value.name));
    transports.push(observed);
  }
  await verifyPackageRelease(directory);
  assert.deepEqual(checkoutState(repository), source, 'Fixture source changed');
  await writeFile(receiptPath, JSON.stringify({artifactSourceSha: manifest.sourceSha,
    fixtureSourceSha: source.revision, runtimeSourceDelta: [], fixtureDigests,
    artifacts: manifest.packages.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity})),
    transports, records, publicPublication: false}, null, 2) + '\n', {flag: 'wx'});
  scratch.passed();
} finally {await registry.close();}
