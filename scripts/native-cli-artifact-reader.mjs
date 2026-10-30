// Existing artifact admission, shared by producer-layout and staged readers.
// This does not execute a binary or grant runtime/ABI acceptance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {admitInstalledLocalRuntime} from '../packages/native-cli/lib/local-runtime.mjs';
import {nativeCliPlatforms as platforms} from './native-cli-package-inputs.mjs';
import {releaseVersion} from './release-version.mjs';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const exact = (value, keys) => assert.deepEqual(Object.keys(value).sort(), [...keys].sort());

async function readArtifact(directory, sourceSha, binaryMember) {
  const record = JSON.parse(await readFile(join(directory, 'artifact.json'), 'utf8'));
  exact(record, ['version', 'sourceSha', 'platform', 'binarySha256', 'binaryBytes', 'generatedCSha256', 'toolchainPinSha256', 'notices', 'toolchain', 'abi', 'testedHost', 'generation',
    ...(Object.hasOwn(record, 'localRuntime') ? ['localRuntime'] : []),
    ...(Object.hasOwn(record, 'packageVersion') ? ['packageVersion', 'packageVersionObservation'] : [])]);
  assert.equal(record.version, 'actql-native-cli-artifact/0.1'); assert.equal(record.sourceSha, sourceSha);
  assert(Object.hasOwn(platforms, record.platform), 'Unknown Native artifact platform');
  for (const key of ['binarySha256', 'generatedCSha256', 'toolchainPinSha256']) assert.match(record[key], /^[a-f0-9]{64}$/u);
  assert(Number.isSafeInteger(record.binaryBytes) && record.binaryBytes > 0 && record.binaryBytes <= 64 * 1024 * 1024);
  const bytes = await readFile(join(directory, binaryMember));
  assert.equal(bytes.length, record.binaryBytes); assert.equal(hash(bytes), record.binarySha256);
  if (Object.hasOwn(record, 'packageVersion')) requireNativePackageVersion(record, record.packageVersion);
  if (record.platform === 'darwin-arm64') {
    assert.equal(bytes.readUInt32LE(0), 0xfeedfacf); assert.equal(bytes.readUInt32LE(4), 0x0100000c);
    assert.equal(record.abi.format, 'Mach-O');
    assert.match(record.abi.minimumMacOS, /^\d+\.\d+(?:\.\d+)?$/u);
  } else {
    assert.equal(bytes.subarray(0, 4).toString('hex'), '7f454c46'); assert.equal(bytes[4], 2); assert.equal(bytes[5], 1);
    assert.equal(bytes.readUInt16LE(18), 62); assert.equal(record.abi.format, 'ELF');
    assert.match(record.abi.minimumGlibc, /^\d+\.\d+$/u);
  }
  if (record.localRuntime !== undefined) admitInstalledLocalRuntime({root: directory,
    expected: {sourceSha, platform: record.platform, localRuntimeSha256: record.localRuntime.sha256}, metadata: record.localRuntime});
  return record;
}

export function requireNativePackageVersion(record, version) {
  const selected = releaseVersion(version);
  assert(selected.version.length <= 128, 'Native package version exceeds its original bounded literal');
  assert.equal(record.packageVersion, selected.version, 'Native release requires the original explicitly versioned executable');
  const observation = record.packageVersionObservation;
  assert(observation && typeof observation === 'object');
  exact(observation, ['argv', 'stdout', 'code', 'signal', 'binarySha256', 'binaryBytes', 'buildInputSha256']);
  assert.deepEqual(observation.argv, ['--version']); assert.equal(observation.code, 0); assert.equal(observation.signal, null);
  assert.equal(observation.stdout, `${selected.version}\n`);
  assert.equal(observation.binarySha256, record.binarySha256); assert.equal(observation.binaryBytes, record.binaryBytes);
  assert.match(observation.buildInputSha256, /^[a-f0-9]{64}$/u);
  // Historical unstamped artifacts still have their old read-only byte scope.
  // This extra release predicate never grants their missing version acceptance.
  return record;
}

export function requireNativeCohortPackageVersions(manifest) {
  assert(Array.isArray(manifest.artifacts) && manifest.artifacts.length > 0);
  for (const record of manifest.artifacts) requireNativePackageVersion(record, manifest.cohort.packageVersion);
  return manifest;
}


export async function admitNativeArtifact(directory, sourceSha) {
  return readArtifact(directory, sourceSha, 'actql-native-client');
}

export async function admitInstalledNativeArtifact(directory, sourceSha) {
  return readArtifact(directory, sourceSha, 'bin/actql-native-client');
}
