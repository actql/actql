import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
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
