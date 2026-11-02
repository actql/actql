// Native version build DATA and focused real C/stdlib mechanism. No complete
// CLI/Common/provider producer, Host, Store, Run or public install acceptance.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {nativePackageVersion, nativeVersionCompilerArguments, observeNativePackageVersion} from './native-cli-version.mjs';
import {admitNativeArtifact, requireNativePackageVersion} from './native-cli-artifact-reader.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

test('Native package version: shared grammar and finite literal bind only the original stub, never another compiler step', () => {
  const args = ['-O2', '-c', './src/cmd/native_client/version_stub.c', '-o', '/owned/version.o'];
  assert.deepEqual(nativeVersionCompilerArguments(args, repository, '0.0.7-rc.1'),
    [...args, '-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION="0.0.7-rc.1"']);
  assert.deepEqual(args, ['-O2', '-c', './src/cmd/native_client/version_stub.c', '-o', '/owned/version.o']);
  for (const source of ['src/cmd/native_client/stdout_stub.c', '/foreign/version_stub.c', '/owned/native_client.c']) {
    const original = ['-c', source, '-o', '/owned/other.o'];
    assert.deepEqual(nativeVersionCompilerArguments(original, repository, '0.0.7'), original);
  }
  assert.throws(() => nativeVersionCompilerArguments([...args, '-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION="0.0.8"'], repository, '0.0.7'), /Duplicate/u);
  for (const value of ['patch', '0.0.7rc1', '0.0.7\n', '0.0.' + '1'.repeat(125)]) assert.throws(() => nativePackageVersion(value));
  assert.equal(nativePackageVersion('0.0.' + '1'.repeat(124)).length, 128);
});

test('Native package version: observation requires the same executable banner and an ordinary successful terminal', () => {
  const inspect = (code = 0, stdout = '0.0.7-rc.1\n', signal = null, stderr = '') =>
    (_file, args, options) => {
      assert.deepEqual(args, ['--version']); assert.equal(options.env.PATH, '');
      assert.equal(options.env.ACTQL_NATIVE_LOCAL_RUNTIME, undefined); assert.equal(options.timeout, 10000);
      return {status: code, stdout, signal, stderr};
    };
  assert.equal(observeNativePackageVersion('/selected/binary', '0.0.7-rc.1', inspect()).stdout, '0.0.7-rc.1\n');
  for (const read of [inspect(1), inspect(0, '0.1\n'), inspect(0, '0.0.7-rc.1\n', 'SIGTERM'), inspect(0, '0.0.7-rc.1\n', null, 'warning')])
    assert.throws(() => observeNativePackageVersion('/selected/binary', '0.0.7-rc.1', read));
});

test('Native package version: legacy byte reads remain distinct from new version-bound release predicates', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-version-metadata-',
    label: 'Native artifact version metadata controls'});
  const binary = Buffer.alloc(64); binary.writeUInt32LE(0xfeedfacf); binary.writeUInt32LE(0x0100000c, 4);
  const legacy = {version: 'actql-native-cli-artifact/0.1', sourceSha: 'a'.repeat(40), platform: 'darwin-arm64',
    binarySha256: sha(binary), binaryBytes: binary.length, generatedCSha256: 'b'.repeat(64), toolchainPinSha256: 'c'.repeat(64),
    notices: {}, toolchain: {}, abi: {format: 'Mach-O', minimumMacOS: '11.0'}, testedHost: {}, generation: []};
  const save = body => writeFile(join(scratch.path, 'artifact.json'), JSON.stringify(body));
  await writeFile(join(scratch.path, 'actql-native-client'), binary); await save(legacy);
  assert.deepEqual(await admitNativeArtifact(scratch.path, legacy.sourceSha), legacy);
  assert.throws(() => requireNativePackageVersion(legacy, '0.0.7'), /explicitly versioned/u);
  const current = {...legacy, packageVersion: '0.0.7', packageVersionObservation: {
    argv: ['--version'], stdout: '0.0.7\n', code: 0, signal: null,
    binarySha256: legacy.binarySha256, binaryBytes: legacy.binaryBytes, buildInputSha256: 'd'.repeat(64)}};
  await save(current); assert.deepEqual(await admitNativeArtifact(scratch.path, legacy.sourceSha), current);
  for (const changed of [{stdout: '0.1\n'}, {binarySha256: 'e'.repeat(64)}, {binaryBytes: 1},
    {code: 1}, {signal: 'SIGTERM'}, {argv: ['--help']}, {buildInputSha256: 'unknown'}]) {
    await save({...current, packageVersionObservation: {...current.packageVersionObservation, ...changed}});
    await assert.rejects(admitNativeArtifact(scratch.path, legacy.sourceSha));
  }
  await scratch.passed();
});

test('Native package version: actual artifact CLI refuses invalid or duplicated selection before creating build output', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-version-argv-',
    label: 'Native version artifact CLI refusal'});
  const destination = join(scratch.path, 'unstarted-artifact');
  for (const args of [['--package-version', 'patch'], ['--package-version', '0.0.7rc1'],
    ['--package-version'], ['--package-version', '0.0.7', '--package-version', '0.0.8']]) {
    const result = spawnSync(process.execPath, ['scripts/native-cli-artifact.mjs', destination, ...args],
      {cwd: repository, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024});
    assert.ifError(result.error); assert.equal(result.signal, null); assert.notEqual(result.status, 0);
    await assert.rejects(lstat(destination), {code: 'ENOENT'});
  }
  await scratch.passed();
});
