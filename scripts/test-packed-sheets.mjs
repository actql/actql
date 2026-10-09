// One exact release cohort, installed outside the checkout. Product imports
// in the authored acceptance entry and its replay child are public exports.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState, packedNpmCache} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {nodeTestArguments, assertTestExecution} from './test-execution.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const state = checkoutState(repository);
if (!state.clean) throw new Error('Build inputs differ from HEAD');
const directory = await withPackedQueryEvidence({
  scratch: join(repository, '..', '.codex-scratch'), revision: state.revision,
}, async ({root, recordTarball, run}) => {
  const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
  delete environment.NODE_PATH;
  delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
  delete environment.ACTQL_LOCAL_EFFECT_PROFILE;
  delete environment.ACTQL_PACKED_CLIENT_PACKAGES;
  const producer = join(root, 'release');
  // The existing release recipe runs normal producer prepack, then changes
  // metadata/license only and verifies all frozen runtime bytes and digests.
  const recipe = join(repository, 'scripts/package-release.mjs');
  run(process.execPath, [recipe, 'prepare', producer], {
    cwd: repository, env: environment, timeout: 900_000,
  });
  run(process.execPath, [recipe, 'verify', producer], {cwd: repository, env: environment});
  const manifest = JSON.parse(await readFile(join(producer, 'release.json'), 'utf8'));
  assert.equal(manifest.sourceSha, state.revision);
  const names = manifest.cohort.packages;
  assert.deepEqual(names, ['client-wire', 'sdk', 'local-node', 'node']);
  const archives = manifest.packages.map(item => join(producer, item.file));
  for (const archive of archives) recordTarball(archive);
  console.log('SHEETS_ARTIFACT_COHORT', JSON.stringify({sourceSha: manifest.sourceSha,
    cohort: manifest.cohort, toolchain: manifest.toolchain,
    recipeSha256: manifest.recipeSha256, cohortSha256: manifest.cohortSha256,
    generation: manifest.generation,
    packages: manifest.packages.map(({name, version, file, sha256, integrity}) =>
      ({name, version, file, sha256, integrity}))}));
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--offline', '--no-save', '--no-audit', '--no-fund',
    ...archives], {cwd: root, env: environment});
  auditPackedPackages(root, names);
  for (const path of [
    'adapters/site-node/https-exchange-fixture.mjs',
    ...['sheets-api.fixture.mjs', 'sheets-public-acceptance.fixture.mjs',
      'sheets-replay.fixture.mjs', 'sheets-replay-packed.fixture.mjs',
      'sheets-packed.fixture.mjs'].map(name => `adapters/connectors/sheets/test/${name}`),
  ]) {
    await mkdir(dirname(join(root, path)), {recursive: true});
    await copyFile(join(repository, path), join(root, path));
    assert.deepEqual(await readFile(join(root, path)), await readFile(join(repository, path)));
  }
  const args = nodeTestArguments(['adapters/connectors/sheets/test/sheets-packed.fixture.mjs']);
  const stdout = run(process.execPath, args, {cwd: root, env: environment, timeout: 180_000});
  const checked = assertTestExecution('node', process.execPath, args, {status: 0, stdout});
  assert.equal(checked.counts.passed, 14);
  console.log('PACKED_SHEETS_VERIFIED', JSON.stringify({revision: state.revision, counts: checked.counts}));
});
console.log(`Packed Sheets evidence: ${directory}`);
