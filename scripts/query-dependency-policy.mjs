// Test-only architectural assertions. Manifest syntax and production scope
// belong to the shared reader; these policies describe responsibility edges.
import assert from 'node:assert/strict';
import {productionDependencyClosure, productionPackageImports} from './source-dependency-closure.mjs';

export const concreteDependencies = /^(?:connectors\/|duckdb_)/u;
export const conformanceDependencies = /^(?:connector_conformance$|connectors\/[^/]+\/conformance(?:\/|$)|node_host_conformance$|workers_conformance$)/u;

export function assertProductionBoundary(name, readManifest, forbidden) {
  for (const dependency of productionDependencyClosure(name, readManifest)) {
    assert.ok(!forbidden.test(dependency),
      `Forbidden production dependency: ${name} -> ${dependency}`);
  }
}

export function assertProductionImports(name, source, forbidden) {
  for (const dependency of productionPackageImports(source)) {
    assert.ok(!forbidden.test(dependency),
      `Forbidden production import: ${name} -> ${dependency}`);
  }
}

export function assertOpaqueHandles(api, handles) {
  for (const handle of handles) {
    assert.match(api, new RegExp(`^type ${handle}(?:\\[[^\\n]*\\])?$`, 'm'),
      `Missing opaque handle: ${handle}`);
    assert.doesNotMatch(api, new RegExp(`(?:struct|enum) ${handle}\\b`),
      `Public representation: ${handle}`);
  }
}

export function assertPublicBoundary(name, api, forbidden) {
  assert.doesNotMatch(api, forbidden, `Public responsibility leak: ${name}`);
}

export function publicFunction(api, name) {
  const signature = api.split('\n').find(line =>
    new RegExp(`^pub fn(?:\\[[^\\]]*\\])? ${name}\\(`).test(line));
  assert.ok(signature, `Missing public operation: ${name}`);
  return signature;
}

export function assertCommonAdapterGraph(paths) {
  for (const path of paths) {
    assert.doesNotMatch(path, /^adapters\/connectors(?:-builtin)?\//u,
      `Connector implementation in common adapter graph: ${path}`);
    assert.doesNotMatch(path, /(?:\.fixture|\.test)\.mjs$/u,
      `Test authority in product adapter graph: ${path}`);
  }
}
