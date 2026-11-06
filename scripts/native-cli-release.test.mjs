import assert from 'node:assert/strict';
import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {platformKey, macOSProductVersion, admitInstalledBinary} from '../packages/native-cli/bin/actql.mjs';
import {admitNativeArtifact, sharedRuntimeSourceDelta, requireLinuxLocalReleaseArtifacts} from './native-cli-release.mjs';
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
  abi: {format: 'Mach-O', minimumMacOS: '26.0'}, testedHost: {}, generation: []};
const expected = {sourceSha, binarySha256: metadata.binarySha256, binaryBytes: binary.length};

test('explicit Local release profile requires its already admitted Linux Local artifact', () => {
  // Selection-only fixtures. Actual artifact/library validation precedes this
  // check in the producer; these records do not claim executable admission.
  const linux = {platform: 'linux-x64-gnu', localRuntime: {syntheticSelection: true}};
  const remoteDarwin = {platform: 'darwin-arm64'};
  requireLinuxLocalReleaseArtifacts([linux]);
  requireLinuxLocalReleaseArtifacts([linux, remoteDarwin]);
  for (const records of [[], [remoteDarwin], [linux, linux]]) {
    assert.throws(() => requireLinuxLocalReleaseArtifacts(records), /requires one Linux x64 artifact/u);
  }
  for (const localRuntime of [undefined, null, false, 'claimed-local']) {
    assert.throws(() => requireLinuxLocalReleaseArtifacts([{platform: 'linux-x64-gnu', localRuntime}]),
      /cannot use a Remote-only Linux artifact/u);
  }
});

test('macOS version uses one bounded kernel query when available', () => {
  const calls = [];
  assert.equal(macOSProductVersion((command, args, options) => {
    calls.push({command, args, options: {encoding: options.encoding,
      maxBuffer: options.maxBuffer, timeout: options.timeout},
    compatibility: options.env.SYSTEM_VERSION_COMPAT,
    environmentCloned: options.env !== process.env,
    inheritedPathMatches: options.env.PATH === process.env.PATH});
    return {status: 0, signal: null, stdout: '26.2\n'};
  }), '26.2');
  assert.deepEqual(calls, [{command: '/usr/sbin/sysctl', args: ['-n', 'kern.osproductversion'],
    options: {encoding: 'utf8', maxBuffer: 1024, timeout: 1000},
    compatibility: '0', environmentCloned: true, inheritedPathMatches: true}]);
});

test('macOS version retains sw_vers for an unavailable kernel service', () => {
  for (const first of [{error: {code: 'ENOENT'}}, {status: 1, stdout: '26.2'},
    {status: 0, signal: 'SIGTERM', stdout: '26.2'}]) {
    const calls = [];
    const version = macOSProductVersion((command, args) => {
      calls.push({command, args});
      return calls.length === 1 ? first : {status: 0, stdout: '26.2\n'};
    });
    assert.equal(version, '26.2');
    assert.deepEqual(calls, [{command: '/usr/sbin/sysctl', args: ['-n', 'kern.osproductversion']},
      {command: '/usr/bin/sw_vers', args: ['-productVersion']}]);
  }
});

test('macOS version never replaces a valid unsupported version or admits missing replies', () => {
  for (const stdout of ['25.9', 'unavailable', '26.2\n26.1', '1'.repeat(48) + '.0', Buffer.from('26.2')]) {
    let calls = 0;
    const macOS = macOSProductVersion(() => {calls++; return {status: 0, stdout};});
    assert.equal(calls, 1);
    assert.throws(() => admitInstalledBinary({key: metadata.platform, expected, metadata, binary, macOS}),
      error => error.exitCode === 64);
  }
  assert.equal(macOSProductVersion(() => ({status: 1, stdout: ''})), undefined);
  assert.throws(() => admitInstalledBinary({key: metadata.platform, expected, metadata, binary,
    macOS: macOSProductVersion(() => ({status: 1, stdout: ''}))}), error => error.exitCode === 64);
});

