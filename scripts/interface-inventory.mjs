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
// Only closed literal syntax is folded. No product expression, getter, or
// callback is evaluated by the inventory.
function literalValue(node, depth = 0) {
  if (!node || depth > 8) return undefined;
  if (node.type === 'Literal' && ['string', 'number', 'boolean'].includes(typeof node.value)) return node.value;
  if (node.type === 'BinaryExpression' && node.operator === '+') {
    const left = literalValue(node.left, depth + 1), right = literalValue(node.right, depth + 1);
    if (left !== undefined && right !== undefined) {
      const value = left + right;
      return typeof value === 'string' && value.length > 128 ? undefined : value;
    }
  }
  if (node.type === 'TemplateLiteral') {
    let value = node.quasis[0].value.cooked;
    for (let index = 0; index < node.expressions.length; index++) {
      const part = literalValue(node.expressions[index], depth + 1);
      if (part === undefined) return undefined;
      value += String(part) + node.quasis[index + 1].value.cooked;
      if (value.length > 128) return undefined;
    }
    return value;
  }
}
const propertyName = node => node?.type === 'MemberExpression'
  ? node.computed ? literalValue(node.property) : node.property.name : undefined;
const compilerField = node => {
  const value = literalValue(node);
  if (value !== undefined) return typeof value === 'string' && /^(?:\$tag|_\d+)$/u.test(value) ? value : undefined;
  if (node?.type === 'TemplateLiteral' && node.expressions.length &&
      node.quasis[0].value.cooked === '_' && node.quasis.at(-1).value.cooked === '') return '_<dynamic>';
  if (node?.type === 'BinaryExpression' && node.operator === '+' && literalValue(node.left) === '_') return '_<dynamic>';
};
const exportsObject = node => node?.type === 'Identifier' && node.name === 'exports' ||
  node?.type === 'MemberExpression' && node.object.name === 'module' && propertyName(node) === 'exports';

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
  const operations = [], exports = [], imports = [], compilerFields = [], unresolvedSyntax = [], occurrences = new Map();
  function commonJsMembers(value) {
    if (value?.type === 'CallExpression' && value.callee.type === 'MemberExpression' &&
        value.callee.object.name === 'Object' && propertyName(value.callee) === 'freeze') value = value.arguments[0];
    if (value?.type !== 'ObjectExpression') {
      unresolvedSyntax.push('dynamic CommonJS export value');
      return;
    }
    for (const property of value.properties) {
      const key = property.computed ? property.key.type === 'Literal' ? property.key.value : undefined
        : property.key?.name ?? property.key?.value;
      if (typeof key === 'string') exports.push(`commonjs:${key}`);
      else unresolvedSyntax.push('dynamic CommonJS export member');
    }
  }
  function visit(node, scope = []) {
    if (!node || typeof node !== 'object') return;
    let childScope = scope;
    if (node.type === 'ClassDeclaration' || node.type === 'ClassExpression') {
      childScope = [...scope, node.id?.name ?? '<class>'];
    }
    if (node.type === 'MethodDefinition' || node.type === 'Property' && node.method) {
      const key = node.computed ? node.key.value : node.key.name ?? node.key.value;
      childScope = [...scope, `${node.static ? 'static ' : ''}${node.kind ?? 'method'}:${key ?? '<computed>'}`];
    }
    if (/^(?:FunctionDeclaration|FunctionExpression|ArrowFunctionExpression)$/u.test(node.type)) {
      const name = node.id?.name ?? scope.at(-1) ?? '<anonymous>';
      const base = [...scope, name].join('/'), occurrence = (occurrences.get(base) ?? 0) + 1;
      occurrences.set(base, occurrence);
      const path = occurrence === 1 ? base : `${base}#${occurrence}`;
      operations.push({name: path, parameters: node.params.flatMap(names), async: node.async});
      childScope = [...scope, name];
    }
    if (node.type === 'ImportDeclaration' || node.type === 'ExportAllDeclaration' ||
        node.type === 'ExportNamedDeclaration' && node.source) imports.push(node.source.value);
    if (node.type === 'ImportExpression' || node.type === 'CallExpression' &&
        node.callee.type === 'Identifier' && node.callee.name === 'require') {
      const target = literalValue(node.type === 'ImportExpression' ? node.source : node.arguments[0]);
      if (typeof target === 'string') imports.push(target);
      else unresolvedSyntax.push('runtime-dependent module dependency requires original owner/artifact mapping');
    }
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.name === 'Reflect' && propertyName(node.callee) === 'get' &&
        compilerField(node.arguments[1])) compilerFields.push(compilerField(node.arguments[1]));
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        ['Object', 'Reflect'].includes(node.callee.object.name) &&
        ['getOwnPropertyDescriptor', 'defineProperty', 'set'].includes(propertyName(node.callee)) &&
        compilerField(node.arguments[1])) compilerFields.push(compilerField(node.arguments[1]));
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.name === 'Object' && propertyName(node.callee) === 'assign' &&
        exportsObject(node.arguments[0])) node.arguments.slice(1).forEach(commonJsMembers);
    if (node.type === 'AssignmentExpression' && node.left.type === 'MemberExpression') {
      const target = node.left;
      if (exportsObject(target.object)) {
        const name = propertyName(target);
        if (typeof name === 'string') exports.push(`commonjs:${name}`);
        else unresolvedSyntax.push('dynamic CommonJS export assignment');
      }
      if (exportsObject(target)) commonJsMembers(node.right);
    }
    if (node.type === 'ExportDefaultDeclaration') exports.push('default');
    if (node.type === 'ExportAllDeclaration') exports.push(node.exported
      ? `${node.exported.name ?? node.exported.value}=*:${node.source.value}` : `*:${node.source.value}`);
    if (node.type === 'ExportNamedDeclaration') {
      exports.push(...node.specifiers.map(value => value.exported.name ?? value.exported.value));
      if (node.declaration?.id) exports.push(node.declaration.id.name);
      if (node.declaration?.declarations) exports.push(...node.declaration.declarations.flatMap(value => names(value.id)));
    }
    const key = node.type === 'MemberExpression'
      ? node.computed ? compilerField(node.property) ?? literalValue(node.property) : node.property.name
      : node.type === 'Property' ? node.computed
        ? compilerField(node.key) ?? literalValue(node.key) : node.key.name ?? node.key.value : undefined;
    if (typeof key === 'string' && /^(?:\$tag|_\d+|_<dynamic>)$/u.test(key)) compilerFields.push(key);
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
    imports: ordered(imports), compilerFields: ordered(compilerFields), unresolvedSyntax: ordered(unresolvedSyntax)};
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
  const base = resolve(directory);
  return ordered([...targets(manifest.exports), ...targets(manifest.imports), ...targets(manifest.bin),
    ...targets(manifest.main), ...targets(manifest.types)]).map(path => {
    const target = resolve(base, path);
    assert(inside(relative(base, target)), `Nonlocal distribution entrance: ${path}`);
    return target;
  }).sort();
}

