// Distribution coverage, not another execution or semantic contract.
// Resolve JavaScript with the packaging resolver and parse it with Acorn;
// never infer production scope from the directory in which a helper lives.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, relative, resolve} from 'node:path';
import {parse} from 'acorn';
import type {AnyNode, Program, Property, CallExpression, VariableDeclarator} from 'acorn';
import type {BinaryLike} from 'node:crypto';
import ts from 'typescript';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';
import {hasExecutableTestCase} from './executable-test-cases.mjs';

// These structural views describe existing parser/projection DATA only.
// Original syntax, owner, reference and generated-byte checks remain authority.
type Callable = Extract<AnyNode, {type: 'FunctionDeclaration' | 'FunctionExpression' | 'ArrowFunctionExpression'}>;
type Mutation = Extract<AnyNode, {type: 'AssignmentExpression' | 'UpdateExpression' | 'UnaryExpression'}>;
type NamedSyntax = {readonly name?: string; readonly value?: unknown};
type ImportedBinding = {source: string; name?: string};
type Binding = {initializers: AnyNode[]; invalid?: boolean; function?: Callable; definition?: AnyNode;
  parameter?: {function: Callable; index: number; property?: string | number};
  projection?: {node: AnyNode; key: string | number}; imported?: ImportedBinding};
type Scope = {parent: Scope | undefined; functionScope: boolean; bindings: Map<string, Binding>};
type SyntaxOrigin = {kind: 'unresolved'} | {kind: 'value'; value: unknown}
  | ({kind: 'import'} & ImportedBinding) | {kind: 'runtime-parameter'; index: number; property?: string | number}
  | {kind: 'object'; properties: Record<string, SyntaxOrigin>} | {kind: 'array' | 'alternatives'; values: SyntaxOrigin[]}
  | {kind: 'spread'; value: SyntaxOrigin} | {kind: 'module-meta-url'}
  | ({kind: 'owner-call'; arguments: SyntaxOrigin[]} & ImportedBinding);
type RuntimeReference = {kind: 'literal' | 'module-url' | 'package-resolution'; specifier: string}
  | ({kind: 'owner-projection'; arguments: SyntaxOrigin[]} & ImportedBinding);
type Operation = {name: string; declaration?: unknown};
type ModuleInterface = {module: string; sha256?: string; exports: readonly string[]; operations: readonly Operation[];
  privateOperations?: readonly string[]; compilerFields?: readonly string[]; unresolvedSyntax?: readonly string[]};
type UncheckedReference = {path: unknown; anchor?: unknown; case_id?: unknown};
type UncheckedContract = {operations: unknown; exports: unknown; attributes: Record<string, unknown>};
type UncheckedDeclaration = {module: string; role: string; owner: unknown; exports: unknown;
  operations: readonly Operation[]; contracts: readonly UncheckedContract[]};
type GeneratedProof = {module: string; sha256: string; generator: UncheckedReference; freshness: UncheckedReference};
type ReadReference = (path: string) => string;
type UncheckedPackageManifest = {exports?: unknown; imports?: unknown; bin?: unknown; main?: unknown; types?: unknown};
type Literal = string | number | boolean | null;

export const interfaceRoles = Object.freeze([
  'common-semantics', 'connector-semantics', 'physical-io',
  'generated-binding', 'public-wire-codec', 'observation-presentation',
]);
export const interfaceAttributes = Object.freeze([
  'responsibility', 'inputsOutputs', 'identity', 'ownership',
  'synchronization', 'failure', 'cancellation', 'resources',
  'extension', 'verification',
]);
const digest = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');
const inside = (path: string) => !isAbsolute(path) && path !== '..' && !path.startsWith('../');
const ordered = <T,>(values: Iterable<T>) => [...new Set(values)].sort();
// Only closed literal syntax is folded. No product expression, getter, or
// callback is evaluated by the inventory.
function literalValue(node: AnyNode | null | undefined, depth = 0): Literal | undefined {
  if (!node || depth > 8) return undefined;
  if (node.type === 'Literal' && ['string', 'number', 'boolean'].includes(typeof node.value)) return node.value as Literal;
  if (node.type === 'BinaryExpression' && node.operator === '+') {
    const left = literalValue(node.left, depth + 1), right = literalValue(node.right, depth + 1);
    if (left !== undefined && right !== undefined) {
      // The operand views do not coerce JavaScript's mixed-primitive +.
      const value = (left as string) + (right as string);
      return typeof value === 'string' && value.length > 128 ? undefined : value;
    }
  }
  if (node.type === 'TemplateLiteral') {
    let value = node.quasis[0].value.cooked;
    for (let index = 0; index < node.expressions.length; index++) {
      const part = literalValue(node.expressions[index], depth + 1);
      if (part === undefined) return undefined;
      value += String(part) + node.quasis[index + 1].value.cooked;
      if (value!.length > 128) return undefined;
    }
    return value;
  }
}
const propertyName = (node: AnyNode | null | undefined) => node?.type === 'MemberExpression'
  ? node.computed ? literalValue(node.property) : (node.property as NamedSyntax).name : undefined;
