// A source-qualified projection of ordinary build inputs. Missing generated
// artifacts are explicit references, never pretend compiled module passes.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import {dirname, relative, resolve} from 'node:path';
import {buildSync} from 'esbuild';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {javascriptInterface} from './interface-inventory.mjs';
import {moonInterfaceClosure} from './moon-interface-inventory.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';

export function sourceInterfaceClosure(root, {distributionRoots = npmInterfaceRoots(root), generatedInputs = []} = {}) {
  root = realpathSync(root);
  const roots = distributionRoots, plans = runtimePackageInputs(root);
  const local = localNodePackageInputs(root), artifacts = new Map();
  for (const [name, plan] of Object.entries(plans)) {
    for (const file of plan.files) artifacts.set(resolve(root, file), {module: file,
      sourcePackages: plan.sources, build: `scripts/${plan.script}.mjs`, package: name});
  }
  for (const file of local.runtimeFiles) {
    artifacts.set(resolve(root, '_build/js/release/build', file), {
      module: `_build/js/release/build/${file}`, sourcePackages: local.runtimePackages,
      build: 'scripts/build-local-node-assets.mjs', package: 'local-node'});
  }
  for (const input of generatedInputs) {
    const path = resolve(root, input.module);
    assert(!artifacts.has(path), `Duplicate generated interface input: ${input.module}`);
    assert(existsSync(resolve(root, input.build)), `Missing generated interface recipe: ${input.build}`);
    artifacts.set(path, input);
  }
  const entrances = [...new Set([...roots.flatMap(value => value.entrances)
    .filter(path => /\.[cm]?js$/u.test(path)), ...local.adapterEntries])];
  const sourceEntrances = [], artifactReferences = new Set();
  for (const entrance of entrances) {
    if (artifacts.has(resolve(root, entrance))) artifactReferences.add(resolve(root, entrance));
    else {
      assert(existsSync(resolve(root, entrance)), `Undeclared generated interface entrance: ${entrance}`);
      sourceEntrances.push(entrance);
    }
  }
  const graph = buildSync({entryPoints: sourceEntrances, bundle: true,
    packages: 'external', platform: 'node', format: 'esm', target: 'node22',
    metafile: true, write: false, absWorkingDir: root,
    outdir: resolve(root, '_build/unused-interface-discovery'),
    plugins: [{name: 'ordinary-compiled-input-references', setup(builder) {
      builder.onResolve({filter: /^\./}, args => {
        const path = resolve(dirname(args.importer), args.path);
        if (artifacts.has(path)) {
          artifactReferences.add(path);
          return {path, external: true};
        }
      });
    }}]});
  const modules = Object.keys(graph.metafile.inputs).sort().map(path => {
    const module = relative(root, realpathSync(resolve(root, path)));
    assert(!module.startsWith('..'), `Escaped source interface: ${module}`);
    assert(!isConnectorTestFixture(module) && !/(?:\.test|_test|_wbtest)\./u.test(module),
      `Test authority in source interface: ${module}`);
    const bytes = readFileSync(resolve(root, module));
    return {module, sha256: createHash('sha256').update(bytes).digest('hex'),
      ...javascriptInterface(bytes.toString('utf8'))};
  });
  const moon = moonInterfaceClosure(root, [...new Set([...artifactReferences]
    .flatMap(path => artifacts.get(path).sourcePackages))]);
  return {qualification: 'source-input-coverage-only', roots, modules, moon,
    artifacts: [...artifactReferences].sort().map(path => artifacts.get(path))};
}
