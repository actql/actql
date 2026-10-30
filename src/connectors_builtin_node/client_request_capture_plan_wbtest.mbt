///|
// Existing authored Source/row contracts are copied exactly for this Node
// consuming test. Transport/capture ports are explicit component inputs, not
// Account, permission, physical IO or ordinary Host backing.

///|
let request_capture_bridge_source_query_original_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"connector_catalogs":[{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8","host_policy_profile":{"capacity":{"max_aggregate_array_items":10000,"max_artifact_bytes":10000,"max_artifact_rows":10000,"max_effect_items":10000,"max_graph_input_edges":10000,"max_graph_input_nodes":10000,"max_graph_output_rows":10000,"max_graph_paths":10000,"max_infer_items":10000,"max_model_input_tokens_per_item":10000,"max_model_request_bytes_per_item":10000,"max_model_total_duration_ms":10000,"max_nested_value_bytes":10000,"max_nested_value_depth":10000,"max_relation_output_rows":10000,"max_temporal_matches_per_key":10000,"max_temporal_output_rows":10000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:f6a45e666ca86c60fe3ce8ec72cb43dff5757740391cd2e8a883834baa681d1f","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:b257547d26294b5e2f7131d760d54cb8e6783fb8f44504e59c4f8917211387fb","row_mapping":{"Name":{"field":"id","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"number"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:c000fb12383456a0e123e74501d164b96bb886251dbb44f301661070321be8e0","version":"fixture-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
let request_capture_bridge_source_query_original_document : String =
  #|{"id":"source-compute","results":{"answer":{"from":{"result":"r","stage":"compute"}}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]},{"id":"compute","inputs":{"x":{"result":{"result":"r","stage":"acquire"}}},"results":{"r":{"fields":["id"],"from":"out"}},"steps":[{"filter":"id > 2"},{"as":"out","select":["id"]}]}],"version":"actql/0.1"}

///|
// Exact existing query_planning contract inputs, not product-generated
// expected values. The same shared verifier admits both complete bodies.
let request_capture_bridge_original_row_query_contract_fixture : String = "{\"version\":\"actql-query-acquisition-contract/0.1\",\"scope\":\"exclusive_finite_relation_scan_filter_select\",\"dependencies\":{\"canonical_value_contract\":{\"path\":\"spec/contracts/actql-protocol-schemas.json\",\"pointer\":\"/schemas/canonical_value_contract\",\"cid\":\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"},\"consumer_capacity\":{\"path\":\"spec/contracts/actql-consumer-capacity.json\",\"pointer\":\"\",\"cid\":\"sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f\"}},\"schemas\":{\"requirement\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"owner\",\"source_ref\",\"source_contract_cid\",\"input_contract_cid\",\"output_contract_cid\",\"request\",\"parameter_values_cid\",\"filter\",\"select\",\"source_validation\",\"source_order_cid\",\"logical_guards\"],\"properties\":{\"version\":{\"const\":\"actql-query-acquisition/0.1\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"input_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"output_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"request\":{\"type\":\"object\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"expression_cid\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"expression_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"select\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"fields\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"fields\":{\"type\":\"array\",\"minItems\":1,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"input\",\"output\"],\"properties\":{\"input\":{\"type\":\"string\",\"minLength\":1},\"output\":{\"type\":\"string\",\"minLength\":1}}}}}},\"source_validation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope\",\"fields\"],\"properties\":{\"scope\":{\"const\":\"selected_scan\"},\"fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true}}},\"source_order_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"logical_guards\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"max_rows\",\"max_value_bytes\"],\"properties\":{\"max_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"max_value_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"},\"completed_observation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"requirement_cid\",\"owner\",\"source_ref\",\"source_contract_cid\",\"parameter_values_cid\",\"resolved_request_cid\",\"snapshot\",\"actual_access\",\"coverage\",\"output\",\"retention\"],\"properties\":{\"version\":{\"const\":\"actql-query-observation/0.1\"},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"resolved_request_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"coverage\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"complete\",\"source_validation_evidence_cid\",\"filter_evidence_cid\",\"select_evidence_cid\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"complete\":{\"const\":true},\"source_validation_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"select_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"retention\":{\"const\":\"process\"}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"}},\"semantics\":{\"owner\":\"program_source_cid_is_authority_bearing_program_definition_cid_not_program_semantics_or_source_text_hash\",\"query_time_owner\":\"declared_query_time_dependency_requires_original_admitted_run_definition_cid_in_requirement_and_completed_observation_owner_with_same_nominal_context_and_saved_run_no_resample_no_grant\",\"derivation\":\"checked_exclusive_scan_filter_select_without_backend_cost_or_placement\",\"capture\":\"completed_select_output_before_any_consumer\",\"identity\":\"sha256_of_canonical_json_utf8_entire_body_no_self_cid\",\"request_values\":\"bound_wire_values_no_reinterpretation_of_business_param_or_literal\",\"parameter_identity\":\"existing_typed_parameter_values_projection_of_used_request_and_query_names\",\"source_validation\":\"all_known_fields_of_selected_scan_before_filter_including_rows_excluded_by_filter\",\"demand\":\"existing_checked_expression_demand_without_eager_undemanded_evaluation\",\"native\":\"preserve_mandatory_admission_and_demanded_failures_before_projection\",\"logical_guards\":\"max_rows_on_capture_output_max_value_bytes_on_admitted_records_and_demanded_roots\",\"physical_budget\":\"actual_received_bytes_rows_and_retention_independent_of_logical_output\",\"failure\":\"atomic_no_success_capture_or_consumer_on_failure_or_cancellation\",\"evidence\":\"verify_actual_execution_evidence_not_candidate_coverage_proposals_or_self_cid_only\",\"snapshot\":\"source_specific_no_universal_snapshot_token_or_isolation_requirement\",\"retention\":\"same_process_immutable_completed_observation_not_durable_run_or_recovery\",\"invocation\":\"existing_invocation_rules_retain_actual_observation_identity_not_result_identity_only\"}}"

///|
let request_capture_bridge_original_row_evidence_contract_fixture : String = "{\"version\":\"actql-query-process-evidence-contract/0.1\",\"dependencies\":{\"query_acquisition\":{\"path\":\"spec/contracts/actql-query-acquisition.json\",\"pointer\":\"\",\"cid\":\"sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc\"}},\"schemas\":{\"record\":{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"issuer\",\"attempt\",\"requirement_cid\",\"role\",\"snapshot\",\"scan_scope_cid\",\"actual_access\",\"output\"],\"properties\":{\"version\":{\"const\":\"actql-query-process-evidence/0.1\"},\"issuer\":{\"type\":\"string\",\"minLength\":1},\"attempt\":{\"type\":\"string\",\"minLength\":1},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"role\":{\"enum\":[\"source_validation\",\"filter\",\"select\"]},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"scan_scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}}}},\"semantics\":{\"preimage\":\"entire_record_canonical_json_utf8_sha256_no_self_cid\",\"authority\":\"authorized_host_private_issuer_and_live_opaque_success_handle_not_wire_or_cid_alone\",\"issuance\":\"after_complete_scan_validation_filter_select_limits_and_immutable_output_retention\",\"attempt\":\"host_allocated_unique_within_unique_process_issuer_never_reused_or_caller_selected\",\"binding\":\"exact_requirement_attempt_snapshot_scan_scope_actual_access_and_retained_output_for_all_three_roles\",\"native\":\"authorized_source_execution_covers_full_selected_scan_not_only_host_received_rows_or_columns\",\"source_order\":\"null_only_in_this_profile_relative_order_is_not_total_order_evidence\",\"lifetime\":\"same_process_no_deserialization_rehydration_or_durable_capture\",\"host_adapter\":\"host_authorized_execution_with_owned_consistent_read_view_full_scan_validation_and_query_not_driver_location_or_sql_success\",\"read_view\":\"private_task_session_transaction_binding_not_snapshot_token_no_cross_attempt_or_read_view_substitution\",\"access_accounting\":\"engine_internal_scan_host_row_receipt_and_retention_are_distinct_auxiliary_row_receipts_are_not_hidden_or_double_counted\",\"receipt_scope\":\"one_logical_received_sequence_only_independent_validation_and_query_receipts_require_an_additional_admitted_contract\",\"scan_failure\":\"invalid_excluded_rows_still_fail_no_global_diagnostic_order_or_total_order_from_validation_traversal\"}}"

