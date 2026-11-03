// Build from this checkout, never from committed runtime output. Package users
// receive these files in the tarball and do not need MoonBit or install hooks.
import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync, readdirSync} from 'node:fs';
import {dirname, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {occurrences, repositoryOccurrences, violations} from './check-owned-contract-versions.mjs';
import {assertGeneratedOwnedContracts} from './generated-owned-contracts.mjs';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {packageMetadata} from './connector-build-inputs.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const packages = runtimePackageInputs(root);
// A resolved external Host compiles only the inventory's exact package
// targets. Its workspace is supplied by the trusted build harness; this
// function never resolves modules from a registry or rewrites Core inputs.
export async function buildExternalLocalNodeRuntime({inputs, destination, compiledDirectory}) {
  const {buildLocalNodeAssets} = await import('./build-local-node-assets.mjs');
  const resolved = inputs.buildInputs;
  if (resolved === undefined || existsSync(compiledDirectory)) {
    throw new Error('ExternalLocalNodeBuildNeedsFreshOutput');
  }
  resolved.outputPath(relative(resolved.host.root, join(compiledDirectory, 'sentinel')));
  const inventory = JSON.parse(readFileSync(join(inputs.coreRoot,
    'scripts/owned-contract-version-legacy.json'), 'utf8'));
  const source = repositoryOccurrences(inputs.coreRoot);
  // Core's reviewed contexts do not grant an external Source writer the same
  // token. Package inputs need not have their own Git checkout.
  const external = [];
  const inspectText = (path, ownerPath) => {
    const bytes = readFileSync(path);
    if (bytes.includes(0)) return;
    let text;
    try {text = new TextDecoder('utf-8', {fatal: true}).decode(bytes);} catch {return;}
    external.push(...occurrences(text, ownerPath));
  };
  const pending = inputs.runtimeInputs.map(entry => ({name: entry.qualifiedPackage,
    from: resolved.host.namespace})), inspected = new Set();
  while (pending.length) {
    const {name, from} = pending.pop();
    if (name.startsWith('moonbitlang/core/') || inspected.has(name)) continue;
    inspected.add(name);
    const owner = resolved.modules.find(module => name === module.namespace || name.startsWith(module.namespace + '/'));
    if (owner?.root === inputs.coreRoot) continue;
    const manifest = resolved.resolvePackage(name, from), directory = dirname(manifest);
    for (const imported of packageMetadata(manifest).productionImports) {
      pending.push({name: imported, from: owner.namespace});
    }
    for (const entry of readdirSync(directory, {withFileTypes: true})) {
      const path = join(directory, entry.name);
      if (entry.name.endsWith('.mbt') && !/_(?:wb)?test\.mbt$/u.test(entry.name)) {
        if (!entry.isFile()) throw new Error('AliasedExternalContractSource');
        inspectText(path, `${owner.namespace}:${relative(owner.root, path)}`);
      }
    }
  }
  const {localNodeAdapterSourceInputs} = await import('./build-local-node-adapters.mjs');
  const adapterSources = await localNodeAdapterSourceInputs({root: resolved.host.root, inputs});
  for (const item of [...adapterSources, ...inputs.dataInputs]) {
    const owner = resolved.modules.find(module => item.source.startsWith(module.root + sep));
    if (owner?.root !== inputs.coreRoot) {
      if (owner === undefined) throw new Error('ForeignExternalContractSource');
      inspectText(item.source, `${owner.namespace}:${relative(owner.root, item.source)}`);
    }
  }
  const rejected = violations(external, inventory);
  if (rejected.length) throw new Error('Unadmitted external source contract contexts:\n' +
    rejected.map(item => `${item.path}:${item.line}: ${item.token}`).join('\n'));
  assertGeneratedOwnedContracts({source, generated: [], inventory});
  const byModule = new Map();
  for (const entry of inputs.runtimeInputs) {
    const targets = byModule.get(entry.moduleRoot) ?? [];
    targets.push(entry.target);
    byModule.set(entry.moduleRoot, targets);
  }
  for (const [moduleRoot, targets] of byModule) {
    execFileSync('moon', ['build', '--frozen', '--target', 'js', '--release',
      '--target-dir', compiledDirectory, ...targets], {cwd: moduleRoot, stdio: 'inherit'});
  }
  buildLocalNodeAssets({root: resolved.host.root, inputs, destination, compiledDirectory});
  buildLocalNodeAssets({root: resolved.host.root, inputs, destination, compiledDirectory, check: true});
  const generated = inputs.runtimeFiles.flatMap(path => {
    const file = join(destination, '_build/js/release/build', path);
    return occurrences(readFileSync(file, 'utf8'), file);
  });
  assertGeneratedOwnedContracts({source, generated, inventory});
}

// The normal CLI always resolves the real source-side gate. An imported
// scheduling fixture may supply an explicit admission/refusal port; that
// result is not an interface-Owner proof or a product admission capability.
async function checkSourceInterfaces(root, options) {
  const {checkInterfaceOwners} = await import('./check-interface-owners.mjs');
  await checkInterfaceOwners(root, options);
}

export async function prepareRuntimePackages(requested,
  {checkInterfaces = checkSourceInterfaces} = {}) {
const inventory = JSON.parse(readFileSync(join(root,
  'scripts/owned-contract-version-legacy.json'), 'utf8'));
const source = repositoryOccurrences(root);
assertGeneratedOwnedContracts({source, generated: [], inventory});
for (const name of requested) {
  if (!Object.hasOwn(packages, name)) throw new Error(`Unknown runtime package: ${name}`);
}
const selected = new Set(requested.length ? requested : Object.keys(packages));
const entries = [...selected].map(name => packages[name]);
await checkInterfaces(root, {manifests: [...selected].map(name => `packages/${name}/package.json`)});
execFileSync('moon', ['build', '--target', 'js', '--release',
  ...new Set(entries.flatMap(item => item.sources.map(path => `src/${path}`)))],
{cwd: root, stdio: 'inherit'});
for (const item of entries) {
  execFileSync(process.execPath, [`scripts/${item.script}.mjs`, ...(item.args ?? [])],
    {cwd: root, stdio: 'inherit'});
  // Tracked wrapper copies still have to match their source; preparation must
  // not repair them silently and hide a source/wrapper mismatch from CI.
  execFileSync(process.execPath, [`scripts/${item.script}.mjs`, '--check'],
    {cwd: root, stdio: 'inherit'});
}
const generated = entries.flatMap(item => item.files.flatMap(path =>
  occurrences(readFileSync(join(root, path), 'utf8'), path)));
assertGeneratedOwnedContracts({source, generated, inventory});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await prepareRuntimePackages(process.argv.slice(2));
}
