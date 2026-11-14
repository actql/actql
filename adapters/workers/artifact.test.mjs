import test from 'node:test';
import assert from 'node:assert/strict';
import {checkWorkersArtifact, conformanceModules, hostModules,
  finiteConformanceModules, finiteRuntimeModules} from './artifact.mjs';
import {build} from 'esbuild';
import {parse as parseJavaScript} from 'acorn';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildHost, buildFiniteRuntime} from './build.mjs';
import {checkPureRuntime} from './moon-runtime.mjs';
import {generateCompilerBindings} from '../../scripts/generate-js-compiler-bindings.mjs';
import {actionBindingOutputs} from '../../scripts/generate-js-action-bindings.mjs';

function graph(dependency, options = {}) {
  return {
    inputs: {
      'worker.mjs': {imports: dependency ? [{path:dependency, kind:'import-statement', ...options}] : []},
      ...(dependency && !options.external ? {[dependency]:{imports:[]}} : {}),
    },
    outputs: {'bundle.mjs':{imports:[]}},
  };
}

test('retired Workers invocation entry is excluded from every module profile', () => {
  const retired = 'adapters/workers/invocation.mjs';
  for (const modules of [conformanceModules, hostModules,
    finiteConformanceModules, finiteRuntimeModules]) {
    assert.ok(!modules.includes(retired));
    assert.throws(() => checkWorkersArtifact(graph(retired), 'export {};',
      ['worker.mjs', ...modules]), /WorkersDependencyRejected/);
  }
});

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

test('task observation has an explicitly reviewed dependency-free Workers graph', async () => {
  const result = await build({
    absWorkingDir: fileURLToPath(new URL('../../', import.meta.url)),
    entryPoints: ['adapters/host-common/task-observation.mjs'],
    bundle: true, platform: 'browser', format: 'esm',
    metafile: true, write: false,
  });
  assert.deepEqual(Object.keys(result.metafile.inputs), [
    'adapters/host-common/task-observation.mjs',
  ]);
  assert.deepEqual(result.metafile.inputs['adapters/host-common/task-observation.mjs'].imports, []);
  for (const modules of [hostModules, conformanceModules]) {
    checkWorkersArtifact(result.metafile, result.outputFiles[0].text, modules);
  }
});

test('task observation review does not admit an unreviewed sibling or dependency', () => {
  const sibling = 'adapters/host-common/task-observation-unreviewed.mjs';
  for (const modules of [hostModules, conformanceModules]) {
    assert.throws(() => checkWorkersArtifact({
      inputs: {[sibling]: {imports: []}},
      outputs: {'bundle.mjs': {imports: []}},
    }, 'export {};', modules), /WorkersModuleRejected/);
    assert.throws(() => checkWorkersArtifact({
      inputs: {
        'adapters/host-common/task-observation.mjs': {
          imports: [{path: sibling, kind: 'import-statement'}],
        },
        [sibling]: {imports: []},
      },
      outputs: {'bundle.mjs': {imports: []}},
    }, 'export {};', modules), /WorkersDependencyRejected/);
  }
});

test('original Credential metadata has only the reviewed portable Workers closure', async () => {
  const signing = 'adapters/host-common/local-signing-metadata.mjs';
  const preparation = 'adapters/host-common/installation-preparation-metadata.mjs';
  const fields = 'adapters/host-common/installation-preparation-fields.generated.mjs';
  const binding = 'adapters/host-common/compiler-binding.generated.mjs';
  const resultBinding = 'adapters/host-common/runtime-result.mjs';
  const result = await build({
    absWorkingDir: fileURLToPath(new URL('../../', import.meta.url)),
    entryPoints: [signing, preparation], bundle: true, platform: 'browser',
    format: 'esm', metafile: true, write: false, outdir: 'unused-output',
  });
  assert.deepEqual(Object.keys(result.metafile.inputs).sort(),
    [binding, resultBinding, signing, preparation, fields].sort());
  assert.deepEqual(result.metafile.inputs[fields].imports, []);
  assert.deepEqual(result.metafile.inputs[signing].imports.map(value => value.path), [resultBinding]);
  assert.deepEqual(result.metafile.inputs[preparation].imports.map(value => value.path).sort(),
    [resultBinding, fields].sort());
  for (const modules of [hostModules, conformanceModules,
    finiteRuntimeModules, finiteConformanceModules]) {
    for (const output of result.outputFiles) {
      checkWorkersArtifact(result.metafile, output.text, modules);
    }
  }
});