const compilerField = (node: AnyNode | null | undefined) => {
  const value = literalValue(node);
  if (value !== undefined) return typeof value === 'string' && /^(?:\$tag|_\d+)$/u.test(value) ? value : undefined;
  if (node?.type === 'TemplateLiteral' && node.expressions.length &&
      node.quasis[0].value.cooked === '_' && node.quasis.at(-1)!.value.cooked === '') return '_<dynamic>';
  if (node?.type === 'BinaryExpression' && node.operator === '+' && literalValue(node.left) === '_') return '_<dynamic>';
};
const exportsObject = (node: AnyNode | null | undefined) => node?.type === 'Identifier' && node.name === 'exports' ||
  node?.type === 'MemberExpression' && (node.object as NamedSyntax).name === 'module' && propertyName(node) === 'exports';

function names(pattern: AnyNode | null | undefined): string[] {
  if (!pattern) return [];
  if (pattern.type === 'Identifier') return [pattern.name];
  if (pattern.type === 'RestElement') return names(pattern.argument);
  if (pattern.type === 'AssignmentPattern') return names(pattern.left);
  if (pattern.type === 'ArrayPattern') return pattern.elements.flatMap(names);
  if (pattern.type === 'ObjectPattern') return pattern.properties.flatMap(property =>
    names(property.type === 'RestElement' ? property.argument : property.value));
  return [];
}

