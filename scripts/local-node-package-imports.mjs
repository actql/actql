// Adapter nesting varies. Every checkout-only package import must resolve to
// its existing public export before the adapter is copied into a tarball.
const exports = new Map([
  ['client-wire/index.mjs', '@actql/client-wire'],
  ['sdk/index.mjs', '@actql/sdk'],
  ['sdk/host-port.mjs', '@actql/sdk/host-port'],
  ['run-host-core/index.mjs', '@actql/run-host-core'],
]);
export function rewriteLocalNodePackageImports(code, path) {
  return code.replace(/(['"])(?:\.\.\/)+packages\/([^'"]+)\1/gu,
    (_literal, quote, module) => {
      const target = exports.get(module);
      if (target === undefined) throw new Error(`UnpackagedLocalNodeImport:${path}:${module}`);
      return quote + target + quote;
    });
}
