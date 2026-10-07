import {lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildSync} from 'esbuild';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const destination = join(root, 'packages/local-node');
const inputs = localNodePackageInputs(root);
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
const entries = inputs.adapterEntries;
const graph = buildSync({entryPoints: entries, bundle: true,
  packages: 'external', platform: 'node', format: 'esm', target: 'node22',
  metafile: true, write: false, absWorkingDir: root,
  outdir: join(root, '_build/local-node-adapter-graph')});
const sourcePaths = Object.keys(graph.metafile.inputs)
  .filter(path => path.startsWith('adapters/')).sort();
if (sourcePaths.length < entries.length ||
    entries.some(path => !sourcePaths.includes(path))) {
  throw new Error('IncompleteLocalNodeAdapterGraph');
}
// URL-referenced optional Table I/O is not an esbuild JS import. Preserve its
// reviewed finite worker dependency set and pinned installation requirements,
// not tests, fixtures, virtualenvs or generated Catalog files.
sourcePaths.push(...['catalog.py', 'custody.py', 'physical.py', 'process_worker.py',
  'requirements.in', 'requirements.lock', 'README.md']
  .map(name => `adapters/table-iceberg/${name}`));
const expected = new Set();
for (const path of sourcePaths) {
  const output = join(destination, path);
  let bytes = readFileSync(join(root, path));
  if (path.endsWith('.mjs')) {
    const code = rewriteLocalNodePackageImports(bytes.toString('utf8'), path);
    bytes = Buffer.from(code);
  }
  expected.add(path);
  if (process.argv.includes('--check')) {
    if (!readFileSync(output).equals(bytes)) {
      throw new Error(`StaleLocalNodeAdapter:${path}`);
    }
  } else {
    mkdirSync(join(output, '..'), {recursive: true});
    writeFileSync(output, bytes);
  }
}
const walk = (directory, prefix = '') => {
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) walk(join(directory, entry.name), path);
    else if (!expected.has(`adapters/${path}`)) {
      throw new Error(`StaleLocalNodeAdapter:${path}`);
    }
  }
};
walk(join(destination, 'adapters'));
for (const path of inputs.dataFiles) {
  const bytes = readFileSync(join(root, path));
  const output = join(destination, path);
  if (process.argv.includes('--check')) {
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
