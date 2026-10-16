import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {sourceInterfaceClosure} from './source-interface-closure.mjs';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {generateUpdateTargetDataCodec} from './generate-update-target-data-codec.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const paths = [
  'adapters/host-node/update-target-original-shape.mjs',
  'adapters/host-node/update-target-data.generated.mjs',
  'adapters/host-node/installed-update-originals.mjs',
  'adapters/host-node/installed-row-effect.mjs',
  'adapters/host-node/effect-run-recovery.mjs',
  'adapters/host-node/client-request-journal.mjs',
  'adapters/host-node/embedded-local.mjs',
  'adapters/connectors/salesforce/host/installed-salesforce-effect.mjs',
];
const source = await sourceInterfaceClosure(root, {distributionRoots:
  npmInterfaceRoots(root).filter(value => value.name === '@actql/local-node')});
const modules = () => paths.map(path => {
  const actual = source.modules.find(value => value.module === path);
  assert(actual, `Missing original UPDATE source: ${path}`);
  return structuredClone(actual);
});
// This focused test selects only the R3 change boundary. The ordinary checker
// continues to validate every declaration in the full distribution closure.
const owners = () => interfaceOwnerDeclarations(root).map(owner => ({...owner,
  declarations: owner.declarations.filter(value => paths.includes(value.module))}));
const check = (actual, declarations) => interfaceOwnerCoverage({root, modules: actual,
  owners: declarations, generated: [], requireComplete: true});

test('UPDATE selection references retain complete original functional and supplemental facets', () => {
  const result = check(modules(), owners());
  assert.equal(result.modules, paths.length);
  assert.equal(result.primaryCovered, paths.length);
  assert(result.complete && result.primaryComplete);
});

test('UPDATE selection source changes and missing operations are rejected by the actual reference boundary', () => {
  const actual = modules();
  assert.throws(() => check([{...actual[0], sha256: '0'.repeat(64)}, ...actual.slice(1)], owners()),
    /Unreviewed interface implementation/);
  const declarations = owners();
  const target = declarations.flatMap(owner => owner.declarations).find(value => value.module === paths[0]);
  target.operations.pop();
  assert.throws(() => check(actual, declarations), /Unregistered interface operation/);
});

test('UPDATE selection supplemental representation cannot replace a deleted functional primary', () => {
  const declarations = owners();
  for (const owner of declarations) owner.declarations = owner.declarations.filter(value =>
    value.module !== paths[3] || value.responsibilityFacet !== 'primary');
  assert.throws(() => check(modules(), declarations), /Missing primary interface responsibilities/);
});

test('UPDATE bounded DATA codec has ordinary freshness without compiler-binding privilege', () => {
  generateUpdateTargetDataCodec(root);
  const declarations = owners().flatMap(owner => owner.declarations).filter(value => value.module === paths[1]);
  assert(declarations.length);
  assert(declarations.every(value => value.role === 'physical-io'));
  assert.equal(modules().find(value => value.module === paths[1]).compilerFields.length, 0);
});
