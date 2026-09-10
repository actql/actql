import assert from 'node:assert/strict';
import { test } from 'node:test';
import { checkDependencies, checkVersionTokens, loadDependencies } from './check-aoa-versions.mjs';
import { machineCid } from './actql-spec-family.mjs';

test('adopted AoA bodies match their exact pins', () => checkDependencies(loadDependencies()));

test('legacy contract and law versions are rejected while external versions are independent', () => {
  for (const prefix of ['aoa-kernel-laws/', 'aoa-rela-scalar-laws/', 'aoa-decimal-value/', 'aoa.rela.scalar.portability.v']) {
    for (const version of ['1', '1.0', '2.0', '3.0', '0.1.1']) {
      assert.throws(() => checkVersionTokens(prefix + version));
    }
    checkVersionTokens(prefix + '0.1');
  }
  checkVersionTokens('Unicode 16.0; YAML 1.2.2; IEEE 754; AoaMechanized.RelA.Select');
});

test('missing manifests and modified preimages cannot keep their old pins', () => {
  for (const key of ['kernel', 'pipeline', 'scalar', 'primitive']) {
    const missing = loadDependencies();
    delete missing.bodies[key];
    assert.throws(() => checkDependencies(missing));
    const changed = loadDependencies();
    changed.bodies[key].unexpected = true;
    assert.throws(() => checkDependencies(changed));
  }
});

test('renamed Effect law must be present even if the manifest pin is recomputed', () => {
  const value = loadDependencies();
  value.bodies.pipeline.laws = value.bodies.pipeline.laws.filter(law => law.law_id !== value.contract.effect_plan_law);
  value.contract.pipeline_law_manifest_cid = machineCid(value.bodies.pipeline);
  assert.throws(() => checkDependencies(value), /Missing Effect law/);
});
