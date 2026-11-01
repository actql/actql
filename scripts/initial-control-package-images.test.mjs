import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {initialControlPackageOriginal, renderInitialControlPackageOriginal}
  from './initial-control-package-images.mjs';

const sha = value => createHash('sha256').update(value).digest('hex');
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-initial-control-image-'));
  t.after(() => rmSync(root, {recursive: true}));
  const put = (path, bytes) => {
    const selected = join(root, path);
    mkdirSync(dirname(selected), {recursive: true});
    writeFileSync(selected, bytes);
  };
  const destination = join(root, 'packages/local-node');
  put('packages/local-node/package.json', JSON.stringify({name: '@actql/local-node',
    version: '0.0.0-development', type: 'module', exports: {'.': './index.mjs',
      './selected-infer-startup': './selected-infer-startup.cjs'},
    dependencies: {'@actql/sdk': '0.0.0-development', '@actql/client-wire': '0.0.0-development'}}));
  put('packages/local-node/index.mjs', 'export const selected = "original-local-entry";\n');
  put('packages/local-node/selected-infer-startup.cjs', "module.exports = Object.freeze({});\n");
  for (const [name, source] of [['sdk', 'export const sdk = "original-sdk";\n'],
    ['client-wire', 'export const wire = "original-wire";\n']]) {
    put(`packages/${name}/package.json`, JSON.stringify({name: '@actql/' + name,
      version: '0.0.0-development', type: 'module', files: ['index.mjs'], exports: './index.mjs',
      ...(name === 'sdk' ? {dependencies: {'@actql/client-wire': '0.0.0-development'}} : {})}));
    put(`packages/${name}/index.mjs`, source);
  }
  mkdirSync(join(root, 'node_modules/@actql'), {recursive: true});
  symlinkSync(join(root, 'packages/client-wire'), join(root, 'node_modules/@actql/client-wire'));
  const runtimePath = 'common/common.js';
  put('packages/local-node/_build/js/release/build/' + runtimePath,
    'export const common = "independent-runtime-fixture";\n');
  const inputs = {runtimeFiles: [runtimePath]};
  const absent = Buffer.from("'use strict';\nmodule.exports = Object.freeze({imageInventory:undefined});\n");
  const outputs = new Map([[initialControlPackageOriginal, absent],
    ['adapters/host-node/embedded-local.mjs', Buffer.from('export function originalHost() {}\n')],
    ['spec/selected.json', Buffer.from('{"original":"exact-data"}\n')]]);
  const options = {root, destination, inputs, outputs};
  const render = () => renderInitialControlPackageOriginal(options);
  const read = bytes => {
    const module = {exports: undefined};
    runInNewContext(bytes.toString('utf8'), {module});
    return JSON.parse(JSON.stringify(module.exports.imageInventory));
  };
  return {root, destination, put, inputs, outputs, absent, options, render, read};
}

function addPublicNode(f, dependencies = {'@actql/local-node': '0.0.0-development',
  '@actql/sdk': '0.0.0-development'}) {
  f.put('packages/node/package.json', JSON.stringify({name: '@actql/node',
    version: '0.0.0-development', type: 'module', exports: './index.mjs',
    files: ['index.mjs', 'selected-infer-startup.cjs'], dependencies}));
  f.put('packages/node/index.mjs', 'export const facade = "original-node-facade";\n');
  f.put('packages/node/selected-infer-startup.cjs', 'module.exports = {};\n');
  for (const name of ['sdk', 'local-node']) {
    symlinkSync(join(f.root, 'packages', name), join(f.root, 'node_modules/@actql', name));
  }
}

test('the public Node facade has distinct Source facts and the same Local dependency binding', t => {
  const f = fixture(t); addPublicNode(f);
  const value = f.read(f.render());
  assert.equal(value.localPublicModule, 'index.mjs');
  assert.equal(value.publicNodeCoverage, 'prepared');
  assert.equal(value.publicNode.name, '@actql/node');
  assert.equal(value.publicNode.images.find(item => item.path === 'index.mjs').sha256,
    sha('export const facade = "original-node-facade";\n'));
  assert.deepEqual(value.publicNode.dependencies.find(item => item.name === '@actql/local-node'),
    {name: '@actql/local-node', local: true});
  assert.equal(value.packages[value.publicNode.dependencies.find(item => item.name === '@actql/sdk').package].name,
    '@actql/sdk');
  assert.equal(value.images.some(item => item.sha256 === value.publicNode.images[0].sha256), false);
  assert.equal(f.render().includes(Buffer.from(f.root)), false);
});

