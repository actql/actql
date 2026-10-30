// Inert Mach-O/ELF and Local metadata fixtures only. No executable is run or
// compiled; full Native npm producer/installed acceptance remains separate.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, mkdir, mkdtemp, readFile, writeFile, rm, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import test from 'node:test';
import {inventory, unpack} from './package-release.mjs';
import {stageNativeStandaloneArchive, verifyNativeStandalone} from './native-standalone-release.mjs';
import {admitInstalledNativeArtifact} from './native-cli-artifact-reader.mjs';
import {freezeReleaseSet, verifyReleaseSet} from './release-set.mjs';

const source = 'a'.repeat(40), version = '0.0.7-rc.1';
const qualification = 'standalone packaging/source-byte correspondence only; runtime/Node-free/profile/version-display/public acceptance and owner approval remain external';
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => createHash(algorithm).update(bytes).digest(encoding);
const json = value => Buffer.from(JSON.stringify(value));

async function fixture(t, local = false, platform = 'darwin-arm64') {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-archive-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const input = join(root, 'input'), payload = join(input, 'package'), destination = join(root, 'standalone');
  await mkdir(join(payload, 'bin'), {recursive: true}); await mkdir(destination);
  const binary = Buffer.alloc(64); binary.writeUInt32LE(0xfeedfacf, 0); binary.writeUInt32LE(0x0100000c, 4);
  if (platform === 'linux-x64-gnu') {
    binary.writeUInt32BE(0x7f454c46, 0); binary[4] = 2; binary[5] = 1; binary.writeUInt16LE(62, 18);
  }
  await writeFile(join(payload, 'bin/actql-native-client'), binary); await chmod(join(payload, 'bin/actql-native-client'), 0o755);
  const record = {version: 'actql-native-cli-artifact/0.1', sourceSha: source, platform,
    binarySha256: hash(binary), binaryBytes: binary.length, generatedCSha256: 'b'.repeat(64), toolchainPinSha256: 'c'.repeat(64),
    notices: {}, toolchain: {fixture: 'Not a compiler receipt'}, abi: {format: 'Mach-O', minimumMacOS: '11.0'},
    testedHost: {}, generation: ['inert fixture; never executed']};
  if (platform === 'linux-x64-gnu') record.abi = {format: 'ELF', minimumGlibc: '2.17'};
  for (const name of ['LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE']) {
    const bytes = Buffer.from('Independent inert fixture notice ' + name); await writeFile(join(payload, name), bytes);
    if (name !== 'LICENSE') record.notices[name] = hash(bytes);
  }
  if (local) {
    for (const name of ['lib', 'data', 'licenses']) await mkdir(join(payload, name));
    const license = Buffer.from('Inert fixture library license'); await writeFile(join(payload, 'licenses/NATIVE-LICENSE'), license);
    const libraries = [];
    for (const role of ['sqlite', 'crypto']) {
      const bytes = Buffer.alloc(32); bytes.writeUInt32LE(0xfeedfacf, 0); bytes.writeUInt32LE(0x0100000c, 4); bytes.writeUInt32LE(6, 12);
      const path = `lib/lib${role}.dylib`; await writeFile(join(payload, path), bytes);
      libraries.push({role, path, bytes: bytes.length, sha256: hash(bytes), license: 'licenses/NATIVE-LICENSE',
        dependencies: ['/usr/lib/libSystem.B.dylib'], abi: {minimumMacOS: '11.0'}});
    }
    const assets = [];
    for (const role of ['environment', 'registry', 'values', 'fragment', 'result-policy']) {
      const bytes = Buffer.from('{}'); const path = `data/${role}.json`; await writeFile(join(payload, path), bytes);
      assets.push({role, path, bytes: bytes.length, sha256: hash(bytes)});
    }
    const body = json({sourceSha: source, platform: record.platform, libraries, assets,
      licenses: [{path: 'licenses/NATIVE-LICENSE', bytes: license.length, sha256: hash(license)}]});
    await writeFile(join(payload, 'local-runtime.json'), body);
    record.localRuntime = {path: 'local-runtime.json', bytes: body.length, sha256: hash(body)};
  }
  await writeFile(join(payload, 'artifact.json'), json(record));
  await writeFile(join(payload, 'package.json'), json({name: `@actql/cli-${platform}`, version,
    license: 'Apache-2.0', os: [platform === 'linux-x64-gnu' ? 'linux' : 'darwin'],
    cpu: [platform === 'linux-x64-gnu' ? 'x64' : 'arm64'], ...(platform === 'linux-x64-gnu' ? {libc: ['glibc']} : {})}));
  const archive = join(root, 'original-os.tgz');
  execFileSync('tar', ['-czf', archive, '-C', input, 'package']);
  const original = await readFile(archive);
  const item = {name: `@actql/cli-${platform}`, version, file: 'original-os.tgz', bytes: original.length,
    sha256: hash(original), integrity: `sha512-${hash(original, 'sha512', 'base64')}`, files: await inventory(payload)};
  const npm = {version: 'actql-native-cli-release/0.1', sourceSha: source, preparedAt: '2000-01-01T00:00:00Z',
    recipeSha256: 'd'.repeat(64), cohort: {packageVersion: version, registry: 'https://registry.npmjs.org/', access: 'public', tag: 'candidate-fixture'},
    platforms: {[platform]: {}}, artifacts: [record], packages: [item, {name: 'actql'}]};
  const originalManifest = json(npm), profiles = local ? ['remote', 'local'] : ['remote'];
  const options = {archive, destination, source, version, item, artifact: record, profiles, cohortSha256: hash(originalManifest)};
  const staged = await stageNativeStandaloneArchive(options);
  const sums = Buffer.from(`${staged.sha256}  ${staged.file}\n`); await writeFile(join(destination, 'SHA256SUMS'), sums);
  const manifest = {schemaVersion: 'actql-native-standalone/0.1', sourceSha: source, packageVersion: version,
    platforms: [record.platform], requestedProfiles: profiles,
    origin: {bytes: originalManifest.length, sha256: hash(originalManifest), manifest: originalManifest.toString()}, archives: [staged],
    checksums: {name: 'actql-checksums', version, file: 'SHA256SUMS', bytes: sums.length, sha256: hash(sums)}, qualification};
  const manifestPath = join(destination, 'native-standalone.json'); await writeFile(manifestPath, json(manifest));
  return {root, payload, destination, manifestPath, manifest, staged, binary, options, archive, item, record};
}

