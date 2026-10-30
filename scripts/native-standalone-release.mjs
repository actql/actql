// Repackage only an existing verified Native npm cohort. No compilation,
// binary patch, Node consumer, credentials, runtime acceptance or publication.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, lstat, mkdir, mkdtemp, open, readFile, rename, rm, writeFile} from 'node:fs/promises';
import {basename, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inventory, unpack} from './package-release.mjs';
import {verifyNativeCliRelease, admitNativeReleaseManifest} from './native-cli-release.mjs';
import {admitInstalledNativeArtifact} from './native-cli-artifact-reader.mjs';
import {admitReleaseRequest} from './release-policy.mjs';
import {releaseVersion} from './release-version.mjs';
import {nativeCliPlatforms} from './native-cli-package-inputs.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => createHash(algorithm).update(bytes).digest(encoding);
const wire = value => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
const exact = (value, keys) => {
  assert(value && typeof value === 'object' && !Array.isArray(value));
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort());
};
const qualification = 'standalone packaging/source-byte correspondence only; runtime/Node-free/profile/version-display/public acceptance and owner approval remain external';
const originFields = value => Object.fromEntries(['name', 'file', 'bytes', 'sha256', 'integrity'].map(key => [key, value[key]]));
const contentList = files => files.map(item => `${item.sha256}  ${item.path}\n`).join('');
async function regular(path) {
  const status = await lstat(path); assert(status.isFile() && !status.isSymbolicLink(), 'Standalone input must be a regular original file');
  return path;
}

function profilesFor(profiles, artifact) {
  assert(Array.isArray(profiles) && profiles.length && new Set(profiles).size === profiles.length);
  assert(profiles.every(value => ['remote', 'local'].includes(value)), 'Unknown Native requested profile');
  if (profiles.includes('local')) {
    assert(artifact.localRuntime, 'Local archive needs the original admitted Local runtime material');
    assert.equal(artifact.platform, 'darwin-arm64', 'Existing Local producer has no admitted Linux Local route');
  }
}

function buildInfo({source, version, platform, profiles, origin, artifact}) {
  return {schemaVersion: 'actql-native-build-info/0.1', sourceSha: source, packageVersion: version,
    platform, requestedProfiles: profiles, originalPackage: origin,
    binarySha256: artifact.binarySha256, generatedCSha256: artifact.generatedCSha256,
    toolchainPinSha256: artifact.toolchainPinSha256, abi: artifact.abi,
    qualification: 'immutable build/packaging facts; not runtime, command-version or profile acceptance'};
}

function instructions(version, platform, profiles) {
  return `# ActQL standalone Native ${version} (${platform})\n\n` +
    'The executable is bin/actql-native-client. Node/npm is not an archive runtime dependency.\n' +
    'package.json is retained unchanged as original OS-package provenance, not an install hook.\n\n' +
    `Requested profiles: ${profiles.join(', ')}. Requested is not accepted.\n` +
    'Remote use needs its configured Host/authentication/TLS. Local assets alone do not establish\n' +
    'the separate Node-free Native installation/bootstrap connection or Local acceptance.\n' +
    'See the exact release acceptance and platform prerequisites before operational use.\n\n' +
    'The build-info packageVersion identifies these distribution bytes. The compiled command\n' +
    'version is not rewritten by packaging and needs separate display acceptance.\n' +
    'No fallback executable, compiler, downloader, replacement parser or publisher is included.\n';
}

