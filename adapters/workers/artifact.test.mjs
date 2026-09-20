import test from 'node:test';
import assert from 'node:assert/strict';
import {checkWorkersArtifact} from './artifact.mjs';
import {build} from 'esbuild';
import {mkdtempSync,mkdirSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {buildHost} from './build.mjs';

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
    'adapters/connectors/duckdb/node/host.mjs', 'adapters/host-node/entry.mjs',
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

test('actual bundler resolution catches a forbidden unused Connector removed from output', async t => {
  const directory = mkdtempSync(join(tmpdir(),'actql-worker-bundle-negative-'));
  t.diagnostic(`isolated injection retained: ${directory}`);
  mkdirSync(join(directory,'adapters/connectors/duckdb/node'),{recursive:true});
  writeFileSync(join(directory,'worker.mjs'),
    'import {unused} from "./adapters/connectors/duckdb/node/unused.mjs"; export const result = 1;');
  writeFileSync(join(directory,'adapters/connectors/duckdb/node/unused.mjs'),'export const unused = "native-addon-marker";');
  const result = await build({absWorkingDir:directory,entryPoints:['worker.mjs'],
    bundle:true,platform:'browser',format:'esm',metafile:true,write:false});
  assert.doesNotMatch(result.outputFiles[0].text,/native-addon-marker/);
  assert.throws(() => checkWorkersArtifact(result.metafile,result.outputFiles[0].text,Object.keys(result.metafile.inputs)),
    /Workers(Module|Dependency)Rejected/);
});

test('product Local-only Host builds separately without conformance or test Connector modules', async t => {
  const artifact = await buildHost();
  const modules = Object.keys(artifact.metafile.inputs);
  assert.ok(modules.includes('adapters/local-node/strategy-bundle.mjs'));
  assert.ok(modules.every(path => !/conformance|reference|fixture|async_bridge/.test(path)));
  assert.ok(modules.every(path => !/(?:^|\/)connectors\/duckdb(?:\/|$)|duckdb-node|@duckdb/.test(path)));
  assert.doesNotMatch(artifact.source, /(?:libduckdb|@duckdb\/node-api|native-addon-marker)/);
  t.diagnostic(JSON.stringify({profile:'host',bytes:artifact.bytes,gzipBytes:artifact.gzipBytes,modules:modules.length}));
});
