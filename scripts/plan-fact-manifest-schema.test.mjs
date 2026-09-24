import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkPlanFactManifestSchema} from './plan-fact-manifest-schema.mjs';

const registry = JSON.parse(readFileSync(
  'spec/contracts/actql-protocol-schemas.json', 'utf8'));

test('Plan fact manifest reuses the closed executable fact union', () => {
  checkPlanFactManifestSchema(registry);
  const manifest = registry.artifact_schemas.plan_fact_manifest;
  assert.deepEqual(manifest.required,
    ['version', 'plan_facts', 'plan_fact_manifest_cid']);
  assert.equal(manifest.properties.version.const,
    'actql-plan-fact-manifest/0.1');
  assert.deepEqual(manifest.properties.plan_facts.items.oneOf.map(
    fact => fact.properties.kind.const), [
    'fixed_language_law', 'resolved_limit', 'contract_fact',
  ]);
  assert.deepEqual(manifest.properties.plan_facts,
    registry.artifact_schemas.executable_plan.properties.plan_facts);
  const mutated = structuredClone(registry);
  mutated.artifact_schemas.plan_fact_manifest.properties.plan_facts.items
    .oneOf.pop();
  assert.throws(() => checkPlanFactManifestSchema(mutated));
});
