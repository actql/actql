// Shared ORIGINAL inert Native archive fixture. No executable/build/runtime acceptance.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, mkdir, mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inventory} from '../package-release.mjs';
import {stageNativeStandaloneArchive} from '../native-standalone-release.mjs';

const source = 'a'.repeat(40), version = '0.0.7-rc.1';
const qualification = 'standalone packaging/source-byte correspondence only; runtime/Node-free/profile/version-display/public acceptance and owner approval remain external';
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => createHash(algorithm).update(bytes).digest(encoding);
const json = value => Buffer.from(JSON.stringify(value));

async function fixture(t, local = false, platform = 'darwin-arm64', selectedVersion = version) {
  const version = selectedVersion;
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
  // Declared metadata oracle only, not an observed compiler/CLI receipt. The
  // separate Native mechanism case exercises actual compiled version bytes.
  record.packageVersion = version;
  record.packageVersionObservation = {argv: ['--version'], stdout: `${version}\n`, code: 0, signal: null,
    binarySha256: record.binarySha256, binaryBytes: record.binaryBytes, buildInputSha256: 'e'.repeat(64)};
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

export {fixture as inertNativeStandaloneFixture};
