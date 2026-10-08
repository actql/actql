// One import graph resolver for packaging and Connector implementation binding.
// URL-referenced I/O assets still come from the checked Host manifest.
import {join} from 'node:path';
import {buildSync} from 'esbuild';

export function adapterModuleGraph(root, entries) {
  entries = [...new Set(entries)];
  const graph = buildSync({entryPoints: entries, bundle: true,
    packages: 'external', platform: 'node', format: 'esm', target: 'node22',
    metafile: true, write: false, absWorkingDir: root,
    outdir: join(root, '_build/local-node-adapter-graph')});
  const paths = Object.keys(graph.metafile.inputs)
    .filter(path => path.startsWith('adapters/')).sort();
  if (paths.length < entries.length || entries.some(path => !paths.includes(path))) {
    throw new Error('IncompleteLocalNodeAdapterGraph');
  }
  return paths;
}
