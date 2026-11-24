// Use the pinned TypeScript parser/resolver for declaration and Cloud sources.
// No application module or user configuration is evaluated here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync} from 'node:fs';
import {dirname, relative, resolve} from 'node:path';
import ts from 'typescript';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';

// Unchecked parser-node views expose existing optional syntax fields; the
// TypeScript parser and the same syntax-kind checks remain authoritative.
type UncheckedNamedNode = ts.Node & {readonly modifiers?: readonly ts.ModifierLike[]; readonly name?: ts.DeclarationName};
type ParsedSource = ts.SourceFile & {readonly parseDiagnostics: readonly ts.DiagnosticWithLocation[]};
type Literal = string | number | boolean;
type Operation = {name: string; parameters: string[]; result: string | null};

// Fold only bounded, closed literal syntax. Unknown expressions remain syntax,
// and no callback, property getter or product function is ever evaluated.
function literalValue(node: ts.Node | undefined, depth = 0): Literal | undefined {
  if (!node || depth > 8) return undefined;
  if (ts.isStringLiteralLike(node)) return node.text;
  if (ts.isNumericLiteral(node)) return Number(node.text);
  if (node.kind === ts.SyntaxKind.TrueKeyword) return true;
  if (node.kind === ts.SyntaxKind.FalseKeyword) return false;
  if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) ||
      ts.isTypeAssertionExpression(node) || ts.isSatisfiesExpression(node) ||
      ts.isNonNullExpression(node)) return literalValue(node.expression, depth + 1);
  if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.PlusToken) {
    const left = literalValue(node.left, depth + 1), right = literalValue(node.right, depth + 1);
    if (left !== undefined && right !== undefined) {
      // Static operand views preserve JavaScript's original mixed-primitive +.
      const value = (left as string) + (right as string);
      return typeof value === 'string' && value.length > 128 ? undefined : value;
    }
  }
  if (ts.isTemplateExpression(node)) {
    let value = node.head.text;
    for (const span of node.templateSpans) {
      const part = literalValue(span.expression, depth + 1);
      if (part === undefined) return undefined;
      value += String(part) + span.literal.text;
      if (value.length > 128) return undefined;
    }
    return value;
  }
}
function compilerField(node: ts.Node | undefined, depth = 0): string | undefined {
  if (!node || depth > 8) return undefined;
  // Erased wrappers must preserve both closed literals and dynamic prefixes.
  // The asserted type supplies no value; only the same bounded expression is read.
  if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) ||
      ts.isTypeAssertionExpression(node) || ts.isSatisfiesExpression(node) ||
      ts.isNonNullExpression(node)) return compilerField(node.expression, depth + 1);
  const value = literalValue(node, depth);
  if (value !== undefined) return typeof value === 'string' && /^(?:\$tag|_\d+)$/u.test(value) ? value : undefined;
  if (node && ts.isTemplateExpression(node) && node.head.text === '_' &&
      node.templateSpans.at(-1)!.literal.text === '') return '_<dynamic>';
  if (node && ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.PlusToken &&
      literalValue(node.left, depth) === '_') return '_<dynamic>';
}

function bindingNames(node: ts.Node): string[] {
  if (ts.isIdentifier(node)) return [node.text];
  if (ts.isObjectBindingPattern(node) || ts.isArrayBindingPattern(node)) {
    return node.elements.flatMap(value => ts.isOmittedExpression(value) ? [] : bindingNames(value.name));
  }
  return [];
}

