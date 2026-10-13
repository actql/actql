import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {createWorkersFiniteRuntime, workersFiniteArtifact} from './dist/workers_finite.js';
import {finiteOriginalMaterials} from '../../adapters/workers/finite-runtime-fixture.mjs';

import {exerciseWorkersFinitePackage} from '../../scripts/fixtures/workers-finite-package-acceptance.mjs';

test('finite package metadata describes every exact audited payload byte', () => {
  const bytes = readFileSync(new URL('./dist/workers_finite_payload.js', import.meta.url));
  assert.deepEqual(workersFiniteArtifact, {
    componentCid: 'sha256:' + createHash('sha256').update(bytes).digest('hex'),
    componentBytes: bytes.length,
  });
  assert.equal(Object.isFrozen(workersFiniteArtifact), true);
  assert.doesNotMatch(bytes.toString(), /workersFiniteFixture|workers_conformance/);
  const manifest = JSON.parse(readFileSync(new URL('./package.json', import.meta.url)));
  assert.equal(manifest.exports['./workers-finite'].default, './dist/workers_finite.js');
  assert.ok(manifest.files.includes('dist/workers_finite_payload.js'));
  assert.ok(manifest.files.includes('workers-finite.d.ts'));
});

test('finite package keeps original Run identity across a separate compiled link unit', async () => {
  for (const rows of [[], [{id: 3}, {id: null}, {id: 3}, {id: 1}]]) {
    const input = finiteOriginalMaterials({rows, nullable: true});
    const result = await exerciseWorkersFinitePackage(createWorkersFiniteRuntime, input);
    assert.deepEqual(result.rows, rows);
    assert.equal(result.measurement.rowCount, rows.length);
    assert.deepEqual(result.measurement.columnNullRows, [rows.length ? 1 : 0]);
  }
});

test('finite package does not accept a replacement runtime in authorization options', () => {
  const input = finiteOriginalMaterials();
  const assembly = createWorkersFiniteRuntime(0, input.configuration);
  assert.throws(() => assembly.createAuthorizationGate({runtime: {}}),
    /InvalidWorkersFiniteAuthorizationOptions/);
  assert.throws(() => createWorkersFiniteRuntime(0.5, input.configuration),
    /Invalid physical hash seed/);
  assert.equal(typeof assembly.core.remoteBundleControl.prepare, 'function');
});
