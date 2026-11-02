import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync, chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {checkCurrentSource} from './inventory.mjs';

function git(root, ...args) {
  const result = spawnSync('git', args, {cwd: root, encoding: 'utf8', env: {...process.env,
    GIT_AUTHOR_NAME: 'Fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
    GIT_COMMITTER_NAME: 'Fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid'}});
  assert.equal(result.status, 0, result.stderr); return result.stdout.trim();
}
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-current-source-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  git(root, 'init', '-q'); mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'src/current.mbt'), 'current source\n');
  git(root, 'add', '.'); git(root, 'commit', '-qm', 'Current source');
  return root;
}
test('current source accepts a real shallow checkout without historical declarations', t => {
  const root = fixture(t), clone = join(root, 'shallow');
  git(root, 'clone', '--depth=1', `file://${root}`, clone);
  assert.equal(git(clone, 'rev-parse', '--is-shallow-repository'), 'true');
  assert.equal(checkCurrentSource(clone), git(root, 'rev-parse', 'HEAD'));
});
for (const stage of [false, true]) test(`current source rejects ${stage ? 'staged' : 'unstaged'} changed inputs`, t => {
  const root = fixture(t); writeFileSync(join(root, 'src/current.mbt'), 'different\n');
  if (stage) git(root, 'add', '.');
  assert.throws(() => checkCurrentSource(root), /differ from tested HEAD/);
});
test('current source rejects an untracked proof input', t => {
  const root = fixture(t); writeFileSync(join(root, 'src/untracked.mbt'), 'new\n');
  assert.throws(() => checkCurrentSource(root), /Untracked current proof inputs/);
});
test('current source rejects deleted inputs and accepts ordinary new committed revisions', t => {
  const root = fixture(t); rmSync(join(root, 'src/current.mbt'));
  assert.throws(() => checkCurrentSource(root), /differ from tested HEAD/);
  writeFileSync(join(root, 'src/current.mbt'), 'new ordinary source\n');
  git(root, 'add', '.'); git(root, 'commit', '-qm', 'Ordinary change without declaration');
  assert.equal(checkCurrentSource(root), git(root, 'rev-parse', 'HEAD'));
});

test('current source rejects ignored untracked files that enter the source snapshot', t => {
  const root = fixture(t);
  writeFileSync(join(root, '.git/info/exclude'), 'src/ignored.mbt\n');
  writeFileSync(join(root, 'src/ignored.mbt'), 'ignored but snapshotted\n');
  assert.throws(() => checkCurrentSource(root), /Untracked current proof inputs/);
});

for (const flag of ['--assume-unchanged', '--skip-worktree']) {
  test(`current source rejects bytes hidden by ${flag}`, t => {
    const root = fixture(t);
    git(root, 'update-index', flag, 'src/current.mbt');
    writeFileSync(join(root, 'src/current.mbt'), 'different physical input\n');
    git(root, 'diff', '--quiet', 'HEAD', '--', 'src');
    assert.throws(() => checkCurrentSource(root), /differ from tested HEAD/);
  });
}

test('current source rejects a tracked input symlink with an unbound target', t => {
  const root = fixture(t);
  rmSync(join(root, 'src/current.mbt'));
  writeFileSync(join(root, 'outside.mbt'), 'outside source\n');
  symlinkSync('../outside.mbt', join(root, 'src/current.mbt'));
  git(root, 'add', 'src/current.mbt');
  git(root, 'commit', '-qm', 'Tracked symbolic link');
  git(root, 'diff', '--quiet', 'HEAD', '--', 'src');
  assert.throws(() => checkCurrentSource(root), /Non-regular current proof input/);
  writeFileSync(join(root, 'outside.mbt'), 'changed outside source\n');
  git(root, 'diff', '--quiet', 'HEAD', '--', 'src');
  assert.throws(() => checkCurrentSource(root), /Non-regular current proof input/);
});

test('current source rejects physical executable mode hidden by Git configuration', t => {
  const root = fixture(t);
  git(root, 'config', 'core.filemode', 'false');
  chmodSync(join(root, 'src/current.mbt'), 0o755);
  git(root, 'diff', '--quiet', 'HEAD', '--', 'src');
  assert.throws(() => checkCurrentSource(root), /Current proof input mode/);
});

test('current source rejects a committed symlink above a selected input', t => {
  const root = fixture(t);
  mkdirSync(join(root, 'outside/spec'), {recursive: true});
  writeFileSync(join(root, 'outside/spec/language.md'), 'unbound specification\n');
  symlinkSync('outside', join(root, 'docs'), 'dir');
  git(root, 'add', 'docs');
  git(root, 'commit', '-qm', 'Symbolic link above selected specification');
  git(root, 'diff', '--quiet', 'HEAD', '--', 'docs/spec/language.md');
  assert.throws(() => checkCurrentSource(root), /Non-regular current proof input/);
});
