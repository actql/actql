// Follow authored fixture imports while keeping the real installed product
// graph external. Product source is never copied as a fixture fallback.
import {isAbsolute, join, relative, resolve, sep} from 'node:path';
import {realpathSync} from 'node:fs';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

export function packedFixtureSupport(root, entries,
  {productEntries = localNodePackageInputs(root).adapterEntries} = {}) {
  root = realpathSync(root);
  const product = localModuleGraphInputs(root, productEntries);
  const modules = localModuleGraphInputs(root, entries.filter(path => path.endsWith('.mjs')), {
    external: [...product.map(path => resolve(root, path)),
      join(root, 'packages/*'), join(root, '_build/*')],
  });
  const support = [...new Set([...entries, ...modules])].sort();
  for (const path of support) {
    const suffix = relative(root, resolve(root, path));
    if (isAbsolute(suffix) || suffix === '..' || suffix.startsWith('..' + sep)) {
      throw new Error(`Unpackaged fixture import: ${path}`);
    }
  }
  return support;
}
