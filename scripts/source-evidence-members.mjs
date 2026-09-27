// Components of the existing Check Environment, not a second evidence format.
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const common = {
  source_ref: {type: 'string', pattern: '^connector://.+/.+#.+$'},
  source_contract_cid: cid,
  source_view_contract_cid: cid,
  read_mode: {const: 'snapshot'},
};
const closed = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});

export function connectorSourceEvidenceMembers() {
  return {
    schema_snapshot: closed({...common,
      output_carrier: {const: 'relation'},
      carrier_schema_contract_cid: cid,
      source_data_policy_cid: cid,
      data_classification: {enum: ['public', 'internal', 'confidential',
        'restricted', 'unknown']},
    }),
    connector_capability: closed({...common,
      capability_contract_cids: {type: 'array', uniqueItems: true, items: cid},
    }),
    semantics: {
      identity: 'full_canonical_member_body_no_self_cid_no_exclusions',
      selection: 'unique_exact_checked_source_contract_view_and_read_mode',
      capability_order: 'strict_ascending_full_contract_cid',
      runtime: 'issuer_verifies_observed_schema_and_used_contracts',
      authority: 'current_read_grant_completion_and_order_verified_separately',
      scope: 'connector_snapshot_relation_source_evidence_issuance',
    },
  };
}