// Resolve only lexical, single-write references. The normal builder must still
// admit each resulting target; this AST projection never loads product code.
function runtimeImportReferences(tree: Program, privateFunctions?: WeakSet<AnyNode>) {
  const scopes = new WeakMap<AnyNode, Scope>(), parents = new WeakMap<AnyNode, AnyNode | undefined>(), assignments: Mutation[] = [], nodes: AnyNode[] = [];
  const callables = new WeakMap<Binding, Callable>(), candidates = new Map<Callable, Set<Binding>>(), exported = new Set<Callable>();
  const callable = (binding: Binding, node: Callable) => {
    callables.set(binding, node);
    if (!candidates.has(node)) candidates.set(node, new Set<Binding>());
    candidates.get(node)!.add(binding);
  };
  const scope = (parent: Scope | undefined, functionScope = false): Scope => ({parent, functionScope, bindings: new Map<string, Binding>()});
  const lookup = (current: Scope | undefined, name: string): Binding | undefined => {
    for (; current; current = current.parent) if (current.bindings.has(name)) return current.bindings.get(name)!;
  };
  function declare(current: Scope, name: string, value: Partial<Binding> = {}): Binding {
    const prior = current.bindings.get(name);
    if (prior) prior.invalid = true;
    else current.bindings.set(name, {initializers: [], ...value});
    return current.bindings.get(name)!;
  }
  function collect(node: AnyNode | null | undefined, current: Scope, parent?: AnyNode) {
    if (!node || typeof node !== 'object') return;
    parents.set(node, parent);
    nodes.push(node);
    if (node.type === 'FunctionDeclaration' || node.type === 'ClassDeclaration') {
      if (node.id) {
        const binding = declare(current, node.id.name, {function: node.type === 'FunctionDeclaration' ? node : undefined});
        if (node.type === 'FunctionDeclaration') {
          callable(binding, node);
          if (/^Export/u.test(parent?.type ?? '')) exported.add(node);
        }
      }
    }
    if (/^(?:FunctionDeclaration|FunctionExpression|ArrowFunctionExpression)$/u.test(node.type)) {
      current = scope(current, true);
      (node as Callable).params.forEach((parameter, index) => {
        const pattern = parameter.type === 'AssignmentPattern' ? parameter.left : parameter;
        for (const name of names(parameter)) {
          const property = pattern.type === 'ObjectPattern' && pattern.properties.find(property =>
            property.type === 'Property' && !property.computed && property.value.type === 'Identifier' && property.value.name === name);
          declare(current, name, {parameter: pattern.type === 'Identifier' || property
            ? {function: node as Callable, index, property: property ? (((property as Property).key as NamedSyntax).name ?? ((property as Property).key as NamedSyntax).value) as string | number : undefined} : undefined});
        }
      });
      if (node.type === 'FunctionExpression' && node.id) {
        const binding = declare(current, node.id.name);
        // A returned/passed function literal is not a private declaration.
        // Only retain its self-name when an actual local binding owns it.
        if (candidates.has(node)) callable(binding, node);
      }
    } else if (['BlockStatement', 'CatchClause'].includes(node.type)) {
      current = scope(current);
      if ((node as {param?: AnyNode}).param) for (const name of names((node as {param?: AnyNode}).param)) declare(current, name);
    }
    scopes.set(node, current);
    if (node.type === 'ImportDeclaration') for (const value of node.specifiers) {
      declare(current, value.local.name, {imported: {source: node.source.value as string,
        name: value.type === 'ImportSpecifier' ? (value.imported as NamedSyntax).name ?? (value.imported as NamedSyntax).value as string | undefined : undefined}});
    }
    if (node.type === 'VariableDeclaration') for (const value of node.declarations) {
      let target = current;
      if (node.kind === 'var') while (target.parent && !target.functionScope) target = target.parent;
      for (const name of names(value.id)) {
        const binding = declare(target, name);
        if (value.id.type !== 'Identifier') {
          const property = value.id.type === 'ObjectPattern' && value.id.properties.find(property =>
            property.type === 'Property' && property.kind === 'init' && !property.computed && property.value.type === 'Identifier' &&
            property.value.name === name);
          if (property && value.init) binding.projection = {node: value.init, key: (((property as Property).key as NamedSyntax).name ?? ((property as Property).key as NamedSyntax).value) as string | number};
          else binding.invalid = true;
        }
        else if (value.init) {
          binding.initializers.push(value.init);
          if (/^(?:FunctionExpression|ArrowFunctionExpression)$/u.test(value.init.type)) {
            callable(binding, value.init as Callable);
            binding.definition = value.id;
            if (/^Export/u.test(parent?.type ?? '')) exported.add(value.init as Callable);
          }
        }
      }
    }
    if (['AssignmentExpression', 'UpdateExpression', 'UnaryExpression'].includes(node.type)) assignments.push(node as Mutation);
    for (const [key, value] of Object.entries(node)) {
      if (['loc', 'start', 'end'].includes(key)) continue;
      if (Array.isArray(value)) value.forEach(child => collect(child as AnyNode, current, node));
      else if (value && typeof value === 'object') collect(value as AnyNode, current, node);
    }
  }
  collect(tree, scope(undefined, true));
  for (const node of assignments) {
    let left = (node as Mutation & {left?: AnyNode}).left ?? (node as Mutation & {argument?: AnyNode}).argument;
    if (node.type === 'UnaryExpression' && node.operator !== 'delete') continue;
    const member = left?.type === 'MemberExpression';
    while (left?.type === 'MemberExpression') left = left.object;
    if (left?.type !== 'Identifier') {
      for (const name of names(left)) {
        const binding = lookup(scopes.get(node), name);
        if (binding) binding.invalid = true;
      }
      continue;
    }
    const binding = lookup(scopes.get(node), left.name);
    if (!binding) continue;
    if (binding.parameter || binding.projection || binding.imported || binding.function) binding.invalid = true;
    else if (!member && node.type === 'AssignmentExpression' && node.operator === '=') binding.initializers.push(node.right);
    else binding.invalid = true;
  }
  const calls = new Map<Callable, CallExpression[]>(), escaped = new Set<Callable>();
  for (const node of nodes) if (node.type === 'Identifier') {
    const binding = lookup(scopes.get(node), node.name), fn = binding?.function ?? (binding && callables.get(binding));
    if (!fn) continue;
    const parent = parents.get(node);
    if (parent === fn && (fn as Callable & {id?: AnyNode}).id === node || binding!.definition === node) continue;
    if (parent?.type === 'CallExpression' && parent.callee === node) {
      if (!calls.has(fn)) calls.set(fn, []);
      calls.get(fn)!.push(parent);
    } else escaped.add(fn);
  }
  // Direct eval can observe/return any lexical function without an Identifier
  // reference in this syntax tree. Keep the entire module conservative there.
  const lexicalEval = nodes.some(node => node.type === 'CallExpression' && !node.optional &&
    node.callee.type === 'Identifier' && node.callee.name === 'eval' && !lookup(scopes.get(node), 'eval'));
  for (const [fn, bindings] of candidates) {
    if (!lexicalEval && !exported.has(fn) && !escaped.has(fn) && [...bindings].every(binding => !binding.invalid)) {
      privateFunctions?.add(fn);
    }
  }
  const union = (values: SyntaxOrigin[]): SyntaxOrigin => values.length === 1 ? values[0] : {kind: 'alternatives', values};
  const unresolved = (): SyntaxOrigin => ({kind: 'unresolved'});
  const selectedProperty = (value: SyntaxOrigin | undefined, key: string | number): SyntaxOrigin | undefined => value?.kind === 'object' ? value.properties[key] :
    value?.kind === 'alternatives' ? union(value.values.map(value => selectedProperty(value, key) ?? unresolved())) : undefined;
  // Bounded syntax provenance, not execution of a product callback. Follow
  // private, nonescaping local calls only. Unknown arguments remain explicit;
  // imported Owner identity alone never supplies their values or provenance.
  function origin(node: AnyNode | null | undefined, seen = new Set<AnyNode>(), depth = 0): SyntaxOrigin {
    if (!node || depth > 32 || seen.has(node)) return unresolved();
    seen = new Set(seen).add(node);
    const next = (value: AnyNode | null | undefined) => origin(value, seen, depth + 1);
    if (node.type === 'Literal' && (node.value === null || ['string', 'number', 'boolean'].includes(typeof node.value))) {
      return {kind: 'value', value: node.value};
    }
    if (node.type === 'Identifier') {
      const binding = lookup(scopes.get(node), node.name);
      if (!binding || binding.invalid) return unresolved();
      if (binding.imported && !binding.initializers.length) return {kind: 'import', ...binding.imported};
      if (binding.initializers.length === 1) return next(binding.initializers[0]);
      if (binding.projection) return selectedProperty(next(binding.projection.node), binding.projection.key) ?? unresolved();
      if (binding.parameter) {
        const {function: fn, index, property} = binding.parameter;
        if (escaped.has(fn) || parents.get(fn)?.type === 'ExportNamedDeclaration' || !calls.get(fn)?.length) {
          return {kind: 'runtime-parameter', index, ...(property === undefined ? {} : {property})};
        }
        return union(calls.get(fn)!.map(call => {
          const value = next(call.arguments[index]);
          return property === undefined ? value : selectedProperty(value, property) ?? unresolved();
        }));
      }
    }
    if (node.type === 'AwaitExpression') return next(node.argument);
    if (node.type === 'ConditionalExpression') return union([next(node.consequent), next(node.alternate)]);
    if (node.type === 'ObjectExpression') {
      const properties: Record<string, SyntaxOrigin> = {};
      for (const property of node.properties) {
        if (property.type !== 'Property' || property.kind !== 'init' || property.computed) return unresolved();
        const name = ((property.key as NamedSyntax).name ?? (property.key as NamedSyntax).value) as string;
        if (Object.hasOwn(properties, name)) return unresolved();
        properties[name] = next(property.value);
      }
      return {kind: 'object', properties};
    }
    if (node.type === 'ArrayExpression') return {kind: 'array', values: node.elements.map(value =>
      value?.type === 'SpreadElement' ? {kind: 'spread', value: next(value.argument)} : next(value))};
    if (node.type === 'MemberExpression' && meta(node.object) && propertyName(node) === 'url') return {kind: 'module-meta-url'};
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        node.callee.object.type === 'Identifier' && (node.callee.object as NamedSyntax).name === 'Object' &&
        !lookup(scopes.get(node), 'Object') && propertyName(node.callee) === 'freeze' && node.arguments.length === 1) {
      return next(node.arguments[0]);
    }
    if (node.type === 'CallExpression' && node.callee.type === 'Identifier') {
      const binding = lookup(scopes.get(node), node.callee.name);
      if (!binding || binding.invalid) return unresolved();
      if (binding.imported?.name && !binding.initializers.length) return {kind: 'owner-call',
        ...binding.imported, arguments: node.arguments.map(next)};
      if (binding.function && !escaped.has(binding.function)) {
        const results: SyntaxOrigin[] = [];
        function returns(value: AnyNode | null | undefined) {
          if (!value || typeof value !== 'object') return;
          if (/^(?:FunctionDeclaration|FunctionExpression|ArrowFunctionExpression)$/u.test(value.type)) return;
          if (value.type === 'ReturnStatement') {results.push(next(value.argument)); return;}
          for (const child of Object.values(value)) if (Array.isArray(child)) child.forEach(returns);
          else if (child && typeof child === 'object') returns(child as AnyNode);
        }
        returns(binding.function.body);
        if (results.length) return union(results);
      }
    }
    return unresolved();
  }
  const meta = (node: AnyNode | null | undefined) => node?.type === 'MetaProperty' && node.meta.name === 'import' && (node.property as NamedSyntax).name === 'meta';
  function reference(node: AnyNode | null | undefined, depth = 0): RuntimeReference | undefined {
    if (!node || depth > 8) return;
    const literal = literalValue(node);
    if (typeof literal === 'string') return {kind: 'literal', specifier: literal};
    if (node.type === 'Identifier') {
      const binding = lookup(scopes.get(node), node.name);
      if (binding && !binding.invalid && binding.initializers.length === 1) return reference(binding.initializers[0], depth + 1);
    }
    if (node.type === 'NewExpression' && node.callee.type === 'Identifier' && node.callee.name === 'URL' &&
        !lookup(scopes.get(node), 'URL') && node.arguments.length === 2 &&
        node.arguments[1].type === 'MemberExpression' && meta(node.arguments[1].object) &&
        propertyName(node.arguments[1]) === 'url') {
      const specifier = literalValue(node.arguments[0]);
      if (typeof specifier === 'string') return {kind: 'module-url', specifier};
    }
    if (node.type === 'MemberExpression' && propertyName(node) === 'href') return reference(node.object, depth + 1);
    if (node.type === 'CallExpression' && node.arguments.length === 1 &&
        node.callee.type === 'MemberExpression' && meta(node.callee.object) && propertyName(node.callee) === 'resolve') {
      const specifier = literalValue(node.arguments[0]);
      if (typeof specifier === 'string') return {kind: 'package-resolution', specifier};
    }
    if (node.type === 'CallExpression' && node.callee.type === 'Identifier') {
      const binding = lookup(scopes.get(node), node.callee.name), imported = binding?.imported;
      if (!binding?.invalid && !binding?.initializers.length && imported?.name) return {
        kind: 'owner-projection', source: imported.source, name: imported.name, arguments: node.arguments.map(value => origin(value))};
    }
  }
  return reference;
}