function reference(root, ref, readReference) {
  assert(ref && Object.keys(ref).sort().join() === 'anchor,path', 'Invalid interface reference');
  assert(typeof ref.path === 'string' && inside(ref.path) && typeof ref.anchor === 'string' && ref.anchor.length,
    'Invalid interface reference');
  assert(!ref.path.split('/').includes('..'), 'Invalid interface reference traversal');
  if (readReference) {
    assert(readReference(ref.path).includes(ref.anchor), `Missing interface reference: ${ref.path}#${ref.anchor}`);
    return;
  }
  const path = realpathSync(resolve(root, ref.path));
  assert(inside(relative(realpathSync(root), path)), 'Interface reference escapes owner');
  assert(readFileSync(path, 'utf8').includes(ref.anchor), `Missing interface reference: ${ref.path}#${ref.anchor}`);
}

export function assertInterfaceCoverage({root, modules, declarations, generated = [], readReference}) {
  const references = new Map();
  const read = path => {
    if (!references.has(path)) references.set(path, readReference
      ? readReference(path) : (() => {
        const actual = realpathSync(resolve(root, path));
        assert(inside(relative(realpathSync(root), actual)), 'Interface reference escapes owner');
        return readFileSync(actual, 'utf8');
      })());
    return references.get(path);
  };
  const byModule = new Map();
  for (const declaration of declarations) {
    assert(!byModule.has(declaration.module), `Duplicate interface classification: ${declaration.module}`);
    assert(interfaceRoles.includes(declaration.role), `Unknown interface role: ${declaration.module}`);
    assert(typeof declaration.owner === 'string' && declaration.owner.length, 'Missing interface owner');
    assert(Array.isArray(declaration.contracts) && declaration.contracts.length,
      `Missing operation contracts: ${declaration.module}`);
    for (const contract of declaration.contracts) {
      assert(Array.isArray(contract.operations) && Array.isArray(contract.exports), 'Invalid operation contract');
      assert.deepEqual(Object.keys(contract.attributes).sort(), [...interfaceAttributes].sort(),
        `Incomplete interface attributes: ${declaration.module}`);
      for (const [name, value] of Object.entries(contract.attributes)) {
      if (Array.isArray(value)) {
        assert(value.length, `Empty interface attribute: ${declaration.module}:${name}`);
        value.forEach(ref => reference(root, ref, read));
      } else assert(value && Object.keys(value).join() === 'notApplicable' &&
        typeof value.notApplicable === 'string' && value.notApplicable.trim().length > 0,
      `Unexplained interface attribute: ${declaration.module}:${name}`);
      }
    }
    byModule.set(declaration.module, declaration);
  }
  for (const module of modules) {
    const declaration = byModule.get(module.module);
    assert(!module.unresolvedSyntax?.length, `Unresolved interface syntax: ${module.module}`);
    assert(declaration, `Unregistered distributed interface: ${module.module}`);
    assert.equal(declaration.sha256, module.sha256,
      `Unreviewed interface implementation: ${module.module}`);
    assert.deepEqual(declaration.exports, module.exports, `Unregistered interface export: ${module.module}`);
    assert.deepEqual(declaration.operations, module.operations,
      `Unregistered interface operation: ${module.module}`);
    for (const [field, actual] of [['operations', ['<module>', ...module.operations.map(value => value.name)]],
      ['exports', module.exports]]) {
      const covered = declaration.contracts.flatMap(value => value[field]);
      assert.equal(new Set(covered).size, covered.length, `Duplicate operation contract: ${module.module}`);
      assert.deepEqual(covered.sort(), [...actual].sort(), `Missing operation contract: ${module.module}:${field}`);
    }
    if (module.compilerFields?.length) {
      assert.equal(declaration.role, 'generated-binding', `Compiler representation outside generated binding: ${module.module}`);
      const proof = generated.find(value => value.module === module.module);
      assert(proof && proof.sha256 === module.sha256,
        `Unverified generated binding: ${module.module}`);
      // The generator owner supplies a verified output digest, never a comment
      // or filename suffix. Its actual read-only freshness test is mandatory.
      reference(root, proof.generator, read);
      reference(root, proof.freshness, read);
    }
  }
  return modules.length;
}
