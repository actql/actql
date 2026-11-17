// Fresh actual npm consumer of the fixed Native RC. Business/approval/Saved
// oracles belong to the existing two-template public-command scenario.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {inventory} from './package-release.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {observeNativeCliNpmRelease} from './release-registry.mjs';
import {publicConsumerEnvironment, publicNpmRegistry} from './release-public-install.mjs';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {admitInstalledNativeArtifact, requireNativeCohortPackageVersions} from './native-cli-artifact-reader.mjs';
import {captureNativeMockCommand, mockTemplates, runNativeCliMockScenario} from './native-cli-mock-scenario.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export function nativeCliPublicSelection(args) {
  assert(Array.isArray(args) && args.length === 3 && args.every(value => typeof value === 'string'),
    'usage: test-native-cli-public-install.mjs <fixed-Native-RC> <release.json-SHA256> <new-absolute-receipt.json>');
  assert(isAbsolute(args[0]) && isAbsolute(args[2]), 'Select explicit original RC and new receipt paths');
  assert.match(args[1], /^[a-f0-9]{64}$/u);
  const directory = resolve(args[0]), receiptPath = resolve(args[2]);
  assert(receiptPath !== directory && !receiptPath.startsWith(directory + '/'), 'Keep the fixed RC unchanged');
  return {directory, manifestSha256: args[1], receiptPath};
}

export function nativeCliPublicInstallCommand() {
  return ['install', '--save-exact', '--ignore-scripts', '--engine-strict', '--no-audit', '--no-fund',
    '--registry', publicNpmRegistry, 'actql@0.0.2'];
}

export function admitPublicCliLock(lock, manifest, platform) {
  assert.equal(lock.lockfileVersion, 3);
  assert.deepEqual(lock.packages?.['']?.dependencies, {actql: '0.0.2'}, 'Install only the exact public CLI entry');
  const entries = [], selected = `@actql/cli-${platform}`;
  for (const [path, value] of Object.entries(lock.packages)) {
    if (path === '') continue;
    const item = manifest.packages.find(item => path === `node_modules/${item.name}` ||
      item.name !== 'actql' && path === `node_modules/actql/node_modules/${item.name}`);
    assert(item, 'Unexpected public CLI dependency or nested package');
    assert.equal(value.version, item.version); assert.equal(value.integrity, item.integrity);
    assert.notEqual(value.link, true, 'Public CLI cannot use workspace links');
    assert(typeof value.resolved === 'string' && !/[\u0000-\u0020\u007f]/u.test(value.resolved));
    const url = new URL(value.resolved);
    assert.equal(url.origin, 'https://registry.npmjs.org');
    assert(!url.username && !url.password && !url.search && !url.hash, 'Only literal official public archive URLs');
    entries.push({path, item, resolved: value.resolved});
  }
  for (const name of ['actql', selected]) assert.equal(entries.filter(row => row.item.name === name).length, 1,
    'Missing or duplicated selected public CLI package');
  for (const item of manifest.packages) assert(entries.filter(row => row.item.name === item.name).length <= 1);
  return entries;
}

