// Bounded provenance composition for the existing relation-pipeline foundation.
// Declarations are reviewable inputs, never evidence of human approval.
import assert from 'node:assert/strict';
import { lstatSync, readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { hash } from './inventory.mjs';
import { foundationAncestorQuery, foundationMergeBaseQuery, populateFoundationTrees, populateFoundationBlobs,
  foundationBlobOutputLimit } from './foundation-trees.mjs';
const sha = /^[0-9a-f]{40}$/;
const digest = /^[0-9a-f]{64}$/;
const id = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const same = (a, b) => a?.object === b?.object && a?.mode === b?.mode;
const sorted = values => [...values].sort();
// A descriptor, not a verifier. The composer calls this only after every
// record's real Git binding and complete dependency grounds have passed.
export function foundationSourceBinding(declaration, inputRevisions) {
  return { version: declaration.version, kind: declaration.kind, revision: declaration.revision,
    parents: declaration.parents,
    ...(Object.hasOwn(declaration, 'mergeBases') ? { mergeBases: declaration.mergeBases } : {}),
    changes: declaration.changes.map(({ path, before, afterDigest, afterMode }) =>
      ({ path, before, afterDigest, afterMode })).sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0),
    inputs: sorted(new Set(inputRevisions)) };
}

// Combine full source obligations, retaining every real base's grounds even
// when that base alone needs no resolution. The caller obtains the complete
// maximal-base set and every identity from checked Git objects, not a record.
export function foundationMergeObligations(revision, parents, mergeBases, evaluations) {
  assert(sha.test(revision) && parents.length === 2 && parents.every(value => sha.test(value)), 'Invalid merge obligation source');
  assert(mergeBases.length && mergeBases.every(value => sha.test(value)) && new Set(mergeBases).size === mergeBases.length,
    'Invalid merge obligation bases');
  assert.deepEqual(sorted(evaluations.map(value => value.mergeBase)), sorted(mergeBases), 'Incomplete merge obligation bases');
  const identity = value => {
    if (value === null) return null;
    keys(value, ['object', 'mode'], 'merge obligation identity');
    assert(sha.test(value.object) && ['100644', '100755'].includes(value.mode), 'Invalid merge obligation identity');
    return { object: value.object, mode: value.mode };
  };
  const bindings = new Map(), paths = new Map();
  let expectedPaths;
  for (const evaluation of [...evaluations].sort((a, b) => a.mergeBase < b.mergeBase ? -1 : 1)) {
    const actualPaths = sorted(evaluation.paths.map(value => value.path));
    assert(new Set(actualPaths).size === actualPaths.length, 'Duplicate merge obligation path');
    if (expectedPaths) assert.deepEqual(actualPaths, expectedPaths, 'Incomplete merge obligation paths');
    else expectedPaths = actualPaths;
    for (const entry of evaluation.paths) {
      assert(typeof entry.path === 'string' && entry.path.length, 'Invalid merge obligation path');
      assert(Array.isArray(entry.before) && entry.before.length === 2, 'Invalid merge obligation parents');
      const before = entry.before.map(identity), after = identity(entry.after), base = identity(entry.base);
      const binding = { revision, parents: [...parents], path: entry.path, before, after };
      const key = JSON.stringify(binding);
      assert(!paths.has(entry.path) || paths.get(entry.path) === key, 'Inconsistent merge obligation grounds');
      paths.set(entry.path, key);
      if (!bindings.has(key)) bindings.set(key, { ...binding, grounds: [] });
      // This is the existing single-base rule, applied independently to each
      // maximal base. No synthetic or arbitrarily selected base is introduced.
      const bothChanged = !same(before[0], base) && !same(before[1], base);
      const automatic = same(before[0], before[1]) ? before[0]
        : same(before[0], base) ? before[1] : same(before[1], base) ? before[0] : undefined;
      bindings.get(key).grounds.push({ mergeBase: evaluation.mergeBase, base, bothChanged,
        automatic: automatic === undefined ? { conflict: true } : { identity: automatic },
        required: bothChanged || !same(automatic, after) });
    }
  }
  return [...bindings.values()].filter(value => value.grounds.some(ground => ground.required))
    .sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}