test('standalone archive retains every original OS payload byte and mode with noncircular build/checksum metadata', async t => {
  const f = await fixture(t); const original = await readFile(f.archive);
  assert.deepEqual(await verifyNativeStandalone(f.destination), f.manifest);
  const unpacked = await unpack(join(f.destination, f.staged.file), join(f.root, 'consumer'), {rootName: f.staged.archiveRoot});
  assert.deepEqual(await readFile(join(unpacked, 'bin/actql-native-client')), f.binary);
  assert.equal((await inventory(unpacked)).find(value => value.path === 'bin/actql-native-client').mode, 0o755);
  assert.deepEqual((await inventory(unpacked)).filter(value => !['build-info.json', 'STANDALONE.md', 'CONTENTS.sha256'].includes(value.path)), f.item.files);
  const info = JSON.parse(await readFile(join(unpacked, 'build-info.json')));
  assert.equal(info.packageVersion, version); assert.equal(Object.hasOwn(info, 'archiveSha256'), false);
  assert.equal(JSON.parse(await readFile(join(unpacked, 'package.json'))).scripts, undefined);
  assert.deepEqual(await readFile(f.archive), original);
});

test('standalone Local payload uses the existing full metadata reader without claiming operation or Linux support', async t => {
  const f = await fixture(t, true);
  assert.deepEqual(await verifyNativeStandalone(f.destination), f.manifest);
  assert.deepEqual(f.manifest.requestedProfiles, ['remote', 'local']);
  await assert.rejects(stageNativeStandaloneArchive({...f.options, profiles: ['local'], artifact: {...f.record, platform: 'linux-x64-gnu'}}), /Linux Local/u);
  await assert.rejects(stageNativeStandaloneArchive({...f.options, profiles: ['local'], artifact: {...f.record, localRuntime: undefined}}), /original admitted Local/u);
});

test('standalone original tarball or missing binary cannot be rebuilt or replaced under its old identity', async t => {
  const f = await fixture(t); await writeFile(f.archive, 'Changed original archive');
  await assert.rejects(stageNativeStandaloneArchive(f.options));
  await rm(join(f.payload, 'bin/actql-native-client'));
  execFileSync('tar', ['-czf', f.archive, '-C', join(f.root, 'input'), 'package']);
  const bytes = await readFile(f.archive), item = {...f.item, bytes: bytes.length, sha256: hash(bytes),
    integrity: `sha512-${hash(bytes, 'sha512', 'base64')}`, files: await inventory(f.payload)};
  await assert.rejects(stageNativeStandaloneArchive({...f.options, item}), /ENOENT/u);
});

test('standalone archive tamper missing bytes and changed checksum inventory remain failures', async t => {
  const f = await fixture(t), path = join(f.destination, f.staged.file), original = await readFile(path);
  await writeFile(path, 'Changed final archive'); await assert.rejects(verifyNativeStandalone(f.destination));
  await writeFile(path, original); await writeFile(join(f.destination, 'SHA256SUMS'), 'Wrong checksum list');
  await assert.rejects(verifyNativeStandalone(f.destination));
  await rm(path); await assert.rejects(verifyNativeStandalone(f.destination), /ENOENT/u);
});

