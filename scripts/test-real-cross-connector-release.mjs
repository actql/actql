// One normal installed Local scenario. This is neither a producer nor a
// development-package fallback; its external scope is supplied explicitly.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
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
import {realCrossConnectorFixturePaths} from './real-cross-connector-fixtures.mjs';
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
const environment = {...process.env, npm_config_cache: join(scratch.path, 'npm-cache')};
for (const key of Object.keys(environment)) {
  if (key.startsWith('ACTQL_') || key.startsWith('MOON_') ||
      ['MOON_HOME', 'NODE_OPTIONS', 'NODE_PATH', 'NODE_TEST_CONTEXT'].includes(key)) delete environment[key];
}
// Normal lifecycle install. The selected optional DuckDB native peer is a real
// package dependency, not a source supplier or checkout runtime link.
const install = spawnSync('npm', ['install', '--no-audit', '--no-fund', '--no-save',
  ...release.archives, '@duckdb/node-api@1.5.5-r.4'], {cwd: application,
  env: environment, encoding: 'utf8', timeout: 90000, maxBuffer: 8 * 1024 * 1024});
assert.ifError(install.error); assert.equal(install.status, 0, 'Normal installation failed; no GCS was started');
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
  lifecycleInstall: {ignoreScripts: false, optionalPeer: '@duckdb/node-api@1.5.5-r.4'}};
await writeFile(join(scratch.path, 'receipt.json'), JSON.stringify(receipt, null, 2)+'\n', {mode: 0o600});
console.log('REAL_CROSS_CONNECTOR_PROVENANCE '+JSON.stringify(receipt));
scratch.passed();
