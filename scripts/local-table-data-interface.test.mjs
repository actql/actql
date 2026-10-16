// Syntax coverage of shipped physical assets, separate from their real-library
// tests. The existing stdlib AST reader never imports Arrow or product modules.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {assertInterfaceCoverage, javascriptInterface} from './interface-inventory.mjs';
import {pythonModuleInterfaces} from './python-interface-sources.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const declarations = JSON.parse(readFileSync(new URL(
  '../src/connectors/local/data-interface-boundaries.json', import.meta.url)));
const manifest = JSON.parse(readFileSync(new URL('../src/connectors/local/host-bundle.json', import.meta.url)));

test('Local data interfaces cover real declared physical assets and the original managed-process port', () => {
  const python = declarations.filter(value => value.module.endsWith('.py')).map(value => value.module);
  for (const path of python) assert.ok(manifest.installation.assets.includes(path));
  const interfaces = pythonModuleInterfaces(root, python,
    process.env.ACTQL_INTERFACE_PYTHON ?? 'python3.12');
  const module = 'adapters/connectors/local/host/iceberg-process.mjs';
  const bytes = readFileSync(new URL(`../${module}`, import.meta.url));
  interfaces.push({module, sha256: createHash('sha256').update(bytes).digest('hex'),
    ...javascriptInterface(bytes.toString())});
  assert.equal(assertInterfaceCoverage({root, modules: interfaces, declarations}), 3);
  assert.equal(interfaces.flatMap(value => value.operations).length, 56);
});

test('a new physical Python decision or export cannot inherit an existing data boundary', () => {
  const path = 'adapters/connectors/local/iceberg/physical.py';
  const original = declarations.find(value => value.module === path);
  const module = {...original, operations: [...original.operations,
    {name: 'infer_unknown_as_unsent', parameters: ['value'], async: false}]};
  assert.throws(() => assertInterfaceCoverage({root, modules: [module], declarations}),
    /Unregistered interface operation/u);
  const exported = {...original, exports: [...original.exports, 'new_unchecked_writer']};
  assert.throws(() => assertInterfaceCoverage({root, modules: [exported], declarations}),
    /Unregistered interface export/u);
});
