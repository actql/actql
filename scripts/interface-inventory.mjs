// Distribution coverage, not another execution or semantic contract.
// Resolve JavaScript with the packaging resolver and parse it with Acorn;
// never infer production scope from the directory in which a helper lives.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, relative, resolve} from 'node:path';
import {parse} from 'acorn';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';

export const interfaceRoles = Object.freeze([
  'common-semantics', 'connector-semantics', 'physical-io',
  'generated-binding', 'public-wire-codec', 'observation-presentation',
]);
export const interfaceAttributes = Object.freeze([
  'responsibility', 'inputsOutputs', 'identity', 'ownership',
  'synchronization', 'failure', 'cancellation', 'resources',
  'extension', 'verification',
]);
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const inside = path => !isAbsolute(path) && path !== '..' && !path.startsWith('../');
const ordered = values => [...new Set(values)].sort();

function names(pattern) {
  if (!pattern) return [];
  if (pattern.type === 'Identifier') return [pattern.name];
  if (pattern.type === 'RestElement') return names(pattern.argument);
  if (pattern.type === 'AssignmentPattern') return names(pattern.left);
  if (pattern.type === 'ArrayPattern') return pattern.elements.flatMap(names);
  if (pattern.type === 'ObjectPattern') return pattern.properties.flatMap(property =>
    names(property.type === 'RestElement' ? property.argument : property.value));
  return [];
}

// Private helpers are inventoried too: a new decision helper must not hide
// under an already classified file. Locations are diagnostic, not identity.
export function javascriptInterface(source) {
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module',
    allowHashBang: true, locations: true});
  const operations = [], exports = [], imports = [], compilerFields = [];
  function visit(node, scope = []) {
    if (!node || typeof node !== 'object') return;
    let childScope = scope;
    if (/^(?:FunctionDeclaration|FunctionExpression|ArrowFunctionExpression)$/u.test(node.type)) {
      const name = node.id?.name ?? scope.at(-1) ?? '<anonymous>';
      const path = [...scope, name].join('/');
      operations.push({name: path, parameters: node.params.flatMap(names), async: node.async});
      childScope = [...scope, name];
    }
    if (node.type === 'ImportDeclaration' || node.type === 'ExportAllDeclaration' ||
        node.type === 'ExportNamedDeclaration' && node.source) imports.push(node.source.value);
    if (node.type === 'ImportExpression' && node.source.type === 'Literal') imports.push(node.source.value);
    if (node.type === 'ExportDefaultDeclaration') exports.push('default');
    if (node.type === 'ExportAllDeclaration') exports.push(`*:${node.source.value}`);
    if (node.type === 'ExportNamedDeclaration') {
      exports.push(...node.specifiers.map(value => value.exported.name ?? value.exported.value));
      if (node.declaration?.id) exports.push(node.declaration.id.name);
      if (node.declaration?.declarations) exports.push(...node.declaration.declarations.flatMap(value => names(value.id)));
    }
    const key = node.type === 'MemberExpression'
      ? node.computed ? node.property.type === 'Literal' ? node.property.value : undefined : node.property.name
      : node.type === 'Property' && !node.computed ? node.key.name ?? node.key.value : undefined;
    if (typeof key === 'string' && /^(?:\$tag|_\d+)$/u.test(key)) compilerFields.push(key);
    for (const [key, child] of Object.entries(node)) {
      if (['loc', 'start', 'end'].includes(key)) continue;
      const binding = node.type === 'VariableDeclarator' && key === 'init' && node.id.type === 'Identifier'
        ? [...childScope, node.id.name] : childScope;
      if (Array.isArray(child)) child.forEach(value => visit(value, binding));
      else if (child && typeof child === 'object') visit(child, binding);
    }
  }
  visit(tree);
  return {exports: ordered(exports), operations: operations.sort((a, b) => a.name.localeCompare(b.name)),
    imports: ordered(imports), compilerFields: ordered(compilerFields)};
}

