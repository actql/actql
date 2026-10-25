import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path = 'spec/contracts/actql-protocol-schemas.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const count = {type: 'string', pattern: '^(0|[1-9][0-9]*)$(?![\\s\\S])'};
const signed = {type: 'string', pattern: '^(0|-?[1-9][0-9]*)$(?![\\s\\S])'};
const bool = {type: 'boolean'};
const nullable = schema => ({oneOf: [{type: 'null'}, schema]});
const tuple = prefixItems => ({type: 'array', prefixItems, items: false,
  minItems: prefixItems.length, maxItems: prefixItems.length});
const closed = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
const quantities = tuple([count, count, count]);
const limits = tuple(Array(6).fill(count));
const reservation = tuple([signed, count, count, count, bool, bool,
  nullable(quantities), nullable(quantities), tuple([bool, bool, bool]),
  nullable(tuple([nullable(count), count, count])), bool, bool]);

// Positional shape is shared with the existing original-state codec. Integer
// widths, live token identities, full census and current phase are checked by
// the original Core owner, never by JSON Schema or a caller usage aggregate.
export function originalResourceDocumentSchema() {
  return tuple([
    {const: 'actql-original-ledger-state/0.1'}, limits,
    tuple(Array(13).fill(count)), tuple([count, count, count]),
    nullable(quantities), tuple([quantities, quantities, quantities]),
    tuple([nullable(signed), nullable(count), nullable(count)]),
    tuple([count, count, count, bool, bool, bool,
      {enum: ['reading', 'parked', 'stopping']}, bool]),
    reservation, {type: 'array', minItems: 1, items: reservation},
    {type: 'array', items: tuple([count, signed, count, bool])},
    {type: 'array', items: tuple([signed, limits,
      tuple([count, count, count, count, count])])},
  ]);
}

export function modelOriginalResourceStateSchema() {
  const origin = closed({
    run_id: text, run_definition_cid: cid, prepared_invocation_cid: cid,
    host_policy_cid: cid, execution_context_cid: cid,
    program_definition_cid: cid, parameter_values_cid: cid, barrier_cid: cid,
    runtime_artifact_cid: cid, layout_artifact_cid: cid,
    response_profile_cid: cid, storage_binding_cid: cid,
  });
  const slot = closed({ordinal: {type: 'integer', minimum: 0}, slot_cid: cid,
    attempt_index: {type: 'integer', minimum: 0},
    state: {enum: ['Unsent', 'EnteredUnknown', 'SavedSuccess', 'SavedFailure']},
    entry_identity_cid: nullable(cid), settlement_identity_cid: nullable(cid)});
  const cut = closed({scope_cid: cid, input_artifact_cid: cid,
    fixed_input_receipt_cid: cid, run_version: {type: 'integer', minimum: 1},
    continuation: nullable(closed({checkpoint_cid: cid, intent_id: text,
      claimant: text, generation: {type: 'integer', minimum: 1}, resolution_cid: cid})),
    slots: {type: 'array', items: slot}});
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: 'https://smooth.dev/schemas/actql-model-original-resource-state-0.1.json',
    title: 'actql-model-original-resource-state-0.1',
    ...closed({version: {const: 'actql-model-original-resource-state/0.1'},
      origin, resource_state: originalResourceDocumentSchema(),
      resource_state_cid: cid,
      resource_phase: {enum: ['preparation_base', 'parked', 'stopping']},
      cut: nullable(cut)}),
    allOf: [{oneOf: [
      {properties: {resource_phase: {const: 'preparation_base'}, cut: {type: 'null'}}},
      {properties: {resource_phase: {enum: ['parked', 'stopping']}, cut}},
    ]}],
    $comment: 'No self CID. resource_state_cid identifies exact original Writer UTF-8 bytes. Shape admission grants neither restored resources nor Model send. Current cut requires the same opaque parked/stopping owner and committed original journal fences.',
  };
}

export function applyModelOriginalResourceStateSchema(registry) {
  registry.artifact_schemas.model_original_resource_state = modelOriginalResourceStateSchema();
  registry.artifact_schema_cids.model_original_resource_state =
    machineCid(registry.artifact_schemas.model_original_resource_state);
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkModelOriginalResourceStateSchema(registry) {
  assert.deepEqual(registry.artifact_schemas.model_original_resource_state,
    modelOriginalResourceStateSchema());
  assert.equal(registry.artifact_schema_cids.model_original_resource_state,
    machineCid(modelOriginalResourceStateSchema()));
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv.includes('--write')) {
    applyModelOriginalResourceStateSchema(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
    const familyPath = 'spec/spec-family.json';
    const family = JSON.parse(readFileSync(familyPath, 'utf8'));
    const owner = family.documents.find(value => value.document_id === 'run');
    assert.ok(owner);
    const pointer = '/artifact_schemas/model_original_resource_state';
    const reference = {path, pointer,
      cid: registry.artifact_schema_cids.model_original_resource_state,
      version: registry.version};
    const old = owner.machine_contracts.findIndex(value => value.path === path && value.pointer === pointer);
    if (old < 0) owner.machine_contracts.push(reference);
    else owner.machine_contracts[old] = reference;
    writeFileSync(familyPath, JSON.stringify(family, null, 2) + '\n');
  }
  checkModelOriginalResourceStateSchema(registry);
}
