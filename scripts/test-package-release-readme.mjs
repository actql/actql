// Consumer-only release acceptance. All business oracles and child watchdogs
// belong to the existing README and File inventory orchestrators.
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile, readdir, lstat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from './owned-scratch.mjs';
import {verifyPackageRelease, inventory} from './package-release.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {releaseInstallSelection, publicConsumerEnvironment, publicInstallCommand,
  verifyPublicConsumer, verifyPublicNodeReleaseBinding, publicNpmRegistry} from './release-public-install.mjs';
import {observeNpmPackageRelease} from './release-registry.mjs';
import {mockWorkflowMetrics, execute} from './health-monitor-adapters.mjs';
import {runPackedProjectFileStoreInventory} from './packed-project-file-store-inventory.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export function releaseReadmeSelection(args) {
  assert(Array.isArray(args) && args.length >= 2 && isAbsolute(args[1]),
    'usage: test-package-release-readme.mjs <fixed-RC> <new-absolute-receipt.json> [--public-registry <release.json-SHA256> [--release-set <fixed-directory> <upper-SHA256> --target <target-id>]]');
  const selection = releaseInstallSelection([args[0], ...args.slice(2)]);
  const receiptPath = resolve(args[1]);
  assert(!receiptPath.startsWith(selection.directory + '/') && receiptPath !== selection.directory,
    'Keep the original release cohort unchanged');
  return {...selection, receiptPath};
}

export function releaseReadmeEnvironment(parent, root, node, registry) {
  const env = publicConsumerEnvironment(parent, root, node);
  env.PATH = [dirname(node), '/usr/bin', '/bin', '/usr/sbin', '/sbin'].join(':');
  env.npm_config_registry = registry;
  env.npm_config_prefix = join(root, 'npm-prefix');
  if (registry !== publicNpmRegistry) env.NO_PROXY = '127.0.0.1,localhost';
  return env;
}