// Keep implementation syntax available for diagnostics. Responsibility belongs
// to the actual module and its escaping/public operations, not private helper
// names or argument spelling. Compiler representation checks remain separate.
export function javascriptInterface(source: string, {resolveRuntimeImport}: {resolveRuntimeImport?: (reference: RuntimeReference) => unknown} = {}) {
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module',
    allowHashBang: true, locations: true});
  const operations: {name: string; parameters: string[]; async: boolean}[] = [], exports: string[] = [], imports: string[] = [], compilerFields: string[] = [], unresolvedSyntax: string[] = [], occurrences = new Map<string, number>();
  const privateFunctions = new WeakSet<AnyNode>(), privateOperations: string[] = [];
  const runtimeReference = runtimeImportReferences(tree, privateFunctions);
  function commonJsMembers(value: AnyNode | null | undefined) {
    if (value?.type === 'CallExpression' && value.callee.type === 'MemberExpression' &&
        (value.callee.object as NamedSyntax).name === 'Object' && propertyName(value.callee) === 'freeze') value = value.arguments[0];
    if (value?.type !== 'ObjectExpression') {
      unresolvedSyntax.push('dynamic CommonJS export value');
      return;
    }
    for (const property of value.properties) {
      const key = (property as Property).computed ? (property as Property).key.type === 'Literal' ? ((property as Property).key as NamedSyntax).value : undefined
        : ((property as Property).key as NamedSyntax | undefined)?.name ?? ((property as Property).key as NamedSyntax | undefined)?.value;
      if (typeof key === 'string') exports.push(`commonjs:${key}`);
      else unresolvedSyntax.push('dynamic CommonJS export member');
    }
  }
  function visit(node: AnyNode | null | undefined, scope: string[] = []) {
    if (!node || typeof node !== 'object') return;
    let childScope = scope;
    if (node.type === 'ClassDeclaration' || node.type === 'ClassExpression') {
      childScope = [...scope, node.id?.name ?? '<class>'];
    }
    if (node.type === 'MethodDefinition' || node.type === 'Property' && node.method) {
      const key = node.computed ? (node.key as NamedSyntax).value : (node.key as NamedSyntax).name ?? (node.key as NamedSyntax).value;
      childScope = [...scope, `${(node as {static?: boolean}).static ? 'static ' : ''}${node.kind ?? 'method'}:${key ?? '<computed>'}`];
    }
    if (/^(?:FunctionDeclaration|FunctionExpression|ArrowFunctionExpression)$/u.test(node.type)) {
      const name = (node as {id?: {name: string}}).id?.name ?? scope.at(-1) ?? '<anonymous>';
      const base = [...scope, name].join('/'), occurrence = (occurrences.get(base) ?? 0) + 1;
      occurrences.set(base, occurrence);
      const path = occurrence === 1 ? base : `${base}#${occurrence}`;
      operations.push({name: path, parameters: (node as Callable).params.flatMap(names), async: (node as Callable).async});
      if (privateFunctions.has(node)) privateOperations.push(path);
      childScope = [...scope, name];
    }
    if (node.type === 'ImportDeclaration' || node.type === 'ExportAllDeclaration' ||
        node.type === 'ExportNamedDeclaration' && node.source) imports.push(node.source!.value as string);
    if (node.type === 'ImportExpression' || node.type === 'CallExpression' &&
        node.callee.type === 'Identifier' && node.callee.name === 'require') {
      const argument = node.type === 'ImportExpression' ? node.source : node.arguments[0];
      const target = literalValue(argument);
      if (typeof target === 'string') imports.push(target);
      else {
        const reference = resolveRuntimeImport && runtimeReference(argument);
        const resolved = reference && resolveRuntimeImport(reference);
        if (Array.isArray(resolved) && resolved.length && resolved.every(value => typeof value === 'string')) imports.push(...resolved);
        else unresolvedSyntax.push('runtime-dependent module dependency requires original owner/artifact mapping');
      }
    }
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        (node.callee.object as NamedSyntax).name === 'Reflect' && propertyName(node.callee) === 'get' &&
        compilerField(node.arguments[1])) compilerFields.push(compilerField(node.arguments[1])!);
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        ['Object', 'Reflect'].includes((node.callee.object as NamedSyntax).name as string) &&
        ['getOwnPropertyDescriptor', 'defineProperty', 'set'].includes(propertyName(node.callee) as string) &&
        compilerField(node.arguments[1])) compilerFields.push(compilerField(node.arguments[1])!);
    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression' &&
        (node.callee.object as NamedSyntax).name === 'Object' && propertyName(node.callee) === 'assign' &&
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
      ? `${(node.exported as NamedSyntax).name ?? (node.exported as NamedSyntax).value}=*:${node.source.value}` : `*:${node.source.value}`);
    if (node.type === 'ExportNamedDeclaration') {
      exports.push(...node.specifiers.map(value => ((value.exported as NamedSyntax).name ?? (value.exported as NamedSyntax).value) as string));
      if ((node.declaration as {id?: {name: string}} | null | undefined)?.id) exports.push((node.declaration as {id: {name: string}}).id.name);
      if ((node.declaration as {declarations?: VariableDeclarator[]} | null | undefined)?.declarations) exports.push(...(node.declaration as {declarations: VariableDeclarator[]}).declarations.flatMap(value => names(value.id)));
    }
    const key = node.type === 'MemberExpression'
      ? node.computed ? compilerField(node.property) ?? literalValue(node.property) : (node.property as NamedSyntax).name
      : node.type === 'Property' ? node.computed
        ? compilerField(node.key) ?? literalValue(node.key) : (node.key as NamedSyntax).name ?? (node.key as NamedSyntax).value : undefined;
    if (typeof key === 'string' && /^(?:\$tag|_\d+|_<dynamic>)$/u.test(key)) compilerFields.push(key);
    for (const [key, child] of Object.entries(node)) {
      if (['loc', 'start', 'end'].includes(key)) continue;
      const binding = node.type === 'VariableDeclarator' && key === 'init' && node.id.type === 'Identifier'
        ? [...childScope, node.id.name] : childScope;
      if (Array.isArray(child)) child.forEach(value => visit(value as AnyNode, binding));
      else if (child && typeof child === 'object') visit(child as AnyNode, binding);
    }
  }
  visit(tree);
  return {exports: ordered(exports), operations: operations.sort((a, b) => a.name.localeCompare(b.name)),
    privateOperations: ordered(privateOperations),
    imports: ordered(imports), compilerFields: ordered(compilerFields), unresolvedSyntax: ordered(unresolvedSyntax)};
}

