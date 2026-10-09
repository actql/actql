// One exact release cohort, installed outside the checkout. Product imports
// in the authored acceptance entry and its replay child are public exports.
import assert from 'node:assert/strict';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState, CLIENT_PACKAGES, packClientPackages,
  packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {auditPackedPackages} from './packed-package-boundaries.mjs';
import {withPackedQueryEvidence} from './packed-query-evidence.mjs';
import {nodeTestArguments, assertTestExecution} from './test-execution.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const state = checkoutState(repository);
if (!state.clean) throw new Error('Build inputs differ from HEAD');
const tarball = name => `actql-${name}-0.0.0-development.tgz`;
const directory = await withPackedQueryEvidence({
  scratch: join(repository, '..', '.codex-scratch'), revision: state.revision,
}, async ({root, recordTarball, run}) => {
  const environment = {...process.env, npm_config_cache: packedNpmCache(root)};
  delete environment.NODE_PATH;
  delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
  delete environment.ACTQL_LOCAL_EFFECT_PROFILE;
  const producer = environment.ACTQL_PACKED_CLIENT_PACKAGES || join(root, 'producer');
  if (!environment.ACTQL_PACKED_CLIENT_PACKAGES) {
    await packClientPackages({repository, destination: producer,
      pack: name => run('npm', ['pack', '--json', '--pack-destination', producer], {
        cwd: join(repository, 'packages', name), env: environment, timeout: 600_000,
      })});
  }
  // Reuse is accepted only after the existing exact SHA/clean input/digest checks.
  const previous = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = producer;
  try {
    for (const name of CLIENT_PACKAGES) {
      await packedClientPackage({repository, name, destination: root,
        pack: () => { throw new Error('Missing exact Sheets package cohort'); }});
      recordTarball(join(root, tarball(name)));
    }
  } finally {
    if (previous === undefined) delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
    else process.env.ACTQL_PACKED_CLIENT_PACKAGES = previous;
  }
  const manifest = JSON.parse(await readFile(join(producer, 'packed-client-packages.json'), 'utf8'));
  assert.equal(manifest.revision, state.revision);
  console.log('SHEETS_ARTIFACT_COHORT', JSON.stringify(manifest));
  await writeFile(join(root, 'package.json'), '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--offline', '--no-save', '--no-audit', '--no-fund',
    ...CLIENT_PACKAGES.map(name => join(root, tarball(name)))], {cwd: root, env: environment});
  auditPackedPackages(root, CLIENT_PACKAGES);
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
  assert.equal(checked.counts.passed, 12);
  console.log('PACKED_SHEETS_VERIFIED', JSON.stringify({revision: state.revision, counts: checked.counts}));
});
console.log(`Packed Sheets evidence: ${directory}`);
