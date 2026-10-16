// Independent existing owners can describe different obligations in the same
// authored module. Validate each facet; never concatenate duplicate module
// registrations or replace functional contracts with representation references.
import assert from 'node:assert/strict';
import {assertInterfaceCoverage} from './interface-inventory.mjs';
import {trustedCompilerBindingOutputs} from './interface-generation-freshness.mjs';

export function replaceInterfaceDeclarations(base, overlay) {
  const values = new Map();
  for (const [name, declarations] of [['base', base], ['overlay', overlay]]) {
    const seen = new Set();
    for (const declaration of declarations) {
      assert(!seen.has(declaration.module), `Duplicate ${name} interface declaration: ${declaration.module}`);
      seen.add(declaration.module);
      values.set(declaration.module, declaration);
    }
  }
  return [...values.values()].sort((a, b) => a.module.localeCompare(b.module));
}

export function interfaceOwnerCoverage({root, modules, owners, requireComplete = true, generated}) {
  const actual = new Map(), covered = new Set(), primary = new Set(), ids = new Set(), facets = [];
  const checkedGenerated = trustedCompilerBindingOutputs(root, generated);
  for (const module of modules) {
    const previous = actual.get(module.module);
    if (previous) assert.deepEqual(previous, module, `Conflicting actual interface: ${module.module}`);
    actual.set(module.module, module);
  }
  for (const owner of owners) {
    assert(typeof owner.id === 'string' && owner.id.length && !ids.has(owner.id), 'Duplicate or missing interface owner facet');
    ids.add(owner.id);
    // The original declaration validator checks duplicates, all ten attribute
    // references and exact operation/export coverage inside each owner facet.
    const selected = owner.declarations.filter(value => actual.has(value.module));
    for (const declaration of selected) {
      assert(['primary', 'supplemental'].includes(declaration.responsibilityFacet),
        `Unclassified interface responsibility facet: ${declaration.module}`);
      if (declaration.responsibilityFacet === 'primary') primary.add(declaration.module);
    }
    const selectedModules = selected.map(value => actual.get(value.module));
    assertInterfaceCoverage({root, modules: selectedModules, declarations: owner.declarations,
      generated: checkedGenerated, readReference: owner.readReference});
    selected.forEach(value => covered.add(value.module));
    facets.push({owner: owner.id, modules: selected.length,
      primary: selected.filter(value => value.responsibilityFacet === 'primary').length,
      qualification: owner.qualification ?? 'owner-reference-coverage-only'});
  }
  const missing = [...actual.keys()].filter(name => !covered.has(name)).sort();
  const missingPrimary = [...actual.keys()].filter(name => covered.has(name) && !primary.has(name)).sort();
  if (requireComplete) assert.equal(missing.length, 0, `Unregistered distributed interfaces: ${missing.join(', ')}`);
  if (requireComplete) assert.equal(missingPrimary.length, 0,
    `Missing primary interface responsibilities: ${missingPrimary.join(', ')}`);
  return {qualification: 'owner-reference-coverage-only; not-semantic-or-artifact-admission',
    complete: missing.length === 0, primaryComplete: missingPrimary.length === 0, modules: actual.size,
    covered: covered.size, primaryCovered: primary.size, missing, missingPrimary, facets};
}