///|
fn request_capture_bridge_fixture() -> (
  @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  ClientLocalPreparationInputOriginal,
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @publication_host.PreparedClientProgram,
  @publication_host.ClientRequestIdentity,
  Array[@client_local_host.ClientInstalledCaptureCapacity],
  @client_row_source_host.RowAcquisition,
  @client_local_host.ClientInstalledSequenceContracts,
) raise {
  let environment = @publication_host.admit_client_check_environment(
    request_capture_bridge_source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  assert_eq(
    client_program_prepare_request_native_computation(
      parent,
      receipt,
      request_diagnostic_test_json(
        request_capture_bridge_source_query_original_document,
      ),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ).unwrap(),
    "effect_free",
  )
  let holder = client_program_borrow_request_program_plan_input(parent, receipt).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "node-original-capture-plan",
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let requirement = client_program_prepare_local_query_requirement(
    prepared,
    0,
    0,
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let view = @client_row_source_host.declared_row_view(
    "r",
    facts.source_ref,
    facts.source_contract_cid,
    ["id", "amount"],
    facts.carrier_schema_contract_cid,
    facts.source_data_policy_cid,
  )
  let source = @client_row_source_host.prepare_declared_row_source(
    requirement, "crm/main", view,
  ).unwrap()
  let acquisition = @client_row_source_host.prepare_declared_row_acquisition(
    source, "fixture-original-source", request_capture_bridge_original_row_query_contract_fixture,
    request_capture_bridge_original_row_evidence_contract_fixture,
  ).unwrap()
  let capacity = client_program_installed_row_capture_capacity(acquisition).unwrap()
  (
    parent,
    receipt,
    holder,
    prepared,
    request,
    [capacity],
    acquisition,
    contracts,
  )
}

///|
test "actual Request captured Source bridge keeps original Plan acquisition and borrow through Run retirement" {
  let (
    parent,
    receipt,
    holder,
    prepared,
    request,
    captures,
    acquisition,
    contracts,
  ) = request_capture_bridge_fixture()
  let assets = @publication_host.client_local_product_assets()
  let plan = client_program_installed_managed_capture_plan_prepare(
    prepared,
    request,
    captures,
    [4096L],
    [2048L],
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
    true,
    None,
  ).unwrap()
  assert_true(
    physical_equal(
      @client_local_host.prepared_installed_managed_capture_acquisition(plan, 0).unwrap(),
      acquisition,
    ),
  )
  client_program_prepare_request_capture_module_body(parent, receipt, plan, None).unwrap()
  assert_true(
    physical_equal(
      client_program_preparation_borrow_read(holder).unwrap(),
      prepared,
    ),
  )
  let copied = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "node-original-capture-plan",
  ).unwrap()
  assert_true(
    client_program_adopt_request_capture_preparation(parent, copied)
    is Err(ForeignOriginal),
  )
  let run = client_program_adopt_request_capture_preparation(parent, request).unwrap()
  let compilation = @client_local_host.installed_managed_run_compilation_original(
    run, prepared,
  ).unwrap()
  assert_true(
    physical_equal(
      @client_local_host.installed_managed_run_compilation_original(
        run, prepared,
      ).unwrap(),
      compilation,
    ),
  )
  assert_true(
    physical_equal(
      @client_local_host.installed_managed_capture_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  let read = @client_local_host.begin_installed_managed_capture_read(run, 0).unwrap()
  @client_local_host.retire_installed_source_read(read).unwrap()
  assert_true(
    @client_local_host.retire_installed_managed_run(run) is Err(CleanupPending),
  )
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  assert_true(client_program_preparation_borrow_return(holder).unwrap())
  @client_local_host.retire_installed_managed_run(run).unwrap()
  assert_true(client_program_preparation_borrow_read(holder) is None)
}

///|
test "actual Request capture bridge rejects changed inventory query-time and original input without replacement" {
  let (parent, receipt, holder, prepared, request, captures, _, contracts) = request_capture_bridge_fixture()
  let assets = @publication_host.client_local_product_assets()
  assert_true(
    client_program_installed_managed_capture_plan_prepare(
      prepared,
      request,
      [],
      [4096L],
      [2048L],
      contracts,
      assets.values,
      Some(assets.fragment),
      None,
      true,
      None,
    )
    is Err(Unsupported),
  )
  assert_true(
    client_program_installed_managed_capture_plan_prepare(
      prepared,
      request,
      captures,
      [],
      [2048L],
      contracts,
      assets.values,
      Some(assets.fragment),
      None,
      true,
      None,
    )
    is Err(Unsupported),
  )
  // This original sample was not bound into the selected requirement. Its
  // presence must not be erased by forwarding a default None instead.
  let unbound = @publication_host.prepare_client_query_time(
    prepared, request, "2026-10-30T00:00:00.000Z",
  ).unwrap()
  assert_true(
    client_program_installed_managed_capture_plan_prepare(
      prepared,
      request,
      captures,
      [4096L],
      [2048L],
      contracts,
      assets.values,
      Some(assets.fragment),
      None,
      true,
      Some(unbound),
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    physical_equal(
      client_program_preparation_borrow_read(holder).unwrap(),
      prepared,
    ),
  )
  let plan = client_program_installed_managed_capture_plan_prepare(
    prepared,
    request,
    captures,
    [4096L],
    [2048L],
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
    true,
    None,
  ).unwrap()
  assert_true(
    client_program_prepare_request_capture_module_body(
      parent,
      request_diagnostic_test_receipt(),
      plan,
      None,
    )
    is Err(Preparation(Preparation(ForeignOriginal))),
  )
  client_program_prepare_request_capture_module_body(parent, receipt, plan, None).unwrap()
  assert_true(
    client_program_prepare_request_capture_module_body(parent, receipt, plan, None)
    is Err(Preparation(Preparation(WrongPhase))),
  )
  let run = client_program_adopt_request_capture_preparation(parent, request).unwrap()
  let compilation = @client_local_host.installed_managed_run_compilation_original(
    run, prepared,
  ).unwrap()
  assert_true(
    physical_equal(
      @client_local_host.installed_managed_run_compilation_original(
        run, prepared,
      ).unwrap(),
      compilation,
    ),
  )
  assert_true(
    client_program_adopt_request_capture_preparation(parent, request)
    is Err(ForeignOriginal),
  )
  assert_false(client_program_preparation_borrow_return(holder).unwrap())
  assert_true(client_program_preparation_borrow_read(holder) is None)
  @client_local_host.retire_installed_managed_run(run).unwrap()
}
