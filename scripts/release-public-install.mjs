// Consumer-only preparation/audit for the existing Node install harness.
// This never stages/publishes and cannot convert an install into approval.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, lstat, readdir, realpath} from 'node:fs/promises';
import {join, resolve, dirname, isAbsolute, basename, relative, sep} from 'node:path';
import {inventory} from './package-release.mjs';
import {releaseVersion} from './release-version.mjs';

export const publicNpmRegistry = 'https://registry.npmjs.org/';

export function pythonReleaseInstallSelection(args) {
  assert(Array.isArray(args) && args.length === 5,
    'usage: test-python-release-install.mjs <fixed-directory> <externally-retained-SHA256> <target-id> <absolute-python> <new-external-consumer-directory>');
  assert.match(args[1], /^[a-f0-9]{64}$/u); assert(isAbsolute(args[3]), 'Select one absolute Python interpreter');
  return {directory: resolve(args[0]), manifestSha256: args[1], targetId: args[2],
    python: args[3], consumer: resolve(args[4]), kind: 'public-pypi'};
}

export function pythonPublicConsumerEnvironment(parent, root, interpreter) {
  assert(isAbsolute(interpreter));
  const environment = {};
  for (const key of ['LANG', 'LC_ALL', 'LC_CTYPE', 'TZ'])
    if (typeof parent[key] === 'string') environment[key] = parent[key];
  // Only the fresh venv's bin is available. Node/npm/actql, source paths,
  // publisher tokens, proxies, Python startup and old pip config are absent.
  Object.assign(environment, {PATH: dirname(interpreter), HOME: join(root, 'home'),
    TMPDIR: join(root, 'tmp'), TMP: join(root, 'tmp'), TEMP: join(root, 'tmp'),
    PIP_CONFIG_FILE: process.platform === 'win32' ? 'NUL' : '/dev/null'});
  return environment;
}

export function pythonInstallCommand(version, entry, report) {
  assert(['actql', 'actql-sdk'].includes(entry)); assert(isAbsolute(report));
  const selected = releaseVersion(version);
  return ['-I', '-B', '-m', 'pip', '--isolated', 'install', '--index-url', 'https://pypi.org/simple',
    '--only-binary=:all:', '--no-cache-dir', '--no-compile', '--disable-pip-version-check', '--no-input',
    '--report', report, `${entry}==${selected.pythonVersion}`];
}

export async function pythonConsumerDestination(destination, excludedRoots) {
  const actual = join(await realpath(dirname(destination)), basename(destination));
  for (const root of excludedRoots) {
    const delta = relative(await realpath(root), actual);
    assert(delta !== '' && (delta === '..' || delta.startsWith(`..${sep}`) || isAbsolute(delta)),
      'Python consumer must be physically outside source and fixed artifacts');
  }
  try {await lstat(actual); throw Error('Python consumer destination already exists');}
  catch (failure) {if (failure.code !== 'ENOENT') throw failure;}
  return actual;
}

export function releaseInstallSelection(args) {
  assert(Array.isArray(args) && args.length >= 1, 'Supply the original RC directory');
  if (args.length === 1) return {kind: 'private-loopback', directory: resolve(args[0])};
  assert(args.length === 3 && args[1] === '--public-registry',
    'usage: test-package-release-install.mjs <RC-directory> [--public-registry <externally-retained-release.json-SHA256>]');
  assert.match(args[2], /^[a-f0-9]{64}$/u, 'Public acceptance needs the exact retained cohort digest');
  return {kind: 'public-npm', directory: resolve(args[0]), manifestSha256: args[2]};
}

export function publicConsumerEnvironment(parent, root, node = process.execPath) {
  // Do not inherit publisher tokens, npm configs, proxy credentials, Node
  // injection, ActQL profiles or previous HOME/state. The harness may later
  // add only its existing explicit own HTTPS fixture context.
  const environment = {};
  for (const key of ['LANG', 'LC_ALL', 'LC_CTYPE', 'TZ', 'SystemRoot', 'SYSTEMROOT', 'COMSPEC'])
    if (typeof parent[key] === 'string') environment[key] = parent[key];
  environment.PATH = `${dirname(node)}${process.platform === 'win32' ? ';' : ':'}${parent.PATH ?? ''}`;
  environment.HOME = join(root, 'home'); environment.USERPROFILE = environment.HOME;
  environment.TMPDIR = join(root, 'tmp'); environment.TMP = environment.TMPDIR; environment.TEMP = environment.TMPDIR;
  Object.assign(environment, {npm_config_registry: publicNpmRegistry, npm_config_cache: join(root, 'npm-cache'),
    npm_config_userconfig: join(root, 'npmrc'), npm_config_globalconfig: join(root, 'npmrc-global'),
    npm_config_update_notifier: 'false', npm_config_proxy: '', npm_config_https_proxy: ''});
  return environment;
}

