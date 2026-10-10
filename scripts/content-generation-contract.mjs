import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
export const contentGenerationReferences = Object.freeze({type: 'array',
  uniqueItems: true, items: cid});
export const contentGenerationSchema = Object.freeze({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: 'https://smooth.dev/schemas/actql-content-generation-0.1.json',
  title: 'actql-content-generation-0.1', type: 'object', additionalProperties: false,
  required: ['version', 'bound_invocation_template_cid', 'run_definition_cid', 'node_id', 'barrier_cid',
    'content_evidence_cid',
    'availability_evidence_cid', 'content_store_cid', 'workspace_scope_cid',
    'generation_cid'],
  properties: {
    version: {const: 'actql-content-generation/0.1'},
    bound_invocation_template_cid: cid, run_definition_cid: cid,
    node_id: {type: 'string', minLength: 1},
    barrier_cid: cid, content_evidence_cid: cid, availability_evidence_cid: cid,
    content_store_cid: cid, workspace_scope_cid: cid,
    generation_cid: cid,
  },
});

// The input Artifact identifies actual ordered rows and schema, not the AoA
// fragment. The compiled owner supplies Program/bindings/occurrence provenance.
export const contentInputArtifactSchema = Object.freeze({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: 'https://smooth.dev/schemas/actql-content-input-artifact-0.1.json',
  title: 'actql-content-input-artifact-0.1', type: 'object', additionalProperties: false,
  required: ['version', 'program_definition_cid', 'parameter_values_cid',
    'invocation_bindings_cid', 'task_ordinal', 'step_ordinal', 'input_fragment_cid',
    'logical_relation_cid', 'relation_schema_cid', 'ordered_rows_cid', 'row_count',
    'effective_data_policy_cid', 'input_artifact_cid'],
  properties: {
    version: {const: 'actql-content-input-artifact/0.1'},
    program_definition_cid: cid, parameter_values_cid: cid, invocation_bindings_cid: cid,
    task_ordinal: {type: 'integer', minimum: 0, maximum: 2147483647},
    step_ordinal: {type: 'integer', minimum: 0, maximum: 2147483647},
    input_fragment_cid: cid, logical_relation_cid: cid, relation_schema_cid: cid,
    ordered_rows_cid: cid, row_count: {type: 'integer', minimum: 0, maximum: 2147483647},
    effective_data_policy_cid: cid, input_artifact_cid: cid,
  },
});

// Current protocol schemas only. Historical evidence bodies are never repinned.
export function applyContentGenerationSchema(registry) {
  const next = structuredClone(registry);
  next.artifact_schemas.content_generation = structuredClone(contentGenerationSchema);
  next.artifact_schemas.content_input_artifact = structuredClone(contentInputArtifactSchema);
  // Embed the existing normative bodies rather than introducing a second
  // derivation/Ref contract. Saved Ref metadata is not issuance authority.
  const profiles = JSON.parse(readFileSync('spec/contracts/actql-production-profile-schemas.json', 'utf8'));
  const capture = {type: 'array', minItems: 1, items: {
    type: 'object', additionalProperties: false,
    required: ['content_evidence', 'content_generation', 'content_input_artifact',
      'content_reference', 'invocation_template'],
    properties: {
      content_evidence: structuredClone(profiles.schemas.content_evidence),
      content_generation: structuredClone(contentGenerationSchema),
      content_input_artifact: structuredClone(contentInputArtifactSchema),
      content_reference: structuredClone(next.schemas.content_ref),
      invocation_template: structuredClone(next.artifact_schemas.bound_invocation_template),
    },
  }};
  function visit(value) {
    if (value === null || typeof value !== 'object') return;
    if (value.properties?.version?.const === 'actql-observation-set/0.1') {
      value.properties.content_generation_cids = structuredClone(contentGenerationReferences);
    }
    if (value.properties?.version?.const === 'actql-run-receipt/0.1') {
      const kinds = value.properties.external_observation_evidence.items.properties.kind.enum;
      if (!kinds.includes('content_generation')) kinds.push('content_generation');
    }
    if (value.properties?.version?.const === 'actql-run-effect-context/0.1') {
      value.properties.content_generations = structuredClone(capture);
    }
    for (const child of Object.values(value)) visit(child);
  }
  visit(next.artifact_schemas);
  for (const [name, schema] of Object.entries(next.artifact_schemas)) {
    next.artifact_schema_cids[name] = machineCid(schema);
  }
  next.artifact_registry_cid = machineCid(next.artifact_schemas);
  return next;
}

export function checkContentGenerationSchema(registry) {
  assert.deepEqual(registry, applyContentGenerationSchema(registry));
  const schema = registry.artifact_schemas.observation_set;
  assert.equal(schema.additionalProperties, false);
  assert.ok(!schema.required.includes('content_generation_cids'));
  assert.deepEqual(schema.properties.content_generation_cids, contentGenerationReferences);
  assert.deepEqual(registry.artifact_schemas.content_generation, contentGenerationSchema);
  assert.deepEqual(registry.artifact_schemas.content_input_artifact, contentInputArtifactSchema);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    registry = applyContentGenerationSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkContentGenerationSchema(registry);
}
