import test from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkFoundation } from './history.mjs';

test('integrated foundation remains byte-pinned without rewriting the original experiment', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const baseline = JSON.parse(readFileSync(join(root, 'proofs/relation-pipeline/reuse-baseline.json')));
  assert.equal(baseline.originalExperiment.foundationRevision, '489f3c4ad38eece09de9674eae7a1b0ddeab1969');
  assert.equal(baseline.originalExperiment.verifiedRegistrationRevision, 'e73411cc068c853314b6a771dbd6b27680499115');
  assert.equal(Object.keys(baseline.common).length, 57);
  assert.equal(baseline.propertyGraphVerificationIntegration.unchangedCommonFiles, 56);
  checkFoundation(root);

  // Nested fixture remains under the same Git history, but owns its file copies.
  mkdirSync(join(root, '_build'), { recursive: true });
  const fixture = mkdtempSync(join(root, '_build/foundation-pin-'));
  try {
    for (const file of Object.keys(baseline.common)) {
      mkdirSync(dirname(join(fixture, file)), { recursive: true });
      copyFileSync(join(root, file), join(fixture, file));
    }
    const manifest = join(fixture, 'proofs/relation-pipeline/reuse-baseline.json');
    const integration = baseline.propertyGraphVerificationIntegration;
    const previous = { ...baseline, revision: integration.priorRevision,
      common: { ...baseline.common, [integration.path]: integration.priorDigest } };
    writeFileSync(manifest, JSON.stringify(previous));
    assert.throws(() => checkFoundation(fixture), /Changed common foundation package.json/);
    writeFileSync(manifest, JSON.stringify(baseline));
    assert.doesNotThrow(() => checkFoundation(fixture));
    writeFileSync(join(fixture, 'package.json'), `${readFileSync(join(fixture, 'package.json'), 'utf8')}\n`);
    assert.throws(() => checkFoundation(fixture), /Changed common foundation package.json/);
  } finally {
    rmSync(fixture, { recursive: true });
  }
});
