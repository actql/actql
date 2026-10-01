import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {closeSync, existsSync, lstatSync, mkdirSync, mkdtempSync, openSync,
  opendirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {formatInventory, inventoryWorktrees, parseArgs, parseLsof} from './worktree-inventory.mjs';

const script = fileURLToPath(new URL('./worktree-inventory.mjs', import.meta.url));
const noProcesses = {status: 0, stdout: '', stderr: ''};
const runWithLsof = response => (program, args, options) => {
  assert.ok(['git', 'lsof'].includes(program), `unexpected command: ${program}`);
  assert.ok(!options.shell);
  return program === 'lsof' ? (args[0] === '-h' ?
    {status: 0, stdout: 'lsof help -F', stderr: ''} : response) : spawnSync(program, args, options);
};
const inventory = (roots, options = {}) => inventoryWorktrees(roots,
  {run: runWithLsof(noProcesses), ...options});
function git(root, ...args) {
  const result = spawnSync('git', ['-C', root, ...args], {encoding: 'utf8',
    env: {...process.env, GIT_CONFIG_NOSYSTEM: '1'}});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}
function fixture(t) {
  const parent = mkdtempSync(join(tmpdir(), 'actql inventory '));
  // Only this test's newly created fixtures are removed, never scanned user roots.
  t.after(() => rmSync(parent, {recursive: true, force: true}));
  function root(name) {
    const path = join(parent, name);
    mkdirSync(path);
    git(path, 'init', '-q');
    writeFileSync(join(path, '.gitignore'), '_build/\nnode_modules/\ndist/\n');
    writeFileSync(join(path, 'README.md'), 'source\n');
    git(path, 'add', '.');
    git(path, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
      'commit', '-qm', 'fixture');
    return path;
  }
  return {parent, root};
}
function put(root, path, body = 'fixture') {
  const target = join(root, path);
  mkdirSync(join(target, '..'), {recursive: true});
  writeFileSync(target, body);
  return target;
}
const candidate = (report, path) => report.candidates.find(item => item.path === path);

test('borrowed dependencies resolve nested component links across explicit roots with spaces', t => {
  const f = fixture(t);
  const owner = f.root('owner worktree');
  const borrower = f.root('borrower worktree');
  put(owner, '_build/node_modules/package/index.js');
  symlinkSync('_build/node_modules', join(owner, 'borrowed-link'));
  symlinkSync(join(owner, 'borrowed-link'), join(borrower, 'node_modules'));
  const report = inventory([owner, borrower]);
  const output = candidate(report, join(owner, '_build'));
  assert.ok(output);
  assert.equal(output.references.find(item => item.root === borrower).realPath,
    join(owner, '_build/node_modules'));
  assert.equal(output.references.find(item => item.root === borrower).borrowed, true);
  assert.equal(output.review, 'referenced-by-symlink');
  assert.equal(report.dependencyLinks.find(item => item.root === borrower).status, 'resolved');
  assert.equal(report.dependencyLinks.find(item => item.root === borrower).insideDeclaredScope, true);
});

test('nested package links are observed but ordinary dependency trees are bounded', t => {
  const f = fixture(t);
  const owner = f.root('owner');
  const borrower = f.root('borrower');
  put(owner, '_build/package/out.js');
  put(borrower, 'node_modules/deep/lib/further/index.js');
  mkdirSync(join(borrower, 'node_modules/@scope'), {recursive: true});
  symlinkSync(join(owner, '_build/package'), join(borrower, 'node_modules/@scope/pkg'));
  const report = inventory([owner, borrower]);
  assert.equal(candidate(report, join(owner, '_build')).references.length, 1);
  assert.ok(report.exclusions.some(item => item.path.endsWith('deep/lib') && /dependency depth/u.test(item.reason)));
  assert.equal(candidate(report, join(borrower, 'node_modules')).size.status, 'partial');
  assert.ok(!report.protectedPaths.some(item => item.path.endsWith('further/index.js')));
});

test('link cycles and broken links are unknown and never traversed', t => {
  const f = fixture(t);
  const root = f.root('cycle');
  symlinkSync('link-b', join(root, 'link-a'));
  symlinkSync('link-a', join(root, 'link-b'));
  symlinkSync('missing', join(root, 'node_modules'));
  const report = inventory([root]);
  assert.equal(report.dependencyLinks.length, 3);
  assert.ok(report.dependencyLinks.every(item => item.status === 'unknown' && item.realPath === null));
  assert.ok(report.failedChecks.some(item => item.reason === 'ELOOP'));
  assert.ok(report.failedChecks.some(item => item.reason === 'ENOENT'));
});

test('active file and cwd references remain visible even with a failed lsof snapshot', t => {
  const f = fixture(t);
  const root = f.root('active tree');
  const output = join(root, '_build');
  const file = put(root, '_build/active file.js');
  const report = inventory([root], {run: runWithLsof({status: 1,
    stdout: `p123\0\nfcwd\0n${output}\0\nf4r\0n${file}\0\n`,
    stderr: 'permission denied'})});
  assert.equal(candidate(report, output).usage, 'active');
  assert.equal(candidate(report, output).liveReferences.length, 2);
  assert.equal(report.processVisibility.status, 'unknown');
  assert.equal(report.processVisibility.snapshot, 'incomplete');
  assert.ok(report.failedChecks.some(item => item.check === 'process-visibility'));
});

test('missing commands, permission failures and timeouts never imply unused', t => {
  const f = fixture(t);
  const root = f.root('unknown');
  put(root, '_build/output.js');
  for (const code of ['ENOENT', 'EACCES', 'ETIMEDOUT', 'ENOBUFS']) {
    const report = inventory([root], {run: runWithLsof({status: null,
      error: Object.assign(new Error(code), {code}), stdout: '', stderr: ''})});
    assert.equal(candidate(report, join(root, '_build')).usage, 'unknown');
    assert.ok(report.failedChecks.some(item => item.reason === code));
  }
  const unsupported = inventory([root], {platform: 'win32'});
  assert.equal(unsupported.processVisibility.status, 'unknown');
  assert.ok(unsupported.failedChecks.some(item => /unsupported platform/u.test(item.reason)));
  const visibleEmpty = inventory([root]);
  assert.equal(candidate(visibleEmpty, join(root, '_build')).usage, 'unknown');
  assert.equal(visibleEmpty.processVisibility.snapshot, 'observed');
});

test('dirty, untracked and tracked output-looking paths stay protected', t => {
  const f = fixture(t);
  const root = f.root('dirty');
  put(root, 'dist/tracked.js');
  git(root, 'add', '-f', 'dist/tracked.js');
  git(root, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-qm', 'tracked output-looking source');
  put(root, 'dist/tracked.js', 'dirty');
  put(root, 'new source.txt');
  put(root, 'target/untracked.js');
  const report = inventory([root]);
  assert.equal(candidate(report, join(root, 'dist')), undefined);
  assert.equal(candidate(report, join(root, 'target')), undefined);
  assert.ok(report.protectedPaths.some(item => item.path === join(root, 'dist') && item.kind === 'dirty-or-untracked'));
  assert.ok(report.roots[0].git.changes.some(item => item.path === 'new source.txt' && item.status === '??'));
  assert.ok(report.roots[0].git.trackedPaths.includes('dist/tracked.js'));
});

test('credentials, evidence, databases, journals and recovery records protect their parent output', t => {
  const f = fixture(t);
  const root = f.root('protected');
  for (const path of ['_build/.env', '_build/credentials/token', '_build/evidence/report.json',
    '_build/state.sqlite', '_build/state.sqlite-wal', '_build/journals/record',
    '_build/recovery/checkpoint', 'src/journal/module.mbt']) put(root, path);
  const seen = [];
  const io = {lstatSync, realpathSync, opendirSync(path) { seen.push(path); return opendirSync(path); }};
  const report = inventory([root], {io});
  assert.equal(candidate(report, join(root, '_build')), undefined);
  assert.ok(report.protectedOutputs.find(item => item.path === join(root, '_build')));
  for (const kind of ['credentials', 'evidence', 'database', 'runtime-journal', 'recovery']) {
    assert.ok(report.protectedPaths.some(item => item.kind === kind), kind);
  }
  assert.ok(!seen.includes(join(root, '_build/credentials')));
  assert.ok(!seen.includes(join(root, '_build/journals')));
  assert.ok(report.protectedPaths.some(item => item.path === join(root, 'src/journal') && item.kind !== 'runtime-journal'));
});

test('directory permission failure is recorded and sizes become lower bounds', t => {
  const f = fixture(t);
  const root = f.root('permission');
  put(root, '_build/unreadable/payload');
  const io = {lstatSync, realpathSync, opendirSync(path) {
    if (path.endsWith('unreadable')) throw Object.assign(new Error(), {code: 'EACCES'});
    return opendirSync(path);
  }};
  const report = inventory([root], {io});
  assert.equal(candidate(report, join(root, '_build')).size.status, 'partial');
  assert.ok(report.failedChecks.some(item => item.reason === 'EACCES'));
});

test('allocated size counts blocks rather than logical sparse length', t => {
  const f = fixture(t);
  const root = f.root('allocated');
  put(root, '_build/file', 'x'.repeat(10000));
  const expected = (lstatSync(join(root, '_build')).blocks +
    lstatSync(join(root, '_build/file')).blocks) * 512;
  const report = inventory([root]);
  assert.equal(candidate(report, join(root, '_build')).size.allocatedBytes, expected);
  assert.equal(candidate(report, join(root, '_build')).size.status, 'observed');
});

test('max entries/depth expose excluded work and do not follow external targets', t => {
  const f = fixture(t);
  const root = f.root('limits');
  const outside = join(f.parent, 'outside');
  mkdirSync(outside);
  put(outside, 'payload', 'outside');
  symlinkSync(outside, join(root, 'node_modules'));
  put(root, '_build/a/b/c/data');
  const bounded = inventory([root], {limits: {depth: 2}});
  assert.ok(bounded.exclusions.some(item => item.reason === 'scan depth limit'));
  const link = bounded.dependencyLinks.find(item => item.path === join(root, 'node_modules'));
  assert.equal(link.insideDeclaredScope, false);
  assert.ok(!bounded.protectedPaths.some(item => item.path === join(outside, 'payload')));
  const tiny = inventory([root], {limits: {entries: 2}});
  assert.ok(tiny.scannedEntries <= 2);
  assert.ok(tiny.exclusions.some(item => /global entry limit/u.test(item.reason)));
});

test('Git failure retains the failed check and unknown protection state', t => {
  const f = fixture(t);
  const root = f.root('git-failure');
  put(root, '_build/out');
  const report = inventory([root], {run(program) {
    return program === 'git' ? {status: 128, stdout: '', stderr: 'fatal'} : noProcesses;
  }});
  assert.equal(report.roots[0].git.status, 'unknown');
  assert.equal(candidate(report, join(root, '_build')).gitStatus, 'unknown');
  assert.ok(report.failedChecks.some(item => item.check === 'git-root'));
});

test('Git guards do not refresh the index or invoke configured fsmonitor', t => {
  const f = fixture(t);
  const root = f.root('read-only');
  put(root, '_build/payload');
  const sentinel = join(root, 'fsmonitor-was-called');
  git(root, 'config', 'core.fsmonitor', `touch '${sentinel}'`);
  const beforeStatus = git(root, '-c', 'core.fsmonitor=false', 'status', '--porcelain=v1');
  const beforeIndex = readFileSync(join(root, '.git/index'));
  const beforeMtime = lstatSync(join(root, '.git/index')).mtimeMs;
  const report = inventory([root]);
  assert.equal(report.roots[0].git.status, 'observed');
  assert.equal(existsSync(sentinel), false);
  assert.deepEqual(readFileSync(join(root, '.git/index')), beforeIndex);
  assert.equal(lstatSync(join(root, '.git/index')).mtimeMs, beforeMtime);
  assert.equal(git(root, '-c', 'core.fsmonitor=false', 'status', '--porcelain=v1'), beforeStatus);
  assert.equal(readFileSync(join(root, '_build/payload'), 'utf8'), 'fixture');
});

test('readable and JSON CLI output require explicit roots and retain unknowns', t => {
  const f = fixture(t);
  const root = f.root('cli spaces');
  put(root, '_build/out');
  const missing = spawnSync(process.execPath, [script], {encoding: 'utf8'});
  assert.equal(missing.status, 2);
  const cli = spawnSync(process.execPath, [script, '--json', '--', root], {encoding: 'utf8'});
  assert.equal(cli.status, 0, cli.stderr);
  const parsed = JSON.parse(cli.stdout);
  assert.deepEqual(parsed.requestedRoots, [root]);
  assert.ok(parsed.timestamp);
  assert.ok(parsed.limits);
  const text = formatInventory(parsed);
  for (const section of ['Largest regenerable-output', 'Protected paths',
    'Dependency/symbolic links', 'Live file/cwd', 'Exclusions', 'Failed checks']) assert.ok(text.includes(section));
  assert.match(text, /usage unknown/u);
  assert.deepEqual(parseArgs(['--max-depth', '3', '--', root]).options.limits, {depth: 3});
  assert.throws(() => parseArgs(['--delete']));
  assert.throws(() => parseArgs(['--max-depth', '-1']));
});

test('real lsof observes this test process holding a file in a candidate', t => {
  if (!['linux', 'darwin'].includes(process.platform)) return t.skip('lsof platform unavailable');
  const available = spawnSync('lsof', ['-v'], {encoding: 'utf8'});
  if (available.error?.code === 'ENOENT') return t.skip('lsof unavailable; injected command tests still run');
  const f = fixture(t);
  const root = f.root('real live file');
  const path = put(root, '_build/open file');
  const fd = openSync(path, 'r');
  try {
    const report = inventoryWorktrees([root]);
    const output = candidate(report, join(root, '_build'));
    assert.equal(output.usage, 'active', JSON.stringify(report.failedChecks));
    assert.ok(output.liveReferences.some(item => item.pid === String(process.pid) && item.path === path));
  } finally { closeSync(fd); }
});

test('lsof parsing handles NUL fields, spaces and deleted-file observations', () => {
  assert.deepEqual(parseLsof('p12\0\nfcwd\0n/tmp/tree with space\0\nf3r\0n/tmp/out (deleted)\0\n'), [
    {pid: '12', descriptor: 'cwd', path: '/tmp/tree with space', deleted: false},
    {pid: '12', descriptor: '3r', path: '/tmp/out', deleted: true},
  ]);
});

test('tracked and nested compiler journal modules are source, not runtime journals', t => {
  const f = fixture(t);
  const root = f.root('compiler');
  put(root, 'packages/compiler/journal/module.mbt');
  put(root, 'packages/other/src/journal/module.mbt');
  git(root, 'add', 'packages/compiler/journal/module.mbt');
  const report = inventory([root]);
  for (const path of ['packages/compiler/journal', 'packages/other/src/journal']) {
    const entry = report.protectedPaths.find(item => item.path === join(root, path));
    assert.ok(entry);
    assert.notEqual(entry.kind, 'runtime-journal');
  }
});

test('lsof cache writes and network name/port lookups are disabled', t => {
  const f = fixture(t);
  const root = f.root('lsof-options');
  let observed = false;
  inventory([root], {run(program, args, options) {
    if (program !== 'lsof') return spawnSync(program, args, options);
    if (args[0] === '-h') return {status: 0, stdout: 'lsof -D D -F fields', stderr: ''};
    assert.deepEqual(args, ['-Di', '-nP', '-l', '-M', '-F0pfn']);
    observed = true;
    return noProcesses;
  }});
  assert.equal(observed, true);
});


test('Git-linked worktrees stay protected until scanned as explicit roots', t => {
  const f = fixture(t);
  const root = f.root('parent');
  const nested = join(root, 'nested');
  mkdirSync(nested);
  git(nested, 'init', '-q');
  put(nested, '.gitignore', '_build/\n');
  put(nested, 'source', 'source');
  git(nested, 'add', '.');
  git(nested, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-qm', 'nested');
  git(root, 'add', 'nested');
  put(nested, '_build/output');
  const report = inventory([root]);
  assert.ok(!report.candidates.some(item => item.path === join(nested, '_build')));
  assert.ok(report.exclusions.some(item => item.path === nested && /gitlink/u.test(item.reason)));
  assert.ok(candidate(inventory([root, nested]), join(nested, '_build')));
});
