import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {encode} from '../bounded-session/action-inputs.mjs';

export const catalogPath = 'proofs/ci-evidence/bounded-session-actions.json';
// The published initial inventory is an independent bootstrap requirement.
// Candidate edits cannot delete/relabel it before a protected policy update.
export const initialRegistrationRevision = 'c35c28021531c8445c95a45ffcfcc1760d02e819';
export const version = 'actql-verification-action-catalog/0.1';
const fields = ['id', 'kind', 'target', 'command', 'package', 'minimumUnits', 'profile', 'premises', 'dependencies'];
const exact = (value, keys) => assert.deepEqual(Object.keys(value ?? {}).sort(), [...keys].sort(), 'Unknown/missing catalog field');
const name = value => typeof value === 'string' && /^[a-z][a-z0-9-]*$/u.test(value);

export function validateCatalog(catalog) {
  exact(catalog, ['version', 'family', 'actions']);
  assert.equal(catalog.version, version);
  assert.equal(catalog.family, 'bounded-session');
  assert(Array.isArray(catalog.actions) && catalog.actions.length > 0);
  const byId = new Map();
  for (const action of catalog.actions) {
    exact(action, fields);
    assert(name(action.id) && !byId.has(action.id), 'Invalid/duplicate action');
    assert(['formal-model', 'tested-refinement'].includes(action.kind));
    assert(['model', 'js', 'wasm', 'native'].includes(action.target));
    assert.equal(action.kind === 'formal-model', action.target === 'model');
    assert(Number.isSafeInteger(action.minimumUnits) && action.minimumUnits > 0);
    assert(typeof action.profile === 'string' && action.profile.length > 0);
    for (const field of ['premises', 'dependencies', 'command']) {
      assert(Array.isArray(action[field]) && action[field].every(value => typeof value === 'string' && value.length > 0));
    }
    assert(action.premises.length && new Set(action.dependencies).size === action.dependencies.length);
    if (action.command[0] === 'moon') {
      assert(/^src\/[a-z0-9_/]+$/u.test(action.package ?? ''), 'Invalid package');
      const [executor, verb, selection, targetFlag, target, warnings, ...rest] = action.command;
      assert.equal(executor, 'moon'); assert.equal(verb, 'test');
      assert.equal(targetFlag, '--target'); assert.equal(target, action.target); assert.equal(warnings, '--deny-warn');
      assert(selection === action.package || selection.startsWith(`${action.package}/`) && /^[a-z0-9_]+\.mbt$/u.test(selection.slice(action.package.length + 1)));
      assert(rest.length === 0 || rest.length === 2 && rest[0] === '--filter' && rest[1].length > 0);
    } else {
      assert.equal(action.package, null);
      assert(['model', 'mutations-js'].includes(action.id), 'Unreviewed Node executor');
      assert.equal(encode(action.command), encode(['node', `proofs/bounded-session/${action.id === 'model' ? 'check' : 'mutations'}.mjs`]));
    }
    byId.set(action.id, action);
  }
  const visited = new Set(), active = new Set();
  function visit(id) {
    assert(byId.has(id), `Missing action dependency: ${id}`);
    assert(!active.has(id), `Cyclic action dependency: ${id}`);
    if (visited.has(id)) return;
    active.add(id);
    byId.get(id).dependencies.forEach(visit);
    active.delete(id); visited.add(id);
  }
  byId.forEach((_, id) => visit(id));
  return catalog;
}

export function readCatalog(path = new URL('bounded-session-actions.json', import.meta.url)) {
  return validateCatalog(JSON.parse(readFileSync(path, 'utf8')));
}

export function requiredActions(catalog = readCatalog()) {
  return validateCatalog(catalog).actions.map(action => structuredClone(action));
}

// Keep the protected inventory separate from a candidate's own labels. The
// current adoption has no retirement mechanism; dropping an old obligation is
// rejected rather than interpreting its absence as not-applicable.
export function compareCatalogs(protectedCatalog, candidateCatalog) {
  validateCatalog(protectedCatalog); validateCatalog(candidateCatalog);
  const current = new Map(candidateCatalog.actions.map(action => [action.id, action]));
  for (const action of protectedCatalog.actions) assert(current.has(action.id), `Removed required action: ${action.id}`);
  return {
    unchanged: encode(protectedCatalog) === encode(candidateCatalog),
    required: candidateCatalog.actions.map(action => action.id),
    changed: candidateCatalog.actions.filter(action => {
      const original = protectedCatalog.actions.find(entry => entry.id === action.id);
      return !original || encode(original) !== encode(action);
    }).map(action => action.id),
  };
}

// Additive local obligations are permitted. Published requirements cannot be
// deleted or weakened merely by editing the candidate's registration labels.
export function preserveProtectedActions(protectedCatalog, candidateCatalog) {
  const comparison = compareCatalogs(protectedCatalog, candidateCatalog);
  for (const original of protectedCatalog.actions) {
    assert.equal(encode(candidateCatalog.actions.find(action => action.id === original.id)), encode(original),
      'Changed protected registration requires a reviewed policy update');
  }
  return comparison;
}
