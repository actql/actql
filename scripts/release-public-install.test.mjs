// Inert normal-format archive and installed-tree components. HTTP is injected;
// no real public install, product runtime, owner approval or supplier occurs.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile, rm, rename, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test, {before, after} from 'node:test';
import {admitCohort, stagePackage, unpack, inventory} from './package-release.mjs';
import {observeNpmPackageRelease} from './release-registry.mjs';
import {releaseInstallSelection, publicNpmRegistry, publicConsumerEnvironment,
  publicInstallCommand, verifyPublicConsumer} from './release-public-install.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
let root, directory, manifest, original, manifestSha256;

before(async () => {
  root = await mkdtemp(join(tmpdir(), 'actql-public-consumer-component-')); directory = join(root, 'cohort');
  const development = join(directory, 'development'); await mkdir(development, {recursive: true});
  const packRoot = join(root, 'pack-environment'); await mkdir(packRoot);
  const packEnvironment = publicConsumerEnvironment(process.env, packRoot);
  for (const path of [packEnvironment.HOME, packEnvironment.TMPDIR]) await mkdir(path);
  await writeFile(packEnvironment.npm_config_userconfig, `registry=${publicNpmRegistry}\n`);
  await writeFile(packEnvironment.npm_config_globalconfig, '');
  const cohort = admitCohort({version: 'actql-package-release-cohort/0.1', packageVersion: '0.0.7-rc.1',
    registry: publicNpmRegistry, access: 'public', tag: 'candidate-synthetic', packages: ['client-wire', 'sdk', 'local-node', 'node']});
  const license = join(root, 'LICENSE'); await writeFile(license, 'Independent inert fixture license\n');
  const packages = [], tarballs = {};
  for (const [index, name] of cohort.packages.entries()) {
    const path = join(root, `original-${name}`); await mkdir(path);
    await writeFile(join(path, 'package.json'), JSON.stringify({name: `@actql/${name}`, version: '0.0.0-development',
      private: true, type: 'module', files: ['index.mjs', 'index.d.ts'],
      exports: {'.': {types: './index.d.ts', default: './index.mjs'}},
      dependencies: index ? {[`@actql/${cohort.packages[index - 1]}`]: '0.0.0-development'} : {}}));
    await writeFile(join(path, 'index.mjs'), 'export const inert = 73;\n');
    await writeFile(join(path, 'index.d.ts'), 'export declare const inert: number;\n');
    execFileSync('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination', development, '--cache', join(root, 'npm-cache')],
      {cwd: path, env: packEnvironment, encoding: 'utf8', stdio: 'pipe'});
    const item = await stagePackage({archive: join(development, `actql-${name}-0.0.0-development.tgz`),
      destination: directory, name, cohort, license});
    packages.push(item); tarballs[name] = item.originalSha256;
  }
  await writeFile(join(development, 'packed-client-packages.json'), JSON.stringify({revision: 'a'.repeat(40), tarballs}));
  manifest = {version: 'actql-package-release/0.1', sourceSha: 'a'.repeat(40), preparedAt: '2000-01-01T00:00:00Z',
    cohort, recipeSha256: 'b'.repeat(64), cohortSha256: 'c'.repeat(64), toolchain: {fixture: true},
    generation: 'normal-prepack-then-metadata-and-license-only', packages};
  original = Buffer.from(JSON.stringify(manifest)); manifestSha256 = sha(original);
  await writeFile(join(directory, 'release.json'), original);
});
after(async () => {if (root) await rm(root, {recursive: true, force: true});});

async function transport() {
  const routes = new Map(), calls = [];
  for (const item of manifest.packages) {
    const metadata = `${publicNpmRegistry}${encodeURIComponent(item.name)}/${item.version}`;
    const url = `${publicNpmRegistry}${item.name}/-/${item.file}`, bytes = await readFile(join(directory, item.file));
    routes.set(metadata, () => Response.json({name: item.name, version: item.version, dist: {integrity: item.integrity, tarball: url}}));
    routes.set(url, () => new Response(bytes));
  }
  const fetchResponse = async (url, options) => {
    calls.push(url); assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit');
    assert.equal(options.redirect, 'error'); assert.equal(options.headers.authorization, undefined);
    assert.equal(Object.hasOwn(options, 'body'), false); assert(routes.has(url), `Unexpected request: ${url}`);
    return routes.get(url)();
  };
  return {routes, calls, fetchResponse, observe: () => observeNpmPackageRelease(directory, manifestSha256, {fetchResponse})};
}

