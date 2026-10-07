// Actual Native acquisition/capture/Compute boundaries; publication transport is separate.

///|
let resident_compute_query_contract : String =
  #|{"version":"actql-query-acquisition-contract/0.1","scope":"exclusive_finite_relation_scan_filter_select","dependencies":{"canonical_value_contract":{"path":"spec/contracts/actql-protocol-schemas.json","pointer":"/schemas/canonical_value_contract","cid":"sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551"},"consumer_capacity":{"path":"spec/contracts/actql-consumer-capacity.json","pointer":"","cid":"sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f"}},"schemas":{"requirement":{"type":"object","additionalProperties":false,"required":["version","owner","source_ref","source_contract_cid","input_contract_cid","output_contract_cid","request","parameter_values_cid","filter","select","source_validation","source_order_cid","logical_guards"],"properties":{"version":{"const":"actql-query-acquisition/0.1"},"owner":{"type":"object","additionalProperties":false,"required":["program_source_cid","stage","input"],"properties":{"program_source_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"stage":{"type":"string","minLength":1},"input":{"type":"string","minLength":1}}},"source_ref":{"type":"string","minLength":1},"source_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"input_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"output_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"request":{"type":"object"},"parameter_values_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"filter":{"type":"object","additionalProperties":false,"required":["occurrence","expression_cid"],"properties":{"occurrence":{"type":"string","pattern":"^/steps/(0|[1-9][0-9]*)/(filter|select)$"},"expression_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"select":{"type":"object","additionalProperties":false,"required":["occurrence","fields"],"properties":{"occurrence":{"type":"string","pattern":"^/steps/(0|[1-9][0-9]*)/(filter|select)$"},"fields":{"type":"array","minItems":1,"items":{"type":"object","additionalProperties":false,"required":["input","output"],"properties":{"input":{"type":"string","minLength":1},"output":{"type":"string","minLength":1}}}}}},"source_validation":{"type":"object","additionalProperties":false,"required":["scope","fields"],"properties":{"scope":{"const":"selected_scan"},"fields":{"type":"array","items":{"type":"string","minLength":1},"uniqueItems":true}}},"source_order_cid":{"anyOf":[{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},{"type":"null"}]},"logical_guards":{"type":"object","additionalProperties":false,"required":["max_rows","max_value_bytes"],"properties":{"max_rows":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_value_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}}},"$schema":"https://json-schema.org/draft/2020-12/schema"},"completed_observation":{"type":"object","additionalProperties":false,"required":["version","requirement_cid","owner","source_ref","source_contract_cid","parameter_values_cid","resolved_request_cid","snapshot","actual_access","coverage","output","retention"],"properties":{"version":{"const":"actql-query-observation/0.1"},"requirement_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"owner":{"type":"object","additionalProperties":false,"required":["program_source_cid","stage","input"],"properties":{"program_source_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"stage":{"type":"string","minLength":1},"input":{"type":"string","minLength":1}}},"source_ref":{"type":"string","minLength":1},"source_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"parameter_values_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"resolved_request_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"snapshot":{"anyOf":[{"type":"object","additionalProperties":false,"required":["contract_cid","token_cid"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"token_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},{"type":"null"}]},"actual_access":{"type":"object","additionalProperties":false,"required":["scope_cid","provider_scope_cid","received_rows","received_fields","received_bytes"],"properties":{"scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"provider_scope_cid":{"anyOf":[{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},{"type":"null"}]},"received_rows":{"type":"integer","minimum":0,"maximum":9007199254740991},"received_fields":{"type":"array","items":{"type":"string","minLength":1},"uniqueItems":true},"received_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"coverage":{"type":"object","additionalProperties":false,"required":["scope_cid","complete","source_validation_evidence_cid","filter_evidence_cid","select_evidence_cid"],"properties":{"scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"complete":{"const":true},"source_validation_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"filter_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"select_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"output":{"type":"object","additionalProperties":false,"required":["contract_cid","rows_cid","row_count"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"rows_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"row_count":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"retention":{"const":"process"}},"$schema":"https://json-schema.org/draft/2020-12/schema"}},"semantics":{"owner":"program_source_cid_is_authority_bearing_program_definition_cid_not_program_semantics_or_source_text_hash","derivation":"checked_exclusive_scan_filter_select_without_backend_cost_or_placement","capture":"completed_select_output_before_any_consumer","identity":"sha256_of_canonical_json_utf8_entire_body_no_self_cid","request_values":"bound_wire_values_no_reinterpretation_of_business_param_or_literal","parameter_identity":"existing_typed_parameter_values_projection_of_used_request_and_query_names","source_validation":"all_known_fields_of_selected_scan_before_filter_including_rows_excluded_by_filter","demand":"existing_checked_expression_demand_without_eager_undemanded_evaluation","native":"preserve_mandatory_admission_and_demanded_failures_before_projection","logical_guards":"max_rows_on_capture_output_max_value_bytes_on_admitted_records_and_demanded_roots","physical_budget":"actual_received_bytes_rows_and_retention_independent_of_logical_output","failure":"atomic_no_success_capture_or_consumer_on_failure_or_cancellation","evidence":"verify_actual_execution_evidence_not_candidate_coverage_proposals_or_self_cid_only","snapshot":"source_specific_no_universal_snapshot_token_or_isolation_requirement","retention":"same_process_immutable_completed_observation_not_durable_run_or_recovery","invocation":"existing_invocation_rules_retain_actual_observation_identity_not_result_identity_only"}}

