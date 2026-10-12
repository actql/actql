// Additive data identities of admitted original journal facts. These schemas
// confer no custody, ACK, resource park, restoration or dispatch permission.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
// These are existing journal integer facts, not new Ledger quantities.
const natural = {type: 'integer', minimum: 0, maximum: Number.MAX_SAFE_INTEGER};
const positive = {...natural, minimum: 1};
const nullable = value => ({oneOf: [{type: 'null'}, value]});
const strings = {type: 'array', uniqueItems: true, items: text};
const closed = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
const artifact = (name, fields) => ({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: `https://smooth.dev/schemas/actql-${name.replaceAll('_', '-')}-0.1.json`,
  title: `actql-${name.replaceAll('_', '-')}-0.1`,
  ...closed({version: {const: `actql-${name.replaceAll('_', '-')}/0.1`},
    ...fields, self_cid: cid}),
});

export function modelJournalIdentitySchemas() {
  // The optional parent is the exact four-field read-resume fence actually
  // retained by an immediate Entry. No absent approval is manufactured.
  const parent = closed({checkpoint_cid: cid, intent_id: text,
    claimant: text, generation: positive});
  const immediate = closed({run_valid_until: text, dispatch_valid_until: text,
    parent_resume_fence: nullable(parent)});
  const deferred = closed({
    checkpoint_cid: cid, intent_id: text, claimant: text, generation: positive,
    resolution_cid: cid, verified_resolution_cid: cid,
    lease_expires_ms: natural, prepare_attempt_id: {type: 'null'},
    kind: {const: 'model_invocation'}, required_artifact_cid: cid,
    decision_subject_cid: nullable(cid), requested_claims: strings,
    configuration_cid: nullable(cid), observed_claims: strings,
    authority: text, approval_expires_at: text,
  });
  const entry = artifact('model_journal_entry', {
    run_id: text, run_definition_cid: cid, prepared_invocation_cid: cid,
    scope_cid: cid, provider_binding_cid: cid, input_artifact_cid: cid,
    task_index: natural, strategy_revision: natural,
    ordinal: natural, slot_cid: cid, attempt_index: positive, attempt_cid: cid,
    dispatch_authority_cid: cid, admitted_at: text,
    model_grant_expires_at: text,
    provenance: {enum: ['immediate', 'deferred']},
    immediate: nullable(immediate), deferred: nullable(deferred),
  });
  entry.oneOf = [
    {properties: {provenance: {const: 'immediate'}, immediate,
      deferred: {type: 'null'}}},
    {properties: {provenance: {const: 'deferred'}, immediate: {type: 'null'},
      deferred}},
  ];
  const savedReference = closed({cid, holding_cid: cid});
  const settlement = artifact('model_journal_settlement', {
    entry_identity_cid: cid,
    state: {enum: ['SavedSuccess', 'SavedFailure']},
    durable: {const: true}, retry_allowed: {type: 'boolean'}, settled_at: text,
    evidence: closed({
      model_call_attempt: savedReference,
      model_dispatch_authority: savedReference,
      model_attempt_accounting: savedReference,
      model_attempt_outcome: savedReference,
      model_slot_capture: nullable(savedReference),
      model_capture_bundle: nullable(savedReference),
      terminal_failure: nullable({type: 'boolean'}),
    }),
  });
  // Existing validSettlement forbids retry of SavedSuccess. SavedFailure may
  // carry a partially persisted capture; do not invent a missing reference.
  settlement.oneOf = [
    {properties: {state: {const: 'SavedSuccess'}, retry_allowed: {const: false}}},
    {properties: {state: {const: 'SavedFailure'}}},
  ];
  return {model_journal_entry: entry, model_journal_settlement: settlement};
}

export function applyModelJournalIdentitySchemas(registry) {
  for (const [name, schema] of Object.entries(modelJournalIdentitySchemas())) {
    registry.artifact_schemas[name] = schema;
    registry.artifact_schema_cids[name] = machineCid(schema);
  }
  registry.artifact_registry_cid = machineCid(registry.artifact_schemas);
  return registry;
}

export function checkModelJournalIdentitySchemas(registry) {
  for (const [name, schema] of Object.entries(modelJournalIdentitySchemas())) {
    assert.deepEqual(registry.artifact_schemas[name], schema);
    assert.equal(registry.artifact_schema_cids[name], machineCid(schema));
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
}

function registerPins(registry, write) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const familyPath = 'spec/spec-family.json';
  const family = JSON.parse(readFileSync(familyPath, 'utf8'));
  const owner = family.documents.find(value =>
    value.path === 'docs/spec/protocols/artifacts.md');
  assert.ok(owner);
  const marker = /<!-- model-journal-identity-pins:start -->[\s\S]*?<!-- model-journal-identity-pins:end -->/u;
  let source = readFileSync(owner.path, 'utf8');
  const lines = [];
  for (const name of Object.keys(modelJournalIdentitySchemas())) {
    const reference = {path, pointer: `/artifact_schemas/${name}`,
      cid: registry.artifact_schema_cids[name], version: registry.version};
    const old = owner.machine_contracts.find(value =>
      value.path === path && value.pointer === reference.pointer);
    if (write) {
      if (old) Object.assign(old, reference);
      else owner.machine_contracts.push(reference);
    } else assert.deepEqual(old, reference);
    lines.push(`../../../${path}#${reference.pointer} ${reference.cid}`);
  }
  const block = '<!-- model-journal-identity-pins:start -->\n```text\n' +
    lines.join('\n') + '\n```\n<!-- model-journal-identity-pins:end -->';
  assert.ok(marker.test(source));
  if (write) {
    source = source.replace(marker, block);
    writeFileSync(owner.path, source);
    writeFileSync(familyPath, JSON.stringify(family, null, 2) + '\n');
  } else assert.equal(source.match(marker)[0], block);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = 'spec/contracts/actql-protocol-schemas.json';
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  const write = process.argv.includes('--write');
  if (write) {
    applyModelJournalIdentitySchemas(registry);
    writeFileSync(path, JSON.stringify(registry, null, 2) + '\n');
  }
  checkModelJournalIdentitySchemas(registry);
  registerPins(registry, write);
}
