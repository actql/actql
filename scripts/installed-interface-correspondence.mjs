// Compose the existing member, source and Owner readers. The caller obtains
// copy bindings from the ordinary builder and validates the normal artifacts;
// syntax/reference consistency alone never admits a release or runtime result.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {dirname, isAbsolute, relative, resolve} from 'node:path';
import {existsSync, readFileSync, realpathSync} from 'node:fs';
import ts from 'typescript';
import {build} from 'esbuild';
import {isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {ownerSourcePath, projectOwnerSources} from './interface-owner-source-projection.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';
import {checkedOriginalInterface} from './check-interface-owners.mjs';

const inside = path => typeof path === 'string' && path.length && !isAbsolute(path) &&
  !path.split(/[\\/]/u).includes('..');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

// Runtime paths remain package identities. For emitted members, derive the
// expected bytes from the selected Git source and the same compiler options
// as preparation. The working .mjs is never an input to this derivation.
function installedOriginalBytes(repository, source, selected) {
  const git = args => execFileSync('git', args,
    {cwd: repository, maxBuffer: 16 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
  const blob = path => git(['show', `${source}:${path}`]);
  const runtimePaths = [...new Set(selected.filter(path => path.endsWith('.mjs')))];
  const authoredPath = path => path.slice(0, -4) + '.mts';
  let tracked, config, included;
  return path => {
    try { return blob(path); }
    catch (error) {
      if (!path.endsWith('.mjs') || error.status !== 128) throw error;
      tracked ??= new Set(git(['--literal-pathspecs', 'ls-tree', '-r', '--name-only', '-z',
        source, '--', ...runtimePaths, ...runtimePaths.map(authoredPath)]).toString('utf8').split('\0'));
      if (tracked.has(path) || !tracked.has(authoredPath(path))) throw error;
    }
    if (!config) {
      const preparation = new Map();
      for (const file of ['tsconfig.base.json', 'tsconfig.tooling.json', 'package-lock.json']) {
        const path = resolve(repository, file), original = blob(file);
        assert(readFileSync(path).equals(original), `Changed TypeScript preparation input: ${file}`);
        preparation.set(path, original.toString('utf8'));
      }
      const lock = JSON.parse(preparation.get(resolve(repository, 'package-lock.json')));
      assert.equal(ts.version, lock.packages['node_modules/typescript'].version,
        'TypeScript emitter differs from the original package lock');
      const readConfig = path => preparation.get(resolve(repository, path));
      const file = resolve(repository, 'tsconfig.tooling.json');
      const read = ts.readConfigFile(file, readConfig);
      assert(!read.error, 'Invalid original TypeScript preparation config');
      config = ts.parseJsonConfigFileContent(read.config, {...ts.sys, readFile: readConfig},
        repository, undefined, file);
      assert(!config.errors.length && config.options.noEmitOnError && !config.options.noEmit &&
        !config.options.emitDeclarationOnly && !config.options.outDir && !config.options.outFile,
      'Expected the canonical in-place TypeScript preparation');
      included = new Set(config.fileNames);
    }
    const authored = authoredPath(path), fileName = resolve(repository, authored);
    assert(included.has(fileName), `Unselected TypeScript package source: ${authored}`);
    const emitted = ts.transpileModule(blob(authored).toString('utf8'), {
      fileName, compilerOptions: config.options, reportDiagnostics: true,
    });
    assert(!emitted.diagnostics?.some(item => item.category === ts.DiagnosticCategory.Error),
      `Cannot derive installed TypeScript runtime bytes: ${authored}`);
    return Buffer.from(emitted.outputText);
  };
}

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
  const commands = selected.filter(path => !/\.[^/]+$/u.test(path));
  // The same checker already retains the original parsed model. Keep the
  // existing source eligibility and compare its hash with actual Git bytes
  // below before using it for installed correspondence.
  const original = checkedSource ? selected.filter(path => ownerSourcePath(path, commands))
    .map(path => checkedOriginalInterface(repository, path, checkedSource)) : selected.length ? projectOwnerSources(repository,
    {source, base: source, paths: selected, all: true,
      commands}).modules : [];
  const bySource = new Map(original.map(module => [module.module, module]));
  const originalBytes = installedOriginalBytes(repository, source, selected);
  const actual = installed.modules.map(module => {
    const binding = byMember.get(module.module), input = bySource.get(binding.source);
    assert(input, `Missing original authored interface: ${binding.source}`);
    const bytes = originalBytes(binding.source);
    if (checkedSource) assert.equal(input.sha256, digest(bytes),
      `Changed checked original source interface: ${binding.source}`);
    const expected = binding.transform === 'local-node-public-imports'
      ? Buffer.from(rewriteLocalNodePackageImports(bytes.toString('utf8'), binding.source)) : bytes;
    assert.equal(module.sha256, digest(expected), `Changed installed interface bytes: ${module.module}`);
    assert.deepEqual(module.exports, input.exports, `Changed installed interface exports: ${module.module}`);
    assert.deepEqual(module.operations, input.operations, `Changed installed interface operations: ${module.module}`);
    assert.deepEqual(module.compilerFields ?? [], input.compilerFields ?? [],
      `Changed installed compiler representation: ${module.module}`);
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

// Validate the actual bundled graph, not the SDK's private module inventory.
// Generated pure codecs may grow inside these two lightweight packages.
export function assertRemoteBrowserDependencyBoundary(metadata) {
  const inputs = Object.entries(metadata.inputs), outputs = Object.values(metadata.outputs);
  assert(inputs.length && outputs.length, 'Remote browser bundle graph must be nonempty');
  assert(inputs.some(([path]) => path.replaceAll('\\', '/') ===
    'node_modules/@actql/sdk/index.mjs'), 'Remote browser SDK entry is missing');
  for (const [path, input] of inputs) {
    const normalized = path.replaceAll('\\', '/');
    const match = /^node_modules\/@actql\/(?:sdk|client-wire)\/(.+)$/u.exec(normalized);
    assert(match, `Remote browser dependency outside SDK/client-wire: ${path}`);
    const parts = match[1].split('/');
    assert(parts.every(part => part && !['.', '..', 'node_modules', '_build', 'native'].includes(part)) &&
      !/(?:^|\/)Core\.[cm]?js$|\.(?:node|wasm|core|mi|rsp|dylib|so|dll)$/iu.test(match[1]),
    `Remote browser compiled/runtime dependency: ${path}`);
    assert(Array.isArray(input.imports) && input.imports.every(value => !value.external),
      `Remote browser external input import: ${path}`);
  }
  assert(outputs.every(output => Array.isArray(output.imports) && output.imports.length === 0),
    'Remote browser bundle must have no remaining imports');
}
