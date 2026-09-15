// Build-time evidence: resolved source graph and emitted imports, not merely
// tree-shaken text. This does not sandbox malicious same-process plugins.
import {builtinModules} from 'node:module';
import {parse} from 'acorn';
import {walk} from './moon-runtime.mjs';

const builtins = new Set(builtinModules.flatMap(name => [name, name.replace(/^node:/, '')]));
function forbidden(path) {
  return path.startsWith('node:') || builtins.has(path) ||
    /(?:^|\/)(?:host-node|duckdb-node|connectors-builtin)(?:\/|$)/.test(path) ||
    /(?:^|\/)node_modules(?:\/|$)/.test(path) || /\.(?:node|dll|dylib|so)$/.test(path);
}

export function checkWorkersArtifact(metafile, source, allowedModules) {
  const allow = new Set(allowedModules);
  for (const [path, module] of Object.entries(metafile.inputs)) {
    if (forbidden(path) || !allow.has(path)) throw new Error(`WorkersModuleRejected: ${path}`);
    for (const dependency of module.imports) {
      if (dependency.external || forbidden(dependency.path) || !allow.has(dependency.path)) {
        throw new Error(`WorkersDependencyRejected: ${path} -> ${dependency.path}`);
      }
      if (dependency.kind === 'dynamic-import' || dependency.kind === 'require-call') {
        throw new Error(`WorkersDynamicDependency: ${path}`);
      }
    }
  }
  for (const output of Object.values(metafile.outputs)) {
    if (output.imports.length) throw new Error('WorkersUnresolvedOutputImport');
  }
  walk(parse(source, {ecmaVersion:'latest', sourceType:'module'}), node => {
    if (node.type === 'ImportDeclaration' || node.type === 'ImportExpression' ||
        node.type === 'ExportAllDeclaration' ||
        node.type === 'ExportNamedDeclaration' && node.source) {
      throw new Error('WorkersArtifactImport');
    }
  });
}

// Each source is explicitly reviewed: generated fixture/bridge contain the same
// product Core; generated composition selects only Local; Local's JS contribution
// is pure despite its historical directory name. No namespace-wide permission.
export const conformanceModules = [
  '_build/workers/modules/bridge.mjs',
  '_build/workers/modules/fixture.mjs',
  'adapters/connectors-workers/strategy.generated.mjs',
  'adapters/local-node/strategy-bundle.mjs',
  'adapters/host-common/strategy.mjs',
  'adapters/host-common/runtime-core.mjs',
  'adapters/host-common/runtime-result.mjs',
  'adapters/workers/host.mjs',
  'adapters/workers/conformance.mjs',
];