///|
let resident_compute_query_evidence_contract : String =
  #|{"version":"actql-query-process-evidence-contract/0.1","dependencies":{"query_acquisition":{"path":"spec/contracts/actql-query-acquisition.json","pointer":"","cid":"sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1"}},"schemas":{"record":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["version","issuer","attempt","requirement_cid","role","snapshot","scan_scope_cid","actual_access","output"],"properties":{"version":{"const":"actql-query-process-evidence/0.1"},"issuer":{"type":"string","minLength":1},"attempt":{"type":"string","minLength":1},"requirement_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"role":{"enum":["source_validation","filter","select"]},"snapshot":{"anyOf":[{"type":"object","additionalProperties":false,"required":["contract_cid","token_cid"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"token_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},{"type":"null"}]},"scan_scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"actual_access":{"type":"object","additionalProperties":false,"required":["scope_cid","provider_scope_cid","received_rows","received_fields","received_bytes"],"properties":{"scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"provider_scope_cid":{"anyOf":[{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},{"type":"null"}]},"received_rows":{"type":"integer","minimum":0,"maximum":9007199254740991},"received_fields":{"type":"array","items":{"type":"string","minLength":1},"uniqueItems":true},"received_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"output":{"type":"object","additionalProperties":false,"required":["contract_cid","rows_cid","row_count"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"rows_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"row_count":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}}},"semantics":{"preimage":"entire_record_canonical_json_utf8_sha256_no_self_cid","authority":"authorized_host_private_issuer_and_live_opaque_success_handle_not_wire_or_cid_alone","issuance":"after_complete_scan_validation_filter_select_limits_and_immutable_output_retention","attempt":"host_allocated_unique_within_unique_process_issuer_never_reused_or_caller_selected","binding":"exact_requirement_attempt_snapshot_scan_scope_actual_access_and_retained_output_for_all_three_roles","native":"authorized_source_execution_covers_full_selected_scan_not_only_host_received_rows_or_columns","source_order":"null_only_in_this_profile_relative_order_is_not_total_order_evidence","lifetime":"same_process_no_deserialization_rehydration_or_durable_capture","host_adapter":"host_authorized_execution_with_owned_consistent_read_view_full_scan_validation_and_query_not_driver_location_or_sql_success","read_view":"private_task_session_transaction_binding_not_snapshot_token_no_cross_attempt_or_read_view_substitution","access_accounting":"engine_internal_scan_host_row_receipt_and_retention_are_distinct_auxiliary_row_receipts_are_not_hidden_or_double_counted","receipt_scope":"one_logical_received_sequence_only_independent_validation_and_query_receipts_require_an_additional_admitted_contract","scan_failure":"invalid_excluded_rows_still_fail_no_global_diagnostic_order_or_total_order_from_validation_traversal"}}