test('original metadata review grants no sibling, Node or dynamic dependency allowance', () => {
  const signing = 'adapters/host-common/local-signing-metadata.mjs';
  const preparation = 'adapters/host-common/installation-preparation-metadata.mjs';
  const fields = 'adapters/host-common/installation-preparation-fields.generated.mjs';
  const sibling = 'adapters/host-common/installation-preparation-physical.mjs';
  for (const modules of [hostModules, conformanceModules,
    finiteRuntimeModules, finiteConformanceModules]) {
    assert.throws(() => checkWorkersArtifact({inputs: {[sibling]: {imports: []}},
      outputs: {'bundle.mjs': {imports: []}}}, 'export {};', modules), /WorkersModuleRejected/);
    for (const metadata of [signing, preparation, fields]) {
      for (const dependency of [sibling, 'node:fs']) {
        assert.throws(() => checkWorkersArtifact({
          inputs: {[metadata]: {imports: [{path: dependency, kind: 'import-statement'}]}},
          outputs: {'bundle.mjs': {imports: []}},
        }, 'export {};', modules), /WorkersDependencyRejected/);
      }
      assert.throws(() => checkWorkersArtifact({
        inputs: {[metadata]: {imports: [{path: fields, kind: 'dynamic-import'}]},
          ...(metadata === fields ? {} : {[fields]: {imports: []}})},
        outputs: {'bundle.mjs': {imports: []}},
      }, 'export {};', modules), /WorkersDynamicDependency/);
    }
  }
});

test('generated compiler binding has the exact canonical dependency-free Workers graph', async () => {
  const root = new URL('../../', import.meta.url);
  const binding = 'adapters/host-common/compiler-binding.generated.mjs';
  generateCompilerBindings(root);
  const source = readFileSync(new URL(binding, root), 'utf8');
  assert.equal(source, readFileSync(new URL('scripts/templates/js-compiler-binding.mjs', root), 'utf8'));
  checkPureRuntime(source);
  const result = await build({
    absWorkingDir: fileURLToPath(root), entryPoints: [binding],
    bundle: true, platform: 'browser', format: 'esm',
    metafile: true, write: false,
  });
  assert.deepEqual(Object.keys(result.metafile.inputs), [binding]);
  assert.deepEqual(result.metafile.inputs[binding].imports, []);
  for (const modules of [hostModules, conformanceModules,
    finiteRuntimeModules, finiteConformanceModules]) {
    checkWorkersArtifact(result.metafile, result.outputFiles[0].text, modules);
  }
});

test('generated compiler binding review grants no sibling or dependency allowance', () => {
  const binding = 'adapters/host-common/compiler-binding.generated.mjs';
  const sibling = 'adapters/host-common/compiler-binding-unreviewed.mjs';
  for (const modules of [hostModules, conformanceModules,
    finiteRuntimeModules, finiteConformanceModules]) {
    assert.throws(() => checkWorkersArtifact({
      inputs: {[sibling]: {imports: []}}, outputs: {'bundle.mjs': {imports: []}},
    }, 'export {};', modules), /WorkersModuleRejected/);
    for (const dependency of [sibling, 'node:fs']) {
      assert.throws(() => checkWorkersArtifact({
        inputs: {[binding]: {imports: [{path: dependency, kind: 'import-statement'}]}},
        outputs: {'bundle.mjs': {imports: []}},
      }, 'export {};', modules), /WorkersDependencyRejected/);
    }
  }
});

