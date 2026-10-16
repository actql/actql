// Original Native CLI staging inputs, shared with interface correspondence.
import {existsSync} from 'node:fs';
import {join} from 'node:path';
export const nativeCliLauncherInputs = Object.freeze([
  'README.md', 'bin/actql.mjs', 'lib/local-runtime.mjs', 'lib/product-members.mjs',
]);
export const nativeCliPlatforms = Object.freeze({'darwin-arm64': {os: 'darwin', cpu: 'arm64'},
  'linux-x64-gnu': {os: 'linux', cpu: 'x64', libc: 'glibc'}});

// The producer owns these source-to-stage copies. Discovery consumes this
// exact projection rather than treating the entry import graph as all files.
export function nativeCliPackageInputs(root) {
  const manifest = 'packages/native-cli/package.json';
  if (!existsSync(join(root, manifest))) return undefined;
  return {manifest, copies: nativeCliLauncherInputs.map(member => ({
    member, source: `packages/native-cli/${member}`}))};
}
