// Normal release verification and normal builder checks remain authoritative.
// This composes their actual installed members with existing Owner references;
// it does not turn reference consistency into runtime behavior evidence.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {dirname, join, relative} from 'node:path';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyPackageRelease, inventory} from './package-release.mjs';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {checkInterfaceOwners} from './check-interface-owners.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {installedInterfaceCorrespondence} from './installed-interface-correspondence.mjs';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {buildLocalNodeAdapters, localNodeAdapterSourceInputs} from './build-local-node-adapters.mjs';
import {buildLocalNodeAssets} from './build-local-node-assets.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export async function releaseInterfaceCheck({repository, directory}) {
  const before = checkoutState(repository);
  assert(before.clean, 'Release interface verification needs clean source HEAD');
  const manifest = await verifyPackageRelease(directory);
  assert.equal(manifest.sourceSha, before.revision, 'Release interface source differs from checkout');
  assert.equal(manifest.recipeSha256, hash(readFileSync(join(repository, 'scripts/package-release.mjs'))),
    'Release interface recipe differs from original source');
  const roots = npmInterfaceRoots(repository), plans = runtimePackageInputs(repository);
  const owners = interfaceOwnerDeclarations(repository);
  const manifestSha256 = hash(readFileSync(join(directory, 'release.json')));
  return {manifest, async verifyConsumer(consumer, names) {
    assert.equal(new Set(names).size, names.length, 'Duplicate installed interface package');
    const reports = [];
    for (const name of names) {
      const item = manifest.packages.find(value => value.name === `@actql/${name}`);
      assert(item, `Package outside original release cohort: ${name}`);
      const root = roots.find(value => value.name === item.name);
      assert(root, `Missing normal package source entrance: ${item.name}`);
      const installed = join(consumer, 'node_modules', item.name);
      assert.deepEqual(await inventory(installed), item.files, `Changed installed release members: ${item.name}`);
      const packageSource = dirname(root.manifest);
      const bindings = new Map(item.files.map(file => [file.path,
        {member: file.path, source: `${packageSource}/${file.path}`} ]));
      const plan = plans[name];
      if (name === 'local-node') {
        const inputs = localNodePackageInputs(repository);
        await buildLocalNodeAdapters({root: repository, destination: installed, inputs, check: true});
        buildLocalNodeAssets({root: repository, destination: installed, inputs, check: true});
        for (const entry of await localNodeAdapterSourceInputs({root: repository, inputs})) {
          bindings.set(entry.path, {member: entry.path, source: relative(repository, entry.source),
            ...(entry.path.endsWith('.mjs') ? {transform: 'local-node-public-imports'} : {})});
        }
        for (const path of inputs.dataFiles) bindings.set(path, {member: path, source: path});
      }
      const artifacts = (plan?.files ?? []).map(path => {
        assert(path.startsWith(packageSource + '/'), 'Runtime input outside its original package');
        const module = path.slice(packageSource.length + 1);
        const file = item.files.find(value => value.path === module);
        assert(file, `Missing ordinary runtime interface: ${path}`);
        return {module, sha256: file.sha256, sourceSha: before.revision, target: 'js',
          verification: {manifestSha256, originalSha256: item.originalSha256,
            build: `scripts/${plan.script}.mjs`, sourcePackages: plan.sources}};
      });
      const actual = installedInterfaceInventory(installed, {artifacts});
      const authoredEntrances = actual.modules.map(module => {
        const binding = bindings.get(module.module);
        assert(binding, `Unbound installed authored interface: ${module.module}`);
        return binding.source;
      });
      const checkedSource = await checkInterfaceOwners(repository, {manifests: [root.manifest], authoredEntrances});
      reports.push(installedInterfaceCorrespondence({repository, directory: installed,
        source: before.revision, bindings: [...bindings.values()], artifacts,
        owners, generated: checkedSource.generatedQualification, checkedSource}));
    }
    assert.deepEqual(checkoutState(repository), before, 'Release interface source changed during verification');
    return {qualification: 'normal release/source/installed interface correspondence; not runtime or all-I6 acceptance',
      source: before.revision, manifestSha256, reports};
  }};
}
