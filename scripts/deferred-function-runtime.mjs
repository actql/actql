import {buildSync, transformSync} from 'esbuild';

// These generated ABI modules export synchronous functions only. Keep their
// original compiled body and process-wide state together, but initialize it
// on the first Owner call rather than during a Worker's global module load.
// In particular, the pinned runtime's random hash seed still uses its actual
// entropy source; it is not replaced with a constant or a Host-side hash.
export function deferredFunctionRuntime(source, {minify = false} = {}) {
  const built = buildSync({entryPoints: [source], bundle: true, minify,
    write: false, metafile: true, format: 'esm', platform: 'neutral',
    target: 'es2022'});
  const outputs = Object.values(built.metafile.outputs);
  if (outputs.length !== 1 || built.outputFiles.length !== 1 ||
      outputs[0].imports.length !== 0 || outputs[0].exports.length === 0 ||
      outputs[0].exports.some(name => !/^[A-Za-z_$][A-Za-z0-9_$]*$/u.test(name) ||
        name === 'default')) {
    throw new TypeError('Expected a closed synchronous function ABI');
  }
  const body = transformSync(built.outputFiles[0].text, {format: 'iife',
    globalName: '__actqlCompiledRuntime', minify, target: 'es2022'}).code;
  const exports = [...outputs[0].exports].sort();
  const wrappers = exports.map(name => `export function ${name}(...args) {
  return runtime().${name}(...args);
}`).join('\n');
  // Cache initialization failure too. A later call must not silently retry an
  // initializer whose outcome was lost, nor construct a second Owner instance.
  return Buffer.from(`// Generated from the original compiled function ABI.
let compiled, attempted = false, failed = false, failure;
function runtime() {
  if (failed) throw failure;
  if (!attempted) {
    attempted = true;
    try {
      compiled = initialize();
      if (${JSON.stringify(exports)}.some(name => typeof compiled[name] !== 'function')) {
        throw new TypeError('Expected a synchronous function ABI');
      }
    } catch (error) {
      failed = true;
      failure = error;
      throw error;
    }
  }
  return compiled;
}
function initialize() {
${body}
  return __actqlCompiledRuntime;
}
${wrappers}
`);
}