test('macOS version agrees with the existing OS service and ignores compatibility spelling', {skip: process.platform !== 'darwin'}, () => {
  const before = process.env.SYSTEM_VERSION_COMPAT;
  try {
    process.env.SYSTEM_VERSION_COMPAT = '1';
    assert.equal(macOSProductVersion(), execFileSync('/usr/bin/sw_vers', ['-productVersion'], {
      encoding: 'utf8', env: {...process.env, SYSTEM_VERSION_COMPAT: '0'},
    }).trim());
  } finally {
    if (before === undefined) delete process.env.SYSTEM_VERSION_COMPAT;
    else process.env.SYSTEM_VERSION_COMPAT = before;
  }
});

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
  admitInstalledBinary({key: metadata.platform, expected, metadata, binary, macOS: '26.2'});
  for (const changed of [{...metadata, sourceSha: 'd'.repeat(40)}, {...metadata, platform: 'linux-x64-gnu'},
    {...metadata, binaryBytes: binary.length + 1}, {...metadata, binarySha256: 'e'.repeat(64)}]) {
    assert.throws(() => admitInstalledBinary({key: metadata.platform, expected, metadata: changed, binary}),
      error => error.exitCode === 65);
  }
  assert.throws(() => admitInstalledBinary({key: metadata.platform, expected, metadata, binary: Buffer.alloc(32)}));
});

test('macOS deployment bound is extracted and checked before Native starts', () => {
  const abi = inspectNativeAbi('fixture', 'darwin-arm64', (_tool, args) => args.includes('-l')
    ? 'cmd LC_BUILD_VERSION\n cmdsize 32\n platform 1\n minos 26.0\n sdk 26.2'
    : 'fixture:\n /usr/lib/libSystem.B.dylib');
  assert.equal(abi.minimumMacOS, '26.0');
  for (const macOS of ['26.0', '26.2', '27.0']) {
    admitInstalledBinary({key: metadata.platform, expected, metadata, binary, macOS});
  }
  for (const macOS of ['25.9', undefined, 'unavailable']) {
    assert.throws(() => admitInstalledBinary({key: metadata.platform, expected, metadata, binary, macOS}), error => error.exitCode === 64);
  }
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


test('combined CLI acceptance detects SDK and generated wire changes outside src', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-cli-cohort-source-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const git = (...args) => execFileSync('git', ['-c', 'user.name=Fixture',
    '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', ...args],
    {cwd: root, encoding: 'utf8'}).trim();
  const commit = () => {git('add', '.'); git('commit', '-qm', 'fixture'); return git('rev-parse', 'HEAD');};
  await mkdir(join(root, 'packages/sdk'), {recursive: true});
  await mkdir(join(root, 'packages/client-wire'), {recursive: true});
  await writeFile(join(root, 'packages/sdk/index.mjs'), 'export const protocol = 1;\n');
  await writeFile(join(root, 'packages/client-wire/client-host.generated.js'), 'export const schema = 1;\n');
  git('init', '-q'); const original = commit();
  await writeFile(join(root, 'README.md'), 'Documentation-only CLI handoff.\n');
  const docs = commit();
  assert.equal(sharedRuntimeSourceDelta(root, original, docs), '');
  await writeFile(join(root, 'packages/sdk/index.mjs'), 'export const protocol = 2;\n');
  const sdk = commit();
  assert.equal(sharedRuntimeSourceDelta(root, docs, sdk), 'packages/sdk/index.mjs');
  await writeFile(join(root, 'packages/client-wire/client-host.generated.js'), 'export const schema = 2;\n');
  const wire = commit();
  assert.equal(sharedRuntimeSourceDelta(root, sdk, wire), 'packages/client-wire/client-host.generated.js');
  assert.throws(() => sharedRuntimeSourceDelta(root, '--help', wire));
});
