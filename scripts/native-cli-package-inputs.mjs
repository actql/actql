// Original Native CLI staging inputs, shared with interface correspondence.
export const nativeCliLauncherInputs = Object.freeze([
  'README.md', 'bin/actql.mjs', 'lib/local-runtime.mjs', 'lib/product-members.mjs',
]);
export const nativeCliPlatforms = Object.freeze({'darwin-arm64': {os: 'darwin', cpu: 'arm64'},
  'linux-x64-gnu': {os: 'linux', cpu: 'x64', libc: 'glibc'}});