export async function stageNativeStandaloneArchive({archive, destination, source, version, item, artifact, profiles, cohortSha256}) {
  releaseVersion(version); assert.match(source, /^[a-f0-9]{40}$/u); assert.match(cohortSha256, /^[a-f0-9]{64}$/u);
  assert(Object.hasOwn(nativeCliPlatforms, artifact.platform), 'Unknown standalone Native platform'); profilesFor(profiles, artifact);
  assert.equal(item.name, `@actql/cli-${artifact.platform}`); assert.equal(item.version, version);
  const original = await readFile(await regular(archive));
  assert.equal(original.length, item.bytes); assert.equal(hash(original), item.sha256);
  assert.equal(`sha512-${hash(original, 'sha512', 'base64')}`, item.integrity);
  const scratch = await mkdtemp(join(destination, '.standalone-'));
  try {
    const unpacked = await unpack(archive, join(scratch, 'original'));
    assert.deepEqual(await inventory(unpacked), item.files, 'Original OS package payload changed');
    assert.deepEqual(await admitInstalledNativeArtifact(unpacked, source), artifact);
    for (const filename of ['build-info.json', 'STANDALONE.md', 'CONTENTS.sha256'])
      assert(!item.files.some(value => value.path === filename), 'Original payload occupies a reserved standalone metadata name');
    const origin = {...originFields(item), cohortSha256};
    await writeFile(join(unpacked, 'build-info.json'), wire(buildInfo({source, version, platform: artifact.platform, profiles, origin, artifact})), {flag: 'wx', mode: 0o644});
    await writeFile(join(unpacked, 'STANDALONE.md'), instructions(version, artifact.platform, profiles), {flag: 'wx', mode: 0o644});
    await writeFile(join(unpacked, 'CONTENTS.sha256'), contentList(await inventory(unpacked)), {flag: 'wx', mode: 0o644});
    for (const name of ['build-info.json', 'STANDALONE.md', 'CONTENTS.sha256']) await chmod(join(unpacked, name), 0o644);
    const archiveRoot = `actql-${version}-${artifact.platform}`;
    const file = `${archiveRoot}.tar.gz`;
    // Rename only the directory, preserving all original payload file bytes/modes.
    await rename(unpacked, join(scratch, archiveRoot));
    const output = await open(join(destination, file), 'wx', 0o644);
    try {
      execFileSync('tar', ['-czf', '-', '-C', scratch, archiveRoot],
        {stdio: ['ignore', output.fd, 'pipe'], timeout: 60_000, maxBuffer: 4 * 1024 * 1024});
    } finally {await output.close();}
    const bytes = await readFile(join(destination, file));
    return {name: `actql-${artifact.platform}`, version, file, bytes: bytes.length, sha256: hash(bytes),
      platform: artifact.platform, archiveRoot, origin: originFields(item), files: await inventory(join(scratch, archiveRoot))};
  } finally {await rm(scratch, {recursive: true});}
}

export async function prepareNativeStandalone({cohortDirectory, destination, request, policy, targetId}) {
  const selected = admitReleaseRequest(request, policy), target = request.targets.find(value => value.id === targetId);
  assert(target && target.ecosystem === 'native', 'Select the exact standalone Native target');
  const originPath = join(cohortDirectory, 'release.json'), original = await readFile(originPath);
  const npm = await verifyNativeCliRelease(cohortDirectory);
  assert.deepEqual(await readFile(originPath), original, 'Original Native cohort changed during verification');
  assert.equal(npm.sourceSha, request.source.commit); assert.equal(npm.cohort.packageVersion, selected.version.version);
  assert.deepEqual(target.packages, [...target.platforms.map(value => `actql-${value}`), 'actql-checksums']);
  const inputs = target.platforms.map(platform => {
    const artifact = npm.artifacts.find(value => value.platform === platform);
    const item = npm.packages.find(value => value.name === `@actql/cli-${platform}`);
    assert(artifact && item && Object.hasOwn(nativeCliPlatforms, platform), 'Selected Native platform has no original artifact');
    profilesFor(target.profiles, artifact); return {artifact, item};
  });
  destination = resolve(destination); await mkdir(destination);
  const archives = [];
  for (const input of inputs) archives.push(await stageNativeStandaloneArchive({
    archive: join(cohortDirectory, input.item.file), destination, source: request.source.commit,
    version: selected.version.version, ...input, profiles: target.profiles, cohortSha256: hash(original)}));
  const checksumFile = 'SHA256SUMS';
  const checksumBytes = Buffer.from(archives.map(value => `${value.sha256}  ${value.file}\n`).join(''));
  await writeFile(join(destination, checksumFile), checksumBytes, {flag: 'wx'});
  const manifest = {schemaVersion: 'actql-native-standalone/0.1', sourceSha: request.source.commit,
    packageVersion: selected.version.version, platforms: target.platforms, requestedProfiles: target.profiles,
    origin: {bytes: original.length, sha256: hash(original), manifest: original.toString('utf8')}, archives,
    checksums: {name: 'actql-checksums', version: selected.version.version, file: checksumFile,
      bytes: checksumBytes.length, sha256: hash(checksumBytes)}, qualification};
  assert.deepEqual(await readFile(originPath), original, 'Original Native cohort changed during standalone preparation');
  await writeFile(join(destination, 'native-standalone.json'), wire(manifest), {flag: 'wx'});
  return verifyNativeStandalone(destination);
}