export function javascriptClosure(root, entries) {
  const base = realpathSync(root);
  return localModuleGraphInputs(base, entries).map(path => {
    const absolute = realpathSync(resolve(base, path));
    const module = relative(base, absolute).split('\\').join('/');
    assert(inside(module), `Interface source escapes distribution: ${module}`);
    assert(!isConnectorTestFixture(module) && !/(?:\.test|_test|_wbtest|_bbtest)\.[^/]+$/u.test(module),
      `Test authority in distributed interface: ${module}`);
    const bytes = readFileSync(absolute);
    return {module, sha256: digest(bytes), ...javascriptInterface(bytes.toString('utf8'))};
  });
}

// Callers supply the actual normal package metadata, not a second package list.
// The all-condition export targets and bins remain visible even if a consumer
// happens to exercise only one condition. Types are checked by their own owner.
export function packageEntrances(manifest, directory = '.') {
  function targets(value) {
    return typeof value === 'string' ? [value] : value && typeof value === 'object'
      ? Object.values(value).flatMap(targets) : [];
  }
  return ordered([...targets(manifest.exports), ...targets(manifest.bin),
    ...targets(manifest.main), ...targets(manifest.types)]).map(path => {
    assert(inside(path), `Nonlocal distribution entrance: ${path}`);
    return resolve(directory, path);
  }).sort();
}

function reference(root, ref) {
  assert(ref && Object.keys(ref).sort().join() === 'anchor,path', 'Invalid interface reference');
  assert(typeof ref.path === 'string' && inside(ref.path) && typeof ref.anchor === 'string' && ref.anchor.length,
    'Invalid interface reference');
  const path = realpathSync(resolve(root, ref.path));
  assert(inside(relative(realpathSync(root), path)), 'Interface reference escapes owner');
  assert(readFileSync(path, 'utf8').includes(ref.anchor), `Missing interface reference: ${ref.path}#${ref.anchor}`);
}

export function assertInterfaceCoverage({root, modules, declarations, generated = []}) {
  const byModule = new Map();
  for (const declaration of declarations) {
    assert(!byModule.has(declaration.module), `Duplicate interface classification: ${declaration.module}`);
    assert(interfaceRoles.includes(declaration.role), `Unknown interface role: ${declaration.module}`);
    assert(typeof declaration.owner === 'string' && declaration.owner.length, 'Missing interface owner');
    assert.deepEqual(Object.keys(declaration.attributes).sort(), [...interfaceAttributes].sort(),
      `Incomplete interface attributes: ${declaration.module}`);
    for (const [name, value] of Object.entries(declaration.attributes)) {
      if (Array.isArray(value)) {
        assert(value.length, `Empty interface attribute: ${declaration.module}:${name}`);
        value.forEach(ref => reference(root, ref));
      } else assert(value && Object.keys(value).join() === 'notApplicable' &&
        typeof value.notApplicable === 'string' && value.notApplicable.trim().length > 0,
      `Unexplained interface attribute: ${declaration.module}:${name}`);
    }
    byModule.set(declaration.module, declaration);
  }
  for (const module of modules) {
    const declaration = byModule.get(module.module);
    assert(declaration, `Unregistered distributed interface: ${module.module}`);
    assert.deepEqual(declaration.exports, module.exports, `Unregistered interface export: ${module.module}`);
    assert.deepEqual(declaration.operations, module.operations,
      `Unregistered interface operation: ${module.module}`);
    if (module.compilerFields?.length) {
      assert.equal(declaration.role, 'generated-binding', `Compiler representation outside generated binding: ${module.module}`);
      const proof = generated.find(value => value.module === module.module);
      assert(proof && proof.sha256 === module.sha256,
        `Unverified generated binding: ${module.module}`);
      // The generator owner supplies a verified output digest, never a comment
      // or filename suffix. Its actual read-only freshness test is mandatory.
      reference(root, proof.generator);
      reference(root, proof.freshness);
    }
  }
  return modules.length;
}
