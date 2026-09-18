import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const output = 'spec/contracts/actql-run-publication.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const digest = {type: 'string', pattern: '^[0-9a-f]{64}$'};
const timestamp = {
  type: 'string',
  pattern: '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$',
};
const safeCount = {
  type: 'integer',
  minimum: 0,
  maximum: 9007199254740991,
};
const nonempty = {type: 'string', minLength: 1};
const clone = value => structuredClone(value);

function schema(name, version, required, properties, allOf) {
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: `https://smooth.dev/schemas/${name}-0.1.json`,
    title: `${name}-0.1`,
    type: 'object',
    additionalProperties: false,
    required: ['version', ...required],
    properties: {version: {const: version}, ...properties},
    ...(allOf ? {allOf} : {}),
  };
}

function inventory() {
  return {
    type: 'array',
    minItems: 1,
    items: {
      type: 'object',
      additionalProperties: false,
      required: ['result_name', 'result_definition_cid'],
      properties: {
        result_name: clone(nonempty),
        result_definition_cid: clone(cid),
      },
    },
  };
}

export function publicationSchemas() {
  const schemas = {};
  schemas.compiled_plan = schema(
    'actql-compiled-plan',
    'actql-compiled-plan/0.1',
    [
      'compiler_version',
      'aoa_ir_version',
      'executable_plan_cid',
      'program_definition_cid',
      'program_semantics_cid',
      'aoa_contract_cid',
      'aoa_logical_cid',
      'compiled_plan_cid',
    ],
    {
      compiler_version: {
        type: 'string',
        pattern: '^[A-Za-z0-9][A-Za-z0-9._+:-]{0,127}$',
      },
      aoa_ir_version: {
        type: 'string',
        pattern: '^[A-Za-z0-9][A-Za-z0-9._+:-]{0,127}$',
      },
      executable_plan_cid: clone(cid),
      program_definition_cid: clone(cid),
      program_semantics_cid: clone(cid),
      aoa_contract_cid: clone(cid),
      aoa_logical_cid: clone(cid),
      compiled_plan_cid: clone(cid),
    },
  );
  schemas.result_definition = schema(
    'actql-result-definition',
    'actql-result-definition/0.1',
    ['program_definition_cid', 'result_name', 'result_definition_cid'],
    {
      program_definition_cid: clone(cid),
      result_name: clone(nonempty),
      result_definition_cid: clone(cid),
    },
  );
  schemas.run_invocation = schema(
    'actql-run-invocation',
    'actql-run-invocation/0.1',
    ['invocation_template_cid', 'observation_set_cid', 'invocation_cid'],
    {
      invocation_template_cid: clone(cid),
      observation_set_cid: clone(cid),
      invocation_cid: clone(cid),
    },
  );
  schemas.result_retention_policy = schema(
    'actql-result-retention-policy',
    'actql-result-retention-policy/0.1',
    [
      'retention_contract_cid',
      'effective_data_policy_cid',
      'available_until',
      'delete_by',
      'extension_ceiling_at',
      'metadata_retention_policy_cid',
      'clock_contract_cid',
      'effective_retention_policy_cid',
    ],
    {
      retention_contract_cid: clone(cid),
      effective_data_policy_cid: clone(cid),
      available_until: clone(timestamp),
      delete_by: clone(timestamp),
      extension_ceiling_at: clone(timestamp),
      metadata_retention_policy_cid: clone(cid),
      clock_contract_cid: clone(cid),
      effective_retention_policy_cid: clone(cid),
    },
  );
  schemas.durable_result_binding = schema(
    'actql-durable-result-binding',
    'actql-durable-result-binding/0.1',
    [
      'run_definition_cid',
      'result_definition_cid',
      'invocation_cid',
      'logical_result_cid',
      'result_schema_cid',
      'ordering_evidence_cid',
      'codec_contract_cid',
      'material_generation_cid',
      'store_authority_cid',
      'effective_retention_policy_cid',
      'row_count',
      'byte_count',
      'physical_sha256',
      'durable_result_binding_cid',
    ],
    {
      run_definition_cid: clone(cid),
      result_definition_cid: clone(cid),
      invocation_cid: clone(cid),
      logical_result_cid: clone(cid),
      result_schema_cid: clone(cid),
      ordering_evidence_cid: clone(cid),
      codec_contract_cid: clone(cid),
      material_generation_cid: clone(cid),
      store_authority_cid: clone(cid),
      effective_retention_policy_cid: clone(cid),
      row_count: clone(safeCount),
      byte_count: clone(safeCount),
      physical_sha256: clone(digest),
      durable_result_binding_cid: clone(cid),
    },
  );
  schemas.publication_request = schema(
    'actql-publication-request',
    'actql-publication-request/0.1',
    [
      'tenant_id',
      'authority_scope_cid',
      'run_definition_cid',
      'inventory',
      'publication_policy_cid',
      'publication_target_cid',
      'requested_at',
      'publication_request_cid',
    ],
    {
      tenant_id: clone(nonempty),
      authority_scope_cid: clone(cid),
      run_definition_cid: clone(cid),
      inventory: inventory(),
      publication_policy_cid: clone(cid),
      publication_target_cid: clone(cid),
      requested_at: clone(timestamp),
      publication_request_cid: clone(cid),
    },
  );
  schemas.publication_attempt = schema(
    'actql-publication-attempt',
    'actql-publication-attempt/0.1',
    [
      'publication_request_cid',
      'run_definition_cid',
      'attempt_id',
      'fence_cid',
      'started_at',
      'publication_attempt_cid',
    ],
    {
      publication_request_cid: clone(cid),
      run_definition_cid: clone(cid),
      attempt_id: clone(nonempty),
      fence_cid: clone(cid),
      external_idempotency_key: clone(nonempty),
      started_at: clone(timestamp),
      publication_attempt_cid: clone(cid),
    },
  );
  schemas.publication_record = schema(
    'actql-publication-record',
    'actql-publication-record/0.1',
    [
      'publication_attempt_cid',
      'sequence',
      'state',
      'observed_at',
      'cleanup_owner_cids',
      'publication_record_cid',
    ],
    {
      publication_attempt_cid: clone(cid),
      prior_record_cid: clone(cid),
      sequence: {type: 'integer', minimum: 0, maximum: 9007199254740991},
      state: {
        enum: [
          'preparing',
          'committing',
          'publication_unknown',
          'succeeded',
          'failed',
          'cancelled',
        ],
      },
      observed_at: clone(timestamp),
      public_index_entry_cid: clone(cid),
      failure_cid: clone(cid),
      cleanup_owner_cids: {
        type: 'array',
        uniqueItems: true,
        items: clone(cid),
      },
      publication_record_cid: clone(cid),
    },
    [
      {
        if: {properties: {state: {const: 'succeeded'}}, required: ['state']},
        then: {required: ['public_index_entry_cid']},
      },
      {
        if: {properties: {state: {const: 'failed'}}, required: ['state']},
        then: {required: ['failure_cid']},
      },
    ],
  );
  const grantBase = {
    tenant_id: clone(nonempty),
    authority_scope_cid: clone(cid),
    principal_id: clone(nonempty),
    run_definition_cid: clone(cid),
    result_manifest_cid: clone(cid),
    purpose: clone(nonempty),
    data_ceiling_cid: clone(cid),
    max_bytes: clone(safeCount),
    max_uses: clone(safeCount),
    expires_at: clone(timestamp),
    authorization_context_cid: clone(cid),
  };
  schemas.manifest_read_grant = schema(
    'actql-manifest-read-grant',
    'actql-manifest-read-grant/0.1',
    [
      ...Object.keys(grantBase),
      'manifest_read_grant_cid',
    ],
    {...clone(grantBase), manifest_read_grant_cid: clone(cid)},
  );
  schemas.result_read_grant = schema(
    'actql-result-read-grant',
    'actql-result-read-grant/0.1',
    [
      ...Object.keys(grantBase),
      'results',
      'formats',
      'egress_admission_cid',
      'result_read_grant_cid',
    ],
    {
      ...clone(grantBase),
      results: {
        type: 'array',
        minItems: 1,
        uniqueItems: true,
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['result_name', 'result_artifact_cid'],
          properties: {
            result_name: clone(nonempty),
            result_artifact_cid: clone(cid),
          },
        },
      },
      formats: {
        type: 'array',
        minItems: 1,
        uniqueItems: true,
        items: {enum: ['json', 'jsonl', 'csv']},
      },
      egress_admission_cid: clone(cid),
      result_read_grant_cid: clone(cid),
    },
  );
  schemas.delivery_attempt = schema(
    'actql-delivery-attempt',
    'actql-delivery-attempt/0.1',
    [
      'attempt_id',
      'result_read_grant_cid',
      'run_definition_cid',
      'result_manifest_cid',
      'result_name',
      'result_artifact_cid',
      'serialization_contract_cid',
      'requested_at',
      'delivery_attempt_cid',
    ],
    {
      attempt_id: clone(nonempty),
      result_read_grant_cid: clone(cid),
      run_definition_cid: clone(cid),
      result_manifest_cid: clone(cid),
      result_name: clone(nonempty),
      result_artifact_cid: clone(cid),
      serialization_contract_cid: clone(cid),
      requested_at: clone(timestamp),
      delivery_attempt_cid: clone(cid),
    },
  );
  schemas.delivery_record = schema(
    'actql-delivery-record',
    'actql-delivery-record/0.1',
    [
      'delivery_attempt_cid',
      'sequence',
      'state',
      'confirmed_byte_count',
      'exposure',
      'observed_at',
      'cleanup_owner_cids',
      'delivery_record_cid',
    ],
    {
      delivery_attempt_cid: clone(cid),
      prior_record_cid: clone(cid),
      sequence: {type: 'integer', minimum: 0, maximum: 9007199254740991},
      state: {enum: ['streaming', 'succeeded', 'failed', 'cancelled']},
      confirmed_byte_count: clone(safeCount),
      exposure: {enum: ['exact', 'unknown_additional']},
      possible_unconfirmed_max_bytes: clone(safeCount),
      delivered_sha256: clone(digest),
      result_delivery_receipt_cid: clone(cid),
      failure_cid: clone(cid),
      observed_at: clone(timestamp),
      cleanup_owner_cids: {
        type: 'array',
        uniqueItems: true,
        items: clone(cid),
      },
      delivery_record_cid: clone(cid),
    },
    [
      {
        if: {properties: {state: {const: 'succeeded'}}, required: ['state']},
        then: {
          required: [
            'delivered_sha256',
            'result_delivery_receipt_cid',
          ],
          properties: {exposure: {const: 'exact'}},
        },
      },
      {
        if: {
          properties: {exposure: {const: 'unknown_additional'}},
          required: ['exposure'],
        },
        then: {required: ['possible_unconfirmed_max_bytes']},
      },
    ],
  );
  schemas.public_index_entry = schema(
    'actql-public-index-entry',
    'actql-public-index-entry/0.1',
    [
      'tenant_id',
      'authority_scope_cid',
      'run_definition_cid',
      'invocation_cid',
      'result_manifest_cid',
      'run_receipt_cid',
      'captured_run_cid',
      'durable_result_binding_cids',
      'publication_request_cid',
      'publication_attempt_cid',
      'committed_at',
      'public_index_entry_cid',
    ],
    {
      tenant_id: clone(nonempty),
      authority_scope_cid: clone(cid),
      run_definition_cid: clone(cid),
      invocation_cid: clone(cid),
      result_manifest_cid: clone(cid),
      run_receipt_cid: clone(cid),
      captured_run_cid: clone(cid),
      durable_result_binding_cids: {
        type: 'array',
        minItems: 1,
        uniqueItems: true,
        items: clone(cid),
      },
      publication_request_cid: clone(cid),
      publication_attempt_cid: clone(cid),
      committed_at: clone(timestamp),
      public_index_entry_cid: clone(cid),
    },
  );
  return schemas;
}

