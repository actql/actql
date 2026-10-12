import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareNativeLocalRuntime, inspectLocalLibrary} from './native-cli-local-runtime.mjs';
import {admitNativeArtifact} from './native-cli-release.mjs';
import {admitInstalledLocalRuntime, admitLocalRuntimePlatform, validateLocalRuntimeManifest, LOCAL_RUNTIME_MAX_BYTES} from '../packages/native-cli/lib/local-runtime.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const sourceSha = 'a'.repeat(40), platform = 'darwin-arm64';
// Fixed tool observations for the synthetic headers, not real ABI evidence.
const inspectFixture = (tool, args) => {
  if (tool === 'otool') {
    if (args[0] === '-D') return 'fixture:\n /fixture/original-id.dylib\n';
    if (args[0] === '-l') return 'cmd LC_BUILD_VERSION\n cmdsize 32\n platform 1\n minos 14.0\n sdk 14.1\n';
    return 'fixture:\n /fixture/original-id.dylib (compatibility version 1.0.0, current version 1.0.0)\n /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n';
  }
  return args[0] === '-d' ? ' (NEEDED) Shared library: [libc.so.6]\n' : 'GLIBC_2.2.5 GLIBC_2.34';
};

async function fixture(t, selectedPlatform = platform) {
  const root = await mkdtemp(join(tmpdir(), 'actql-cli-local-runtime-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const source = join(root, 'input'), output = join(root, 'output');
  await mkdir(source); await mkdir(output);
  const original = async (name, bytes) => {
    const path = join(source, name); await writeFile(path, bytes);
    return {path, bytes: bytes.length, sha256: hash(bytes)};
  };
  // Deliberately synthetic architecture headers. No dlopen, compiler, Provider
  // or CLI process runs, and these fixtures are not distribution artifacts.
  const library = tag => {
    const bytes = Buffer.alloc(64);
    if (selectedPlatform === 'darwin-arm64') {
      bytes.writeUInt32LE(0xfeedfacf, 0); bytes.writeUInt32LE(0x0100000c, 4); bytes.writeUInt32LE(6, 12);
    } else {
      bytes.write('ELF', 1); bytes[0] = 0x7f; bytes[4] = 2; bytes[5] = 1;
      bytes.writeUInt16LE(3, 16); bytes.writeUInt16LE(62, 18);
    }
    bytes.write(tag, 32); return bytes;
  };
  const raw = Buffer.from('{"value":"e\\u0301","nested":{"value":"é\\r\\n"},"missing":null}\r\n');
  const dependencies = selectedPlatform === 'darwin-arm64' ? ['/usr/lib/libSystem.B.dylib'] : ['libc.so.6'];
  const options = {sourceSha, platform: selectedPlatform,
    libraries: [
      {role: 'sqlite', name: selectedPlatform === platform ? 'libsqlite3.dylib' : 'libsqlite3.so', original: await original('sqlite', library('sqlite-fixture')), license: 'sqlite.txt', dependencies},
      {role: 'crypto', name: selectedPlatform === platform ? 'libcrypto.3.dylib' : 'libcrypto.so.3', original: await original('crypto', library('crypto-fixture')), license: 'crypto.txt', dependencies},
    ],
    assets: await Promise.all(['environment', 'registry', 'values', 'fragment', 'result-policy'].map(async role => ({role, original: await original(role, raw)}))),
    licenses: [
      {name: 'sqlite.txt', original: await original('sqlite-license', Buffer.from('Synthetic SQLite license fixture\n'))},
      {name: 'crypto.txt', original: await original('crypto-license', Buffer.from('Synthetic crypto license fixture\n'))},
    ]};
  const metadata = await prepareNativeLocalRuntime(output, options, inspectFixture);
  const expected = {sourceSha, platform: selectedPlatform, localRuntimeSha256: metadata.sha256};
  const manifest = JSON.parse(await readFile(join(output, 'local-runtime.json'), 'utf8'));
  return {root, source, output, options, metadata, expected, manifest, raw};
}

test('Local runtime sidecars bind exact source/platform/original bytes and finite licenses', async t => {
  const f = await fixture(t);
  const result = admitInstalledLocalRuntime({root: f.output, metadata: f.metadata, expected: f.expected});
  assert.deepEqual(result, f.manifest);
  assert.equal(result.libraries.length, 2); assert.equal(result.assets.length, 5); assert.equal(result.licenses.length, 2);
  for (const item of result.assets) assert.deepEqual(await readFile(join(f.output, item.path)), f.raw);
  assert.equal(f.metadata.sha256, hash(await readFile(join(f.output, 'local-runtime.json'))));
});

test('Linux x64 shared-library headers use the same explicit closure and source binding', async t => {
  const f = await fixture(t, 'linux-x64-gnu');
  assert.deepEqual(admitInstalledLocalRuntime({root: f.output, metadata: f.metadata, expected: f.expected}), f.manifest);
});

test('foreign source platform or manifest digest is refused without dependency discovery', async t => {
  const f = await fixture(t);
  for (const expected of [
    {...f.expected, sourceSha: 'b'.repeat(40)}, {...f.expected, platform: 'linux-x64-gnu'},
    {...f.expected, localRuntimeSha256: 'c'.repeat(64)},
  ]) assert.throws(() => admitInstalledLocalRuntime({root: f.output, metadata: f.metadata, expected}), e => e.exitCode === 65);
});

test('closed runtime metadata rejects missing roles duplicate paths and unknown fields', async t => {
  const f = await fixture(t);
  for (const change of [
    m => { m.libraries.pop(); },
    m => { m.assets = m.assets.filter(a => a.role !== 'result-policy'); },
    m => { m.assets[1] = m.assets[0]; },
    m => { m.libraries[1].role = 'sqlite'; },
    m => { m.assets[0].authority = true; },
    m => { m.authority = true; },
  ]) {
    const manifest = structuredClone(f.manifest); change(manifest);
    assert.throws(() => validateLocalRuntimeManifest(manifest, f.expected));
  }
});

test('ambient Homebrew absolute paths traversal and missing dependency closure are refused', async t => {
  const f = await fixture(t);
  for (const dependency of ['/opt/homebrew/lib/libcrypto.3.dylib', '../libcrypto.3.dylib', 'libmissing.dylib', '@rpath/libmissing.dylib']) {
    const manifest = structuredClone(f.manifest); manifest.libraries[0].dependencies = [dependency];
    assert.throws(() => validateLocalRuntimeManifest(manifest, f.expected));
  }
  for (const path of ['../outside', 'lib/../outside', '/tmp/outside', 'lib/link/file']) {
    const manifest = structuredClone(f.manifest); manifest.libraries[0].path = path;
    assert.throws(() => validateLocalRuntimeManifest(manifest, f.expected));
  }
});

test('unreferenced absent and blank license originals do not form an admitted runtime', async t => {
  const f = await fixture(t);
  const manifest = structuredClone(f.manifest); manifest.libraries[0].license = 'licenses/missing.txt';
  assert.throws(() => validateLocalRuntimeManifest(manifest, f.expected));
  const extra = structuredClone(f.manifest); extra.licenses.push({...extra.licenses[0], path: 'licenses/extra.txt'});
  assert.throws(() => validateLocalRuntimeManifest(extra, f.expected));
  const blank = Buffer.from('   '), options = structuredClone(f.options);
  await writeFile(options.licenses[0].original.path, blank);
  options.licenses[0].original.bytes = blank.length; options.licenses[0].original.sha256 = hash(blank);
  const destination = join(f.root, 'blank-license'); await mkdir(destination);
  await assert.rejects(prepareNativeLocalRuntime(destination, options, inspectFixture));
  await rm(join(f.output, f.manifest.licenses[0].path));
  assert.throws(() => admitInstalledLocalRuntime({root: f.output, metadata: f.metadata, expected: f.expected}), e => e.exitCode === 65);
});

test('exact dependency bytes are checked after copy and before Native launch', async t => {
  const f = await fixture(t);
  const path = join(f.output, f.manifest.libraries[0].path), bytes = await readFile(path); bytes[40] ^= 1;
  await writeFile(path, bytes);
  assert.throws(() => admitInstalledLocalRuntime({root: f.output, metadata: f.metadata, expected: f.expected}), e => e.exitCode === 65);
});

test('library file data directory and installation root symlinks are refused', async t => {
  const f = await fixture(t), item = f.manifest.libraries[0];
  const saved = join(f.root, 'saved-library'); await writeFile(saved, await readFile(join(f.output, item.path)));
  await rm(join(f.output, item.path)); await symlink(saved, join(f.output, item.path));
  assert.throws(() => admitInstalledLocalRuntime({root: f.output, metadata: f.metadata, expected: f.expected}), e => e.exitCode === 65);
  await rm(join(f.output, item.path)); await writeFile(join(f.output, item.path), await readFile(saved));
  await symlink(f.output, join(f.root, 'linked-root'));
  assert.throws(() => admitInstalledLocalRuntime({root: join(f.root, 'linked-root'), metadata: f.metadata, expected: f.expected}), e => e.exitCode === 65);
  const data = join(f.output, 'data'); await rm(data, {recursive: true}); await symlink(f.source, data);
  assert.throws(() => admitInstalledLocalRuntime({root: f.output, metadata: f.metadata, expected: f.expected}), e => e.exitCode === 65);
});

test('finite sidecar envelope rejects invalid byte counts and aggregate overflow', async t => {
  const f = await fixture(t);
  for (const size of [0, -1, 1.5, '64', LOCAL_RUNTIME_MAX_BYTES + 1]) {
    const manifest = structuredClone(f.manifest); manifest.libraries[0].bytes = size;
    assert.throws(() => validateLocalRuntimeManifest(manifest, f.expected));
  }
  const manifest = structuredClone(f.manifest); manifest.libraries[0].bytes = LOCAL_RUNTIME_MAX_BYTES;
  assert.throws(() => validateLocalRuntimeManifest(manifest, f.expected));
});

test('producer refuses a changed original before writing its sidecar directories', async t => {
  const f = await fixture(t), directory = join(f.root, 'changed'); await mkdir(directory);
  await writeFile(f.options.libraries[0].original.path, Buffer.alloc(64));
  await assert.rejects(prepareNativeLocalRuntime(directory, f.options, inspectFixture));
  await assert.rejects(readFile(join(directory, 'local-runtime.json')));
});

test('producer refuses architecture mismatch and symlinked input instead of selecting another library', async t => {
  const f = await fixture(t), directory = join(f.root, 'wrong-architecture'); await mkdir(directory);
  const wrong = Buffer.alloc(64); wrong.writeUInt32LE(0xfeedfacf, 0); wrong.writeUInt32LE(0x01000007, 4);
  await writeFile(f.options.libraries[0].original.path, wrong);
  const options = structuredClone(f.options); options.libraries[0].original.sha256 = hash(wrong);
  await assert.rejects(prepareNativeLocalRuntime(directory, options, inspectFixture));
  await rm(f.options.libraries[0].original.path);
  await symlink(f.options.libraries[1].original.path, f.options.libraries[0].original.path);
  await assert.rejects(prepareNativeLocalRuntime(directory, f.options, inspectFixture));
});

test('physical loader observations reject undeclared dependencies and ambient search paths', () => {
  const names = new Set(['libcrypto.3.dylib']);
  const linked = (tool, args) => args[0] === '-L' ? inspectFixture(tool, args)
    .replace('/usr/lib/libSystem.B.dylib', '@loader_path/libcrypto.3.dylib') : inspectFixture(tool, args);
  assert.deepEqual(inspectLocalLibrary('fixture', platform, names, linked),
    {dependencies: ['libcrypto.3.dylib'], abi: {minimumMacOS: '14.0'}});
  for (const dependency of ['/opt/homebrew/lib/libcrypto.3.dylib', '@rpath/libcrypto.3.dylib', '@loader_path/../libcrypto.3.dylib']) {
    assert.throws(() => inspectLocalLibrary('fixture', platform, names, (tool, args) => args[0] === '-L'
      ? inspectFixture(tool, args).replace('/usr/lib/libSystem.B.dylib', dependency) : inspectFixture(tool, args)));
  }
  assert.throws(() => inspectLocalLibrary('fixture', platform, names, (tool, args) => args[0] === '-l'
    ? `${inspectFixture(tool, args)}cmd LC_RPATH\n path /opt/homebrew/lib\n` : inspectFixture(tool, args)));
  const linux = (_tool, args) => args[0] === '-d'
    ? ' (NEEDED) Shared library: [libcrypto.so.3]\n (RUNPATH) Library runpath: [$ORIGIN]\n' : 'GLIBC_2.34';
  assert.deepEqual(inspectLocalLibrary('fixture', 'linux-x64-gnu', new Set(['libcrypto.so.3']), linux),
    {dependencies: ['libcrypto.so.3'], abi: {minimumGlibc: '2.34'}});
  for (const replacement of ['/usr/local/lib', '$ORIGIN:/opt/developer/lib', '']) {
    assert.throws(() => inspectLocalLibrary('fixture', 'linux-x64-gnu', new Set(['libcrypto.so.3']), (tool, args) =>
      linux(tool, args).replace('$ORIGIN', replacement)));
  }
  assert.throws(() => inspectLocalLibrary('fixture', 'linux-x64-gnu', new Set(), (_tool, args) =>
    args[0] === '-d' ? '' : 'GLIBC_2.34 GLIBCXX_3.4.30'));
});

test('declared dependency list cannot hide the physically observed loader requirement', async t => {
  const f = await fixture(t), destination = join(f.root, 'missing-physical-dependency'); await mkdir(destination);
  const options = structuredClone(f.options); options.libraries[0].dependencies = [];
  await assert.rejects(prepareNativeLocalRuntime(destination, options, inspectFixture));
  await assert.rejects(readFile(join(destination, 'local-runtime.json')));
});

test('bundled library deployment requirements are checked separately from Native binary integrity', async t => {
  const darwin = await fixture(t), linux = await fixture(t, 'linux-x64-gnu');
  for (const macOS of ['14.0', '14.1', '15.0']) admitLocalRuntimePlatform(darwin.manifest, {macOS});
  for (const macOS of ['13.9', undefined, 'unknown']) assert.throws(() => admitLocalRuntimePlatform(darwin.manifest, {macOS}), e => e.exitCode === 64);
  for (const glibc of ['2.34', '2.34.1', '2.36']) admitLocalRuntimePlatform(linux.manifest, {glibc});
  for (const glibc of ['2.33', undefined, 'musl']) assert.throws(() => admitLocalRuntimePlatform(linux.manifest, {glibc}), e => e.exitCode === 64);
});

test('existing artifact admission consumes the optional fixed Local profile and rejects altered sidecars', async t => {
  const f = await fixture(t), binary = Buffer.alloc(32);
  binary.writeUInt32LE(0xfeedfacf, 0); binary.writeUInt32LE(0x0100000c, 4);
  const metadata = {version: 'actql-native-cli-artifact/0.1', sourceSha, platform,
    binarySha256: hash(binary), binaryBytes: binary.length,
    generatedCSha256: 'b'.repeat(64), toolchainPinSha256: 'c'.repeat(64),
    notices: {}, toolchain: {evidence: 'synthetic fixture only'},
    abi: {format: 'Mach-O', minimumMacOS: '14.0'}, testedHost: {}, generation: [], localRuntime: f.metadata};
  await writeFile(join(f.output, 'actql-native-client'), binary);
  await writeFile(join(f.output, 'artifact.json'), JSON.stringify(metadata));
  assert.deepEqual(await admitNativeArtifact(f.output, sourceSha), metadata);
  await writeFile(join(f.output, 'data/result-policy.json'), Buffer.from('{"changed":true}'));
  await assert.rejects(admitNativeArtifact(f.output, sourceSha), e => e.exitCode === 65);
});
