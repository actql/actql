// These are build-DATA fixtures, never compiled native acceptance or producer
// authentication. Exercise the actual exporter/assembler without a compiler.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync,
  statSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {assembleNodeDirectoryNative, directoryNativeDescriptor, exportNodeDirectoryNativeInput}
  from './build-node-directory-native.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const wire = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');
const git = (root, ...args) => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
const targets = [['darwin', 'arm64', 'directory-darwin-arm64.node', 'directory-darwin.c'],
  ['linux', 'x64', 'local-files-linux-x64.node', 'local-files-linux.c']];
function fixture(t) {
  const scratch = mkdtempSync(join(tmpdir(), 'actql-native-input-data-'));
  t.after(() => rmSync(scratch, {recursive: true}));
  const root = join(scratch, 'source'); mkdirSync(root);
  for (const path of ['adapters/host-node/native/directory-darwin.c',
    'adapters/host-node/native/local-files-linux.c', 'adapters/host-node/native/napi-filesystem-helpers.inc',
    'adapters/connectors/local/site/root-filesystem-platform.inc',
    'adapters/connectors/local/site/root-filesystem.inc', 'adapters/connectors/local/site/root-file-writer.inc',
    'scripts/build-node-directory-native.mjs', 'scripts/build-local-node-adapters.mjs',
    'scripts/initial-control-package-images.mjs', 'toolchain.json', 'packages/local-node/package.json',
    'release/client-cohort.json']) {
    mkdirSync(dirname(join(root, path)), {recursive: true});
    copyFileSync(join(repository, path), join(root, path));
  }
  git(root, 'init', '-q'); git(root, 'add', '.');
  git(root, '-c', 'user.name=Native DATA fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-q', '-m', 'fixture');
  const normal = join(scratch, 'normal'), inputs = join(scratch, 'inputs');
  mkdirSync(join(normal, '_build/native'), {recursive: true}); mkdirSync(inputs);
  const contents = new Map();
  for (const [platform, arch, filename, sourceFile] of targets) {
    const bytes = Buffer.from(`Independent ${platform}/${arch} build DATA; not executable.`);
    const sourcePath = 'adapters/host-node/native/' + sourceFile;
    const original = {platform, arch, node: '22.22.0', moduleAbi: '127', napi: 8,
      source: {path: sourcePath, sha256: sha(readFileSync(join(root, sourcePath)))},
      compilerSha256: 'c'.repeat(64), nodeSha256: sha(readFileSync(process.execPath)),
      ...(platform === 'darwin' ? {sdkSettingsSha256: 'd'.repeat(64)} : {}),
      headers: [{path: 'node/node_api.h', bytes: 17, sha256: 'e'.repeat(64)}],
      binary: {path: '_build/native/' + filename, bytes: bytes.length, sha256: sha(bytes)}};
    contents.set(`${platform}-${arch}`, {bytes, descriptor: wire(original), original, filename});
  }
  const selected = contents.get(`${process.platform}-${process.arch}`);
  assert(selected, 'This DATA fixture selects one of the two supported producer platforms');
  writeFileSync(join(normal, '_build/native', selected.filename), selected.bytes);
  writeFileSync(join(normal, directoryNativeDescriptor), selected.descriptor);
  const exported = exportNodeDirectoryNativeInput({root, destination: normal, output: join(inputs, 'current')});
  const seed = JSON.parse(readFileSync(exported.manifest));
  for (const [target, value] of contents) {
    const directory = join(inputs, target); mkdirSync(directory);
    writeFileSync(join(directory, value.filename), value.bytes);
    writeFileSync(join(directory, 'directory-original.json'), value.descriptor);
    const fact = (path, bytes) => ({path, bytes: bytes.length, mode: 0o644, sha256: sha(bytes)});
    const manifest = {...seed, engine: {...seed.engine, platform: value.original.platform,
      arch: value.original.arch}, original: fact('directory-original.json', value.descriptor),
      binary: fact(value.filename, value.bytes)};
    writeFileSync(join(directory, 'native-input.json'), wire(manifest));
  }
  const selection = join(inputs, 'selection.json'), destination = join(scratch, 'assembled');
  mkdirSync(destination);
  const choose = (paths = targets.map(([platform, arch]) => `${platform}-${arch}/native-input.json`)) => {
    const data = {version: 'actql-node-directory-native-selection/0.1', inputs: paths.map(path => ({path,
      sha256: sha(readFileSync(join(inputs, path)))}))};
    writeFileSync(selection, wire(data)); return sha(wire(data));
  };
  const assemble = (options = {}) => assembleNodeDirectoryNative({root, destination, selection,
    expectedSha256: sha(readFileSync(selection)), ...options});
  choose();
  return {root, inputs, normal, selection, destination, contents, seed, choose, assemble, exported};
}

test('native input export binds source/version/recipe and preserves original descriptor and bytes', t => {
  const f = fixture(t), manifestBytes = readFileSync(f.exported.manifest);
  assert.equal(sha(manifestBytes), f.exported.sha256);
  assert.equal(f.seed.source.revision, git(f.root, 'rev-parse', 'HEAD'));
  assert.equal(f.seed.source.packageVersion, JSON.parse(readFileSync(join(f.root, 'release/client-cohort.json'))).packageVersion);
  assert.equal(f.seed.source.recipe.find(value => value.path === 'scripts/build-node-directory-native.mjs').sha256,
    sha(readFileSync(join(f.root, 'scripts/build-node-directory-native.mjs'))));
  const selected = f.contents.get(`${process.platform}-${process.arch}`);
  assert.deepEqual(readFileSync(join(dirname(f.exported.manifest), f.seed.original.path)), selected.descriptor);
  assert.deepEqual(readFileSync(join(dirname(f.exported.manifest), f.seed.binary.path)), selected.bytes);
  assert.equal(manifestBytes.includes(Buffer.from(f.root)), false);
});

