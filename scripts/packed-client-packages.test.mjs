// Shared Client tarballs are used only for the exact checkout they were
// packed from: every build input a pack reads, not only packages/.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {appendFile, mkdir, mkdtemp, readFile, rm, writeFile} from
  'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {packClientPackages, packedClientPackage} from
  './packed-client-packages.mjs';

const tarball = name => `actql-${name}-0.0.0-development.tgz`;
const git = (repository, ...args) => execFileSync('git', args,
  {cwd: repository, encoding: 'utf8'});

// A repository with one file in each build input directory, an ignored
// generated directory, and one packed tarball shared through a manifest.
async function fixture(t) {
  const base = await mkdtemp(join(tmpdir(), 'actql-packed-client-'));
  t.after(() => rm(base, {recursive: true, force: true}));
  const repository = join(base, 'repository');
  for (const directory of ['packages/sdk', 'src', 'adapters', 'spec',
    'scripts', '_build']) {
    await mkdir(join(repository, directory), {recursive: true});
  }
  for (const file of ['packages/sdk/index.mjs', 'src/core.mbt',
    'adapters/host.mjs', 'spec/contract.json', 'scripts/generate.mjs',
    'README.md']) {
    await writeFile(join(repository, file), `${file}\n`);
  }
  await writeFile(join(repository, '.gitignore'), '_build/\n');
  git(repository, 'init', '-q');
  git(repository, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
    'add', '.');
  git(repository, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
    'commit', '-q', '-m', 'fixture');
  const shared = join(base, 'shared');
  const pack = name => writeFile(join(shared, tarball(name)),
    `${name} packed\n`);
  await packClientPackages({repository, destination: shared, names: ['sdk'],
    pack});
  const destination = join(base, 'install');
  await mkdir(destination);
  const previous = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = shared;
  t.after(() => {
    if (previous === undefined) delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
    else process.env.ACTQL_PACKED_CLIENT_PACKAGES = previous;
  });
  const reuse = () => packedClientPackage({repository, name: 'sdk',
    destination, pack: () => assert.fail('packed again instead of reusing')});
  return {base, repository, shared, destination, pack, reuse};
}

test('an unchanged checkout reuses the shared tarball as packed', async t => {
  const {repository, destination, reuse} = await fixture(t);
  // Generated output and scratch outside the build inputs do not count.
  await writeFile(join(repository, '_build', 'generated.js'), 'generated\n');
  await mkdir(join(repository, '.native-tests'));
  await writeFile(join(repository, '.native-tests', 'scratch'), 'scratch\n');
  await reuse();
  assert.equal(await readFile(join(destination, tarball('sdk')), 'utf8'),
    'sdk packed\n');
});

for (const file of ['src/core.mbt', 'adapters/host.mjs', 'spec/contract.json',
  'scripts/generate.mjs', 'packages/sdk/index.mjs', 'README.md']) {
  test(`a tracked change to ${file} refuses the shared tarball`, async t => {
    const {repository, reuse} = await fixture(t);
    await appendFile(join(repository, file), 'changed\n');
    await assert.rejects(reuse(), /build inputs changed/u);
  });
}

for (const file of ['src/new.mbt', 'adapters/new.mjs', 'spec/new.json',
  'scripts/new.mjs', 'packages/sdk/new.mjs']) {
  test(`an untracked ${file} refuses the shared tarball`, async t => {
    const {repository, reuse} = await fixture(t);
    await writeFile(join(repository, file), 'new\n');
    await assert.rejects(reuse(), /build inputs changed/u);
  });
}

test('another revision refuses the shared tarball', async t => {
  const {repository, reuse} = await fixture(t);
  await appendFile(join(repository, 'src/core.mbt'), 'committed\n');
  git(repository, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
    'commit', '-q', '-am', 'next');
  await assert.rejects(reuse(), /were packed from [0-9a-f]+, not this checkout/u);
});

test('a tarball changed after packing is refused', async t => {
  const {shared, reuse} = await fixture(t);
  await appendFile(join(shared, tarball('sdk')), 'tampered\n');
  await assert.rejects(reuse(), /changed after packing/u);
});

test('no manifest is recorded from a dirty checkout or one changed while packing',
  async t => {
    const {base, repository} = await fixture(t);
    await appendFile(join(repository, 'src/core.mbt'), 'dirty\n');
    await assert.rejects(packClientPackages({repository,
      destination: join(base, 'dirty'), names: ['sdk'], pack: name =>
        writeFile(join(base, 'dirty', tarball(name)), 'x\n')}),
    /Build inputs differ from HEAD/u);
    git(repository, 'checkout', '--', 'src/core.mbt');
    const destination = join(base, 'during');
    await assert.rejects(packClientPackages({repository, destination,
      names: ['sdk'], pack: async name => {
        await writeFile(join(destination, tarball(name)), 'x\n');
        await appendFile(join(repository, 'adapters/host.mjs'), 'edited\n');
      }}), /Build inputs changed while packing/u);
    await assert.rejects(readFile(join(destination,
      'packed-client-packages.json')), {code: 'ENOENT'});
  });
