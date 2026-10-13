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
import {releaseVectorScalarEnvironment} from './release-vector-scalar-fixtures.mjs';
import {selectInstalledSourcefreeQuerySuite, releaseSourcefreeFixturePaths}
  from './release-sourcefree-query-cases.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [input, receiptPath, ...extra] = process.argv.slice(2);
assert(input && receiptPath && (extra.length === 0 ||
  extra.length === 1 && ['--sequence-only', '--time-series-only', '--temporal-join-only'].includes(extra[0])) && isAbsolute(receiptPath),
  'usage: test-package-release-sourcefree-query.mjs <fixed-RC> <new-absolute-receipt.json> [--sequence-only|--time-series-only|--temporal-join-only]');
const suite = extra.length === 0 ? 'in-unnest' :
  {'--sequence-only': 'sequence', '--time-series-only': 'time-series', '--temporal-join-only': 'temporal-join'}[extra[0]];
const freshProcessReread = suite === 'time-series' || suite === 'temporal-join';
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
const cases = selectInstalledSourcefreeQuerySuite(suite);
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-release-sourcefree-',
  label: 'Installed source-free query acceptance'});
const registry = await openReleaseTestRegistry([{directory, manifest}]);
const root = scratch.path, records = [], fixtureDigests = {}, transports = [];
const env = releaseVectorScalarEnvironment(process.env, {registry: registry.url, root, node: process.execPath});
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
let primary;
try {
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  await writeFile(env.npm_config_userconfig, `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
  await writeFile(env.npm_config_globalconfig, '');
  await run('npm', ['install', '--no-audit', '--no-fund', `@actql/node@${manifest.cohort.packageVersion}`]);
  auditPackedPackages(root, manifest.cohort.packages);
  // These are test code and independent input fixtures only. Nothing is
  // copied into node_modules, and no adapter/Store/runtime is supplied later.
  for (const path of releaseSourcefreeFixturePaths) {
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
  for (const mode of ['local', 'https']) {
    await run(process.execPath, ['scripts/fixtures/release-sourcefree-query.mjs', mode, suite]);
    const observed = JSON.parse(await readFile(join(root, `sourcefree-${mode}.json`), 'utf8'));
    assert.equal(observed.suite, suite);
    assert.equal(observed.complete, true);
    assert.deepEqual(observed.successNames, cases.successes.map(value => value.name));
    assert.deepEqual(observed.refusalNames, cases.refusals.map(value => value.name));
    if (freshProcessReread) {
      await run(process.execPath, ['scripts/fixtures/release-time-series-reread.mjs', mode, suite]);
      const reread = JSON.parse(await readFile(join(root, `sourcefree-reread-${mode}.json`), 'utf8'));
      assert.equal(reread.complete, true);
      assert.deepEqual(reread.completed.map(item => item.name), cases.successes.map(item => item.name));
      observed.freshProcessReread = reread;
    }
    transports.push(observed);
  }
  await verifyPackageRelease(directory);
  assert.deepEqual(checkoutState(repository), source, 'Fixture source changed');
} catch (error) {
  primary = error;
} finally {
  try {await registry.close();}
  catch (error) {primary ??= error;}
  for (const mode of ['local', 'https']) {
    if (transports.some(value => value.mode === mode)) continue;
    try {
      const observed = JSON.parse(await readFile(join(root, `sourcefree-${mode}.json`), 'utf8'));
      if (freshProcessReread) {
        try {observed.freshProcessReread = JSON.parse(await readFile(join(root, `sourcefree-reread-${mode}.json`), 'utf8'));}
        catch (error) {if (error.code !== 'ENOENT') throw error;}
      }
      transports.push(observed);
    }
    catch (error) {if (error.code !== 'ENOENT') primary ??= error;}
  }
  await writeFile(receiptPath, JSON.stringify({suite, complete: primary === undefined,
    artifactSourceSha: manifest.sourceSha,
    fixtureSourceSha: source.revision, runtimeSourceDelta: [], fixtureDigests,
    artifacts: manifest.packages.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity})),
    transports, records, retainedConsumer: root, publicPublication: false}, null, 2) + '\n', {flag: 'wx'});
  if (primary === undefined) scratch.passed();
}
if (primary !== undefined) throw primary;
