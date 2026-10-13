// Consumer only: normal registry installation of the four unchanged RC packages.
import assert from 'node:assert/strict';
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
import {releaseNearestRequiredFixturePaths, releaseNearestRequiredEnvironment} from './release-nearest-required-fixtures.mjs';
import {createTransportOwner, transportModes} from './fixtures/packed-query-transport-owner.mjs';
import {auditNearestRequiredTransport} from '../reviews/2026-10-14-nearest-required-release-matrix/public-audit.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const [input, receiptPath, ...extra] = process.argv.slice(2);
assert(input && receiptPath && extra.length === 0 && isAbsolute(receiptPath),
  'usage: test-package-release-nearest-required.mjs <fixed-RC> <new-absolute-receipt.json>');
assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1',
  'Retain actual Run/Result, Source custody and full transport receipts');
const directory = resolve(input), manifest = await verifyPackageRelease(directory);
assert.deepEqual(manifest.cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
assert.ok(!resolve(receiptPath).startsWith(directory + '/'), 'Keep the original RC unchanged');
const source = checkoutState(repository);
assert(source.clean, 'Release NEAREST fixture requires clean committed source');
assert.equal(manifest.sourceSha, source.revision, 'Use the exact same clean producer/consumer source');
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-release-nearest-required-',
  label: 'Installed NEAREST typed Carrier acceptance'});
const root = scratch.path, fixtureDigests = {}, audits = [];
const registry = await openReleaseTestRegistry([{directory, manifest}]);
const env = releaseNearestRequiredEnvironment(process.env, {registry: registry.url, root, node: process.execPath});
// One original 300-second consumer budget, including install and both transports.
const owner = createTransportOwner({deadline: Date.now() + 300000, timeoutMs: 300000, env});
let primary;
try {
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  await writeFile(env.npm_config_userconfig, `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
  await writeFile(env.npm_config_globalconfig, '');
  await owner.run([{name: 'registry-install-node', command: 'npm',
    args: ['install', '--no-audit', '--no-fund', `@actql/node@${manifest.cohort.packageVersion}`], cwd: root}]);
  auditPackedPackages(root, manifest.cohort.packages);
  for (const path of releaseNearestRequiredFixturePaths) {
    const target = join(root, path); await mkdir(dirname(target), {recursive: true});
    await copyFile(join(repository, path), target);
    const bytes = await readFile(join(repository, path));
    assert.deepEqual(await readFile(target), bytes);
    fixtureDigests[path] = createHash('sha256').update(bytes).digest('hex');
  }
  await owner.run([{name: 'fixture-https-certificate', command: 'openssl',
    args: ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'remote.key',
      '-out', 'remote.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], cwd: root}]);
  await owner.run(transportModes.map(mode => ({name: `nearest-required-${mode}`,
    args: [join(root, 'scripts/fixtures/release-nearest-required-worker.mjs')], cwd: root,
    environment: {ACTQL_TEST_QUERY_TRANSPORT: mode, NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')}})));
  for (const mode of transportModes) {
    const report = JSON.parse(await readFile(join(root, `transport-completion.${mode}.json`), 'utf8'));
    const receipt = JSON.parse(await readFile(join(root, `nearest-required-receipts.${mode}.json`), 'utf8'));
    audits.push(await auditNearestRequiredTransport(mode, report, receipt));
  }
  await verifyPackageRelease(directory);
  auditPackedPackages(root, manifest.cohort.packages);
  assert.deepEqual(checkoutState(repository), source, 'Source changed during acceptance');
  owner.check();
} catch (error) { primary = error; }
finally {
  owner.close();
  await registry.close();
  await writeFile(receiptPath, JSON.stringify({artifactSourceSha: manifest.sourceSha,
    fixtureSourceSha: source.revision, consumerDirectory: root, fixtureDigests,
    artifacts: manifest.packages.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity})),
    audits, processReceipt: owner.report(), complete: primary === undefined,
    primaryError: primary?.message, publicPublication: false}, null, 2) + '\n', {flag: 'wx'});
}
if (primary !== undefined) throw primary;
scratch.passed();
