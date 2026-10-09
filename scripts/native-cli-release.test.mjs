import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {platformKey, admitInstalledBinary} from '../packages/native-cli/bin/actql.mjs';
import {admitNativeArtifact} from './native-cli-release.mjs';
import {inspectNativeAbi} from './native-cli-artifact.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const binary = Buffer.alloc(32);
binary.writeUInt32LE(0xfeedfacf, 0); binary.writeUInt32LE(0x0100000c, 4);
const sourceSha = 'a'.repeat(40);
const metadata = {version: 'actql-native-cli-artifact/0.1', sourceSha,
  platform: 'darwin-arm64', binarySha256: digest(binary), binaryBytes: binary.length,
  generatedCSha256: 'b'.repeat(64), toolchainPinSha256: 'c'.repeat(64),
  notices: {'MOONBIT-CORE-LICENSE': 'd'.repeat(64), 'MOONBIT-CORE-NOTICE': 'e'.repeat(64)},
  toolchain: {diagnostic: 'synthetic fixture, not compiled Native evidence'},
  abi: {format: 'Mach-O'}, testedHost: {}, generation: []};
const expected = {sourceSha, binarySha256: metadata.binarySha256, binaryBytes: binary.length};

test('platform selection refuses other CPUs, musl and unknown libc without fallback', () => {
  assert.equal(platformKey({platform: 'darwin', arch: 'arm64'}), 'darwin-arm64');
  assert.equal(platformKey({platform: 'linux', arch: 'x64', glibc: '2.36'}), 'linux-x64-gnu');
  for (const value of [{platform: 'win32', arch: 'x64'}, {platform: 'darwin', arch: 'x64'},
    {platform: 'linux', arch: 'arm64', glibc: '2.36'}, {platform: 'linux', arch: 'x64'},
    {platform: 'linux', arch: 'x64', glibc: 'musl'}]) {
    assert.throws(() => platformKey(value), error => error.exitCode === 64);
  }
});

test('installed binary remains bound to source, platform and bytes', () => {
  admitInstalledBinary({key: metadata.platform, expected, metadata, binary});
  for (const changed of [{...metadata, sourceSha: 'd'.repeat(40)}, {...metadata, platform: 'linux-x64-gnu'},
    {...metadata, binaryBytes: binary.length + 1}, {...metadata, binarySha256: 'e'.repeat(64)}]) {
    assert.throws(() => admitInstalledBinary({key: metadata.platform, expected, metadata: changed, binary}),
      error => error.exitCode === 65);
  }
  assert.throws(() => admitInstalledBinary({key: metadata.platform, expected, metadata, binary: Buffer.alloc(32)}));
});

test('Linux executable glibc bound is checked independently of binary integrity', () => {
  const linux = {...metadata, platform: 'linux-x64-gnu', abi: {minimumGlibc: '2.34'}};
  admitInstalledBinary({key: linux.platform, expected, metadata: linux, binary, glibc: '2.36'});
  for (const glibc of ['2.33', '1.99', undefined, 'musl']) {
    assert.throws(() => admitInstalledBinary({key: linux.platform, expected, metadata: linux, binary, glibc}),
      error => error.exitCode === 64);
  }
});

test('ABI extraction records executable symbol requirements and shared libraries', () => {
  const abi = inspectNativeAbi('test-executable', 'linux-x64-gnu', (tool, args) => {
    assert.equal(tool, 'readelf');
    return args.includes('--version-info') ? 'GLIBC_2.2.5 GLIBC_2.34 GLIBC_2.17'
      : ' (NEEDED) Shared library: [libm.so.6]\n (NEEDED) Shared library: [libc.so.6]';
  });
  assert.equal(abi.minimumGlibc, '2.34'); assert.deepEqual(abi.sharedLibraries, ['libm.so.6', 'libc.so.6']);
  assert.equal(abi.httpLibraryBundled, false);
  assert.match(abi.httpLibraryRequirements, /newer glibc/u);
});

test('producer record rejects foreign SHA, wrong CPU, unknown fields and changed binary', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-cli-artifact-unit-'));
  try {
    await writeFile(join(directory, 'actql-native-client'), binary);
    const save = value => writeFile(join(directory, 'artifact.json'), JSON.stringify(value));
    await save(metadata); assert.deepEqual(await admitNativeArtifact(directory, sourceSha), metadata);
    await assert.rejects(admitNativeArtifact(directory, 'd'.repeat(40)));
    await save({...metadata, surplus: true}); await assert.rejects(admitNativeArtifact(directory, sourceSha));
    await save(metadata); await writeFile(join(directory, 'actql-native-client'), Buffer.alloc(32));
    await assert.rejects(admitNativeArtifact(directory, sourceSha));
    const cpu = Buffer.from(binary); cpu.writeUInt32LE(0x01000007, 4);
    await writeFile(join(directory, 'actql-native-client'), cpu); await save({...metadata, binarySha256: digest(cpu)});
    await assert.rejects(admitNativeArtifact(directory, sourceSha));
  } finally {await rm(directory, {recursive: true});}
});

test('source CLI metadata has no install hook and only exact OS binary dependencies', async () => {
  const packageJson = JSON.parse(await readFile(new URL('../packages/native-cli/package.json', import.meta.url), 'utf8'));
  assert.equal(packageJson.name, 'actql'); assert.equal(packageJson.version, '0.0.2'); assert.equal(packageJson.scripts, undefined);
  assert.deepEqual(packageJson.optionalDependencies, {'@actql/cli-darwin-arm64': '0.0.2', '@actql/cli-linux-x64-gnu': '0.0.2'});
});
