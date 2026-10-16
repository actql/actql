import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {join, relative} from 'node:path';
import {test} from 'node:test';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {moonOperations, moonInterfaceClosure} from './moon-interface-inventory.mjs';
import {productionPackageImports} from './source-dependency-closure.mjs';
import {sourceInterfaceClosure} from './source-interface-closure.mjs';
import {typescriptInterface, typescriptInterfaceClosure} from './typescript-interface-inventory.mjs';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';

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

test('pinned TypeScript parser inventories named declaration roles and relative public type closure', () => {
  const result = typescriptInterface('export interface Host {read(run: string, task: string): Promise<void>;}');
  assert.deepEqual(result.exports, ['Host']);
  assert.deepEqual(result.operations[0], {name: 'Host/read',
    parameters: ['run: string', 'task: string'], result: 'Promise<void>'});
  assert(typescriptInterfaceClosure(process.cwd(), ['packages/sdk/index.d.ts'])
    .some(value => value.module === 'packages/sdk/standard-schema.d.ts'));
});
