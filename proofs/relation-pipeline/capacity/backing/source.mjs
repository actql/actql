import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
const profile = JSON.parse(readFileSync(new URL('./core-profile.json', import.meta.url)));
export const nativeProfile = JSON.parse(readFileSync(new URL('./native-profile.json', import.meta.url)));
export function checkNativeRuntime(home, toolchain, read = readFileSync) {
  assert.equal(toolchain.moonc, nativeProfile.compiler);
  assert.deepEqual(toolchain.archives, nativeProfile.archives, 'Unreviewed native runtime archive');
  const platform = process.platform + '-' + process.arch;
  assert(['darwin-arm64', 'linux-x64'].includes(platform), 'Unreviewed native ABI target');
  const sources = { ...nativeProfile.sources, ...nativeProfile.platformBinaries[platform] };
  for (const [path, digest] of Object.entries(sources)) {
    assert.equal(createHash('sha256').update(read(join(home, path))).digest('hex'), digest,
      'Installed native runtime differs from verified archive: ' + path);
  }
  return { platform, sources, archive: toolchain.archives[platform],
    profileDigest: createHash('sha256').update(JSON.stringify(nativeProfile)).digest('hex') };
}
export function checkCore(core, toolchain, read = readFileSync) {
  assert.equal(toolchain.moonc, profile.compiler);
  assert.deepEqual(toolchain.core, profile.coreArchive, 'Unreviewed core archive');
  for (const [path, digest] of Object.entries(profile.sources)) {
    const bytes = read(join(core, path));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), digest,
      'Installed core differs from verified archive: ' + path);
  }
  return profile;
}
