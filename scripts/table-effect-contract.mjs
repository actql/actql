// This generator owns only the Table provider envelopes. It neither issues
// approval nor interprets Catalog observations as Effect state transitions.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

export const tableContractPath = 'spec/contracts/actql-table-effect.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const uuid = {type: 'string',
  pattern: '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'};
const text = {type: 'string', minLength: 1, maxLength: 256};
const nonnegative = {type: 'integer', minimum: 0, maximum: 9007199254740991};
const fieldId = {type: 'integer', minimum: 1, maximum: 2147483647};
const nullable = schema => ({anyOf: [schema, {type: 'null'}]});
const object = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});
const schema = (name, fields) => ({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: `urn:actql:table-${name}:0.1`,
  ...object(fields),
});

export function tableEffectContract() {
  return {
    version: 'actql-table-effect-contract/0.1',
    identity: {
      request: 'canonical_complete_operation_excluding_only_request_cid',
      receipt: 'canonical_complete_receipt_excluding_only_receipt_cid',
      mapping: 'canonical_complete_mapping_excluding_only_mapping_cid',
      generation: 'sha256_of_exact_published_iceberg_metadata_file_bytes',
      table: 'catalog_identity_and_immutable_iceberg_table_uuid',
      snapshot_id: 'nullable_decimal_string_not_generation_or_logical_content_cid',
    },
    semantics: {
      input: 'one_complete_checked_relation_per_operation_not_per_row',
      create: 'name_absent_at_atomic_publication',
      replace: 'same_table_uuid_exact_expected_generation_same_schema_cid',
      empty: 'typed_empty_table_no_fabricated_row_or_snapshot_id',
      multiplicity: 'preserve_duplicate_rows',
      ordering: 'no_query_order_from_physical_file_or_iceberg_sort_order',
      approval: 'required_before_table_staging_and_publication_current_authority_rechecked',
      unknown: 'reconcile_original_operation_no_resend_no_potentially_published_file_cleanup',
      publication: 'durable_catalog_head_and_original_operation_record_in_one_transaction',
      completion: 'confirmed_original_catalog_commit_not_http_admission_or_staging',
      recovery: 'operation_record_retained_independently_of_head_and_later_commits',
      retention: 'independent_of_origin_run_release_or_named_result_ttl',
      capacity: 'finite_persistent_limits_include_retained_staged_and_unknown_files',
      refusal: 'typed_prewrite_refusal_for_unsupported_contracts_or_storage_exhaustion',
      external_writers: 'outside_initial_provider_capability',
    },
    presence: {
      binding: 'sealed_logical_column_to_value_and_companion_iceberg_field_ids',
      false_null: 'missing_logical_column',
      true_null: 'present_null_requires_logical_nullable',
      true_value: 'present_value_requires_checked_type',
      false_value: 'reject',
      missing_or_null_companion: 'reject_before_default_projection',
      missing_value_field: 'reject_before_default_projection',
      required_column: 'value_field_physically_present_without_companion_nullable_independent',
      physical_namespace: '__actql_presence_',
      ordinary_reader: 'physical_companions_visible_no_implicit_actql_presence_semantics',
    },
    schemas: {
      operation: schema('operation', {
        version: {const: 'actql-table-operation/0.1'},
        logical_request_scope_cid: cid,
        effect_identity_cid: cid,
        action: {enum: ['create', 'replace']},
        catalog_identity_cid: cid,
        namespace: {type: 'array', items: text, minItems: 1, maxItems: 16},
        table_name: text,
        expected_table: nullable(object({table_uuid: uuid, generation_cid: cid})),
        input_artifact_cid: cid,
        input_relation_cid: cid,
        schema_cid: cid,
        storage_mapping_cid: cid,
        data_policy_cid: cid,
        request_cid: cid,
      }),
      receipt: schema('receipt', {
        version: {const: 'actql-table-receipt/0.1'},
        request_cid: cid,
        effect_identity_cid: cid,
        catalog_identity_cid: cid,
        table_uuid: uuid,
        generation_cid: cid,
        metadata_location: {type: 'string', minLength: 1, maxLength: 4096},
        snapshot_id: nullable({type: 'string',
          pattern: '^[1-9][0-9]{0,18}$'}),
        schema_cid: cid,
        storage_mapping_cid: cid,
        row_count: nonnegative,
        receipt_cid: cid,
      }),
      storage_mapping: schema('storage-mapping', {
        version: {const: 'actql-table-storage-mapping/0.1'},
        schema_cid: cid,
        iceberg_format_version: {const: 2},
        columns: {type: 'array', maxItems: 1024, items: object({
          name: text,
          value_field_id: fieldId,
          presence_field_id: nullable(fieldId),
          physical_type: {enum: ['boolean', 'double', 'string']},
          nullable: {type: 'boolean'},
          presence: {enum: ['required', 'conditional']},
        })},
        mapping_cid: cid,
      }),
    },
  };
}

export function checkTableEffectContract(body) {
  assert.deepEqual(body, tableEffectContract());
}

// Independent structural checks for fixtures/generators, not production
// authority or a substitute for common bounded request admission.
export function checkTableOperation(body) {
  const fields = tableEffectContract().schemas.operation.required;
  assert.deepEqual(Object.keys(body).sort(), [...fields].sort());
  for (const name of fields.filter(name => name.endsWith('_cid'))) {
    assert.match(body[name], /^sha256:[0-9a-f]{64}$/u);
  }
  assert.equal(body.version, 'actql-table-operation/0.1');
  assert.ok(['create', 'replace'].includes(body.action));
  assert.ok(Array.isArray(body.namespace) && body.namespace.length > 0 &&
    body.namespace.length <= 16);
  for (const part of [...body.namespace, body.table_name]) {
    assert.ok(typeof part === 'string' && part.length > 0 && part.length <= 256);
    assert.ok(part.isWellFormed() && part === part.normalize('NFC') &&
      !/[\r\n\0]/u.test(part));
  }
  if (body.action === 'create') assert.equal(body.expected_table, null);
  else {
    assert.deepEqual(Object.keys(body.expected_table).sort(),
      ['generation_cid', 'table_uuid']);
    assert.match(body.expected_table.table_uuid, new RegExp(uuid.pattern, 'u'));
    assert.match(body.expected_table.generation_cid, /^sha256:[0-9a-f]{64}$/u);
  }
  const {request_cid: expected, ...preimage} = body;
  assert.equal(machineCid(preimage), expected);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--write')) {
    writeFileSync(tableContractPath,
      JSON.stringify(tableEffectContract(), null, 2) + '\n');
  }
  checkTableEffectContract(JSON.parse(readFileSync(tableContractPath, 'utf8')));
  console.log('Table Effect contract: exact provider envelopes; runtime acceptance not implied.');
}