test('shared unpack admits only the selected root and rejects links and duplicate entries', async t => {
  const f = await fixture(t);
  await assert.rejects(unpack(join(f.destination, f.staged.file), join(f.root, 'wrong-root')), /Unsafe archive/u);
  const malicious = join(f.root, 'malicious'); await mkdir(join(malicious, 'package'), {recursive: true});
  await symlink('/unselected-must-not-be-followed', join(malicious, 'package/link'));
  const linkTar = join(f.root, 'links.tgz'); execFileSync('tar', ['-czf', linkTar, '-C', malicious, 'package']);
  await assert.rejects(unpack(linkTar, join(f.root, 'link-output')), /links and special/u);
  await rm(join(malicious, 'package/link')); await writeFile(join(malicious, 'package/member'), 'duplicate fixture');
  const tar = join(f.root, 'duplicate.tar'), gz = join(f.root, 'duplicate.tgz');
  execFileSync('tar', ['-cf', tar, '-C', malicious, 'package']);
  execFileSync('tar', ['-rf', tar, '-C', malicious, 'package/member']);
  await writeFile(gz, execFileSync('gzip', ['-c', tar]));
  await assert.rejects(unpack(gz, join(f.root, 'duplicates')), /Duplicate archive/u);
});

test('standalone archives and final SHA256SUMS connect to the exact upper release set', async t => {
  const f = await fixture(t), destination = join(f.root, 'fixed');
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'inert-native-fixture', version,
    source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'},
    targets: [{id: 'native', ecosystem: 'native', packages: ['actql-darwin-arm64', 'actql-checksums'],
      platforms: ['darwin-arm64'], profiles: ['remote'], destination: 'https://github.com/actql/actql', channels: ['version-only']}],
    notes: {summary: 'Inert archive metadata only', breakingChanges: [], migration: [], knownLimitations: ['Not executable or accepted']}};
  const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url)));
  const result = await freezeReleaseSet({request, policy, cohorts: [{targetId: 'native', kind: 'native-standalone', directory: f.destination}], destination});
  assert.deepEqual(result.manifest.artifacts.map(value => value.name), ['actql-darwin-arm64', 'actql-checksums']);
  assert.equal(result.manifest.acceptance, 'unaccepted'); assert(result.manifest.artifacts.every(value => !Object.hasOwn(value, 'integrity')));
  assert.deepEqual(await verifyReleaseSet(destination, {expectedSha256: result.sha256}), result);
  const changed = structuredClone(request); changed.targets[0].profiles = ['local'];
  await assert.rejects(freezeReleaseSet({request: changed, policy, cohorts: [{targetId: 'native', kind: 'native-standalone', directory: f.destination}], destination: join(f.root, 'wrong-profile')}));
});

test('standalone preparation never overwrites an existing final archive', async t => {
  const f = await fixture(t), path = join(f.destination, f.staged.file), before = await readFile(path);
  await assert.rejects(stageNativeStandaloneArchive(f.options), /EEXIST/u);
  assert.deepEqual(await readFile(path), before);
});

test('standalone CLI has no publish or credential subprocess route', async t => {
  const f = await fixture(t), marker = join(f.root, 'unexpected-publisher'), npm = join(f.root, 'npm');
  await writeFile(npm, '#!/bin/sh\nprintf called > "$ACTQL_RELEASE_TEST_MARKER"\nexit 77\n'); await chmod(npm, 0o755);
  const child = spawnSync(process.execPath, [resolve('scripts/native-standalone-release.mjs'), '--publish', f.destination],
    {env: {...process.env, PATH: f.root, ACTQL_RELEASE_TEST_MARKER: marker}, encoding: 'utf8', timeout: 20_000});
  assert.equal(child.error, undefined); assert.notEqual(child.status, 0);
  await assert.rejects(readFile(marker), {code: 'ENOENT'});
});

test('Native artifact reader refuses inherited object names as unsupported platforms', async t => {
  const f = await fixture(t), binary = Buffer.alloc(64);
  binary.writeUInt32BE(0x7f454c46, 0); binary[4] = 2; binary[5] = 1; binary.writeUInt16LE(62, 18);
  await writeFile(join(f.payload, 'bin/actql-native-client'), binary);
  await writeFile(join(f.payload, 'artifact.json'), json({...f.record, platform: 'constructor',
    binaryBytes: binary.length, binarySha256: hash(binary), abi: {format: 'ELF', minimumGlibc: '2.17'}}));
  await assert.rejects(admitInstalledNativeArtifact(f.payload, source), /Unknown Native artifact platform/u);
});

test('standalone Linux Remote archive keeps original ELF bytes and ABI facts without a Linux Local claim', async t => {
  const f = await fixture(t, false, 'linux-x64-gnu');
  const result = await verifyNativeStandalone(f.destination);
  assert.deepEqual(result.platforms, ['linux-x64-gnu']); assert.deepEqual(result.requestedProfiles, ['remote']);
  assert.equal(result.archives[0].file, 'actql-0.0.7-rc.1-linux-x64-gnu.tar.gz');
  const unpacked = await unpack(join(f.destination, f.staged.file), join(f.root, 'linux-consumer'), {rootName: f.staged.archiveRoot});
  assert.deepEqual(await readFile(join(unpacked, 'bin/actql-native-client')), f.binary);
  assert.deepEqual(JSON.parse(await readFile(join(unpacked, 'build-info.json'))).abi, {format: 'ELF', minimumGlibc: '2.17'});
  const metadata = JSON.parse(await readFile(join(unpacked, 'package.json')));
  assert.deepEqual(metadata.os, ['linux']); assert.deepEqual(metadata.cpu, ['x64']); assert.deepEqual(metadata.libc, ['glibc']);
});
