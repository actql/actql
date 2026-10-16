import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {interfaceOwnerCoverage, replaceInterfaceDeclarations} from './interface-owner-coverage.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-interface-owner-'));
  t.after(() => rmSync(root, {recursive: true}));
  writeFileSync(join(root, 'owner.md'), 'Original functional boundary and original representation binding');
  const source = 'export function read(value) {return value;}';
  const module = {module: 'outside/sdk.mjs', sha256: createHash('sha256').update(source).digest('hex'),
    ...javascriptInterface(source)};
  const declaration = (role, anchor) => ({...module, role, owner: anchor, responsibilityFacet: 'primary',
    contracts: [{operations: ['<module>', ...module.operations.map(value => value.name)], exports: module.exports,
      attributes: Object.fromEntries(interfaceAttributes.map(name => [name, [{path: 'owner.md', anchor}]]))}]});
  return {root, module, declaration};
}

test('functional and binding facets keep independent original references without duplicate module concatenation', t => {
  const {root, module, declaration} = fixture(t);
  const functional = declaration('physical-io', 'Original functional boundary');
  const binding = declaration('physical-io', 'original representation binding');
  binding.responsibilityFacet = 'supplemental';
  const owners = [{id: 'functional', declarations: [functional]}, {id: 'binding', declarations: [binding]}];
  const result = interfaceOwnerCoverage({root, modules: [module], owners});
  assert.equal(result.covered, 1);
  assert.equal(result.facets.length, 2);
  assert.equal(result.primaryCovered, 1);
  assert.equal(owners[0].declarations[0].contracts[0].attributes.failure[0].anchor, 'Original functional boundary');
});

test('deleting the complete primary facet cannot be covered by supplemental binding references', t => {
  const {root, module, declaration} = fixture(t);
  const binding = declaration('physical-io', 'original representation binding');
  binding.responsibilityFacet = 'supplemental';
  const owners = [{id: 'binding', declarations: [binding]}];
  assert.throws(() => interfaceOwnerCoverage({root, modules: [module], owners}),
    /Missing primary interface responsibilities/u);
  const diagnostic = interfaceOwnerCoverage({root, modules: [module], owners, requireComplete: false});
  assert.equal(diagnostic.covered, 1);
  assert.equal(diagnostic.complete, true, 'module union remains distinct from primary responsibilities');
  assert.equal(diagnostic.primaryComplete, false);
  assert.deepEqual(diagnostic.missingPrimary, [module.module]);
  delete binding.responsibilityFacet;
  assert.throws(() => interfaceOwnerCoverage({root, modules: [module], owners}),
    /Unclassified interface responsibility facet/u);
});

test('one fresh facet cannot hide a stale or missing operation in another owner facet', t => {
  const {root, module, declaration} = fixture(t);
  const good = declaration('physical-io', 'Original functional boundary');
  const stale = structuredClone(good);
  stale.sha256 = '0'.repeat(64);
  const check = () => interfaceOwnerCoverage({root, modules: [module], owners: [
    {id: 'current', declarations: [good]}, {id: 'stale', declarations: [stale]}]});
  assert.throws(check, /Unreviewed interface implementation/u);
  stale.sha256 = module.sha256;
  stale.contracts[0].operations.pop();
  assert.throws(check, /Missing operation contract/u);
});

test('partial owner intake reports missing modules but normal admission refuses them', t => {
  const {root, module, declaration} = fixture(t);
  const modules = [module, {...module, module: 'another/private-host.mjs'}];
  const owners = [{id: 'original', declarations: [declaration('physical-io', 'Original functional boundary')]}];
  const partial = interfaceOwnerCoverage({root, modules, owners, requireComplete: false});
  assert.equal(partial.complete, false);
  assert.deepEqual(partial.missing, ['another/private-host.mjs']);
  assert.throws(() => interfaceOwnerCoverage({root, modules, owners}), /Unregistered distributed interfaces/u);
});

test('explicit module replacement adds a new declaration and refuses duplicate overlay entries', t => {
  const {declaration} = fixture(t), original = declaration('physical-io', 'Original functional boundary');
  const child = {...original, sha256: '1'.repeat(64)}, added = {...original, module: 'new/module.mjs'};
  const merged = replaceInterfaceDeclarations([original], [child, added]);
  assert.equal(merged.length, 2);
  assert.equal(merged.find(value => value.module === original.module).sha256, child.sha256);
  assert.throws(() => replaceInterfaceDeclarations([original], [child, child]), /Duplicate overlay interface declaration/u);
});

test('an owner sidecar cannot self-approve a new raw compiler wrapper outside actual generator outputs', t => {
  const {root, declaration} = fixture(t);
  const source = 'export function read(value) {return value._0;}';
  const module = {module: 'new-wrapper.mjs', sha256: createHash('sha256').update(source).digest('hex'),
    ...javascriptInterface(source)};
  const declared = {...declaration('generated-binding', 'original representation binding'), ...module};
  const proof = {module: module.module, sha256: module.sha256,
    generator: {path: 'owner.md', anchor: 'original representation binding'},
    freshness: {path: 'owner.md', anchor: 'original representation binding'}};
  const owners = [{id: 'unverified-wrapper', declarations: [declared], generated: [proof]}];
  for (const option of [{}, {generated: undefined}, {generated: null}, {generated: []}]) {
    assert.throws(() => interfaceOwnerCoverage({root, modules: [module], owners, ...option}),
      /Unverified generated binding: new-wrapper.mjs/u);
  }
  for (const forged of [proof, {...proof, generator: {path: 'owner.md', anchor: 'Original functional boundary'}},
    {...proof, freshness: {path: 'owner.md', anchor: 'Original functional boundary'}}]) {
    assert.throws(() => interfaceOwnerCoverage({root, modules: [module], owners, generated: [forged]}),
      /Untrusted generated interface qualification/u);
  }
});
