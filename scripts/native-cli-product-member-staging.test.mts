// Small staging fixtures only: no Native image, package build/install or Run.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmod, mkdir, mkdtemp, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {stageProductMembers, verifyStagedProductMembers, launcherMemberPlatform} from './native-cli-product-members.mjs';
import {DUAL_LOCAL_LAUNCHER_PLATFORM, installedProductCensus} from '../packages/native-cli/lib/product-members.mjs';

import type {TestContext} from 'node:test';
import type {BinaryLike} from 'node:crypto';

const selected = {sourceSha: 'a'.repeat(40), platform: 'darwin-arm64', packageName: 'actql'};
const sha = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');
const descriptorName = 'local-product-members.json';

async function fixture(t: TestContext) {
  const root = await mkdtemp(join(tmpdir(), 'actql-d-member-stage-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  await mkdir(join(root, 'bin'));
  await writeFile(join(root, 'LICENSE'), 'abc'); await chmod(join(root, 'LICENSE'), 0o644);
  await writeFile(join(root, 'bin/actql.mjs'), '1234567'); await chmod(join(root, 'bin/actql.mjs'), 0o755);
  return root;
}

test('private stage emits exact descriptor bytes with independent fixture digests', async t => {
  const root = await fixture(t), metadata = await stageProductMembers(root, selected);
  const wire = await readFile(join(root, descriptorName), 'utf8');
  const literal = '{"files":[{"bytes":3,"mode":420,"path":"LICENSE","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},{"bytes":7,"mode":493,"path":"bin/actql.mjs","sha256":"8bb0cf6eb9b17d0f7d22b456f121257dc1254e1f01665370476383ea776df414"}],"packageName":"actql","platform":"darwin-arm64","sourceSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}';
  assert.equal(wire, literal);
  assert.deepEqual(metadata, {path: descriptorName, bytes: 352,
    sha256: '82767f3dc5482dd0b524f0324277396b51d0225611bb602fdf7ab30834081155'});
  const read = await verifyStagedProductMembers(root, selected, metadata);
  assert.equal(read.files.length, 2);
  assert(!read.files.some(v => v.path === descriptorName));
});

test('same stage never overwrites an existing descriptor', async t => {
  const root = await fixture(t); await stageProductMembers(root, selected);
  const before = await readFile(join(root, descriptorName));
  await assert.rejects(stageProductMembers(root, selected), /must not hash itself/u);
  assert.deepEqual(await readFile(join(root, descriptorName)), before);
});

test('member hash, bytes and mode changes refuse', async t => {
  for (const change of ['hash', 'bytes', 'mode']) {
    const root = await fixture(t), metadata = await stageProductMembers(root, selected);
    if (change === 'hash') await writeFile(join(root, 'LICENSE'), 'xyz');
    if (change === 'bytes') await writeFile(join(root, 'LICENSE'), 'abcdef');
    if (change === 'mode') await chmod(join(root, 'LICENSE'), 0o600);
    await assert.rejects(verifyStagedProductMembers(root, selected, metadata));
  }
});

test('unknown files and empty directories have no census exception', async t => {
  for (const kind of ['file', 'directory', 'nested-directory']) {
    const root = await fixture(t), metadata = await stageProductMembers(root, selected);
    if (kind === 'file') await writeFile(join(root, 'extra'), 'x');
    if (kind === 'directory') await mkdir(join(root, 'extra'));
    if (kind === 'nested-directory') await mkdir(join(root, 'bin', 'empty'));
    await assert.rejects(verifyStagedProductMembers(root, selected, metadata));
  }
});

test('descriptor, member and parent symlinks refuse without fallback', async t => {
  for (const kind of ['descriptor', 'member', 'parent']) {
    const root = await fixture(t), metadata = await stageProductMembers(root, selected);
    if (kind === 'descriptor') {
      await writeFile(join(root, 'copy'), await readFile(join(root, descriptorName)));
      await rm(join(root, descriptorName)); await symlink('copy', join(root, descriptorName));
    }
    if (kind === 'member') {
      await rm(join(root, 'bin/actql.mjs')); await symlink('../LICENSE', join(root, 'bin/actql.mjs'));
    }
    if (kind === 'parent') {
      await rm(join(root, 'bin'), {recursive: true}); await symlink('.', join(root, 'bin'));
    }
    await assert.rejects(verifyStagedProductMembers(root, selected, metadata));
  }
});

test('descriptor source/platform/package and external hash stay separate comparisons', async t => {
  const root = await fixture(t), metadata = await stageProductMembers(root, selected);
  for (const expected of [{...selected, sourceSha: 'b'.repeat(40)},
    {...selected, platform: 'linux-x64-gnu'}, {...selected, packageName: '@actql/cli-darwin-arm64'}]) {
    await assert.rejects(verifyStagedProductMembers(root, expected, metadata));
  }
  await assert.rejects(verifyStagedProductMembers(root, selected, {...metadata, sha256: 'b'.repeat(64)}));
  await assert.rejects((verifyStagedProductMembers as (directory: string, selected: unknown, metadata: unknown) => Promise<unknown>)(root, selected, {...metadata, bytes: '355'}));
});

test('self descriptor rewrite cannot borrow a previous external binding', async t => {
  const root = await fixture(t), metadata = await stageProductMembers(root, selected);
  const body = await readFile(join(root, descriptorName), 'utf8');
  const changed = body.replace('"sourceSha":"a', '"sourceSha":"b');
  await writeFile(join(root, descriptorName), changed);
  await assert.rejects(verifyStagedProductMembers(root, selected, metadata));
  // A caller's replacement digest still cannot change the selected source.
  await assert.rejects(verifyStagedProductMembers(root, selected, {...metadata, sha256: sha(changed)}));
});

test('launcher descriptor selects one finite profile without changing multi Remote packaging', () => {
  const darwin = {platform: 'darwin-arm64'}, linux = {platform: 'linux-x64-gnu'};
  assert.equal(launcherMemberPlatform([darwin]), 'darwin-arm64');
  assert.equal(launcherMemberPlatform([darwin, linux]), undefined);
  assert.equal(launcherMemberPlatform([{...darwin, localRuntime: {}}, linux]), 'darwin-arm64');
  assert.equal(launcherMemberPlatform([{...darwin, localRuntime: {}}, {...linux, localRuntime: {}}]), DUAL_LOCAL_LAUNCHER_PLATFORM);
  assert.equal(launcherMemberPlatform([{...linux, localRuntime: {}}, {...darwin, localRuntime: {}}]), DUAL_LOCAL_LAUNCHER_PLATFORM);
  for (const records of [[], [darwin, darwin], [{platform: 'linux-arm64-gnu'}], [darwin, linux, darwin]])
    assert.throws(() => launcherMemberPlatform(records));
});


test('one dual launcher descriptor verifies the same strict payload on each exact platform', async t => {
  const root = await fixture(t), shared = {...selected, platform: DUAL_LOCAL_LAUNCHER_PLATFORM};
  const metadata = await stageProductMembers(root, shared);
  const raw = await readFile(join(root, descriptorName), 'utf8');
  assert(raw.includes('"platform":"darwin-arm64+linux-x64-gnu"'));
  for (const platform of ['darwin-arm64', 'linux-x64-gnu']) {
    const launcher = await verifyStagedProductMembers(root, {...selected, platform}, metadata);
    assert.equal(launcher.platform, DUAL_LOCAL_LAUNCHER_PLATFORM);
    const osPackage = {...launcher, platform, packageName: `@actql/cli-${platform}`};
    const placement = installedProductCensus(launcher, osPackage, '/installed/actql',
      `/installed/actql/node_modules/@actql/cli-${platform}`);
    assert.equal(placement.layout, 'nested');
    assert.deepEqual(placement.launcher.directories.at(-1), {path: 'node_modules/@actql',
      entries: [{name: `cli-${platform}`, kind: 'directory'}]});
  }
  await assert.rejects(verifyStagedProductMembers(root, {...selected, sourceSha: 'b'.repeat(40)}, metadata));
  await assert.rejects(verifyStagedProductMembers(root, {...selected, platform: 'linux-arm64-gnu'}, metadata));
  await assert.rejects(verifyStagedProductMembers(root, {...shared, packageName: '@actql/cli-linux-x64-gnu'}, metadata));
  await assert.rejects(verifyStagedProductMembers(root, selected, {...metadata, sha256: 'b'.repeat(64)}));
});

test('dual launcher payload and generation remain exact physical staging obligations', async t => {
  const root = await fixture(t), shared = {...selected, platform: DUAL_LOCAL_LAUNCHER_PLATFORM};
  const metadata = await stageProductMembers(root, shared);
  const before = await readFile(join(root, descriptorName));
  await writeFile(join(root, descriptorName), before.toString().replace('darwin-arm64+linux-x64-gnu', 'linux-x64-gnu+darwin-arm64'));
  await assert.rejects(verifyStagedProductMembers(root, selected, metadata));
  await writeFile(join(root, descriptorName), before);
  await writeFile(join(root, 'bin/actql.mjs'), 'changed');
  await assert.rejects(verifyStagedProductMembers(root, selected, metadata));
});
