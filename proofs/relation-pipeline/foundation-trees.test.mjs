import test from 'node:test';
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {chmodSync, writeFileSync} from 'node:fs';
import {FoundationRepository, PACKAGE, RENAME, DISTINCT, DECLARATION_DIRECTORY,
  packageBytes} from './fixtures/foundation-repository.mjs';
import {populateFoundationTrees, readFoundationTreeDeltas} from './foundation-trees.mjs';

const revision = 'a'.repeat(40), other = 'b'.repeat(40), object = 'c'.repeat(40), zero = '0'.repeat(40);
const paths = [PACKAGE, RENAME, DISTINCT, DECLARATION_DIRECTORY];
const frame = (header = `:000000 100644 ${zero} ${object} A`, path = PACKAGE) =>
  Buffer.from(`${revision}\0${header}\0${path}\0`);
test('binary delta decoding preserves modifications, additions, deletions and empty revisions', () => {
  const output = Buffer.concat([frame(), Buffer.from(`${other}\0`)]);
  const decoded = readFoundationTreeDeltas(output, [revision, other], paths);
  assert.deepEqual(decoded.get(revision), [{path: PACKAGE, before: undefined, after: {mode: '100644', object}}]);
  assert.deepEqual(decoded.get(other), []);
  assert.deepEqual(readFoundationTreeDeltas(frame(`:100644 000000 ${object} ${zero} D`), [revision], paths).get(revision),
    [{path: PACKAGE, before: {mode: '100644', object}, after: undefined}]);
  assert.deepEqual(readFoundationTreeDeltas(frame(`:100644 100755 ${other} ${object} M`), [revision], paths).get(revision),
    [{path: PACKAGE, before: {mode: '100644', object: other}, after: {mode: '100755', object}}]);
});
for (const [name, output] of [
  ['missing revision', Buffer.alloc(0)],
  ['foreign revision', Buffer.from(`${other}\0`)],
  ['truncated final path', frame().subarray(0, -1)],
  ['extra revision', Buffer.concat([frame(), Buffer.from(`${other}\0`)])],
  ['duplicate path', Buffer.concat([frame(), frame().subarray(41)])],
  ['foreign path', frame(undefined, 'unrelated.mjs')],
  ['parent traversal', frame(undefined, `${DECLARATION_DIRECTORY}/../other.json`)],
  ['symlink', frame(`:000000 120000 ${zero} ${object} A`)],
  ['submodule', frame(`:000000 160000 ${zero} ${object} A`)],
  ['rename status', frame(`:100644 100644 ${other} ${object} R100`)],
  ['missing prior identity', frame(`:000000 100644 ${other} ${object} A`)],
  ['missing current identity', frame(`:000000 100644 ${zero} ${zero} A`)],
  ['false modification', frame(`:100644 100644 ${object} ${object} M`)],
  ['inconsistent deletion', frame(`:100644 100644 ${other} ${object} D`)],
  ['lossy path encoding', Buffer.concat([frame().subarray(0, -1), Buffer.from([0xff, 0])])],
]) test(`tree transport refuses ${name}`, () => {
  assert.throws(() => readFoundationTreeDeltas(output, [revision], paths));
});

function load(repo, selected = paths, {onGit = () => {}, mutate} = {}) {
  const revisions = repo.git('rev-list', '--reverse', '--topo-order', `${repo.checkpoint}..HEAD`).split('\n').filter(Boolean);
  const parentMap = new Map(repo.git('rev-list', '--parents', 'HEAD').split('\n').map(line => {
    const [revision, ...parents] = line.split(' '); return [revision, parents];
  }));
  const direct = revision => {
    const records = repo.run(['ls-tree', '-r', '-z', revision, '--', ...selected]);
    assert.equal(records.status, 0);
    return new Map(records.stdout.split('\0').filter(Boolean).map(line => {
      const [, mode, kind, object, path] = /^(\d+) (\w+) ([a-f0-9]{40})\t(.*)$/u.exec(line);
      assert.equal(kind, 'blob'); return [path, {mode, object}];
    }));
  };
  const trees = new Map(), verified = new Set(), calls = [];
  const tree = revision => {
    if (!trees.has(revision)) trees.set(revision, direct(revision));
    return trees.get(revision);
  };
  const git = (args, input) => {
    calls.push(args); onGit(args);
    const result = repo.run(['--no-replace-objects', ...args], {input, encoding: null});
    assert.equal(result.status, 0, result.stderr.toString());
    return mutate ? mutate(result.stdout) : result.stdout;
  };
  populateFoundationTrees({revisions, parents: revision => parentMap.get(revision), paths: selected,
    git, tree, trees, verifyObjects: objects => {
      for (const object of objects) {
        assert.equal(repo.git('cat-file', '-t', object), 'blob'); verified.add(object);
      }
    }});
  for (const revision of [repo.checkpoint, ...revisions])
    assert.deepEqual([...tree(revision)].sort(), [...direct(revision)].sort(), `Tree differs at ${revision}`);
  return {trees, verified, calls, revisions};
}

