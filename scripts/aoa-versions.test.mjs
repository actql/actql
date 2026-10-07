import assert from 'node:assert/strict';
import { test } from 'node:test';
import { checkDependencies, checkVersionTokens, loadDependencies } from './check-aoa-versions.mjs';
import { machineCid } from './actql-spec-family.mjs';
import { readFileSync } from 'node:fs';

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
  for (const key of ['kernel', 'pipeline', 'scalar', 'primitive', 'vector', 'graph', 'graphIdentity', 'graph']) {
    const missing = loadDependencies();
    delete missing.bodies[key];
    assert.throws(() => checkDependencies(missing));
    const changed = loadDependencies();
    changed.bodies[key].unexpected = true;
    assert.throws(() => checkDependencies(changed));
  }
});

test('sole Graph contract implementation pins the owned Graph law without a legacy fallback', () => {
  const {contract} = loadDependencies();
  const implementation = readFileSync(new URL('../src/graph_contract/contract.mbt', import.meta.url), 'utf8');
  assert.match(implementation, /pub fn admit_graph\(\s*graph : @carrier\.Graph,\s*limits : Limits,?\s*\) -> Result\[CheckedContract, Issue\] \{\s*admit\(@carrier\.graph_carrier\(graph\), limits\)\s*\}/);
  const definitionImplementation = readFileSync(new URL('../src/graph_contract/definition_contract.mbt', import.meta.url), 'utf8');
  const law = definitionImplementation.match(/pub fn law_cid\(\) -> String \{\s*"([^"\n]+)"\s*\}/);
  assert.equal(law?.[1], contract.graph_law_manifest_cid, 'the Graph law owner returns the exact current pin');
  for (const source of [implementation, definitionImplementation]) {
    assert.doesNotMatch(source, /\b(?:property_law_cid|admit_property_graph)\b/);
    assert.ok(!source.includes(contract.sga_identity_law_manifest_cid));
  }
  assert.notEqual(contract.graph_law_manifest_cid, contract.sga_identity_law_manifest_cid);
});

test('renamed Effect law must be present even if the manifest pin is recomputed', () => {
  const value = loadDependencies();
  value.bodies.pipeline.laws = value.bodies.pipeline.laws.filter(law => law.law_id !== value.contract.effect_plan_law);
  value.contract.pipeline_law_manifest_cid = machineCid(value.bodies.pipeline);
  assert.throws(() => checkDependencies(value), /Missing Effect law/);
});

// Historical manifests are preserved as evidence of a different contract,
// never re-pinned or interpreted as the current value-preservation law.
test('old String law pins cannot admit current bodies', () => {
  for (const [member, old] of [
    ['kernel_law_manifest_cid', 'sha256:5a79d6cb9b012d0c3871c72e496eec7183948ac81d8ebff91b4f7ee6a59ae19d'],
    ['rela_scalar_law_manifest_cid', 'sha256:a866ed224e15da7e25b45d4e166b25b6bd6749a31bd7dfacb185391ad3f80122'],
  ]) {
    const dependencies = loadDependencies();
    dependencies.contract[member] = old;
    assert.throws(() => checkDependencies(dependencies), /law body CID/);
    assert.equal(dependencies.contract[member], old, 'no implicit pin repair');
  }
});
