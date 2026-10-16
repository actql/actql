// Compose the original Native artifact and installed/source interface readers.
// Header/member checks are not execution or a new compiler provenance issuer.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {lstatSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {checkInterfaceOwners, checkedOriginalInterface} from './check-interface-owners.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {installedInterfaceCorrespondence, assertInstalledDependencyClosure} from './installed-interface-correspondence.mjs';
import {admitInstalledNativeArtifact} from './native-cli-artifact-reader.mjs';
import {nativeCliPackageInputs} from './native-cli-package-inputs.mjs';
import {admitInstalledLocalRuntime} from '../packages/native-cli/lib/local-runtime.mjs';

export async function checkStagedNativeCliInterfaces({repository, directory, source, checkedSource, artifact}) {
  assert.match(source, /^[a-f0-9]{40}$/u);
  execFileSync('git', ['cat-file', '-e', `${source}^{commit}`], {cwd: repository});
  const checkedHead = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const metadata = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8'));
  // Validate the existing checker instance before reading its candidate list.
  // DATA or a foreign-root report cannot request a replacement qualification.
  checkedOriginalInterface(repository, 'packages/native-cli/bin/actql.mjs', checkedSource);
  const artifacts = [];
  let bindings;
  if (artifact === undefined) {
    assert.equal(metadata.name, 'actql');
    bindings = nativeCliPackageInputs(repository).copies;
  } else {
    const original = await admitInstalledNativeArtifact(directory, source);
    assert.deepEqual(original, artifact, 'Changed original CLI artifact admission');
    assert.equal(metadata.name, `@actql/cli-${original.platform}`);
    const proof = {sourceSha: source, target: 'native', verification: {
      build: 'scripts/native-cli-artifact.mjs', generatedCSha256: original.generatedCSha256,
      toolchainPinSha256: original.toolchainPinSha256}};
    artifacts.push({...proof, module: 'bin/actql-native-client', sha256: original.binarySha256});
    if (original.localRuntime !== undefined) {
      // The artifact contains a bounded manifest reference, not inline library
      // records. Reuse the original reader before selecting any runtime member.
      const local = admitInstalledLocalRuntime({root: directory,
        expected: {sourceSha: source, platform: original.platform,
          localRuntimeSha256: original.localRuntime.sha256}, metadata: original.localRuntime});
      const runtimeVerification = {reader: 'packages/native-cli/lib/local-runtime.mjs#admitInstalledLocalRuntime',
        manifest: original.localRuntime,
        qualification: 'Original selected runtime material; not compiled by the MoonBit CLI build or runtime ABI acceptance'};
      for (const library of local.libraries) {
        artifacts.push({sourceSha: source, target: 'native-runtime-library',
          module: library.path, sha256: library.sha256,
          verification: {...runtimeVerification, role: library.role,
            dependencies: library.dependencies, abi: library.abi}});
      }
      for (const license of local.licenses.filter(item => item.path.endsWith('.h'))) {
        // SQLite's original blessing is its public header. This is one exact
        // manifest-selected, hash-verified source original, never a directory
        // exemption for headers, scripts or other authored package members.
        assert.equal(lstatSync(join(directory, license.path)).mode & 0o111, 0,
          'Executable runtime license header');
        artifacts.push({sourceSha: source, target: 'native-runtime-original-header',
          module: license.path, sha256: license.sha256,
          verification: {...runtimeVerification, role: 'original-license-header',
            libraryRoles: local.libraries.filter(library => library.license === license.path)
              .map(library => library.role)}});
      }
    }
    bindings = [];
  }
  const installed = installedInterfaceInventory(directory, {artifacts});
  const originalByMember = new Map(bindings.map(value => [value.member, value.source]));
  const authoredEntrances = installed.modules.map(value => {
    const original = originalByMember.get(value.module);
    assert(original, `Unbound installed authored interface: ${value.module}`);
    return original;
  });
  if (authoredEntrances.some(path => !checkedSource.modules.some(value => value.module === path))) {
    // A valid original entry check does not cover a dormant distributed helper.
    // Resolve those actual staged inputs with the same mandatory Owner checker.
    checkedSource = await checkInterfaceOwners(repository, {
      manifests: ['packages/native-cli/package.json'], authoredEntrances});
  }
  const correspondence = installedInterfaceCorrespondence({repository, directory, source,
    bindings, artifacts, checkedSource, generated: checkedSource.generatedQualification,
    owners: interfaceOwnerDeclarations(repository)});
  const dependencies = await assertInstalledDependencyClosure({directory,
    modules: installed.modules, artifacts});
  assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim(), checkedHead);
  return {qualification: 'ordinary CLI member/source/reference correspondence; not Native execution or compiler provenance',
    artifactSource: source, checkedSource: checkedHead, correspondence, dependencies};
}