async function consumer(t, entry = 'node') {
  const path = await mkdtemp(join(root, 'installed-')); t.after(() => rm(path, {recursive: true, force: true}));
  const scope = join(path, 'node_modules/@actql'); await mkdir(scope, {recursive: true});
  const packages = {'': {dependencies: {[`@actql/${entry}`]: manifest.cohort.packageVersion}}};
  const names = entry === 'node' ? manifest.cohort.packages : ['client-wire', 'sdk'];
  for (const name of names) {
    const item = manifest.packages.find(value => value.name === `@actql/${name}`), scratch = join(path, `extract-${name}`);
    const payload = await unpack(join(directory, item.file), scratch); await rename(payload, join(scope, name));
    await rm(scratch, {recursive: true});
    packages[`node_modules/${item.name}`] = {version: item.version, integrity: item.integrity,
      resolved: `${publicNpmRegistry}${item.name}/-/${item.file}`};
  }
  const lock = {name: 'independent-inert-consumer', lockfileVersion: 3, packages};
  const save = async () => writeFile(join(path, 'package-lock.json'), JSON.stringify(lock)); await save();
  return {path, lock, save};
}

test('public consumer: mode is explicit, digest-bound and never falls back to loopback or an arbitrary registry', () => {
  assert.equal(releaseInstallSelection(['relative-rc']).kind, 'private-loopback');
  assert.equal(releaseInstallSelection(['relative-rc', '--public-registry', 'a'.repeat(64)]).kind, 'public-npm');
  for (const args of [[], ['rc', '--public-registry'], ['rc', '--public-registry', 'HEAD'],
    ['rc', '--registry', 'http://127.0.0.1:9'], ['rc', '--public-registry', 'a'.repeat(64), '--fallback']])
    assert.throws(() => releaseInstallSelection(args));
});

test('public consumer: fresh configuration excludes publisher/source injection and requests only one exact entry without scripts', () => {
  const environment = publicConsumerEnvironment({PATH: '/usr/bin:/bin', HOME: '/old-home', NPM_TOKEN: 'not-forwarded',
    NODE_AUTH_TOKEN: 'not-forwarded', npm_config_userconfig: '/old-config', NODE_OPTIONS: '--require old-code',
    NODE_PATH: '/old-source', ACTQL_LOCAL_SOURCE_PROFILE: 'old-profile', HTTPS_PROXY: 'http://owner:secret@proxy', LANG: 'C'}, '/fresh-owned');
  for (const key of ['NPM_TOKEN', 'NODE_AUTH_TOKEN', 'NODE_OPTIONS', 'NODE_PATH', 'ACTQL_LOCAL_SOURCE_PROFILE', 'HTTPS_PROXY']) assert.equal(environment[key], undefined);
  assert.equal(environment.HOME, '/fresh-owned/home'); assert.equal(environment.npm_config_registry, publicNpmRegistry);
  assert.equal(environment.npm_config_userconfig, '/fresh-owned/npmrc');
  for (const entry of ['node', 'sdk']) assert.deepEqual(publicInstallCommand(manifest, entry), ['install', '--save-exact', '--ignore-scripts',
    '--engine-strict', '--no-audit', '--no-fund', '--registry', publicNpmRegistry, `@actql/${entry}@0.0.7-rc.1`]);
  assert.throws(() => publicInstallCommand(manifest, 'internal')); assert.throws(() => publicInstallCommand({...manifest, cohort: {...manifest.cohort, registry: 'http://localhost'}}, 'node'));
});

test('public consumer: real original cohort verifier and existing npm identity/byte reader precede installation, without changing fixed bytes', async () => {
  const f = await transport(), result = await f.observe();
  assert.equal(result.manifestSha256, manifestSha256); assert.equal(result.sourceSha, manifest.sourceSha);
  assert(result.observations.every(item => item.state === 'present')); assert.deepEqual(result.issues, []);
  assert.equal(f.calls.length, 8); assert.equal(result.requests.filter(item => item.sha256 && item.integrity).length, 4);
  assert.deepEqual(await readFile(join(directory, 'release.json')), original);
  const before = f.calls.length;
  await assert.rejects(observeNpmPackageRelease(directory, 'f'.repeat(64), {fetchResponse: f.fetchResponse}), /externally retained manifest/u);
  assert.equal(f.calls.length, before);
});

