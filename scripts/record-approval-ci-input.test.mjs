// Independent tiny archive fixtures exercise input admission only. No SDK,
// Host, native image, npm install or provider operation executes in this file.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {CLIENT_PACKAGES} from './packed-client-packages.mjs';
import {admitRecordApprovalCIInput} from './record-approval-ci-input.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const run = (command, args, cwd) => execFileSync(command, args,
  {cwd, encoding: 'utf8', timeout: 10000});

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-approval-ci-input-'));
  const previous = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  t.after(async () => {
    if (previous === undefined) delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
    else process.env.ACTQL_PACKED_CLIENT_PACKAGES = previous;
    await rm(root, {recursive: true});
  });
  const repository = join(root, 'source'), directory = join(root, 'original'), destination = join(root, 'copy');
  await mkdir(repository); await mkdir(directory);
  await writeFile(join(repository, 'source.txt'), 'original independent source\n');
  run('git', ['init', '--quiet'], repository);
  run('git', ['add', 'source.txt'], repository);
  run('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'user.name=Input fixture',
    '-c', 'user.email=input@example.invalid', '-c', 'commit.gpgsign=false',
    'commit', '--quiet', '-m', 'test: retain independent input'], repository);
  const manifest = {revision: run('git', ['rev-parse', 'HEAD'], repository).trim(), tarballs: {}};
  const archive = async (name, packageName = '@actql/' + name) => {
    const stage = join(root, 'stage-' + name); await mkdir(join(stage, 'package'), {recursive: true});
    await writeFile(join(stage, 'package/package.json'), JSON.stringify({name: packageName, version: '0.0.0-development'}));
    await writeFile(join(stage, 'package/input.txt'), 'independent archive DATA\n');
    const path = join(directory, `actql-${name}-0.0.0-development.tgz`);
    run('tar', ['-czf', path, '-C', stage, 'package'], root);
    manifest.tarballs[name] = digest(await readFile(path));
    return path;
  };
  for (const name of CLIENT_PACKAGES) await archive(name);
  const manifestPath = join(directory, 'packed-client-packages.json');
  const saveManifest = () => writeFile(manifestPath, JSON.stringify(manifest) + '\n');
  await saveManifest(); process.env.ACTQL_PACKED_CLIENT_PACKAGES = directory;
  return {root, repository, directory, destination, manifest, manifestPath, archive, saveManifest,
    admit: () => admitRecordApprovalCIInput({repository, destination})};
}

test('record approval CI input admits exact five archives and inventories original payload bytes', async t => {
  const f = await fixture(t), actual = await f.admit();
  assert.equal(actual.kind, 'ci-packed-client-packages');
  assert.equal(actual.manifest.sourceSha, f.manifest.revision);
  assert.equal(actual.manifest.packages.length, 5);
  assert.deepEqual(actual.manifest.packages.map(item => item.name), CLIENT_PACKAGES.map(name => '@actql/' + name));
  for (const item of actual.manifest.packages) {
    assert.deepEqual(item.files.map(file => file.path), ['input.txt', 'package.json']);
    assert.equal(item.files[0].sha256, digest('independent archive DATA\n'));
  }
  await actual.verifyUnchanged();
});

test('record approval CI input refuses missing input, foreign revision and dirty source without packing', async t => {
  const f = await fixture(t);
  delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  await assert.rejects(f.admit(), /explicit ACTQL_PACKED_CLIENT_PACKAGES/u);
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = f.directory;
  const original = f.manifest.revision;
  f.manifest.revision = 'f'.repeat(40); await f.saveManifest();
  await assert.rejects(f.admit(), /exact packed source/u);
  f.manifest.revision = original; await f.saveManifest();
  await writeFile(join(f.repository, 'source.txt'), 'changed source\n');
  await assert.rejects(f.admit(), /clean source/u);
});

test('record approval CI input preserves original manifest, original archive and copied archive fences', async t => {
  const f = await fixture(t), actual = await f.admit();
  const wire = await readFile(f.manifestPath);
  await writeFile(f.manifestPath, Buffer.concat([wire, Buffer.from('\n')]));
  await assert.rejects(actual.verifyUnchanged(), /Original packed manifest changed/u);
  await writeFile(f.manifestPath, wire);
  const originalPath = join(f.directory, actual.manifest.packages[0].file), original = await readFile(originalPath);
  await writeFile(originalPath, Buffer.concat([original, Buffer.from('changed')]));
  await assert.rejects(actual.verifyUnchanged(), /Original packed archive changed/u);
  await writeFile(originalPath, original);
  await writeFile(actual.archives[0], Buffer.concat([original, Buffer.from('changed')]));
  await assert.rejects(actual.verifyUnchanged(), /Copied packed archive changed/u);
});

test('record approval CI input refuses incomplete cohort and mismatched package identity', async t => {
  const f = await fixture(t), original = f.manifest.tarballs.node;
  delete f.manifest.tarballs.node; await f.saveManifest();
  await assert.rejects(f.admit(), /complete five-package input/u);
  f.manifest.tarballs.node = original;
  await f.archive('client-wire', '@actql/unexpected'); await f.saveManifest();
  await assert.rejects(f.admit(), /original named package/u);
});