///|
let resident_compute_query_two_receipt_contract : String =
  #|{"version":"actql-query-two-receipt-contract/0.1","dependencies":{"query_acquisition":{"path":"spec/contracts/actql-query-acquisition.json","pointer":"","cid":"sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1"},"process_evidence":{"path":"spec/contracts/actql-query-process-evidence.json","pointer":"","cid":"sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89"}},"schemas":{"receipt":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["version","issuer","attempt","read_view","requirement_cid","snapshot","scan_scope_cid","role","received_rows_cid","received_rows","received_fields","received_bytes"],"properties":{"version":{"const":"actql-query-receipt/0.1"},"issuer":{"type":"string","minLength":1},"attempt":{"type":"string","minLength":1},"read_view":{"type":"string","minLength":1},"requirement_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"snapshot":{"anyOf":[{"type":"object","additionalProperties":false,"required":["contract_cid","token_cid"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"token_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},{"type":"null"}]},"scan_scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"role":{"enum":["validation_scan","native_result"]},"received_rows_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"received_rows":{"type":"integer","minimum":0,"maximum":9007199254740991},"received_fields":{"type":"array","uniqueItems":true,"items":{"type":"string","minLength":1}},"received_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"record":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["version","issuer","attempt","read_view","requirement_cid","snapshot","scan_scope_cid","role","accesses","output"],"properties":{"version":{"const":"actql-query-two-receipt-evidence/0.1"},"issuer":{"type":"string","minLength":1},"attempt":{"type":"string","minLength":1},"read_view":{"type":"string","minLength":1},"requirement_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"snapshot":{"anyOf":[{"type":"object","additionalProperties":false,"required":["contract_cid","token_cid"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"token_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},{"type":"null"}]},"scan_scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"role":{"enum":["source_validation","filter","select"]},"accesses":{"type":"object","additionalProperties":false,"required":["validation_scan_cid","native_result_cid"],"properties":{"validation_scan_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"native_result_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"output":{"type":"object","additionalProperties":false,"required":["contract_cid","rows_cid","row_count"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"rows_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"row_count":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}},"completed_observation":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["requirement_cid","owner","source_ref","source_contract_cid","parameter_values_cid","resolved_request_cid","snapshot","coverage","output","retention","version","evidence_contract_cid","execution","accesses"],"properties":{"requirement_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"owner":{"type":"object","additionalProperties":false,"required":["program_source_cid","stage","input"],"properties":{"program_source_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"stage":{"type":"string","minLength":1},"input":{"type":"string","minLength":1}}},"source_ref":{"type":"string","minLength":1},"source_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"parameter_values_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"resolved_request_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"snapshot":{"anyOf":[{"type":"object","additionalProperties":false,"required":["contract_cid","token_cid"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"token_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},{"type":"null"}]},"coverage":{"type":"object","additionalProperties":false,"required":["scope_cid","complete","source_validation_evidence_cid","filter_evidence_cid","select_evidence_cid"],"properties":{"scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"complete":{"const":true},"source_validation_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"filter_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"select_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"output":{"type":"object","additionalProperties":false,"required":["contract_cid","rows_cid","row_count"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"rows_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"row_count":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"retention":{"const":"process"},"version":{"const":"actql-query-two-receipt-observation/0.1"},"evidence_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"execution":{"type":"object","additionalProperties":false,"required":["issuer","attempt","read_view"],"properties":{"issuer":{"type":"string","minLength":1},"attempt":{"type":"string","minLength":1},"read_view":{"type":"string","minLength":1}}},"accesses":{"type":"object","additionalProperties":false,"required":["validation_scan_cid","native_result_cid"],"properties":{"validation_scan_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"native_result_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}}}}},"semantics":{"preimages":"entire_canonical_json_utf8_sha256_without_self_cid_receipts_then_records_then_observation","authority":"selected_contract_pins_and_authorized_host_private_issuer_live_task_read_view_and_immutable_retention_not_wire_alone","shape":"exactly_one_validation_scan_receipt_then_one_native_result_receipt_no_extra_row_receipts","validation":"pinned_host_value_admission_of_all_known_fields_and_all_selected_scan_rows_before_native_filter_select","native":"checked_query_equivalent_ordered_output_not_sql_success_or_coercion_alone","binding":"both_receipts_all_three_records_and_observation_same_requirement_task_attempt_owned_consistent_read_view_and_applicable_snapshot","identity":"receipt_role_is_in_preimage_native_rows_equal_output_rows_without_merging_roles","accounting":"each_distinct_transfer_once_sum_received_rows_and_canonical_typed_wire_bytes_retention_copies_and_engine_work_separate","lifetime":"issue_all_only_after_successful_validation_query_budgets_and_retention_failure_or_cancellation_is_terminal_no_durable_capture","source_order":"null_only_preserve_input_relative_order_without_total_order_evidence","compatibility":"separate_observation_version_single_receipt_and_requirement_contracts_unchanged_no_admission_by_old_verifier"}}

