// Compose the original Native artifact and installed/source interface readers.
// Header/member checks are not execution or a new compiler provenance issuer.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {installedInterfaceCorrespondence, assertInstalledDependencyClosure} from './installed-interface-correspondence.mjs';
import {admitInstalledNativeArtifact} from './native-cli-artifact-reader.mjs';
import {nativeCliLauncherInputs} from './native-cli-package-inputs.mjs';

export async function checkStagedNativeCliInterfaces({repository, directory, source, checkedSource, artifact}) {
  assert.match(source, /^[a-f0-9]{40}$/u);
  execFileSync('git', ['cat-file', '-e', `${source}^{commit}`], {cwd: repository});
  const checkedHead = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim();
  const metadata = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8'));
  const artifacts = [];
  let bindings;
  if (artifact === undefined) {
    assert.equal(metadata.name, 'actql');
    bindings = nativeCliLauncherInputs.map(member => ({member, source: `packages/native-cli/${member}`}));
  } else {
    const original = await admitInstalledNativeArtifact(directory, source);
    assert.deepEqual(original, artifact, 'Changed original CLI artifact admission');
    assert.equal(metadata.name, `@actql/cli-${original.platform}`);
    const proof = {sourceSha: source, target: 'native', verification: {
      build: 'scripts/native-cli-artifact.mjs', generatedCSha256: original.generatedCSha256,
      toolchainPinSha256: original.toolchainPinSha256}};
    artifacts.push({...proof, module: 'bin/actql-native-client', sha256: original.binarySha256});
    for (const library of original.localRuntime?.libraries ?? []) {
      artifacts.push({...proof, module: library.path, sha256: library.sha256});
    }
    bindings = [];
  }
  const installed = installedInterfaceInventory(directory, {artifacts});
  const correspondence = installedInterfaceCorrespondence({repository, directory, source,
    bindings, artifacts, checkedSource, generated: checkedSource.generatedQualification,
    owners: interfaceOwnerDeclarations(repository)});
  const dependencies = await assertInstalledDependencyClosure({directory,
    modules: installed.modules, artifacts});
  assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], {cwd: repository, encoding: 'utf8'}).trim(), checkedHead);
  return {qualification: 'ordinary CLI member/source/reference correspondence; not Native execution or compiler provenance',
    artifactSource: source, checkedSource: checkedHead, correspondence, dependencies};
}
