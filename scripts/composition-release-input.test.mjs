import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {admitCompositionRelease, compositionReleaseDirectory} from './composition-release-input.mjs';
import {stagePackage} from './package-release.mjs';

const digest = value => createHash('sha256').update(value).digest('hex');
const run = (command, args, cwd) => execFileSync(command, args,
  {cwd, encoding: 'utf8', timeout: 30000});

test('normal composition release selection is explicit and has no implicit fallback', () => {
  assert.equal(compositionReleaseDirectory(['--composed-infer']), undefined);
  assert.equal(compositionReleaseDirectory(['--release-dir', '/fixed/rc', '--composed-text']), '/fixed/rc');
  for (const argv of [['--release-dir'], ['--release-dir', '--composed-text'],
    ['--release-dir', 'relative'], ['--release-dir', '/one', '--release-dir', '/two'],
    ['--release-dir=/one'], ['--release-directory', '/one']]) {
    assert.throws(() => compositionReleaseDirectory(argv));
  }
});

test('normal composition admits immutable archives and rejects invalid source or artifacts before a Host', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-composition-release-input-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const repository = join(root, 'repository'), directory = join(root, 'release');
  await mkdir(repository); await mkdir(directory);
  await writeFile(join(repository, 'source.txt'), 'independent committed source\n');
  run('git', ['init', '--quiet'], repository);
  run('git', ['add', 'source.txt'], repository);
  run('git', ['-c', 'core.hooksPath=/dev/null', '-c', 'user.name=Release fixture',
    '-c', 'user.email=release-fixture@example.invalid', '-c', 'commit.gpgsign=false',
    'commit', '--quiet', '-m', 'test: retain independent release source'], repository);
  const revision = run('git', ['rev-parse', 'HEAD'], repository).trim();
  const cohort = JSON.parse(await readFile(new URL('../release/client-cohort.json', import.meta.url)));
  const originals = join(directory, 'development'); await mkdir(originals);
  const license = join(root, 'LICENSE'); await copyFile(new URL('../LICENSE', import.meta.url), license);
  const packages = [], tarballs = {};
  for (const [index, name] of cohort.packages.entries()) {
    const source = join(root, `input-${name}`); await mkdir(source);
    const previous = index === 0 ? undefined : `@actql/${cohort.packages[index - 1]}`;
    await writeFile(join(source, 'package.json'), JSON.stringify({name: `@actql/${name}`,
      version: '0.0.0-development', private: true, type: 'module',
      exports: './index.mjs', files: ['index.mjs'],
      ...(previous === undefined ? {} : {dependencies: {[previous]: '0.0.0-development'}})}));
    await writeFile(join(source, 'index.mjs'), previous === undefined
      ? 'export const fixed = 7;\n' : `export {fixed} from '${previous}';\n`);
    run('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination', originals,
      '--cache', join(root, 'npm-cache')], source);
    const item = await stagePackage({archive: join(originals, `actql-${name}-0.0.0-development.tgz`),
      destination: directory, name, cohort, license});
    packages.push(item); tarballs[name] = item.originalSha256;
  }
  await writeFile(join(originals, 'packed-client-packages.json'),
    JSON.stringify({revision, tarballs}));
  const manifest = {version: 'actql-package-release/0.1', sourceSha: revision,
    preparedAt: '2026-10-15T00:00:00.000Z', cohort, recipeSha256: 'b'.repeat(64),
    cohortSha256: digest(JSON.stringify(cohort)), toolchain: {node: process.version},
    generation: 'normal-prepack-then-metadata-and-license-only', packages};
  const manifestPath = join(directory, 'release.json');
  const manifestWire = JSON.stringify(manifest);
  await writeFile(manifestPath, manifestWire);

  await t.test('install all four release archives normally outside the source checkout', async () => {
    const admitted = await admitCompositionRelease({repository, directory});
    assert.deepEqual(admitted.archives, packages.map(item => join(directory, item.file)));
    assert.equal(admitted.manifestSha256, digest(manifestWire));
    const consumer = join(root, 'consumer'); await mkdir(consumer);
    await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
    run('npm', ['install', '--ignore-scripts', '--no-audit', '--no-fund',
      '--cache', join(root, 'npm-cache'), ...admitted.archives], consumer);
    assert.equal(run(process.execPath, ['--input-type=module', '-e',
      "const {fixed}=await import('@actql/node'); console.log(fixed);"], consumer).trim(), '7');
    for (const name of cohort.packages) {
      const installed = JSON.parse(await readFile(join(consumer, 'node_modules/@actql', name, 'package.json')));
      assert.equal(installed.version, cohort.packageVersion);
      assert.equal(installed.private, false);
    }
    await admitted.verifyUnchanged();
  });
  await t.test('dirty source cannot borrow a valid release', async () => {
    await writeFile(join(repository, 'source.txt'), 'changed source\n');
    await assert.rejects(admitCompositionRelease({repository, directory}), /clean source/u);
    await writeFile(join(repository, 'source.txt'), 'independent committed source\n');
  });
  await t.test('checkout artifacts cannot fill an empty installed consumer', async () => {
    await assert.rejects(admitCompositionRelease({repository, directory: repository}),
      /outside the source checkout/u);
  });
  await t.test('a valid release from a different source is refused', async () => {
    const foreign = 'f'.repeat(40);
    await writeFile(manifestPath, JSON.stringify({...manifest, sourceSha: foreign}));
    await writeFile(join(originals, 'packed-client-packages.json'),
      JSON.stringify({revision: foreign, tarballs}));
    await assert.rejects(admitCompositionRelease({repository, directory}), /same source/u);
    await writeFile(manifestPath, manifestWire);
    await writeFile(join(originals, 'packed-client-packages.json'), JSON.stringify({revision, tarballs}));
  });
  await t.test('a changed staged payload is rejected instead of repacking', async () => {
    const archive = join(directory, packages[0].file), before = await readFile(archive);
    await writeFile(archive, Buffer.concat([before, Buffer.from('changed')]));
    await assert.rejects(admitCompositionRelease({repository, directory}));
    await writeFile(archive, before);
  });
  await t.test('metadata-only mutation after admission still changes the original manifest', async () => {
    const admitted = await admitCompositionRelease({repository, directory});
    await writeFile(manifestPath, JSON.stringify({...manifest, preparedAt: '2026-10-15T01:00:00.000Z'}));
    await assert.rejects(admitted.verifyUnchanged(), /Original release manifest changed/u);
    await writeFile(manifestPath, manifestWire);
    await admitted.verifyUnchanged();
  });
});
