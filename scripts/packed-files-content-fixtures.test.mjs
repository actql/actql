import assert from 'node:assert/strict';
import {mkdir, mkdtemp, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {contentFixtureData, contentFixtureFiles, contentProductFiles,
  stagePackedContentFixtures} from './packed-files-content-fixtures.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
async function setup(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-packed-content-staging-'));
  t.after(() => rm(root, {recursive: true}));
  const application = join(root, 'application');
  const packageRoot = join(application, 'node_modules/@actql/local-node');
  const runtime = '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
  for (const name of [...contentProductFiles, runtime]) {
    const path = join(packageRoot, name);
    await mkdir(dirname(path), {recursive: true});
    await writeFile(path, '// Staging-only synthetic package asset; never executed.\n');
  }
  const sdk = join(application, 'node_modules/@actql/sdk');
  await mkdir(sdk, {recursive: true});
  await writeFile(join(sdk, 'index.mjs'), '// Synthetic SDK asset, not runtime evidence.\n');
  return {root, application, packageRoot};
}

test('packed Content fixture keeps product source external and independent inputs exact', async t => {
  const {application, packageRoot} = await setup(t);
  const staged = await stagePackedContentFixtures({repository, application});
  assert.equal(staged.copiedProductSources, 0);
  assert.equal(staged.inputs.length, contentFixtureFiles.length + contentFixtureData.length);
  assert.ok(staged.productImports.includes('@actql/sdk'));
  assert.ok(staged.productImports.includes('@actql/local-node/runtime'));
  assert.ok(staged.productImports.includes('@actql/local-node'));
  assert.ok(staged.productImports.includes('@actql/local-node/http-host'));
  assert.ok(staged.productImports.some(value => value.includes(packageRoot)));
  const output = await readFile(staged.entry, 'utf8');
  assert.ok(!output.includes(repository));
  assert.match(output, /FixtureCommandReplyLost/u);
  assert.match(output, /recovery must not reacquire the Source/u);
  assert.match(output, /UnpreparedGeneratedContentCall/u);
  for (const name of contentFixtureData) assert.deepEqual(
    await readFile(join(application, name)), await readFile(join(repository, name)));
  await assert.rejects(readFile(join(application, 'adapters/host-node/embedded-local.mjs')),
    {code: 'ENOENT'});
});
test('missing product asset fails rather than importing the checkout', async t => {
  const {application, packageRoot} = await setup(t);
  await rm(join(packageRoot, 'adapters/host-node/installed-row-source.mjs'));
  await assert.rejects(stagePackedContentFixtures({repository, application}), {code: 'ENOENT'});
});
test('a linked package outside the consumer is refused', async t => {
  const {root, application, packageRoot} = await setup(t);
  await rm(packageRoot, {recursive: true});
  const external = join(root, 'external');
  await mkdir(external);
  await symlink(external, packageRoot);
  await assert.rejects(stagePackedContentFixtures({repository, application}), /PackedContentPackageLink/u);
});
test('a linked individual product asset is refused', async t => {
  const {root, application, packageRoot} = await setup(t);
  const path = join(packageRoot, 'adapters/host-common/runtime-core.mjs');
  const external = join(root, 'external.mjs');
  await writeFile(external, '// external\n');
  await rm(path);
  await symlink(external, path);
  await assert.rejects(stagePackedContentFixtures({repository, application}), /PackedContentFileEscaped/u);
});
test('an undeclared fixture import cannot drag product source into the bundle', async t => {
  const {root, application} = await setup(t);
  const source = join(root, 'source');
  for (const name of contentFixtureFiles) {
    const path = join(source, name);
    await mkdir(dirname(path), {recursive: true});
    await writeFile(path, name.endsWith('content-command-restart.mjs')
      ? 'import "../embedded-local.mjs"; import "../undeclared-owner.mjs";\n'
      : '// fixture\n');
  }
  await assert.rejects(stagePackedContentFixtures({repository: source, application}),
    /UndeclaredPackedContentImport:adapters\/host-node\/undeclared-owner.mjs/u);
});
test('staging inside the checkout is refused', async () => {
  await assert.rejects(stagePackedContentFixtures({repository, application: repository}),
    /PackedContentApplicationMustBeExternal/u);
});