export function typescriptInterface(source: string, filename = 'interface.ts') {
  const tree = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  assert.equal((tree as ParsedSource).parseDiagnostics.length, 0, `Invalid TypeScript interface: ${filename}`);
  const operations: Operation[] = [], exports: string[] = [], imports: string[] = [], compilerFields: string[] = [], unresolvedSyntax: string[] = [], occurrences = new Map<string, number>();
  const globalDeclarations = tree.isDeclarationFile && !ts.isExternalModule(tree);
  function visit(node: ts.Node, scope: string[] = []) {
    const exported = (node as UncheckedNamedNode).modifiers?.some(value => value.kind === ts.SyntaxKind.ExportKeyword) ||
      globalDeclarations && node.parent === tree;
    const defaultExport = (node as UncheckedNamedNode).modifiers?.some(value => value.kind === ts.SyntaxKind.DefaultKeyword);
    const name = (node as UncheckedNamedNode).name?.getText(tree) ??
      ((ts.isArrowFunction(node) || ts.isFunctionExpression(node)) ? (node.parent as UncheckedNamedNode | undefined)?.name?.getText(tree) : undefined);
    let next = scope;
    if (ts.isClassDeclaration(node) || ts.isInterfaceDeclaration(node) || ts.isModuleDeclaration(node)) {
      next = [...scope, name ?? '<anonymous>'];
    }
    if (ts.isFunctionDeclaration(node) || ts.isMethodDeclaration(node) || ts.isMethodSignature(node) ||
        ts.isConstructorDeclaration(node) || ts.isGetAccessor(node) || ts.isSetAccessor(node) ||
        ts.isCallSignatureDeclaration(node) || ts.isFunctionTypeNode(node) || ts.isArrowFunction(node) ||
        ts.isFunctionExpression(node)) {
      const base = [...scope, name ?? (ts.isConstructorDeclaration(node) ? 'constructor' : '<call>')].join('/');
      const occurrence = (occurrences.get(base) ?? 0) + 1;
      occurrences.set(base, occurrence);
      const operation = occurrence === 1 ? base : `${base}#${occurrence}`;
      operations.push({name: operation, parameters: node.parameters.map(value => value.getText(tree)),
        result: node.type?.getText(tree) ?? null});
      next = [...scope, name ?? '<call>'];
    }
    if (defaultExport) exports.push('default');
    else if (exported && name) exports.push(name);
    if (exported && ts.isVariableStatement(node)) exports.push(...node.declarationList.declarations.flatMap(value => bindingNames(value.name)));
    if (ts.isExportAssignment(node)) exports.push('default');
    if (ts.isExportDeclaration(node)) {
      if (!node.exportClause) exports.push(`*:${(node.moduleSpecifier as ts.StringLiteral | undefined)?.text}`);
      else if (ts.isNamespaceExport(node.exportClause)) exports.push(node.exportClause.name.text);
      else exports.push(...node.exportClause.elements.map(value => value.name.text));
    }
    if ((ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) && node.moduleSpecifier) {
      imports.push((node.moduleSpecifier as ts.StringLiteral).text);
    }
    if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument) &&
        ts.isStringLiteral(node.argument.literal)) imports.push(node.argument.literal.text);
    if (ts.isImportEqualsDeclaration(node) && ts.isExternalModuleReference(node.moduleReference) &&
        node.moduleReference.expression && ts.isStringLiteral(node.moduleReference.expression)) {
      imports.push(node.moduleReference.expression.text);
    }
    if (ts.isCallExpression(node) && (node.expression.kind === ts.SyntaxKind.ImportKeyword ||
        ts.isIdentifier(node.expression) && node.expression.text === 'require')) {
      const target = literalValue(node.arguments[0]);
      if (typeof target === 'string') imports.push(target);
      else unresolvedSyntax.push('runtime-dependent module dependency requires original owner/artifact mapping');
    }
    const key = (node as UncheckedNamedNode).name && (ts.isComputedPropertyName((node as UncheckedNamedNode).name!) ? ((node as UncheckedNamedNode).name as ts.ComputedPropertyName).expression : (node as UncheckedNamedNode).name);
    const field = ts.isPropertyAccessExpression(node) ? node.name.text
      : ts.isElementAccessExpression(node) ? compilerField(node.argumentExpression)
        : ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
          ['Reflect', 'Object'].includes(node.expression.expression.getText(tree)) &&
          ['get', 'set', 'getOwnPropertyDescriptor', 'defineProperty'].includes(node.expression.name.text)
          ? compilerField(node.arguments[1])
          : ts.isBindingElement(node) && ts.isObjectBindingPattern(node.parent)
            ? ts.isComputedPropertyName(node.propertyName ?? node.name)
              ? compilerField(((node.propertyName ?? node.name) as ts.ComputedPropertyName).expression) : ((node.propertyName ?? node.name) as ts.Identifier).text
            : ts.isPropertyAssignment(node) || ts.isShorthandPropertyAssignment(node)
              ? compilerField(key) ?? (key && ts.isIdentifier(key) ? key.text : undefined) : undefined;
    if (field && /^(?:\$tag|_\d+|_<dynamic>)$/u.test(field)) compilerFields.push(field);
    ts.forEachChild(node, child => visit(child, next));
  }
  visit(tree);
  imports.push(...tree.referencedFiles.map(value => value.fileName.startsWith('.')
    ? value.fileName : `./${value.fileName}`));
  return {exports: [...new Set(exports)].sort(), operations: operations.sort((a, b) => a.name.localeCompare(b.name)),
    imports: [...new Set(imports)].sort(), compilerFields: [...new Set(compilerFields)].sort(),
    ...(unresolvedSyntax.length ? {unresolvedSyntax: [...new Set(unresolvedSyntax)].sort()} : {})};
}

