// One exact normal package cohort, installed outside the checkout. An explicit
// release input retains its staged metadata; default CI uses development packs.
// The authored acceptance entry and replay child use only public exports.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {CLIENT_PACKAGES, checkoutState, normalNpmPackJsonArgs, packClientPackages,
  packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {nodeTestArguments, assertTestExecution} from './test-execution.mjs';
import {admitCompositionRelease} from './composition-release-input.mjs';
import {sheetsPackedSelection, sheetsPackedFixturePaths} from './sheets-packed-cases.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const state = checkoutState(repository);
if (!state.clean) throw new Error('Build inputs differ from HEAD');
const selection = sheetsPackedSelection(process.argv.slice(2));
// Existing admission checks source, normal prepack, archive bytes and modes.
// A foreign release is refused before creating an installation, Site or Run.
const normalRelease = selection.directory === undefined ? undefined
  : await admitCompositionRelease({repository, directory: selection.directory});
const directory = await withPackedQueryEvidence({
  scratch: join(repository, '..', '.codex-scratch'), revision: state.revision,
  // A deliberately uncertain range request retains its installation/runtime
  // alongside the original private Run/DB/key custody after test closure.
  keepArtifacts: true,
}, async ({root, recordTarball, run}) => {
  const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
  delete environment.NODE_PATH;
  delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
  delete environment.ACTQL_LOCAL_EFFECT_PROFILE;
  let names, archives;
  if (normalRelease === undefined) {
    // CI does not choose a release version. Use the same lifecycle-enabled
    // five-package producer and source/digest-checked reuse as other consumers.
    const producer = join(root, 'packages');
    names = CLIENT_PACKAGES;
    await packClientPackages({repository, destination: producer, names,
      pack: name => packedClientPackage({repository, name, destination: producer,
        pack: () => run('npm', normalNpmPackJsonArgs([
          'pack', '--pack-destination', producer, '--json',
        ]), {cwd: join(repository, 'packages', name), env: environment, timeout: 600_000})})});
    const manifest = JSON.parse(await readFile(join(producer, 'packed-client-packages.json'), 'utf8'));
    assert.equal(manifest.revision, state.revision);
    assert.deepEqual(Object.keys(manifest.tarballs), names);
    archives = names.map(name => join(producer, `actql-${name}-0.0.0-development.tgz`));
    console.log('SHEETS_ARTIFACT_COHORT', JSON.stringify({sourceSha: manifest.revision,
      generation: 'normal-prepack-development', tarballs: manifest.tarballs}));
  } else {
    const manifest = normalRelease.manifest;
    assert.equal(manifest.sourceSha, state.revision);
    names = manifest.cohort.packages;
    archives = normalRelease.archives;
    console.log('SHEETS_ARTIFACT_COHORT', JSON.stringify({sourceSha: manifest.sourceSha,
      manifestSha256: normalRelease.manifestSha256,
      cohort: manifest.cohort, toolchain: manifest.toolchain,
      recipeSha256: manifest.recipeSha256, cohortSha256: manifest.cohortSha256,
      generation: manifest.generation,
      packages: manifest.packages.map(({name, version, file, sha256, integrity}) =>
        ({name, version, file, sha256, integrity}))}));
  }
  for (const archive of archives) recordTarball(archive);
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--offline', '--no-save', '--no-audit', '--no-fund',
    ...archives], {cwd: root, env: environment});
  auditPackedPackages(root, names);
  for (const path of sheetsPackedFixturePaths) {
    await mkdir(dirname(join(root, path)), {recursive: true});
    await copyFile(join(repository, path), join(root, path));
    assert.deepEqual(await readFile(join(root, path)), await readFile(join(repository, path)));
  }
  const args = nodeTestArguments(selection.testArguments);
  const stdout = run(process.execPath, args, {cwd: root, env: environment, timeout: 180_000});
  const checked = assertTestExecution('node', process.execPath, args, {status: 0, stdout});
  assert.equal(checked.counts.passed, selection.expectedTests);
  await normalRelease?.verifyUnchanged();
  assert.deepEqual(checkoutState(repository), state);
  console.log('PACKED_SHEETS_VERIFIED', JSON.stringify({revision: state.revision,
    rangeOnly: selection.rangeOnly, counts: checked.counts}));
});
console.log(`Packed Sheets evidence: ${directory}`);
