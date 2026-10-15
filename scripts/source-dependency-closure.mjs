// Test-only production dependency selection. The existing manifest reader
// validates import syntax/scopes; target/options policy remains with its owners.
import assert from 'node:assert/strict';
import {packageImports, tokens} from './portable-core.mjs';

export function productionPackageImports(source) {
  const ts = tokens(source), imports = [];
  let depth = 0;
  for (let i = 0; i < ts.length; i++) {
    const token = ts[i];
    if (depth === 0 && token.kind === 'word' && token.value === 'import') {
      const start = i;
      assert.equal(ts[++i]?.value, '{', 'Malformed import block');
      while (i < ts.length && ts[i].value !== '}') i++;
      assert(i < ts.length, 'Unclosed import block');
      if (ts[i + 1]?.kind === 'word' && ts[i + 1].value === 'for') i += 2;
      const block = ts.slice(start, i + 1).map(t =>
        t.kind === 'string' ? JSON.stringify(t.value) : t.value).join(' ');
      imports.push(...packageImports(block).filter(entry =>
        entry.scope === 'production' && entry.path.startsWith('actql/actql/'))
        .map(entry => entry.path.slice('actql/actql/'.length)));
    } else if (token.kind === 'symbol') {
      if (['{', '(', '['].includes(token.value)) depth++;
      else if (['}', ')', ']'].includes(token.value)) depth--;
    }
  }
  return imports;
}

export function productionDependencyClosure(name, readManifest) {
  const seen = new Set(), pending = productionPackageImports(readManifest(name));
  while (pending.length) {
    const dependency = pending.pop();
    if (seen.has(dependency)) continue;
    seen.add(dependency);
    pending.push(...productionPackageImports(readManifest(dependency)));
  }
  return [...seen];
}
