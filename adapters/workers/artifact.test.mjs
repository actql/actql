import test from 'node:test';
import assert from 'node:assert/strict';
import {checkWorkersArtifact} from './artifact.mjs';

function graph(dependency, options = {}) {
  return {
    inputs: {
      'worker.mjs': {imports: dependency ? [{path:dependency, kind:'import-statement', ...options}] : []},
      ...(dependency && !options.external ? {[dependency]:{imports:[]}} : {}),
    },
    outputs: {'bundle.mjs':{imports:[]}},
  };
}

test('resolved Workers graph rejects Node dependencies even if generated output erases them', () => {
  for (const name of ['node:fs', 'fs', 'fs/promises', 'child_process',
    'adapters/duckdb-node/host.mjs', 'adapters/host-node/entry.mjs',
    'node_modules/sneaky/index.js', 'addons/driver.node']) {
    assert.throws(() => checkWorkersArtifact(graph(name), 'export {};', ['worker.mjs', name]),
      /Workers(Module|Dependency)Rejected/, name);
  }
  assert.throws(() => checkWorkersArtifact(graph('unreviewed.mjs'), 'export {};', ['worker.mjs']),
    /WorkersDependencyRejected/);
});

test('unresolved and dynamic dependencies cannot escape source and artifact checks', () => {
  assert.throws(() => checkWorkersArtifact(graph('remote', {external:true}), '', ['worker.mjs','remote']),
    /WorkersDependencyRejected/);
  assert.throws(() => checkWorkersArtifact(graph('pure.mjs', {kind:'dynamic-import'}), '', ['worker.mjs','pure.mjs']),
    /WorkersDynamicDependency/);
  for (const source of ['import("./late.mjs")', 'export * from "./late.mjs"',
    'export {x} from "./late.mjs"']) {
    assert.throws(() => checkWorkersArtifact(graph(), source, ['worker.mjs']), /WorkersArtifactImport/);
  }
  const output = graph();
  output.outputs['bundle.mjs'].imports.push({path:'late.mjs',external:true});
  assert.throws(() => checkWorkersArtifact(output, '', ['worker.mjs']), /WorkersUnresolvedOutputImport/);
  checkWorkersArtifact(graph('pure.mjs'), 'const documentation = "node:fs";', ['worker.mjs','pure.mjs']);
});
