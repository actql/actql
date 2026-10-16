// Required source-side admission from ordinary distribution entrances. Actual
// archives, target behavior and installed acceptance remain separate checks.
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {dirname, isAbsolute, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {npmInterfaceRoots, repositoryFiles} from './distribution-interface-roots.mjs';
import {sourceInterfaceClosure} from './source-interface-closure.mjs';
import {pythonInterfaceSources} from './python-interface-sources.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {interfaceGenerationFreshness} from './interface-generation-freshness.mjs';

export async function checkInterfaceOwners(root, {manifests = []} = {}) {
  root = resolve(root);
  const files = repositoryFiles(root), allRoots = npmInterfaceRoots(root, files);
  const python = pythonInterfaceSources(root);
  const allManifests = new Set([...allRoots, ...python.roots].map(value => value.manifest));
  assert(new Set(manifests).size === manifests.length, 'Duplicate interface manifest selection');
  for (const manifest of manifests) assert(allManifests.has(manifest), `Unknown normal interface manifest: ${manifest}`);
  const roots = manifests.length ? allRoots.filter(value => manifests.includes(value.manifest)) : [...allRoots];
  // Follow actual declared workspace dependencies, including lazy providers.
  for (let index = 0; index < roots.length; index++) for (const dependency of roots[index].dependencies) {
    const target = allRoots.find(value => value.name === dependency);
    if (target && !roots.includes(target)) roots.push(target);
  }
  const configs = files.filter(path => /(?:^|\/)vite\.config\.[cm]?[jt]s$/u.test(path) &&
    roots.some(value => dirname(value.manifest) === dirname(path)));
  let vite = {modules: [], sourceArtifacts: [], generated: [], buildInputs: []};
  if (configs.length) {
    const {viteInterfaceInventory} = await import('./vite-interface-inventory.mjs');
    vite = await viteInterfaceInventory(root, configs);
  }
  const source = await sourceInterfaceClosure(root, {distributionRoots: roots, generatedInputs: vite.sourceArtifacts});
  assert.deepEqual(source.unresolvedEntrances, [], 'Unresolved normal distribution entrances');
  const pythonRoots = manifests.length ? python.roots.filter(value => manifests.includes(value.manifest)) : python.roots;
  const pythonMembers = new Set(pythonRoots.flatMap(value => value.entrances));
  const modules = new Map();
  for (const module of [...source.modules, ...source.types, ...vite.modules,
    ...python.modules.filter(value => pythonMembers.has(value.module))]) {
    const previous = modules.get(module.module);
    if (previous) assert.deepEqual(previous, module, `Conflicting normal interface source: ${module.module}`);
    modules.set(module.module, module);
  }
  assert(modules.size, 'No normal product interfaces discovered');
  // A tiny external-source fixture without this generator has no privileged
  // compiler outputs. It cannot supply approvals through its sidecars.
  const freshness = existsSync(resolve(root, 'scripts/generate-js-compiler-bindings.mjs'))
    ? interfaceGenerationFreshness(root) : undefined;
  const result = interfaceOwnerCoverage({root, modules: [...modules.values()],
    owners: interfaceOwnerDeclarations(root, files), generated: freshness?.generated, requireComplete: true});
  assert(result.complete && result.primaryComplete, 'Incomplete required interface responsibility');
  return {qualification: 'required normal source/generation interface check; not artifact or runtime acceptance',
    result, modules: [...modules.values()], roots, pythonRoots, runtimeBindings: source.runtimeBindings,
    artifacts: source.artifacts, moon: source.moon, generated: vite.generated,
    buildInputs: vite.buildInputs, freshness: freshness && {qualification: freshness.qualification, checked: freshness.checked},
    generatedQualification: freshness?.generated};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let root = fileURLToPath(new URL('../', import.meta.url));
  const manifests = [];
  for (let index = 2; index < process.argv.length; index++) {
    const option = process.argv[index], value = process.argv[++index];
    assert(value && ['--root', '--manifest'].includes(option), 'Invalid required interface check option');
    if (option === '--root') root = resolve(value);
    else {
      assert(!isAbsolute(value) && !relative('.', value).startsWith('..'), 'Escaped interface manifest selection');
      manifests.push(value);
    }
  }
  const checked = await checkInterfaceOwners(root, {manifests});
  console.log(JSON.stringify({qualification: checked.qualification, ...checked.result,
    generationChecks: checked.freshness?.checked.length ?? 0,
    compiledArtifactReferences: checked.artifacts.length, artifactAcceptance: 'not-executed', newProductE2E: 0}));
}
