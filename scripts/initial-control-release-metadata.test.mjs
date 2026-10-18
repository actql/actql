import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdir, readFile, rename, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import source from '../adapters/host-node/initial-control-image-source.cjs';
import {admitCohort, releasePackageMetadata, stagePackage, unpack} from './package-release.mjs';
import {initialControlPackageOriginal, renderInitialControlPackageOriginal}
  from './initial-control-package-images.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const cohort = admitCohort(JSON.parse(await readFile(new URL('../release/client-cohort.json', import.meta.url))));
const hash = b => createHash('sha256').update(b).digest('hex');
const wire = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');
const fact = (bytes, release) => ({bytes: bytes.length, sha256: hash(bytes),
  npmRelease: {bytes: release.length, sha256: hash(release), version: cohort.packageVersion}});
const original = name => ({name: '@actql/' + name, version: '0.0.0-development', private: true,
  type: 'module', exports: './index.mjs', files: ['index.mjs'],
  ...(name === 'sdk' ? {dependencies: {'@actql/client-wire': '0.0.0-development'}} : {})});

test('the exact original and normal release metadata bytes are distinct admitted representations', async () => {
  const scratch = await createOwnedScratch({parent: join(root, '_build'), prefix: 'release-image-original-',
    label: 'exact release image metadata'});
  const a = wire(original('sdk')), b = wire(releasePackageMetadata(original('sdk'), 'sdk', cohort));
  const file = join(scratch.path, 'package.json'), expected = fact(a, b);
  await writeFile(file, b);
  const captured = source.captureInitialControlImageSource(file, expected);
  assert.equal(captured.source, b.toString());
  assert.equal(captured.sha256, hash(b)); assert.equal(captured.representation, 'release');
  await writeFile(file, a);
  assert.equal(source.captureInitialControlImageSource(file, expected).representation, 'source');
  for (const changed of [wire({...JSON.parse(b), version: '0.0.2'}),
    wire({...JSON.parse(b), exports: './foreign.mjs'}), Buffer.from(b.toString().replace('Apache-2.0', 'changed'))]) {
    await writeFile(file, changed);
    assert.throws(() => source.captureInitialControlImageSource(file, expected), {code: 'InitialControlImageChanged'});
  }
  scratch.passed();
});

test('normal metadata-only staging keeps runtime bytes and supplies the bound manifest representation', async () => {
  const scratch = await createOwnedScratch({parent: join(root, '_build'), prefix: 'release-image-stage-',
    label: 'normal metadata staging image'});
  const input = join(scratch.path, 'input'), development = join(scratch.path, 'development');
  await mkdir(input); await mkdir(development);
  const metadata = original('client-wire'), code = Buffer.from('export const fixed = "original-runtime";\n');
  await writeFile(join(input, 'package.json'), wire(metadata)); await writeFile(join(input, 'index.mjs'), code);
  execFileSync('npm', ['pack', '--json', '--pack-destination', development,
    '--cache', join(scratch.path, 'cache')], {cwd: input, stdio: 'pipe'});
  const archive = join(development, 'actql-client-wire-0.0.0-development.tgz');
  const published = await stagePackage({archive, destination: scratch.path,
    name: 'client-wire', cohort, license: join(root, 'LICENSE')});
  const installed = await unpack(join(scratch.path, published.file), join(scratch.path, 'installed'));
  const manifest = await readFile(join(installed, 'package.json'));
  assert.deepEqual(await readFile(join(installed, 'index.mjs')), code);
  assert.deepEqual(manifest, wire(releasePackageMetadata(metadata, 'client-wire', cohort)));
  assert.equal(source.captureInitialControlImageSource(join(installed, 'package.json'),
    fact(wire(metadata), manifest)).representation, 'release');
  scratch.passed();
});

// Tiny independently named package Sources; no actual Host, operational
// admission, Provider or normal runtime is replaced or established here.
async function recipeFixture() {
  const scratch = await createOwnedScratch({parent: join(root, '_build'), prefix: 'release-image-cohort-',
    label: 'same original release image cohort'});
  const base = scratch.path, local = join(base, 'packages/local-node');
  const put = async (p, bytes) => {await mkdir(dirname(join(base, p)), {recursive: true}); await writeFile(join(base, p), bytes);};
  await put('release/client-cohort.json', wire(cohort));
  const manifests = new Map();
  for (const name of cohort.packages) {
    const metadata = original(name);
    if (name === 'local-node') {
      metadata.exports = {'.': './index.mjs', './selected-infer-startup': './selected-infer-startup.cjs'};
      metadata.dependencies = {'@actql/client-wire': '0.0.0-development', '@actql/sdk': '0.0.0-development'};
      metadata.files = ['index.mjs', 'selected-infer-startup.cjs', 'adapters', 'spec', '_build'];
    }
    if (name === 'node') {
      metadata.dependencies = {'@actql/local-node': '0.0.0-development', '@actql/sdk': '0.0.0-development'};
      metadata.files = ['index.mjs', 'selected-infer-startup.cjs'];
    }
    manifests.set(name, metadata);
    await put('packages/' + name + '/package.json', wire(metadata));
    await put('packages/' + name + '/index.mjs', 'export const original = ' + JSON.stringify(name) + ';\n');
    if (metadata.files.includes('selected-infer-startup.cjs')) await put('packages/' + name + '/selected-infer-startup.cjs', 'module.exports={};\n');
  }
  // The actual Node package resolver sees these concrete Source packages.
  const {symlink} = await import('node:fs/promises');
  await mkdir(join(base, 'node_modules/@actql'), {recursive: true});
  for (const name of cohort.packages) await symlink(join(base, 'packages', name), join(base, 'node_modules/@actql', name));
  const outputs = new Map([[initialControlPackageOriginal, Buffer.from('module.exports={imageInventory:undefined};\n')],
    ['adapters/host-node/embedded-local.mjs', Buffer.from('export function assertInitialControlHostPreparation(){}\n')],
    ['spec/local-check-environment.json', Buffer.from('{"original":true}\n')]]);
  for (const [p, b] of outputs) await put('packages/local-node/' + p, b);
  const runtime = Buffer.from('export const unchangedRuntime = 7;\n');
  await put('packages/local-node/_build/js/release/build/common/common.js', runtime);
  const rendered = renderInitialControlPackageOriginal({root: base, destination: local,
    inputs: {runtimeFiles: ['common/common.js']}, outputs});
  const context = {module: {exports: undefined}}; runInNewContext(rendered.toString(), context);
  const inventory = JSON.parse(JSON.stringify(context.module.exports.imageInventory));
  return {scratch, base, local, manifests, inventory, runtime, rendered};
}

