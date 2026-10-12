import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, rm, writeFile, copyFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {admitCohort, releasePackageMetadata, stagePackage, publishedVersion,
  publicationPlan, verifyPackageRelease} from './package-release.mjs';
import {publishPackageRelease} from './publish-package-release.mjs';

const cohort = admitCohort(JSON.parse(await readFile(new URL('../release/client-cohort.json', import.meta.url))));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

test('Explorer is a separate exact closure and internal peers receive the release version', async () => {
  const explorer = admitCohort(JSON.parse(await readFile(new URL('../release/explorer-cohort.json', import.meta.url))));
  assert.deepEqual(cohort.packages, ['client-wire', 'sdk', 'local-node', 'node']);
  assert.deepEqual(explorer.packages, [...cohort.packages, 'explorer-ui', 'explorer']);
  const original = JSON.parse(await readFile(new URL('../packages/explorer-ui/package.json', import.meta.url)));
  const metadata = releasePackageMetadata(original, 'explorer-ui', explorer);
  assert.equal(metadata.peerDependencies['@actql/sdk'], explorer.packageVersion);
  assert.equal(metadata.peerDependencies.react, original.peerDependencies.react);
  assert.equal(metadata.peerDependencies['react-dom'], original.peerDependencies['react-dom']);
  assert.equal(metadata.exports['./styles.css'], './dist/plan-explorer.css');
  assert.throws(() => admitCohort({...explorer, packages: cohort.packages}));
  assert.throws(() => admitCohort({...cohort, packages: explorer.packages}));
  assert.throws(() => releasePackageMetadata({name: '@actql/explorer-ui',
    peerDependencies: {'@actql/missing': '0.0.0-development'}}, 'explorer-ui', explorer));
  assert.throws(() => releasePackageMetadata({name: '@actql/explorer',
    peerDependencies: {react: 'file:../../react'}}, 'explorer', explorer));
});

test('public metadata keeps the exact standard closure and optional peer capability', () => {
  const original = {name: '@actql/local-node', version: '0.0.0-development', private: true,
    exports: {'.': {types: './index.d.ts', default: './index.mjs'}},
    dependencies: {'@actql/sdk': '0.0.0-development'},
    peerDependencies: {'@duckdb/node-api': '1.5.5-r.4'},
    peerDependenciesMeta: {'@duckdb/node-api': {optional: true}},
    scripts: {prepack: 'must-not-run-in-a-consumer'}, files: ['index.mjs', 'index.d.ts']};
  const metadata = releasePackageMetadata(original, 'local-node', cohort);
  assert.equal(metadata.private, false);
  assert.equal(metadata.version, '0.0.1');
  assert.deepEqual(metadata.dependencies, {'@actql/sdk': '0.0.1'});
  assert.deepEqual(metadata.exports, original.exports);
  assert.deepEqual(metadata.peerDependencies, original.peerDependencies);
  assert.deepEqual(metadata.peerDependenciesMeta, original.peerDependenciesMeta);
  assert.equal(metadata.scripts, undefined);
  assert.equal(original.private, true);
});

