// The existing production reader owns manifest syntax and test scopes.
// This projection never compiles or evaluates a package.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, readdirSync} from 'node:fs';
import {join, relative, resolve} from 'node:path';
import {productionDependencyClosure} from './source-dependency-closure.mjs';
import {tokens} from './portable-core.mjs';

export function moonApiInterface(source) {
  const exports = source.split('\n').filter(line => line.startsWith('pub '));
  const operations = exports.flatMap(declaration => {
    const match = /^pub fn(?:\[[^\]]*\])? ([^(]+)\(/u.exec(declaration);
    return match ? [{name: match[1], declaration}] : [];
  });
  return {exports, operations};
}

export function moonOperations(source) {
  const input = tokens(source, true), operations = [];
  let braces = 0;
  for (let index = 0; index < input.length; index++) {
    const token = input[index];
    if (token.kind === 'symbol' && token.value === '{') braces++;
    if (token.kind === 'symbol' && token.value === '}') braces--;
    if (braces !== 0 || token.kind !== 'word' || token.value !== 'fn') continue;
    // Anonymous function types have no name. Keep the actual declaration
    // header, including type parameters and same-typed argument role names.
    if (input[index + 1]?.kind !== 'word' && input[index + 1]?.value !== '[') continue;
    const header = [];
    let cursor = index + 1;
    while (cursor < input.length && !['{', '=', ';'].includes(input[cursor].value)) {
      header.push(input[cursor++].value);
    }
    if (header.includes('(')) operations.push({name: header.slice(0, header.indexOf('(')).join(''),
      declaration: header.join(' ')});
  }
  return operations.sort((a, b) => a.name.localeCompare(b.name));
}

export function moonInterfaceClosure(root, entrances) {
  const readManifest = name => readFileSync(join(root, 'src', name, 'moon.pkg'), 'utf8');
  const packages = [...new Set(entrances.flatMap(name => [name,
    ...productionDependencyClosure(name, readManifest)]))].sort();
  const modules = [];
  for (const name of packages) {
    const directory = resolve(root, 'src', name);
    assert(!relative(resolve(root, 'src'), directory).startsWith('..'), 'Escaped MoonBit package');
    for (const entry of readdirSync(directory, {withFileTypes: true})) {
      if (!entry.isFile() || !entry.name.endsWith('.mbt') ||
          /(?:_test|_wbtest|_bbtest)\.mbt$/u.test(entry.name)) continue;
      const module = `src/${name}/${entry.name}`, bytes = readFileSync(join(root, module));
      const operations = moonOperations(bytes.toString('utf8'));
      modules.push({module, sha256: createHash('sha256').update(bytes).digest('hex'),
        operations, exports: [], package: name});
    }
    const module = `src/${name}/pkg.generated.mbti`, bytes = readFileSync(join(root, module));
    modules.push({module, sha256: createHash('sha256').update(bytes).digest('hex'),
      ...moonApiInterface(bytes.toString('utf8')),
      package: name});
  }
  return {packages, modules: modules.sort((a, b) => a.module.localeCompare(b.module))};
}
