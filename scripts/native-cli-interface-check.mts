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
import {admitInstalledNativeArtifactMaterial} from './native-cli-artifact-reader.mjs';
import {nativeCliPackageInputs} from './native-cli-package-inputs.mjs';

type ArtifactMaterial = Awaited<ReturnType<typeof admitInstalledNativeArtifactMaterial>>;
type StagedOptions = {repository: string; directory: string; source: string;
  checkedSource: Awaited<ReturnType<typeof checkInterfaceOwners>>; artifact?: unknown};
type Correspondence = Parameters<typeof installedInterfaceCorrespondence>[0];
type Artifacts = ReturnType<typeof installedInterfaceInventory>['artifacts'];

export async function checkStagedNativeCliInterfaces({repository, directory, source, checkedSource, artifact}: StagedOptions) {
  assert.match(source, /^[a-f0-9]{40}$/u);
  execFileSync('git', ['cat-file', '-e', `${source}^{commit}`], {cwd: repository});
  const checkedHead = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const metadata = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8')) as {name: unknown};
  // Validate the existing checker instance before reading its candidate list.
  // DATA or a foreign-root report cannot request a replacement qualification.
  checkedOriginalInterface(repository, 'packages/native-cli/bin/actql.mjs', checkedSource);
  const artifacts: Artifacts = [];
  let bindings: Correspondence['bindings'], artifactMaterial: ArtifactMaterial | undefined;
  if (artifact === undefined) {
    assert.equal(metadata.name, 'actql');
    bindings = nativeCliPackageInputs(repository)!.copies;
  } else {
    artifactMaterial = await admitInstalledNativeArtifactMaterial(directory, source);
    const {artifact: original, localRuntime: local} = artifactMaterial;
    assert.deepEqual(original, artifact, 'Changed original CLI artifact admission');
    assert.equal(metadata.name, `@actql/cli-${original.platform}`);
    const proof = {sourceSha: source, target: 'native', verification: {
      build: 'scripts/native-cli-artifact.mjs', generatedCSha256: original.generatedCSha256,
      toolchainPinSha256: original.toolchainPinSha256}};
    artifacts.push({...proof, module: 'bin/actql-native-client', sha256: original.binarySha256});
    if (original.localRuntime !== undefined) {
      // These are the same-call original runtime records, not inline candidate
      // libraries or a replacement admission supplied by this caller.
      const runtimeVerification = {reader: 'packages/native-cli/lib/local-runtime.mjs#admitInstalledLocalRuntime',
        manifest: original.localRuntime,
        qualification: 'Original selected runtime material; not compiled by the MoonBit CLI build or runtime ABI acceptance'};
      for (const library of local!.libraries) {
        artifacts.push({sourceSha: source, target: 'native-runtime-library',
          module: library.path, sha256: library.sha256,
          verification: {...runtimeVerification, role: library.role,
            dependencies: library.dependencies, abi: library.abi}});
      }
      for (const license of local!.licenses.filter(item => item.path.endsWith('.h'))) {
        // SQLite's original blessing is its public header. This is one exact
        // manifest-selected, hash-verified source original, never a directory
        // exemption for headers, scripts or other authored package members.
        assert.equal(lstatSync(join(directory, license.path)).mode & 0o111, 0,
          'Executable runtime license header');
        artifacts.push({sourceSha: source, target: 'native-runtime-original-header',
          module: license.path, sha256: license.sha256,
          verification: {...runtimeVerification, role: 'original-license-header',
            libraryRoles: local!.libraries.filter(library => library.license === license.path)
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
    artifactSource: source, checkedSource: checkedHead, correspondence, dependencies,
    ...(artifactMaterial === undefined ? {} : {artifactMaterial})};
}
