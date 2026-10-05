import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const count = {type: 'integer', minimum: 0, maximum: Number.MAX_SAFE_INTEGER};
const nullableCount = {anyOf: [count, {type: 'null'}]};
const schema = (name, fields) => ({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  type: 'object', additionalProperties: false,
  required: ['version', ...Object.keys(fields), 'self_cid'],
  properties: {version: {const: `actql-${name.replaceAll('_', '-')}/0.1`},
    ...fields, self_cid: cid},
});

export function modelAttemptEvidenceSchemas() {
  const accounting = schema('model_attempt_accounting', {
    attempt_cid: cid, slot_cid: cid,
    cumulative_work: count, uncertain_wire_bytes: count,
    input_tokens: nullableCount, output_tokens: nullableCount,
    cost_units: nullableCount, duration_ms: nullableCount,
  });
  // Existing bodies without a metered installed profile retain their exact
  // preimage. An installed profile must bind all three reservation units.
  accounting.properties.reservation = {type: 'object',
    additionalProperties: false,
    required: ['tokens', 'cost_units', 'duration_ms'],
    properties: {tokens: count, cost_units: count, duration_ms: count}};
  const authority = schema('model_dispatch_authority', {
      program_definition_cid: cid, run_definition_cid: cid,
      run_authorization_cid: cid, account_configuration_cid: cid,
      model_task_cid: cid, fixed_request_cid: cid,
      execution_context_cid: cid, host_policy_cid: cid,
      principal: text, connection: text, resource: text,
      operation: {const: 'infer'}, entry_id: text,
      basis: {enum: ['account_allow', 'host_permit']},
      answering_authority: {anyOf: [text, {type: 'null'}]},
      satisfied_claims: {type: 'array', uniqueItems: true, items: text},
    });
  // Historical authority and response originals remain readable for no-send
  // replay. Every new delegated send semantically requires this exact scope.
  authority.properties.model_invocation_scope_cid = cid;
  return {
    model_dispatch_authority: authority,
    model_call_attempt: schema('model_call_attempt', {
      slot_cid: cid, run_definition_cid: cid, model_task_cid: cid,
      fixed_request_cid: cid, authority_evidence_cid: cid,
      attempt: {...count, minimum: 1}, provider_id: text,
    }),
    model_attempt_accounting: accounting,
    model_attempt_outcome: schema('model_attempt_outcome', {
      attempt_cid: cid, slot_cid: cid,
      category: {enum: ['ok', 'provider_failure', 'contract_violation',
        'cancelled', 'result_unknown']},
      failure: {anyOf: [{enum: ['rate_limit', 'timeout', 'provider_error',
        'refusal', 'schema_invalid', 'safety_rejected', 'truncated',
        'output_identity', 'output_value', 'cancelled', 'deadline',
        'result_unknown', 'budget_exceeded']}, {type: 'null'}]},
    }),
  };
}

export function applyModelAttemptEvidenceSchemas(registry) {
  for (const [name, body] of Object.entries(modelAttemptEvidenceSchemas())) {
    registry.artifact_schemas[name] = body;
    registry.artifact_schema_cids[name] = machineCid(body);
  }
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkModelAttemptEvidenceSchemas(registry) {
  for (const [name, body] of Object.entries(modelAttemptEvidenceSchemas())) {
    assert.deepEqual(registry.artifact_schemas[name], body);
    assert.equal(registry.artifact_schema_cids[name], machineCid(body));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

// Register generated schema pins with their existing normative owner. No
// existing schema or identity preimage is rewritten by this additive update.
function registerPins(registry) {
  const manifestPath = 'spec/spec-family.json';
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const owner = manifest.documents.find(d => d.document_id === 'contracts');
  assert.ok(owner);
  let source = readFileSync(owner.path, 'utf8');
  const marker = '../../../spec/contracts/actql-protocol-schemas.json#/artifact_schemas/model_call_slot ';
  const line = source.split('\n').find(line => line.startsWith(marker));
  assert.ok(line);
  const additions = [];
  for (const name of Object.keys(modelAttemptEvidenceSchemas())) {
    const pointer = `/artifact_schemas/${name}`;
    const pin = registry.artifact_schema_cids[name];
    const existing = owner.machine_contracts.find(ref =>
      ref.path === 'spec/contracts/actql-protocol-schemas.json' && ref.pointer === pointer);
    if (existing) {
      const previousLine = `../../../spec/contracts/actql-protocol-schemas.json#${pointer} ${existing.cid}`;
      source = source.replace(previousLine,
        `../../../spec/contracts/actql-protocol-schemas.json#${pointer} ${pin}`);
      existing.cid = pin;
    }
    else owner.machine_contracts.push({path: 'spec/contracts/actql-protocol-schemas.json',
      pointer, cid: pin, version: registry.version});
    const pinLine = `../../../spec/contracts/actql-protocol-schemas.json#${pointer} ${pin}`;
    if (!source.includes(pinLine)) additions.push(pinLine);
  }
  if (additions.length) source = source.replace(line, line + '\n' + additions.join('\n'));
  writeFileSync(owner.path, source);
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyModelAttemptEvidenceSchemas(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    registerPins(registry);
  }
  checkModelAttemptEvidenceSchemas(registry);
}
