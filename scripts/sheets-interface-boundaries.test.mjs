// Existing distributed-interface readers remain the sole syntax/coverage gate.
// This producer supplies Sheets contracts and actual boundary-specific controls.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {assertInterfaceCoverage, javascriptInterface} from './interface-inventory.mjs';
import {moonInterfaceClosure} from './moon-interface-inventory.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const declarations = JSON.parse(readFileSync(new URL(
  '../src/connectors/sheets/interface-boundaries.json', import.meta.url)));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const jsModule = (module, text = readFileSync(new URL(module, `file://${root}`), 'utf8')) =>
  ({module, sha256: digest(text), ...javascriptInterface(text)});
const modules = () => [
  ...['host', 'site'].flatMap(directory => readdirSync(new URL(
    `../adapters/connectors/sheets/${directory}/`, import.meta.url))
    .filter(name => name.endsWith('.mjs')).map(name =>
      jsModule(`adapters/connectors/sheets/${directory}/${name}`))),
  ...moonInterfaceClosure(root, ['connectors/sheets/catalog', 'connectors/sheets/host_node'])
    .modules.filter(module => module.module.startsWith('src/connectors/sheets/')),
];

test('every Sheets production operation and API references its original ten-attribute contract', () => {
  const actual = modules();
  assert.equal(actual.length, 18);
  assert.equal(assertInterfaceCoverage({root, modules: actual, declarations}), 18);
  assert.equal(new Set(declarations.map(value => value.module)).size, 18);
  for (const module of actual.filter(value => value.module.endsWith('.mjs'))) {
    assert.deepEqual(module.compilerFields, [], module.module);
  }
});

test('the private operation-qualified role issuer requires its own original Moon operation contract', () => {
  const path = 'src/connectors/sheets/catalog/range_declaration.mbt';
  const module = modules().find(value => value.module === path);
  assert(module.operations.some(value => value.name === 'range_named_contract'));
  const changed = structuredClone(declarations);
  const selected = changed.find(value => value.module === path);
  selected.operations = selected.operations.filter(value => value.name !== 'range_named_contract');
  selected.contracts[0].operations = selected.contracts[0].operations.filter(value => value !== 'range_named_contract');
  assert.throws(() => assertInterfaceCoverage({root, modules: [module], declarations: changed}),
    /Unregistered interface operation/u);
});

test('a new private Sheets decision cannot inherit an existing module contract', () => {
  const path = 'adapters/connectors/sheets/host/sheets-range-command.mjs';
  const text = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  const changed = jsModule(path, text + '\nfunction decideUnregisteredOutcome() { return "success"; }\n');
  const declared = structuredClone(declarations);
  declared.find(value => value.module === path).sha256 = changed.sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules: [changed], declarations: declared}),
    /Unregistered interface operation/u, 'the helper inventory, not a setup error, refuses the mutation');
});

test('compiler representation access in the original checked consumer fails its actual role boundary', () => {
  const path = 'adapters/connectors/sheets/site/sheets-owned-request.mjs';
  const text = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  const mutated = text.replace('return checked(result);',
    'return result.$tag === 1 ? result._0 : checked(result);');
  assert.notEqual(mutated, text, 'the actual checked consumer was mutated');
  const changed = jsModule(path, mutated);
  const declared = structuredClone(declarations);
  declared.find(value => value.module === path).sha256 = changed.sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules: [changed], declarations: declared}),
    /Compiler representation outside generated binding/u);
});

test('an old implementation or missing private operation contract is not accepted as current', () => {
  const actual = modules();
  const changed = structuredClone(declarations);
  changed[0].sha256 = '0'.repeat(64);
  assert.throws(() => assertInterfaceCoverage({root, modules: actual, declarations: changed}),
    /Unreviewed interface implementation/u);
  const missing = structuredClone(declarations);
  missing[0].contracts[0].operations.pop();
  assert.throws(() => assertInterfaceCoverage({root, modules: actual, declarations: missing}),
    /Missing operation contract/u);
});
