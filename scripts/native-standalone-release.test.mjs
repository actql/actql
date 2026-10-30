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
import {downloadNativeReleaseTarget} from './release-registry.mjs';
import {extractNativeStandaloneDownload, verifyNativeStandaloneInstallation} from './release-native-install.mjs';
import {inertNativeStandaloneFixture as fixture} from './fixtures/release-native-standalone.mjs';

const source = 'a'.repeat(40), version = '0.0.7-rc.1';
const qualification = 'standalone packaging/source-byte correspondence only; runtime/Node-free/profile/version-display/public acceptance and owner approval remain external';
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => createHash(algorithm).update(bytes).digest(encoding);
const json = value => Buffer.from(JSON.stringify(value));

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

test('standalone release requires the original matching compiled-version observation without rewriting a legacy artifact', async t => {
  const f = await fixture(t), original = await readFile(f.archive);
  const legacy = {...f.record}; delete legacy.packageVersion; delete legacy.packageVersionObservation;
  await assert.rejects(stageNativeStandaloneArchive({...f.options, artifact: legacy}), /explicitly versioned/u);
  await assert.rejects(stageNativeStandaloneArchive({...f.options, version: '0.0.7'}), /explicitly versioned/u);
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

async function publicNativeFixture(t) {
  const f = await fixture(t), directory = join(f.root, 'fixed');
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'inert-native-public-consumer', version,
    source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'},
    targets: [{id: 'native', ecosystem: 'native', packages: ['actql-darwin-arm64', 'actql-checksums'],
      platforms: ['darwin-arm64'], profiles: ['remote'], destination: 'https://github.com/actql/actql', channels: ['version-only']}],
    notes: {summary: 'Inert downloaded payload, not a Native runtime', breakingChanges: [], migration: [], knownLimitations: ['Not executable or accepted']}};
  const policy = JSON.parse(await readFile(new URL('../release/policy.json', import.meta.url)));
  const fixed = await freezeReleaseSet({request, policy, cohorts: [{targetId: 'native', kind: 'native-standalone', directory: f.destination}], destination: directory});
  const api = 'https://api.github.com/repos/actql/actql', tag = `v${version}`;
  const assets = fixed.manifest.artifacts.map((item, index) => ({id: index + 81, name: item.file, state: 'uploaded',
    size: item.bytes, digest: `sha256:${item.sha256}`, browser_download_url: `https://github.com/actql/actql/releases/download/${tag}/${item.file}`}));
  const routes = new Map([
    [`${api}/releases/tags/${tag}`, () => Response.json({id: 71, tag_name: tag, draft: false, immutable: true, prerelease: true})],
    [`${api}/git/ref/tags/${tag}`, () => Response.json({ref: `refs/tags/${tag}`, object: {type: 'commit', sha: source}})],
    [`${api}/releases/71/assets?per_page=100&page=1`, () => Response.json(assets)],
  ]);
  for (const [index, item] of fixed.manifest.artifacts.entries()) {
    const bytes = await readFile(join(directory, item.path)); routes.set(`${api}/releases/assets/${assets[index].id}`, () => new Response(bytes));
  }
  const calls = [], fetchResponse = async (url, options) => {
    calls.push(url); assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit'); assert.equal(options.redirect, 'manual');
    assert.equal(options.headers.authorization, undefined); assert.equal(options.body, undefined); assert(routes.has(url), url);
    return routes.get(url)();
  };
  return {...f, directory, fixed, routes, calls, assets, api, fetchResponse,
    download: destination => downloadNativeReleaseTarget(directory, fixed.sha256, 'native', destination, {fetchResponse})};
}

test('Native public consumer: actual same-reader download feeds complete unchanged standalone extraction, never a local archive substitute', async t => {
  const f = await publicNativeFixture(t), destination = join(f.root, 'public-download');
  const {download, standalone} = await f.download(destination);
  assert.equal(download.status, 'verified'); assert.equal(download.files.length, 2);
  assert(download.files.every(value => value.status === 'verified' && value.retainedBytes === value.expectedBytes));
  assert.equal(f.calls.length, 8); // Exact release/tag/inventory before+after; each asset body once.
  assert.deepEqual(await readFile(join(destination, f.staged.file)), await readFile(join(f.destination, f.staged.file)));
  const result = await extractNativeStandaloneDownload(join(destination, f.staged.file), join(f.root, 'external-install'),
    standalone.archives[0], f.record, source, version, {macOS: '11.0'});
  assert.deepEqual(await readFile(result.executable), f.binary);
  assert.equal(result.binarySha256, hash(f.binary)); assert.equal(result.payloadFiles, f.staged.files.length);
  const record = JSON.parse(await readFile(join(destination, 'download.json'))); assert.equal(record.status, 'verified');
  assert.equal(record.manifestSha256, f.fixed.sha256);
  await assert.rejects(f.download(destination), /EEXIST/u); assert.equal(f.calls.length, 8);
  await assert.rejects(extractNativeStandaloneDownload(join(destination, f.staged.file), join(f.root, 'external-install'),
    f.staged, f.record, source, version, {macOS: '11.0'}), /already exists/u);
});

test('Native public consumer: corrupt oversized interrupted or missing download retains incomplete evidence without retry or success', async t => {
  const f = await publicNativeFixture(t), bytes = await readFile(join(f.destination, f.staged.file));
  const corrupted = Buffer.from(bytes); corrupted[0] ^= 1;
  const bodies = [() => new Response(corrupted), () => new Response(Buffer.concat([bytes, Buffer.from('extra')])),
    () => new Response('', {status: 404}), () => {
      let step = 0;
      return new Response(new ReadableStream({pull(controller) {
        if (step++ === 0) controller.enqueue(bytes.subarray(0, 10)); else controller.error(Error('Own interrupted stream'));
      }}));
    }];
  for (const [index, body] of bodies.entries()) {
    f.routes.set(`${f.api}/releases/assets/81`, body);
    const destination = join(f.root, `incomplete-${index}`), before = f.calls.length;
    await assert.rejects(f.download(destination));
    const record = JSON.parse(await readFile(join(destination, 'download.json')));
    assert.equal(record.status, 'incomplete'); assert.equal(record.files.length, 1);
    assert.equal(record.files[0].status, 'incomplete'); assert.equal(f.calls.length - before, 4);
    assert.equal(f.calls.slice(before).filter(value => value.includes('/releases/assets/81')).length, 1);
    assert.equal((await readFile(join(destination, f.staged.file))).length, record.files[0].retainedBytes);
  }
});

test('Native public consumer: missing public context and changed immutable identity cannot supply downloaded acceptance', async t => {
  const f = await publicNativeFixture(t), release = `${f.api}/releases/tags/v${version}`, original = f.routes.get(release);
  f.routes.set(release, () => new Response('', {status: 404}));
  const unavailable = join(f.root, 'unavailable'); await assert.rejects(f.download(unavailable));
  assert.deepEqual(JSON.parse(await readFile(join(unavailable, 'download.json'))).files, []);
  f.routes.set(release, original); let pages = 0;
  f.routes.set(`${f.api}/releases/71/assets?per_page=100&page=1`, () => Response.json(
    f.assets.map(item => ({...item, id: pages > 0 ? item.id + 100 : item.id})), {status: (pages++, 200)}));
  const changed = join(f.root, 'changed-identity'); await assert.rejects(f.download(changed), /identity changed/u);
  const record = JSON.parse(await readFile(join(changed, 'download.json')));
  assert.equal(record.status, 'incomplete'); assert(record.files.every(value => value.status === 'verified'));
});

test('Native public consumer: original installed payload and ABI checks refuse missing changed linked and nonexecutable binaries', async t => {
  const f = await publicNativeFixture(t), destination = join(f.root, 'download'); await f.download(destination);
  const item = f.staged, facts = {macOS: '11.0'};
  const installed = await extractNativeStandaloneDownload(join(destination, item.file), join(f.root, 'installed'), item, f.record, source, version, facts);
  const check = () => verifyNativeStandaloneInstallation(installed.directory, item, f.record, source, version, facts);
  await writeFile(installed.executable, Buffer.alloc(f.binary.length)); await assert.rejects(check());
  await writeFile(installed.executable, f.binary); await chmod(installed.executable, 0o644); await assert.rejects(check());
  await chmod(installed.executable, 0o755); await rm(installed.executable); await assert.rejects(check());
  await symlink('/unselected-must-not-be-followed', installed.executable); await assert.rejects(check(), /symlink/u);
  await rm(installed.executable); await writeFile(installed.executable, f.binary, {mode: 0o755});
  await assert.rejects(verifyNativeStandaloneInstallation(installed.directory, item, f.record, source, version, {macOS: '10.0'}), /Unsupported macOS/u);
  await writeFile(join(installed.directory, 'unexpected-loader'), 'Not part of original payload'); await assert.rejects(check());
});

test('Native public consumer: chunked signed CDN download retains exact bytes while irrelevant asset order and signed query stay outside identity', async t => {
  const f = await publicNativeFixture(t), archive = await readFile(join(f.destination, f.staged.file));
  const signed = 'https://release-assets.githubusercontent.com/native-81?signature=synthetic-not-retained';
  f.routes.set(`${f.api}/releases/assets/81`, () => new Response('', {status: 302, headers: {location: signed}}));
  f.routes.set(signed, () => {
    let offset = 0;
    return new Response(new ReadableStream({pull(controller) {
      if (offset === archive.length) {controller.close(); return;}
      const end = Math.min(offset + 17, archive.length); controller.enqueue(archive.subarray(offset, end)); offset = end;
    }}));
  });
  let pages = 0;
  f.routes.set(`${f.api}/releases/71/assets?per_page=100&page=1`, () => Response.json(pages++ === 0 ? f.assets : [...f.assets].reverse()));
  const directory = join(f.root, 'cdn-download'), {download} = await f.download(directory);
  assert.equal(download.status, 'verified'); assert.equal(f.calls.length, 9);
  assert.equal(download.files[0].retainedBytes, archive.length);
  assert.deepEqual(await readFile(join(directory, f.staged.file)), archive);
  const receipt = await readFile(join(directory, 'download.json'), 'utf8'); assert(!receipt.includes('synthetic-not-retained'));
  assert(download.requests.some(value => value.url === 'https://release-assets.githubusercontent.com/native-81'));
});
