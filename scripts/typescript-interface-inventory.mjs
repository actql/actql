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
  const operations = [], exports = [], imports = [];
  function visit(node, scope = []) {
    const exported = node.modifiers?.some(value => value.kind === ts.SyntaxKind.ExportKeyword);
    const name = node.name?.getText(tree);
    let next = scope;
    if (ts.isClassDeclaration(node) || ts.isInterfaceDeclaration(node) || ts.isModuleDeclaration(node)) {
      next = [...scope, name ?? '<anonymous>'];
    }
    if (ts.isFunctionDeclaration(node) || ts.isMethodDeclaration(node) || ts.isMethodSignature(node) ||
        ts.isConstructorDeclaration(node) || ts.isGetAccessor(node) || ts.isSetAccessor(node) ||
        ts.isCallSignatureDeclaration(node) || ts.isFunctionTypeNode(node)) {
      const operation = [...scope, name ?? (ts.isConstructorDeclaration(node) ? 'constructor' : '<call>')].join('/');
      operations.push({name: operation, parameters: node.parameters.map(value => value.getText(tree)),
        result: node.type?.getText(tree) ?? null});
      next = [...scope, name ?? '<call>'];
    }
    if (exported && name) exports.push(name);
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
    ts.forEachChild(node, child => visit(child, next));
  }
  visit(tree);
  return {exports: [...new Set(exports)].sort(), operations: operations.sort((a, b) => a.name.localeCompare(b.name)),
    imports: [...new Set(imports)].sort()};
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