export async function verifyNativeStandalone(directory) {
  const status = await lstat(directory); assert(status.isDirectory() && !status.isSymbolicLink());
  const manifest = JSON.parse(await readFile(await regular(join(directory, 'native-standalone.json')), 'utf8'));
  exact(manifest, ['schemaVersion', 'sourceSha', 'packageVersion', 'platforms', 'requestedProfiles', 'origin', 'archives', 'checksums', 'qualification']);
  assert.equal(manifest.schemaVersion, 'actql-native-standalone/0.1'); assert.equal(manifest.qualification, qualification);
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u); releaseVersion(manifest.packageVersion);
  exact(manifest.origin, ['bytes', 'sha256', 'manifest']);
  const original = Buffer.from(manifest.origin.manifest);
  assert.equal(original.length, manifest.origin.bytes); assert.equal(hash(original), manifest.origin.sha256);
  const npm = admitNativeReleaseManifest(JSON.parse(original));
  assert.equal(npm.sourceSha, manifest.sourceSha); assert.equal(npm.cohort.packageVersion, manifest.packageVersion);
  assert(Array.isArray(manifest.platforms) && manifest.platforms.length && manifest.platforms.length <= 2);
  assert.equal(new Set(manifest.platforms).size, manifest.platforms.length);
  assert.deepEqual(manifest.archives.map(value => value.platform), manifest.platforms);
  const scratch = await mkdtemp(join(directory, '.verify-standalone-'));
  try {
    for (const item of manifest.archives) {
      exact(item, ['name', 'version', 'file', 'bytes', 'sha256', 'platform', 'archiveRoot', 'origin', 'files']);
      const artifact = npm.artifacts.find(value => value.platform === item.platform);
      const source = npm.packages.find(value => value.name === `@actql/cli-${item.platform}`);
      assert(artifact && source && Object.hasOwn(nativeCliPlatforms, item.platform)); profilesFor(manifest.requestedProfiles, artifact);
      assert.equal(item.name, `actql-${item.platform}`); assert.equal(item.version, manifest.packageVersion);
      assert.equal(item.archiveRoot, `actql-${item.version}-${item.platform}`); assert.equal(item.file, `${item.archiveRoot}.tar.gz`);
      assert.equal(basename(item.file), item.file); assert.deepEqual(item.origin, originFields(source));
      const bytes = await readFile(await regular(join(directory, item.file))); assert.equal(bytes.length, item.bytes); assert.equal(hash(bytes), item.sha256);
      const payload = await unpack(join(directory, item.file), join(scratch, item.platform), {rootName: item.archiveRoot});
      assert.deepEqual(await inventory(payload), item.files);
      assert.deepEqual(item.files.filter(value => !['build-info.json', 'STANDALONE.md', 'CONTENTS.sha256'].includes(value.path)), source.files,
        'Standalone may not alter or omit any original OS payload byte/mode');
      assert.deepEqual(await admitInstalledNativeArtifact(payload, manifest.sourceSha), artifact);
      assert.deepEqual(await readFile(join(payload, 'build-info.json')), wire(buildInfo({source: manifest.sourceSha,
        version: item.version, platform: item.platform, profiles: manifest.requestedProfiles,
        origin: {...item.origin, cohortSha256: manifest.origin.sha256}, artifact})));
      assert.equal(await readFile(join(payload, 'STANDALONE.md'), 'utf8'), instructions(item.version, item.platform, manifest.requestedProfiles));
      assert.equal(await readFile(join(payload, 'CONTENTS.sha256'), 'utf8'), contentList(item.files.filter(value => value.path !== 'CONTENTS.sha256')));
      assert.deepEqual(await readFile(await regular(join(directory, item.file))), bytes, 'Original archive changed during verification');
    }
  } finally {await rm(scratch, {recursive: true});}
  exact(manifest.checksums, ['name', 'version', 'file', 'bytes', 'sha256']);
  assert.equal(manifest.checksums.name, 'actql-checksums'); assert.equal(manifest.checksums.version, manifest.packageVersion);
  assert.equal(manifest.checksums.file, 'SHA256SUMS');
  const sums = await readFile(await regular(join(directory, 'SHA256SUMS')));
  assert.equal(sums.length, manifest.checksums.bytes); assert.equal(hash(sums), manifest.checksums.sha256);
  assert.equal(sums.toString('utf8'), manifest.archives.map(value => `${value.sha256}  ${value.file}\n`).join(''));
  return manifest;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, ...args] = process.argv.slice(2);
  if (command === 'verify') {assert.equal(args.length, 1); console.log(JSON.stringify(await verifyNativeStandalone(resolve(args[0])), null, 2));}
  else {
    assert.equal(command, 'prepare'); assert.equal(args.length, 4,
      'usage: native-standalone-release.mjs prepare <request.json> <target-id> <native-npm-cohort> <new-directory> | verify <directory>');
    console.log(JSON.stringify(await prepareNativeStandalone({request: JSON.parse(await readFile(resolve(args[0]), 'utf8')),
      policy: JSON.parse(await readFile(join(root, 'release/policy.json'), 'utf8')), targetId: args[1],
      cohortDirectory: resolve(args[2]), destination: resolve(args[3])}), null, 2));
  }
}