///|
let resident_compute_document : String =
  #|{"id":"source-compute","results":{"answer":{"from":{"result":"r","stage":"compute"}}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]},{"id":"compute","inputs":{"x":{"result":{"result":"r","stage":"acquire"}}},"results":{"r":{"fields":["id"],"from":"out"}},"steps":[{"filter":"id > 2"},{"as":"out","select":["id"]}]}],"version":"actql/0.1"}

///|
fn resident_compute_prerequisites() -> (String, String)? {
  let library = @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY")
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT")
  match (library, root) {
    (Some(library), Some(root)) if library != "" && root != "" =>
      Some((library, root))
    _ => {
      if @env.get_env_var("ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS") == Some("1") {
        abort(
          "resident Source Compute requires Native DuckDB and owned scratch",
        )
      }
      None
    }
  }
}

///|
fn resident_compute_prepared(
  document? : String = resident_compute_document,
) -> @host.PreparedClientProgram {
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn resident_compute_configuration(
  library : @duckdb.Library,
  path : String,
  import_rows? : Int = 10,
) -> @resident.ResidentSourceComputeConfiguration {
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  {
    source: {
      retained_output_root: None,
      source_ref: "connector://crm/main/r#v",
      source_contract_cid: "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
      library,
      database_path: path,
      memory_bytes: 134217728L,
      database_schema: "main",
      table: "records",
      query_contract_body: resident_compute_query_contract,
      evidence_contract_body: resident_compute_query_evidence_contract,
      two_receipt_contract_body: resident_compute_query_two_receipt_contract,
      fragment_contract_body: resident_effect_source_fragment,
      ledger: {
        planning_work: 10000,
        attempts: 10,
        holdings: 10,
        transfer_bytes: 1000000L,
        retained_bytes: 1073741824L,
        execution_bytes: 1073741824L,
      },
    },
    registry_body: resident_effect_source_registry,
    values_body: resident_effect_source_values,
    dispatch: {
      input_entries: 100,
      input_name_bytes: 10000,
      candidate_work: 100,
      join_validation: { max_rows: 100, max_work: 1000, max_entries: 1000, },
      capacity: {
        contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
        max_rows: 100,
        max_value_bytes: 10000,
        common_fragment: None,
      },
      local_execution: {
        rows: {
          max_rows: 100,
          metadata_entries: 10000,
          retained_entries: 10000,
          operation_entries: 10000,
          input_values: values,
          output_values: values,
        },
        max_work: 100000,
        max_frames: 100,
      },
      guards: {
        max_work: 10000,
        max_bytes: 10000,
        max_nodes: 10000,
        max_depth: 100,
      },
      native_query: {
        max_entries: 100,
        max_sql_bytes: 10000,
        expressions: {
          max_nodes: 1000,
          max_work: 10000,
          max_depth: 100,
          max_literal_nodes: 1000,
          max_literal_text_bytes: 10000,
        },
      },
      native: {
        values: {
          max_work: 1000,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        demand: {
          max_work: 1000,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        physical: {
          max_rows: 100,
          max_cells: 1000,
          max_nodes: 1000,
          max_text_bytes: 10000,
        },
        retention: values,
        metadata_work: 1000,
        completion_entries: 100,
        completion_name_bytes: 1000,
      },
      transport: {
        max_bytes: 100000,
        max_nodes: 10000,
        max_columns: 10,
        max_rows: 100,
        max_text_bytes: 100000,
      },
    },
    estimates: [
      {
        local_rates: [
          {
            work_slots: [0, 1, 2, 3, 4],
            fixed_ms: Some(1000L),
            per_row_ms: Some(0L),
            per_wire_byte_ms: Some(0L),
            per_pair_ms: Some(0L),
          },
        ],
        native_rates: [
          {
            work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
            fixed_ms: Some(10L),
            per_row_ms: Some(0L),
            per_wire_byte_ms: Some(0L),
            per_pair_ms: Some(0L),
          },
        ],
        // The chosen envelope includes the engine and bounded decoding scratch.
        native_capacity: {
          transfer_bytes: 100000L,
          retained_bytes: 4000000L,
          execution_bytes: 268435456L,
        },
        output_rows_per_mille: Some(1000),
      },
    ],
    search: {
      max_offers: 6,
      max_strategies: 8,
      max_work: 10000,
      max_revisions: 4,
    },
    imports: {
      max_rows: import_rows,
      max_cells: 40,
      max_parameters: 8,
      max_sql_bytes: 10000,
      max_batch_rows: 2,
    },
    transfer_bytes: 100000L,
    execution_bytes: 134217728L,
    retained: None,
  }
}

///|
fn resident_compute_database(
  library : @duckdb.Library,
  path : String,
) -> Unit raise {
  let database = library
    .open_database(@duckdb.restricted_open_limits(134217728L), path~)
    .unwrap()
  for
    sql in [
      "CREATE TABLE records(id DOUBLE, amount DOUBLE)", "INSERT INTO records VALUES (3, NULL), (1, 11), (2, 22)",
    ] {
    let query = database.stream_query(sql, 1, 1L, 1, 256).unwrap()
    while query.next().unwrap() is Some(_) {

    }
    assert_true(query.close())
  }
  database.close()
}

///|
fn resident_compute_limits() -> @host.PublicationOutputExportLimits {
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 100,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  {
    max_result_fields: 10,
    max_result_mapping_work: 100,
    max_result_order_work: 100,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values: {
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_depth: 20,
      max_work: 10000,
    },
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    max_batch_bytes: 64,
  }
}

///|
fn resident_compute_reclaim(
  root : @filesystem.Root,
  name : String,
) -> Unit raise {
  let generation = root.inspect_generation(name).unwrap().unwrap()
  root.reclaim_generation(name, generation).unwrap()
  root.sync_directory().unwrap()
  assert_eq(root.inspect_generation(name).unwrap(), None)
}

///|
test "resident captured Source reaches its exact second Compute and Named Result once" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-compute-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let prepared = resident_compute_prepared()
  assert_eq(
    @strategy.graph_task_count(@host.prepared_client_graph(prepared)),
    2,
  )
  // The original prepared graph still exposes the remote held-input gap.
  assert_true(
    @host.prepare_client_task_input_binding(prepared, 1) is Err(UnsupportedTask),
  )
  let owner = resident_compute_open(
    prepared,
    resident_compute_configuration(library, path),
    name,
  )
  assert_true(owner.usage().held_bytes > 0L)
  assert_true(owner.usage().reserved_execution_bytes >= 134217728L)
  assert_true(owner.execute_task(0) is Err(Unavailable))
  // Remove only this fixture's physical pathname after capture. The consumer
  // must use the captured producer, not reopen the configured Source file.
  resident_compute_reclaim(root, name)
  let completion = resident_compute_execute(owner)
  assert_eq(completion.task, 1)
  assert_eq(owner.usage().attempts, 2)
  assert_true(owner.execute_task(1) is Err(Unavailable))
  let output = owner.prepare_result_export(resident_compute_limits()).unwrap()
  let body = StringBuilder()
  while output.next().unwrap() is Some(chunk) {
    body.write_string(chunk)
  }
  body.write_string(output.finish().unwrap())
  assert_eq(body.to_string(), "[{\"id\":3}]")
  assert_eq(output.result_fields().unwrap(), ["id"])
  assert_eq(output.row_count().unwrap(), 1)
  // Canonical schema maps sort keys; the declared numeric field is non-null.
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  output.cancel()
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  assert_eq(owner.usage().attempts, 2)
}

///|
test "resident captured Source cancellation closes input without starting Compute" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-cancel-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let owner = resident_compute_open(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    name,
  )
  assert_true(owner.usage().held_bytes > 0L)
  assert_true(owner.close())
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_true(owner.close())
  assert_eq(owner.usage().attempts, 1)
  assert_eq(owner.usage().held_bytes, 0L)
  resident_compute_reclaim(root, name)
}

///|
test "resident captured Source survives consumer failure until its existing cleanup owner closes" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-failure-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let owner = resident_compute_open(
    resident_compute_prepared(),
    resident_compute_configuration(library, path, import_rows=1),
    name,
  )
  assert_true(owner.execute_task(1) is Err(Compute(_)))
  let failed = owner.usage()
  assert_true(failed.held_bytes > 0L)
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_eq(owner.usage().attempts, failed.attempts)
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_transfer_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  resident_compute_reclaim(root, name)
}

