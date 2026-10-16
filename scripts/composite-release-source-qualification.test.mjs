import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {qualifyCompositeReleaseSource} from './composite-release-source-qualification.mjs';

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'composite-source-qualification-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const git = (...args) => execFileSync('git', ['-c', 'user.name=Fixture',
    '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
    ...args], {cwd: root, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe']}).trim();
  git('init', '-q');
  const edit = async path => {
    await mkdir(dirname(join(root, path)), {recursive: true});
    await writeFile(join(root, path), 'independent synthetic input\n');
  };
  await edit('README.md'); git('add', '.'); git('commit', '-qm', 'test: base');
  const base = git('rev-parse', 'HEAD');
  const commit = () => {git('add', '.'); git('commit', '-qm', 'test: fixture child'); return git('rev-parse', 'HEAD');};
  return {root, git, edit, commit, base};
}

test('Composite acceptance qualifies the same exact clean artifact source', async t => {
  const {root, base} = await fixture(t);
  assert.deepEqual(qualifyCompositeReleaseSource(root, base), {
    artifactSourceSha: base, fixtureSourceSha: base,
    runtimeSourceDelta: [], harnessOnlyChanges: [],
  });
});

test('Composite acceptance retains artifact source while qualifying only the closed audit harness child', async t => {
  const f = await fixture(t);
  const paths = ['scripts/packed-package-boundaries.mjs',
    'scripts/packed-package-boundaries.test.mjs',
    'scripts/composite-release-source-qualification.mjs',
    'scripts/composite-release-source-qualification.test.mjs',
    'scripts/test-package-release-composite-vector.mjs'];
  for (const path of paths) await f.edit(path);
  const head = f.commit();
  const result = qualifyCompositeReleaseSource(f.root, f.base);
  assert.equal(result.artifactSourceSha, f.base);
  assert.equal(result.fixtureSourceSha, head);
  assert.deepEqual(result.harnessOnlyChanges, [...paths].sort());
});

test('Composite acceptance rejects runtime package contract lock fixture and oracle changes', async t => {
  for (const path of ['src/demo.mbt', 'adapters/host-node/runtime-core.mjs',
    'packages/local-node/package.json', 'spec/contracts/example.json',
    'package.json', 'package-lock.json', 'toolchain.json', 'moon.mod',
    'release/client-cohort.json', 'scripts/package-release.mjs',
    'scripts/fixtures/composite-vector-source-input.mjs',
    'scripts/fixtures/composite-vector-installed-source.mjs',
    'reviews/2026-10-14-composite-vector-release-matrix/public-audit.mjs',
    'scripts/unreviewed-harness.mjs',
    'reviews/synthetic/README.md', 'reviews/synthetic/evidence.json']) {
    const f = await fixture(t);
    await f.edit(path); f.commit();
    assert.throws(() => qualifyCompositeReleaseSource(f.root, f.base),
      /requires identical runtime/u, path);
  }
});

test('Composite acceptance rejects dirty fixtures and unrelated equal-tree history', async t => {
  const f = await fixture(t);
  await f.edit('scripts/packed-package-boundaries.mjs');
  assert.throws(() => qualifyCompositeReleaseSource(f.root, f.base), /clean committed/u);
  f.commit();
  const orphan = f.git('commit-tree', f.git('rev-parse', 'HEAD^{tree}'), '-m', 'test: foreign root');
  f.git('checkout', '-q', '--detach', orphan);
  assert.throws(() => qualifyCompositeReleaseSource(f.root, f.base));
});