test('publication byte accounting has only its exact dependency-free Workers closure', async () => {
  const accounting = 'adapters/host-common/publication-capacity.mjs';
  const result = await build({
    absWorkingDir: fileURLToPath(new URL('../../', import.meta.url)), entryPoints: [accounting],
    bundle: true, platform: 'browser', format: 'esm', metafile: true, write: false,
  });
  assert.deepEqual(Object.keys(result.metafile.inputs), [accounting]);
  assert.deepEqual(result.metafile.inputs[accounting].imports, []);
  for (const modules of [hostModules, conformanceModules, finiteRuntimeModules, finiteConformanceModules]) {
    checkWorkersArtifact(result.metafile, result.outputFiles[0].text, modules);
  }
});

test('publication accounting review grants no sibling Node or dynamic dependency allowance', () => {
  const accounting = 'adapters/host-common/publication-capacity.mjs';
  const sibling = 'adapters/host-common/publication-capacity-unreviewed.mjs';
  for (const modules of [hostModules, conformanceModules, finiteRuntimeModules, finiteConformanceModules]) {
    assert.throws(() => checkWorkersArtifact({inputs: {[sibling]: {imports: []}},
      outputs: {'bundle.mjs': {imports: []}}}, 'export {};', modules), /WorkersModuleRejected/);
    for (const dependency of [sibling, 'node:fs']) {
      assert.throws(() => checkWorkersArtifact({
        inputs: {[accounting]: {imports: [{path: dependency, kind: 'import-statement'}]}},
        outputs: {'bundle.mjs': {imports: []}},
      }, 'export {};', modules), /WorkersDependencyRejected/);
    }
    assert.throws(() => checkWorkersArtifact({
      inputs: {[accounting]: {imports: [{path: accounting, kind: 'dynamic-import'}]}},
      outputs: {'bundle.mjs': {imports: []}},
    }, 'export {};', modules), /WorkersDynamicDependency/);
  }
});

test('generated strategy actions have the canonical dependency-free Workers graph', async () => {
  const root = new URL('../../', import.meta.url);
  const binding = 'adapters/host-common/strategy-actions.mjs';
  const source = readFileSync(new URL(binding, root), 'utf8');
  assert.equal(source, actionBindingOutputs(root).get(binding));
  checkPureRuntime(source);
  const result = await build({
    absWorkingDir: fileURLToPath(root), entryPoints: [binding],
    bundle: true, platform: 'browser', format: 'esm',
    metafile: true, write: false,
  });
  assert.deepEqual(Object.keys(result.metafile.inputs), [binding]);
  assert.deepEqual(result.metafile.inputs[binding].imports, []);
  for (const modules of [hostModules, conformanceModules,
    finiteRuntimeModules, finiteConformanceModules]) {
    checkWorkersArtifact(result.metafile, result.outputFiles[0].text, modules);
  }
});

test('generated strategy action review grants no sibling or dependency allowance', () => {
  const binding = 'adapters/host-common/strategy-actions.mjs';
  const sibling = 'adapters/host-common/strategy-actions-unreviewed.mjs';
  for (const modules of [hostModules, conformanceModules,
    finiteRuntimeModules, finiteConformanceModules]) {
    assert.throws(() => checkWorkersArtifact({
      inputs: {[sibling]: {imports: []}}, outputs: {'bundle.mjs': {imports: []}},
    }, 'export {};', modules), /WorkersModuleRejected/);
    for (const dependency of [sibling, 'node:fs']) {
      assert.throws(() => checkWorkersArtifact({
        inputs: {[binding]: {imports: [{path: dependency, kind: 'import-statement'}]}},
        outputs: {'bundle.mjs': {imports: []}},
      }, 'export {};', modules), /WorkersDependencyRejected/);
    }
  }
});

test('completed Local output custody is portable in both Workers profiles', async () => {
  const result = await build({
    absWorkingDir: fileURLToPath(new URL('../../', import.meta.url)),
    entryPoints: ['adapters/local-node/managed-output-custody.mjs'],
    bundle: true, platform: 'browser', format: 'esm',
    metafile: true, write: false,
  });
  for (const modules of [hostModules, conformanceModules]) {
    checkWorkersArtifact(result.metafile, result.outputFiles[0].text, modules);
  }
});

