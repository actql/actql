import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {join, relative} from 'node:path';
import {test} from 'node:test';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {moonOperations, moonInterfaceClosure} from './moon-interface-inventory.mjs';
import {productionPackageImports} from './source-dependency-closure.mjs';
import {sourceInterfaceClosure} from './source-interface-closure.mjs';
import {typescriptInterface, typescriptInterfaceClosure} from './typescript-interface-inventory.mjs';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';
import {assertInterfaceCoverage, javascriptInterface} from './interface-inventory.mjs';

function publicFacadeFixture(t, name) {
  const root = process.cwd(), source = join(root, 'packages', name);
  const directory = mkdtempSync(join(root, '_build-public-facade-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const manifest = JSON.parse(readFileSync(join(source, 'package.json'), 'utf8'));
  writeFileSync(join(directory, 'package.json'), JSON.stringify(manifest));
  for (const path of manifest.files.filter(path => !path.includes('/') && path.endsWith('.mjs'))) {
    writeFileSync(join(directory, path), readFileSync(join(source, path)));
  }
  symlinkSync(join(root, 'adapters'), join(directory, 'adapters'), 'dir');
  mkdirSync(join(directory, 'node_modules/@actql'), {recursive: true});
  symlinkSync(join(root, 'packages/client-wire'), join(directory, 'node_modules/@actql/client-wire'), 'dir');
  const load = path => import(pathToFileURL(join(directory, path)).href);
  return {root, directory, manifest, load};
}

test('public observation facade retains the two original typed values and private nominal helpers', async t => {
  const {root, manifest, load} = publicFacadeFixture(t, 'local-node');
  const selected = manifest.exports['./observation'].default;
  const exposed = await load(selected);
  assert.deepEqual(Object.keys(exposed).sort(), ['createHostObservationConnection', 'observationLimits']);
  assert(manifest.files.includes(selected.slice(2)));
  const original = await import(pathToFileURL(join(root, 'adapters/host-common/observation.mjs')).href);
  for (const name of Object.keys(exposed)) assert.equal(exposed[name], original[name]);
  assert.equal(typeof original.installHostObservation, 'function');
  assert.equal(original.isHostObservationProjection({}), false);
  assert.equal(original.isHostObservationProjection(Object.freeze({})), false);
});

test('public Result facade retains all five original typed functions and the original private error class', async t => {
  const {root, manifest, load} = publicFacadeFixture(t, 'run-host-core');
  const selected = manifest.exports['./result-access'].default;
  const exposed = await load(selected);
  assert.deepEqual(Object.keys(exposed).sort(), ['deliverAuthorizedResult', 'describeAuthorizedResult',
    'inspectAuthorizedDeliveryAttempt', 'installResultAccessAuthority', 'installResultAccessService']);
  assert(manifest.files.includes(selected.slice(2)));
  const original = await load('result-access.mjs');
  for (const name of Object.keys(exposed)) assert.equal(exposed[name], original[name]);
  assert.throws(() => exposed.installResultAccessAuthority({}), error =>
    error instanceof original.ResultAccessError && error.code === 'InvalidResultAccessAuthority');
  const canonical = readFileSync(join(root, 'adapters/host-common/result-access.mjs'), 'utf8')
    .replace("'../../packages/client-wire/index.mjs'", "'@actql/client-wire'");
  assert.equal(readFileSync(join(root, 'packages/run-host-core/result-access.mjs'), 'utf8'), canonical);
});

test('ordinary runtime builder consumes the same side-effect-free input reader', () => {
  const root = process.cwd(), inputs = runtimePackageInputs(root);
  assert.deepEqual(inputs['local-node'].sources, localNodePackageInputs(root).runtimePackages);
  for (const item of Object.values(inputs)) {
    assert(item.sources.length && item.files.length);
    for (const name of item.sources) assert(readFileSync(`src/${name}/moon.pkg`, 'utf8').length);
  }
  assert.equal(inputs['coordinator-core'].files[0],
    'packages/coordinator-core/dist/remote_coordinator_abi.js');
});

test('Moon projection preserves typed argument roles without reading function bodies as declarations', () => {
  const values = moonOperations('// fn misleading() {}\nfn read(left : Int, right : Int) -> Int {\n let f = fn(x) { x }; left + right\n}\n');
  assert.equal(values.length, 1);
  assert.equal(values[0].name, 'read');
  assert.match(values[0].declaration, /left : Int , right : Int/u);
});

test('production scope reader excludes test and whitebox imports before closure traversal', () => {
  assert.deepEqual(productionPackageImports(`supported_targets = "js"\n
    import { "actql/actql/original" }\n
    import { "actql/actql/test_only" } for "test"\n
    import { "actql/actql/wb_only" } for "wbtest"`), ['original']);
});

test('actual ordinary coordinator boundary includes its production MoonBit dependencies and API', () => {
  const result = moonInterfaceClosure(process.cwd(), ['remote_coordinator_abi']);
  assert(result.packages.includes('execution_site'));
  assert(result.modules.some(value => value.module === 'src/remote_coordinator_abi/pkg.generated.mbti' && value.exports.length));
  assert(result.modules.every(value => !/_(?:test|wbtest|bbtest)\.mbt$/u.test(value.module)));
});

test('actual coordinator source graph records its generated artifact without pretending it was built', async () => {
  const result = await sourceInterfaceClosure(process.cwd(), {distributionRoots:
    npmInterfaceRoots(process.cwd()).filter(value => value.name === '@actql/coordinator-core')});
  assert.equal(result.qualification, 'source-input-coverage-only');
  assert(result.modules.some(value => value.module === 'packages/coordinator-core/index.mjs'));
  assert(result.artifacts.some(value => value.module === 'packages/coordinator-core/dist/remote_coordinator_abi.js'));
  assert(result.moon.packages.includes('remote_coordinator_abi'));
  assert(result.types.some(value => value.module === 'packages/coordinator-core/index.d.ts'));
});

test('ordinary bundled Workers sources and local Host assets remain in source coverage', async () => {
  const result = await sourceInterfaceClosure(process.cwd(), {distributionRoots:
    npmInterfaceRoots(process.cwd()).filter(value => ['@actql/run-host-core', '@actql/local-node'].includes(value.name))});
  assert.equal(result.qualification, 'source-input-coverage-only');
  assert(result.modules.some(value => value.module === 'adapters/workers/finite-runtime.mjs'));
  assert(result.artifacts.some(value => value.module === '_build/workers/modules/bridge.mjs' &&
    value.sourcePackages.includes('connectors_workers_bridge')));
  assert(!result.modules.some(value => /conformance|fixture/u.test(value.module)));
  assert(result.copies.some(value => value.destination === 'packages/local-node/adapters/host-common/observation.mjs'));
  assert(result.modules.some(value => value.module === 'adapters/connectors/local/iceberg/process_worker.py' && value.operations.length));
  assert(result.assets.some(value => value.module === 'spec/contracts/actql-local-table-iceberg.json'));
});

test('source graph retains imported contract data without parsing it as executable JavaScript', async t => {
  // The actual ordinary readers still own runtime input declarations.
  const root = process.cwd(), directory = mkdtempSync(join(root, '_build/interface-source-data-'));
  const name = relative(root, directory);
  t.after(() => rmSync(directory, {recursive: true}));
  writeFileSync(join(directory, 'entry.mjs'), 'import contract from "./schema.json"; export const value = contract;');
  writeFileSync(join(directory, 'schema.json'), '{"type":"object","properties":{"_0":{"type":"string"}}}');
  const result = await sourceInterfaceClosure(root, {distributionRoots: [
    {name: '@actql/source-control', entrances: [`${name}/entry.mjs`]}]});
  assert.equal(result.modules.length, 1);
  assert.equal(result.assets[0].module, `${name}/schema.json`);
  assert.equal(result.assets[0].qualification, 'resolved-distribution-data');
  assert.deepEqual(result.modules[0].compilerFields, []);
});

test('new extensionless executable source entrances cannot disappear before operation coverage', async t => {
  const root = process.cwd(), directory = mkdtempSync(join(root, '_build/interface-command-source-'));
  t.after(() => rmSync(directory, {recursive: true}));
  const name = relative(root, directory);
  writeFileSync(join(directory, 'policy'), '#!/usr/bin/env node\nexport function decideUnknown(value) {return value;}\n');
  writeFileSync(join(directory, 'probe'), '#!/usr/bin/env python3\ndef decide_unknown(value):\n    return value\n');
  const commands = [`${name}/policy`, `${name}/probe`];
  const distributionRoots = [{name: 'outside-cli', entrances: commands, commands}];
  const result = await sourceInterfaceClosure(root, {distributionRoots});
  assert.deepEqual(result.modules.map(value => value.module), commands);
  assert.throws(() => assertInterfaceCoverage({root, modules: result.modules, declarations: []}),
    /Unregistered distributed interface/u);
  const pythonOnly = await sourceInterfaceClosure(root, {distributionRoots: [
    {name: 'outside-python-cli', entrances: [commands[1]], commands: [commands[1]]}]});
  assert.equal(pythonOnly.modules.length, 1);
  writeFileSync(join(directory, 'policy'), Buffer.from([0x7f, 69, 76, 70]));
  await assert.rejects(sourceInterfaceClosure(root, {distributionRoots}), /Unregistered executable source interface/u);
});

test('pinned TypeScript parser inventories named declaration roles and relative public type closure', () => {
  const result = typescriptInterface('export interface Host {read(run: string, task: string): Promise<void>;}');
  assert.deepEqual(result.exports, ['Host']);
  assert.deepEqual(result.operations[0], {name: 'Host/read',
    parameters: ['run: string', 'task: string'], result: 'Promise<void>'});
  assert(typescriptInterfaceClosure(process.cwd(), ['packages/sdk/index.d.ts'])
    .some(value => value.module === 'packages/sdk/standard-schema.d.ts'));
});

test('ordinary Local source binds its finite native delivery images to the actual build inputs', async () => {
  const result = await sourceInterfaceClosure(process.cwd(), {distributionRoots:
    npmInterfaceRoots(process.cwd()).filter(value => value.name === '@actql/local-node')});
  assert.equal(result.qualification, 'source-input-coverage-only');
  const native = result.artifacts.filter(value => value.module.endsWith('.node'));
  assert.equal(native.length, 6);
  for (const artifact of native) {
    assert.equal(artifact.build, 'scripts/build-node-directory-native.mjs');
    assert.deepEqual(artifact.sourcePackages, []);
    assert.deepEqual(artifact.sourceFiles, [artifact.target.startsWith('linux-')
      ? 'adapters/host-node/native/local-files-linux.c' : 'adapters/host-node/native/directory-darwin.c',
      'adapters/host-node/native/napi-filesystem-helpers.inc',
      'adapters/connectors/local/site/root-filesystem-platform.inc',
      'adapters/connectors/local/site/root-filesystem.inc',
      'adapters/connectors/local/site/root-file-writer.inc']);
    assert.equal(artifact.qualification, 'native-build-input-reference-only');
    assert.equal(artifact.sha256, undefined, 'Source coverage is not native artifact acceptance');
  }
  assert.deepEqual([...new Set(native.map(value => value.target))].sort(),
    ['darwin-arm64/node-napi8', 'darwin-x64/node-napi8', 'linux-x64/node-napi8']);
  for (const path of new Set(native.flatMap(value => [...value.sourceFiles, value.build]))) {
    assert(result.assets.some(value => value.module === path && value.qualification === 'compiled-native-build-source'));
  }
  const builder = readFileSync(native[0].build, 'utf8');
  for (const path of new Set(native.flatMap(value => value.sourceFiles))) assert(builder.includes(`'${path}'`));
  const host = result.modules.find(value => value.module === 'adapters/host-node/embedded-local.mjs');
  assert.deepEqual(host.unresolvedSyntax, []);
  assert.equal(host.imports.filter(path => path.endsWith('.node')).length, 6);
  assert(result.modules.every(value => !value.module.endsWith('.node')));
});

test('unregistered native paths and computed require remain outside the fixed delivery mapping', async t => {
  const root = process.cwd(), directory = mkdtempSync(join(root, '_build/interface-native-'));
  t.after(() => rmSync(directory, {recursive: true}));
  const name = relative(root, directory);
  writeFileSync(join(directory, 'entry.mjs'), 'import {createRequire} from "node:module"; const require=createRequire(import.meta.url); export const value=require("./foreign.node");');
  writeFileSync(join(directory, 'foreign.node'), Buffer.from([0xcf, 0xfa, 0xed, 0xfe]));
  await assert.rejects(sourceInterfaceClosure(root, {distributionRoots: [
    {name: '@actql/source-control', entrances: [`${name}/entry.mjs`]}]}), /Unregistered native source interface artifact/u);
  assert.deepEqual(javascriptInterface('export function load(path) {return require(path);}').unresolvedSyntax,
    ['runtime-dependent module dependency requires original owner/artifact mapping']);
});
