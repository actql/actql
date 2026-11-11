import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
import {checkModelOriginalStorageBindingContract} from './model-original-storage-binding-contract.mjs';
import {
  publicationRegistry,
  publicationSchemas,
} from './run-publication-registry.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('Compiled Plan selection projection is optional and independently pinned', () => {
  const schema = publicationSchemas().compiled_plan;
  assert.equal(schema.additionalProperties, false);
  assert.ok(!schema.required.includes('effect_target_selections_cid'));
  assert.deepEqual(schema.properties.effect_target_selections_cid,
    {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'});
  const registered = read('spec/contracts/actql-run-publication.json');
  assert.equal(machineCid(schema),
    'sha256:25094bdc116c9edae1f9ea4123e182d9d898f718941527fe466f55bd448fe7b8');
  assert.deepEqual(schema, registered.schemas.compiled_plan);
  assert.equal(machineCid(schema), registered.schema_cids.compiled_plan);
  const registry = publicationRegistry();
  assert.deepEqual(registry, registered);
  assert.equal(registry.reference_roles.compiled_plan.effect_target_selections_cid,
    'external:executable-plan-effect-target-selections?');
});

test('independent Compiled Plan vectors preserve omission and bind the array CID', () => {
  const vectors = read('portability/corpus/effect-target-selection-projection.json');
  const selection = read('portability/corpus/effect-target-selection.json').cases[0];
  assert.equal(vectors.selection_cid, selection.expected_cid);
  assert.equal(machineCid(selection.preimage), vectors.selection_cid);
  const cases = vectors.cases.filter(item => item.kind === 'compiled_plan');
  for (const item of cases) {
    verifyIdentity(item.preimage, item.expected_cid, item.expected_canonical_bytes);
  }
  assert.ok(!Object.hasOwn(cases[0].preimage, 'effect_target_selections_cid'));
  assert.equal(cases[1].preimage.effect_target_selections_cid,
    vectors.selection_cid);
  assert.equal(new Set(cases.map(item => item.expected_cid)).size, cases.length);
});

test('original Model storage binding has its owned schema pin', () => {
  checkModelOriginalStorageBindingContract();
  assert.equal(machineCid(publicationSchemas().model_original_storage_binding),
    'sha256:b3906487cb64d2c9a7c5a271358d971051e76884e0d795b1c6ad64c3f00d96f1');
});

test('publication schemas are closed and self identities are explicit', () => {
  const schemas = publicationSchemas();
  const selfFields = {
    compiled_plan: 'compiled_plan_cid',
    result_definition: 'result_definition_cid',
    run_invocation: 'invocation_cid',
    result_retention_policy: 'effective_retention_policy_cid',
    durable_result_binding: 'durable_result_binding_cid',
    publication_request: 'publication_request_cid',
    publication_attempt: 'publication_attempt_cid',
    publication_record: 'publication_record_cid',
    manifest_read_grant: 'manifest_read_grant_cid',
    result_read_grant: 'result_read_grant_cid',
    delivery_attempt: 'delivery_attempt_cid',
    delivery_record: 'delivery_record_cid',
    public_index_entry: 'public_index_entry_cid',
    model_raw_capture_policy: 'self_cid',
    model_raw_response: 'self_cid',
    model_original_storage_binding: 'self_cid',
  };
  assert.deepEqual(Object.keys(schemas), Object.keys(selfFields));
  for (const [name, field] of Object.entries(selfFields)) {
    assert.equal(schemas[name].additionalProperties, false);
    assert.ok(schemas[name].required.includes(field));
    assert.deepEqual(schemas[name].properties[field], {
      type: 'string',
      pattern: '^sha256:[0-9a-f]{64}$',
    });
  }
});

test('attempt identity excludes future outcome and terminal receipt', () => {
  const schemas = publicationSchemas();
  for (const name of ['publication_attempt', 'delivery_attempt']) {
    const fields = Object.keys(schemas[name].properties);
    assert.ok(!fields.includes('state'));
    assert.ok(!fields.includes('outcome'));
    assert.ok(!fields.includes('completed_at'));
    assert.ok(!fields.some(field => field.includes('receipt')));
  }
});

test('grants bind an exact committed Manifest without wildcards', () => {
  const schemas = publicationSchemas();
  for (const name of ['manifest_read_grant', 'result_read_grant']) {
    const body = schemas[name];
    assert.ok(body.required.includes('result_manifest_cid'));
    assert.ok(body.required.includes('principal_id'));
    assert.ok(body.required.includes('max_bytes'));
    assert.ok(body.required.includes('max_uses'));
    assert.ok(body.required.includes('expires_at'));
  }
  assert.deepEqual(schemas.result_read_grant.properties.formats.items.enum, [
    'json',
    'jsonl',
    'csv',
  ]);
});

test('publication and delivery records separate progress from identity', () => {
  const schemas = publicationSchemas();
  assert.ok(
    schemas.publication_record.properties.state.enum.includes(
      'publication_unknown',
    ),
  );
  assert.deepEqual(schemas.delivery_record.properties.exposure.enum, [
    'exact',
    'unknown_additional',
  ]);
  assert.ok(
    schemas.delivery_record.properties.possible_unconfirmed_max_bytes,
  );
});

test('registry reference roles and canonical identities are fixed', () => {
  const registry = read('spec/contracts/actql-run-publication.json');
  assert.deepEqual(registry, publicationRegistry());
  assert.equal(
    machineCid(registry.schemas.result_definition),
    'sha256:13d36d24b7adcd346f7719a513f6850260bd84738c897c5bd41def223daba973',
  );
  assert.equal(
    machineCid(registry.schemas.run_invocation),
    'sha256:6295e0fe2d2b066f39c3d5ecd7c16125018aa2d46d0cfa3537c213d109b96c81',
  );
});
