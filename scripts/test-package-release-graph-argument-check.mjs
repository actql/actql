// Consumer only. The four product archives are installed normally and remain immutable.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyPackageRelease} from './package-release.mjs';
import {checkoutState, pinnedDuckDBPackage} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {releaseVectorScalarEnvironment} from './release-vector-scalar-fixtures.mjs';
import {releaseGraphCheckFixturePaths} from './release-graph-argument-check-cases.mjs';
import {requireGraphArgumentCheckReport} from './fixtures/graph-argument-check.mjs';
import {createTransportOwner} from './fixtures/packed-query-transport-owner.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [input, receiptPath, ...extra] = process.argv.slice(2);
assert(input && receiptPath && extra.length === 0 && isAbsolute(receiptPath),
  'usage: test-package-release-graph-argument-check.mjs <fixed-RC> <new-absolute-receipt.json>');
assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1', 'Keep actual Run/DB and unknown attempts');
const directory = resolve(input), manifest = await verifyPackageRelease(directory);
assert.deepEqual(manifest.cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
assert.ok(!resolve(receiptPath).startsWith(directory + '/'));
const source = checkoutState(repository); assert(source.clean);
// Existing Graph CHECK test dependency, not another ActQL package or runtime overlay.
const duckdbPackage = await pinnedDuckDBPackage(repository);
const duckdbLock = JSON.parse(await readFile(join(repository,
  'adapters/connectors/duckdb/node/package-lock.json'), 'utf8'));
execFileSync('git', ['--no-replace-objects', 'merge-base', '--is-ancestor', manifest.sourceSha, source.revision], {cwd: repository});
assert.equal(execFileSync('git', ['--no-replace-objects', 'diff', '--name-only', manifest.sourceSha,
  source.revision, '--', 'src', 'adapters', 'spec', 'packages', 'moon.mod', 'moon.lock',
  'toolchain.json', 'package.json', 'package-lock.json'], {cwd: repository, encoding: 'utf8'}).trim(), '',
  'Retained RC runtime/package inputs differ from fixture source');
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-release-graph-check-',
  label: 'Installed Graph CHECK acceptance'});
const root = scratch.path, fixtureDigests = {}, transports = [];
const registry = await openReleaseTestRegistry([{directory, manifest}]);
const env = {...releaseVectorScalarEnvironment(process.env, {registry: registry.url, root, node: process.execPath}),
  npm_config_registry: manifest.cohort.registry};
// Preserve the ordinary consumer's single shared 180-second inner budget.
const owner = createTransportOwner({deadline: Date.now() + 180000, timeoutMs: 180000, env});
let primary;
try {
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  await writeFile(env.npm_config_userconfig,
    `registry=${manifest.cohort.registry}\n@actql:registry=${registry.url}\n`);
  await writeFile(env.npm_config_globalconfig, '');
  await owner.run([{name: 'registry-install-node', command: 'npm',
    args: ['install', '--no-audit', '--no-fund', `@actql/node@${manifest.cohort.packageVersion}`, duckdbPackage], cwd: root}]);
  const installedLock = JSON.parse(await readFile(join(root, 'package-lock.json'), 'utf8'));
  for (const [path, expected] of Object.entries(duckdbLock.packages)) if (path.startsWith('node_modules/@duckdb/')) {
    assert.equal(installedLock.packages[path]?.version, expected.version, `Pinned Graph CHECK dependency: ${path}`);
    assert.equal(installedLock.packages[path]?.integrity, expected.integrity, `Pinned Graph CHECK integrity: ${path}`);
  }
  auditPackedPackages(root, manifest.cohort.packages);
  for (const path of releaseGraphCheckFixturePaths) {
    const target = join(root, path); await mkdir(dirname(target), {recursive: true});
    await copyFile(join(repository, path), target);
    const bytes = await readFile(join(repository, path)); assert.deepEqual(await readFile(target), bytes);
    fixtureDigests[path] = createHash('sha256').update(bytes).digest('hex');
  }
  await owner.run([{name: 'fixture-https-certificate', command: 'openssl',
    args: ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'remote.key',
      '-out', 'remote.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], cwd: root}]);
  for (const [transport, mode] of [['local', 'local'], ['remote', 'https']]) {
    await owner.run([{name: `graph-check-${mode}`, cwd: root,
      args: [join(root, 'scripts/fixtures/release-graph-argument-check-worker.mjs')],
      environment: {ACTQL_TEST_QUERY_TRANSPORT: transport, NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')}}]);
    const observed = JSON.parse(await readFile(join(root, `graph-argument-check-${transport}.json`), 'utf8'));
    requireGraphArgumentCheckReport(observed, transport);
    transports.push(observed);
  }
  await verifyPackageRelease(directory);
  assert.deepEqual(checkoutState(repository), source);
  owner.check();
} catch (error) { primary = error; }
finally {
  try { owner.close(); } catch (error) { primary ??= error; }
  try { await registry.close(); } catch (error) { primary ??= error; }
  for (const mode of ['local', 'remote']) {
    if (transports.some(item => item.mode === mode)) continue;
    try { transports.push(JSON.parse(await readFile(join(root, `graph-argument-check-${mode}.json`), 'utf8'))); }
    catch (error) { if (error.code !== 'ENOENT') primary ??= error; }
  }
  await writeFile(receiptPath, JSON.stringify({artifactSourceSha: manifest.sourceSha,
    fixtureSourceSha: source.revision, consumerDirectory: root, fixtureDigests,
    testDependency: {package: duckdbPackage, lockSHA256: createHash('sha256').update(
      await readFile(join(repository, 'adapters/connectors/duckdb/node/package-lock.json'))).digest('hex')},
    artifacts: manifest.packages.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity})),
    qualification: 'Checking only; no Run admission, dispatch, physical reservation or Source I/O. No Graph execution rows or arbitrary Provider/filesystem coverage.',
    transports, processReceipt: owner.report(), complete: primary === undefined,
    primaryError: primary?.message, publicPublication: false}, null, 2) + '\n', {flag: 'wx'});
}
if (primary !== undefined) throw primary;
scratch.passed();
