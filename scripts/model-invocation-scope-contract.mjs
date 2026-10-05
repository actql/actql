import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const count = {type: 'integer', minimum: 0, maximum: Number.MAX_SAFE_INTEGER};
const closed = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
const artifact = (name, fields) => ({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: `https://smooth.dev/schemas/actql-${name}-0.1.json`,
  title: `actql-${name}-0.1`,
  ...closed({version: {const: `actql-${name}/0.1`}, ...fields, self_cid: cid}),
});

export function modelInvocationScopeSchemas() {
  return {
    model_provider_binding: artifact('model-provider-binding', {
      provider_id: text, installation_revision_cid: cid,
      configuration_contract_cid: cid, configuration_cid: cid,
    }),
    model_invocation_scope: artifact('model-invocation-scope', {
      run_definition_cid: cid, task_index: count, strategy_revision: count,
      inference_barrier_cid: cid, input_artifact_cid: cid,
      model_call_slot_cids: {type: 'array', uniqueItems: true, items: cid},
      provider_binding_cid: cid,
      // The scope CID becomes Activation.subject_cid after hashing. Including
      // that subject here would create a self-reference in the preimage.
      authorization_context: closed({account_id: text, configuration_cid: cid,
        entry_id: text, principal: text, connection: text, resource: text,
        operation: {const: 'infer'}, boundary: {const: 'activation'},
        context_cid: cid}),
    }),
  };
}

export function applyModelInvocationScopeSchemas(registry) {
  Object.assign(registry.artifact_schemas, modelInvocationScopeSchemas());
  const checkpoint = registry.artifact_schemas.execution_checkpoint;
  const artifacts = checkpoint.properties.required_artifact.properties.artifact_type.enum;
  if (!artifacts.includes('model_invocation_scope')) artifacts.push('model_invocation_scope');
  if (!checkpoint.properties.kind.enum.includes('model_invocation')) {
    checkpoint.properties.kind.enum.push('model_invocation');
    const branch = structuredClone(checkpoint.oneOf.find(branch =>
      branch.properties.kind.const === 'cost_scope'));
    branch.properties.kind.const = 'model_invocation';
    branch.properties.required_artifact.properties.artifact_type.const =
      'model_invocation_scope';
    checkpoint.oneOf.push(branch);
  }
  const kinds = registry.artifact_schemas.run_state.properties.checkpoint
    .properties.kind.enum;
  if (!kinds.includes('model_invocation')) kinds.push('model_invocation');
  const approvalKinds = registry.artifact_schemas.verified_checkpoint_resolution
    .properties.approval_evidence.oneOf[0].properties.kind.enum;
  if (!approvalKinds.includes('model_invocation')) approvalKinds.push('model_invocation');
  // Existing non-Model displays remain compatible. A Model display names both
  // its scope and complete ordered inventory; their exact equality is semantic.
  registry.artifact_schemas.run_review_projection.properties.displayed_scope = {
    type: 'object',
    properties: {model_invocation_scope_cid: cid,
      model_call_slot_cids: {type: 'array', uniqueItems: true, items: cid}},
    allOf: [
      {if: {required: ['model_invocation_scope_cid']},
        then: {required: ['model_call_slot_cids']}},
      {if: {required: ['model_call_slot_cids']},
        then: {required: ['model_invocation_scope_cid']}},
    ],
  };
  for (const [name, body] of Object.entries(registry.artifact_schemas)) {
    registry.artifact_schema_cids[name] = machineCid(body);
  }
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkModelInvocationScopeSchemas(registry) {
  for (const [name, body] of Object.entries(modelInvocationScopeSchemas())) {
    assert.deepEqual(registry.artifact_schemas[name], body);
  }
  assert.deepEqual(applyModelInvocationScopeSchemas(structuredClone(registry)), registry);
  const branch = registry.artifact_schemas.execution_checkpoint.oneOf.filter(
    item => item.properties.kind.const === 'model_invocation');
  assert.equal(branch.length, 1);
  assert.equal(branch[0].properties.subject.properties.kind.const, 'run_unit');
  assert.equal(branch[0].properties.phase.const, 'preflight');
  assert.equal(branch[0].properties.required_artifact.properties.artifact_type.const,
    'model_invocation_scope');
  assert.deepEqual(branch[0].properties.requirements.const, ['invocation_scope_approved']);
  assert.ok(registry.artifact_schemas.execution_checkpoint.properties
    .required_artifact.properties.artifact_type.enum.includes('model_invocation_scope'));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyModelInvocationScopeSchemas(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkModelInvocationScopeSchemas(registry);
}
