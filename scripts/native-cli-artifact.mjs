// Run under the existing heavy guard in a clean, platform-native checkout.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const run = (command, args) => execFileSync(command, args, {cwd: repository,
  encoding: 'utf8', timeout: 300_000, maxBuffer: 8 * 1024 * 1024});

export function inspectNativeAbi(binary, platform, execute = execFileSync) {
  const inspect = (tool, args) => execute(tool, args, {encoding: 'utf8', maxBuffer: 8 * 1024 * 1024});
  if (platform === 'darwin-arm64') return {format: 'Mach-O',
    sharedLibraries: inspect('otool', ['-L', binary]).split('\n').slice(1).filter(Boolean).map(v => v.trim()),
    loadCommands: inspect('otool', ['-l', binary]),
    httpLibrary: '/usr/lib/libcurl.4.dylib', httpLibraryBundled: false};
  const versionInfo = inspect('readelf', ['--version-info', binary]);
  const versions = [...versionInfo.matchAll(/\bGLIBC_(\d+)\.(\d+)\b/gu)]
    .map(v => [Number(v[1]), Number(v[2])]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  assert(versions.length, 'No observed executable glibc symbol requirements');
  const dynamic = inspect('readelf', ['-d', binary]);
  return {format: 'ELF', minimumGlibc: versions.at(-1).join('.'),
    sharedLibraries: [...dynamic.matchAll(/\(NEEDED\).*?\[([^\]]+)\]/gu)].map(v => v[1]),
    versionInfo, dynamic, httpLibrary: 'libcurl.so.4', httpLibraryBundled: false,
    httpLibraryRequirements: 'Separately supplied libcurl and its transitive dependencies may require a newer glibc than the executable.'};
}

export async function buildNativeCliArtifact(destination) {
  const source = checkoutState(repository); assert(source.clean, 'Native artifact requires clean source HEAD');
  const pins = JSON.parse(await readFile(join(repository, 'toolchain.json'), 'utf8'));
  const moon = run('moon', ['version']).trim(), moonc = run('moonc', ['-v']).trim();
  assert(moon.includes(pins.moon)); assert(moonc.includes(pins.moonc));
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  run('moon', ['build', '--target', 'native', '--release', 'src/cmd/native_client']);
  assert.deepEqual(checkoutState(repository), source);
  const built = join(repository, '_build/native/release/build/cmd/native_client/native_client.exe');
  const c = join(repository, '_build/native/release/build/cmd/native_client/native_client.c');
  destination = resolve(destination); await mkdir(destination);
  const binary = join(destination, 'actql-native-client');
  await copyFile(built, binary); await chmod(binary, 0o755);
  const bytes = await readFile(binary);
  const record = {version: 'actql-native-cli-artifact/0.1', sourceSha: source.revision,
    platform, binarySha256: hash(bytes), binaryBytes: bytes.length,
    generatedCSha256: hash(await readFile(c)), toolchainPinSha256: hash(await readFile(join(repository, 'toolchain.json'))),
    toolchain: {moon, moonc, node: process.version, cc: run('cc', ['--version']).split('\n')[0]},
    abi: inspectNativeAbi(binary, platform), testedHost: {platform: process.platform, arch: process.arch, glibc: glibc ?? null},
    generation: ['moon', 'build', '--target', 'native', '--release', 'src/cmd/native_client']};
  await writeFile(join(destination, 'artifact.json'), `${JSON.stringify(record, null, 2)}\n`, {flag: 'wx'});
  return record;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'usage: native-cli-artifact.mjs <new-artifact-directory>');
  const record = await buildNativeCliArtifact(process.argv[2]);
  console.log(JSON.stringify({sourceSha: record.sourceSha, platform: record.platform,
    binarySha256: record.binarySha256, abi: record.abi.sharedLibraries}, null, 2));
}
