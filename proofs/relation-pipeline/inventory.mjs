import { readFileSync, readdirSync, lstatSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import {checkProofRunnerExtension} from './proof-runner-extension.mjs';
export const hash = value => createHash('sha256').update(value).digest('hex');
export const snapshotDirectories = Object.freeze(['src', 'vendor', 'proofs/bounded-session', 'proofs/relation-chain', 'proofs/relation-capacity', 'proofs/relation-pipeline']);
export const snapshotFiles = Object.freeze(['scripts/owned-scratch.mjs', 'scripts/native-cxx-link-driver.sh', 'scripts/ar', 'toolchain.json', 'moon.mod', 'package.json', 'package-lock.json', '.github/workflows/ci.yml', 'docs/spec/language.md', 'docs/spec/execution.md']);
function files(path) {
  return readdirSync(path, { withFileTypes: true }).flatMap(e => e.isDirectory()
    ? files(join(path, e.name)) : e.isFile() ? [join(path, e.name)] : []);
}
export function snapshot(root) {
  const paths = snapshotDirectories
    .flatMap(p => files(join(root, p)))
    .concat(snapshotFiles.map(p => join(root, p)))
    .filter(p => relative(root, p) !== 'src/query_integration/relation_pipeline_batch_wbtest.mbt').sort();
  const sources = Object.fromEntries(paths.map(p => [relative(root, p), hash(readFileSync(p))]));
  return { sources, digest: hash(JSON.stringify(sources)) };
}
// Bind current evidence to actual tracked HEAD inputs. No ancestor walk or
// per-commit declaration is needed; shallow checkouts are sufficient.
export function checkCurrentSource(root) {
  const inputs = [...snapshotDirectories, ...snapshotFiles,
    ':(exclude)src/query_integration/relation_pipeline_batch_wbtest.mbt'];
  const git = args => spawnSync('git', ['--no-replace-objects', ...args],
    {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const head = git(['rev-parse', '--verify', 'HEAD^{commit}']);
  assert.equal(head.status, 0, 'Missing current source commit');
  const difference = git(['diff', '--quiet', 'HEAD', '--', ...inputs]);
  assert.equal(difference.status, 0, 'Current proof inputs differ from tested HEAD');
  const untracked = git(['ls-files', '--others', '--', ...inputs]);
  assert.equal(untracked.status, 0, 'Cannot inspect current source inputs');
  assert.equal(untracked.stdout, '', 'Untracked current proof inputs');
  // Index flags cannot establish the bytes that the runner actually reads.
  // Bind only this HEAD's regular inputs; no historical declarations are used.
  const tree = git(['ls-tree', '-rtz', head.stdout.trim()]);
  assert.equal(tree.status, 0, 'Cannot inspect current source tree');
  const selected = [...snapshotDirectories, ...snapshotFiles];
  for (const entry of tree.stdout.split('\0').filter(Boolean)) {
    const match = /^(\d+) (\S+) ([0-9a-f]+)\t([\s\S]+)$/.exec(entry);
    assert(match, 'Invalid current source tree entry');
    const [, mode, type, object, path] = match;
    if (path === 'src/query_integration/relation_pipeline_batch_wbtest.mbt') continue;
    if (!selected.some(input => path === input || path.startsWith(input + '/') ||
        input.startsWith(path + '/'))) continue;
    const file = join(root, path), stat = lstatSync(file);
    if (type === 'tree') {
      assert(!snapshotFiles.includes(path) && stat.isDirectory() && !stat.isSymbolicLink(),
        `Non-regular current proof input directory: ${path}`);
      continue;
    }
    assert(!snapshotDirectories.includes(path) &&
      !selected.some(input => input.startsWith(path + '/')),
    `Non-regular current proof input directory: ${path}`);
    assert(type === 'blob' && ['100644', '100755'].includes(mode),
      `Non-regular current proof input: ${path}`);
    assert(stat.isFile() && !stat.isSymbolicLink(), `Non-regular current proof input: ${path}`);
    assert.equal(Boolean(stat.mode & 0o111), mode === '100755', `Current proof input mode: ${path}`);
    const bytes = readFileSync(file);
    const actual = createHash(object.length === 40 ? 'sha1' : 'sha256')
      .update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
    assert.equal(actual, object, `Current proof inputs differ from tested HEAD: ${path}`);
  }
  return head.stdout.trim();
}
export function checkBaseline(root, {read = path => readFileSync(join(root, path))} = {}) {
  const baseline = JSON.parse(read('proofs/relation-pipeline/baseline.json'));
  const extension = baseline.modelExtension;
  const checker = 'proofs/relation-chain/check.mjs';
  assert(extension && extension.checker === checker, 'Missing reviewed model extension');
  assert.deepEqual(Object.keys(baseline.unchangedCommon).sort(), [
    'proofs/bounded-session/Session.lean', 'proofs/bounded-session/Claims.lean',
    'proofs/bounded-session/check.mjs', 'proofs/relation-chain/Chain.lean',
    'proofs/relation-chain/Claims.lean', checker,
    'src/bounded_execution/session_contract_wbtest.mbt',
    'src/connectors/local/bounded_session_contract_wbtest.mbt',
  ].sort(), 'Incomplete original common model inputs');
  assert.deepEqual(Object.keys(extension.files).sort(), [checker,
    'proofs/relation-chain/StopAccounting.lean', 'proofs/relation-chain/StopClaims.lean'].sort(),
    'Incomplete or unrelated model extension');
  assert.deepEqual(extension.observation, {session: 14, chain: 22, stopAndPause: 18, total: 54},
    'Unreviewed model extension inventory');
  assert.equal(extension.priorDigest, baseline.unchangedCommon[checker], 'Changed historical checker binding');
  const blob = (revision, path) => {
    const result = spawnSync('git', ['show', `${revision}:${path}`], {cwd: root});
    assert.equal(result.status, 0, 'Missing reviewed model history');
    return result.stdout;
  };
  assert.equal(hash(blob(baseline.revision, checker)), extension.priorDigest, 'Changed historical checker bytes');
  for (const [path, expected] of Object.entries(extension.files)) {
    assert.equal(hash(blob(extension.revision, path)), expected, 'Unrelated model extension history');
    const currentExpected = path === checker && baseline.runnerExtension
      ? baseline.runnerExtension.files[checker] : expected;
    assert.equal(hash(read(path)), currentExpected, `Changed reviewed model extension: ${path}`);
  }
  for (const [path, expected] of Object.entries(baseline.unchangedCommon)) {
    assert.equal(hash(blob(baseline.revision, path)), expected, `Changed original common model history: ${path}`);
    if (path !== checker && hash(read(path)) !== expected) throw new Error(`Changed common proof/history: ${path}`);
  }
  if (baseline.runnerExtension) checkProofRunnerExtension(root, baseline.runnerExtension, read);
  for (const item of baseline.existingGroup) {
    if (!read(item.path).toString('utf8').includes(`test "${item.test}"`)) throw new Error(`Missing retained fixture ${item.test}`);
  }
  return baseline;
}
