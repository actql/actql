// Test-harness provenance only; never an installed runtime or identity adapter.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {checkoutState} from './packed-client-packages.mjs';

const harnessChanges = new Set([
  'scripts/packed-package-boundaries.mjs',
  'scripts/packed-package-boundaries.test.mjs',
  'scripts/composite-release-source-qualification.mjs',
  'scripts/composite-release-source-qualification.test.mjs',
  'scripts/test-package-release-composite-vector.mjs',
]);

export function qualifyCompositeReleaseSource(root, artifactSourceSha) {
  assert.match(artifactSourceSha, /^[a-f0-9]{40}$/u);
  const source = checkoutState(root);
  assert(source.clean, 'Composite fixtures require clean committed source');
  execFileSync('git', ['--no-replace-objects', 'merge-base', '--is-ancestor',
    artifactSourceSha, source.revision], {cwd: root, stdio: 'pipe'});
  const changed = execFileSync('git', ['--no-replace-objects', 'diff',
    '--no-ext-diff', '--no-textconv', '--no-renames', '--name-only', '-z',
    artifactSourceSha, source.revision, '--'], {cwd: root, encoding: 'utf8'})
    .split('\0').filter(Boolean);
  assert(changed.every(path => harnessChanges.has(path)),
    'Retained Composite RC requires identical runtime, contracts, package, toolchain, fixture and independent oracle inputs');
  assert.deepEqual(checkoutState(root), source, 'Fixture source changed during qualification');
  return {artifactSourceSha, fixtureSourceSha: source.revision,
    runtimeSourceDelta: [], harnessOnlyChanges: changed};
}