test('real Git batches retain every revision through branches, merge, binary bytes, mode changes, additions and deletion', t => {
  const repo = new FoundationRepository(t);
  repo.branch('right');
  repo.source({[RENAME]: 'left\0binary\n'});
  const declaration = `${DECLARATION_DIRECTORY}/example.json`;
  repo.source({[declaration]: '{}\n'});
  repo.write('unrelated.mjs', 'not selected\n'); repo.commit('Unrelated empty selected delta');
  repo.checkout('right');
  repo.source({[DISTINCT]: 'right\n'});
  repo.chmod(DISTINCT, 0o755); repo.commit('Executable mode change');
  repo.checkout('main'); repo.merge('right');
  repo.source({[RENAME]: null});
  const result = load(repo);
  assert.equal(result.calls.length, 1);
  assert(result.verified.size > 0);
  assert(!result.trees.get(repo.head()).has(RENAME));
  assert.equal(result.trees.get(repo.head()).get(DISTINCT).mode, '100755');
  assert(result.trees.get(repo.head()).has(declaration));
});

test('a fresh invocation observes new declaration members, deletion and rename without cross-call cache', t => {
  const repo = new FoundationRepository(t);
  repo.source({[PACKAGE]: packageBytes({first: 'node first.mjs'})});
  const before = load(repo).trees.get(repo.head());
  const first = `${DECLARATION_DIRECTORY}/first.json`, second = `${DECLARATION_DIRECTORY}/second.json`;
  repo.source({[first]: '{}\n'}); const added = load(repo).trees.get(repo.head());
  repo.source({[first]: null, [second]: '{}\n'}); const renamed = load(repo).trees.get(repo.head());
  assert(!before.has(first)); assert(added.has(first));
  assert(!renamed.has(first)); assert(renamed.has(second)); assert(added.has(first));
});

test('real history spanning more than one bounded batch retains every empty revision', t => {
  const repo = new FoundationRepository(t), rootTree = repo.git('rev-parse', 'HEAD^{tree}');
  let parent = repo.head();
  for (let index = 0; index < 260; index++)
    parent = repo.git('commit-tree', rootTree, '-p', parent, '-m', `Unchanged selected inputs ${index}`);
  repo.git('update-ref', 'refs/heads/main', parent);
  const result = load(repo);
  assert.equal(result.revisions.length, 260); assert.equal(result.calls.length, 2);
  assert.deepEqual(result.trees.get(parent), result.trees.get(repo.checkpoint));
});

test('external diff, attributes, relative and rename configuration cannot alter raw selected history', t => {
  const repo = new FoundationRepository(t), external = join(repo.root, 'external-diff.sh');
  writeFileSync(external, '#!/bin/sh\nexit 99\n'); chmodSync(external, 0o755);
  repo.git('config', 'diff.external', external); repo.git('config', 'diff.relative', 'true');
  repo.git('config', 'diff.renames', 'true'); repo.git('config', 'diff.hidden.command', external);
  repo.source({'.gitattributes': '* diff=hidden\n', [RENAME]: 'changed under attributes\n'});
  load(repo);
});

test('a transport delta must agree with the independently read first-parent identity', t => {
  const repo = new FoundationRepository(t);
  repo.source({[RENAME]: 'changed\n'});
  assert.throws(() => load(repo, paths, {mutate: bytes => Buffer.from(bytes.toString().replace(
    /(:100644 100644 )([a-f0-9]{40})/u, `$1${object}`))}), /actual parent tree/u);
});

test('missing selected Git blobs fail instead of producing an empty or incomplete successful tree', t => {
  const repo = new FoundationRepository(t);
  const source = repo.source({[RENAME]: 'missing selected blob\n'});
  const blob = repo.git('rev-parse', `${source}:${RENAME}`);
  repo.remove(`.git/objects/${blob.slice(0, 2)}/${blob.slice(2)}`);
  assert.throws(() => load(repo));
});