test('optional SDK rollback cannot leave dangling package indices in public Node coverage', t => {
  const f = fixture(t); addPublicNode(f, {'@actql/local-node': '0.0.0-development',
    '@actql/provider-ai-sdk': '0.0.0-development'});
  f.put('packages/provider-ai-sdk/package.json', JSON.stringify({name: '@actql/provider-ai-sdk',
    version: '0.0.0-development', type: 'module', exports: './index.mjs', files: ['index.mjs'],
    dependencies: {'@actql/missing-original': '0.0.0-development'}}));
  f.put('packages/provider-ai-sdk/index.mjs', 'export const optional = true;\n');
  symlinkSync(join(f.root, 'packages/provider-ai-sdk'), join(f.root, 'node_modules/@actql/provider-ai-sdk'));
  const value = f.read(f.render());
  assert.equal(value.optionalSdkCoverage, 'unprepared');
  assert.equal(value.publicNodeCoverage, 'unprepared');
  assert.equal(value.publicNode, null);
  assert.equal(value.packages.length, 2);
});

test('private root implementation files stay in the ordinary Local and public Node images', t => {
  const f = fixture(t); addPublicNode(f);
  for (const name of ['local-node', 'node']) {
    const file = 'packages/' + name + '/package.json';
    const manifest = JSON.parse(readFileSync(join(f.root, file), 'utf8'));
    manifest.files = [...new Set([...(manifest.files ?? []), 'initial-control-public-dispatch.cjs'])];
    f.put(file, JSON.stringify(manifest));
    f.put('packages/' + name + '/initial-control-public-dispatch.cjs',
      'module.exports=Object.freeze({selectedInitialControlHostPreparation:undefined});\n');
  }
  const first = f.read(f.render());
  const local = first.images.find(value => value.path === 'initial-control-public-dispatch.cjs');
  const node = first.publicNode.images.find(value => value.path === 'initial-control-public-dispatch.cjs');
  assert.equal(local.sha256, node.sha256);
  f.put('packages/local-node/initial-control-public-dispatch.cjs', 'module.exports={changed:true};\n');
  const second = f.read(f.render());
  assert.notEqual(second.images.find(value => value.path === local.path).sha256, local.sha256);
  assert.equal(second.publicNode.images.find(value => value.path === node.path).sha256, node.sha256);
  unlinkSync(join(f.destination, 'initial-control-public-dispatch.cjs'));
  assert.throws(f.render, /ENOENT/);
});

test('public Node exact Local version conflicts remain errors rather than absent coverage', t => {
  const f = fixture(t); addPublicNode(f, {'@actql/local-node': '0.0.1'});
  assert.throws(f.render, /WrongInitialControlDependencyVersion:@actql\/local-node/);
});

test('ordinary rendered adapter and runtime bytes produce one deterministic private image Source', t => {
  const f = fixture(t), bytes = f.render(), value = f.read(bytes);
  assert.equal(value.images.length, 6);
  assert.equal(value.hostModule, 'adapters/host-node/embedded-local.mjs');
  assert.equal(value.hostValidator, 'assertInitialControlHostPreparation');
  assert.equal(value.packages.length, 2);
  assert.equal(value.dependencies.length, 2);
  assert.equal(value.optionalSdkCoverage, 'absent');
  assert.equal(value.optionalSdk, null);
  assert.equal(value.images.some(item => item.path === initialControlPackageOriginal), false);
  assert.equal(value.images.find(item => item.path === 'spec/selected.json').sha256,
    sha(Buffer.from('{"original":"exact-data"}\n')));
  assert.equal(value.sourceBytes, value.images.reduce((sum, item) => sum + item.bytes, 0));
  assert.equal(value.engine.node, process.versions.node);
  assert.equal(value.engine.platform, process.platform);
  f.options.outputs = new Map([...f.outputs].reverse());
  assert.ok(f.render().equals(bytes));
  assert.equal(bytes.includes(Buffer.from(f.root)), false);
  // Only generated Source/data has been read. No preload, Host or issuer ran.
});

for (const path of ['_build/native/directory-darwin-arm64.node',
  '_build/native/local-files-linux-x64.node']) {
  test(`the private native image ${path} stays separate from UTF8 Source images`, t => {
    const f = fixture(t);
    const native = Buffer.from([0xfe, 0xed, 0xfa, 0xcf, 0xff, 0x00]);
    const descriptor = '_build/native/directory-original.json';
    f.options.nativeOutputs = new Map([[path, native], [descriptor, Buffer.from('{"original":"DATA only"}\n')]]);
    const value = f.read(f.render());
    assert.deepEqual(value.nativeImages, [{path, bytes: native.length, sha256: sha(native)}]);
    assert.equal(value.images.some(item => item.path === path), false);
    assert.equal(value.images.some(item => item.path === descriptor), true);
    f.options.nativeOutputs.set('_build/native/arbitrary.txt', Buffer.from('not a module'));
    assert.throws(f.render, /InvalidInitialControlNativeImage/);
  });
}

test('a missing runtime or package manifest preserves source-only issuer absence', t => {
  const f = fixture(t);
  unlinkSync(join(f.destination, '_build/js/release/build/common/common.js'));
  assert.equal(f.render(), f.absent);
  f.put('packages/local-node/_build/js/release/build/common/common.js', 'export const current = true;');
  unlinkSync(join(f.destination, 'package.json'));
  assert.equal(f.render(), f.absent);
});

