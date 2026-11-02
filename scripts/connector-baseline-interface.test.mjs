// Existing Reader checks only: product adapters, native drivers, credentials,
// Catalogs and provider transports are never imported by this test.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import test from 'node:test';
import {assertInterfaceCoverage, javascriptInterface} from './interface-inventory.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {sourceInterfaceClosure} from './source-interface-closure.mjs';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';
import {pythonModuleInterfaces, pythonSourceBlobInterfaces} from './python-interface-sources.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const sidecar = 'scripts/interface-owners/connector-baseline/interface-boundaries.json';
const index = JSON.parse(readFileSync(new URL(sidecar, `file://${root}`), 'utf8'));
const {declarations} = index;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const read = module => readFileSync(new URL(module, `file://${root}`), 'utf8');
// Resolve runtime imports through the normal builder's actual finite inputs.
// A changed reference cannot inherit another module's original resolution.
const sourceClosure = await sourceInterfaceClosure(root, {distributionRoots:
  npmInterfaceRoots(root).filter(value => value.name === '@actql/local-node')});
const jsModule = (module, text = read(module)) => ({module, sha256: digest(text),
  ...javascriptInterface(text, {resolveRuntimeImport(reference) {
    return sourceClosure.runtimeBindings.find(value => value.module === module &&
      isDeepStrictEqual(value.reference, reference))?.targets;
  }})});
const python = process.env.ACTQL_INTERFACE_PYTHON ?? 'python3.12';
let projection;
function modules() {
  return projection ??= [
    ...declarations.filter(value => value.module.endsWith('.mjs')).map(value => jsModule(value.module)),
    ...pythonModuleInterfaces(root, declarations.filter(value => value.module.endsWith('.py'))
      .map(value => value.module), python),
  ];
}

test('the exact 53-module intake has current hashes and ten-attribute contracts for every operation and export', () => {
  const actual = modules();
  assert.equal(actual.length, 53);
  assert.equal(actual.filter(value => value.module.endsWith('.mjs')).length, 51);
  assert.equal(actual.filter(value => value.module.endsWith('.py')).length, 2);
  assert.equal(assertInterfaceCoverage({root, modules: actual, declarations}), 53);
  for (const module of actual.filter(value => value.module.endsWith('.mjs'))) {
    assert.deepEqual(module.compilerFields, [], module.module);
  }
});

test('standard owner discovery and aggregate intake preserve this facet alongside the existing Sheets and data facets', () => {
  const owners = interfaceOwnerDeclarations(root, [sidecar,
    'src/connectors/sheets/interface-boundaries.json',
    'src/connectors/local/data-interface-boundaries.json']);
  assert.equal(owners.length, 3);
  assert.equal(owners.find(value => value.id === sidecar).declarations.length, 53);
  assert.equal(owners.find(value => value.id.includes('/sheets/')).declarations.length, 25);
  assert.equal(owners.find(value => value.id.includes('/local/')).declarations.length, 3);
  const result = interfaceOwnerCoverage({root, modules: modules(), owners});
  assert.equal(result.complete, true);
  assert.equal(result.covered, 53);
  assert.deepEqual(result.missing, []);
  assert.match(result.qualification, /not-semantic-or-artifact-admission/u);
});

test('new private Connector decisions do not inherit module or directory approval', () => {
  const module = 'adapters/connectors/gcs/site/gcs-keyed-content.mjs';
  const mutated = jsModule(module, read(module) +
    '\nfunction inferUnknownAsUnsent() { return "unsent"; }\n');
  const freshDigest = structuredClone(declarations);
  freshDigest.find(value => value.module === module).sha256 = mutated.sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules: [mutated], declarations: freshDigest}),
    /Unregistered interface operation/u);
  assert.throws(() => assertInterfaceCoverage({root,
    modules: [{...mutated, module: 'adapters/connectors/gcs/site/unreviewed.mjs'}], declarations}),
  /Unregistered distributed interface/u);
});

test('a real Python AST addition cannot inherit the existing Catalog custody contract', () => {
  const module = 'adapters/connectors/local/iceberg/custody.py';
  const [mutated] = pythonSourceBlobInterfaces([{module, source: read(module) +
    '\n\ndef infer_unknown_as_noncommit():\n    return True\n'}], python);
  assert(mutated.operations.some(value => value.name === 'infer_unknown_as_noncommit'));
  const freshExport = structuredClone(declarations);
  const declaration = freshExport.find(value => value.module === module);
  declaration.sha256 = mutated.sha256;
  declaration.exports = mutated.exports;
  declaration.contracts[0].exports = mutated.exports;
  assert.throws(() => assertInterfaceCoverage({root, modules: [mutated], declarations: freshExport}),
    /Unregistered interface operation/u);
});

test('complete operation registration cannot hide compiler fields inside a physical adapter role', () => {
  const module = 'adapters/connectors/gcs/site/gcs-keyed-content.mjs';
  const mutated = jsModule(module, read(module) +
    '\nfunction leakedCompilerRepresentation(value) { return value.$tag; }\n');
  assert.deepEqual(mutated.compilerFields, ['$tag']);
  const declared = structuredClone(declarations);
  const declaration = declared.find(value => value.module === module);
  declaration.sha256 = mutated.sha256;
  declaration.operations = mutated.operations;
  declaration.contracts[0].operations.push('leakedCompilerRepresentation');
  assert.throws(() => assertInterfaceCoverage({root, modules: [mutated], declarations: declared}),
    /Compiler representation outside generated binding/u);
});

test('missing operation contracts and stale implementation hashes are rejected independently', () => {
  const missing = structuredClone(declarations);
  missing[0].contracts[0].operations.pop();
  assert.throws(() => assertInterfaceCoverage({root, modules: modules(), declarations: missing}),
    /Missing operation contract/u);
  const stale = structuredClone(declarations);
  stale[0].sha256 = '0'.repeat(64);
  assert.throws(() => assertInterfaceCoverage({root, modules: modules(), declarations: stale}),
    /Unreviewed interface implementation/u);
});

test('an invented attribute anchor cannot replace an existing Owner contract or executable reference', () => {
  const changed = structuredClone(declarations);
  changed[0].contracts[0].attributes.identity[0].anchor = 'invented-current-authority-from-identical-bytes';
  assert.throws(() => assertInterfaceCoverage({root, modules: modules(), declarations: changed}),
    /Missing interface reference/u);
});