test('product Local-only Host builds separately without conformance or test Connector modules', async t => {
  const artifact = await buildHost();
  const modules = Object.keys(artifact.metafile.inputs);
  assert.ok(modules.includes('adapters/local-node/strategy-bundle.mjs'));
  assert.ok(modules.includes('adapters/local-node/carrier-snapshot.mjs'));
  assert.ok(modules.includes('adapters/host-common/local-js-host.mjs'));
  assert.ok(modules.includes('adapters/host-common/task-observation.mjs'));
  assert.ok(modules.includes('adapters/host-common/scoped-strategy.mjs'));
  assert.ok(!modules.includes('adapters/workers/invocation.mjs'));
  assert.ok(modules.every(path => !/conformance|reference|fixture|async_bridge/.test(path)));
  assert.ok(modules.every(path => !/(?:^|\/)connectors\/duckdb(?:\/|$)|duckdb-node|@duckdb/.test(path)));
  assert.doesNotMatch(artifact.source, /(?:libduckdb|@duckdb\/node-api|native-addon-marker)/);
  t.diagnostic(JSON.stringify({profile:'host',bytes:artifact.bytes,gzipBytes:artifact.gzipBytes,modules:modules.length}));
});

test('finite package entry bundles only the explicitly seeded production runtime', async t => {
  const artifact = await buildFiniteRuntime();
  const modules = Object.keys(artifact.metafile.inputs);
  assert.ok(modules.includes('_build/workers/modules/bridge.mjs'));
  assert.ok(modules.includes('adapters/workers/finite-runtime.mjs'));
  assert.ok(modules.includes('adapters/workers/finite.mjs'));
  assert.ok(modules.every(path => !/conformance|reference|fixture|async_bridge/.test(path)));
  assert.doesNotMatch(artifact.source, /workersFiniteFixture|actql-test-owner/);
  assert.deepEqual(Object.values(artifact.metafile.outputs)[0].exports,
    ['createWorkersFiniteRuntime']);
  const fixture = '_build/workers/modules/fixture.mjs';
  assert.throws(() => checkWorkersArtifact(graph(fixture), '',
    ['worker.mjs', ...finiteRuntimeModules]), /WorkersDependencyRejected/);
  t.diagnostic(JSON.stringify({profile: 'finite-runtime', bytes: artifact.bytes,
    gzipBytes: artifact.gzipBytes, modules: modules.length}));
});


test('canonical Ledger projection has one exact import-free shared Workers graph', async () => {
  const leaf = 'adapters/host-common/ledger-contract.generated.mjs';
  const result = await build({absWorkingDir: fileURLToPath(new URL('../../', import.meta.url)),
    entryPoints: [leaf], bundle: true, platform: 'browser', format: 'esm',
    metafile: true, write: false});
  assert.deepEqual(Object.keys(result.metafile.inputs), [leaf]);
  assert.deepEqual(result.metafile.inputs[leaf].imports, []);
  checkPureRuntime(readFileSync(new URL('../../' + leaf, import.meta.url), 'utf8'));
  for (const modules of [hostModules, conformanceModules, finiteRuntimeModules, finiteConformanceModules]) {
    assert.equal(modules.filter(value => value === leaf).length, 1);
    checkWorkersArtifact(result.metafile, result.outputFiles[0].text, modules);
  }
});

