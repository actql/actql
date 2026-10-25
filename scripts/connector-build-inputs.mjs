// Build-time references to explicitly supplied, already verified packages.
// The caller owns package acquisition, integrity and stable input placement.
// These snapshots are not a new manifest, identity or runtime authority.
import {lstatSync, readFileSync, realpathSync} from 'node:fs';
import {isAbsolute, join, relative, resolve, sep} from 'node:path';
import {tokens} from './portable-core.mjs';
import {checkHostBundle, checkHostProfiles} from './connector-host-bundles.mjs';

const coreNamespace = 'actql/actql';
const identifier = value => typeof value === 'string' && /^[a-z][a-z0-9_]*$/.test(value);
const namespace = value => typeof value === 'string' &&
  /^[a-z][a-z0-9_-]*(?:\/[a-z][a-z0-9_-]*)+$/.test(value);
const version = value => typeof value === 'string' &&
  /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(value);
const contains = (parent, child) => {
  const path = relative(parent, child);
  return path === '' || !isAbsolute(path) && path !== '..' && !path.startsWith('..' + sep);
};
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const shape = (value, required, optional = []) => record(value) &&
  required.every(key => Object.hasOwn(value, key)) &&
  Object.keys(value).every(key => required.includes(key) || optional.includes(key));
const freeze = value => {
  if (record(value) || Array.isArray(value)) {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};

function relativePath(value, allowRoot = false) {
  if (allowRoot && value === '.') return value;
  if (typeof value !== 'string' ||
      !/^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(value) ||
      value.split('/').some(part => part === '.' || part === '..')) {
    throw new Error('Invalid build input relative path');
  }
  return value;
}

function stat(path) {
  try { return lstatSync(path); }
  catch (error) {
    if (error.code === 'ENOENT') return undefined;
    throw error;
  }
}

function ownedPath(root, path, kind, optional = false) {
  relativePath(path, kind === 'directory');
  let current = root;
  const parts = path === '.' ? [] : path.split('/');
  for (let index = 0; index <= parts.length; index++) {
    if (index) current = join(current, parts[index - 1]);
    const info = stat(current);
    if (info === undefined && optional && index === parts.length) return undefined;
    const directory = index < parts.length || kind === 'directory';
    if (!info || info.isSymbolicLink() ||
        !(directory ? info.isDirectory() : info.isFile()) || realpathSync(current) !== current) {
      throw new Error(`Missing, aliased or nonregular build input: ${current}`);
    }
  }
  return current;
}

function supportsJS(value, label) {
  if (value === undefined) return;
  const targets = /^(?:js|wasm|wasm-gc|native)$/.test(value) ? [value]
    : /^(?:\+(?:js|wasm|wasm-gc|native))+$/.test(value) ? value.slice(1).split('+') : [];
  if (!targets.length || new Set(targets).size !== targets.length) {
    throw new Error(`Unsupported target metadata: ${label}`);
  }
  if (!targets.includes('js')) throw new Error(`Incompatible JS target: ${label}`);
}

function reader(source, label) {
  const list = tokens(source);
  let index = 0;
  return {
    done: () => index === list.length,
    peek: value => list[index]?.value === value,
    take(kind, value) {
      const token = list[index++];
      if (!token || token.kind !== kind || (value !== undefined && token.value !== value)) {
        throw new Error(`Unsupported build metadata syntax: ${label}`);
      }
      return token.value;
    },
  };
}

function moduleMetadata(root) {
  if (stat(join(root, 'moon.mod.json'))) throw new Error('Unsupported or ambiguous module metadata');
  const path = ownedPath(root, 'moon.mod', 'file');
  const input = reader(readFileSync(path, 'utf8'), path);
  const result = {dependencies: {}};
  const fields = new Set(['name', 'version', 'source', 'supported_targets',
    'preferred_target', 'license', 'readme', 'repository', 'description']);
  let reviewedEsm = false;
  while (!input.done()) {
    const key = input.take('word');
    if (key === 'import') {
      input.take('symbol', '{');
      while (!input.peek('}')) {
        const pin = input.take('string');
        const at = pin.lastIndexOf('@');
        const name = pin.slice(0, at), pinnedVersion = pin.slice(at + 1);
        if (at < 0 || !namespace(name) || !version(pinnedVersion) ||
            Object.hasOwn(result.dependencies, name)) throw new Error('Invalid or duplicate module dependency pin');
        result.dependencies[name] = pinnedVersion;
        if (!input.peek('}')) input.take('symbol', ',');
      }
      input.take('symbol', '}');
    } else if (key === 'options') {
      // The current pinned linker selects CJS before module flags. This exact
      // existing ESM selection is format metadata, not a dependency/build hook
      // or permission to accept other module options.
      if (reviewedEsm) throw new Error('Duplicate reviewed module format');
      for (const [kind, value] of [
        ['symbol', '('], ['string', 'link-flags'], ['symbol', ':'],
        ['symbol', '['], ['string', '-js-format'], ['symbol', ','],
        ['string', 'esm'],
      ]) input.take(kind, value);
      input.take('symbol', ']');
      if (input.peek(',')) input.take('symbol', ',');
      input.take('symbol', ')');
      reviewedEsm = true;
    } else if (fields.has(key) && !Object.hasOwn(result, key)) {
      input.take('symbol', '=');
      result[key] = input.take('string');
    } else throw new Error(`Unsupported or duplicate module metadata: ${key}`);
  }
  return result;
}

// Inspect only the selected package's metadata. The compiler still owns
// parsing and type checking; no transitive source discovery happens here.
function packageMetadata(path) {
  const input = reader(readFileSync(path, 'utf8'), path);
  const imports = [];
  let target;
  let fileTargets = false;
  while (!input.done()) {
    const directive = input.take('word');
    if (directive === 'supported_targets') {
      if (target !== undefined) throw new Error('Duplicate package target metadata');
      input.take('symbol', '=');
      target = input.take('string');
    } else if (directive === 'import') {
      input.take('symbol', '{');
      while (!input.peek('}')) {
        imports.push(input.take('string'));
        if (input.peek('@')) { input.take('symbol', '@'); input.take('word'); }
        if (!input.peek('}')) input.take('symbol', ',');
      }
      input.take('symbol', '}');
      if (input.peek('for')) {
        input.take('word', 'for');
        if (!['test', 'wbtest'].includes(input.take('string'))) throw new Error('Unsupported package import scope');
      }
    } else if (directive === 'pkgtype') {
      input.take('symbol', '('); input.take('word', 'kind'); input.take('symbol', ':');
      if (!['executable', 'foreign_library', 'library'].includes(input.take('string'))) {
        throw new Error('Unsupported package kind');
      }
      if (input.peek(',')) input.take('symbol', ',');
      input.take('symbol', ')');
    } else if (directive === 'options') {
      // File selection does not introduce imports, dependencies or build hooks.
      // Accept only the existing literal per-file target grammar; the compiler
      // remains responsible for source selection and source existence.
      if (fileTargets) throw new Error('Duplicate package file-target options');
      fileTargets = true;
      input.take('symbol', '('); input.take('word', 'targets'); input.take('symbol', ':');
      input.take('symbol', '{');
      const files = new Set();
      while (!input.peek('}')) {
        const file = input.take('string');
        if (!/^[A-Za-z0-9_][A-Za-z0-9_.-]*\.mbt$/.test(file) || files.has(file)) {
          throw new Error('Invalid or duplicate package file target');
        }
        files.add(file);
        input.take('symbol', ':'); input.take('symbol', '[');
        const first = input.take('string');
        let selected = first;
        if (first === 'not') {
          input.take('symbol', ','); selected = input.take('string');
        }
        if (!['js', 'wasm', 'wasm-gc', 'native'].includes(selected)) {
          throw new Error('Unsupported package file target');
        }
        if (input.peek(',')) input.take('symbol', ',');
        input.take('symbol', ']');
        if (!input.peek('}')) input.take('symbol', ',');
      }
      input.take('symbol', '}');
      if (input.peek(',')) input.take('symbol', ',');
      input.take('symbol', ')');
    } else if (directive === 'formatter') {
      input.take('symbol', '('); input.take('word', 'ignore'); input.take('symbol', ':');
      input.take('symbol', '[');
      while (!input.peek(']')) {
        input.take('string');
        if (!input.peek(']')) input.take('symbol', ',');
      }
      input.take('symbol', ']');
      if (input.peek(',')) input.take('symbol', ',');
      input.take('symbol', ')');
    } else throw new Error(`Unsupported package metadata: ${directive}`);
  }
  supportsJS(target, path);
  return imports;
}

export function resolveConnectorBuildInputs(configuration) {
  if (!shape(configuration, ['target', 'modules', 'host', 'connectors']) ||
      configuration.target !== 'js' || !Array.isArray(configuration.modules) ||
      !Array.isArray(configuration.connectors)) throw new Error('Invalid Connector build inputs');
  const modules = new Map();
  for (const pin of configuration.modules) {
    if (!shape(pin, ['namespace', 'version', 'root']) || !namespace(pin.namespace) ||
        !version(pin.version) || typeof pin.root !== 'string' || !isAbsolute(pin.root)) {
      throw new Error('Invalid explicit module pin');
    }
    if (pin.namespace === 'moonbitlang/core' || pin.namespace.startsWith('moonbitlang/core/')) {
      throw new Error('Compiler standard library cannot be supplied or shadowed');
    }
    const root = resolve(pin.root);
    if (modules.has(pin.namespace) || [...modules.values()].some(module =>
      contains(module.root, root) || contains(root, module.root) ||
      module.namespace.startsWith(pin.namespace + '/') ||
      pin.namespace.startsWith(module.namespace + '/'))) throw new Error('Duplicate or overlapping module ownership');
    ownedPath(root, '.', 'directory');
    const metadata = moduleMetadata(root);
    if (metadata.name !== pin.namespace || metadata.version !== pin.version) {
      throw new Error(`Module identity mismatch: ${pin.namespace}`);
    }
    supportsJS(metadata.supported_targets, pin.namespace);
    const source = metadata.source ?? '.';
    const sourceRoot = ownedPath(root, source, 'directory');
    modules.set(pin.namespace, freeze({...pin, root, source, sourceRoot,
      dependencies: metadata.dependencies}));
  }
  const host = modules.get(configuration.host), core = modules.get(coreNamespace);
  if (!host || !core || host === core) throw new Error('A separate explicit Host module and Core are required');
  for (const module of modules.values()) {
    for (const [name, pinnedVersion] of Object.entries(module.dependencies)) {
      if (!modules.has(name) || modules.get(name).version !== pinnedVersion) {
        throw new Error(`Missing or mismatched declared module dependency: ${module.namespace} -> ${name}`);
      }
    }
  }
  const checked = new Set(), checking = new Set();
  const checkGraph = name => {
    if (checking.has(name)) throw new Error('Cyclic module dependency graph');
    if (checked.has(name)) return;
    checking.add(name);
    for (const dependency of Object.keys(modules.get(name).dependencies)) checkGraph(dependency);
    checking.delete(name); checked.add(name);
  };
  for (const name of modules.keys()) checkGraph(name);
  const canImport = (from, to) => {
    if (!modules.has(from) || (from !== to && !Object.hasOwn(modules.get(from).dependencies, to))) {
      throw new Error(`Undeclared module dependency: ${from} -> ${to}`);
    }
  };
  canImport(host.namespace, coreNamespace);
  const ownerOf = name => {
    if (!namespace(name)) throw new Error('Invalid package identifier');
    const owner = [...modules.values()].find(module =>
      name === module.namespace || name.startsWith(module.namespace + '/'));
    if (!owner) throw new Error(`Unavailable package namespace: ${name}`);
    return owner;
  };
  const resolvePackage = (name, fromNamespace = host.namespace) => {
    const owner = ownerOf(name);
    canImport(fromNamespace, owner.namespace);
    const suffix = name.slice(owner.namespace.length + 1);
    const directory = ownedPath(owner.sourceRoot, suffix || '.', 'directory');
    if (stat(join(directory, 'moon.pkg.json'))) throw new Error('Unsupported or ambiguous package metadata');
    const path = ownedPath(directory, 'moon.pkg', 'file');
    for (const imported of packageMetadata(path)) {
      if (!namespace(imported)) throw new Error('Invalid package dependency identifier');
      // The standard library is supplied by the pinned compiler toolchain.
      if (imported.startsWith('moonbitlang/core/')) continue;
      canImport(owner.namespace, ownerOf(imported).namespace);
    }
    return path;
  };
  const resolveFile = (name, path) => {
    const module = modules.get(name);
    if (!module) throw new Error(`Unavailable module namespace: ${name}`);
    return ownedPath(module.root, path, 'file');
  };
  const outputPath = path => {
    relativePath(path);
    ownedPath(host.root, '.', 'directory');
    const parts = path.split('/');
    let current = host.root;
    for (let index = 0; index < parts.length; index++) {
      current = join(current, parts[index]);
      const info = stat(current);
      if (info === undefined) break;
      if (info.isSymbolicLink() || realpathSync(current) !== current ||
          !(index === parts.length - 1 ? info.isFile() : info.isDirectory())) {
        throw new Error(`Aliased or invalid Host output: ${current}`);
      }
    }
    return join(host.root, path);
  };
  const entries = [], computeEntries = [], nodeEntries = [], hostEntries = [], names = new Set();
  for (const selected of configuration.connectors) {
    if (!shape(selected, ['name', 'module', 'directory'], ['revision']) ||
        !identifier(selected.name) || names.has(selected.name) || !modules.has(selected.module)) {
      throw new Error('Invalid or duplicate Connector selection');
    }
    names.add(selected.name);
    const module = modules.get(selected.module);
    canImport(host.namespace, module.namespace);
    if (module === host) throw new Error('Connector implementation must be separate from Host composition');
    const pending = Object.keys(core.dependencies), visited = new Set();
    while (pending.length) {
      const name = pending.pop();
      if (name === module.namespace) throw new Error('Core cannot depend on a selected external Connector');
      if (visited.has(name)) continue;
      visited.add(name);
      pending.push(...Object.keys(modules.get(name).dependencies));
    }
    const directory = ownedPath(module.root, selected.directory, 'directory');
    const entry = {name: selected.name, namespace: module.namespace,
      root: module.root, sourceRoot: module.sourceRoot, directory, manifests: {}};
    for (const role of ['compute', 'node', 'host']) {
      const path = ownedPath(directory, `${role}-bundle.json`, 'file', true);
      if (path === undefined) continue;
      entry[role] = path;
      entry.manifests[role] = JSON.parse(readFileSync(path, 'utf8'));
      if (!record(entry.manifests[role])) throw new Error(`Invalid ${role} bundle manifest`);
    }
    if (!Object.keys(entry.manifests).length) throw new Error('Missing selected Connector manifest');
    if (entry.manifests.host !== undefined) {
      let providerPackagePath;
      const checkedHost = checkHostBundle(module.root, selected.name, entry.host, {
        manifest: entry.manifests.host,
        resolveProviderPackage: bundle => {
          providerPackagePath = resolvePackage(`${module.namespace}/${bundle}`);
          return providerPackagePath;
        },
        resolveFile: path => resolveFile(module.namespace, path),
      });
      if (selected.revision !== undefined && selected.revision !== checkedHost.revision) {
        throw new Error('Host Connector identity mismatch');
      }
      hostEntries.push({...checkedHost, namespace: module.namespace, root: module.root,
        sourceRoot: module.sourceRoot,
        ...(checkedHost.providerBundle === undefined ? {} : {
          providerPackage: `${module.namespace}/${checkedHost.providerBundle}`, providerPackagePath})});
      entry.revision = checkedHost.revision;
    } else if (selected.revision !== undefined) {
      throw new Error('Connector revision requires an existing Host declaration');
    }
    const compute = entry.manifests.compute;
    if (compute !== undefined) {
      const packagePrefix = module === core ? `${coreNamespace}/connectors/${selected.name}` : module.namespace;
      if (typeof compute.package !== 'string' ||
          !(compute.package === packagePrefix || compute.package.startsWith(packagePrefix + '/'))) {
        throw new Error('Compute package does not belong to its Connector');
      }
      const results = compute.dispatch_result === 'Unit' ? []
        : Array.isArray(compute.dispatch_result) ? compute.dispatch_result : [compute.dispatch_result];
      const references = [compute.package, ...[
        compute.dispatch_error, compute.estimate_error, ...results,
        compute.managed_dispatch_result, compute.managed_start_result, compute.managed_start_error,
      ].filter(value => value !== undefined).map(value => value?.package)];
      for (const name of references) {
        resolvePackage(name, module.namespace);
        canImport(host.namespace, ownerOf(name).namespace);
      }
      computeEntries.push({name: selected.name, manifest: compute, packagePrefix});
    }
    if (entry.manifests.node !== undefined) {
      const node = entry.manifests.node;
      if (!compute || !shape(node, ['strategy']) ||
          !shape(node.strategy, ['module', 'export']) ||
          typeof node.strategy.module !== 'string' || !node.strategy.module.endsWith('.mjs') ||
          typeof node.strategy.export !== 'string' || !/^[A-Za-z_]\w*$/.test(node.strategy.export)) {
        throw new Error('Invalid Node strategy contribution');
      }
      if (module === core &&
          node.strategy.module !== `adapters/connectors/${selected.name}/node/strategy-bundle.mjs` &&
          !/^adapters\/[a-z0-9_-]+\/strategy-bundle\.mjs$/.test(node.strategy.module)) {
        throw new Error('Node strategy does not belong to its Connector');
      }
      nodeEntries.push({name: selected.name,
        modulePath: resolveFile(module.namespace, node.strategy.module),
        symbol: node.strategy.export, compute});
    }
    entries.push(entry);
  }
  checkHostProfiles(hostEntries);
  return freeze({target: 'js', host, coreRoot: core.root,
    modules: [...modules.values()], entries, computeEntries, nodeEntries, hostEntries,
    resolvePackage, packagePath: resolvePackage, resolveFile, outputPath});
}
