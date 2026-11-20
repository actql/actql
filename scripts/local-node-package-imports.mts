// Adapter nesting varies. Every checkout-only package import must resolve to
// its existing public export before the adapter is copied into a tarball.
// The fixed native filesystem assets instead retain their package-local
// paths; they are not public exports or interchangeable native modules.
const exports = new Map([
  ['client-wire/index.mjs', '@actql/client-wire'],
  ['sdk/index.mjs', '@actql/sdk'],
  ['sdk/host-port.mjs', '@actql/sdk/host-port'],
  ['sdk/internal/private-source-preparation.mjs', '@actql/sdk/_internal/source-preparation'],
  ['run-host-core/index.mjs', '@actql/run-host-core'],
]);
const nativeAssets = new Set([
  'local-node/_build/native/directory-darwin-arm64.node',
  'local-node/_build/native/directory-darwin-x64.node',
  'local-node/_build/native/local-files-linux-x64.node',
]);
export function rewriteLocalNodePackageImports(code, path) {
  return code.replace(/(['"])((?:\.\.\/)+)packages\/([^'"]+)\1/gu,
    (_literal, quote, prefix, module) => {
      if (nativeAssets.has(module)) {
        return quote + prefix + module.slice('local-node/'.length) + quote;
      }
      const target = exports.get(module);
      if (target === undefined) throw new Error(`UnpackagedLocalNodeImport:${path}:${module}`);
      return quote + target + quote;
    });
}
