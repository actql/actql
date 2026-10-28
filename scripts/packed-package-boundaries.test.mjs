import assert from 'node:assert/strict';
import {mkdtemp, mkdir, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {normalNpmPackJsonArgs, parseNpmPackJson} from './packed-client-packages.mjs';

async function peerFixture(t, {optional = true, declared = true} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'packed-package-peer-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const entry = join(root, 'node_modules/@actql/entry');
  await mkdir(entry, {recursive: true});
  await writeFile(join(entry, 'package.json'), JSON.stringify({name: '@actql/entry',
    type: 'module', exports: './index.mjs',
    ...(declared ? {peerDependencies: {'@fixture/optional': '1.0.0'}} : {}),
    ...(optional ? {peerDependenciesMeta: {'@fixture/optional': {optional: true}}} : {}),
  }));
  await writeFile(join(entry, 'index.mjs'),
    "export const load = () => import('@fixture/optional');\n");
  const install = async (directory = join(root, 'node_modules/@fixture/optional')) => {
    await mkdir(directory, {recursive: true});
    await writeFile(join(directory, 'package.json'), JSON.stringify({name: '@fixture/optional',
      type: 'module', exports: './index.mjs'}));
    await writeFile(join(directory, 'index.mjs'), 'export const value = 1;\n');
    return directory;
  };
  return {root, entry, install};
}

test('installed graph permits an absent declared optional peer', async t => {
  const {root} = await peerFixture(t);
  auditPackedPackages(root, ['entry']);
});

test('installed graph audits a peer installed after an absent optional-peer scan', async t => {
  const {root, install} = await peerFixture(t);
  auditPackedPackages(root, ['entry']);
  await install();
  auditPackedPackages(root, ['entry']);
});

test('installed graph verifies a privately installed optional peer', async t => {
  const {root, install} = await peerFixture(t);
  await install();
  auditPackedPackages(root, ['entry']);
});

test('installed graph refuses a missing required peer', async t => {
  const {root} = await peerFixture(t, {optional: false});
  assert.throws(() => auditPackedPackages(root, ['entry']), {code: 'MODULE_NOT_FOUND'});
});

test('installed graph requires a peer declaration as well as optional metadata', async t => {
  const {root} = await peerFixture(t, {declared: false});
  assert.throws(() => auditPackedPackages(root, ['entry']), /Undeclared dependency/u);
});

test('installed graph refuses an optional peer with a missing exported file', async t => {
  const {root, install} = await peerFixture(t);
  const peer = await install();
  await rm(join(peer, 'index.mjs'));
  assert.throws(() => auditPackedPackages(root, ['entry']), {code: 'MODULE_NOT_FOUND'});
});

test('installed graph refuses an optional peer without package metadata', async t => {
  const {root} = await peerFixture(t);
  await mkdir(join(root, 'node_modules/@fixture/optional'), {recursive: true});
  assert.throws(() => auditPackedPackages(root, ['entry']), {code: 'MODULE_NOT_FOUND'});
});

test('installed graph refuses an optional peer with a dangling package link', async t => {
  const {root} = await peerFixture(t);
  await mkdir(join(root, 'node_modules/@fixture'), {recursive: true});
  await symlink(join(root, 'missing-peer'),
    join(root, 'node_modules/@fixture/optional'), 'dir');
  assert.throws(() => auditPackedPackages(root, ['entry']), {code: 'MODULE_NOT_FOUND'});
});

test('installed graph refuses optional peers resolved outside the consumer', async t => {
  const {root, install} = await peerFixture(t);
  const outside = await mkdtemp(join(tmpdir(), 'packed-peer-outside-'));
  t.after(() => rm(outside, {recursive: true, force: true}));
  await install(outside);
  await mkdir(join(root, 'node_modules/@fixture'), {recursive: true});
  await symlink(outside, join(root, 'node_modules/@fixture/optional'), 'dir');
  assert.throws(() => auditPackedPackages(root, ['entry']), /Dependency outside consumer/u);
});

test('installed graph refuses undeclared dependencies even when separately installed', async () => {
  const root = await mkdtemp(join(tmpdir(), 'packed-package-audit-'));
  try {
    for (const name of ['entry', 'hidden']) {
      const path = join(root, 'node_modules/@actql', name);
      await mkdir(path, {recursive: true});
      await writeFile(join(path, 'package.json'), JSON.stringify({name: `@actql/${name}`,
        type: 'module', exports: './index.mjs'}));
      await writeFile(join(path, 'index.mjs'), name === 'entry'
        ? "export {value} from '@actql/hidden';\n" : 'export const value = 1;\n');
    }
    assert.throws(() => auditPackedPackages(root, ['entry']), /Undeclared dependency/u);
    const entry = join(root, 'node_modules/@actql/entry');
    await writeFile(join(entry, 'package.json'), JSON.stringify({name: '@actql/entry',
      type: 'module', exports: './index.mjs', dependencies: {'@actql/hidden': '1.0.0'}}));
    auditPackedPackages(root, ['entry']);
    await rm(join(entry, 'index.mjs'));
    assert.throws(() => auditPackedPackages(root, ['entry']), /Missing or escaped export/u);
  } finally { await rm(root, {recursive: true, force: true}); }
});

async function commonJSFixture(t, code, {esmEntry = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'packed-package-cjs-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const entry = join(root, 'node_modules/@actql/entry');
  await mkdir(entry, {recursive: true});
  await writeFile(join(entry, 'package.json'), JSON.stringify({name: '@actql/entry',
    type: 'module', exports: esmEntry ? './index.mjs' : './index.cjs'}));
  await writeFile(join(entry, 'index.cjs'), code);
  if (esmEntry) await writeFile(join(entry, 'index.mjs'),
    "import original from './index.cjs'; export default original;\n");
  return root;
}

test('installed graph classifies the compiler helper for a CommonJS require property', async t => {
  const root = await commonJSFixture(t, 'module.exports = {cache: require.cache};\n');
  auditPackedPackages(root, ['entry']);
});

test('installed graph classifies a CommonJS compiler helper reached through an ESM export', async t => {
  const root = await commonJSFixture(t, 'module.exports = {cache: require.cache};\n', {esmEntry: true});
  auditPackedPackages(root, ['entry']);
});

for (const [label, code] of [
  ['static import', "import '<runtime>'; module.exports = {};\n"],
  ['static import alongside a generated helper',
    "import '<runtime>'; module.exports = {cache: require.cache};\n"],
  ['named re-export', "export {value} from '<runtime>'; module.exports = {};\n"],
  ['wildcard re-export', "export * from '<runtime>'; module.exports = {};\n"],
  ['CommonJS require', "require('<runtime>'); module.exports = {};\n"],
  ['dynamic import', "import('<runtime>'); module.exports = {};\n"],
]) test(`installed graph refuses an authored runtime-marker ${label}`, async t => {
  const root = await commonJSFixture(t, code);
  assert.throws(() => auditPackedPackages(root, ['entry']), /Undeclared dependency/u);
});

test('installed graph still refuses an undeclared dependency beside the compiler helper', async t => {
  const root = await commonJSFixture(t,
    "module.exports = {cache: require.cache, hidden: require('@fixture/hidden')};\n");
  assert.throws(() => auditPackedPackages(root, ['entry']), /Undeclared dependency/u);
});

test('installed graph does not mistake comments or data for authored runtime-marker imports', async t => {
  const root = await commonJSFixture(t,
    "// import '<runtime>';\nmodule.exports = {cache: require.cache, text: '<runtime>'};\n");
  auditPackedPackages(root, ['entry']);
});

test('normal SDK tarball resolves every shipped relative module outside the checkout', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-sdk-package-closure-'));
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const env = {...process.env, npm_config_cache: join(root, 'npm-cache'),
    npm_config_offline: 'true'};
  const run = (args, cwd) => {
    const result = spawnSync('npm', args, {cwd, env, encoding: 'utf8', timeout: 30_000});
    assert.equal(result.status, 0, JSON.stringify({args, status: result.status,
      signal: result.signal, stdout: result.stdout, stderr: result.stderr}));
    return result.stdout;
  };
  try {
    const tarballs = [];
    for (const name of ['client-wire', 'sdk']) {
      const packed = parseNpmPackJson(run(normalNpmPackJsonArgs(['pack', '--json', '--pack-destination', root]),
        join(repository, 'packages', name)));
      const entries = Array.isArray(packed) ? packed : Object.values(packed);
      assert.equal(entries.length, 1, JSON.stringify(packed));
      assert.equal(entries[0].name, `@actql/${name}`);
      assert.equal(typeof entries[0].filename, 'string');
      tarballs.push(join(root, entries[0].filename));
    }
    await writeFile(join(root, 'package.json'), JSON.stringify({private: true, type: 'module'}));
    run(['install', '--ignore-scripts', '--no-audit', '--no-fund', ...tarballs], root);
    auditPackedPackages(root, ['sdk', 'client-wire']);
    const sdk = await import(pathToFileURL(join(root, 'node_modules/@actql/sdk/index.mjs')));
    assert.equal(typeof sdk.connect, 'function');
  } finally { await rm(root, {recursive: true, force: true}); }
});