test('shared Ledger review keeps Node paths siblings and hidden dependencies rejected', () => {
  const leaf = 'adapters/host-common/ledger-contract.generated.mjs';
  const oldNode = 'adapters/host-node/ledger-contract.generated.mjs';
  const sibling = 'adapters/host-common/ledger-contract-physical.mjs';
  for (const modules of [hostModules, conformanceModules, finiteRuntimeModules, finiteConformanceModules]) {
    assert(!modules.includes(oldNode));
    assert.throws(() => checkWorkersArtifact({inputs: {[oldNode]: {imports: []}},
      outputs: {'bundle.mjs': {imports: []}}}, 'export {};', [...modules, oldNode]), /WorkersModuleRejected/);
    assert.throws(() => checkWorkersArtifact({inputs: {[sibling]: {imports: []}},
      outputs: {'bundle.mjs': {imports: []}}}, 'export {};', modules), /WorkersModuleRejected/);
    for (const dependency of [sibling, 'node:fs']) {
      assert.throws(() => checkWorkersArtifact({inputs: {[leaf]: {
        imports: [{path: dependency, kind: 'import-statement'}]}},
      outputs: {'bundle.mjs': {imports: []}}}, 'export {};', modules), /WorkersDependencyRejected/);
    }
    assert.throws(() => checkWorkersArtifact({inputs: {[leaf]: {
      imports: [{path: leaf, kind: 'dynamic-import'}]}}, outputs: {'bundle.mjs': {imports: []}}},
    'export {};', modules), /WorkersDynamicDependency/);
  }
});

test('managed advance diagnostic has one exact reviewed pure Workers closure', async () => {
  const root = new URL('../../', import.meta.url);
  const module = 'adapters/local-node/managed-advance-diagnostic.mjs';
  const binding = 'adapters/host-common/compiler-binding.generated.mjs';
  const source = readFileSync(new URL(module, root), 'utf8');
  const imports = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .filter(node => node.type === 'ImportDeclaration');
  assert.equal(imports.length, 1);
  assert.equal(imports[0].source.value, '../host-common/compiler-binding.generated.mjs');
  assert.deepEqual(imports[0].specifiers.map(node => [node.imported.name, node.local.name]),
    [['runtimeIsBoxedSome', 'runtimeIsBoxedSome'], ['runtimeField', 'runtimeField'],
      ['runtimeOptionalField', 'runtimeOptionalField'], ['runtimeUnboxedReferenceOption', 'runtimeUnboxedReferenceOption']]);
  checkPureRuntime(source.slice(0, imports[0].start) + source.slice(imports[0].end));
  checkPureRuntime(readFileSync(new URL(binding, root), 'utf8'));
  const result = await build({absWorkingDir: fileURLToPath(root), entryPoints: [module],
    bundle: true, platform: 'browser', format: 'esm', metafile: true, write: false});
  assert.deepEqual(Object.keys(result.metafile.inputs).sort(), [module, binding].sort());
  assert.deepEqual(result.metafile.inputs[module].imports.map(value => [value.path, value.kind]),
    [[binding, 'import-statement']]);
  assert.deepEqual(result.metafile.inputs[binding].imports, []);
  checkPureRuntime(result.outputFiles[0].text);
  for (const modules of [hostModules, conformanceModules, finiteRuntimeModules, finiteConformanceModules]) {
    assert.equal(modules.filter(path => path === module).length, 1);
    checkWorkersArtifact(result.metafile, result.outputFiles[0].text, modules);
  }
});

test('managed advance diagnostic classification grants no sibling builtin or dynamic allowance', () => {
  const module = 'adapters/local-node/managed-advance-diagnostic.mjs';
  const sibling = 'adapters/local-node/managed-advance-diagnostic-unreviewed.mjs';
  for (const modules of [hostModules, conformanceModules, finiteRuntimeModules, finiteConformanceModules]) {
    assert.throws(() => checkWorkersArtifact({inputs: {[sibling]: {imports: []}},
      outputs: {'bundle.mjs': {imports: []}}}, 'export {};', modules), /WorkersModuleRejected/);
    for (const dependency of [sibling, 'node:fs']) {
      assert.throws(() => checkWorkersArtifact({
        inputs: {[module]: {imports: [{path: dependency, kind: 'import-statement'}]}},
        outputs: {'bundle.mjs': {imports: []}},
      }, 'export {};', modules), /WorkersDependencyRejected/);
    }
    assert.throws(() => checkWorkersArtifact({
      inputs: {[module]: {imports: [{path: module, kind: 'dynamic-import'}]}},
      outputs: {'bundle.mjs': {imports: []}},
    }, 'export {};', modules), /WorkersDynamicDependency/);
  }
});