///|
test "resident captured Source retains capacity while a publication reader pins its result" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-pinned-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let owner = resident_compute_open(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    name,
  )
  resident_compute_execute(owner) |> ignore
  let output = owner.prepare_result_export(resident_compute_limits()).unwrap()
  assert_true(owner.usage().reserved_execution_bytes >= 134217728L)
  assert_false(owner.close())
  let pending = owner.usage()
  assert_true(pending.held_bytes > 0L)
  // Physical databases have stopped; the reader's retained allocation remains.
  assert_eq(pending.reserved_execution_bytes, 0L)
  assert_false(owner.close())
  assert_eq(owner.usage().held_bytes, pending.held_bytes)
  assert_eq(owner.usage().attempts, pending.attempts)
  output.cancel()
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(owner.usage().held_bytes, 0L)
  resident_compute_reclaim(root, name)
}

///|
test "resident captured Source rejects trusted identity mismatch before acquisition IO" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-absent-" + @env.now().to_string() + ".duckdb"
  let root = @filesystem.open_root(root_path).unwrap()
  let configuration = resident_compute_configuration(
    library,
    root_path + "/" + name,
  )
  let foreign = {
    ..configuration,
    source: { ..configuration.source, source_ref: "connector://crm/other/r#v", },
  }
  let (issue, cleanup) = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    foreign,
    name,
  ).unwrap_err()
  assert_true(issue is Source(ForeignInput))
  assert_true(
    @output.native_remote_standard_input_failure_cleanup_pending(cleanup),
  )
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
  )
  assert_eq(root.inspect_generation(name).unwrap(), None)
}