test('missing cohort dependencies, lifecycle hooks and surplus cohort fields are rejected', () => {
  assert.throws(() => releasePackageMetadata({name: '@actql/node', dependencies: {'@actql/missing': '1'}}, 'node', cohort));
  assert.throws(() => releasePackageMetadata({name: '@actql/node', scripts: {postinstall: 'download'}}, 'node', cohort));
  assert.throws(() => admitCohort({...cohort, ignored: true}));
  assert.throws(() => admitCohort({...cohort, packages: [...cohort.packages].reverse()}));
});

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-release-test-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const development = join(directory, 'development'); await mkdir(development);
  const license = join(directory, 'LICENSE'); await copyFile(new URL('../LICENSE', import.meta.url), license);
  const packages = [], tarballs = {};
  for (const [index, name] of cohort.packages.entries()) {
    const source = join(directory, `input-${name}`); await mkdir(source);
    const metadata = {name: `@actql/${name}`, version: '0.0.0-development', private: true,
      type: 'module', exports: {'.': {types: './index.d.ts', default: './index.mjs'}},
      files: ['index.mjs', 'index.d.ts'],
      dependencies: index ? {[`@actql/${cohort.packages[index-1]}`]: '0.0.0-development'} : {}};
    await writeFile(join(source, 'package.json'), JSON.stringify(metadata));
    await writeFile(join(source, 'index.mjs'), 'export const fixed = 7;\n');
    await writeFile(join(source, 'index.d.ts'), 'export declare const fixed: number;\n');
    execFileSync('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination', development,
      '--cache', join(directory, 'cache')], {cwd: source, encoding: 'utf8'});
    const archive = join(development, `actql-${name}-0.0.0-development.tgz`);
    const item = await stagePackage({archive, destination: directory, name, cohort, license});
    packages.push(item); tarballs[name] = item.originalSha256;
  }
  const manifest = {version: 'actql-package-release/0.1', sourceSha: 'a'.repeat(40),
    preparedAt: new Date().toISOString(), cohort, recipeSha256: 'b'.repeat(64), cohortSha256: 'c'.repeat(64),
    toolchain: {node: process.version}, generation: 'normal-prepack-then-metadata-and-license-only', packages};
  await writeFile(join(development, 'packed-client-packages.json'), JSON.stringify({revision: manifest.sourceSha, tarballs}));
  await writeFile(join(directory, 'release.json'), JSON.stringify(manifest));
  return {directory, manifest};
}

test('staging and verification preserve compiled bytes, types, mode and original lineage', async t => {
  const {directory, manifest} = await fixture(t);
  assert.deepEqual(await verifyPackageRelease(directory), manifest);
  const item = manifest.packages[0];
  const archive = join(directory, item.file);
  await writeFile(archive, Buffer.concat([await readFile(archive), Buffer.from('changed')]));
  await assert.rejects(verifyPackageRelease(directory));
});

test('source receipt mismatch refuses a release even when staged archive hashes match', async t => {
  const {directory} = await fixture(t);
  await writeFile(join(directory, 'development/packed-client-packages.json'), JSON.stringify({revision: 'f'.repeat(40), tarballs: {}}));
  await assert.rejects(verifyPackageRelease(directory));
});

test('registry absence, unavailability and occupied version mismatch stay distinct', async () => {
  const item = {name: '@actql/sdk', version: '0.0.1', integrity: 'sha512-fixed'};
  const metadata = {name: item.name, version: item.version, dist: {integrity: item.integrity}};
  assert.equal(await publishedVersion(item, cohort.registry, async () => new Response('', {status: 404})), 'absent');
  assert.equal(await publishedVersion(item, cohort.registry, async () => Response.json(metadata)), 'published-identical');
  await assert.rejects(publishedVersion(item, cohort.registry, async () => new Response('', {status: 503})), /unavailable/u);
  await assert.rejects(publishedVersion(item, cohort.registry, async () => {throw Error('timeout');}), /timeout/u);
  await assert.rejects(publishedVersion(item, cohort.registry, async () => Response.json({...metadata, dist: {integrity: 'sha512-other'}})), /different bytes/u);
});

test('partial publication resumes exact remaining versions and never republishes confirmed bytes', async t => {
  const {directory, manifest} = await fixture(t);
  const published = new Map(), calls = [];
  const fetchMetadata = async url => {
    const name = decodeURIComponent(new URL(url).pathname.split('/')[1]);
    const item = published.get(name);
    return item ? Response.json({name: item.name, version: item.version, dist: {integrity: item.integrity}}) : new Response('', {status: 404});
  };
  let failed = false;
  const executePublish = async ({file}) => {
    const item = manifest.packages.find(v => file.endsWith(v.file)); calls.push(item.name);
    if (item.name === '@actql/local-node' && !failed) {failed = true; throw Error('permission-lost');}
    published.set(item.name, item);
  };
  await assert.rejects(publishPackageRelease({directory, executePublish, fetchMetadata}), /permission-lost/u);
  assert.deepEqual([...published.keys()], ['@actql/client-wire', '@actql/sdk']);
  await publishPackageRelease({directory, executePublish, fetchMetadata});
  assert.deepEqual(calls, ['@actql/client-wire', '@actql/sdk', '@actql/local-node', '@actql/local-node', '@actql/node']);
  assert((await publicationPlan(manifest, fetchMetadata)).every(v => v.state === 'published-identical'));
});
