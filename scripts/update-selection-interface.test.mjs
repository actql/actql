import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {javascriptInterface} from './interface-inventory.mjs';
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
const modules = () => paths.map(module => {
  const bytes = readFileSync(new URL(`../${module}`, import.meta.url));
  return {module, sha256: createHash('sha256').update(bytes).digest('hex'),
    ...javascriptInterface(bytes.toString('utf8'))};
});
const owners = () => interfaceOwnerDeclarations(root);
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