export const referenceRoles = {
  compiled_plan: {
    executable_plan_cid: 'external:executable-plan',
    program_definition_cid: 'external:program-definition',
    program_semantics_cid: 'external:program-semantics',
    aoa_contract_cid: 'external:aoa-contract',
    aoa_logical_cid: 'external:aoa-logical-plan',
  },
  result_definition: {
    program_definition_cid: 'external:program-definition',
  },
  run_invocation: {
    invocation_template_cid: 'external:bound-invocation-template',
    observation_set_cid: 'external:observation-set',
  },
  result_retention_policy: {
    retention_contract_cid: 'external:retention-contract',
    effective_data_policy_cid: 'external:data-policy',
    metadata_retention_policy_cid: 'external:metadata-retention-policy',
    clock_contract_cid: 'external:clock-contract',
  },
  durable_result_binding: {
    run_definition_cid: 'external:run-definition',
    result_definition_cid: 'result_definition',
    invocation_cid: 'run_invocation',
    logical_result_cid: 'external:logical-relation',
    result_schema_cid: 'external:value-contract',
    ordering_evidence_cid: 'external:ordering-evidence',
    codec_contract_cid: 'external:durable-codec',
    material_generation_cid: 'external:material-generation',
    store_authority_cid: 'external:store-authority',
    effective_retention_policy_cid: 'result_retention_policy',
  },
  publication_request: {
    authority_scope_cid: 'external:authority-scope',
    run_definition_cid: 'external:run-definition',
    'inventory/*/result_definition_cid': 'result_definition',
    publication_policy_cid: 'external:publication-policy',
    publication_target_cid: 'external:publication-target',
  },
  publication_attempt: {
    publication_request_cid: 'publication_request',
    run_definition_cid: 'external:run-definition',
    fence_cid: 'external:publication-fence',
  },
  publication_record: {
    publication_attempt_cid: 'publication_attempt',
    prior_record_cid: 'publication_record?',
    public_index_entry_cid: 'public_index_entry?',
    failure_cid: 'external:runtime-error?',
    'cleanup_owner_cids/*': 'external:cleanup-owner',
  },
  manifest_read_grant: {
    authority_scope_cid: 'external:authority-scope',
    run_definition_cid: 'external:run-definition',
    result_manifest_cid: 'external:result-manifest',
    data_ceiling_cid: 'external:data-ceiling',
    authorization_context_cid: 'external:authorization-context',
  },
  result_read_grant: {
    authority_scope_cid: 'external:authority-scope',
    run_definition_cid: 'external:run-definition',
    result_manifest_cid: 'external:result-manifest',
    data_ceiling_cid: 'external:data-ceiling',
    authorization_context_cid: 'external:authorization-context',
    'results/*/result_artifact_cid': 'external:result-artifact',
    egress_admission_cid: 'external:egress-admission',
  },
  delivery_attempt: {
    result_read_grant_cid: 'result_read_grant',
    run_definition_cid: 'external:run-definition',
    result_manifest_cid: 'external:result-manifest',
    result_artifact_cid: 'external:result-artifact',
    serialization_contract_cid: 'external:result-serialization',
  },
  delivery_record: {
    delivery_attempt_cid: 'delivery_attempt',
    prior_record_cid: 'delivery_record?',
    result_delivery_receipt_cid: 'external:delivery-receipt?',
    failure_cid: 'external:runtime-error?',
    'cleanup_owner_cids/*': 'external:cleanup-owner',
  },
  public_index_entry: {
    authority_scope_cid: 'external:authority-scope',
    run_definition_cid: 'external:run-definition',
    invocation_cid: 'run_invocation',
    result_manifest_cid: 'external:result-manifest',
    run_receipt_cid: 'external:run-receipt',
    captured_run_cid: 'external:captured-run',
    'durable_result_binding_cids/*': 'durable_result_binding',
    publication_request_cid: 'publication_request',
    publication_attempt_cid: 'publication_attempt',
  },
};