test('explicit two-target assembly retains both original records and has deterministic read-only verification', t => {
  const f = fixture(t), first = f.assemble();
  const descriptor = JSON.parse(first.get(directoryNativeDescriptor));
  assert.deepEqual(descriptor.targets.map(value => `${value.platform}-${value.arch}`), ['darwin-arm64', 'linux-x64']);
  for (const target of descriptor.targets) {
    const expected = f.contents.get(`${target.platform}-${target.arch}`);
    assert.equal(target.originalSource, expected.descriptor.toString('utf8'));
    assert.equal(target.originalSha256, sha(expected.descriptor));
    assert.deepEqual(target.original, expected.original);
    assert.deepEqual(first.get(expected.original.binary.path), expected.bytes);
  }
  const before = [...first.keys()].map(path => statSync(join(f.destination, path)).ino);
  f.assemble({check: true});
  assert.deepEqual([...first.keys()].map(path => statSync(join(f.destination, path)).ino), before);
  f.choose(['linux-x64/native-input.json', 'darwin-arm64/native-input.json']);
  assert.deepEqual(f.assemble().get(directoryNativeDescriptor), first.get(directoryNativeDescriptor));
});

test('changed selection, input bytes and source bindings refuse before changing an existing output', t => {
  const f = fixture(t), before = f.assemble().get(directoryNativeDescriptor);
  assert.throws(() => f.assemble({expectedSha256: 'f'.repeat(64)}), /ChangedDirectoryNativeSelection/);
  const binary = join(f.inputs, 'linux-x64/local-files-linux-x64.node');
  writeFileSync(binary, 'changed');
  assert.throws(f.assemble, /ChangedDirectoryNativeInput/);
  writeFileSync(binary, f.contents.get('linux-x64').bytes);
  const manifest = join(f.inputs, 'linux-x64/native-input.json'), original = readFileSync(manifest);
  for (const field of ['revision', 'packageVersion', 'recipe']) {
    const value = JSON.parse(original);
    value.source[field] = field === 'recipe' ? [] : 'different';
    writeFileSync(manifest, wire(value)); f.choose();
    assert.throws(f.assemble, /WrongDirectoryNativeSource/);
  }
  writeFileSync(manifest, original); f.choose();
  assert.deepEqual(readFileSync(join(f.destination, directoryNativeDescriptor)), before);
});

test('duplicate targets and descriptor/binary disagreement never produce a combined original', t => {
  const f = fixture(t);
  f.choose(['linux-x64/native-input.json', 'linux-x64/native-input.json']);
  assert.throws(f.assemble, /InvalidDirectoryNativeInput/);
  f.choose();
  const path = join(f.inputs, 'linux-x64/directory-original.json');
  const original = JSON.parse(readFileSync(path)); original.binary.sha256 = 'a'.repeat(64);
  const bytes = wire(original); writeFileSync(path, bytes);
  const manifestPath = join(f.inputs, 'linux-x64/native-input.json'), manifest = JSON.parse(readFileSync(manifestPath));
  manifest.original.bytes = bytes.length; manifest.original.sha256 = sha(bytes);
  writeFileSync(manifestPath, wire(manifest)); f.choose();
  assert.throws(f.assemble, /InvalidDirectoryNativeOriginal/);
});

test('aliased inputs, unsupported files and changed modes remain refused', t => {
  const f = fixture(t), path = join(f.inputs, 'linux-x64/local-files-linux-x64.node');
  const alias = join(dirname(f.inputs), 'input-alias'); symlinkSync(f.inputs, alias);
  assert.throws(() => f.assemble({selection: join(alias, 'selection.json')}), /InvalidDirectoryNativeInput/);
  const sourceAlias = join(dirname(f.root), 'source-alias'); symlinkSync(f.root, sourceAlias);
  assert.throws(() => f.assemble({root: sourceAlias}), /InvalidDirectoryNativeInput/);
  const outside = join(f.inputs, 'unselected.node'); copyFileSync(path, outside);
  unlinkSync(path); symlinkSync(outside, path);
  assert.throws(f.assemble, /AliasedDirectoryNativeInput/);
  unlinkSync(path); copyFileSync(outside, path); chmodSync(path, 0o755);
  assert.throws(f.assemble, /ChangedDirectoryNativeInput/);
  chmodSync(path, 0o644);
  writeFileSync(join(f.inputs, 'linux-x64/unselected.node'), 'stale');
  assert.throws(f.assemble, /InvalidDirectoryNativeInput/);
});

test('dirty source and stale output refuse without an implicit platform or source fallback', t => {
  const f = fixture(t);
  writeFileSync(join(f.root, 'toolchain.json'), '{}');
  assert.throws(f.assemble, /DirtyDirectoryNativeSource/);
  git(f.root, 'checkout', '--', 'toolchain.json');
  mkdirSync(join(f.destination, '_build/native'), {recursive: true});
  writeFileSync(join(f.destination, '_build/native/unselected.node'), 'stale');
  assert.throws(f.assemble, /StaleDirectoryNativeOutput/);
});