export function javascriptClosure(root: string, entries: string[]) {
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
export function packageEntrances(manifest: UncheckedPackageManifest, directory = '.') {
  function targets(value: unknown): string[] {
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

// A verification reference identifies a real test entry, not its presentation
// label. Registration presence does not prove execution, assertions or coverage;
// the existing runtime/nonzero-test gates remain responsible for those claims.
function hasNodeTestRegistration(source: string, filename = 'interface.mjs') {
  let tree: Program;
  try {
    if (/\.[cm]?tsx?$/u.test(filename)) {
      if (/\.d\.[cm]?ts$/u.test(filename)) return false;
      // Erase types with the pinned compiler, then use the same Node import,
      // scope and skip checks. This is registration syntax, never execution
      // or a substitute for the separate strict compiler owner.
      const lowered = ts.transpileModule(source, {fileName: filename,
        compilerOptions: {module: ts.ModuleKind.NodeNext, target: ts.ScriptTarget.ES2022,
          verbatimModuleSyntax: true}, reportDiagnostics: true});
      if (lowered.diagnostics?.some(value => value.category === ts.DiagnosticCategory.Error)) return false;
      source = lowered.outputText;
    }
    tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module', allowHashBang: true});
  }
  catch {return false;}
  const imports = new Map<string, string>();
  for (const node of tree.body) if (node.type === 'ImportDeclaration' && node.source.value === 'node:test') {
    for (const item of node.specifiers) {
      if (item.type === 'ImportDefaultSpecifier' ||
          item.type === 'ImportSpecifier' && ['test', 'it'].includes((item.imported as NamedSyntax).name as string)) {
        imports.set(item.local.name, 'test');
      } else if (item.type === 'ImportNamespaceSpecifier') imports.set(item.local.name, 'namespace');
    }
  }
  const bindings = (pattern: AnyNode | null | undefined, names: Set<string>): void => {
    if (!pattern) return;
    if (pattern.type === 'Identifier') names.add(pattern.name);
    else if (pattern.type === 'RestElement') bindings(pattern.argument, names);
    else if (pattern.type === 'AssignmentPattern') bindings(pattern.left, names);
    else if (pattern.type === 'ArrayPattern') pattern.elements.forEach(item => bindings(item, names));
    else if (pattern.type === 'ObjectPattern') pattern.properties.forEach(item =>
      bindings(item.type === 'RestElement' ? item.argument : item.value, names));
  };
  const locals = (nodes: (AnyNode | null | undefined)[]) => {
    const names = new Set<string>();
    for (const node of nodes) {
      if (node?.type === 'VariableDeclaration') node.declarations.forEach(item => bindings(item.id, names));
      else if (['FunctionDeclaration', 'ClassDeclaration'].includes(node?.type as string) && (node as {id?: {name: string}}).id) names.add((node as {id: {name: string}}).id.name);
    }
    return names;
  };
  const visit = (node: AnyNode | null | undefined, shadowed = new Set<string>()): boolean => {
    if (!node || typeof node !== 'object') return false;
    if (/^(?:Function|ArrowFunction)/u.test(node.type)) return false;
    let scope = shadowed;
    if (node.type === 'Program' || node.type === 'BlockStatement') {
      scope = new Set([...shadowed, ...locals(node.body)]);
    } else if (['ForStatement', 'ForInStatement', 'ForOfStatement'].includes(node.type)) {
      scope = new Set([...shadowed, ...locals([(node as {init?: AnyNode}).init ?? (node as {left?: AnyNode}).left])]);
    } else if (node.type === 'CatchClause') {
      scope = new Set(shadowed);bindings(node.param, scope);
    }
    if (node.type === 'CallExpression') {
      const callee = node.callee;
      const binding = callee.type === 'Identifier' ? callee.name
        : callee.type === 'MemberExpression' && callee.object.type === 'Identifier' ? callee.object.name : undefined;
      const registered = !scope.has(binding!) && (callee.type === 'Identifier' && imports.get(binding!) === 'test' ||
        callee.type === 'MemberExpression' && imports.get(binding!) === 'namespace' &&
        ['test', 'it'].includes(propertyName(callee) as string));
      if (registered) {
        const callback = node.arguments.at(-1);
        const skipped = node.arguments.some(argument => argument.type === 'ObjectExpression' &&
          argument.properties.some(item => item.type === 'Property' &&
            ['skip', 'todo'].includes((item.computed ? (item.key as NamedSyntax).value : (item.key as NamedSyntax).name ?? (item.key as NamedSyntax).value) as string) &&
            item.value.type === 'Literal' && item.value.value === true));
        if (!skipped && callback && (['FunctionExpression', 'ArrowFunctionExpression'].includes(callback.type) ||
            callback.type === 'Identifier' && node.arguments.length > 1)) return true;
      }
    }
    return Object.values(node).some(value => Array.isArray(value)
      ? value.some(item => visit(item as AnyNode, scope)) : value && typeof value === 'object' && visit(value as AnyNode, scope));
  };
  return visit(tree);
}

function reference(root: string, ref: UncheckedReference, readReference?: ReadReference, verification = false, registeredTest: (source: string, filename: string) => boolean = hasNodeTestRegistration) {
  const keys = ref && Object.keys(ref).sort().join();
  assert(keys === 'anchor,path' || keys === 'case_id,path', 'Invalid interface reference');
  const executable = keys === 'case_id,path';
  assert(typeof ref.path === 'string' && inside(ref.path) &&
    (executable ? /_(?:wbtest|bbtest|test)\.mbt$/u.test(ref.path) &&
      typeof ref.case_id === 'string' && /^[a-z][a-z0-9_]*$/u.test(ref.case_id)
      : typeof ref.anchor === 'string' && ref.anchor.length),
    'Invalid interface reference');
  assert(!ref.path.split('/').includes('..'), 'Invalid interface reference traversal');
  // Converted Node .mjs/.cjs entries use .mts/.cts sources. Existing .test.ts
  // compiler fixtures retain their exact source anchors and compiler owners;
  // their declarations are not claims of Node test registration.
  const testEntry = verification && /\.test\.(?:[cm]?js|[cm]ts)$/u.test(ref.path);
  const present = (source: string) => executable ? hasExecutableTestCase(source, ref.case_id)
    : testEntry ? registeredTest(source, ref.path as string) : source.includes(ref.anchor as string);
  const label = executable ? `case_id=${ref.case_id}` : ref.anchor;
  if (readReference) {
    assert(present(readReference(ref.path)), `Missing interface reference: ${ref.path}#${label}`);
    return;
  }
  const path = realpathSync(resolve(root, ref.path));
  assert(inside(relative(realpathSync(root), path)), 'Interface reference escapes owner');
  assert(present(readFileSync(path, 'utf8')), `Missing interface reference: ${ref.path}#${label}`);
}

// Source headers keep argument roles/types, but an optional trailing comma
// in the OUTER named-parameter list is formatting. Nested tuple punctuation
// and compiler-generated .mbti/API text retain their exact existing identity.
function sourceOperationCorrespondence<T extends Operation>(module: string, operations: readonly T[], privateOperations: readonly string[] = []) {
  if (/\.[cm]?jsx?$/u.test(module)) return operations.filter(operation => !privateOperations.includes(operation.name));
  if (!module.endsWith('.mbt')) return operations;
  return operations.map(operation => {
    if (typeof operation.declaration !== 'string') return operation;
    const header = operation.declaration.split(' '), open = header.indexOf('(');
    if (open < 0) return operation;
    let depth = 0, named = false;
    for (let index = open; index < header.length; index++) {
      if (header[index] === '(') depth++;
      else if (header[index] === ')') {
        if (--depth === 0) {
          if (!named || header[index - 1] !== ',') return operation;
          header.splice(index - 1, 1);
          return {...operation, declaration:header.join(' ')};
        }
      } else if (depth === 1 && header[index] === ':') named = true;
    }
    return operation;
  });
}

export function assertInterfaceCoverage({root, modules, declarations, generated = [], readReference}: {root: string; modules: readonly ModuleInterface[]; declarations: readonly UncheckedDeclaration[]; generated?: readonly GeneratedProof[]; readReference?: ReadReference}) {
  const references = new Map<string, string>(), registrations = new Map<string, Map<string, boolean>>();
  const registeredTest = (source: string, filename: string) => {
    if (!registrations.has(filename)) registrations.set(filename, new Map<string, boolean>());
    const selected = registrations.get(filename)!;
    if (!selected.has(source)) selected.set(source, hasNodeTestRegistration(source, filename));
    return selected.get(source)!;
  };
  const read = (path: string) => {
    if (!references.has(path)) references.set(path, readReference
      ? readReference(path) : (() => {
        const actual = realpathSync(resolve(root, path));
        assert(inside(relative(realpathSync(root), actual)), 'Interface reference escapes owner');
        return readFileSync(actual, 'utf8');
      })());
    return references.get(path)!;
  };
  const byModule = new Map<string, UncheckedDeclaration>();
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
        value.forEach((ref: unknown) => reference(root, ref as UncheckedReference, read, name === 'verification', registeredTest));
      } else assert(value && Object.keys(value).join() === 'notApplicable' &&
        typeof (value as {notApplicable?: unknown}).notApplicable === 'string' && (value as {notApplicable: string}).notApplicable.trim().length > 0,
      `Unexplained interface attribute: ${declaration.module}:${name}`);
      }
    }
    byModule.set(declaration.module, declaration);
  }
  for (const module of modules) {
    const declaration = byModule.get(module.module);
    assert(!module.unresolvedSyntax?.length, `Unresolved interface syntax: ${module.module}`);
    assert(declaration, `Unregistered distributed interface: ${module.module}`);
    // The declaration digest is a review snapshot, not behavioral evidence.
    // Actual source/artifact correspondence uses the current module digest;
    // privileged generated representations retain their proof check below.
    assert.deepEqual(declaration.exports, module.exports, `Unregistered interface export: ${module.module}`);
    const privateSnapshot = declaration.role !== 'generated-binding' && !module.compilerFields?.length;
    const actualPrivate = privateSnapshot ? module.privateOperations ?? [] : [];
    const declaredOperations = sourceOperationCorrespondence(module.module, declaration.operations);
    const actualOperations = sourceOperationCorrespondence(module.module, module.operations, actualPrivate);
    assert.deepEqual(declaredOperations, actualOperations,
      `Unregistered interface operation: ${module.module}`);
    for (const [field, actual] of [['operations', ['<module>', ...actualOperations.map(value => value.name)]],
      ['exports', module.exports]] as const) {
      const covered: unknown[] = declaration.contracts.flatMap(value => value[field]);
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