///|
test "resident captured Source reserves engine capacity before acquisition IO" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "source-capacity-" + @env.now().to_string() + ".duckdb"
  let root = @filesystem.open_root(root_path).unwrap()
  let configuration = resident_compute_configuration(
    library,
    root_path + "/" + name,
  )
  let bounded = {
    ..configuration,
    source: {
      ..configuration.source,
      ledger: { ..configuration.source.ledger, execution_bytes: 0L, },
    },
  }
  let (issue, cleanup) = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    bounded,
    name,
  ).unwrap_err()
  assert_true(issue is Capacity(ExecutionLimit))
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
  )
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
  )
  assert_eq(root.inspect_generation(name).unwrap(), None)
}

///|
fn resident_compute_open(
  prepared : @host.PreparedClientProgram,
  config : @resident.ResidentSourceComputeConfiguration,
  occurrence : String,
) -> @resident.ResidentSourceCompute raise {
  match @resident.open_resident_source_compute(prepared, config, occurrence) {
    Ok(owner) => owner
    Err((issue, cleanup)) => {
      assert_true(
        @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
      )
      let label = match issue {
        UnsupportedGraph => "unsupported graph"
        Unavailable => "unavailable"
        Source(Query(_)) => "Source query"
        Source(Acquisition(_)) => "Source acquisition preparation"
        Source(Binding(_)) => "Source binding"
        Source(_) => "Source identity"
        Acquisition(_) => "physical acquisition open"
        Execution(_) => "physical acquisition execution"
        Capture => "capture"
        RetainedInput(_) => "retained input"
        Run(_) => "captured Run"
        Dispatch(_) => "standard dispatch"
        Compute(_) => "Native compute open"
        Export(_) => "export"
        Capacity(RetentionLimit) => "Source retention limit"
        Capacity(ExecutionLimit) => "Source execution limit"
        Capacity(_) => "capacity"
        ObservationUnrecorded(_) => "observation"
      }
      fail("resident Source Compute preparation failed: " + label)
    }
  }
}

