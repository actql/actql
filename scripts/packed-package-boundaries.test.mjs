import assert from 'node:assert/strict';
import {mkdtemp, mkdir, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {auditPackedPackages} from './packed-package-boundaries.mjs';

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
      const packed = JSON.parse(run(['pack', '--json', '--pack-destination', root],
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
