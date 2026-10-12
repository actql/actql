import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {stagePackedGcsFixture, packedGcsFixtureInputs, packedGcsDeclarationAsset} from './packed-gcs-content-fixture.mjs';

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-packed-gcs-unit-'));
  t.after(() => rm(root, {recursive: true}));
  const repository = join(root, 'source'), application = join(root, 'consumer');
  await mkdir(repository); await mkdir(application);
  await mkdir(dirname(join(application, packedGcsDeclarationAsset)), {recursive: true});
  await writeFile(join(application, packedGcsDeclarationAsset), 'export const fixture = true;\n');
  for (const path of packedGcsFixtureInputs) {
    await mkdir(dirname(join(repository, path)), {recursive: true});
    await writeFile(join(repository, path), path === packedGcsFixtureInputs[0]
      ? 'import {connect} from "@actql/local-node"; import {connect as remote} from "@actql/sdk"; export {connect, remote};\n'
      : 'export const fixture = true;\n');
  }
  return {root, repository, application};
}
test('staging keeps product imports external and records authored inputs, not checkout runtime', async t => {
  const value = await fixture(t);
  const staged = await stagePackedGcsFixture(value);
  assert.equal(staged.copiedProductSources, 0);
  assert.equal(staged.inputs.length, 4);
  assert.match(staged.sha256, /^[0-9a-f]{64}$/u);
  const output = await readFile(staged.entry, 'utf8');
  assert.ok(output.includes('@actql/local-node'));
  assert.ok(output.includes('@actql/sdk'));
  assert.equal(output.includes(value.repository), false);
});
test('staging refuses a consumer inside its source checkout', async t => {
  const value = await fixture(t);
  const nested = join(value.repository, 'consumer');
  await mkdir(nested);
  await assert.rejects(stagePackedGcsFixture({...value, application: nested}), /GcsConsumerMustBeExternal/u);
});
test('staging refuses unlisted product-source imports rather than bundling a fallback', async t => {
  const value = await fixture(t);
  await writeFile(join(value.repository, packedGcsFixtureInputs[0]),
    'import "../../adapters/host-node/embedded-local.mjs";\n');
  await assert.rejects(stagePackedGcsFixture(value), /UndeclaredPackedGcsImport/u);
});
test('staging refuses symlinked authored input', async t => {
  const value = await fixture(t);
  const path = join(value.repository, packedGcsFixtureInputs[1]);
  await rm(path);
  await symlink(join(value.repository, packedGcsFixtureInputs[2]), path);
  await assert.rejects(stagePackedGcsFixture(value), /InvalidPackedGcsFixture/u);
});
test('staging uses public Client and runtime entrances plus the recorded installed declaration asset', async t => {
  const value = await fixture(t);
  const staged = await stagePackedGcsFixture({repository: process.cwd(), application: value.application});
  assert.deepEqual(staged.productImports,
    ['@actql/local-node', '@actql/local-node/http-host', '@actql/sdk', '@actql/sdk/host-port', '@actql/local-node/runtime']);
  assert.deepEqual(staged.productAssets.map(value => value.path), [packedGcsDeclarationAsset]);
  assert.equal(staged.copiedProductSources, 0);
});
test('staging refuses a missing installed GCS declaration asset', async t => {
  const value = await fixture(t);
  await rm(join(value.application, packedGcsDeclarationAsset));
  await assert.rejects(stagePackedGcsFixture(value), {code: 'ENOENT'});
});
test('staging refuses a declaration asset linked back into checkout', async t => {
  const value = await fixture(t);
  const asset = join(value.application, packedGcsDeclarationAsset);
  await rm(asset);
  await symlink(join(value.repository, packedGcsFixtureInputs[1]), asset);
  await assert.rejects(stagePackedGcsFixture(value), /InvalidPackagedGcsDeclaration/u);
});
