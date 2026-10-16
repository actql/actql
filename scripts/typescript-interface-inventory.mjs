// Use the pinned TypeScript parser/resolver for declaration and Cloud sources.
// No application module or user configuration is evaluated here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, realpathSync} from 'node:fs';
import {relative, resolve} from 'node:path';
import ts from 'typescript';

export function typescriptInterface(source, filename = 'interface.ts') {
  const tree = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  assert.equal(tree.parseDiagnostics.length, 0, `Invalid TypeScript interface: ${filename}`);
  const operations = [], exports = [], imports = [], compilerFields = [], occurrences = new Map();
  const globalDeclarations = tree.isDeclarationFile && !ts.isExternalModule(tree);
  function visit(node, scope = []) {
    const exported = node.modifiers?.some(value => value.kind === ts.SyntaxKind.ExportKeyword) ||
      globalDeclarations && node.parent === tree;
    const defaultExport = node.modifiers?.some(value => value.kind === ts.SyntaxKind.DefaultKeyword);
    const name = node.name?.getText(tree) ??
      ((ts.isArrowFunction(node) || ts.isFunctionExpression(node)) ? node.parent?.name?.getText(tree) : undefined);
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
    if (exported && ts.isVariableStatement(node)) exports.push(...node.declarationList.declarations.map(value => value.name.getText(tree)));
    if (ts.isExportAssignment(node)) exports.push('default');
    if (ts.isExportDeclaration(node)) {
      if (!node.exportClause) exports.push(`*:${node.moduleSpecifier?.text}`);
      else if (ts.isNamespaceExport(node.exportClause)) exports.push(node.exportClause.name.text);
      else exports.push(...node.exportClause.elements.map(value => value.name.text));
    }
    if ((ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) && node.moduleSpecifier) {
      imports.push(node.moduleSpecifier.text);
    }
    if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument) &&
        ts.isStringLiteral(node.argument.literal)) imports.push(node.argument.literal.text);
    if (ts.isImportEqualsDeclaration(node) && ts.isExternalModuleReference(node.moduleReference) &&
        node.moduleReference.expression && ts.isStringLiteral(node.moduleReference.expression)) {
      imports.push(node.moduleReference.expression.text);
    }
    if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword &&
        node.arguments[0] && ts.isStringLiteral(node.arguments[0])) imports.push(node.arguments[0].text);
    const field = ts.isPropertyAccessExpression(node) ? node.name.text
      : ts.isElementAccessExpression(node) && ts.isStringLiteral(node.argumentExpression) ? node.argumentExpression.text
        : ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
          node.expression.expression.getText(tree) === 'Reflect' && node.expression.name.text === 'get' &&
          node.arguments[1] && ts.isStringLiteral(node.arguments[1]) ? node.arguments[1].text : undefined;
    if (field && /^(?:\$tag|_\d+)$/u.test(field)) compilerFields.push(field);
    ts.forEachChild(node, child => visit(child, next));
  }
  visit(tree);
  imports.push(...tree.referencedFiles.map(value => value.fileName.startsWith('.')
    ? value.fileName : `./${value.fileName}`));
  return {exports: [...new Set(exports)].sort(), operations: operations.sort((a, b) => a.name.localeCompare(b.name)),
    imports: [...new Set(imports)].sort(), compilerFields: [...new Set(compilerFields)].sort()};
}

export function typescriptInterfaceClosure(root, entrances) {
  const base = realpathSync(root), pending = [...entrances], modules = new Map();
  while (pending.length) {
    const path = realpathSync(resolve(base, pending.pop()));
    const module = relative(base, path);
    assert(!module.startsWith('..'), `Escaped TypeScript interface: ${module}`);
    if (modules.has(module)) continue;
    const bytes = readFileSync(path), syntax = typescriptInterface(bytes.toString('utf8'), path);
    modules.set(module, {module, sha256: createHash('sha256').update(bytes).digest('hex'), ...syntax});
    for (const specifier of syntax.imports.filter(value => value.startsWith('.'))) {
      const result = ts.resolveModuleName(specifier, path, {moduleResolution: ts.ModuleResolutionKind.Bundler,
        allowJs: true, resolveJsonModule: true}, ts.sys).resolvedModule;
      assert(result, `Unresolved TypeScript interface dependency: ${module}:${specifier}`);
      if (!result.resolvedFileName.endsWith('.json')) pending.push(result.resolvedFileName);
    }
  }
  return [...modules.values()].sort((a, b) => a.module.localeCompare(b.module));
}
