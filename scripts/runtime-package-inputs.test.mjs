import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {moonOperations, moonInterfaceClosure} from './moon-interface-inventory.mjs';
import {productionPackageImports} from './source-dependency-closure.mjs';

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
