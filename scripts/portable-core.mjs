// Inspect the selected literal metadata; the pinned compiler owns Moon syntax
// and target semantics. Unknown forms are errors, not ignored dependencies.
// Build-time tooling may use Node I/O.
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

// Source overlays may request spans; ordinary inspection retains its exact
// existing token DATA and refusal rules.
export function tokens(source, sourceCode = false, withRanges = false) {
  const result = [];
  const push = (token, begin, end) => result.push(withRanges ? {...token, begin, end} : token);
  let i = 0;
  while (i < source.length) {
    if (/\s/.test(source[i])) { i++; continue; }
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
    if (sourceCode && source.startsWith('$|', i)) {
      // Interpolation contains executable expressions. Do not hide them as DATA.
      throw new Error('UnsupportedInterpolatedMultilineString');
    }
    if (sourceCode && source.startsWith('#|', i) &&
        /^[\t ]*$/.test(source.slice(source.lastIndexOf('\n', i - 1) + 1, i))) {
      // A leading #| line is raw DATA, including quotes, comments and \{...}.
      // Only that physical line is opaque; following source is still inspected.
      const start = i + 2;
      const newline = source.indexOf('\n', start);
      i = newline < 0 ? source.length : newline;
      push({kind:'string', value:source.slice(start, i)}, start - 2, i);
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
      push({kind:'string', value:sourceCode ? raw.slice(1, -1) : JSON.parse(raw)}, start, i);
      continue;
    }
    const word = /^[A-Za-z_][A-Za-z_0-9]*/.exec(source.slice(i));
    if (word) { const begin = i; i += word[0].length; push({kind:'word', value:word[0]}, begin, i); continue; }
    const begin = i;
    push({kind:'symbol', value:source[i++]}, begin, i);
  }
  return result;
}

// One reviewed module-level linker spelling. This is metadata inspection,
// not a general options parser or authority to change compiler/target policy.
export function reviewedEsmModuleOptionEnd(list, start) {
  const literal = [
    ['word', 'options'], ['symbol', '('], ['string', 'link-flags'],
    ['symbol', ':'], ['symbol', '['], ['string', '-js-format'],
    ['symbol', ','], ['string', 'esm'], ['symbol', ']'],
  ];
  if (!literal.every(([kind, value], offset) =>
    list[start + offset]?.kind === kind && list[start + offset].value === value)) {
    return undefined;
  }
  let end = start + literal.length;
  // The pinned formatter may add one final argument comma, not an array
  // element, another option, hook or flag.
  if (list[end]?.kind === 'symbol' && list[end].value === ',') end++;
  return list[end]?.kind === 'symbol' && list[end].value === ')' ? end + 1 : undefined;
}

// Read the existing literal target clause as compiler-owned DATA. Neither
// consumer evaluates its string expressions or uses them to hide dependencies.
export function readPackageTargetOptions({take, peek}) {
  const symbol = value => take('symbol', value);
  symbol('('); take('word', 'targets'); symbol(':'); symbol('{');
  const targets = [];
  const files = new Set();
  while (!peek('}')) {
    const file = take('string');
    if (files.has(file)) throw new Error('UnknownManifestOptions: duplicate filename');
    files.add(file);
    symbol(':'); symbol('[');
    const expression = [];
    while (!peek(']')) {
      expression.push(take('string'));
      if (!peek(']')) symbol(',');
    }
    symbol(']');
    targets.push([file, expression]);
    if (!peek('}')) symbol(',');
  }
  symbol('}'); if (peek(',')) symbol(','); symbol(')');
  return targets;
}

function packageMetadata(source) {
  const ts = tokens(source);
  let i = 0;
  const result = [];
  let targets = null;
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
        let alias;
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
    } else if (directive === 'options') {
      // Extract only the existing literal filename -> string-array metadata.
      // Do not evaluate target expressions or exempt any source/dependency from
      // inspection. The pinned compiler owns their meaning and validation.
      if (targets !== null) throw new Error('UnknownManifestOptions: duplicate targets');
      targets = readPackageTargetOptions({take, peek});
    } else if (directive === 'formatter') {
      symbol('('); take('word', 'ignore'); symbol(':'); symbol('[');
      while (!peek(']')) { take('string'); if (!peek(']')) symbol(','); }
      symbol(']'); if (peek(',')) symbol(','); symbol(')');
    } else throw new Error(`UnknownManifestDirective: ${directive}`);
  }
  return {imports: result, targets};
}

// Dependency inspection keeps the established resolved-alias projection. The
// materializer separately retains whether the author declared an alias: an
// invented explicit builtin alias changes strict compiler admission.
export function packageImports(source) {
  return packageMetadata(source).imports.map(({path, alias, scope}) =>
    ({path, alias: alias ?? path.split('/').at(-1), scope}));
}

function inspectSource(source, path) {
  // Literal DATA and comments do not trigger name checks. Foreign declarations,
  // embedded target code and unsupported interpolated lines still fail closed.
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
      const end = reviewedEsmModuleOptionEnd(module, i);
      if (reviewedEsm || end === undefined) {
        throw new Error('UnauditedCoreModuleDirective');
      }
      reviewedEsm = true;
      i = end;
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
    // This existing out-parameter retains the same reader-collected Inputs on
    // failure. The pinned Ref representation is in-memory DATA, not an owned
    // proof or Host port. Its review does not permit another Owner or import.
    const collectedInputsRef = owner === 'pipeline_check_context' &&
      path === 'moonbitlang/core/ref';
    // Source's existing native reader writes only a maximum key length to
    // its original Ref[Int] out-parameter. The pinned Ref contains mutable
    // in-memory DATA only; this review adds no runtime import or Host port.
    const capturedKeyExtentRef = owner === 'source_value' &&
      path === 'moonbitlang/core/ref';
    // The remaining checker optionally records its once-only call count in
    // the caller's Ref[Int64]. This pinned mutable DATA is neither a Host
    // callback nor an authority, and grants no other Owner a Ref import.
    const checkerCallCountRef = owner === 'program_check' &&
      path === 'moonbitlang/core/ref';
    const permitted = path === 'moonbitlang/core/debug' || collectedInputsRef || capturedKeyExtentRef || checkerCallCountRef ||
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
    const metadata = packageMetadata(readFileSync(join(source, 'moon.pkg'), 'utf8'));
    const imports = metadata.imports.filter(entry => entry.scope === 'production');
    const files = readdirSync(source);
    const manifest = 'supported_targets = "+js+wasm+native"\n' +
      (imports.length ? '\nimport {\n' + imports.map(entry =>
        `  ${JSON.stringify(entry.path)}${entry.alias === undefined ? '' : ` @${entry.alias}`},\n`).join('') + '}\n' : '');
    // Preserve compiler-owned target DATA for every copied production file.
    // Remove only entries for actual test files that this existing copier omits.
    // Unknown filenames stay present so copying cannot hide compiler diagnostics.
    const targets = metadata.targets?.filter(([file]) =>
      !files.includes(file) || !/_(?:wb)?test\.mbt$/.test(file));
    const options = targets === undefined ? '' : '\noptions(targets: {\n' +
      targets.map(([file, expression]) =>
        `  ${JSON.stringify(file)}: ${JSON.stringify(expression)},\n`).join('') + '})\n';
    writeFileSync(join(target, 'moon.pkg'), manifest + options);
    for (const file of files) {
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
