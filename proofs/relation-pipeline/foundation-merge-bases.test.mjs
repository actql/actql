import test from 'node:test';
import assert from 'node:assert/strict';
import {foundationMergeBaseQuery} from './foundation-trees.mjs';
import {FoundationRepository} from './fixtures/foundation-repository.mjs';

function history(repo, tips) {
  const result = repo.run(['--no-replace-objects', 'rev-list', '--parents', ...tips]);
  assert.equal(result.status, 0, 'Incomplete actual Git parent history');
  return new Map(result.stdout.trim().split('\n').map(line => {
    const [revision, ...parents] = line.split(' ');
    return [revision, parents];
  }));
}
function commit(repo, label, parents = []) {
  return repo.git('commit-tree', repo.git('rev-parse', 'HEAD^{tree}'),
    ...parents.flatMap(parent => ['-p', parent]), '-m', label);
}
function oracle(repo, left, right) {
  const result = repo.run(['--no-replace-objects', 'merge-base', '--all', left, right]);
  assert(!result.error);
  assert(result.status === 0 || result.status === 1, result.stderr);
  return result.stdout.trim().split('\n').filter(Boolean).sort();
}

test('complete parent queries equal actual Git for every ordered pair across forks, merges and disconnected roots', t => {
  const repo = new FoundationRepository(t), root = repo.head();
  const a = commit(repo, 'a', [root]), b = commit(repo, 'b', [root]);
  const c = commit(repo, 'c', [a]), d = commit(repo, 'd', [a, b]);
  const e = commit(repo, 'e', [b]), f = commit(repo, 'f', [c, d]);
  const separate = commit(repo, 'separate'), tip = commit(repo, 'tip', [f, e]);
  const graph = history(repo, [tip, separate]);
  const query = foundationMergeBaseQuery(new Map([...graph].reverse()));
  for (const left of graph.keys()) for (const right of graph.keys())
    assert.deepEqual(query(left, right), oracle(repo, left, right), `${left} / ${right}`);
});

test('actual criss-cross keeps both maximal bases and excludes their common ancestor', t => {
  const repo = new FoundationRepository(t), root = repo.head();
  const a = commit(repo, 'left base', [root]), b = commit(repo, 'right base', [root]);
  const left = commit(repo, 'left merge', [a, b]), right = commit(repo, 'right merge', [b, a]);
  const query = foundationMergeBaseQuery(history(repo, [left, right]));
  assert.deepEqual(oracle(repo, left, right), [a, b].sort());
  assert.deepEqual(query(left, right), oracle(repo, left, right));
  assert.deepEqual(query(right, left), oracle(repo, right, left));
  assert(!query(left, right).includes(root));
});

test('actual nested merges retain three maximal bases without choosing one side', t => {
  const repo = new FoundationRepository(t), root = repo.head();
  const a = commit(repo, 'a', [root]), b = commit(repo, 'b', [root]), c = commit(repo, 'c', [root]);
  const ab = commit(repo, 'ab', [a, b]), bc = commit(repo, 'bc', [b, c]);
  const left = commit(repo, 'left', [ab, c]), right = commit(repo, 'right', [bc, a]);
  const query = foundationMergeBaseQuery(history(repo, [left, right]));
  assert.deepEqual(oracle(repo, left, right), [a, b, c].sort());
  assert.deepEqual(query(left, right), oracle(repo, left, right));
});

test('each invocation snapshots parents and results cannot poison its local cache', t => {
  const repo = new FoundationRepository(t), root = repo.head(), tip = commit(repo, 'tip', [root]);
  const graph = history(repo, [tip]), query = foundationMergeBaseQuery(graph);
  assert.deepEqual(query(root, tip), oracle(repo, root, tip));
  query(root, tip).length = 0;
  graph.get(tip).length = 0;
  assert.deepEqual(query(root, tip), [root]);
  assert.deepEqual(foundationMergeBaseQuery(graph)(root, tip), []);
});

test('missing parent records and unknown requested commits fail closed', t => {
  const repo = new FoundationRepository(t), root = repo.head(), tip = commit(repo, 'tip', [root]);
  const graph = history(repo, [tip]);
  graph.delete(root);
  assert.throws(() => foundationMergeBaseQuery(graph), /Incomplete foundation parent ancestry/u);
  const query = foundationMergeBaseQuery(history(repo, [tip]));
  assert.throws(() => query(root, 'f'.repeat(40)), /Missing foundation merge-base parent/u);
  assert.throws(() => query(root, 'not-a-commit'), /Missing foundation merge-base parent/u);
});

test('removing an actual ancestor object prevents a fresh Git snapshot rather than reusing acceptance', t => {
  const repo = new FoundationRepository(t), root = repo.head(), tip = commit(repo, 'tip', [root]);
  assert.deepEqual(foundationMergeBaseQuery(history(repo, [tip]))(root, tip), [root]);
  repo.remove(`.git/objects/${root.slice(0, 2)}/${root.slice(2)}`);
  assert.throws(() => history(repo, [tip]), /Incomplete actual Git parent history/u);
});
