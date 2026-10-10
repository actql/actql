// Lossless, invocation-local transport for the existing complete Git history.
// Every commit still has a complete selected tree; no source change is skipped.
import assert from 'node:assert/strict';

const sha = /^[a-f0-9]{40}$/u;
const zero = '0'.repeat(40);
const modes = new Set(['000000', '100644', '100755']);
const same = (a, b) => a?.mode === b?.mode && a?.object === b?.object;

export function foundationAncestorQuery(completeParents) {
  // Snapshot the complete Git-derived graph. Cache reachability only for
  // queried descendants, without simplifying merges or filtering revisions.
  const ordinals = new Map([...completeParents.keys()].map((revision, index) => [revision, index]));
  const parents = [...completeParents].map(([revision, values]) => {
    assert(sha.test(revision) && Array.isArray(values), 'Invalid complete foundation ancestry');
    return values.map(parent => {
      assert(sha.test(parent) && ordinals.has(parent), 'Incomplete foundation parent ancestry');
      return ordinals.get(parent);
    });
  });
  const reachable = new Map(), words = Math.ceil(parents.length / 32);
  return (a, b) => {
    if (!ordinals.has(a) || !ordinals.has(b)) return false;
    const source = ordinals.get(a), descendant = ordinals.get(b);
    if (!reachable.has(descendant)) {
      const bits = new Uint32Array(words), pending = [descendant];
      while (pending.length) {
        const current = pending.pop(), word = current >>> 5, mask = 1 << (current & 31);
        if ((bits[word] & mask) !== 0) continue;
        bits[word] |= mask;
        for (const parent of parents[current]) pending.push(parent);
      }
      reachable.set(descendant, bits);
    }
    return (reachable.get(descendant)[source >>> 5] & (1 << (source & 31))) !== 0;
  };
}

export function readFoundationTreeDeltas(output, revisions, paths) {
  assert(Buffer.isBuffer(output) && revisions.length > 0 && revisions.length <= 256,
    'Invalid foundation tree batch');
  assert(revisions.every(value => sha.test(value)) && new Set(revisions).size === revisions.length,
    'Invalid foundation tree revisions');
  const selected = path => paths.some(value => path === value || path.startsWith(`${value}/`));
  let offset = 0;
  function field() {
    const end = output.indexOf(0, offset);
    assert(end >= offset, 'Truncated foundation tree batch');
    const bytes = output.subarray(offset, end), value = bytes.toString('utf8');
    assert(Buffer.from(value).equals(bytes), 'Invalid foundation tree path encoding');
    offset = end + 1;
    return value;
  }
  const frames = new Map();
  for (const revision of revisions) {
    assert.equal(field(), revision, 'Missing/reordered foundation tree revision');
    const entries = [], seen = new Set();
    while (offset < output.length && output[offset] === 58) {
      const header = /^:(\d{6}) (\d{6}) ([a-f0-9]{40}) ([a-f0-9]{40}) ([AMD])$/u.exec(field());
      assert(header, 'Invalid foundation tree delta');
      const [, beforeMode, afterMode, beforeObject, afterObject, status] = header;
      assert(modes.has(beforeMode) && modes.has(afterMode), 'Non-regular foundation tree delta');
      const path = field();
      assert(path.length && !path.split('/').some(value => ['', '.', '..'].includes(value))
        && selected(path) && !seen.has(path), 'Unexpected/duplicate foundation tree path');
      seen.add(path);
      const absentBefore = beforeMode === '000000', absentAfter = afterMode === '000000';
      assert.equal(absentBefore, beforeObject === zero, 'Inconsistent prior foundation tree identity');
      assert.equal(absentAfter, afterObject === zero, 'Inconsistent current foundation tree identity');
      assert(status === 'A' ? absentBefore && !absentAfter : status === 'D'
        ? !absentBefore && absentAfter : !absentBefore && !absentAfter,
      'Inconsistent foundation tree delta status');
      const before = absentBefore ? undefined : {mode: beforeMode, object: beforeObject};
      const after = absentAfter ? undefined : {mode: afterMode, object: afterObject};
      assert(!same(before, after), 'Unchanged foundation tree delta');
      entries.push({path, before, after});
    }
    frames.set(revision, entries);
  }
  assert.equal(offset, output.length, 'Unexpected extra foundation tree batch');
  return frames;
}

export function populateFoundationTrees({revisions, parents, paths, git, tree, trees, verifyObjects}) {
  // The supplied first parent is independently obtained from the complete,
  // unsimplified graph. Other parents and every maximal base still participate
  // in the unchanged merge/ancestry/introduction/dependency validation.
  for (let offset = 0; offset < revisions.length; offset += 256) {
    const batch = revisions.slice(offset, offset + 256);
    const input = batch.map(revision => {
      const actual = parents(revision);
      assert(actual.length === 1 || actual.length === 2, 'Unsupported foundation merge parent count');
      return `${revision} ${actual[0]}`;
    }).join('\n') + '\n';
    const output = git(['diff-tree', '--stdin', '-r', '--raw', '-z', '--always',
      '--no-renames', '--no-ext-diff', '--no-textconv', '--no-relative',
      '--ignore-submodules=none', '--', ...paths], input);
    const frames = readFoundationTreeDeltas(output, batch, paths), objects = new Set();
    for (const revision of batch) {
      const entries = new Map(tree(parents(revision)[0]));
      for (const {path, before, after} of frames.get(revision)) {
        assert(same(entries.get(path), before), 'Foundation delta differs from actual parent tree');
        if (after) { entries.set(path, after); objects.add(after.object); }
        else entries.delete(path);
      }
      trees.set(revision, entries);
    }
    // Do not treat transport metadata as object existence/type evidence. The
    // same independent Git blob checks cover seeds and all added/changed IDs.
    verifyObjects([...objects]);
  }
}
