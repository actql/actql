// Compose the existing member, source and Owner readers. The caller obtains
// copy bindings from the ordinary builder and validates the normal artifacts;
// syntax/reference consistency alone never admits a release or runtime result.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {dirname, isAbsolute, relative, resolve} from 'node:path';
import {existsSync, realpathSync} from 'node:fs';
import {build} from 'esbuild';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {projectOwnerSources} from './interface-owner-source-projection.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';
import {checkedOriginalInterface} from './check-interface-owners.mjs';

const inside = path => typeof path === 'string' && path.length && !isAbsolute(path) &&
  !path.split(/[\\/]/u).includes('..');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

export function installedInterfaceCorrespondence({repository, directory, source,
  bindings, artifacts = [], owners, generated = [], checkedSource}) {
  assert.match(source, /^[a-f0-9]{40}$/u);
  const byMember = new Map();
  for (const binding of bindings) {
    assert(inside(binding.member) && inside(binding.source), 'Escaped installed interface binding');
    assert(!byMember.has(binding.member), `Duplicate installed interface binding: ${binding.member}`);
    assert(binding.transform === undefined || binding.transform === 'local-node-public-imports',
      'Unknown installed interface transformation');
    byMember.set(binding.member, binding);
  }
  for (const artifact of artifacts) assert.equal(artifact.sourceSha, source,
    `Foreign installed interface artifact source: ${artifact.module}`);
  const installed = installedInterfaceInventory(directory, {artifacts});
  const selected = installed.modules.map(module => {
    const binding = byMember.get(module.module);
    assert(binding, `Unbound installed authored interface: ${module.module}`);
    return binding.source;
  });
  const original = selected.length ? projectOwnerSources(repository,
    {source, base: source, paths: selected, all: true,
      commands: selected.filter(path => !/\.[^/]+$/u.test(path))}).modules : [];
  const bySource = new Map(original.map(module => [module.module, module]));
  const actual = installed.modules.map(module => {
    const binding = byMember.get(module.module), input = bySource.get(binding.source);
    assert(input, `Missing original authored interface: ${binding.source}`);
    const bytes = execFileSync('git', ['show', `${source}:${binding.source}`],
      {cwd: repository, maxBuffer: 16 * 1024 * 1024});
    const expected = binding.transform === 'local-node-public-imports'
      ? Buffer.from(rewriteLocalNodePackageImports(bytes.toString('utf8'), binding.source)) : bytes;
    assert.equal(module.sha256, digest(expected), `Changed installed interface bytes: ${module.module}`);
    assert.deepEqual(module.exports, input.exports, `Changed installed interface exports: ${module.module}`);
    assert.deepEqual(module.operations, input.operations, `Changed installed interface operations: ${module.module}`);
    assert.deepEqual(module.compilerFields ?? [], input.compilerFields ?? [],
      `Changed installed compiler representation: ${module.module}`);
    if (checkedSource) {
      const checked = checkedOriginalInterface(repository, binding.source, checkedSource);
      for (const field of ['sha256', 'exports', 'operations', 'compilerFields']) {
        assert.deepEqual(checked[field] ?? [], input[field] ?? [], `Changed checked source interface: ${binding.source}:${field}`);
      }
      return checked;
    }
    return input;
  });
  const coverage = interfaceOwnerCoverage({root: repository, modules: actual, owners, generated});
  return {qualification: 'installed/source/reference correspondence only; not release or runtime admission',
    source, package: installed.name, coverage, artifacts: installed.artifacts};
}


// Resolve real installed files with the existing packaging resolver. Compiled
// members are exact, already admitted artifact references, never parsed helpers.
export async function assertInstalledDependencyClosure({directory, modules, artifacts = [], runtimeBindings = []}) {
  const root = realpathSync(directory), compiled = new Set(artifacts.map(value => resolve(root, value.module)));
  const inside = path => !isAbsolute(relative(root, path)) && !relative(root, path).startsWith('..');
  // Declaration files retain their full syntax/source/Owner correspondence,
  // but do not emit runtime code. Actual value imports still use the resolver
  // below, so this cannot exempt a runtime dependency on a declaration file.
  const entries = modules.filter(value => !/(?:\.pyi?|\.d\.[cm]?ts)$/u.test(value.module))
    .map(value => resolve(root, value.module));
  for (const binding of runtimeBindings) for (const specifier of binding.targets) {
    if (!specifier.startsWith('.')) continue;
    const path = resolve(dirname(resolve(root, binding.module)), specifier);
    assert(inside(path) && existsSync(path), `Missing installed runtime dependency: ${binding.module}`);
    if (!compiled.has(path) && !entries.includes(path)) entries.push(path);
  }
  if (!entries.length) return {modules: 0, qualification: 'no-JavaScript-installed-members'};
  let graph;
  try {
    graph = await build({absWorkingDir: root, entryPoints: entries, bundle: true, packages: 'external',
      platform: 'node', format: 'esm', target: 'node22', write: false, metafile: true,
      outdir: resolve(root, '.unused-interface-dependency-graph'), logLevel: 'silent',
      plugins: [{name: 'original-installed-compiled-members', setup(builder) {
        builder.onResolve({filter: /^\./}, argument => {
          const path = resolve(dirname(argument.importer), argument.path);
          if (compiled.has(path)) return {path, external: true};
        });
      }}]});
  } catch (failure) {
    if (failure.errors?.length && failure.errors.every(value => /^Could not resolve /u.test(value.text))) {
      assert.fail('Unresolved installed interface dependency');
    }
    throw failure;
  }
  for (const path of Object.keys(graph.metafile.inputs)) {
    const actual = realpathSync(resolve(root, path)), module = relative(root, actual);
    assert(inside(actual), `Escaped installed interface dependency: ${module}`);
    assert(!isConnectorTestFixture(module) && !/(?:\.test|_test|_wbtest)\./u.test(module),
      `Test authority in installed interface dependency: ${module}`);
  }
  return {modules: Object.keys(graph.metafile.inputs).length,
    qualification: 'actual installed dependency closure; not product execution'};
}
