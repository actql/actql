// Build-time evidence: resolved source graph and emitted imports, not merely
// tree-shaken text. This does not sandbox malicious same-process plugins.
import {builtinModules} from 'node:module';
import {parse} from 'acorn';
import {walk} from './moon-runtime.mjs';

const builtins = new Set(builtinModules.flatMap(name => [name, name.replace(/^node:/, '')]));
function forbidden(path) {
  return path.startsWith('node:') || builtins.has(path) ||
    /(?:^|\/)(?:host-node|duckdb-node|connectors-builtin)(?:\/|$)/.test(path) ||
    /(?:^|\/)connectors\/duckdb\/node(?:\/|$)/.test(path) ||
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
// delegates reads without Node I/O despite its historical directory name. The
// Store registry and row framing use only WeakMap/typed arrays/TextDecoder;
// concrete files.mjs and delegated-file.mjs are NOT included in this allowance.
// The execution-authorization gate imported by the common strategy has no
// imports and uses only crypto.subtle, TextEncoder and timers; account
// interpretation stays in the bundled MoonBit runtime.
// The Effect receipt custody imported by run publication has no imports and
// keeps only a WeakMap of issued receipt sets. The private publication
// holding imported by completed-run publication has no imports and only calls
// the Store it is given. Publication action names are a fixed, dependency-free
// ABI translation table; they confer no publication authority.
// No namespace-wide permission.
// The Carrier snapshot transport is dependency-free: it uses typed arrays,
// text codecs and timers, and calls the supplied Store lease. It imports no
// filesystem or Node module; the resolved-dependency checks still apply.
// Completed Local output custody imports only the already reviewed common
// managed-failure progression. It retains the supplied cleanup owner without
// filesystem access or starting another computation.
export const conformanceModules = [
  '_build/workers/modules/bridge.mjs',
  '_build/workers/modules/fixture.mjs',
  '_build/workers/modules/async_bridge.mjs',
  'adapters/connectors-workers/strategy.generated.mjs',
  'adapters/local-node/strategy-bundle.mjs',
  'adapters/local-node/retained-input.mjs',
  'adapters/local-node/retained-store.mjs',
  'adapters/local-node/retained-output.mjs',
  'adapters/local-node/carrier-snapshot.mjs',
  'adapters/local-node/managed-output-custody.mjs',
  'adapters/store-local/managed-memory-representations.mjs',
  'adapters/store-local/representations.mjs',
  'adapters/store-local/moonbit-row-frames.mjs',
  'adapters/store-local/row-frames.mjs',
  'adapters/reference-compute-node/async-probe.mjs',
  'adapters/host-common/execution-sites.mjs',
  'adapters/host-common/managed-site-transfer.mjs',
  'adapters/host-common/strategy.mjs',
  'adapters/host-common/authorization-gate.mjs',
  'adapters/host-common/managed-failure.mjs',
  'adapters/host-common/durable-result-payload.mjs',
  'adapters/host-common/completed-run-publication.mjs',
  'adapters/host-common/private-publication-holding.mjs',
  'adapters/host-common/run-publication.mjs',
  'adapters/host-common/effect-receipt-custody.mjs',
  'adapters/host-common/run-publication-preflight.mjs',
  'adapters/host-common/publication-action.mjs',
  'adapters/host-common/runtime-core.mjs',
  'adapters/host-common/runtime-result.mjs',
  'adapters/host-common/result-output-limits.mjs',
  'adapters/workers/host.mjs',
  'adapters/host-common/local-js-host.mjs',
  'adapters/host-common/scoped-strategy.mjs',
  'adapters/workers/invocation.mjs',
  'adapters/workers/async-conformance.mjs',
  'adapters/workers/phase-audit.mjs',
  'adapters/workers/conformance.mjs',
];

export const hostModules = [
  '_build/workers/modules/bridge.mjs',
  'adapters/connectors-workers/strategy.generated.mjs',
  'adapters/local-node/strategy-bundle.mjs',
  'adapters/local-node/retained-input.mjs',
  'adapters/local-node/retained-store.mjs',
  'adapters/local-node/retained-output.mjs',
  'adapters/local-node/carrier-snapshot.mjs',
  'adapters/local-node/managed-output-custody.mjs',
  'adapters/store-local/managed-memory-representations.mjs',
  'adapters/store-local/representations.mjs',
  'adapters/store-local/moonbit-row-frames.mjs',
  'adapters/store-local/row-frames.mjs',
  'adapters/host-common/execution-sites.mjs',
  'adapters/host-common/managed-site-transfer.mjs',
  'adapters/host-common/strategy.mjs',
  'adapters/host-common/authorization-gate.mjs',
  'adapters/host-common/managed-failure.mjs',
  'adapters/host-common/durable-result-payload.mjs',
  'adapters/host-common/completed-run-publication.mjs',
  'adapters/host-common/private-publication-holding.mjs',
  'adapters/host-common/run-publication.mjs',
  'adapters/host-common/effect-receipt-custody.mjs',
  'adapters/host-common/run-publication-preflight.mjs',
  'adapters/host-common/publication-action.mjs',
  'adapters/host-common/runtime-core.mjs',
  'adapters/host-common/runtime-result.mjs',
  'adapters/host-common/result-output-limits.mjs',
  'adapters/workers/host.mjs',
  'adapters/host-common/local-js-host.mjs',
  'adapters/host-common/scoped-strategy.mjs',
];