///|
fn resident_compute_execute(
  owner : @resident.ResidentSourceCompute,
) -> @duckdb_native.NativeStandardStrategyTaskCompletion raise {
  match owner.execute_task(1) {
    Ok(value) => value
    Err(issue) => {
      let label = match issue {
        Compute(Dispatch(_)) => "dispatch"
        Compute(Local(_)) => "Local"
        Compute(DuckDB(Start(Physical(ImportRows)))) => "DuckDB import rows"
        Compute(DuckDB(Start(Strategy(Physical(ExecutionLimit))))) =>
          "DuckDB start execution capacity"
        Compute(DuckDB(Start(Strategy(Physical(RetentionLimit))))) =>
          "DuckDB start retention capacity"
        Compute(DuckDB(Start(Strategy(Physical(InvalidCharge))))) =>
          "DuckDB start invalid charge"
        Compute(DuckDB(Start(Strategy(ActivationNotAuthorized)))) =>
          "DuckDB start activation"
        Compute(DuckDB(Start(Strategy(ForeignCandidate)))) =>
          "DuckDB start candidate"
        Compute(DuckDB(Start(Strategy(Compute(_))))) =>
          "DuckDB start compute binding"
        Compute(DuckDB(Start(Strategy(_)))) => "DuckDB start strategy"
        Compute(DuckDB(Start(Physical(_)))) => "DuckDB start physical"
        Compute(DuckDB(Execution(failure))) =>
          match failure.primary {
            Strategy(_) => "DuckDB execution strategy"
            Physical(Compute(_)) => "DuckDB execution Compute"
            Physical(Runtime(_)) => "DuckDB execution runtime"
            Physical(ImportRows) => "DuckDB execution import rows"
            Physical(_) => "DuckDB execution physical"
            Settlement(_) => "DuckDB execution settlement"
            MissingOutput => "DuckDB missing output"
          }
        Compute(DuckDB(_)) => "DuckDB"
        Compute(Database(_)) => "database"
        Compute(DuckDBUnavailable) => "DuckDB unavailable"
        Compute(InvalidSelection) => "selection"
        Compute(Closed) => "closed"
        _ => "unavailable"
      }
      ignore(owner.close())
      fail("resident consumer failed: " + label)
    }
  }
}
