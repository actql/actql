import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp, mkdir, readFile, writeFile, copyFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {preparePackageRelease, verifyPackageRelease, releasePackageMetadata} from './package-release.mjs';

const four = JSON.parse(await readFile(new URL('../release/client-cohort.json', import.meta.url)));
const six = JSON.parse(await readFile(new URL('../release/explorer-cohort.json', import.meta.url)));
const git = (root, ...args) => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();

// Actual npm prepack/staging with tiny synthetic payloads; no compiler, Host,
// Source or product runtime. Counters establish that shared prepack ran once.
test('normal six-package prepack supplies an independently verified exact four-package cohort', async t => {
  const scratch = await mkdtemp(join(tmpdir(), 'actql-shared-release-control-'));
  t.after(() => rm(scratch, {recursive: true, force: true}));
  const repository = join(scratch, 'repository'); await mkdir(repository);
  await mkdir(join(repository, 'release'));
  await mkdir(join(repository, 'scripts'));
  await copyFile(new URL('./package-release.mjs', import.meta.url),
    join(repository, 'scripts/package-release.mjs'));
  await writeFile(join(repository, '.gitignore'), 'prepack.calls\n');
  await writeFile(join(repository, 'package.json'), '{"private":true}\n');
  await writeFile(join(repository, 'count.mjs'),
    "import{appendFileSync}from'node:fs';appendFileSync(new URL('./prepack.calls',import.meta.url),process.argv[2]+'\\n');\n");
  await copyFile(new URL('../LICENSE', import.meta.url), join(repository, 'LICENSE'));
  for (const [name, cohort] of [['four', four], ['six', six]])
    await writeFile(join(repository, 'release', name + '.json'), JSON.stringify(cohort));
  for (const [index, name] of six.packages.entries()) {
    const directory = join(repository, 'packages', name); await mkdir(directory, {recursive: true});
    await writeFile(join(directory, 'package.json'), JSON.stringify({
      name: '@actql/' + name, version: '0.0.0-development', private: true, type: 'module',
      scripts: {prepack: 'node ../../count.mjs ' + name}, files: ['index.mjs', 'index.d.ts'],
      dependencies: index ? {['@actql/' + six.packages[index - 1]]: '0.0.0-development'} : {},
    }));
    await writeFile(join(directory, 'index.mjs'), 'export const fixed = 7;\n');
    await writeFile(join(directory, 'index.d.ts'), 'export declare const fixed: number;\n');
  }
  git(repository, 'init', '--initial-branch=main');
  git(repository, 'add', '.');
  git(repository, '-c', 'user.name=ActQL Test', '-c', 'user.email=test@example.invalid',
    '-c', 'commit.gpgsign=false', 'commit', '-m', 'test: declare shared release fixture');
  const source = git(repository, 'rev-parse', 'HEAD');
  const inherited = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  t.after(() => {
    if (inherited === undefined) delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
    else process.env.ACTQL_PACKED_CLIENT_PACKAGES = inherited;
  });
  delete process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  const explorerDirectory = join(scratch, 'normal-six');
  const explorer = await preparePackageRelease({repository, destination: explorerDirectory,
    cohortPath: join(repository, 'release/six.json')});
  assert.equal(explorer.sourceSha, source);
  assert.deepEqual((await readFile(join(repository, 'prepack.calls'), 'utf8')).trim().split('\n'), six.packages);
  const originalManifest = await readFile(join(explorerDirectory, 'release.json'));
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = join(explorerDirectory, 'development');
  const clientDirectory = join(scratch, 'normal-four');
  const client = await preparePackageRelease({repository, destination: clientDirectory,
    cohortPath: join(repository, 'release/four.json')});
  assert.deepEqual((await readFile(join(repository, 'prepack.calls'), 'utf8')).trim().split('\n'),
    six.packages, 'The common four packages must not run prepack again');
  assert.equal(client.sourceSha, source);
  assert.deepEqual(client.cohort, four); assert.deepEqual(explorer.cohort, six);
  assert.deepEqual(await readFile(join(explorerDirectory, 'release.json')), originalManifest);
  assert.deepEqual(await verifyPackageRelease(explorerDirectory), explorer);
  assert.deepEqual(await verifyPackageRelease(clientDirectory), client);
  for (const name of four.packages) {
    const original = explorer.packages.find(value => value.name === '@actql/' + name);
    const shared = client.packages.find(value => value.name === original.name);
    assert.deepEqual(shared, original, 'Original and staged tarball identities, payload bytes and modes must match');
  }
  const sourceManifest = JSON.parse(await readFile(join(explorerDirectory, 'development/packed-client-packages.json')));
  const foreign = join(scratch, 'foreign-shared'); await mkdir(foreign);
  await writeFile(join(foreign, 'packed-client-packages.json'), JSON.stringify({
    ...sourceManifest, revision: 'f'.repeat(40),
  }));
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = foreign;
  await assert.rejects(preparePackageRelease({repository, destination: join(scratch, 'refused-source'),
    cohortPath: join(repository, 'release/four.json')}), /not this checkout/u);
  const changed = join(scratch, 'changed-shared'); await mkdir(changed);
  await writeFile(join(changed, 'packed-client-packages.json'), JSON.stringify(sourceManifest));
  await writeFile(join(changed, 'actql-client-wire-0.0.0-development.tgz'), 'changed');
  process.env.ACTQL_PACKED_CLIENT_PACKAGES = changed;
  await assert.rejects(preparePackageRelease({repository, destination: join(scratch, 'refused-digest'),
    cohortPath: join(repository, 'release/four.json')}), /changed after packing/u);
  assert.deepEqual((await readFile(join(repository, 'prepack.calls'), 'utf8')).trim().split('\n'), six.packages);
  assert.deepEqual(await readFile(join(explorerDirectory, 'release.json')), originalManifest);
  assert.equal(git(repository, 'status', '--porcelain'), '');
});

test('common release metadata equality requires the same selected package version', () => {
  assert.equal(four.packageVersion, six.packageVersion);
  assert.equal(four.tag, six.tag);
  const original = {name: '@actql/node', version: '0.0.0-development', private: true,
    dependencies: {'@actql/local-node': '0.0.0-development'}};
  assert.deepEqual(releasePackageMetadata(original, 'node', four),
    releasePackageMetadata(original, 'node', six));
  assert.notDeepEqual(releasePackageMetadata(original, 'node', four),
    releasePackageMetadata(original, 'node', {...six, packageVersion: '0.0.2'}));
});