function keys(value, expected, label) {
  assert(value && typeof value === 'object' && !Array.isArray(value), `Invalid ${label}`);
  assert.deepEqual(Object.keys(value).sort(), [...expected].sort(), `Invalid ${label} fields`);
}
export function composeFoundation(root, { checkpoint, paths, directory = 'proofs/relation-pipeline/foundation-declarations',
  supplementDirectory = `${directory}-supplements`, immutable = [] }) {
  assert.match(checkpoint, sha, 'Invalid foundation checkpoint');
  assert(Array.isArray(paths) && paths.length && new Set(paths).size === paths.length, 'Invalid foundation paths');
  const canonical = path => typeof path === 'string' && /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(path)
    && !path.split('/').some(part => part === '.' || part === '..');
  assert(paths.every(canonical) && canonical(directory) && canonical(supplementDirectory)
    && !directory.startsWith(`${supplementDirectory}/`) && !supplementDirectory.startsWith(`${directory}/`)
    && directory !== supplementDirectory, 'Invalid foundation path');
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
      cwd: root, input, env: { ...process.env, GIT_NO_REPLACE_OBJECTS: '1' },
      maxBuffer: args[0] === 'cat-file' && args[1] === '--batch'
        ? foundationBlobOutputLimit : 64 * 1024 * 1024,
    });
    assert(!result.error, `Foundation Git failed: ${result.error}`);
    if (!allowedFailure) assert.equal(result.status, 0, `Missing foundation Git history: git ${args.join(' ')}\n${result.stderr}`);
    return result;
  }
  // Read the invocation's shallow state and commit identity in one real Git
  // process. Graft paths remain a separate read because paths may contain LF.
  // This is transport batching, not a cached history or admission result.
  const metadata = git(['rev-parse', '--is-shallow-repository', '--verify', 'HEAD^{commit}']);
  const metadataLines = metadata.stdout.toString().trim().split('\n');
  assert.equal(metadataLines[0], 'false',
    'Incomplete foundation Git history: fetch full history');
  assert.equal(metadataLines.length, 2, 'Invalid foundation Git head metadata');
  const head = metadataLines[1];
  assert.match(head, sha);
  const grafts = git(['rev-parse', '--git-path', 'info/grafts']).stdout.toString().trim();
  assert(!existsSync(resolve(root, grafts)) || !readFileSync(resolve(root, grafts)).length, 'Grafted foundation Git history');
  assert(!git(['for-each-ref', '--format=%(refname)', 'refs/replace']).stdout.length, 'Replaced foundation Git history');
  // Walk the complete unsimplified ancestry once. These are Git-derived parent
  // facts, not receipt labels. Missing objects still fail before any declaration
  // is accepted; retain parent order and reject incomplete/ambiguous output.
  const completeParents = new Map();
  for (const line of git(['rev-list', '--parents', head]).stdout.toString().trim().split('\n')) {
    const [revision, ...actualParents] = line.split(' ');
    assert(sha.test(revision) && actualParents.every(value => sha.test(value))
      && !completeParents.has(revision), 'Invalid complete foundation ancestry');
    completeParents.set(revision, actualParents);
  }
  assert(completeParents.has(head), 'Missing foundation head ancestry');
  for (const actualParents of completeParents.values()) {
    assert(actualParents.every(parent => completeParents.has(parent)), 'Incomplete foundation parent ancestry');
  }
  const ancestor = foundationAncestorQuery(completeParents);
  const parentMergeBases = foundationMergeBaseQuery(completeParents);
  assert(ancestor(checkpoint, head), 'Foundation checkpoint is not an ancestor of HEAD');
  const revisions = git(['rev-list', '--reverse', '--topo-order', `${checkpoint}..${head}`]).stdout.toString().trim().split('\n').filter(Boolean);
  const revisionSet = new Set(revisions), trees = new Map(), blobs = new Map(), verifiedObjects = new Map();
  function parents(revision) {
    assert(completeParents.has(revision), `Missing foundation parent facts ${revision}`);
    return completeParents.get(revision);
  }
  const mergeBaseCache = new Map();
  function mergeBases(revision) {
    if (!mergeBaseCache.has(revision)) {
      const actualParents = parents(revision);
      assert.equal(actualParents.length, 2, 'Invalid foundation merge parent count');
      const bases = parentMergeBases(...actualParents);
      assert(bases.length && bases.every(value => sha.test(value)) && new Set(bases).size === bases.length,
        'Invalid foundation merge bases');
      mergeBaseCache.set(revision, bases);
    }
    return mergeBaseCache.get(revision);
  }
  function verifyObjects(objects) {
    const unchecked = [...new Set(objects)].filter(object => !verifiedObjects.has(object));
    for (let offset = 0; offset < unchecked.length; offset += 256) {
      const batch = unchecked.slice(offset, offset + 256);
      const checked = git(['cat-file', '--batch-check'], { input: `${batch.join('\n')}\n` }).stdout.toString().trim().split('\n');
      assert.equal(checked.length, batch.length, 'Incomplete foundation Git object check');
      const objects = checked.map((line, index) => {
        const match = new RegExp(`^${batch[index]} blob (0|[1-9][0-9]*)$`).exec(line);
        assert(match, 'Missing foundation Git blob');
        return {object: batch[index], size: Number(match[1])};
      });
      // Independently checked object kind/size still precedes every body read.
      // Batch only transport; all actual bytes feed the unchanged validation.
      populateFoundationBlobs({objects, blobs,
        git: (args, input) => git(args, {input}).stdout});
      for (const entry of objects) verifiedObjects.set(entry.object, entry.size);
    }
  }
  function tree(revision) {
    if (!trees.has(revision)) {
      const output = git(['ls-tree', '-r', '-z', revision, '--', ...inspectedPaths, directory, supplementDirectory]).stdout.toString();
      const entries = new Map();
      for (const entry of output.split('\0').filter(Boolean)) {
        const match = /^(\d+) (\w+) ([0-9a-f]{40})\t(.*)$/.exec(entry);
        assert(match, 'Invalid foundation Git tree entry');
        const [, mode, type, object, path] = match;
        assert(type === 'blob' && ['100644', '100755'].includes(mode), `Non-regular foundation file ${path}`);
        entries.set(path, { mode, object });
      }
      verifyObjects([...entries.values()].map(entry => entry.object));
      trees.set(revision, entries);
    }
    return trees.get(revision);
  }
  function bytes(entry) {
    if (!blobs.has(entry.object)) verifyObjects([entry.object]);
    assert(blobs.has(entry.object), 'Missing verified foundation blob bytes');
    return blobs.get(entry.object);
  }
  function identity(revision, path) {
    const entry = tree(revision).get(path);
    return { revision, digest: entry ? hash(bytes(entry)) : null, mode: entry?.mode ?? null };
  }
  populateFoundationTrees({revisions, parents,
    paths: [...inspectedPaths, directory, supplementDirectory], tree, trees, verifyObjects,
    git: (args, input) => git(args, {input}).stdout});
  const immutableEntries = new Map(immutable.map(entry => {
    const expected = tree(entry.revision).get(entry.sourcePath ?? entry.path);
    assert(expected, `Missing immutable foundation Git object ${entry.path}`);
    return [entry.path, expected];
  }));
  const declarationsAt = revision => new Map([...tree(revision)].filter(([path]) => path.startsWith(`${directory}/`)));
  const supplementsAt = revision => new Map([...tree(revision)].filter(([path]) => path.startsWith(`${supplementDirectory}/`)));
  assert.equal(declarationsAt(checkpoint).size, 0, 'Foundation checkpoint already contains declarations');
  assert.equal(supplementsAt(checkpoint).size, 0, 'Foundation checkpoint already contains supplements');
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
    for (const parent of actualParents) for (const [path, entry] of [...declarationsAt(parent), ...supplementsAt(parent)]) {
      assert(!inherited.has(path) || same(inherited.get(path), entry), `Ambiguous foundation declaration ${path}`);
      inherited.set(path, entry);
    }
    const current = new Map([...declarationsAt(revision), ...supplementsAt(revision)]);
    for (const [path, entry] of inherited) assert(same(entry, current.get(path)), `Changed or removed foundation declaration ${path}`);
    for (const [path, entry] of current) if (!inherited.has(path)) {
      assert(entry.mode === '100644', `Invalid foundation declaration mode ${path}`);
      const previous = introductions.get(path);
      assert(!previous || same(previous.entry, entry), `Conflicting foundation declaration introduction ${path}`);
      if (previous) previous.revisions.push(revision);
      else introductions.set(path, { entry, revisions: [revision] });
    }
  }
  // A committed, digest-bound supplement may normalize only an exact redundant
  // singleton. Originals and their introductions remain immutable. Full schema,
  // target digest and introduction checks below still apply to every supplement.
  const singleBaseNormalizations = new Map();
  for (const [, entry] of supplementsAt(head)) {
    const record = JSON.parse(bytes(entry));
    if (record.version !== 'actql-foundation-single-base-normalization/0.1') continue;
    assert(!singleBaseNormalizations.has(record.target?.id), 'Duplicate foundation single-base normalization');
    singleBaseNormalizations.set(record.target?.id, record);
  }
  // An exact copied introduction can be reconciled only after a real merge of
  // the original declaration commit. The source must still be in HEAD's DAG;
  // this record never admits an unrelated source or rewrites an introduction.
  const declarationCopies = new Map(), checkedCopyRecords = new Map();
  for (const [path, entry] of supplementsAt(head)) {
    const raw = bytes(entry), record = JSON.parse(raw);
    if (record.version !== 'actql-foundation-declaration-copy/0.1') continue;
    assert(raw.equals(Buffer.from(`${JSON.stringify(record, null, 2)}\n`)), 'Noncanonical foundation copy JSON');
    keys(record, ['version', 'id', 'target', 'original', 'copy', 'reconciliation', 'reason'], 'foundation copy');
    assert.match(record.id, id, 'Invalid foundation copy ID');
    assert.equal(path, `${supplementDirectory}/${record.id}.json`, 'Ambiguous foundation copy filename');
    keys(record.target, ['id', 'digest'], 'foundation copy target');
    assert.match(record.target.id, id, 'Invalid foundation copy target ID');
    assert.match(record.target.digest, digest, 'Invalid foundation copy target digest');
    assert(typeof record.reason === 'string' && record.reason.trim(), 'Missing foundation copy rationale');
    assert(!declarationCopies.has(record.target.id), 'Duplicate foundation copy target');
    const targetPath = `${directory}/${record.target.id}.json`, target = declarationsAt(head).get(targetPath);
    assert(target && target.mode === '100644', 'Missing or wrong-mode foundation copy target');
    assert.equal(hash(bytes(target)), record.target.digest, 'Changed foundation copy target');
    const declaration = JSON.parse(bytes(target));
    assert(revisionSet.has(declaration.revision), 'Unrelated foundation copy supporting revision');
    for (const name of ['original', 'copy', 'reconciliation']) {
      const binding = record[name];
      keys(binding, ['revision', 'parents'], `foundation copy ${name}`);
      assert(sha.test(binding.revision) && revisionSet.has(binding.revision), 'Unrelated foundation copy commit');
      assert.deepEqual(binding.parents, parents(binding.revision), 'Incorrect foundation copy parents');
      assert(same(tree(binding.revision).get(targetPath), target), 'Different foundation copy bytes or mode');
    }
    const original = record.original.revision, copy = record.copy.revision, merge = record.reconciliation.revision;
    assert(record.original.parents.length === 1 && record.copy.parents.length === 1,
      'Foundation copy must name single-parent introductions');
    assert(original !== copy && declaration.revision !== original && ancestor(declaration.revision, original),
      'Foundation copy original must follow its source');
    assert(!ancestor(declaration.revision, copy), 'Foundation copy must identify a non-ancestral introduction');
    for (const binding of [record.original, record.copy]) {
      assert(!tree(binding.parents[0]).has(targetPath)
        && introductions.get(targetPath).revisions.includes(binding.revision), 'Not a foundation copy introduction');
      // Inspect the whole commit, including unprotected paths. These two exact
      // commits may only introduce this declaration, with no bundled changes.
      assert.deepEqual(git(['diff-tree', '--no-commit-id', '--name-only', '-r', '-z',
        binding.parents[0], binding.revision]).stdout.toString().split('\0').filter(Boolean), [targetPath],
      'Foundation copy introduction contains other changes');
    }
    assert(record.reconciliation.parents.length === 2 && record.reconciliation.parents[1] === original,
      'Foundation copy reconciliation must merge its exact original');
    const first = record.reconciliation.parents[0];
    assert(ancestor(copy, first) && !ancestor(original, first), 'Incorrect foundation copy reconciliation ancestry');
    assert.equal(git(['rev-parse', `${merge}^{tree}`]).stdout.toString().trim(),
      git(['rev-parse', `${first}^{tree}`]).stdout.toString().trim(),
      'Foundation copy reconciliation changed the copied tree');
    const automaticMerge = git(['merge-tree', '--write-tree', first, original], { allowedFailure: true });
    assert.equal(automaticMerge.status, 0, 'Foundation copy reconciliation is not a clean normal merge');
    assert.equal(automaticMerge.stdout.toString().trim(),
      git(['rev-parse', `${merge}^{tree}`]).stdout.toString().trim(),
      'Foundation copy reconciliation differs from normal merge');
    const introduced = sorted(introductions.get(path).revisions);
    for (const introduction of introduced) {
      assert(introduction !== merge && ancestor(merge, introduction), 'Foundation copy record must follow reconciliation');
    }
    declarationCopies.set(record.target.id, record);
    checkedCopyRecords.set(path, { path, digest: hash(raw), introductions: introduced, ...record });
  }
  const declarations = [], byRevision = new Map(), byId = new Map();
  for (const [path, entry] of declarationsAt(head)) {
    const declarationBytes = bytes(entry);
    const declaration = JSON.parse(declarationBytes);
    // One reviewable encoding also rejects duplicate JSON keys and lossy UTF-8.
    assert(declarationBytes.equals(Buffer.from(`${JSON.stringify(declaration, null, 2)}\n`)), 'Noncanonical or ambiguous foundation declaration JSON');
    const expectedKeys = ['version', 'id', 'kind', 'revision', 'parents', 'changes'];
    if (declaration.kind === 'resolution') {
      expectedKeys.push('inputs');
      if (Object.hasOwn(declaration, 'mergeBases')) expectedKeys.push('mergeBases');
    }
    keys(declaration, expectedKeys, 'foundation declaration');
    assert.equal(declaration.version, 'actql-foundation-declaration/0.1');
    assert.match(declaration.id, id, 'Invalid foundation declaration ID');
    assert.equal(path, `${directory}/${declaration.id}.json`, 'Ambiguous foundation declaration filename');
    assert(!byId.has(declaration.id), 'Duplicate foundation declaration ID');
    assert.match(declaration.revision, sha, 'Invalid foundation supporting revision');
    assert(revisionSet.has(declaration.revision), 'Unrelated foundation supporting revision');
    assert(Array.isArray(declaration.parents) && declaration.parents.every(value => sha.test(value)), 'Invalid foundation parents');
    assert.deepEqual(declaration.parents, parents(declaration.revision), 'Incorrect foundation supporting parents');
    if (declaration.parents.length === 2 && mergeBases(declaration.revision).length > 1) {
      assert.deepEqual(declaration.mergeBases, mergeBases(declaration.revision), 'Incomplete or noncanonical foundation merge bases');
    } else if (singleBaseNormalizations.has(declaration.id)) {
      assert(declaration.kind === 'resolution' && declaration.parents.length === 2,
        'Invalid foundation single-base normalization target');
      assert.deepEqual(declaration.mergeBases, mergeBases(declaration.revision),
        'Incorrect foundation singleton merge base');
    } else assert(!Object.hasOwn(declaration, 'mergeBases'), 'Spurious foundation merge bases');
    const declarationIntroductions = sorted(introductions.get(path).revisions);
    for (const introduction of declarationIntroductions) {
      if (declarationCopies.get(declaration.id)?.copy.revision === introduction) continue;
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
  // Preserve a rejected co-introduction as rejected provenance. Only a new,
  // independently checked, strictly later receipt can supply its inputs.
  const temporalRepairs = new Map(), checkedRepairRecords = new Map(), repairReplacements = new Set();
  for (const [path, entry] of supplementsAt(head)) {
    const raw = bytes(entry), repair = JSON.parse(raw);
    if (repair.version !== 'actql-foundation-supplement-repair/0.1') continue;
    assert(raw.equals(Buffer.from(`${JSON.stringify(repair, null, 2)}\n`)), 'Noncanonical foundation repair JSON');
    keys(repair, ['version', 'id', 'target', 'rejectedIntroductions', 'replacement', 'reason'], 'foundation repair');
    assert.match(repair.id, id, 'Invalid foundation repair ID');
    assert.equal(path, `${supplementDirectory}/${repair.id}.json`, 'Ambiguous foundation repair filename');
    for (const binding of [repair.target, repair.replacement]) {
      keys(binding, ['id', 'digest'], 'foundation repair binding');
      assert.match(binding.id, id, 'Invalid foundation repair binding ID');
      assert.match(binding.digest, digest, 'Invalid foundation repair binding digest');
    }
    assert(typeof repair.reason === 'string' && repair.reason.trim(), 'Missing foundation repair rationale');
    assert(!temporalRepairs.has(repair.target.id), 'Duplicate foundation temporal repair');
    assert(!repairReplacements.has(repair.replacement.id), 'Duplicate foundation repair replacement');
    const bound = binding => {
      const boundPath = `${supplementDirectory}/${binding.id}.json`, boundEntry = supplementsAt(head).get(boundPath);
      assert(boundEntry && hash(bytes(boundEntry)) === binding.digest, 'Missing or changed foundation repair binding');
      const value = JSON.parse(bytes(boundEntry));
      assert.equal(value.version, 'actql-foundation-resolution-supplement/0.1', 'Wrong-kind foundation repair binding');
      assert.equal(value.id, binding.id, 'Ambiguous foundation repair binding');
      return { value, introductions: sorted(introductions.get(boundPath).revisions) };
    };
    const original = bound(repair.target), replacement = bound(repair.replacement);
    assert.notEqual(repair.target.id, repair.replacement.id, 'Self-replacing foundation repair');
    assert.deepEqual(replacement.value.target, original.value.target, 'Changed foundation repair target');
    assert.deepEqual(replacement.value.inputs, original.value.inputs, 'Changed foundation repair inputs');
    assert(Array.isArray(original.value.inputs) && original.value.inputs.length
      && original.value.inputs.every(input => byId.has(input)), 'Unknown foundation repair dependency');
    const rejected = original.introductions.filter(introduction => {
      let coIntroduced = false;
      for (const input of original.value.inputs) {
        const dependency = declarations.find(value => value.id === input);
        if (dependency.introductions.some(prior => prior !== introduction && ancestor(prior, introduction))) continue;
        assert(dependency.introductions.includes(introduction), 'Foundation repair requires exact co-introduction');
        coIntroduced = true;
      }
      return coIntroduced;
    });
    assert(rejected.length, 'Foundation repair requires a rejected co-introduction');
    assert.deepEqual(repair.rejectedIntroductions, rejected.map(revision => ({revision, parents: parents(revision)})),
      'Incorrect foundation repair rejected introductions');
    for (const introduction of replacement.introductions) {
      assert(original.introductions.every(prior => prior !== introduction && ancestor(prior, introduction)),
        'Foundation repair replacement must follow every original introduction');
    }
    const introduced = sorted(introductions.get(path).revisions);
    for (const introduction of introduced) {
      assert(replacement.introductions.every(prior => prior !== introduction && ancestor(prior, introduction)),
        'Foundation repair must follow every replacement introduction');
    }
    temporalRepairs.set(repair.target.id, repair);
    repairReplacements.add(repair.replacement.id);
    checkedRepairRecords.set(path, {path, digest: hash(raw), introductions: introduced, ...repair});
  }
  for (const target of temporalRepairs.keys()) {
    assert(!repairReplacements.has(target), 'Chained foundation temporal repair');
  }
  const supplements = [], supplementsByTarget = new Map(), completionsByTarget = new Map();
  const inputNormalizationsByTarget = new Map();
  // Originals remain immutable. A completion may only add separately checked
  // missing source paths, never replace an original field or acceptance rule.
  const effectiveChanges = declaration => [...declaration.changes,
    ...(completionsByTarget.get(declaration.id) ?? []).flatMap(record => record.changes)];
  for (const [path, entry] of supplementsAt(head)) {
    if (checkedRepairRecords.has(path)) {
      supplements.push(checkedRepairRecords.get(path));
      continue;
    }
    if (checkedCopyRecords.has(path)) {
      supplements.push(checkedCopyRecords.get(path));
      continue;
    }
    const raw = bytes(entry), supplement = JSON.parse(raw);
    assert(raw.equals(Buffer.from(`${JSON.stringify(supplement, null, 2)}\n`)), 'Noncanonical foundation supplement JSON');
    const completion = supplement.version === 'actql-foundation-change-completion/0.1';
    const normalization = supplement.version === 'actql-foundation-single-base-normalization/0.1';
    const equivalence = supplement.version === 'actql-foundation-supplement-equivalence/0.1';
    const inputNormalization = supplement.version === 'actql-foundation-irrelevant-input-normalization/0.1';
    keys(supplement, ['version', 'id', 'target', ...(normalization ? [] : [completion ? 'changes' : equivalence ? 'members' : inputNormalization ? 'removeInputs' : 'inputs']), 'reason'], 'foundation supplement');
    if (!completion && !normalization && !equivalence && !inputNormalization) assert.equal(supplement.version, 'actql-foundation-resolution-supplement/0.1');
    assert.match(supplement.id, id, 'Invalid foundation supplement ID');
    assert.equal(path, `${supplementDirectory}/${supplement.id}.json`, 'Ambiguous foundation supplement filename');
    keys(supplement.target, ['id', 'digest'], 'foundation supplement target');
    const original = declarations.find(value => value.id === supplement.target.id);
    assert(original?.kind === (completion ? 'change' : 'resolution'), 'Unknown or wrong-kind foundation supplement target');
    assert.equal(supplement.target.digest, original.digest, 'Changed foundation supplement original');
    assert(typeof supplement.reason === 'string' && supplement.reason.trim(), 'Missing foundation supplement rationale');
    if (normalization) {
      assert(original.parents.length === 2 && mergeBases(original.revision).length === 1,
        'Non-singleton foundation normalization target');
      assert.deepEqual(original.mergeBases, mergeBases(original.revision),
        'Incorrect foundation singleton merge base');
    } else if (completion) {
      assert(Array.isArray(supplement.changes) && supplement.changes.length, 'Empty foundation completion changes');
      const paths = supplement.changes.map(change => change.path);
      assert.deepEqual(paths, sorted(new Set(paths)), 'Noncanonical foundation completion paths');
      const priorPaths = new Set(effectiveChanges(original).map(change => change.path));
      for (const change of supplement.changes) {
        keys(change, ['path', 'before', 'afterDigest', 'afterMode', 'reason'], 'foundation completion change');
        assert(allowed.has(change.path), `Unknown foundation completion path ${change.path}`);
        assert(!priorPaths.has(change.path), 'Redundant foundation completion path');
        assert(typeof change.reason === 'string' && change.reason.trim(), 'Missing foundation completion rationale');
        assert.match(change.afterDigest, digest, 'Incorrect foundation completion digest');
        assert(['100644', '100755'].includes(change.afterMode), 'Invalid foundation completion mode');
        const before = original.parents.map(parent => identity(parent, change.path));
        assert.deepEqual(change.before, before, 'Incorrect foundation completion prior identity');
        const after = identity(original.revision, change.path);
        assert.equal(change.afterDigest, after.digest, 'Incorrect foundation completion current digest');
        assert.equal(change.afterMode, after.mode, 'Incorrect foundation completion current mode');
        assert(before.some(entry => entry.digest !== after.digest || entry.mode !== after.mode), 'Unchanged foundation completion path');
      }
    } else if (equivalence) {
      assert(Array.isArray(supplement.members) && supplement.members.length >= 2,
        'Incomplete foundation supplement equivalence members');
      for (const member of supplement.members) {
        keys(member, ['id', 'digest'], 'foundation supplement equivalence member');
        assert.match(member.id, id, 'Invalid foundation supplement equivalence member ID');
        assert.match(member.digest, digest, 'Invalid foundation supplement equivalence member digest');
      }
      assert.deepEqual(supplement.members.map(member => member.id),
        sorted(new Set(supplement.members.map(member => member.id))),
        'Noncanonical foundation supplement equivalence members');
    } else if (inputNormalization) {
      assert(!inputNormalizationsByTarget.has(original.id), 'Duplicate foundation input normalization');
      assert(Array.isArray(supplement.removeInputs) && supplement.removeInputs.length
        && supplement.removeInputs.every(value => typeof value === 'string' && byId.has(value)),
      'Unknown or empty foundation input normalization');
      assert.deepEqual(supplement.removeInputs, sorted(new Set(supplement.removeInputs)),
        'Noncanonical foundation input normalization');
      assert(Array.isArray(original.inputs) && supplement.removeInputs.every(value => original.inputs.includes(value)),
        'Foundation input normalization must name original inputs');
    } else {
      assert(Array.isArray(supplement.inputs) && supplement.inputs.length
        && supplement.inputs.every(value => typeof value === 'string' && byId.has(value)), 'Unknown or empty foundation supplement inputs');
      assert.deepEqual(supplement.inputs, sorted(new Set(supplement.inputs)), 'Noncanonical foundation supplement inputs');
    }
    const introduced = sorted(introductions.get(path).revisions);
    for (const introduction of introduced) {
      assert(original.introductions.some(prior => prior !== introduction && ancestor(prior, introduction)),
        'Foundation supplement must follow its original declaration');
      if (!completion && !normalization && !equivalence) for (const input of inputNormalization ? supplement.removeInputs : supplement.inputs) {
        const dependency = declarations.find(value => value.id === input);
        if (!dependency.introductions.some(prior => prior !== introduction && ancestor(prior, introduction))) {
          const repair = temporalRepairs.get(supplement.id);
          assert(repair && dependency.introductions.includes(introduction)
            && repair.rejectedIntroductions.some(value => value.revision === introduction),
          'Foundation supplement must follow its dependency declaration');
        }
      }
    }
    const repair = temporalRepairs.get(supplement.id);
    const record = { path, digest: hash(raw), introductions: introduced, ...supplement,
      ...(repair ? {disposition: 'repaired_co_introduction', temporalRepair: repair.id} : {}) };
    supplements.push(record);
    if (repair) continue;
    if (inputNormalization) {
      inputNormalizationsByTarget.set(original.id, record);
      continue;
    }
    if (normalization || equivalence) continue;
    const collection = completion ? completionsByTarget : supplementsByTarget;
    if (!collection.has(original.id)) collection.set(original.id, []);
    collection.get(original.id).push(record);
  }
  // Equivalence is explicit and digest-bound. Every raw receipt still passes
  // its own schema, Git, ancestry, late-introduction and source-binding checks.
  // This joins only complete, equal late source sets across separate receipts;
  // it cannot excuse an original dependency or a duplicate within one receipt.
  const equivalentSupplements = new Map();
  for (const equivalence of supplements.filter(record =>
    record.version === 'actql-foundation-supplement-equivalence/0.1')) {
    let sources;
    for (const member of equivalence.members) {
      const raw = supplements.find(record => record.id === member.id);
      assert(raw?.version === 'actql-foundation-resolution-supplement/0.1',
        'Unknown or wrong-kind foundation supplement equivalence member');
      assert(!temporalRepairs.has(raw.id), 'Rejected foundation receipt cannot supply equivalence');
      assert.equal(member.digest, raw.digest, 'Changed foundation supplement equivalence member');
      assert.deepEqual(raw.target, equivalence.target,
        'Different foundation supplement equivalence targets');
      for (const introduction of equivalence.introductions) {
        assert(raw.introductions.some(prior => prior !== introduction && ancestor(prior, introduction)),
          'Foundation supplement equivalence must follow every member');
      }
      const current = sorted(new Set(raw.inputs.map(input => byId.get(input).revision)));
      assert.equal(current.length, raw.inputs.length,
        'Redundant dependency within foundation supplement equivalence member');
      if (sources) assert.deepEqual(current, sources,
        'Different foundation supplement equivalence source sets');
      else sources = current;
      assert(!equivalentSupplements.has(raw.id), 'Ambiguous foundation supplement equivalence');
      equivalentSupplements.set(raw.id, equivalence.id);
    }
  }
  const requirements = new Map();
  for (const revision of revisions) {
    const actualParents = parents(revision), required = [], result = tree(revision);
    const bases = actualParents.length === 2 ? mergeBases(revision) : [];
    for (const path of protectedPaths) {
      const after = result.get(path), before = actualParents.map(parent => tree(parent).get(path));
      assert(after || before.every(entry => !entry), `Deleted foundation file ${path}`);
      for (const entry of before) assert(!entry || !after || entry.mode === after.mode, `Unsupported foundation mode change ${path}`);
      if (actualParents.length === 1) {
        if (!same(before[0], after)) required.push(path);
      }
    }
    const obligations = bases.length ? foundationMergeObligations(revision, actualParents, bases,
      bases.map(mergeBase => ({ mergeBase, paths: protectedPaths.map(path => ({ path,
        before: actualParents.map(parent => tree(parent).get(path) ?? null), after: result.get(path) ?? null,
        base: tree(mergeBase).get(path) ?? null })) }))) : [];
    required.push(...obligations.map(obligation => obligation.path));
    const candidates = byRevision.get(revision);
    if (!required.length) {
      assert(!candidates, 'Spurious foundation declaration');
      if (bases.length > 1) requirements.set(revision, { actualParents, required, bases, obligations });
      continue;
    }
    assert(candidates, `Unlisted foundation source change ${revision}: ${required.join(', ')}`);
    for (const declaration of candidates) {
      assert.equal(declaration.kind, actualParents.length === 1 ? 'change' : 'resolution', 'Incorrect foundation declaration kind');
      assert.deepEqual(sorted(effectiveChanges(declaration).map(change => change.path)), sorted(required), 'Incomplete foundation changed paths');
    }
    requirements.set(revision, { actualParents, required, bases, obligations });
  }
  const integrations = [];
  // All records have now independently matched real source commits and the
  // complete changed-path set. Validate ancestor dependencies in topological
  // order before allowing equivalent records to share a source-binding group.
  for (const [revision, { actualParents, required, bases, obligations }] of requirements) {
    const candidates = byRevision.get(revision);
    if (!required.length) {
      integrations.push({ revision, parents: actualParents, mergeBases: bases, obligations, declarations: [] });
      continue;
    }
    let inputs = [];
    if (actualParents.length === 2) {
      inputs = sorted(new Set(declarations.filter(candidate => candidate.revision !== revision
        && effectiveChanges(candidate).some(change => required.includes(change.path))
        && actualParents.some(parent => ancestor(candidate.revision, parent))).map(candidate => candidate.revision)));
    }
    let binding;
    for (const declaration of candidates) {
      let inputRevisions = [];
      if (declaration.kind === 'resolution') {
        assert(Array.isArray(declaration.inputs) && declaration.inputs.every(value => typeof value === 'string' && byId.has(value)),
          'Unknown foundation resolution input');
        assert.deepEqual(declaration.inputs, sorted(new Set(declaration.inputs)), 'Noncanonical foundation resolution inputs');
        const normalization = inputNormalizationsByTarget.get(declaration.id);
        const removed = new Set(normalization?.removeInputs ?? []);
        if (normalization) {
          // Only a reviewed, digest-bound correction may remove raw inputs.
          // Each complete source group must be a real ancestor but unrelated
          // to every actual resolution obligation, including completed paths.
          const removedRevisions = new Set([...removed].map(value => byId.get(value).revision));
          for (const source of removedRevisions) {
            assert(actualParents.some(parent => ancestor(source, parent)),
              'Non-ancestral foundation input normalization');
            assert(!declarations.some(value => value.revision === source
              && effectiveChanges(value).some(change => required.includes(change.path))),
            'Relevant foundation input cannot be normalized');
            assert(declaration.inputs.filter(value => byId.get(value).revision === source)
              .every(value => removed.has(value)), 'Ambiguous partial foundation input normalization');
          }
        }
        inputRevisions = sorted(new Set(declaration.inputs.filter(value => !removed.has(value))
          .map(value => byId.get(value).revision)));
        const additions = supplementsByTarget.get(declaration.id) ?? [];
        if (additions.length) {
          // A supplement repairs only a source group whose receipt was absent
          // at every original introduction. Never excuse an omission that was
          // already visible, replace a raw input, or ignore an inherited record.
          const original = declarations.find(value => value.id === declaration.id);
          for (const introduction of original.introductions) {
            const visible = inputs.filter(source => declarations.some(value => value.revision === source
              && value.introductions.some(prior => ancestor(prior, introduction))));
            assert.deepEqual(inputRevisions, visible, 'Incomplete original foundation resolution inputs');
          }
          const effective = new Set(inputRevisions);
          const lateSources = new Map();
          for (const supplement of additions) for (const input of supplement.inputs) {
            const source = byId.get(input).revision;
            assert(inputs.includes(source), 'Non-ancestral or cyclic foundation supplement dependency');
            if (effective.has(source)) {
              const prior = lateSources.get(source);
              assert(prior && prior.id !== supplement.id &&
                equivalentSupplements.has(prior.id) &&
                equivalentSupplements.get(prior.id) === equivalentSupplements.get(supplement.id),
              'Redundant foundation supplement dependency');
            } else lateSources.set(source, supplement);
            effective.add(source);
          }
          inputRevisions = sorted(effective);
        }
        assert.deepEqual(inputRevisions, inputs, 'Incomplete or ambiguous foundation resolution inputs');
      }
      const effectiveDeclaration = { ...declaration, changes: effectiveChanges(declaration) };
      if (singleBaseNormalizations.has(declaration.id)) delete effectiveDeclaration.mergeBases;
      const current = foundationSourceBinding(effectiveDeclaration, inputRevisions);
      if (binding) assert.deepEqual(current, binding, 'Conflicting foundation source-binding declarations');
      else binding = current;
    }
    if (actualParents.length === 2) {
      integrations.push({ revision, parents: actualParents,
        ...(bases.length === 1 ? { mergeBase: bases[0] } : { mergeBases: bases, obligations }),
        declarations: sorted(candidates.map(candidate => candidate.id)),
        ...(candidates.some(value => inputNormalizationsByTarget.has(value.id)) ? {
          inputNormalizations: sorted(candidates.filter(value => inputNormalizationsByTarget.has(value.id))
            .map(value => inputNormalizationsByTarget.get(value.id).id)),
        } : {}),
        ...(candidates.some(value => supplementsByTarget.has(value.id)) ? {
          supplements: sorted(candidates.flatMap(value => (supplementsByTarget.get(value.id) ?? []).map(value => value.id))),
        } : {}) });
    }
  }
  const expectedIndex = new Map([...tree(head)].filter(([path]) => allowed.has(path)
    || immutablePaths.includes(path) || path.startsWith(`${directory}/`) || path.startsWith(`${supplementDirectory}/`)));
  const indexEntries = git(['ls-files', '--stage', '-z', '--', ...protectedPaths, ...immutablePaths, directory, supplementDirectory]).stdout.toString().split('\0').filter(Boolean);
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
  for (const [folder, records] of [[directory, declarationsAt(head)], [supplementDirectory, supplementsAt(head)]]) {
    const directoryPath = join(root, folder);
    const workingDeclarations = existsSync(directoryPath) ? readdirSync(directoryPath).map(name => `${folder}/${name}`).sort() : [];
    assert.deepEqual(workingDeclarations, sorted(records.keys()), 'Uncommitted foundation declaration membership');
  }
  for (const [path, entry] of [...declarationsAt(head), ...supplementsAt(head)]) {
    workingFile(path, entry.mode);
    assert.equal(hash(readFileSync(join(root, path))), hash(bytes(entry)), `Uncommitted foundation declaration ${path}`);
  }
  return { version: 'actql-composed-foundation/0.1', sourceRevision: head, checkpoint,
    declarations: declarations.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0).map(declaration => ({ ...declaration,
      changes: [...declaration.changes].sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0) })),
    ...(completionsByTarget.size ? { changeCompletions: [...completionsByTarget].map(([target, records]) => ({
      target, supplements: sorted(records.map(record => record.id)),
      changes: effectiveChanges(byId.get(target)).sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0),
    })).sort((a, b) => a.target < b.target ? -1 : a.target > b.target ? 1 : 0) } : {}),
    integrations: integrations.sort((a, b) => a.revision < b.revision ? -1 : a.revision > b.revision ? 1 : 0),
    ...(supplements.length ? { supplements: supplements.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0) } : {}),
    immutable: immutable.map(entry => ({ ...entry, digest: hash(bytes(immutableEntries.get(entry.path))) })).sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0),
    files: protectedPaths.map(path => ({ path, ...identity(head, path) })) };
}