export function typescriptInterfaceClosure(root: string, entrances: readonly string[]) {
  return typescriptInterfaceInputs(root, entrances).modules;
}

// Keep TypeScript's real config/path resolution and non-code inputs visible.
// Actual web asset/plugin inputs still come from the configured Vite build.
export function typescriptInterfaceInputs(root: string, entrances: readonly string[]) {
  const base = realpathSync(root), pending = [...entrances], modules = new Map<string, ReturnType<typeof typescriptInterface> & {module: string; sha256: string}>(), assets = new Map<string, {module: string; sha256: string}>();
  const configs = new Map<string, ts.CompilerOptions>(), external: {module: string; specifier: string; qualification: string}[] = [];
  const options = (path: string): ts.CompilerOptions => {
    const file = ts.findConfigFile(dirname(path), ts.sys.fileExists);
    if (!file) return {moduleResolution: ts.ModuleResolutionKind.Bundler, allowJs: true, resolveJsonModule: true};
    const local = relative(base, realpathSync(file));
    assert(!local.startsWith('..'), `Escaped TypeScript config: ${local}`);
    if (!configs.has(file)) {
      const errors: ts.Diagnostic[] = [];
      const config = ts.getParsedCommandLineOfConfigFile(file, {}, {...ts.sys,
        onUnRecoverableConfigFileDiagnostic: error => errors.push(error)});
      assert(config && !errors.length, `Invalid TypeScript interface config: ${local}`);
      configs.set(file, config.options);
    }
    return configs.get(file)!;
  };
  while (pending.length) {
    const path = realpathSync(resolve(base, pending.pop()!));
    const module = relative(base, path);
    assert(!module.startsWith('..'), `Escaped TypeScript interface: ${module}`);
    assert(!isConnectorTestFixture(module) && !/(?:\.test|_test|_wbtest|_bbtest)\.[^/]+$/u.test(module),
      `Test authority in TypeScript interface: ${module}`);
    if (modules.has(module) || assets.has(module)) continue;
    if (module.endsWith('.json')) {
      assets.set(module, {module, sha256: createHash('sha256').update(readFileSync(path)).digest('hex')});
      continue;
    }
    const bytes = readFileSync(path), syntax = typescriptInterface(bytes.toString('utf8'), path);
    modules.set(module, {module, sha256: createHash('sha256').update(bytes).digest('hex'), ...syntax});
    for (const specifier of syntax.imports) {
      const local = specifier.startsWith('.');
      const result = ts.resolveModuleName(specifier, path, options(path), ts.sys).resolvedModule;
      // TypeScript also sets this flag on relative edges inside node_modules.
      // The same realpath containment check still applies to every local edge.
      if (result && (local || !result.isExternalLibraryImport)) pending.push(result.resolvedFileName);
      else if (local) assert.fail(`Unresolved TypeScript interface dependency: ${module}:${specifier}`);
      else {
        assert(!Object.keys(options(path).paths ?? {}).some(pattern => pattern.includes('*')
          ? specifier.startsWith(pattern.split('*')[0]) && specifier.endsWith(pattern.split('*')[1]) : pattern === specifier),
        `Unresolved TypeScript configured alias: ${module}:${specifier}`);
        external.push({module, specifier, qualification: 'external-type-reference; requires-own-package-admission'});
      }
    }
  }
  return {modules: [...modules.values()].sort((a, b) => a.module.localeCompare(b.module)),
    assets: [...assets.values()].sort((a, b) => a.module.localeCompare(b.module)), external,
    configs: [...configs.keys()].sort().map(path => ({module: relative(base, path),
      sha256: createHash('sha256').update(readFileSync(path)).digest('hex')}))};
}
