// The owned scratch decision at process exit, in real child processes:
// success removes, a failure keeps, a refused removal is a distinct failure,
// preservation keeps, and an unconfirmed end keeps.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmodSync, existsSync, mkdtempSync, rmSync, writeFileSync} from
  'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {pathToFileURL} from 'node:url';

const helper = pathToFileURL(new URL('./owned-scratch.mjs', import.meta.url)
  .pathname).href;

// Run a child that creates an owned scratch in `parent`, writes a tarball and
// a nested file, then does `body` (JavaScript source using `scratch`).
function child(parent, body, env = {}) {
  const source = `
import {mkdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {createOwnedScratch} from ${JSON.stringify(helper)};
const scratch = await createOwnedScratch({parent: ${JSON.stringify(parent)},
  prefix: 'owned-', label: 'probe', digests: () => ['probe.tgz']});
console.log('PATH=' + scratch.path);
writeFileSync(join(scratch.path, 'probe.tgz'), 'tarball');
mkdirSync(join(scratch.path, 'nested'));
writeFileSync(join(scratch.path, 'nested', 'state'), 'x'.repeat(1000));
${body}
`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e',
    source], {encoding: 'utf8', env: {...process.env,
    ACTQL_TEST_PRESERVE_SCRATCH: '', ...env}});
  const path = /PATH=(.*)/u.exec(result.stdout)?.[1];
  return {...result, path};
}

function parent(t) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-owned-scratch-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  return directory;
}

test('a passed test removes its scratch and reports what it removed', t => {
  const result = child(parent(t), 'scratch.passed();');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(result.path), false);
  assert.match(result.stdout, /probe: probe\.tgz sha256:[0-9a-f]{64}/u);
  assert.match(result.stdout,
    /probe: removed .* \(2 files, 0\.0 MiB before removal\)/u);
});

test('a failed test keeps its scratch and its own failure', t => {
  const result = child(parent(t), `
scratch.passed();
throw new Error('original test failure');`);
  assert.notEqual(result.status, 0);
  assert.equal(existsSync(result.path), true);
  assert.match(result.stderr, /original test failure/u);
  assert.match(result.stderr, /probe: test failed; scratch kept: /u);
  assert.match(result.stderr, /rm -rf -- '.*owned-.*'/u);
  assert.doesNotMatch(result.stderr, /cleanup failed/u);
});

test('a refused removal fails a passed test separately', t => {
  const result = child(parent(t), `
import {chmodSync} from 'node:fs';
chmodSync(join(scratch.path, 'nested'), 0o500);
scratch.passed();`);
  // The removal must actually have been refused; a privileged user would
  // remove the directory anyway, which proves nothing.
  if (existsSync(result.path) === false) {
    t.skip('this user can remove a read-only directory\'s entries');
    return;
  }
  try {
    assert.equal(existsSync(join(result.path, 'nested', 'state')), true);
    assert.equal(result.status, 2, result.stderr);
    assert.match(result.stderr, /probe: test passed; cleanup failed: /u);
    assert.match(result.stderr, /probe: cleanup failed; scratch kept: /u);
    assert.match(result.stderr, /rm -rf -- '/u);
  } finally {
    chmodSync(join(result.path, 'nested'), 0o700);
  }
});

test('preservation keeps a passed test\'s scratch', t => {
  const result = child(parent(t), 'scratch.passed();',
    {ACTQL_TEST_PRESERVE_SCRATCH: '1'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(result.path), true);
  assert.match(result.stderr, /preservation requested; scratch kept: /u);
});

test('an end without confirmation keeps the scratch and fails', t => {
  const result = child(parent(t), '');
  assert.equal(result.status, 1);
  assert.equal(existsSync(result.path), true);
  assert.match(result.stderr, /did not confirm that its processes ended/u);
});

test('nothing outside the scratch is removed through a link', t => {
  const directory = parent(t);
  const outside = join(directory, 'outside');
  writeFileSync(outside, 'kept');
  const result = child(directory, `
import {symlinkSync} from 'node:fs';
symlinkSync(${JSON.stringify(outside)}, join(scratch.path, 'link'));
scratch.passed();`);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(result.path), false);
  assert.equal(existsSync(outside), true);
});
