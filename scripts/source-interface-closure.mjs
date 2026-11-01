// A source-qualified projection of ordinary build inputs. Missing generated
// artifacts are explicit references, never pretend compiled module passes.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import {dirname, relative, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {providerBundleUrl} from '../adapters/host-node/installed-connectors.mjs';
import {build} from 'esbuild';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {nativeCliPackageInputs} from './native-cli-package-inputs.mjs';
import {javascriptInterface} from './interface-inventory.mjs';
import {moonInterfaceClosure} from './moon-interface-inventory.mjs';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';
import {typescriptInterface, typescriptInterfaceClosure} from './typescript-interface-inventory.mjs';
import {productionRuntimeModules} from '../adapters/workers/moon-runtime.mjs';
import {pythonModuleInterfaces} from './python-interface-sources.mjs';

export async function sourceInterfaceClosure(root, {distributionRoots = npmInterfaceRoots(root), generatedInputs = [],
  reportUnresolvedEntrances = false, authoredEntrances = []} = {}) {
  root = realpathSync(root);
  const roots = distributionRoots, availablePlans = runtimePackageInputs(root);
  const includesLocal = roots.some(value => value.name === '@actql/local-node');
  const plans = Object.fromEntries(Object.keys(availablePlans).filter(name =>
    roots.some(value => value.name === `@actql/${name}`)).map(name => [name, availablePlans[name]]));
  const local = includesLocal ? localNodePackageInputs(root) : undefined, artifacts = new Map();
  for (const [name, plan] of Object.entries(plans)) {
    for (const file of plan.files) artifacts.set(resolve(root, file), {module: file,
      sourcePackages: plan.sources, build: `scripts/${plan.script}.mjs`, package: name});
  }
  for (const file of local?.runtimeFiles ?? []) {
    artifacts.set(resolve(root, '_build/js/release/build', file), {
      module: `_build/js/release/build/${file}`, sourcePackages: local.runtimePackages,
      build: 'scripts/build-local-node-assets.mjs', package: 'local-node'});
  }
  // The existing Local native builder delivers these finite N-API images.
  // Keep missing images as source-qualified build references, never parse a
  // binary as JavaScript or pretend that source discovery executed its build.
  // Both prefixes are the actual package-relative/source-checkout entrances.
  const nativeTargets = [
    ...['arm64', 'x64'].map(arch => ({name: `directory-darwin-${arch}.node`,
      source: 'adapters/host-node/native/directory-darwin.c', target: `darwin-${arch}/node-napi8`})),
    {name: 'local-files-linux-x64.node', source: 'adapters/host-node/native/local-files-linux.c',
      target: 'linux-x64/node-napi8'},
  ];
  if (includesLocal) for (const {name, source, target} of nativeTargets) {
    for (const prefix of ['', 'packages/local-node/']) {
      const module = `${prefix}_build/native/${name}`;
      artifacts.set(resolve(root, module), {module, sourcePackages: [],
        sourceFiles: [source, 'adapters/host-node/native/napi-filesystem-helpers.inc',
          'adapters/connectors/local/site/root-filesystem-platform.inc',
          'adapters/connectors/local/site/root-filesystem.inc',
          'adapters/connectors/local/site/root-file-writer.inc'],
        build: 'scripts/build-node-directory-native.mjs', package: 'local-node',
        target, qualification: 'native-build-input-reference-only'});
    }
  }
  for (const [name, pkg] of productionRuntimeModules) {
    const module = `_build/workers/modules/${name}.mjs`;
    artifacts.set(resolve(root, module), {module, sourcePackages: [pkg],
      build: 'adapters/workers/moon-runtime.mjs', package: 'run-host-core'});
  }
  for (const input of generatedInputs) {
    const path = resolve(root, input.module);
    assert(!artifacts.has(path), `Duplicate generated interface input: ${input.module}`);
    assert(existsSync(resolve(root, input.build)), `Missing generated interface recipe: ${input.build}`);
    assert(Array.isArray(input.sourcePackages), `Missing generated interface source inputs: ${input.module}`);
    if (input.sha256 !== undefined && existsSync(path)) {
      assert.equal(createHash('sha256').update(readFileSync(path)).digest('hex'), input.sha256,
        `Mixed configured interface output: ${input.module}`);
    }
    artifacts.set(path, input);
  }
  const ownedAssets = includesLocal ? local.dataFiles : [];
  const commands = new Set(roots.flatMap(value => value.commands ?? []));
  const declarationEntrances = [...new Set([...roots.flatMap(value => value.entrances),
    ...authoredEntrances].filter(path => /\.d\.[cm]?ts$/u.test(path)))];
  const entrances = [...new Set([...roots.flatMap(value => value.entrances)
    .filter(path => !/\.d\.[cm]?ts$/u.test(path)),
    ...(includesLocal ? local.adapterEntries : []), ...ownedAssets.filter(path => /\.[cm]?js$/u.test(path)),
    ...authoredEntrances.filter(path => !/\.d\.[cm]?ts$/u.test(path))])];
  const native = nativeCliPackageInputs(root);
  if (native && roots.some(value => value.manifest === native.manifest)) {
    entrances.push(...native.copies.map(value => value.source));
  }
  const sourceEntrances = [], artifactReferences = new Set(), unresolvedEntrances = [];
  const dataEntrances = [], pythonEntrances = [], scriptEntrances = new Set();
  const copyReferences = new Map();
  function copiedSource(path) {
    const destination = relative(resolve(root, 'packages/local-node'), path);
    if (!destination.startsWith('adapters/') && !destination.startsWith('src/')) return;
    const source = resolve(root, destination);
    if (destination.startsWith('src/')) assert(local.dataFiles.includes(destination),
      `Undeclared local-node source asset: ${destination}`);
    assert(existsSync(source), `Missing local-node copy source: ${destination}`);
    copyReferences.set(path, {destination: relative(root, path), source: destination});
    return source;
  }
  for (const entrance of entrances) {
    assert(!relative(root, resolve(root, entrance)).startsWith('..'), `Escaped authored interface entrance: ${entrance}`);
    if (artifacts.has(resolve(root, entrance))) artifactReferences.add(resolve(root, entrance));
    else {
      const source = copiedSource(resolve(root, entrance));
      if (source) {
        sourceEntrances.push(relative(root, source));
        continue;
      }
      if (!existsSync(resolve(root, entrance))) {
        assert(reportUnresolvedEntrances, `Undeclared generated interface entrance: ${entrance}`);
        unresolvedEntrances.push(entrance);
        continue;
      }
      if (/\.pyi?$/u.test(entrance)) pythonEntrances.push(entrance);
      else if (/\.[cm]?[jt]sx?$/u.test(entrance)) sourceEntrances.push(entrance);
      else if (commands.has(entrance)) {
        const first = readFileSync(resolve(root, entrance)).subarray(0, 256).toString('utf8').split(/\r?\n/u, 1)[0];
        if (/^#!(?:\/usr\/bin\/env[ \t]+python3?|\/usr\/bin\/python3?)(?:[ \t]|$)/u.test(first)) {
          pythonEntrances.push(entrance);
        } else {
          assert(/^#!(?:\/usr\/bin\/env[ \t]+node|\/usr\/bin\/node)(?:[ \t]|$)/u.test(first),
            `Unregistered executable source interface: ${entrance}`);
          sourceEntrances.push(entrance);
          scriptEntrances.add(entrance);
        }
      } else dataEntrances.push(entrance);
    }
  }
  for (const plan of Object.values(plans)) {
    if (plan.files.some(file => artifactReferences.has(resolve(root, file)))) {
      sourceEntrances.push(...plan.embeddedSources ?? []);
    }
  }
  const runtimeBindings = [], extraEntrances = new Set();
  const parsed = new Map(), assetMap = new Map();
  let graph;
  do {
  for (const entry of extraEntrances) if (!sourceEntrances.includes(entry)) sourceEntrances.push(entry);
  extraEntrances.clear();
  graph = sourceEntrances.length ? await build({entryPoints: sourceEntrances, bundle: true,
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
        assert(!path.endsWith('.node'), `Unregistered native source interface artifact: ${relative(root, path)}`);
        // The ordinary local-node builder copies these exact source paths.
        // Resolve the source projection without manufacturing the generated
        // package tree, then leave actual copied-byte checks to that builder.
        const source = copiedSource(path);
        if (source) return {path: source};
      });
    }}]}) : {metafile: {inputs: {}}};
  for (const path of Object.keys(graph.metafile.inputs).sort()) {
    const module = relative(root, realpathSync(resolve(root, path)));
    assert(!module.startsWith('..'), `Escaped source interface: ${module}`);
    assert(!isConnectorTestFixture(module) && !/(?:\.test|_test|_wbtest)\./u.test(module),
      `Test authority in source interface: ${module}`);
    const bytes = readFileSync(resolve(root, module));
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    if (!/\.[cm]?[jt]sx?$/u.test(module) && !scriptEntrances.has(module)) {
      assetMap.set(module, {module, sha256, qualification: 'resolved-distribution-data'});
      continue;
    }
    if (parsed.has(module)) continue;
    const admitTarget = specifier => {
      const target = resolve(dirname(resolve(root, module)), specifier);
      assert(!relative(root, target).startsWith('..'), `Escaped runtime interface: ${module}`);
      if (artifacts.has(target)) artifactReferences.add(target);
      else if (target.endsWith('.node')) {
        assert.fail(`Unregistered native source interface artifact: ${relative(root, target)}`);
      }
      else if (!sourceEntrances.includes(relative(root, target))) extraEntrances.add(relative(root, target));
      return specifier;
    };
    const resolveRuntimeImport = reference => {
      let targets;
      if (reference.kind === 'module-url' || reference.kind === 'literal') {
        if (!reference.specifier.startsWith('./') && !reference.specifier.startsWith('../')) return;
        targets = [admitTarget(reference.specifier)];
      } else if (reference.kind === 'package-resolution') {
        const original = roots.find(value => module.startsWith(dirname(value.manifest) + '/'));
        const target = roots.find(value => value.name === reference.specifier);
        if (!original?.dependencies.includes(reference.specifier) || !target) return;
        targets = [reference.specifier];
      } else if (reference.kind === 'owner-projection') {
        const owner = 'adapters/host-node/installed-connectors.mjs';
        const importedFrom = (value, expected) => value?.source &&
          relative(root, resolve(dirname(resolve(root, module)), value.source)) === expected;
        const ownerCall = (value, name) => value?.kind === 'owner-call' && value.name === name && importedFrom(value, owner);
        if (!importedFrom(reference, owner) || reference.name !== 'providerBundleUrl' ||
            ![1, 2].includes(reference.arguments?.length)) return;
        // Reuse the actual installed table Owner and normal checked manifest
        // inventory. No provider names, target patterns or alternate table.
        assert(readFileSync(resolve(root, owner)).equals(readFileSync(new URL('../' + owner, import.meta.url))),
          'Runtime dependency Owner differs from its checked source');
        const declared = () => local?.providerBundles.map(entry => ({providerBundle: entry.package}));
        const runtimeTable = value => value?.kind === 'runtime-parameter' ||
          value?.kind === 'alternatives' && value.values.length && value.values.every(runtimeTable);
        function entries(value) {
          if (value?.kind === 'alternatives') {
            const choices = value.values.map(entries);
            return choices.every(Array.isArray) ? choices.flat() : undefined;
          }
          if (value?.kind === 'object') {
            const bundle = value.properties.providerBundle;
            return bundle === undefined ? [{}] : bundle.kind === 'value' && typeof bundle.value === 'string'
              ? [{providerBundle: bundle.value}] : undefined;
          }
          if (value?.kind === 'import' && value.name === 'installedConnectors' &&
              importedFrom(value, 'adapters/connectors-builtin/installations.generated.mjs')) return declared();
          if (value?.kind === 'array') {
            const parts = value.values.map(part => entries(part?.kind === 'spread' ? part.value : part));
            return parts.every(Array.isArray) ? parts.flat() : undefined;
          }
          if ((ownerCall(value, 'installedEffectTable') || ownerCall(value, 'installedConnectorTable')) &&
              value.arguments.length === 1) return entries(value.arguments[0]);
          if (ownerCall(value, 'installedConnectorFor') && value.arguments.length >= 2 && value.arguments.length <= 3) {
            return entries(value.arguments[0]);
          }
          // Explicit tables are opaque, Owner-admitted runtime installations.
          // Their selector's original role/handle obligation stays visible;
          // this qualifies only the normal builder's finite compiled set, not
          // an arbitrary foreign table or a new runtime installation.
          if (ownerCall(value, 'installedConnectorForTable') && value.arguments.length >= 3 && value.arguments.length <= 4 &&
              runtimeTable(value.arguments[0]) &&
              value.arguments[1]?.kind === 'value' && ['source', 'effect'].includes(value.arguments[1].value)) return declared();
        }
        const actualEntries = entries(reference.arguments[0]);
        if (!actualEntries) return;
        let base = pathToFileURL(resolve(root, owner));
        if (reference.arguments.length === 2) {
          const actualBase = reference.arguments[1];
          if (actualBase.kind === 'module-meta-url') base = pathToFileURL(resolve(root, module));
          else if (actualBase.kind === 'value' && typeof actualBase.value === 'string') base = actualBase.value;
          else return;
        }
        targets = [...new Set(actualEntries.flatMap(entry => {
          const url = providerBundleUrl(entry, base);
          if (url === undefined) return [];
          const target = fileURLToPath(url);
          assert(artifacts.has(target), `Unregistered provider runtime interface: ${target}`);
          artifactReferences.add(target);
          return [relative(dirname(resolve(root, module)), target).replace(/^(?!\.)/u, './')];
        }))];
      }
      if (targets?.length) runtimeBindings.push({module, sourceSha256: sha256, reference, targets});
      return targets;
    };
    const syntax = {module, sha256,
      ...(/\.[cm]?tsx?$/u.test(module) ? typescriptInterface(bytes.toString('utf8'), module)
        : javascriptInterface(bytes.toString('utf8'), {resolveRuntimeImport}))};
    // createRequire's locally bound receiver is not an esbuild dependency.
    // Admit its original literal native paths from the same parsed source,
    // using the fixed build-input map above; never infer a dynamic image.
    for (const specifier of syntax.imports) {
      if (specifier.endsWith('.node') && /^\.\.?\//u.test(specifier)) admitTarget(specifier);
    }
    parsed.set(module, syntax);
  }
  } while (extraEntrances.size);
  for (const path of artifactReferences) {
    const artifact = artifacts.get(path);
    if (!artifact.sourceFiles) continue;
    for (const module of [...artifact.sourceFiles, artifact.build]) {
      const input = realpathSync(resolve(root, module));
      assert(!relative(root, input).startsWith('..'), `Escaped native build input: ${module}`);
      assetMap.set(module, {module, sha256: createHash('sha256').update(readFileSync(input)).digest('hex'),
        qualification: 'compiled-native-build-source'});
    }
  }
  const modules = [...parsed.values()], assets = [...assetMap.values()];
  const pythonAssets = [...new Set([...ownedAssets.filter(path => /\.pyi?$/u.test(path)), ...pythonEntrances])];
  modules.push(...pythonModuleInterfaces(root, pythonAssets));
  for (const module of new Set([...ownedAssets, ...dataEntrances])) {
    if (modules.some(value => value.module === module) || assets.some(value => value.module === module)) continue;
    const path = realpathSync(resolve(root, module));
    assert(!relative(root, path).startsWith('..'), `Escaped source asset: ${module}`);
    assets.push({module, sha256: createHash('sha256').update(readFileSync(path)).digest('hex'),
      qualification: 'checked-host-manifest-asset'});
  }
  const moon = moonInterfaceClosure(root, [...new Set([...artifactReferences]
    .flatMap(path => artifacts.get(path).sourcePackages))]);
  const types = typescriptInterfaceClosure(root, declarationEntrances);
  return {qualification: unresolvedEntrances.length ? 'incomplete-source-input-coverage' : 'source-input-coverage-only',
    unresolvedEntrances, runtimeBindings, roots, modules: modules.sort((a, b) => a.module.localeCompare(b.module)),
    assets: assets.sort((a, b) => a.module.localeCompare(b.module)), types, moon,
    copies: [...copyReferences.values()].sort((a, b) => a.destination.localeCompare(b.destination)),
    artifacts: [...artifactReferences].sort().map(path => artifacts.get(path))};
}
