import { accessSync, constants, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Paths verified against the pinned archive and its three core bundle outputs.
export const installationFiles = [
  'bin/moon', 'bin/moonc', 'bin/moonrun', 'bin/internal/tcc',
  'lib/core/moon.mod',
  ...['js', 'wasm', 'native'].flatMap(target =>
    ['mi', 'core'].map(ext => `lib/core/_build/${target}/release/bundle/prelude/prelude.${ext}`)),
];

export function verifyInstallation(install, marker) {
  try {
    if (readFileSync(join(install, 'installed.json'), 'utf8') !== marker) {
      throw new Error('installation marker differs from current pins');
    }
    for (const relative of installationFiles) {
      const path = join(install, relative);
      const stat = statSync(path);
      if (!stat.isFile() || stat.size === 0) throw new Error(`Missing or empty file: ${relative}`);
      accessSync(path, relative.startsWith('bin/') ? constants.X_OK : constants.R_OK);
    }
  } catch (error) {
    throw new Error(`Incomplete or mismatched MoonBit installation at ${install}. Move only this directory aside and rerun node scripts/setup-moonbit.mjs. ${error.message}`);
  }
}
