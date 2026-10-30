// Standalone consumer admission. No Node launcher, compiler, credential,
// product implementation, source build or substitute Native executable.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, readFile} from 'node:fs/promises';
import {isAbsolute, join, resolve} from 'node:path';
import {inventory, unpack} from './package-release.mjs';
import {admitInstalledNativeArtifact, requireNativePackageVersion} from './native-cli-artifact-reader.mjs';
import {admitInstalledBinary} from '../packages/native-cli/bin/actql.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
export function nativeStandaloneAcceptanceScope() {
  return {acceptedScope: 'only completed direct Native --version/help/refusal and original Remote Host fixture; Node-free Native child PATH; separate public Node Host installation',
    unverified: ['Local execution/bootstrap/approval', 'standard Project/README CLI', 'other platforms', 'npm Native launcher installation', 'full fault matrix', 'owner approval/publication authority']};
}

export function nativeReleaseInstallSelection(args) {
  assert(Array.isArray(args) && args.length === 5,
    'usage: test-native-standalone-install.mjs <fixed-directory> <externally-retained-SHA256> <native-target-id> <host-node-target-id> <new-external-consumer-directory>');
  assert.match(args[1], /^[a-f0-9]{64}$/u); assert(args[2] && args[3] && args[2] !== args[3]);
  return {directory: resolve(args[0]), manifestSha256: args[1], targetId: args[2], hostTargetId: args[3],
    consumer: resolve(args[4]), kind: 'public-native-standalone'};
}

export function nativeStandaloneEnvironment(parent, root) {
  assert(isAbsolute(root));
  const env = {PATH: '', HOME: join(root, 'home'), TMPDIR: join(root, 'tmp')};
  for (const key of ['LANG', 'LC_ALL', 'LC_CTYPE', 'TZ'])
    if (typeof parent[key] === 'string') env[key] = parent[key];
  // Remote configuration/TLS is passed by the original explicit argv. There
  // are no inherited ActQL profiles, Node/loader injections or credentials.
  return env;
}

export async function verifyNativeStandaloneInstallation(directory, item, artifact, source, version, platformFacts) {
  const stat = await lstat(directory); assert(stat.isDirectory() && !stat.isSymbolicLink());
  assert.equal(item.platform, artifact.platform);
  assert.deepEqual(await inventory(directory), item.files, 'Installed standalone payload differs from the original complete byte/mode inventory');
  assert.deepEqual(await admitInstalledNativeArtifact(directory, source), artifact);
  requireNativePackageVersion(artifact, version);
  const executable = join(directory, 'bin/actql-native-client'), file = await lstat(executable);
  assert(file.isFile() && !file.isSymbolicLink() && (file.mode & 0o111), 'Original standalone binary must remain executable');
  // Reuse the launcher's original platform/ABI admission, but execute Native
  // directly. No Node launcher becomes an archive runtime dependency.
  const bytes = await readFile(executable);
  admitInstalledBinary({key: artifact.platform, expected: artifact, metadata: artifact, binary: bytes, ...platformFacts});
  return {executable, binarySha256: sha(bytes), binaryBytes: bytes.length, payloadFiles: item.files.length};
}

export async function extractNativeStandaloneDownload(archive, destination, item, artifact, source, version, platformFacts) {
  const stat = await lstat(archive); assert(stat.isFile() && !stat.isSymbolicLink());
  const original = await readFile(archive); assert.equal(original.length, item.bytes); assert.equal(sha(original), item.sha256);
  try {await lstat(destination); assert.fail('Standalone extraction destination already exists');}
  catch (failure) {if (failure.code !== 'ENOENT') throw failure;}
  const directory = await unpack(archive, destination, {rootName: item.archiveRoot});
  const admitted = await verifyNativeStandaloneInstallation(directory, item, artifact, source, version, platformFacts);
  assert.deepEqual(await readFile(archive), original, 'Original public archive changed during extraction');
  return {directory, ...admitted};
}
