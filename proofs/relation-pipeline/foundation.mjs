// Bounded provenance composition for the existing relation-pipeline foundation.
// Declarations are reviewable inputs, never evidence of human approval.
import assert from 'node:assert/strict';
import { lstatSync, readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { hash } from './inventory.mjs';
const sha = /^[0-9a-f]{40}$/;
const digest = /^[0-9a-f]{64}$/;
const id = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const same = (a, b) => a?.object === b?.object && a?.mode === b?.mode;
const sorted = values => [...values].sort();
// A descriptor, not a verifier. The composer calls this only after every
// record's real Git binding and complete dependency grounds have passed.
export function foundationSourceBinding(declaration, inputRevisions) {
  return { version: declaration.version, kind: declaration.kind, revision: declaration.revision,
    parents: declaration.parents, changes: declaration.changes.map(({ path, before, afterDigest, afterMode }) =>
      ({ path, before, afterDigest, afterMode })).sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0),
    inputs: sorted(new Set(inputRevisions)) };
}
function keys(value, expected, label) {
  assert(value && typeof value === 'object' && !Array.isArray(value), `Invalid ${label}`);
  assert.deepEqual(Object.keys(value).sort(), [...expected].sort(), `Invalid ${label} fields`);
}
export function composeFoundation(root, { checkpoint, paths, directory = 'proofs/relation-pipeline/foundation-declarations', immutable = [] }) {
  assert.match(checkpoint, sha, 'Invalid foundation checkpoint');
  assert(Array.isArray(paths) && paths.length && new Set(paths).size === paths.length, 'Invalid foundation paths');
  const canonical = path => typeof path === 'string' && /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(path)
    && !path.split('/').some(part => part === '.' || part === '..');
  assert(paths.every(canonical) && canonical(directory), 'Invalid foundation path');
  const protectedPaths = sorted(paths), allowed = new Set(paths);
  assert(Array.isArray(immutable), 'Invalid immutable foundation inputs');
  for (const entry of immutable) {
    assert(canonical(entry.path) && canonical(entry.sourcePath ?? entry.path) && sha.test(entry.revision), 'Invalid immutable foundation input');
    assert(!allowed.has(entry.path), 'Ambiguous immutable foundation path');
  }
  const immutablePaths = immutable.map(entry => entry.path);
  assert.equal(new Set(immutablePaths).size, immutablePaths.length, 'Duplicate immutable foundation input');
  const inspectedPaths = [...new Set([...protectedPaths, ...immutablePaths, ...immutable.map(entry => entry.sourcePath ?? entry.path)])];
  function git(args, { allowedFailure = false, input } = {}) {
    const result = spawnSync('git', ['--no-replace-objects', ...args], {
      cwd: root, input, env: { ...process.env, GIT_NO_REPLACE_OBJECTS: '1' }, maxBuffer: 64 * 1024 * 1024,
    });
    assert(!result.error, `Foundation Git failed: ${result.error}`);
    if (!allowedFailure) assert.equal(result.status, 0, `Missing foundation Git history: git ${args.join(' ')}\n${result.stderr}`);
    return result;
  }
  assert.equal(git(['rev-parse', '--is-shallow-repository']).stdout.toString().trim(), 'false',
    'Incomplete foundation Git history: fetch full history');
  const grafts = git(['rev-parse', '--git-path', 'info/grafts']).stdout.toString().trim();
  assert(!existsSync(resolve(root, grafts)) || !readFileSync(resolve(root, grafts)).length, 'Grafted foundation Git history');
  assert(!git(['for-each-ref', '--format=%(refname)', 'refs/replace']).stdout.length, 'Replaced foundation Git history');
  const head = git(['rev-parse', '--verify', 'HEAD^{commit}']).stdout.toString().trim();
  assert.match(head, sha);
  // Walk the complete ancestry once: deleting a shallow marker must not turn
  // missing parent objects into an apparently complete declaration interval.
  git(['rev-list', '--parents', head]);
  const ancestorCache = new Map();
  function ancestor(a, b) {
    const key = `${a}:${b}`;
    if (!ancestorCache.has(key)) ancestorCache.set(key, git(['merge-base', '--is-ancestor', a, b], { allowedFailure: true }).status === 0);
    return ancestorCache.get(key);
  }
  assert(ancestor(checkpoint, head), 'Foundation checkpoint is not an ancestor of HEAD');
  const revisions = git(['rev-list', '--reverse', '--topo-order', `${checkpoint}..${head}`]).stdout.toString().trim().split('\n').filter(Boolean);
  const revisionSet = new Set(revisions), commits = new Map(), trees = new Map(), blobs = new Map(), verifiedObjects = new Set();
  function parents(revision) {
    if (!commits.has(revision)) {
      const raw = git(['cat-file', 'commit', revision]).stdout.toString();
      commits.set(revision, raw.split('\n\n')[0].split('\n').filter(line => line.startsWith('parent ')).map(line => line.slice(7)));
    }
    return commits.get(revision);
  }
  function tree(revision) {
    if (!trees.has(revision)) {
      const output = git(['ls-tree', '-r', '-z', revision, '--', ...inspectedPaths, directory]).stdout.toString();
      const entries = new Map();
      for (const entry of output.split('\0').filter(Boolean)) {
        const match = /^(\d+) (\w+) ([0-9a-f]{40})\t(.*)$/.exec(entry);
        assert(match, 'Invalid foundation Git tree entry');
        const [, mode, type, object, path] = match;
        assert(type === 'blob' && ['100644', '100755'].includes(mode), `Non-regular foundation file ${path}`);
        entries.set(path, { mode, object });
      }
      const unchecked = [...new Set([...entries.values()].map(entry => entry.object))].filter(object => !verifiedObjects.has(object));
      if (unchecked.length) {
        const checked = git(['cat-file', '--batch-check'], { input: `${unchecked.join('\n')}\n` }).stdout.toString().trim().split('\n');
        assert.equal(checked.length, unchecked.length, 'Incomplete foundation Git object check');
        checked.forEach((line, index) => {
          assert.match(line, new RegExp(`^${unchecked[index]} blob [0-9]+$`), 'Missing foundation Git blob');
          verifiedObjects.add(unchecked[index]);
        });
      }
      trees.set(revision, entries);
    }
    return trees.get(revision);
  }
  function bytes(entry) {
    if (!blobs.has(entry.object)) blobs.set(entry.object, git(['cat-file', 'blob', entry.object]).stdout);
    return blobs.get(entry.object);
  }
  function identity(revision, path) {
    const entry = tree(revision).get(path);
    return { revision, digest: entry ? hash(bytes(entry)) : null, mode: entry?.mode ?? null };
  }
  const immutableEntries = new Map(immutable.map(entry => {
    const expected = tree(entry.revision).get(entry.sourcePath ?? entry.path);
    assert(expected, `Missing immutable foundation Git object ${entry.path}`);
    return [entry.path, expected];
  }));
  const declarationsAt = revision => new Map([...tree(revision)].filter(([path]) => path.startsWith(`${directory}/`)));
  assert.equal(declarationsAt(checkpoint).size, 0, 'Foundation checkpoint already contains declarations');
  const introductions = new Map();
  for (const revision of revisions) {
    const actualParents = parents(revision);
    assert(actualParents.length === 1 || actualParents.length === 2, 'Unsupported foundation merge parent count');
    for (const parent of actualParents) {
      // Old forks keep their original source identities. A boundary parent
      // must belong to the already accepted checkpoint ancestry; every other
      // parent is independently enumerated and checked in the new commit DAG.
      assert(revisionSet.has(parent) || ancestor(parent, checkpoint), `Unrelated foundation boundary parent ${parent}`);
    }
    for (const [path, expected] of immutableEntries) {
      const current = tree(revision).get(path);
      assert(!current || same(current, expected), `Changed immutable foundation ${path}`);
      assert(current || actualParents.every(parent => !tree(parent).has(path)), `Removed immutable foundation ${path}`);
    }
    const inherited = new Map();
    for (const parent of actualParents) for (const [path, entry] of declarationsAt(parent)) {
      assert(!inherited.has(path) || same(inherited.get(path), entry), `Ambiguous foundation declaration ${path}`);
      inherited.set(path, entry);
    }
    const current = declarationsAt(revision);
    for (const [path, entry] of inherited) assert(same(entry, current.get(path)), `Changed or removed foundation declaration ${path}`);
    for (const [path, entry] of current) if (!inherited.has(path)) {
      assert(entry.mode === '100644', `Invalid foundation declaration mode ${path}`);
      const previous = introductions.get(path);
      assert(!previous || same(previous.entry, entry), `Conflicting foundation declaration introduction ${path}`);
      if (previous) previous.revisions.push(revision);
      else introductions.set(path, { entry, revisions: [revision] });
    }
  }
  const declarations = [], byRevision = new Map(), byId = new Map();
  for (const [path, entry] of declarationsAt(head)) {
    const declarationBytes = bytes(entry);
    const declaration = JSON.parse(declarationBytes);
    // One reviewable encoding also rejects duplicate JSON keys and lossy UTF-8.
    assert(declarationBytes.equals(Buffer.from(`${JSON.stringify(declaration, null, 2)}\n`)), 'Noncanonical or ambiguous foundation declaration JSON');
    const expectedKeys = ['version', 'id', 'kind', 'revision', 'parents', 'changes'];
    if (declaration.kind === 'resolution') expectedKeys.push('inputs');
    keys(declaration, expectedKeys, 'foundation declaration');
    assert.equal(declaration.version, 'actql-foundation-declaration/0.1');
    assert.match(declaration.id, id, 'Invalid foundation declaration ID');
    assert.equal(path, `${directory}/${declaration.id}.json`, 'Ambiguous foundation declaration filename');
    assert(!byId.has(declaration.id), 'Duplicate foundation declaration ID');
    assert.match(declaration.revision, sha, 'Invalid foundation supporting revision');
    assert(revisionSet.has(declaration.revision), 'Unrelated foundation supporting revision');
    assert(Array.isArray(declaration.parents) && declaration.parents.every(value => sha.test(value)), 'Invalid foundation parents');
    assert.deepEqual(declaration.parents, parents(declaration.revision), 'Incorrect foundation supporting parents');
    const declarationIntroductions = sorted(introductions.get(path).revisions);
    for (const introduction of declarationIntroductions) {
      assert(introduction !== declaration.revision && ancestor(declaration.revision, introduction), 'Foundation declaration must follow its source commit');
    }
    assert(Array.isArray(declaration.changes) && declaration.changes.length, 'Empty foundation declaration');
    const changePaths = declaration.changes.map(change => change.path);
    assert(new Set(changePaths).size === changePaths.length, 'Duplicate foundation change path');
    for (const change of declaration.changes) {
      keys(change, ['path', 'before', 'afterDigest', 'afterMode', 'reason'], 'foundation change');
      assert(allowed.has(change.path), `Unknown foundation change path ${change.path}`);
      assert.equal(typeof change.reason, 'string');
      assert(change.reason.trim(), 'Missing foundation change rationale');
      assert.match(change.afterDigest, digest, 'Incorrect foundation digest');
      assert(['100644', '100755'].includes(change.afterMode), 'Invalid foundation mode');
      assert.deepEqual(change.before, declaration.parents.map(parent => identity(parent, change.path)), `Incorrect prior foundation identity ${change.path}`);
      const after = identity(declaration.revision, change.path);
      assert.equal(change.afterDigest, after.digest, `Incorrect current foundation digest ${change.path}`);
      assert.equal(change.afterMode, after.mode, `Incorrect current foundation mode ${change.path}`);
    }
    // Retain every physical record. No representative may exempt another
    // record from the independent Git, path, mode or dependency checks.
    if (!byRevision.has(declaration.revision)) byRevision.set(declaration.revision, []);
    byRevision.get(declaration.revision).push(declaration);
    byId.set(declaration.id, declaration);
    declarations.push({ path, digest: hash(bytes(entry)), introductions: declarationIntroductions, ...declaration });
  }
  const requirements = new Map();
  for (const revision of revisions) {
    const actualParents = parents(revision), required = [], result = tree(revision);
    let mergeBase;
    if (actualParents.length === 2) {
      const bases = git(['merge-base', '--all', ...actualParents]).stdout.toString().trim().split('\n').filter(Boolean);
      assert.equal(bases.length, 1, 'Ambiguous foundation merge bases');
      [mergeBase] = bases;
    }
    for (const path of protectedPaths) {
      const after = result.get(path), before = actualParents.map(parent => tree(parent).get(path));
      assert(after || before.every(entry => !entry), `Deleted foundation file ${path}`);
      for (const entry of before) assert(!entry || !after || entry.mode === after.mode, `Unsupported foundation mode change ${path}`);
      if (actualParents.length === 1) {
        if (!same(before[0], after)) required.push(path);
      } else {
        const base = tree(mergeBase).get(path);
        // Two independent edits of one path always need an explicit resolution,
        // including equal resulting bytes; both change rationales stay required.
        const bothChanged = !same(before[0], base) && !same(before[1], base);
        const automatic = same(before[0], before[1]) ? before[0]
          : same(before[0], base) ? before[1] : same(before[1], base) ? before[0] : undefined;
        if (bothChanged || !same(automatic, after)) required.push(path);
      }
    }
    const candidates = byRevision.get(revision);
    if (!required.length) { assert(!candidates, 'Spurious foundation declaration'); continue; }
    assert(candidates, `Unlisted foundation source change ${revision}: ${required.join(', ')}`);
    for (const declaration of candidates) {
      assert.equal(declaration.kind, actualParents.length === 1 ? 'change' : 'resolution', 'Incorrect foundation declaration kind');
      assert.deepEqual(sorted(declaration.changes.map(change => change.path)), sorted(required), 'Incomplete foundation changed paths');
    }
    requirements.set(revision, { actualParents, required, mergeBase });
  }
  const integrations = [];
  // All records have now independently matched real source commits and the
  // complete changed-path set. Validate ancestor dependencies in topological
  // order before allowing equivalent records to share a source-binding group.
  for (const [revision, { actualParents, required, mergeBase }] of requirements) {
    const candidates = byRevision.get(revision);
    let inputs = [];
    if (actualParents.length === 2) {
      inputs = sorted(new Set(declarations.filter(candidate => candidate.revision !== revision
        && candidate.changes.some(change => required.includes(change.path))
        && actualParents.some(parent => ancestor(candidate.revision, parent))).map(candidate => candidate.revision)));
    }
    let binding;
    for (const declaration of candidates) {
      let inputRevisions = [];
      if (declaration.kind === 'resolution') {
        assert(Array.isArray(declaration.inputs) && declaration.inputs.every(value => typeof value === 'string' && byId.has(value)),
          'Unknown foundation resolution input');
        assert.deepEqual(declaration.inputs, sorted(new Set(declaration.inputs)), 'Noncanonical foundation resolution inputs');
        inputRevisions = sorted(new Set(declaration.inputs.map(value => byId.get(value).revision)));
        assert.deepEqual(inputRevisions, inputs, 'Incomplete or ambiguous foundation resolution inputs');
      }
      const current = foundationSourceBinding(declaration, inputRevisions);
      if (binding) assert.deepEqual(current, binding, 'Conflicting foundation source-binding declarations');
      else binding = current;
    }
    if (actualParents.length === 2) {
      integrations.push({ revision, parents: actualParents, mergeBase, declarations: sorted(candidates.map(candidate => candidate.id)) });
    }
  }
  const expectedIndex = new Map([...tree(head)].filter(([path]) => allowed.has(path)
    || immutablePaths.includes(path) || path.startsWith(`${directory}/`)));
  const indexEntries = git(['ls-files', '--stage', '-z', '--', ...protectedPaths, ...immutablePaths, directory]).stdout.toString().split('\0').filter(Boolean);
  assert.equal(indexEntries.length, expectedIndex.size, 'Uncommitted foundation index membership');
  for (const value of indexEntries) {
    const match = /^(\d+) ([0-9a-f]{40}) ([0-3])\t(.*)$/.exec(value);
    assert(match && match[3] === '0', 'Unmerged foundation index');
    assert(same({ mode: match[1], object: match[2] }, expectedIndex.get(match[4])), 'Uncommitted foundation index');
  }
  function workingFile(path, mode) {
    const parts = path.split('/');
    for (let i = 1; i < parts.length; i++) {
      const component = lstatSync(join(root, ...parts.slice(0, i)));
      assert(component.isDirectory() && !component.isSymbolicLink(), `Non-regular foundation directory ${path}`);
    }
    const stat = lstatSync(join(root, path));
    assert(stat.isFile() && !stat.isSymbolicLink(), `Non-regular foundation working file ${path}`);
    assert.equal((stat.mode & 0o111) !== 0, mode === '100755', `Uncommitted foundation mode ${path}`);
  }
  for (const path of [...protectedPaths, ...immutablePaths]) {
    const entry = tree(head).get(path);
    if (immutableEntries.has(path)) assert(same(entry, immutableEntries.get(path)), `Changed immutable foundation ${path}`);
    assert(entry, `Missing foundation file ${path}`);
    workingFile(path, entry.mode);
    assert.equal(hash(readFileSync(join(root, path))), hash(bytes(entry)), `Uncommitted foundation source ${path}`);
  }
  const directoryPath = join(root, directory);
  const workingDeclarations = existsSync(directoryPath) ? readdirSync(directoryPath).map(name => `${directory}/${name}`).sort() : [];
  assert.deepEqual(workingDeclarations, sorted(declarationsAt(head).keys()), 'Uncommitted foundation declaration membership');
  for (const [path, entry] of declarationsAt(head)) {
    workingFile(path, entry.mode);
    assert.equal(hash(readFileSync(join(root, path))), hash(bytes(entry)), `Uncommitted foundation declaration ${path}`);
  }
  return { version: 'actql-composed-foundation/0.1', sourceRevision: head, checkpoint,
    declarations: declarations.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0).map(declaration => ({ ...declaration,
      changes: [...declaration.changes].sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0) })),
    integrations: integrations.sort((a, b) => a.revision < b.revision ? -1 : a.revision > b.revision ? 1 : 0),
    immutable: immutable.map(entry => ({ ...entry, digest: hash(bytes(immutableEntries.get(entry.path))) })).sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0),
    files: protectedPaths.map(path => ({ path, ...identity(head, path) })) };
}
