// Conservative parser for the audited Moon package grammar. Unknown syntax is
// an error, not an ignored dependency. Build-time tooling may use Node I/O.
import {readFileSync, readdirSync, existsSync, mkdirSync, copyFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const coreRoots = Object.freeze([
  'program_check', 'lowering_relation', 'execution_relation', 'query_planning',
  'connector_sdk', 'physical_strategy', 'physical_host',
]);
export const pureExternal = Object.freeze({
  'moonbitlang/core/encoding/utf8': 'Pinned UTF-8 encoding/decoding; no host I/O.',
  'moonbitlang/core/json': 'Pinned in-memory JSON values and parsing.',
  'moonbitlang/core/bigint': 'Pinned integer arithmetic.',
  'moonbitlang/core/string': 'Pinned in-memory string operations.',
});

// These pinned primitive modules already belong to the audited stdlib inventory.
// The portable scalar kernel uses their constants and numeric representations,
// not the target-selected stdlib math implementation. Keep this explicit review
// local to that Owner; it grants no environment or generated-runtime authority.
// These packages own live custody, not portable checked-graph proposals. Reject
// them even if a future implementation happens to contain no syntactic FFI.
const hostCustodyPackages = new Set([
  'physical_resources', 'physical_strategy_host', 'physical_host_dispatch',
]);
const numericKernelExternal = Object.freeze({
  'moonbitlang/core/builtin': 'Pinned scalar primitive representations; implicit-runtime and explicit-seed audits remain required.',
  'moonbitlang/core/double': 'Pinned Double constants and representations for the portable scalar kernel.',
  'moonbitlang/core/float': 'Pinned Float constants and representations for the portable scalar kernel.',
  'moonbitlang/core/int': 'Pinned integer representation operations for the portable scalar kernel.',
});
function reviewedExternal(owner, path) {
  if (Object.hasOwn(pureExternal, path)) return pureExternal[path];
  if (owner === 'scalar_numeric_kernel' && Object.hasOwn(numericKernelExternal, path)) {
    return numericKernelExternal[path];
  }
  return undefined;
}

export function tokens(source, sourceCode = false) {
  const result = [];
  let i = 0;
  while (i < source.length) {
    if (/\s/.test(source[i])) { i++; continue; }
    // MoonBit's #| lines are raw string data. Only recognize the literal at
    // the start of an indented source line; attributes and executable code
    // on subsequent lines must still pass the ordinary source audit.
    if (sourceCode && source.startsWith('#|', i) &&
        /^[ \t]*$/.test(source.slice(source.lastIndexOf('\n', i - 1) + 1, i))) {
      const end = source.indexOf('\n', i);
      const stop = end < 0 ? source.length : end;
      result.push({kind: 'string', value: source.slice(i + 2, stop)});
      i = stop;
      continue;
    }
    if (source.startsWith('//', i)) {
      i = source.indexOf('\n', i);
      if (i < 0) break;
      continue;
    }
    if (source.startsWith('/*', i)) {
      let depth = 1; i += 2;
      while (depth && i < source.length) {
        if (source.startsWith('/*', i)) { depth++; i += 2; }
        else if (source.startsWith('*/', i)) { depth--; i += 2; }
        else i++;
      }
      if (depth) throw new Error('UnclosedComment');
      continue;
    }
    if (source[i] === '"' || (sourceCode && source[i] === "'")) {
      const quote = source[i];
      const start = i++;
      while (i < source.length && source[i] !== quote) {
        if (source[i] === '\\') i++;
        i++;
      }
      if (i === source.length) throw new Error('UnclosedString');
      const raw = source.slice(start, ++i);
      result.push({kind:'string', value:sourceCode ? raw.slice(1, -1) : JSON.parse(raw)});
      continue;
    }
    const word = /^[A-Za-z_][A-Za-z_0-9]*/.exec(source.slice(i));
    if (word) { result.push({kind:'word', value:word[0]}); i += word[0].length; continue; }
    result.push({kind:'symbol', value:source[i++]});
  }
  return result;
}

export function packageImports(source) {
  const ts = tokens(source);
  let i = 0;
  const result = [];
  const take = (kind, value) => {
    const t = ts[i++];
    if (!t || t.kind !== kind || (value !== undefined && t.value !== value)) {
      throw new Error(`UnknownManifestSyntax at token ${i - 1}`);
    }
    return t.value;
  };
  const symbol = value => take('symbol', value);
  const peek = value => ts[i]?.value === value;
  while (i < ts.length) {
    const directive = take('word');
    if (directive === 'supported_targets') {
      symbol('=');
      if (take('string') !== '+js+wasm+native') throw new Error('UnsupportedCoreTargets');
    } else if (directive === 'import') {
      symbol('{');
      const imports = [];
      while (!peek('}')) {
        const path = take('string');
        let alias = path.split('/').at(-1);
        if (peek('@')) { symbol('@'); alias = take('word'); }
        imports.push({path, alias});
        if (!peek('}')) symbol(',');
      }
      symbol('}');
      let scope = 'production';
      if (peek('for')) {
        take('word', 'for'); scope = take('string');
        if (!['test', 'wbtest'].includes(scope)) throw new Error('UnknownImportScope');
      }
      result.push(...imports.map(entry => ({...entry, scope})));
    } else if (directive === 'formatter') {
      symbol('('); take('word', 'ignore'); symbol(':'); symbol('[');
      while (!peek(']')) { take('string'); if (!peek(']')) symbol(','); }
      symbol(']'); if (peek(',')) symbol(','); symbol(')');
    } else throw new Error(`UnknownManifestDirective: ${directive}`);
  }
  return result;
}

function inspectSource(source, path) {
  // Foreign declarations and embedded target code remain forbidden. Raw
  // literal data strings and comments do not trigger executable name checks.
  const ts = tokens(source, true);
  const words = ts.filter(t => t.kind !== 'string').map(t => t.value);
  const forbidden = new Set(['extern', 'fetch', 'performance', 'println', 'print',
    'process', 'globalThis', 'require', 'eval', 'crypto']);
  for (const word of words) if (forbidden.has(word)) {
    throw new Error(`CoreEnvironmentAccess: ${path}: ${word}`);
  }
  for (let i = 0; i < ts.length; i++) {
    if (ts[i].kind === 'word' && ts[i].value === 'Date' && ts[i + 1]?.value === '.' && ts[i + 2]?.value === 'now') {
      throw new Error(`CoreEnvironmentAccess: ${path}: Date.now`);
    }
    if (ts[i].kind === 'symbol' && ts[i].value === '#' && !['alias', 'warnings'].includes(ts[i + 1]?.value)) {
      throw new Error(`CoreForeignOrUnknownAttribute: ${path}`);
    }
    if (ts[i].kind === 'symbol' && ts[i].value === '@' && ts[i + 1]?.kind === 'string') {
      throw new Error(`CoreEmbeddedCode: ${path}`);
    }
  }
}

export function inspectCore(root, roots = coreRoots) {
  if (existsSync(join(root, 'moon.mod.json'))) throw new Error('AmbiguousCoreModule');
  const module = tokens(readFileSync(join(root,'moon.mod'),'utf8'));
  const metadata = new Set(['name','version','license','source','preferred_target','supported_targets']);
  let reviewedEsm = false;
  for (let i = 0; i < module.length;) {
    if (module[i]?.kind === 'word' && module[i].value === 'options') {
      // Review only the existing pinned linker's ESM format selection, not a
      // general options object, extra flags, hooks or another module format.
      const literal = [
        ['word', 'options'], ['symbol', '('], ['string', 'link-flags'],
        ['symbol', ':'], ['symbol', '['], ['string', '-js-format'],
        ['symbol', ','], ['string', 'esm'],
      ];
      if (reviewedEsm || !literal.every(([kind, value], offset) =>
        module[i + offset]?.kind === kind && module[i + offset].value === value)) {
        throw new Error('UnauditedCoreModuleDirective');
      }
      i += literal.length;
      if (module[i]?.kind !== 'symbol' || module[i++].value !== ']') {
        throw new Error('UnauditedCoreModuleDirective');
      }
      if (module[i]?.kind === 'symbol' && module[i].value === ',') i++;
      if (module[i]?.kind !== 'symbol' || module[i++].value !== ')') {
        throw new Error('UnauditedCoreModuleDirective');
      }
      reviewedEsm = true;
      continue;
    }
    const [key,equals,value] = module.slice(i,i+3);
    if (key?.kind !== 'word' || !metadata.has(key.value) || equals?.value !== '=' || value?.kind !== 'string') {
      throw new Error('UnauditedCoreModuleDirective');
    }
    if (key.value === 'source' && value.value !== 'src') throw new Error('UnsupportedCoreSourceRoot');
    i += 3;
  }
  const packages = new Map(), external = new Map(), publicImports = [];
  const pending = [...roots];
  while (pending.length) {
    const name = pending.pop();
    if (packages.has(name)) continue;
    if (hostCustodyPackages.has(name)) throw new Error(`HostCustodyCoreDependency: ${name}`);
    if (!/^[a-z][a-z_0-9]*$/.test(name) || /^(duckdb_|connectors_|.*_node$|.*_workers$)/.test(name)) {
      throw new Error(`ConcreteCoreDependency: ${name}`);
    }
    const directory = join(root, 'src', name);
    if (existsSync(join(directory, 'moon.pkg.json'))) {
      throw new Error(`AmbiguousCoreManifest: ${name}`);
    }
    const imports = packageImports(readFileSync(join(directory, 'moon.pkg'), 'utf8'));
    packages.set(name, imports);
    for (const entry of imports.filter(x => x.scope === 'production')) {
      if (entry.path.startsWith('actql/actql/')) pending.push(entry.path.slice(12));
      else {
        const review = reviewedExternal(name, entry.path);
        if (review === undefined) throw new Error(`UnreviewedExternal: ${name}: ${entry.path}`);
        external.set(entry.path, review);
      }
    }
    for (const file of readdirSync(directory)) {
      if (file.endsWith('.mbt') && !/_(?:wb)?test\.mbt$/.test(file)) {
        inspectSource(readFileSync(join(directory, file), 'utf8'), `${name}/${file}`);
      } else if (/\.(?:js|mjs|cjs|c|h|cc|cpp|rs|s|S|o|a|node|so|dylib|dll|wasm)$/.test(file)) {
        throw new Error(`CoreForeignFile: ${name}/${file}`);
      }
    }
    const apiPath = join(directory, 'pkg.generated.mbti');
    if (existsSync(apiPath)) {
      const api = tokens(readFileSync(apiPath, 'utf8'));
      for (const t of api) {
        if (t.kind === 'string' && /(?:\/connectors\/|\/duckdb_|\/[^/]*(?:_node|_workers))/.test(t.value)) {
          throw new Error(`ConcretePublicType: ${name}: ${t.value}`);
        }
      }
      for (let i = 0; i < api.length; i++) {
        if (api[i].kind !== 'word' || api[i].value !== 'import') continue;
        if (api[++i]?.value !== '{') throw new Error(`UnknownPublicImports: ${name}`);
        while (api[++i] && api[i].value !== '}') {
          if (api[i].kind === 'string') publicImports.push([name, api[i].value]);
        }
        if (!api[i]) throw new Error(`UnknownPublicImports: ${name}`);
      }
    }
  }
  for (const [owner, path] of publicImports) {
    // Generated Show/Debug declarations reference this implicit runtime trait;
    // its implementation is separately covered by the pinned stdlib inventory.
    const permitted = path === 'moonbitlang/core/debug' ||
      reviewedExternal(owner, path) !== undefined ||
      path.startsWith('actql/actql/') && packages.has(path.slice(12));
    if (!permitted) throw new Error(`UnreviewedPublicType: ${owner}: ${path}`);
  }
  return {roots:[...roots], packages:[...packages.keys()].sort(), external:Object.fromEntries(external),
    implicitRuntime: 'Pinned MoonBit builtin/compiler runtime: generated JS requires the separate explicit-seed and artifact audit; source import inspection alone does not certify it.'};
}

// Materialize exactly the audited production closure. Test manifests must not
// make the isolated build depend on packages outside that closure.
export function copyProductionCore(root, destination, roots = coreRoots) {
  const audit = inspectCore(root, roots);
  mkdirSync(destination, {recursive: true});
  copyFileSync(join(root, 'moon.mod'), join(destination, 'moon.mod'));
  for (const name of audit.packages) {
    const source = join(root, 'src', name);
    const target = join(destination, 'src', name);
    mkdirSync(target, {recursive: true});
    const imports = packageImports(readFileSync(join(source, 'moon.pkg'), 'utf8'))
      .filter(entry => entry.scope === 'production');
    const manifest = 'supported_targets = "+js+wasm+native"\n' +
      (imports.length ? '\nimport {\n' + imports.map(entry =>
        `  ${JSON.stringify(entry.path)} @${entry.alias},\n`).join('') + '}\n' : '');
    writeFileSync(join(target, 'moon.pkg'), manifest);
    for (const file of readdirSync(source)) {
      if (file.endsWith('.mbt') && !/_(?:wb)?test\.mbt$/.test(file)) {
        copyFileSync(join(source, file), join(target, file));
      }
    }
  }
  return audit;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  console.log(JSON.stringify(inspectCore(root), null, 2));
}