test('the generator binds the one owned release cohort without altering any other image fact', async () => {
  const f = await recipeFixture();
  const local = f.inventory.images.find(v => v.path === 'package.json');
  const expected = wire(releasePackageMetadata(f.manifests.get('local-node'), 'local-node', cohort));
  assert.deepEqual(local.npmRelease, {version: cohort.packageVersion, bytes: expected.length, sha256: hash(expected)});
  assert.equal(f.inventory.localReleaseVersion, cohort.packageVersion);
  assert.equal(f.inventory.publicNode.releaseVersion, cohort.packageVersion);
  for (const p of f.inventory.packages) assert.equal(p.releaseVersion, cohort.packageVersion);
  assert.equal(f.inventory.images.find(v => v.path.endsWith('common.js')).sha256, hash(f.runtime));
  f.scratch.passed();
});

test('a normal staged cohort captures exact release images and refuses mixed or changed metadata before entry', async () => {
  const f = await recipeFixture();
  await writeFile(join(f.local, initialControlPackageOriginal), f.rendered);
  const development = join(f.base, 'development'), staged = join(f.base, 'staged'), app = join(f.base, 'app');
  await mkdir(development); await mkdir(staged); await mkdir(join(app, 'node_modules/@actql'), {recursive: true});
  const originals = new Map(), released = new Map();
  for (const name of cohort.packages) {
    const directory = join(f.base, 'packages', name);
    originals.set(name, await readFile(join(directory, 'package.json')));
    execFileSync('npm', ['pack', '--json', '--pack-destination', development,
      '--cache', join(f.base, 'cache')], {cwd: directory, stdio: 'pipe'});
    const publication = await stagePackage({archive: join(development, `actql-${name}-0.0.0-development.tgz`),
      destination: staged, name, cohort, license: join(root, 'LICENSE')});
    const extracted = await unpack(join(staged, publication.file), join(f.base, 'extracted-' + name));
    const target = join(app, 'node_modules/@actql', name);
    await rename(extracted, target);
    released.set(name, await readFile(join(target, 'package.json')));
  }
  const local = join(app, 'node_modules/@actql/local-node');
  assert.deepEqual(await readFile(join(local, '_build/js/release/build/common/common.js')), f.runtime);
  const entry = join(app, 'entry.mjs'), preload = join(app, 'preload.cjs');
  const custody = fileURLToPath(new URL('../adapters/host-node/initial-control-package-custody.cjs', import.meta.url));
  await writeFile(preload, [
    'const {captureInitialControlPackageCustody}=require(' + JSON.stringify(custody) + ');',
    'const inventory=require(' + JSON.stringify(join(local, initialControlPackageOriginal)) + ').imageInventory;',
    'globalThis.originalCustody=captureInitialControlPackageCustody(inventory,' + JSON.stringify(local) + ',' +
      JSON.stringify(entry) + ',' + JSON.stringify(join(app, 'node_modules/@actql/node/selected-infer-startup.cjs')) + ');',
    'globalThis.originalNamespace=originalCustody.initializeHostNamespace();',
  ].join('\n'));
  const run = body => {
    return writeFile(entry, body).then(() => spawnSync(process.execPath, ['--require', preload, entry],
      {cwd: app, env: {PATH: process.env.PATH}, encoding: 'utf8', timeout: 30000}));
  };
  const positive = await run('import assert from"node:assert/strict";assert.equal(typeof originalNamespace.assertInitialControlHostPreparation,"function");originalCustody.assertCurrent();console.log("coherent-release-images");');
  assert.equal(positive.error, undefined); assert.equal(positive.status, 0, positive.stderr);
  assert.equal(positive.stdout.trim(), 'coherent-release-images');
  const sdk = join(app, 'node_modules/@actql/sdk/package.json');
  await writeFile(sdk, originals.get('sdk'));
  const mixed = await run('throw new Error("EntryMustNotRun");');
  assert.notEqual(mixed.status, 0); assert.match(mixed.stderr, /InitialControlPackageImageChanged/);
  assert.doesNotMatch(mixed.stderr, /EntryMustNotRun/);
  const foreign = {...JSON.parse(released.get('sdk')), version: '0.0.2'};
  await writeFile(sdk, wire(foreign));
  const changed = await run('throw new Error("EntryMustNotRun");');
  assert.notEqual(changed.status, 0); assert.match(changed.stderr, /InitialControlImageChanged/);
  assert.doesNotMatch(changed.stderr, /EntryMustNotRun/);
  f.scratch.passed();
});