const authorizationSources = new Set([
  'manifest_read_grant',
  'result_read_grant',
]);
const retentionSources = new Set([
  'result_retention_policy',
  'durable_result_binding',
]);

export function publicationRegistry() {
  const schemas = publicationSchemas();
  const reference_graph = [];
  for (const [source, roles] of Object.entries(referenceRoles)) {
    for (const [slot, target] of Object.entries(roles)) {
      reference_graph.push({
        source,
        slot,
        target,
        role: authorizationSources.has(source)
          ? 'authorization'
          : retentionSources.has(source)
            ? 'retention'
            : 'semantic',
      });
    }
  }
  return {
    version: 'actql-run-publication-registry/0.1',
    schemas,
    schema_cids: Object.fromEntries(
      Object.entries(schemas).map(([name, body]) => [name, machineCid(body)]),
    ),
    reference_roles: clone(referenceRoles),
    reference_graph,
    laws: {
      self_identity:
        'each_self_cid_hashes_the_complete_closed_body_without_only_its_self_member',
      result_definition:
        'program_definition_and_result_name_resolve_one_exact_checked_result_occurrence',
      run_invocation:
        'template_matches_observation_set_and_all_required_observations_are_admitted',
      publication_commit:
        'one_tenant_authority_run_definition_has_one_atomic_durable_public_index_entry',
      publication_retry:
        'unknown_reconciles_under_fencing_before_retry_and_durable_commit_wins_cancel_race',
      availability:
        'run_outcome_is_immutable_and_current_per_result_availability_is_separate_from_authority',
      delivery:
        'attempt_identity_precedes_append_only_progress_and_retry_starts_at_byte_zero',
      retention:
        'availability_authority_and_deletion_deadline_are_independent',
    },
  };
}

export function checkRegistry(value) {
  const expected = publicationRegistry();
  assert.deepEqual(value, expected);
  for (const [name, body] of Object.entries(value.schemas)) {
    assert.equal(value.schema_cids[name], machineCid(body), name);
  }
  assert.equal(
    new Set(value.reference_graph.map(edge => `${edge.source}\0${edge.slot}`)).size,
    value.reference_graph.length,
  );
  return value;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const value = publicationRegistry();
  if (process.argv.includes('--write')) {
    writeFileSync(output, JSON.stringify(value, null, 2) + '\n');
  } else {
    checkRegistry(JSON.parse(readFileSync(output, 'utf8')));
  }
  console.log(
    `${Object.keys(value.schemas).length} Run publication schemas verified.`,
  );
}
