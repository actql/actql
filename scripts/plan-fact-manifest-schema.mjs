import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};

function insertAfter(entries, key, name, value) {
  const result = {};
  for (const [entry, body] of Object.entries(entries)) {
    result[entry] = body;
    if (entry === key) result[name] = value;
  }
  if (!Object.hasOwn(result, name)) throw new Error(`Missing predecessor: ${key}`);
  return result;
}

export function planFactManifestSchema(registry) {
  const executableFacts =
    registry.artifact_schemas.executable_plan.properties.plan_facts;
  const documentFacts =
    registry.artifact_schemas.plan_document.properties.plan.properties.plan_facts;
  assert.deepEqual(executableFacts, documentFacts);
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-plan-fact-manifest-0.1.json',
    title: 'actql-plan-fact-manifest-0.1',
    type: 'object',
    additionalProperties: false,
    required: ['version', 'plan_facts', 'plan_fact_manifest_cid'],
    properties: {
      version: {const: 'actql-plan-fact-manifest/0.1'},
      plan_facts: structuredClone(executableFacts),
      plan_fact_manifest_cid: cid,
    },
  };
}

export function checkPlanFactManifestSchema(registry) {
  const schema = registry.artifact_schemas.plan_fact_manifest;
  assert.deepEqual(schema, planFactManifestSchema(registry));
  assert.equal(registry.artifact_schema_cids.plan_fact_manifest,
    machineCid(schema));
  assert.equal(registry.artifact_registry_cid,
    machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    const schema = planFactManifestSchema(registry);
    registry.artifact_schemas = insertAfter(
      registry.artifact_schemas, 'executable_plan', 'plan_fact_manifest',
      schema,
    );
    registry.artifact_schema_cids = insertAfter(
      registry.artifact_schema_cids, 'executable_plan', 'plan_fact_manifest',
      machineCid(schema),
    );
    registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkPlanFactManifestSchema(registry);
}