export async function runReleaseReadmeAcceptance(args) {
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const selection = releaseReadmeSelection(args), directory = selection.directory;
  await assert.rejects(lstat(selection.receiptPath), {code: 'ENOENT'});
  assert(!process.env.NODE_OPTIONS && !process.env.NODE_PATH &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Release consumer refuses ambient runtime overlays');
  const manifest = await verifyPackageRelease(directory);
  assert.deepEqual(manifest.cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
  assert.equal(manifest.cohort.packageVersion, '0.0.2');
  const source = checkoutState(repository);
  assert(source.clean, 'Release README fixtures require clean committed source');
  assert.equal(source.revision, manifest.sourceSha, 'Use the exact release source for this consumer');
  const manifestBytes = await readFile(join(directory, 'release.json'));
  const isPublic = selection.kind === 'public-npm';
  if (isPublic) assert.equal(hash(manifestBytes), selection.manifestSha256);
  const releaseSetBinding = isPublic ? await verifyPublicNodeReleaseBinding(selection) : null;
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-release-readme-',
    label: 'Fixed public Node README and File inventory consumer', preserve: true});
  const root = scratch.path, consumer = join(root, 'consumer'), raw = join(root, 'raw');
  const prepared = {consumer, manifest, manifestPath: join(directory, 'release.json')};
  const records = [], workflows = [], failures = [], cleanup = [], fileInventory = {cases: []};
  const publicObservations = [], payloadObservations = [];
  let registry, primary, verifiedInstall = false;
  async function verifyPreparedPackages(value) {
    assert.strictEqual(value, prepared);
    assert.deepEqual(await verifyPackageRelease(directory), manifest, 'Original release cohort changed');
    assert.deepEqual(await readFile(join(directory, 'release.json')), manifestBytes);
    assert.deepEqual(checkoutState(repository), source, 'Release fixture source changed');
    const scope = join(consumer, 'node_modules/@actql');
    for (const path of [consumer, join(consumer, 'node_modules'), scope]) {
      const stat = await lstat(path); assert(stat.isDirectory() && !stat.isSymbolicLink(), 'Release consumer cannot alias another installation');
    }
    assert.deepEqual((await readdir(scope)).sort(), [...manifest.cohort.packages].sort());
    for (const item of manifest.packages) {
      const target = join(consumer, 'node_modules', item.name), stat = await lstat(target);
      assert(stat.isDirectory() && !stat.isSymbolicLink(), 'Release consumer cannot use source links');
      assert.deepEqual(await inventory(target, '', {ignoreInstalledDependencies: true}), item.files,
        `Installed public payload changed: ${item.name}`);
    }
    if (isPublic) return verifyPublicConsumer(consumer, manifest, 'node');
    const lock = JSON.parse(await readFile(join(consumer, 'package-lock.json'), 'utf8'));
    assert.deepEqual(lock.packages[''].dependencies, {'@actql/node': '0.0.2'}, 'Install only the public Node entry');
    assert.deepEqual(Object.keys(lock.packages).filter(path => /(?:^|\/)node_modules\/@actql\//u.test(path)).sort(),
      manifest.packages.map(item => 'node_modules/' + item.name).sort(), 'No nested or extra ActQL package');
    for (const item of manifest.packages) {
      const actual = lock.packages['node_modules/' + item.name];
      assert.equal(actual.version, item.version); assert.equal(actual.integrity, item.integrity);
      assert.notEqual(actual.link, true);
      const origin = new URL(actual.resolved);
      assert.equal(origin.origin, new URL(registry.url).origin);
      assert.equal(origin.pathname, '/archives/' + item.file);
      assert(!origin.username && !origin.password && !origin.search && !origin.hash);
    }
    return {packages: manifest.packages.map(({name, version, sha256}) => ({name, version, sha256}))};
  }
  const observePublic = async () => {
    const value = await observeNpmPackageRelease(directory, selection.manifestSha256);
    publicObservations.push(value);
    assert(value.observations.every(item => item.state === 'present'), 'All exact original release bytes must be public');
  };
  try {
    if (isPublic) await observePublic(); else registry = await openReleaseTestRegistry([{directory, manifest}]);
    const env = releaseReadmeEnvironment(process.env, root, process.execPath, registry?.url ?? publicNpmRegistry);
    for (const path of [consumer, raw, env.HOME, env.TMPDIR]) await mkdir(path);
    await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n', {flag: 'wx'});
    await writeFile(env.npm_config_userconfig, `registry=${env.npm_config_registry}\n@actql:registry=${env.npm_config_registry}\n`, {flag: 'wx'});
    await writeFile(env.npm_config_globalconfig, '', {flag: 'wx'});
    const run = async (command, commandArgs, options) => {
      const childEnv = {...env, ...(options.env?.HOME === undefined ? {} : {HOME: options.env.HOME})};
      const record = {command, args: commandArgs, cwd: options.cwd, name: options.name}; records.push(record);
      try {
        const observed = await execute(command, commandArgs, {...options, raw, env: childEnv});
        Object.assign(record, observed); return observed;
      } catch (error) {Object.assign(record, error.commandResult ?? {}, {error: {name: error.name, message: error.message}}); throw error;}
    };
    await run('npm', isPublic ? publicInstallCommand(manifest, 'node') :
      ['install', '--save-exact', '--engine-strict', '--no-audit', '--no-fund', '@actql/node@0.0.2'],
    {cwd: consumer, name: 'install-public-node', timeout: 180000});
    auditPackedPackages(consumer, manifest.cohort.packages);
    payloadObservations.push(await verifyPreparedPackages(prepared)); verifiedInstall = true;
    const command = async (executable, commandArgs, options) => {
      await verifyPreparedPackages(prepared);
      let result, failed;
      try {result = await run(executable, commandArgs, options);} catch (error) {failed = error;}
      try {await verifyPreparedPackages(prepared);} catch (error) {if (failed) cleanup.push(error); else failed = error;}
      if (failed) throw failed; return result;
    };
    for (const template of ['churn-risk-mock', 'deal-review-mock']) {
      const record = {template, variant: 'readme', completed: false}; workflows.push(record);
      try {
        await mockWorkflowMetrics({prepared, root, repository, command, counts: {coldSamples: 1}, template,
          onMetric: async metric => {record.metric = metric;}});
        record.completed = true;
      } catch (error) {record.error = {name: error.name, message: error.message}; failures.push(error);}
    }
    try {
      await runPackedProjectFileStoreInventory({prepared, root: join(root, 'file-inventory'), repository,
        command, report: fileInventory, cleanup, verifyPreparedPackages});
    } catch (error) {failures.push(error);}
    if (failures.length) throw new AggregateError(failures, 'ReleaseReadmeAcceptanceFailed');
  } catch (error) {primary = error;}
  finally {
    if (verifiedInstall) {try {payloadObservations.push(await verifyPreparedPackages(prepared));} catch (error) {primary ??= error;}}
    if (isPublic) {try {await observePublic(); if (selection.releaseSet) await verifyPublicNodeReleaseBinding(selection);} catch (error) {primary ??= error;}}
    try {await registry?.close();} catch (error) {primary ??= error;}
    try {assert.deepEqual(await verifyPackageRelease(directory), manifest); assert.deepEqual(checkoutState(repository), source);} catch (error) {primary ??= error;}
    const recipePaths = ['scripts/test-package-release-readme.mjs', 'scripts/packed-project-file-store-inventory.mjs',
      'scripts/health-monitor-adapters.mjs', 'scripts/fixtures/packed-project-file-store-inventory.mjs',
      'adapters/host-node/fixtures/mock-project-effect-public.mjs'];
    const fixtureRecipes = await Promise.all(recipePaths.map(async path => ({path, sha256: hash(await readFile(join(repository, path)))})));
    const report = {version: 'actql-release-readme-acceptance/0.1', complete: primary === undefined,
      sourceSha: manifest.sourceSha, fixtureSourceSha: source.revision, node: process.version, platform: process.platform, arch: process.arch,
      manifestSha256: hash(manifestBytes), releaseSetBinding, consumer, retainedScratch: root,
      artifacts: manifest.packages.map(({name, version, file, bytes, sha256, integrity}) => ({name, version, file, bytes, sha256, integrity})),
      publicRegistryPublication: !isPublic ? 'not-tested' : publicObservations.length >= 2 &&
        publicObservations.every(value => value.observations.every(item => item.state === 'present'))
        ? 'exact-original-bytes-observed-anonymously' : 'not-confirmed',
      publicObservations, payloadObservations, registryRequests: registry?.requested ?? [],
      fixtureRecipes, workflows, fileInventory, records,
      cleanup: cleanup.map(error => ({name: error.name, message: error.message})),
      primary: primary ? {name: primary.name, message: primary.message} : null,
      scope: 'Existing README2 and File101/17 capture/approve/fresh Saved lifecycle; original watchdogs and512MiB. Full interface/type/SDK-alone acceptance is separate.',
      performanceAcceptance: false};
    await writeFile(selection.receiptPath, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
    if (primary === undefined) scratch.passed();
  }
  if (primary !== undefined) throw primary;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  await runReleaseReadmeAcceptance(process.argv.slice(2));
}