test('runtime or rewritten adapter changes remain distinct original image facts', t => {
  const f = fixture(t), first = f.read(f.render());
  const path = '_build/js/release/build/common/common.js';
  const changed = 'export const common = "new-independent-runtime";\n';
  f.put('packages/local-node/' + path, changed);
  f.outputs.set('adapters/host-node/embedded-local.mjs', Buffer.from('export function changedHost() {}\n'));
  const second = f.read(f.render());
  assert.equal(second.images.find(item => item.path === path).sha256, sha(changed));
  assert.notEqual(first.images.find(item => item.path === path).sha256,
    second.images.find(item => item.path === path).sha256);
  assert.notEqual(first.images.find(item => item.path === 'adapters/host-node/embedded-local.mjs').sha256,
    second.images.find(item => item.path === 'adapters/host-node/embedded-local.mjs').sha256);
});

test('aliased runtime and escaped image names never become a selected image original', t => {
  const f = fixture(t), path = join(f.destination, '_build/js/release/build/common/common.js');
  unlinkSync(path);
  symlinkSync(join(f.destination, 'index.mjs'), path);
  assert.throws(f.render, /AliasedInitialControlRuntime/);
  unlinkSync(path);
  f.put('packages/local-node/_build/js/release/build/common/common.js', 'export const x = 1;');
  f.outputs.set('../foreign-source.mjs', Buffer.from('export const x = 2;'));
  assert.throws(f.render, /InvalidInitialControlImage/);
});

test('a required dependency has an exact version and a concrete original package image', t => {
  const f = fixture(t);
  f.put('packages/sdk/package.json', JSON.stringify({name: '@actql/sdk',
    version: '0.0.1', type: 'module', exports: './index.mjs', files: ['index.mjs']}));
  assert.throws(f.render, /WrongInitialControlDependencyVersion:@actql\/sdk/);
  f.put('packages/sdk/package.json', JSON.stringify({name: '@actql/foreign',
    version: '0.0.0-development', files: ['index.mjs']}));
  assert.throws(f.render, /WrongInitialControlDependency/);
});

test('an unresolved external composition remains absent rather than importing Core images by label', t => {
  const f = fixture(t);
  f.inputs.buildInputs = {callerPacketIsNotAnIssuer: true};
  assert.equal(f.render(), f.absent);
});

test('generated recipe reads the actual same manifest rather than a caller-supplied package flag', t => {
  const f = fixture(t), original = readFileSync(join(f.destination, 'package.json'));
  const value = f.read(f.render());
  assert.equal(value.images.find(item => item.path === 'package.json').sha256, sha(original));
  assert.equal('operationalAdmission' in value, false);
  assert.equal('capacity' in value, false);
  assert.equal('permission' in value, false);
});

test('unprepared optional SDK coverage does not discard original mandatory package images', t => {
  const f = fixture(t);
  f.put('packages/provider-ai-sdk/package.json', JSON.stringify({name: '@actql/provider-ai-sdk',
    version: '0.0.0-development', type: 'module', exports: './index.mjs', files: ['index.mjs'],
    dependencies: {'@actql/not-installed-fixture': '0.0.0-development'}}));
  f.put('packages/provider-ai-sdk/index.mjs', 'export const optional = true;\n');
  const value = f.read(f.render());
  assert.equal(value.packages.length, 2);
  assert.equal(value.dependencies.length, 2);
  assert.equal(value.optionalSdk, null);
  assert.equal(value.optionalSdkCoverage, 'unprepared');
  assert.equal('dependencyCoverage' in value, false);
});

test('dependency reuse cannot conceal a foreign exact-version requirement', t => {
  const f = fixture(t);
  f.put('packages/sdk/package.json', JSON.stringify({name: '@actql/sdk',
    version: '0.0.0-development', type: 'module', exports: './index.mjs', files: ['index.mjs'],
    dependencies: {'@actql/client-wire': '0.0.1'}}));
  assert.throws(f.render, /WrongInitialControlDependencyVersion:@actql\/client-wire/);
});

test('an aliased runtime ancestor cannot be mistaken for a regular selected file', t => {
  const f = fixture(t), parent = join(f.destination, '_build/js/release/build');
  const renamed = join(f.destination, '_build/js/release/original-build');
  renameSync(parent, renamed);
  symlinkSync(renamed, parent);
  assert.throws(f.render, /AliasedInitialControlRuntime/);
});

test('an escaped generated module reference cannot mutate any original image or dependency fact', t => {
  const f = fixture(t), module = {exports: undefined};
  runInNewContext(f.render().toString('utf8'), {module});
  const original = module.exports.imageInventory;
  const visit = value => {
    if (value !== null && typeof value === 'object') {
      assert.ok(Object.isFrozen(value));
      for (const child of Object.values(value)) visit(child);
    }
  };
  visit(module.exports);
  assert.equal(Reflect.set(original.images[0], 'sha256', '0'.repeat(64)), false);
  assert.equal(Reflect.set(original.packages[0].images[0], 'bytes', 0), false);
});