export async function runNativeCliPublicAcceptance(args) {
  const selection = nativeCliPublicSelection(args), directory = selection.directory;
  await assert.rejects(lstat(selection.receiptPath), {code: 'ENOENT'});
  assert(!process.env.NODE_OPTIONS && !process.env.NODE_PATH, 'Refuse ambient Node injection');
  const repository = fileURLToPath(new URL('../', import.meta.url)), source = checkoutState(repository);
  const manifestBytes = await readFile(join(directory, 'release.json'));
  assert.equal(hash(manifestBytes), selection.manifestSha256);
  const manifest = requireNativeCohortPackageVersions(await verifyNativeCliRelease(directory));
  assert(source.clean && source.revision === manifest.sourceSha, 'Exact clean release fixture source required');
  assert.equal(manifest.cohort.packageVersion, '0.0.2'); assert.equal(manifest.cohort.registry, publicNpmRegistry);
  assert.deepEqual(manifest.packages.map(item => item.name).sort(), ['@actql/cli-darwin-arm64', '@actql/cli-linux-x64-gnu', 'actql']);
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  const expected = manifest.artifacts.find(value => value.platform === platform);
  assert(expected?.localRuntime, 'Actual selected packaged Local runtime required');
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-public-cli-',
    label: 'Actual npm CLI README and cold Saved consumer', preserve: true});
  const root = scratch.path, consumer = join(root, 'consumer'), records = [], scenarios = [], publicObservations = [], payloadObservations = [];
  const env = publicConsumerEnvironment(process.env, root, process.execPath);
  env.PATH = [dirname(process.execPath), '/usr/bin', '/bin', '/usr/sbin', '/sbin'].join(':');
  let primary, installed = false;
  const cleanup = [];
  const unchanged = async () => {
    assert.deepEqual(await readFile(join(directory, 'release.json')), manifestBytes);
    assert.deepEqual(await verifyNativeCliRelease(directory), manifest);
    assert.deepEqual(checkoutState(repository), source);
  };
  const observe = async () => {
    const value = await observeNativeCliNpmRelease(directory, selection.manifestSha256);
    publicObservations.push(value);
    assert(value.observations.every(item => item.state === 'present'), 'Every original CLI archive must be public with exact bytes');
  };
  const verifyInstalled = async () => {
    const lockBytes = await readFile(join(consumer, 'package-lock.json'));
    const entries = admitPublicCliLock(JSON.parse(lockBytes), manifest, platform), payloads = [];
    for (const row of entries) {
      if (row.item.name !== 'actql' && row.item.name !== `@actql/cli-${platform}`) {
        await assert.rejects(lstat(join(consumer, row.path)), {code: 'ENOENT'}); continue;
      }
      const parts = row.path.split('/'); let path = consumer;
      for (const part of parts) {path = join(path, part); const st = await lstat(path); assert(st.isDirectory() && !st.isSymbolicLink());}
      assert.deepEqual(await inventory(path, '', {ignoreInstalledDependencies: true}), row.item.files,
        `Installed public payload differs: ${row.item.name}`);
      payloads.push({name: row.item.name, path: row.path, resolved: row.resolved, integrity: row.item.integrity,
        archiveSha256: row.item.sha256, files: row.item.files.length});
    }
    const os = entries.find(row => row.item.name === `@actql/cli-${platform}`);
    assert.deepEqual(await admitInstalledNativeArtifact(join(consumer, os.path), manifest.sourceSha), expected);
    const launcher = join(consumer, 'node_modules/.bin/actql');
    assert.equal(await realpath(launcher), join(consumer, 'node_modules/actql/bin/actql.mjs'));
    payloadObservations.push({lockSha256: hash(lockBytes), payloads});
    return launcher;
  };
  async function run(command, commandArgs, cwd = root, timeout = 120000) {
    const record = {command, args: commandArgs, cwd, timeout}; records.push(record);
    const started = process.hrtime.bigint();
    try {
      Object.assign(record, await captureNativeMockCommand(command, commandArgs, {cwd, env, timeout,
        stderrPath: join(root, `command-${records.length}.stderr`)}), {code: 0, signal: null});
    } catch (error) {
      Object.assign(record, {code: error.code ?? null, signal: error.signal ?? null, killed: error.killed ?? false,
        stdout: error.stdout ?? '', stderr: error.stderr ?? '', ...(error.exitCode !== undefined ? {childExitCode: error.exitCode} : {})});
    }
    record.elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
    await writeFile(join(root, 'commands.json'), JSON.stringify(records, null, 2) + '\n');
    return record;
  }
  try {
    await observe();
    for (const path of [consumer, env.HOME, env.TMPDIR]) await mkdir(path);
    await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n', {flag: 'wx'});
    await writeFile(env.npm_config_userconfig, `registry=${publicNpmRegistry}\n@actql:registry=${publicNpmRegistry}\n`, {flag: 'wx'});
    await writeFile(env.npm_config_globalconfig, '', {flag: 'wx'});
    const installation = await run('npm', nativeCliPublicInstallCommand(), consumer, 180000);
    assert.equal(installation.code, 0, installation.stderr); assert.equal(installation.signal, null);
    const launcher = await verifyInstalled(); installed = true;
    env.PATH = ''; env.ACTQL_NATIVE_TIMINGS = '1'; env.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS = '1';
    for (const command of ['--help', '--version']) {
      const record = await run(process.execPath, [launcher, command]);
      assert.equal(record.code, 0, record.stderr); assert.equal(record.signal, null);
      if (command === '--version') assert.equal(record.stdout, '0.0.2\n');
    }
    for (const template of mockTemplates) scenarios.push(await runNativeCliMockScenario({root, template, launcherTimings: 'required',
      run: (commandArgs, cwd) => run(process.execPath, [launcher, ...commandArgs], cwd)}));
    await verifyInstalled(); await unchanged();
  } catch (error) {primary = error;}
  finally {
    for (const check of [unchanged, observe, ...(installed ? [verifyInstalled] : [])]) {
      try {await check();} catch (error) {if (primary) cleanup.push(error); else primary = error;}
    }
    const receipt = {version: 'actql-native-cli-public-install/0.1', complete: primary === undefined,
      sourceSha: manifest.sourceSha, fixtureSourceSha: source.revision, manifestSha256: selection.manifestSha256,
      platform, node: process.version, consumer, retainedScratch: root, registry: publicNpmRegistry,
      artifacts: manifest.packages.map(({name, version, file, bytes, sha256, integrity}) => ({name, version, file, bytes, sha256, integrity})),
      publicObservations, payloadObservations, scenarios, records,
      primary: primary ? {name: primary.name, message: primary.message} : null,
      cleanup: cleanup.map(error => ({name: error.name, message: error.message})),
      scope: 'Fresh public actql installation; exact launcher/selected OS payload and public lock; existing two-template README approval and fresh-process Saved/noReplay oracles',
      performanceAcceptance: false};
    await writeFile(selection.receiptPath, JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
    if (primary === undefined) scratch.passed();
  }
  if (primary !== undefined) throw primary;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  await runNativeCliPublicAcceptance(process.argv.slice(2));
}
