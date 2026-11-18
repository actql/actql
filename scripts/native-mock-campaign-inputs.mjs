// Private same-process Native Mock admission inputs. This is never a portable
// receipt, a Source-check replacement or permission to change the candidate.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {closeSync, constants, fstatSync, lstatSync, openSync, readFileSync, readdirSync, readlinkSync, realpathSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';

// The campaign already has a finite Source and dependency installation. Refuse
// unknown/oversized subjects instead of trusting partial discovery or stat-only
// observations. Bounds do not admit new product inputs.
const MAX_FILES = 200000, MAX_BYTES = 2 * 1024 ** 3;
function describe(repository, controller, files) {
  const selected = new Map(), directories = new Set();
  const archives = new Set(files.filter(path => path.endsWith('.tgz')).map(path => resolve(path)));
  let total = 0;
  const visit = path => {
    path = resolve(path);
    if (selected.has(path)) return;
    assert(selected.size < MAX_FILES, 'Native Mock campaign input inventory exceeds its bound');
    const before = lstatSync(path, {bigint: true});
    const identity = {resolvedPath: realpathSync(path), dev: String(before.dev), ino: String(before.ino), mode: String(before.mode)};
    if (before.isSymbolicLink()) {
      const target = realpathSync(path), link = readlinkSync(path);
      selected.set(path, {...identity, link, target});
      visit(target);
    } else if (before.isDirectory()) {
      selected.set(path, identity);
      const original = realpathSync(path);
      // Shared workspace-package aliases may lead back to a directory already
      // visited. Its original inventory is still checked once, not discarded.
      if (!directories.has(original)) {
        directories.add(original);
        for (const name of readdirSync(path).sort()) visit(join(path, name));
      }
    } else {
      assert(before.isFile(), 'Non-regular Native Mock campaign input');
      assert(before.size <= 512n * 1024n ** 2n);
      total += Number(before.size);
      assert(total <= MAX_BYTES, 'Native Mock campaign input bytes exceed their bound');
      const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
      try {
        const opened = fstatSync(fd, {bigint: true}), bytes = readFileSync(fd), after = fstatSync(fd, {bigint: true});
        const named = lstatSync(path, {bigint: true});
        for (const key of ['dev', 'ino', 'size', 'mode', 'mtimeNs', 'ctimeNs']) {
          assert.equal(opened[key], before[key]); assert.equal(after[key], opened[key]);
          assert.equal(named[key], opened[key]);
        }
        assert.equal(BigInt(bytes.length), before.size);
        selected.set(path, {...identity, bytes: bytes.length,
          sha256: createHash('sha256').update(bytes).digest('hex'),
          ...(archives.has(path) ? {integrity: 'sha512-' + createHash('sha512').update(bytes).digest('base64')} : {})});
      } finally {closeSync(fd);}
    }
  };
  // Include discovery inputs, not only the previously discovered module list.
  // Git's nonignored untracked list makes additions/removals explicit too.
  for (const root of new Set([realpathSync(repository), realpathSync(controller)])) {
    const paths = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
      {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 ** 2}).split('\0').filter(Boolean);
    for (const path of paths) visit(join(root, path));
  }
  // Inspect the actual loaded controller's dependency installation, including
  // package metadata, resolution links and complete target inventories. Do not
  // silently omit workspace links or mutable dependency code.
  visit(join(controller, 'node_modules'));
  visit(process.execPath);
  for (const command of ['git', 'tar', 'npm']) {
    const path = execFileSync('/usr/bin/which', [command], {encoding: 'utf8'}).trim();
    assert(path && !path.includes('\n'), 'Unresolved Native Mock campaign tool');
    visit(path);
    if (command === 'npm') {
      // npm's fresh process must still use this selected tool installation.
      // Its CLI and resolved private dependencies are outside root node_modules.
      const original = realpathSync(path);
      if (original.endsWith('/bin/npm-cli.js')) visit(dirname(dirname(original)));
    }
  }
  for (const path of files) visit(path);
  return [...selected].sort(([a], [b]) => a.localeCompare(b));
}

export function retainNativeMockCampaignInputs({repository, controller, files}) {
  assert(!process.env.NODE_OPTIONS && !process.env.NODE_PATH,
    'Native Mock admission reuse requires the ordinary Node loader');
  assert(process.execArgv.every(arg => !/loader|import|require|eval|inspect/u.test(arg)),
    'Native Mock admission reuse cannot authenticate a custom Node loader');
  const node = {execPath: process.execPath, version: process.version,
    searchPath: process.env.PATH, options: process.env.NODE_OPTIONS, path: process.env.NODE_PATH, execArgv: [...process.execArgv]};
  const original = describe(repository, controller, files);
  // Only this original lexical operation consumes the retained observations.
  // JSON/DATA descriptors cannot supply another admission or select new files.
  return () => {
    assert.deepEqual({execPath: process.execPath, version: process.version,
      searchPath: process.env.PATH, options: process.env.NODE_OPTIONS, path: process.env.NODE_PATH, execArgv: [...process.execArgv]}, node,
    'Native Mock controller admission changed');
    assert.deepEqual(describe(repository, controller, files), original,
      'Native Mock fixed candidate Source, archive, controller or dependency changed');
  };
}