test('public consumer: absent, unavailable and conflicting public bytes are distinct and cannot qualify an install', async () => {
  const f = await transport(), first = manifest.packages[0];
  const metadata = `${publicNpmRegistry}${encodeURIComponent(first.name)}/${first.version}`;
  for (const [status, expected] of [[404, 'absent'], [503, 'unknown']]) {
    f.routes.set(metadata, () => new Response('', {status})); assert.equal((await f.observe()).observations[0].state, expected);
  }
  const binary = `${publicNpmRegistry}${first.name}/-/${first.file}`;
  f.routes.set(metadata, () => Response.json({name: first.name, version: first.version, dist: {integrity: first.integrity, tarball: binary}}));
  f.routes.set(binary, () => new Response(Buffer.alloc(first.bytes, 65)));
  const result = await f.observe(); assert.equal(result.observations[0].state, 'conflict'); assert.match(result.issues[0].reason, /different sha256/u);
});

test('public consumer: actual lock and complete original Node/SDK payload audits remain separate from runtime acceptance', async t => {
  for (const entry of ['node', 'sdk']) {
    const f = await consumer(t, entry), result = await verifyPublicConsumer(f.path, manifest, entry);
    assert.equal(result.entry, `@actql/${entry}`); assert.equal(result.payloads.length, entry === 'node' ? 4 : 2);
    assert.equal(result.version, '0.0.7-rc.1'); assert.match(result.qualification, /runtime\/close\/public source needs/u);
    const lock = await readFile(join(f.path, 'package-lock.json')); assert.equal(result.lockBytes, lock.length); assert.equal(result.lockSha256, sha(lock));
  }
});

test('public consumer: manual internal installs, workspace links, foreign resolutions, nested ActQL copies and changed SRI refuse', async t => {
  const f = await consumer(t), originalLock = structuredClone(f.lock);
  const variants = [lock => {lock.packages[''].dependencies['@actql/sdk'] = '0.0.7-rc.1';},
    lock => {lock.packages[''].dependencies['@actql/node'] = '^0.0.7-rc.1';},
    lock => {lock.packages['node_modules/@actql/sdk'].link = true;},
    lock => {lock.packages['node_modules/@actql/sdk'].resolved = 'file:../old-source';},
    lock => {lock.packages['node_modules/@actql/sdk'].resolved = 'https://other.invalid/pkg.tgz';},
    lock => {lock.packages['node_modules/@actql/sdk'].integrity = 'sha512-other';},
    lock => {lock.packages['node_modules/@actql/node/node_modules/@actql/sdk'] = lock.packages['node_modules/@actql/sdk'];}];
  for (const change of variants) {f.lock = structuredClone(originalLock); change(f.lock); await writeFile(join(f.path, 'package-lock.json'), JSON.stringify(f.lock)); await assert.rejects(verifyPublicConsumer(f.path, manifest, 'node'));}
});

test('public consumer: payload tamper, extra files and symlink aliases refuse while unrelated npm dependency subtrees are not misidentified as payload', async t => {
  const f = await consumer(t), file = join(f.path, 'node_modules/@actql/sdk/index.mjs'), originalBytes = await readFile(file);
  await writeFile(file, Buffer.alloc(originalBytes.length, 65)); await assert.rejects(verifyPublicConsumer(f.path, manifest, 'node'));
  await writeFile(file, originalBytes);
  const extra = join(f.path, 'node_modules/@actql/sdk/undeclared.js'); await writeFile(extra, 'extra');
  await assert.rejects(verifyPublicConsumer(f.path, manifest, 'node')); await rm(extra);
  await rm(file); const keeper = join(f.path, 'same-bytes.mjs'); await writeFile(keeper, originalBytes); await symlink(keeper, file);
  await assert.rejects(verifyPublicConsumer(f.path, manifest, 'node'), /symlink/u); await rm(file); await writeFile(file, originalBytes);
  const dependencies = join(f.path, 'node_modules/@actql/sdk/node_modules/vendor'); await mkdir(dependencies, {recursive: true});
  await writeFile(join(dependencies, 'index.mjs'), 'Unrelated npm-owned dependency bytes');
  assert.equal((await verifyPublicConsumer(f.path, manifest, 'node')).payloads.length, 4);
});

test('public consumer: archive inventory default still includes dependency directories and refuses links, even when consumer audit has a narrow exclusion', async t => {
  const path = await mkdtemp(join(root, 'inventory-')); t.after(() => rm(path, {recursive: true, force: true}));
  await writeFile(join(path, 'payload.txt'), 'own'); await mkdir(join(path, 'node_modules/dep'), {recursive: true});
  await writeFile(join(path, 'node_modules/dep/index.js'), 'dependency');
  assert.equal((await inventory(path)).length, 2); assert.equal((await inventory(path, '', {ignoreInstalledDependencies: true})).length, 1);
  await symlink(join(path, 'payload.txt'), join(path, 'node_modules/dep/alias'));
  await assert.rejects(inventory(path), /symlink/u);
});
