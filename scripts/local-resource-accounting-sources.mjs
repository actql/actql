import fs from 'node:fs';
import path from 'node:path';

export function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

// These sources are read by cross-route checks, independently of the paths
// declared in a particular manifest/route fixture.
const fixedSources = [
  'package.json',
  'adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs',
  'adapters/connectors/duckdb/node/test/standard-host.test.mjs',
  'adapters/local-node/strategy-bundle.mjs',
  'scripts/property-graph-public-host.test.mjs',
  'scripts/property-graph-surface-checker.test.mjs',
  'scripts/test-packed-property-graph.mjs',
  'src/connectors/local/driver/dispatch.mbt',
  'src/connectors/local/driver/managed_dispatch.mbt',
  'src/connectors/local/materializing.mbt',
  'src/connectors/local/selected_relation_provider.mbt',
  'src/program_check/check.mbt',
];

// Capture input paths, including mutated foreign entrypoints/evidence. Reuse
// only already captured immutable source bytes; validation always runs anew.
// A new load without previousSources sees the current filesystem (the CLI
// always does this). Tests extend one snapshot within a single suite run.
export function loadResourceAccountingSources({
  root, manifest, routes, previousSources = {},
}) {
  const files = {...previousSources};
  const paths = new Set([path.resolve(root),
    ...fixedSources.map(file => path.resolve(root, file))]);
  const pathKeys = new Set(['path', 'sources', 'rela', 'families', 'production_routes']);
  const addPaths = (value, key) => {
    if (typeof value === 'string') {
      if (pathKeys.has(key) || value.includes('/') || /\.(?:json|mbt|mjs|md)$/u.test(value)) {
        paths.add(path.resolve(root, value));
      }
    } else if (Array.isArray(value)) {
      for (const child of value) addPaths(child, key);
    } else if (value && typeof value === 'object') {
      for (const [childKey, child] of Object.entries(value)) addPaths(child, childKey);
    }
  };
  addPaths(manifest);
  addPaths(routes);
  // Missing inventory paths deliberately retain the original directory/read
  // behavior instead of quietly substituting another inventory.
  const jsonPaths = new Set([
    path.join(root, manifest.inventories?.rela ?? ''),
    path.join(root, manifest.inventories?.families ?? ''),
    path.join(root, 'package.json'),
  ]);
  for (const file of jsonPaths) paths.add(file);
  for (const file of paths) {
    if (Object.hasOwn(files, file)) continue;
    if (!fs.existsSync(file)) {
      files[file] = Object.freeze({exists: false});
      continue;
    }
    if (fs.statSync(file).isDirectory()) {
      files[file] = Object.freeze({exists: true, directory: true});
      continue;
    }
    const text = fs.readFileSync(file, 'utf8');
    files[file] = Object.freeze({exists: true, text,
      ...(jsonPaths.has(file) ? {json: deepFreeze(JSON.parse(text))} : {}),
    });
  }
  // A previously captured text source can become an inventory in a later
  // fixture. Parse that input independently without altering the old snapshot.
  for (const file of jsonPaths) {
    const source = files[file];
    if (source.exists && !Object.hasOwn(source, 'json')) {
      if (source.directory) throw new Error(`cannot read inventory directory ${file}`);
      files[file] = Object.freeze({...source, json: deepFreeze(JSON.parse(source.text))});
    }
  }
  return Object.freeze(files);
}

export function sourceAccess(sources) {
  const get = file => {
    const source = sources[file];
    if (!source?.exists) throw new Error(`source snapshot lacks ${file}`);
    if (source.directory) throw new Error(`cannot read source directory ${file}`);
    return source;
  };
  return {
    existsSync: file => sources[file]?.exists === true,
    readFileSync: file => get(file).text,
    readJson: file => get(file).json,
  };
}
