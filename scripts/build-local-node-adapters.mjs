import {lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {isAbsolute, join, relative, resolve, sep} from 'node:path';
import {isBuiltin} from 'node:module';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {build} from 'esbuild';
import {adapterModuleGraph} from './adapter-module-graph.mjs';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {buildNodeDirectoryNative} from './build-node-directory-native.mjs';
import {initialControlPackageOriginal, renderInitialControlPackageOriginal}
  from './initial-control-package-images.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const inside = (root, path) => {
  const suffix = relative(root, path);
  return suffix === '' || !isAbsolute(suffix) && suffix !== '..' && !suffix.startsWith('..' + sep);
};

// Validate exact declared package exports without loading a dependency or
// treating a package name as permission to copy its checkout source.
function declaredLocalNodePackageImport(inputs) {
  const resolved = inputs.buildInputs;
  const core = resolved.modules.find(module => module.root === inputs.coreRoot);
  const read = path => JSON.parse(readFileSync(resolved.resolveFile(core.namespace, path), 'utf8'));
  const local = read('packages/local-node/package.json');
  const manifests = new Map();
  return (specifier, originalSource) => {
    const match = /^(@[a-z0-9_-]+\/[a-z0-9_-]+)(\/[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*)?$/u.exec(specifier);
    if (!match || match[2]?.split('/').some(part => part === '.' || part === '..')) return false;
    const [, name, suffix = ''] = match;
    // Keep the existing self interface and optional native peer entrances.
    if (name === '@duckdb/node-api') return originalSource === undefined &&
      Object.hasOwn(local.peerDependencies ?? {}, name) && ['', '/package.json'].includes(suffix);
    const self = name === local.name;
    if (self ? suffix !== '/connector-installation'
      : !Object.hasOwn(local.dependencies ?? {}, name) || !name.startsWith('@actql/')) return false;
    const directory = 'packages/' + name.slice('@actql/'.length);
    if (!manifests.has(name)) manifests.set(name, self ? local : read(directory + '/package.json'));
    const manifest = manifests.get(name);
    if (manifest.name !== name) return false;
    const key = suffix ? '.' + suffix : '.';
    if (!Object.hasOwn(manifest.exports ?? {}, key)) return false;
    const entry = manifest.exports[key];
    // The existing workspace exports use a literal or types/default pair.
    // Do not implement wildcard or conditional export resolution here.
    const target = typeof entry === 'string' ? entry : entry?.default;
    if (typeof target !== 'string' || !target.startsWith('./')) return false;
    const path = resolved.resolveFile(core.namespace, directory + '/' + target.slice(2));
    return originalSource === undefined || path === originalSource;
  };
}

export async function inspectExternalLocalNodeAdapterGraph(inputs) {
  const resolved = inputs.buildInputs;
  const publicPackage = declaredLocalNodePackageImport(inputs);
  const coreTable = join(inputs.coreRoot, inputs.installationTable.destination);
  const coreRuntime = join(inputs.coreRoot, '_build/js/release/build');
  const resolveInput = path => {
    if (path === coreTable) path = inputs.installationTable.source;
    const owner = resolved.modules.find(module => inside(module.root, path));
    if (owner === undefined) throw new Error(`EscapedLocalNodeAdapterInput:${path}`);
    return resolved.resolveFile(owner.namespace, relative(owner.root, path).split(sep).join('/'));
  };
  return build({entryPoints: inputs.adapterInputs.map(entry => entry.source),
    bundle: true, platform: 'node', format: 'esm', target: 'node22',
    metafile: true, write: false, absWorkingDir: resolved.host.root,
    outdir: join(resolved.host.root, '_build/local-node-adapter-graph'),
    plugins: [{name: 'resolved-local-node-inputs', setup(builder) {
      builder.onResolve({filter: /.*/}, args => {
        const importerOwner = args.importer
          ? resolved.modules.find(module => inside(module.root, args.importer)) : undefined;
        // This SDK seam is exported for the Core Host's original snapshot,
        // never as an external Connector interface merely because it exists.
        if (/^@actql\/sdk\/_internal(?:\/|$)/u.test(args.path) && importerOwner?.root !== inputs.coreRoot) {
          throw new Error(`UndeclaredLocalNodeDependency:${args.path}`);
        }
        if (isBuiltin(args.path) || publicPackage(args.path)) return {path: args.path, external: true};
        if (args.kind === 'entry-point') return {path: resolveInput(resolve(args.path))};
        if (!/^\.\.?\//u.test(args.path)) throw new Error(`UndeclaredLocalNodeDependency:${args.path}`);
        const url = new URL(args.path, pathToFileURL(args.importer));
        if (url.search || url.hash) throw new Error('NonconcreteLocalNodeAdapterImport');
        const path = fileURLToPath(url);
        const targetOwner = resolved.modules.find(module => inside(module.root, path));
        const tableEdge = args.importer === inputs.installationTable.source &&
          inputs.installations.some(entry => [entry.source, entry.effect]
            .some(role => role?.modulePath === path));
        if (!importerOwner || !targetOwner || importerOwner.root !== targetOwner.root && !tableEdge) {
          throw new Error(`CrossOwnerLocalNodeAdapterImport:${args.path}`);
        }
        if (importerOwner.root !== inputs.coreRoot && !tableEdge) {
          const ownEntry = inputs.installations.find(entry =>
            inside(join(entry.root, 'adapters/connectors', entry.name), args.importer));
          if (!ownEntry || !inside(join(ownEntry.root, 'adapters/connectors', ownEntry.name), path) &&
              !ownEntry.assetSources.some(asset => asset.sourcePath === path)) {
            throw new Error(`UndeclaredLocalNodeAdapterHelper:${args.path}`);
          }
        }
        const publicImport = importerOwner.root === inputs.coreRoot
          ? rewriteLocalNodePackageImports(JSON.stringify(args.path), args.importer) : JSON.stringify(args.path);
        if (publicImport !== JSON.stringify(args.path)) {
          const name = JSON.parse(publicImport);
          if (!publicPackage(name, path)) throw new Error(`UndeclaredLocalNodeDependency:${name}`);
          return {path: name, external: true};
        }
        if (inside(coreRuntime, path)) {
          const file = relative(coreRuntime, path).split(sep).join('/');
          if (!inputs.runtimeFiles.includes(file)) throw new Error(`UndeclaredLocalNodeRuntime:${file}`);
          return {path: args.path, external: true};
        }
        return {path: resolveInput(path)};
      });
    }}]});
}

// Packaging and installed-interface checks use the same resolved copy inputs.
// This only inspects the existing graph; it does not write package output.
export async function localNodeAdapterSourceInputs({root = repository, inputs = localNodePackageInputs(root)} = {}) {
  const external = inputs.buildInputs, entries = inputs.adapterEntries;
  const sourcePaths = external === undefined
    ? adapterModuleGraph(root, entries).map(path => ({path, source: join(root, path)}))
    : Object.keys((await inspectExternalLocalNodeAdapterGraph(inputs)).metafile.inputs)
      .map(path => {
        const source = resolve(root, path);
        return {source, path: inputs.destinationForAdapter(source)};
      });
  if (sourcePaths.length < entries.length ||
      entries.some(path => !sourcePaths.some(entry => entry.path === path))) {
    throw new Error('IncompleteLocalNodeAdapterGraph');
  }
  sourcePaths.push(...(external === undefined
    ? inputs.dataFiles.filter(path => path.startsWith('adapters/'))
      .map(path => ({path, source: join(root, path)}))
    : inputs.dataInputs.filter(entry => entry.destination.startsWith('adapters/'))
      .map(entry => ({path: entry.destination, source: entry.source}))));
  return sourcePaths;
}

export async function buildLocalNodeAdapters({root = repository,
  destination = join(root, 'packages/local-node'), inputs = localNodePackageInputs(root), check = false} = {}) {
const external = inputs.buildInputs;
// Validate the publishable data directory before writing through any existing
// path. In particular, never follow an old symlink before reporting it stale.
const expectedConnectorData = new Set(inputs.dataFiles.filter(path =>
  path.startsWith('src/connectors/')));
const stat = path => {
  try { return lstatSync(join(destination, path)); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
};
const checkConnectorData = (path = 'src/connectors') => {
  const info = stat(path);
  if (info === undefined) return;
  if (!info.isDirectory()) throw new Error(`StaleLocalNodeConnectorData:${path}`);
  for (const entry of readdirSync(join(destination, path), {withFileTypes: true})) {
    const child = `${path}/${entry.name}`;
    if (entry.isDirectory()) checkConnectorData(child);
    else if (!entry.isFile() || !expectedConnectorData.has(child)) {
      throw new Error(`StaleLocalNodeConnectorData:${child}`);
    }
  }
};
const dataParent = stat('src');
if (dataParent && !dataParent.isDirectory()) {
  throw new Error('StaleLocalNodeConnectorData:src');
}
checkConnectorData();
// Physical I/O assets use the same finite Connector-owned inventory as
// installation. No retired Table paths or unrelated worker files are copied.
const sourcePaths = await localNodeAdapterSourceInputs({root, inputs});
// Reject aliased destinations before copying any adapter or physical asset.
for (const {path} of sourcePaths) {
  const parts = path.split('/');
  for (let index = 1; index <= parts.length; index++) {
    const child = parts.slice(0, index).join('/');
    const info = stat(child);
    if (info !== undefined && (index === parts.length ? !info.isFile() : !info.isDirectory())) {
      throw new Error(`StaleLocalNodeAdapter:${child}`);
    }
  }
}
const expected = new Set();
const owners = new Map();
for (const entry of sourcePaths) {
  const prior = owners.get(entry.path);
  if (prior !== undefined && prior !== entry.source) throw new Error(`ConflictingLocalNodeDestination:${entry.path}`);
  owners.set(entry.path, entry.source);
  expected.add(entry.path);
  if (external !== undefined) external.outputPath(relative(external.host.root, join(destination, entry.path)));
}
if (external !== undefined) {
  for (const entry of inputs.dataInputs) external.outputPath(relative(external.host.root, join(destination, entry.destination)));
}
if (stat('adapters') !== undefined) walk(join(destination, 'adapters'));
const outputs = new Map();
for (const {path, source} of sourcePaths) {
  let bytes = external !== undefined && path === inputs.installationTable.destination
    ? Buffer.from(inputs.installationTable.render(destination)) : readFileSync(source);
  if (path.endsWith('.mjs') && (external === undefined || inside(inputs.coreRoot, source))) {
    const code = rewriteLocalNodePackageImports(bytes.toString('utf8'), path);
    bytes = Buffer.from(code);
  }
  outputs.set(path, bytes);
}
const dataInputs = external === undefined
  ? inputs.dataFiles.map(path => ({source: join(root, path), destination: path})) : inputs.dataInputs;
for (const entry of dataInputs) outputs.set(entry.destination, readFileSync(entry.source));
const nativeOutputs = external === undefined ? buildNodeDirectoryNative({root, destination, check}) : new Map();
if (outputs.has(initialControlPackageOriginal)) {
  outputs.set(initialControlPackageOriginal,
    renderInitialControlPackageOriginal({root, destination, inputs, outputs, nativeOutputs}));
}
for (const {path} of sourcePaths) {
  const output = join(destination, path), bytes = outputs.get(path);
  expected.add(path);
  if (check) {
    if (!readFileSync(output).equals(bytes)) {
      throw new Error(`StaleLocalNodeAdapter:${path}`);
    }
  } else {
    mkdirSync(join(output, '..'), {recursive: true});
    writeFileSync(output, bytes);
  }
}
function walk(directory, prefix = '') {
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) walk(join(directory, entry.name), path);
    else if (!expected.has(`adapters/${path}`)) {
      throw new Error(`StaleLocalNodeAdapter:${path}`);
    }
  }
}
walk(join(destination, 'adapters'));
for (const entry of dataInputs) {
  const path = entry.destination;
  const bytes = outputs.get(path);
  const output = join(destination, path);
  if (check) {
    if (!readFileSync(output).equals(bytes)) {
      throw new Error(`StaleLocalNodeContract:${path}`);
    }
  } else {
    mkdirSync(join(output, '..'), {recursive: true});
    writeFileSync(output, bytes);
  }
}
// This generated directory is published wholesale. Refuse a declaration
// left behind by a removed or renamed manifest asset, even during prepack.
checkConnectorData();
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await buildLocalNodeAdapters({check: process.argv.includes('--check')});
}
