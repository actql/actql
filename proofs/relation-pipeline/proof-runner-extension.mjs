import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export const proofRunnerFiles = ['proofs/relation-chain/check.mjs',
  'proofs/relation-chain/retirement-check.mjs', 'proofs/bounded-session/proof-command.mjs'];
export const preservedProofInputs = ['proofs/bounded-session/Session.lean',
  'proofs/bounded-session/Claims.lean', 'proofs/relation-chain/Chain.lean',
  'proofs/relation-chain/Claims.lean', 'proofs/relation-chain/StopAccounting.lean',
  'proofs/relation-chain/StopClaims.lean', 'proofs/relation-chain/Retirement.lean',
  'proofs/relation-chain/RetirementClaims.lean', 'proofs/relation-chain/lean-toolchain'];

// The reviewed change is subprocess custody only. Compare the entire checker
// to its original bytes after these exact mechanical substitutions, retaining
// every model, typed claim, theorem inventory, Lean flag and axiom check.
export function custodyChecker(original) {
  const substitutions = [
    ["import { spawnSync } from 'node:child_process';",
      "import {runProofCommand} from '../bounded-session/proof-command.mjs';"],
    ["const version = spawnSync('lean', ['--short-version'], { cwd, encoding: 'utf8' });",
      "const version = await runProofCommand('lean', ['--short-version'], {cwd});\nif (version.error) throw version.error;"],
    ["const result = spawnSync('lean',", "const result = await runProofCommand('lean',"],
    ["cwd, encoding: 'utf8', input:", "cwd, input:"],
  ];
  for (const [before, after] of substitutions) {
    assert.equal(original.split(before).length, 2, 'Missing unique original checker boundary');
    original = original.replace(before, after);
  }
  return original;
}

export function checkProofRunnerExtension(root, extension, read) {
  assert.deepEqual(Object.keys(extension).sort(), ['files', 'parent', 'preserved', 'revision'].sort());
  assert.match(extension.revision, /^[a-f0-9]{40}$/);
  assert.match(extension.parent, /^[a-f0-9]{40}$/);
  const original = '977f59480e4761e654f6360a590caffb878b6899';
  assert.deepEqual(Object.keys(extension.files).sort(), [...proofRunnerFiles].sort());
  assert.deepEqual(Object.keys(extension.preserved).sort(), [...preservedProofInputs].sort());
  const git = args => {
    const result = spawnSync('git', args, {cwd: root});
    assert.equal(result.status, 0, 'Missing actual runner extension history');
    return result.stdout;
  };
  assert.equal(git(['show', '-s', '--format=%P', extension.revision]).toString().trim(), extension.parent);
  git(['merge-base', '--is-ancestor', extension.revision, 'HEAD']);
  git(['merge-base', '--is-ancestor', original, extension.parent]);
  const blob = (revision, path) => git(['show', `${revision}:${path}`]);
  for (const path of proofRunnerFiles) {
    const current = blob(extension.revision, path);
    assert.equal(hash(current), extension.files[path], 'Unrelated runner extension history');
    assert.equal(hash(read(path)), hash(current), 'Changed reviewed runner extension');
    if (path.endsWith('check.mjs')) assert.equal(current.toString(),
      custodyChecker(blob(original, path).toString()), 'Changed checker proof semantics');
  }
  for (const path of preservedProofInputs) {
    const originalBytes = blob(original, path);
    assert.equal(hash(originalBytes), extension.preserved[path], 'Changed original proof input pin');
    assert.equal(hash(blob(extension.revision, path)), hash(originalBytes), 'Changed runner proof input');
    assert.equal(hash(read(path)), hash(originalBytes), 'Changed current runner proof input');
  }
  // Only register the extra custody regression; retain the original tests and
  // their internal 60-second limits byte-for-byte.
  const testPath = 'proofs/relation-chain/proof-check.test.mjs';
  assert.equal(blob(extension.revision, testPath).toString(), blob(original, testPath).toString()
    .replace("import './mutation-retirement.test.mjs';",
      "import './mutation-retirement.test.mjs';\nimport '../bounded-session/proof-command.test.mjs';"));
}
