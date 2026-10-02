import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { checkFoundation, currentFoundation } from './history.mjs';
import { hash } from './inventory.mjs';

test('current Graph integration preserves frozen evidence and independently declares its actual foundation', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const path = 'proofs/relation-pipeline/reuse-baseline.json';
  const historical = execFileSync('git',
    ['show', `0aa3bc921362b53536d5bf9d541a889e09ccc24b:${path}`], { cwd: root });
  assert.deepEqual(readFileSync(`${root}/${path}`), historical);
  const baseline = checkFoundation(root);
  assert.equal(baseline.originalExperiment.foundationRevision, '489f3c4ad38eece09de9674eae7a1b0ddeab1969');
  assert.equal(baseline.originalExperiment.verifiedRegistrationRevision, 'e73411cc068c853314b6a771dbd6b27680499115');
  assert.equal(Object.keys(baseline.common).length, 57);
  const current = currentFoundation(root);
  const head = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  assert.equal(current.sourceRevision, head);
  const registration = current.files.find(file => file.path === 'package.json');
  assert(registration, 'Missing current verification registration');
  assert.equal(registration.digest, hash(readFileSync(`${root}/package.json`)));
  // Negative provenance cases belong to the real-Git foundation/history tests:
  // they retain immutable bytes, exact parents, missing declarations and guards.
  // A directory of copied files is not a substitute Git foundation owner.
});
