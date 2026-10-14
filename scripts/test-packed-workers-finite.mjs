// Consume only a verified clean-source cohort produced through npm prepack.
// This test never repairs package bytes or falls back to checkout adapters.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, mkdir, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {finiteOriginalMaterials} from '../adapters/workers/finite-runtime-fixture.mjs';

if (!process.env.ACTQL_PACKED_CLIENT_PACKAGES) {
  throw new Error('A verified ACTQL_PACKED_CLIENT_PACKAGES cohort is required');
}
const repository = fileURLToPath(new URL('../', import.meta.url));
await mkdir(join(repository, '_build'), {recursive: true});
const installation = await mkdtemp(join(repository, '_build/packed-workers-finite-'));
for (const name of ['client-wire', 'run-host-core']) {
  await packedClientPackage({repository, name, destination: installation,
    pack() { throw new Error('A verified package may not fall back to repacking'); }});
}
await writeFile(join(installation, 'package.json'), '{"private":true,"type":"module"}\n');
const npm = spawnSync('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
  '--no-audit', '--no-fund',
  join(installation, 'actql-client-wire-0.0.0-development.tgz'),
  join(installation, 'actql-run-host-core-0.0.0-development.tgz')], {
  cwd: installation, encoding: 'utf8', timeout: 60000,
  env: {...process.env, npm_config_cache: packedNpmCache(installation)},
});
assert.equal(npm.status, 0, npm.error?.message ?? npm.stderr);
await writeFile(join(installation, 'acceptance.mjs'), await readFile(join(repository,
  'scripts/fixtures/workers-finite-package-acceptance.mjs')));
const rows = [{id: 3}, {id: null}, {id: 3}, {id: 1}];
const input = finiteOriginalMaterials({rows, nullable: true});
await writeFile(join(installation, 'original.json'), JSON.stringify(input,
  (_, value) => typeof value === 'bigint' ? {bigint: String(value)} : value));
await writeFile(join(installation, 'smoke.mjs'), `
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {createWorkersFiniteRuntime, workersFiniteArtifact} from '@actql/run-host-core/workers-finite';
import {exerciseWorkersFinitePackage} from './acceptance.mjs';
const entry = import.meta.resolve('@actql/run-host-core/workers-finite');
const bytes = readFileSync(new URL('./workers_finite_payload.js', entry));
assert.deepEqual(workersFiniteArtifact, {
  componentCid: 'sha256:' + createHash('sha256').update(bytes).digest('hex'),
  componentBytes: bytes.length,
});
assert.doesNotMatch(bytes.toString(), /workersFiniteFixture|workers_conformance/);
globalThis.fetch = async () => { throw new Error('UnexpectedFiniteNetwork'); };
const input = JSON.parse(readFileSync('original.json', 'utf8'), (_, value) =>
  value && typeof value === 'object' && Object.keys(value).length === 1 &&
  typeof value.bigint === 'string' ? BigInt(value.bigint) : value);
const result = await exerciseWorkersFinitePackage(createWorkersFiniteRuntime, input);
assert.deepEqual(result.rows, ${JSON.stringify(rows)});
assert.equal(result.measurement.rowCount, 4);
assert.deepEqual(result.measurement.columnNullRows, [1]);
console.log(JSON.stringify({status: 'passed', ...workersFiniteArtifact,
  rows: result.rows.length, logicalRelationCid: result.identity.logicalRelationCid}));
`);
const smoke = spawnSync(process.execPath, ['smoke.mjs'], {cwd: installation,
  encoding: 'utf8', timeout: 60000});
assert.equal(smoke.status, 0, smoke.error?.message ?? smoke.stderr);
console.log(smoke.stdout.trim());
console.log(`Verified packed Worker installation: ${installation}`);
