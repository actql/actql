import test from 'node:test';
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {FoundationRepository, PROTECTED_PATHS} from './fixtures/foundation-repository.mjs';
import {composeFoundation} from './foundation.mjs';

const compose = (repo, root = repo.root) => composeFoundation(root,
  {checkpoint: repo.checkpoint, paths: PROTECTED_PATHS});

test('head metadata is read afresh after an unrelated committed change', t => {
  const repo = new FoundationRepository(t);
  assert.equal(compose(repo).sourceRevision, repo.checkpoint);
  repo.write('unprotected.txt', 'independent change\n');
  const head = repo.commit('Advance the real head');
  assert.notEqual(head, repo.checkpoint);
  assert.equal(compose(repo).sourceRevision, head);
});

test('detached head composition keeps the actual commit identity', t => {
  const repo = new FoundationRepository(t);
  repo.write('unprotected.txt', 'advance\n');
  repo.commit('Advance branch');
  repo.checkout(repo.checkpoint);
  assert.equal(compose(repo).sourceRevision, repo.checkpoint);
});

test('a real shallow clone is refused before foundation composition', t => {
  const repo = new FoundationRepository(t);
  repo.write('unprotected.txt', 'advance\n');
  repo.commit('Advance branch');
  const clone = join(repo.root, 'shallow');
  repo.git('clone', '--quiet', '--depth=1', pathToFileURL(repo.root).href, clone);
  assert.throws(() => compose(repo, clone), /Incomplete foundation Git history/);
});

test('an unborn head cannot become an empty successful foundation', t => {
  const repo = new FoundationRepository(t);
  repo.git('update-ref', '-d', 'refs/heads/main');
  assert.throws(() => compose(repo), /Missing foundation Git history/);
});

test('a missing head object remains a history failure', t => {
  const repo = new FoundationRepository(t);
  repo.remove(`.git/objects/${repo.checkpoint.slice(0, 2)}/${repo.checkpoint.slice(2)}`);
  assert.throws(() => compose(repo), /Missing foundation Git history/);
});

test('replacement refs cannot alter the head admission', t => {
  const repo = new FoundationRepository(t);
  repo.write('unprotected.txt', 'advance\n');
  const head = repo.commit('Advance branch');
  repo.git('replace', repo.checkpoint, head);
  assert.throws(() => compose(repo), /Replaced foundation Git history/);
});

test('linked-worktree paths containing LF preserve the separate graft check', t => {
  const repo = new FoundationRepository(t);
  const linked = join(repo.root, 'linked with space\nand LF');
  repo.git('worktree', 'add', '--quiet', '--detach', linked, repo.checkpoint);
  assert.equal(compose(repo, linked).sourceRevision, repo.checkpoint);
  repo.write('.git/info/grafts', `${repo.checkpoint}\n`);
  assert.throws(() => compose(repo, linked), /Grafted foundation Git history/);
});
