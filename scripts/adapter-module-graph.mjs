// One import graph resolver for packaging and Connector implementation binding.
// URL-referenced I/O assets still come from the checked Host manifest.
import {join} from 'node:path';
import {buildSync} from 'esbuild';

// Preserve every resolved source input before a caller applies an ownership
// projection. Bare package imports remain external, as in ordinary packaging.
export function localModuleGraphInputs(root, entries) {
  entries = [...new Set(entries)];
  const graph = buildSync({entryPoints: entries, bundle: true,
    packages: 'external', platform: 'node', format: 'esm', target: 'node22',
    metafile: true, write: false, absWorkingDir: root,
    outdir: join(root, '_build/local-node-adapter-graph')});
  return Object.keys(graph.metafile.inputs).sort();
}

// Packaging and Connector binding intentionally own only adapter inputs.
// Keep this projection and its entry validation unchanged.
export function adapterModuleGraph(root, entries) {
  entries = [...new Set(entries)];
  const paths = localModuleGraphInputs(root, entries)
    .filter(path => path.startsWith('adapters/'));
  if (paths.length < entries.length || entries.some(path => !paths.includes(path))) {
    throw new Error('IncompleteLocalNodeAdapterGraph');
  }
  return paths;
}
