import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
const profile = JSON.parse(readFileSync(new URL('./core-profile.json', import.meta.url)));
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