export function publicInstallCommand(manifest, entry) {
  assert.equal(manifest.version, 'actql-package-release/0.1');
  assert.deepEqual(manifest.cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
  assert.equal(manifest.cohort.registry, publicNpmRegistry); assert(['node', 'sdk'].includes(entry));
  const item = manifest.packages.find(value => value.name === `@actql/${entry}`); assert(item);
  assert.equal(item.version, manifest.cohort.packageVersion);
  return ['install', '--save-exact', '--ignore-scripts', '--engine-strict', '--no-audit', '--no-fund', '--registry', publicNpmRegistry,
    `@actql/${entry}@${item.version}`];
}

function publicResolved(value) {
  assert.equal(typeof value, 'string'); assert.equal(value, value.trim());
  assert(!/[\u0000-\u0020\u007f]/u.test(value), 'Installed artifact URL must be literal public text');
  const url = new URL(value);
  assert.equal(url.origin, 'https://registry.npmjs.org');
  assert(!url.username && !url.password && !url.search && !url.hash, 'Non-public installed artifact origin');
}

export async function verifyPublicConsumer(root, manifest, entry) {
  const names = entry === 'node' ? manifest.cohort.packages : ['client-wire', 'sdk'];
  publicInstallCommand(manifest, entry);
  const lockPath = join(root, 'package-lock.json'), lockStat = await lstat(lockPath);
  assert(lockStat.isFile() && !lockStat.isSymbolicLink());
  const original = await readFile(lockPath), lock = JSON.parse(original);
  assert.equal(lock.lockfileVersion, 3, 'Public acceptance requires the selected modern npm lock format');
  assert(lock.packages && typeof lock.packages === 'object' && !Array.isArray(lock.packages));
  assert.deepEqual(lock.packages['']?.dependencies, {[`@actql/${entry}`]: manifest.cohort.packageVersion},
    'The consumer must name only its exact public entry, without manually adding internal packages');
  const selected = names.map(name => `node_modules/@actql/${name}`).sort();
  const actual = Object.keys(lock.packages).filter(path => /(?:^|\/)node_modules\/@actql\//u.test(path)).sort();
  assert.deepEqual(actual, selected, 'Unexpected or nested ActQL dependency in public consumer');
  const nodeModules = join(root, 'node_modules'), scope = join(nodeModules, '@actql');
  for (const path of [root, nodeModules, scope]) {
    const st = await lstat(path); assert(st.isDirectory() && !st.isSymbolicLink(), 'Public consumer cannot use a workspace/source link');
  }
  assert.deepEqual((await readdir(scope)).sort(), [...names].sort());
  const payloads = [];
  for (const name of names) {
    const item = manifest.packages.find(value => value.name === `@actql/${name}`); assert(item);
    const locked = lock.packages[`node_modules/${item.name}`];
    assert.equal(locked.version, item.version); assert.equal(locked.integrity, item.integrity); assert.notEqual(locked.link, true);
    publicResolved(locked.resolved);
    assert(!item.files.some(value => value.path === 'node_modules' || value.path.startsWith('node_modules/')),
      'A bundled dependency payload requires its own selected consumer audit');
    const directory = join(scope, name), stat = await lstat(directory); assert(stat.isDirectory() && !stat.isSymbolicLink());
    assert.deepEqual(await inventory(directory, '', {ignoreInstalledDependencies: true}), item.files,
      `Installed public package payload differs from the fixed original: ${item.name}`);
    payloads.push({name: item.name, version: item.version, integrity: locked.integrity, resolved: locked.resolved,
      payloadFiles: item.files.length, originalArchiveSha256: item.sha256});
  }
  assert.deepEqual(await readFile(lockPath), original, 'Public consumer lock changed during audit');
  return {entry: `@actql/${entry}`, version: manifest.cohort.packageVersion, lockfileVersion: lock.lockfileVersion,
    lockBytes: original.length, lockSha256: createHash('sha256').update(original).digest('hex'),
    payloads, qualification: 'actual lock and original ActQL payload byte/mode audit only; runtime/close/public source needs the selected harness outcome'};
}
