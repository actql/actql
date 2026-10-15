// One normal installed Local scenario. This is neither a producer nor a
// development-package fallback; its external scope is supplied explicitly.
import assert from 'node:assert/strict';
import {spawnSync, execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile, lstat} from 'node:fs/promises';
import {dirname, isAbsolute, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {admitCompositionRelease} from './composition-release-input.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {assertTestExecution, nodeTestArguments} from './test-execution.mjs';
import {checkGcsMetadataAcceptanceEnvironment} from './gcs-files-content-credential.mjs';
import {realCrossConnectorFixturePaths, realCrossConnectorEnvironment} from './real-cross-connector-fixtures.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
const [source, directory, python, scopeFile, ...extra] = process.argv.slice(2);
assert.equal(extra.length, 0); assert.equal(process.version, 'v22.22.0');
assert([directory, python, scopeFile].every(isAbsolute));
assert(!process.env.NODE_OPTIONS && !process.env.NODE_PATH, 'Unreviewed loader/runtime path');
const repository = fileURLToPath(new URL('../', import.meta.url));
const before = checkoutState(repository);
assert.equal(before.revision, source); assert(before.clean);
const scopeStat = await lstat(scopeFile); assert(scopeStat.isFile() && !scopeStat.isSymbolicLink());
const scopeWire = await readFile(scopeFile);
const manifest = checkGcsMetadataAcceptanceEnvironment(JSON.parse(scopeWire));
assert.equal(manifest.project, 'test-for-smooth'); assert.equal(manifest.bucket, 'actql-content-test');
assert.equal(manifest.prefix, 'actql-content-test/');
assert.deepEqual(manifest.expectedObjects, ['actql-content-test/a.csv']);
const release = await admitCompositionRelease({repository, directory});
const scratch = await createOwnedScratch({parent: join(repository, '..', '.codex-scratch'),
  prefix: 'real-cross-connector-', label: 'real cross-Connector installed acceptance'});
const application = join(scratch.path, 'application'); await mkdir(application);
await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
const environment = realCrossConnectorEnvironment(process.env, {root: scratch.path, node: process.execPath});
const registry = await openReleaseTestRegistry([{directory, manifest: release.manifest}]);
try {
  await writeFile(environment.npm_config_userconfig,
    `registry=https://registry.npmjs.org/\n@actql:registry=${registry.url}\n`, {mode: 0o600});
  await writeFile(environment.npm_config_globalconfig, '', {mode: 0o600});
  // The existing immutable registry serves only the selected ActQL artifacts.
  // Third-party native packages use their normal registry/SRI and lifecycle.
  await promisify(execFile)('npm', ['install', '--no-audit', '--no-fund', '--save-exact',
    ...release.manifest.packages.map(item => `${item.name}@${item.version}`),
    '@duckdb/node-api@1.5.5-r.4'], {cwd: application, env: environment,
    timeout: 90000, maxBuffer: 8 * 1024 * 1024});
} catch {
  throw new Error('NormalRealConnectorInstallationFailedBeforeGcs');
} finally { await registry.close(); }
const lockWire = await readFile(join(application, 'package-lock.json'));
const lock = JSON.parse(lockWire);
const peer = lock.packages['node_modules/@duckdb/node-api'];
assert.equal(peer.version, '1.5.5-r.4');
assert.match(peer.resolved, /^https:\/\/registry\.npmjs\.org\//u);
assert.match(peer.integrity, /^sha512-/u);
for (const [path, item] of Object.entries(lock.packages)) {
  if (path.startsWith('node_modules/@duckdb/')) {
    assert.match(item.resolved, /^https:\/\/registry\.npmjs\.org\//u);
    assert.match(item.integrity, /^sha512-/u);
  }
}
auditPackedPackages(application, ['client-wire', 'sdk', 'local-node', 'node']);
const copied = [];
for (const path of realCrossConnectorFixturePaths) {
  const destination = join(application, path); await mkdir(dirname(destination), {recursive: true});
  await copyFile(join(repository, path), destination);
  const wire = await readFile(destination);
  copied.push({path, bytes: wire.byteLength, sha256: createHash('sha256').update(wire).digest('hex')});
}
const copiedScope = join(scratch.path, 'metadata-scope.json');
await writeFile(copiedScope, scopeWire, {flag: 'wx', mode: 0o600});
Object.assign(environment, {ACTQL_TEST_TABLE_PACKED_APPLICATION: application,
  ACTQL_REAL_CONNECTOR_SCOPE: copiedScope, ACTQL_TABLE_PYTHON: python,
  ACTQL_TEST_PRESERVE_SCRATCH: '1'});
const args = nodeTestArguments(['--test-concurrency=1',
  'adapters/host-node/real-cross-connector-installed.test.mjs']);
const result = spawnSync(process.execPath, args, {cwd: application, env: environment,
  encoding: 'utf8', timeout: 180000, maxBuffer: 16 * 1024 * 1024});
// Persist exact private output before classifying failure; never touch old Runs.
await writeFile(join(scratch.path, 'consumer.stdout.log'), result.stdout ?? '', {mode: 0o600});
await writeFile(join(scratch.path, 'consumer.stderr.log'), result.stderr ?? '', {mode: 0o600});
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
const checked = assertTestExecution('node', process.execPath, args, result);
assert.equal(checked.counts.passed, 1);
await release.verifyUnchanged(); assert.deepEqual(checkoutState(repository), before);
const receipt = {source, manifestSHA256: release.manifestSha256,
  archives: release.manifest.packages, copied, actualTests: checked.counts,
  scopeSHA256: createHash('sha256').update(scopeWire).digest('hex'),
  application, complete: true, releaseGeneration: release.manifest.generation,
  lifecycleInstall: {ignoreScripts: false, optionalPeer: '@duckdb/node-api@1.5.5-r.4',
    registryRequests: registry.requested, thirdPartyRegistry: 'https://registry.npmjs.org/',
    packageLockSHA256: createHash('sha256').update(lockWire).digest('hex'),
    dependencyIntegrities: Object.fromEntries(Object.entries(lock.packages).filter(([path]) => path.startsWith('node_modules/'))
      .map(([path, item]) => [path, {version: item.version, resolved: item.resolved, integrity: item.integrity}]))}};
await writeFile(join(scratch.path, 'receipt.json'), JSON.stringify(receipt, null, 2)+'\n', {mode: 0o600});
console.log('REAL_CROSS_CONNECTOR_PROVENANCE '+JSON.stringify(receipt));
scratch.passed();
