// Syntax coverage of shipped physical assets, separate from their real-library
// tests. The existing stdlib AST reader never imports Arrow or product modules.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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
  assert.equal(interfaces.flatMap(value => value.operations).length, 58);
});

test('a new physical Python decision or export cannot inherit an existing data boundary', t => {
  const path = 'adapters/connectors/local/iceberg/physical.py';
  const original = declarations.find(value => value.module === path);
  const scratch = mkdtempSync(join(tmpdir(), 'actql-data-interface-source-'));
  t.after(() => rmSync(scratch, {recursive: true}));
  const source = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  writeFileSync(join(scratch, 'physical.py'), source +
    '\n\ndef infer_unknown_as_unsent(value):\n    return "unsent"\n', {flag: 'wx'});
  const [mutated] = pythonModuleInterfaces(scratch, ['physical.py'],
    process.env.ACTQL_INTERFACE_PYTHON ?? 'python3.12');
  const module = {...mutated, module: path};
  assert.ok(module.operations.some(value => value.name === 'infer_unknown_as_unsent'),
    'the real Python AST reader observes the added decision');
  // Qualify only the changed digest/exports, leaving the original operation
  // declaration unchanged so the intended missing-operation assertion fires.
  const fresh = structuredClone(declarations);
  const declared = fresh.find(value => value.module === path);
  declared.sha256 = module.sha256;
  declared.exports = module.exports;
  declared.contracts[0].exports = module.exports;
  assert.throws(() => assertInterfaceCoverage({root, modules: [module], declarations: fresh}),
    /Unregistered interface operation/u);
  assert.ok(module.exports.includes('infer_unknown_as_unsent'));
  const exportOnly = {...module, operations: original.operations};
  const staleExports = structuredClone(declarations);
  staleExports.find(value => value.module === path).sha256 = module.sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules: [exportOnly], declarations: staleExports}),
    /Unregistered interface export/u);
});
