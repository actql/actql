// Read-only local comparison of the actual before/after workspace check.
// Run under scripts/local-checks-guard.mjs; this is not a CI acceptance receipt.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {pathToFileURL} from 'node:url';
import {join, resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const [directory, baseline, output] = process.argv.slice(2);
assert(directory && /^[0-9a-f]{40}$/.test(baseline) && output,
  'Usage: node profile.mjs <repository-root> <baseline-SHA> <new-output.json>');
const root = resolve(directory), sourcePath = 'proofs/relation-pipeline/workspaces.mjs';
const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const beforeBytes = execFileSync('git', ['show', `${baseline}:${sourcePath}`], {cwd: root});
let relocated = beforeBytes.toString('utf8');
// Only relocate the two relative imports. The baseline function body remains
// byte-identical; both implementations inspect the same candidate filesystem.
for (const input of ['scripts/owned-scratch.mjs', 'proofs/relation-pipeline/inventory.mjs']) {
  const specifier = input.startsWith('scripts/') ? '../../scripts/owned-scratch.mjs' : './inventory.mjs';
  const pattern = `from '${specifier}'`;
  assert.equal(relocated.split(pattern).length, 2);
  assert.equal(git(['diff', baseline, 'HEAD', '--', input]), '', 'Comparison dependency changed');
  relocated = relocated.replace(pattern, `from '${pathToFileURL(join(root, input)).href}'`);
}
const beforeModule = await import(`data:text/javascript;base64,${Buffer.from(relocated).toString('base64')}`);
const afterModule = await import(pathToFileURL(join(root, sourcePath)));
const checkers = {before: beforeModule.workspaceIdentity(root, 'normal'),
  after: afterModule.workspaceIdentity(root, 'normal')};
const expected = checkers.before.check();
for (let index = 0; index < 2; index++) for (const checker of Object.values(checkers)) {
  assert.deepEqual(checker.check(), expected);
}
const pairs = [];
for (let index = 0; index < 9; index++) {
  const pair = {order: index % 2 ? ['after', 'before'] : ['before', 'after']};
  for (const name of pair.order) {
    const began = performance.now();
    const actual = checkers[name].check();
    pair[name] = performance.now() - began;
    assert.deepEqual(actual, expected);
  }
  pairs.push(pair);
}
const lstatCalls = {}, original = fs.lstatSync;
let calls = 0;
fs.lstatSync = (...args) => { calls++; return original(...args); };
syncBuiltinESMExports();
try {
  for (const [name, checker] of Object.entries(checkers)) {
    calls = 0; assert.deepEqual(checker.check(), expected); lstatCalls[name] = calls;
  }
} finally { fs.lstatSync = original; syncBuiltinESMExports(); }
const result = {version: 'actql-local-workspace-cost-comparison/0.1',
  authority: 'local-filesystem-check-only', reuseAuthorized: false, netRunnerSavings: null,
  baseline, candidate: git(['rev-parse', 'HEAD']), sourcePath,
  sourceBytes: {before: hash(beforeBytes), after: hash(fs.readFileSync(join(root, sourcePath)))},
  node: process.version, platform: process.platform, architecture: process.arch,
  condition: 'Same candidate filesystem and process; two warm-ups per implementation; nine alternating-order pairs; no timed syscall instrumentation; separate untimed counts.',
  sourceDigest: expected.digest, sourceFiles: Object.keys(expected.sources).length,
  pairs, meanMilliseconds: Object.fromEntries(['before', 'after'].map(name =>
    [name, pairs.reduce((sum, pair) => sum + pair[name], 0) / pairs.length])), lstatCalls,
  unverified: ['Moon/compiler execution costs', 'whole mutation campaign', 'hosted runner savings', 'cross-revision evidence reuse']};
fs.writeFileSync(output, JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(result));
