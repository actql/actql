import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtempSync, writeFileSync, chmodSync, symlinkSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {checkoutTree, checkBuilder, checkOwnedPreparation, localEngine} from './local-isolated-acceptance.mjs';
import {checkLocalImageDefinition, checkImageDefinition, localIsolatedEnvironment,
  localIsolatedRunArguments, isolatedRunArguments} from './isolation.mjs';
import {imageRuntime} from './isolated-runtime.mjs';
import {prepareIsolatedMutation, executeIsolatedMutation, prepareLocalIsolatedMutation} from './isolated-execution.mjs';

const owner = `local-${'a'.repeat(32)}`, imageId = `sha256:${'b'.repeat(64)}`;
const image = () => ({Id: imageId, Os: 'linux', Architecture: 'amd64', Config: {
  Labels: {'org.actql.local.owner': owner}, Env: Object.entries(localIsolatedEnvironment).map(([k, v]) => `${k}=${v}`),
  User: '1000:1000', WorkingDir: '/workspace', Entrypoint: ['/runtime/node', '/source/proofs/ci-evidence/isolated-mutations.mjs'],
  Cmd: null, Volumes: null, OnBuild: null}});

test('local and Actions image owner domains cannot authorize one another', () => {
  assert(checkLocalImageDefinition({image: image(), imageId, owner}));
  assert.throws(() => checkImageDefinition({image: image(), imageId, owner}));
  const changed = image(); changed.Config.Labels['org.actql.ci.owner'] = '1:2:3';
  assert.throws(() => checkLocalImageDefinition({image: changed, imageId, owner}));
  assert.throws(() => localIsolatedRunArguments({imageId, cidFile: '/owned/id', owner: '1:2:3'}));
  assert.throws(() => isolatedRunArguments({imageId, cidFile: '/owned/id', owner}));
});

test('local physical execution keeps the CI isolation restrictions and no inherited environment or mount', () => {
  const args = localIsolatedRunArguments({imageId, cidFile: '/owned/id', owner});
  assert(args.includes('--read-only') && args.includes('--network=none') && args.includes('--pull=never'));
  assert(args.includes('org.actql.local.owner=' + owner));
  assert(!args.some(arg => /^--(?:env|mount|volume)/u.test(arg)));
  const ci = isolatedRunArguments({imageId, cidFile: '/owned/id', owner: '1:2:3'});
  assert.deepEqual(args.map(arg => arg.replace(owner, '1:2:3').replace('org.actql.local.owner', 'org.actql.ci.owner')), ci);
});

test('local image refuses startup changes, inherited credentials and wrong platform', () => {
  for (const alter of [i => i.Config.Env.push('TOKEN=secret'), i => i.Config.Volumes = {'/source': {}},
    i => i.Config.Entrypoint = ['/bin/sh'], i => i.Architecture = 'arm64', i => i.Config.User = '0:0',
    i => i.Config.Labels['org.actql.local.owner'] = `local-${'c'.repeat(32)}`]) {
    const changed = image(); alter(changed);
    assert.throws(() => checkLocalImageDefinition({image: changed, imageId, owner}));
  }
});

test('immutable Linux builder identity, architecture and startup effects are checked', () => {
  const builder = {Id: imageId, Os: 'linux', Architecture: 'amd64', Config: {}};
  assert(checkBuilder(builder, imageId));
  for (const alter of [i => i.Architecture = 'arm64', i => i.Id = `sha256:${'c'.repeat(64)}`,
    i => i.Config.OnBuild = ['RUN external'], i => i.Config.Volumes = {'/out': {}}]) {
    const changed = structuredClone(builder); alter(changed); assert.throws(() => checkBuilder(changed, imageId));
  }
});

test('Linux preparer independently checks actual checkout bytes, modes and declared membership', t => {
  const directory = mkdtempSync(join(tmpdir(), 'local-isolated-git-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const bytes = Buffer.from('independent original\n'), path = join(directory, 'input');
  writeFileSync(path, bytes); chmodSync(path, 0o644);
  const object = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  const descriptor = {revision: 'a'.repeat(40), entries: [['input', {kind: 'blob', mode: '100644', object}]]};
  const tree = checkoutTree(directory, descriptor); assert.deepEqual(tree.read('input'), bytes);
  assert.throws(() => tree.read('../outside')); assert.throws(() => tree.read('undeclared'));
  writeFileSync(path, 'different bytes'); assert.throws(() => tree.read('input'), /Git blob/u);
  writeFileSync(path, bytes); chmodSync(path, 0o755); assert.throws(() => tree.read('input'), /mode/u);
  rmSync(path); symlinkSync('/etc/passwd', path); assert.throws(() => tree.read('input'), /kind/u);
});

test('the local diagnostic does not open existing Actions-only entry points', () => {
  const original = process.env.GITHUB_ACTIONS;
  delete process.env.GITHUB_ACTIONS;
  try {
    assert.throws(() => prepareIsolatedMutation({}), /CI-only/u);
    assert.throws(() => executeIsolatedMutation({}), /CI-only/u);
  } finally {
    if (original !== undefined) process.env.GITHUB_ACTIONS = original;
  }
  assert.throws(() => prepareLocalIsolatedMutation({owner: '1:2:3'}), /local owner/u);
});


test('preparer cleanup cannot remove a different owner or image', () => {
  const cid = 'd'.repeat(64), container = {Id: cid, Image: imageId, Config: {Labels: {'org.actql.local.owner': owner}}};
  assert(checkOwnedPreparation(container, {cid, imageId, owner}));
  for (const alter of [c => c.Image = `sha256:${'c'.repeat(64)}`, c => c.Id = 'e'.repeat(64),
    c => c.Config.Labels['org.actql.local.owner'] = `local-${'f'.repeat(32)}`]) {
    const changed = structuredClone(container); alter(changed);
    assert.throws(() => checkOwnedPreparation(changed, {cid, imageId, owner}));
  }
});


test('a named Docker launcher is preserved rather than replaced by its multicall target', t => {
  const directory = mkdtempSync(join(tmpdir(), 'local-isolated-launcher-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const target = join(directory, 'docker-tools'), launcher = join(directory, 'docker');
  writeFileSync(target, 'multicall target'); symlinkSync(target, launcher);
  assert.equal(localEngine(launcher), launcher);
  assert.throws(() => localEngine('docker')); assert.throws(() => localEngine(directory));
});


test('local environment inputs never enter the Actions runtime authority', () => {
  const manifest = {version: 'actql-isolated-mutation-inputs/0.1', localDiagnostic: true};
  assert.throws(() => imageRuntime(manifest), /authority/u);
  assert.equal(localIsolatedEnvironment.UV_USE_IO_URING, '0');
  const changed = image(); changed.Config.Env = changed.Config.Env.filter(entry => !entry.startsWith('UV_USE_IO_URING='));
  assert.throws(() => checkLocalImageDefinition({image: changed, imageId, owner}));
  const altered = image(); altered.Config.Env = altered.Config.Env.map(entry => entry === 'UV_USE_IO_URING=0' ? 'UV_USE_IO_URING=1' : entry);
  assert.throws(() => checkLocalImageDefinition({image: altered, imageId, owner}));
});
