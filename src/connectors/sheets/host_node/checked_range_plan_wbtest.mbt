// Existing public rangeProgram and original standard contracts. Checking and
// quotation only: no Source I/O, Host, Ledger, provider or ordinary acceptance.

///|
let sheets_checked_plan_registry : String =
  #|{"REL.select":{"inputs":["relation"],"output":"relation"},"REL.where":{"inputs":["relation"],"output":"relation"},"REL.assert_all":{"inputs":["relation"],"output":"relation"},"REL.assert_unique":{"inputs":["relation"],"output":"relation"},"REL.derive":{"inputs":["relation"],"output":"relation","execution_extensions":{"ordered_bindings":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.derive.ordered","cid":"sha256:00a8fa5a08e8d02ef2e2864deb77be1b6a637d0f7f78d7cfa7b5ec9555573b29"}}},"REL.orderByStable":{"inputs":["relation"],"output":"relation"},"REL.limit":{"inputs":["relation"],"output":"relation"},"REL.topk":{"inputs":["relation"],"output":"relation"},"REL.window.fixed":{"inputs":["relation"],"output":"relation"},"REL.window.sliding":{"inputs":["relation"],"output":"relation"},"REL.window.project":{"inputs":["relation"],"output":"relation"},"REL.window.lag":{"inputs":["relation"],"output":"relation"},"REL.watermark":{"inputs":["relation"],"output":"relation"},"REL.pivot":{"inputs":["relation"],"output":"relation"},"REL.unpivot":{"inputs":["relation"],"output":"relation"},"REL.unnest":{"inputs":["relation"],"output":"relation"},"REL.dedupeRows":{"inputs":["relation"],"output":"relation"},"REL.json.pick":{"inputs":["relation"],"output":"relation"},"REL.join":{"inputs":["relation","relation"],"output":"relation"},"REL.groupBy":{"inputs":["relation"],"output":"relation"},"REL.distinct":{"inputs":["relation"],"output":"relation"},"REL.unionAll":{"inputs":["relation","relation"],"output":"relation"},"REL.except_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.intersect_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.cross_join":{"inputs":["relation","relation"],"output":"relation"},"REL.topk_partitioned":{"inputs":["relation"],"output":"relation"},"REL.analytic":{"inputs":["relation"],"output":"relation"},"SGA.normalize":{"inputs":["graph"],"output":"graph"},"SGA.reachable":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.bounds_check":{"inputs":["graph"],"output":"relation"},"SGA.degree_metrics":{"inputs":["graph"],"output":"relation"},"SGA.apply_delta":{"inputs":["graph","relation"],"output":"graph"},"SGA.diff":{"inputs":["graph","graph"],"output":"relation"},"SGA.graft":{"inputs":["graph","graph"],"output":"graph"},"SGA.union_structural":{"finite_inputs":{"repeated_input":"graph","minimum_inputs":2},"output":"graph"},"SGA.diff_structural":{"inputs":["graph","graph"],"output":"graph"},"SGA.match_nodes":{"inputs":["graph"],"output":"relation"},"SGA.match_edges":{"inputs":["graph"],"output":"relation"},"SGA.traverse":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.shortest_path":{"input_alternatives":[["graph"],["graph","relation"],["graph","relation","relation"]],"output":"relation"},"SGA.components":{"inputs":["graph"],"output":"relation"},"SGA.subgraph":{"input_alternatives":[["graph"],["graph","relation"]],"output":"graph"},"SGA.equal":{"inputs":["graph","graph"],"output":"relation"},"SGA.mean_structural":{"finite_inputs":{"repeated_input":"graph","minimum_inputs":1},"output":"graph"},"TEA.window.fixed_label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.sliding_assign":{"inputs":["event_stream"],"output":"event_stream"},"TEA.watermark.label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.session_assign":{"inputs":["event_stream"],"output":"event_stream"},"TEA.dedupe":{"inputs":["event_stream"],"output":"event_stream"},"TEA.join.asof":{"inputs":["event_stream","relation"],"output":"relation"},"TEA.sequence.match":{"inputs":["event_stream"],"output":"relation"},"TEA.time_series":{"inputs":[],"output":"relation"},"TEA.join.interval":{"inputs":["relation","relation"],"output":"relation"},"VEC.normalize_l2":{"inputs":["vector_set"],"output":"vector_set"},"VEC.score_sort":{"inputs":["vector_set"],"output":"vector_set"},"VEC.knn_join":{"inputs":["vector_set","vector_set"],"output":"relation"},"VEC.pool":{"inputs":["vector_set"],"output":"vector_set"},"VEC.merge_rankings":{"policy_inputs":{"max":{"inputs":["relation","relation"]},"weighted_sum":{"inputs":["relation","relation"]},"rrf":{"repeated_input":"relation","minimum_inputs":2}},"output":"relation"},"BRIDGE.graph.to_edge_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.graph.to_node_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.rows.to_graph":{"finite_inputs":{"repeated_input":"relation","minimum_inputs":0},"output":"graph","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/BRIDGE.rows.to_graph","cid":"sha256:0979999a64bb47f7fcb0d113c0bbcab592ad0a268b548a8776f8fac4fd6f6d84"}},"BRIDGE.events.to_rows":{"inputs":["event_stream"],"output":"relation"},"BRIDGE.rows.to_events":{"inputs":["relation"],"output":"event_stream"},"BRIDGE.vectors.to_rows":{"inputs":["vector_set"],"output":"relation"},"BRIDGE.rows.to_vectors":{"inputs":["relation"],"output":"vector_set"},"EFFECT.plan":{"inputs":["relation"],"output":"relation"},"REL.values":{"inputs":[],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.values","cid":"sha256:96c7925a693801dcb3bce9f3e2da9b4fd9ed39e517af90cbac0e1adbee5ad2ae"}},"ACTQL.expression_fragment/0.1":{"inputs":["relation"],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/ACTQL.expression_fragment~10.1","cid":"sha256:ced7ee00f232f8d5bcfde44dfc769d9d6ae02c8386e54db7d844d43f922bac90"}},"TEA.calendar.bucket":{"inputs":["relation"],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/TEA.calendar.bucket","cid":"sha256:8cbb70e4edcd1dd29deee777b44b3f09b9cee337b5495944ca895fa3065b6227"}},"TEA.calendar.series":{"inputs":[],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/TEA.calendar.series","cid":"sha256:8070a5fa9b6177df0d407b474a2b34aff2ecde9cf9c5b726191f7bd908a4dc83"}}}

///|
let sheets_checked_plan_values : String =
  #|{"version":"actql-rel-values-execution/0.1","operation":"REL.values","inputs":[],"output":"relation","dependencies":{"canonical_value_contract":{"path":"spec/contracts/actql-protocol-schemas.json","pointer":"/schemas/canonical_value_contract","cid":"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1"}},"params_schema":{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://smooth.dev/schemas/actql/rel-values-params-0.1.json","type":"object","additionalProperties":false,"required":["schema","rows"],"properties":{"schema":{"type":"object","minProperties":1,"propertyNames":{"pattern":"^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"},"additionalProperties":{"$ref":"#/$defs/value_contract"}},"rows":{"type":"array","items":{"type":"object","additionalProperties":{"$ref":"#/$defs/wire_value"}}}},"$defs":{"value_contract":{"oneOf":[{"type":"object","additionalProperties":false,"required":["type","nullable","precision","scale"],"properties":{"type":{"const":"decimal"},"nullable":{"type":"boolean"},"precision":{"type":"integer","minimum":1,"maximum":38},"scale":{"type":"integer","minimum":0,"maximum":38}},"allOf":[{"if":{"properties":{"precision":{"const":1}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":1}}}},{"if":{"properties":{"precision":{"const":2}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":2}}}},{"if":{"properties":{"precision":{"const":3}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":3}}}},{"if":{"properties":{"precision":{"const":4}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":4}}}},{"if":{"properties":{"precision":{"const":5}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":5}}}},{"if":{"properties":{"precision":{"const":6}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":6}}}},{"if":{"properties":{"precision":{"const":7}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":7}}}},{"if":{"properties":{"precision":{"const":8}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":8}}}},{"if":{"properties":{"precision":{"const":9}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":9}}}},{"if":{"properties":{"precision":{"const":10}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":10}}}},{"if":{"properties":{"precision":{"const":11}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":11}}}},{"if":{"properties":{"precision":{"const":12}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":12}}}},{"if":{"properties":{"precision":{"const":13}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":13}}}},{"if":{"properties":{"precision":{"const":14}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":14}}}},{"if":{"properties":{"precision":{"const":15}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":15}}}},{"if":{"properties":{"precision":{"const":16}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":16}}}},{"if":{"properties":{"precision":{"const":17}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":17}}}},{"if":{"properties":{"precision":{"const":18}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":18}}}},{"if":{"properties":{"precision":{"const":19}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":19}}}},{"if":{"properties":{"precision":{"const":20}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":20}}}},{"if":{"properties":{"precision":{"const":21}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":21}}}},{"if":{"properties":{"precision":{"const":22}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":22}}}},{"if":{"properties":{"precision":{"const":23}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":23}}}},{"if":{"properties":{"precision":{"const":24}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":24}}}},{"if":{"properties":{"precision":{"const":25}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":25}}}},{"if":{"properties":{"precision":{"const":26}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":26}}}},{"if":{"properties":{"precision":{"const":27}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":27}}}},{"if":{"properties":{"precision":{"const":28}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":28}}}},{"if":{"properties":{"precision":{"const":29}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":29}}}},{"if":{"properties":{"precision":{"const":30}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":30}}}},{"if":{"properties":{"precision":{"const":31}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":31}}}},{"if":{"properties":{"precision":{"const":32}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":32}}}},{"if":{"properties":{"precision":{"const":33}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":33}}}},{"if":{"properties":{"precision":{"const":34}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":34}}}},{"if":{"properties":{"precision":{"const":35}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":35}}}},{"if":{"properties":{"precision":{"const":36}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":36}}}},{"if":{"properties":{"precision":{"const":37}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":37}}}},{"if":{"properties":{"precision":{"const":38}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":38}}}}]},{"type":"object","additionalProperties":false,"required":["type","nullable"],"properties":{"type":{"const":"string"},"nullable":{"type":"boolean"},"min_length":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_codepoints":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_utf8_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991},"enum":{"type":"array","items":{"type":"string"}}}},{"type":"object","additionalProperties":false,"required":["type","nullable"],"properties":{"type":{"enum":["number","boolean","timestamp","date"]},"nullable":{"type":"boolean"}}},{"type":"object","additionalProperties":false,"required":["type","nullable","items"],"properties":{"type":{"const":"array"},"nullable":{"type":"boolean"},"items":{"$ref":"#/$defs/value_contract"},"max_items":{"type":"integer","minimum":0,"maximum":9007199254740991}}},{"type":"object","additionalProperties":false,"required":["type","nullable","additional_properties","fields"],"properties":{"type":{"const":"object"},"nullable":{"type":"boolean"},"additional_properties":{"const":false},"fields":{"type":"object","propertyNames":{"pattern":"^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"},"additionalProperties":{"$ref":"#/$defs/value_contract"}}}},{"type":"object","additionalProperties":false,"required":["type","nullable","dimensions","element_type"],"properties":{"type":{"const":"vector"},"nullable":{"type":"boolean"},"dimensions":{"type":"integer","minimum":1},"element_type":{"const":"f32"}}},{"type":"object","required":["type","nullable"],"additionalProperties":false,"properties":{"type":{"const":"int64"},"nullable":{"type":"boolean"}}}]},"wire_value":{"oneOf":[{"type":["null","boolean","number","string"]},{"type":"array","items":{"$ref":"#/$defs/wire_value"}},{"type":"object","additionalProperties":{"$ref":"#/$defs/wire_value"}}]}}},"semantics":{"schema_form":"nonempty_field_map_of_complete_checked_constructible_contracts","cells":"bound_typed_wire_values_without_cell_wrappers","quotation":"remove_exact_singleton_literal_once_before_execution_params","parameter_resolution":"resolve_only_authored_cell_root_holes_before_execution_params","business_objects":"never_reinterpret_param_or_literal_members","row_fields":"exact_declared_set_including_nullable_fields","values":"recursive_declared_type_admission_without_cast_repair_or_rounding","strings":"preserve_well_formed_unicode_scalar_sequence_without_NFC_or_line_break_repair","object_member_names":"NFC_then_LF_reject_noncanonical_names_and_collisions","string_extents":"retained_unicode_scalars_and_UTF8_bytes","text_enumeration":"exact_original_vector_membership_intersected_with_retained_extents_preserve_nullable_and_empty_duplicates_order_no_constraint_stripping_or_authority","decimal":"canonical_fixed_scale_string_under_declared_precision_and_scale","int64":"canonical_signed_decimal_String_in_full_signed64_range_distinct_logical_type_no_JSON_Number_or_implicit_coercion","empty_rows":"retain_declared_schema","row_order":"retain_occurrence_order","row_multiplicity":"retain_all_occurrences","object_key_order":"canonical_utf16_order_not_row_order","publication":"validate_all_rows_and_resolved_limits_before_publication","recursive_resources":{"selected_root_types":["array","object","vector"],"bytes":"sum_canonical_typed_wire_cell_bytes_across_all_occurrences_including_null_without_double_counting_nested_containers","byte_exclusions":["scalar_typed_cells","row_keys","row_wrappers","rows_wrapper","schema"],"host_byte_ceiling":"max_nested_value_bytes","depth":"declared_cell_type_scalar_0_vector_1_array_1_plus_items_object_1_plus_max_fields","depth_excludes":["row_wrapper","rows_wrapper"],"host_depth_ceiling":"max_nested_value_depth","empty_or_null":"type_depth_still_checked_zero_selected_cells_have_zero_bytes","failure":"atomic_before_any_consumer_without_truncation"},"unsupported_backend":"reject_runnable_plan_without_exact_registered_contract_support"}}

///|
let sheets_checked_plan_fragment : String =
  #|{"version":"actql-expression-fragment-execution/0.1","operation":"ACTQL.expression_fragment/0.1","inputs":["relation"],"output":"relation","dependencies":{"expression_contract":{"file":"spec/contracts/actql-expressions.json","pointer":"","cid":"sha256:2849a6667980fc51ed51a04879470a97068fd08e358d784262602a09b22dacda"},"fragment_schema":{"file":"spec/contracts/actql-expressions.json","pointer":"/schemas/fragment","cid":"sha256:be96b6072058cb165d5350a2575403a4fe35bafc229e669ca296aacc0ca79cdf"}},"params_schema":{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"urn:actql:expression-fragment-params:0.1","type":"object","additionalProperties":false,"required":["fragment"],"properties":{"fragment":{"$ref":"urn:actql:expression-fragment:0.1"}}},"semantics":{"schema_resolution":"resolve_fragment_schema_from_exact_pinned_dependency_without_network_lookup","local_source":"exactly_one_request_pipeline_source_named_input","admission":"regenerate_and_compare_sealed_fragment_under_pinned_expression_contract_before_evaluation","fragment_identity":"hash_complete_canonical_fragment_excluding_only_root_fragment_cid","retained_material":"retain_opcode_and_complete_fragment_in_canonical_composition","inner_graph":"not_a_standalone_execution_artifact","carrier_projection":"validation_witness_only_never_hashed_executed_or_used_as_type_evidence","obligations":"enforce_fragment_input_root_output_limits_demands_and_runtime_checks","backend":"reject_execution_without_support_for_exact_contract_and_all_used_extensions","authority":"registration_does_not_establish_program_completion_or_execution_permission"}}

///|
let sheets_checked_plan_query : String =
  #|{"version":"actql-query-acquisition-contract/0.1","scope":"exclusive_finite_relation_scan_filter_select","dependencies":{"canonical_value_contract":{"path":"spec/contracts/actql-protocol-schemas.json","pointer":"/schemas/canonical_value_contract","cid":"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1"},"consumer_capacity":{"path":"spec/contracts/actql-consumer-capacity.json","pointer":"","cid":"sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f"}},"schemas":{"requirement":{"type":"object","additionalProperties":false,"required":["version","owner","source_ref","source_contract_cid","input_contract_cid","output_contract_cid","request","parameter_values_cid","filter","select","source_validation","source_order_cid","logical_guards"],"properties":{"version":{"const":"actql-query-acquisition/0.1"},"owner":{"type":"object","additionalProperties":false,"required":["program_source_cid","stage","input"],"properties":{"program_source_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"stage":{"type":"string","minLength":1},"input":{"type":"string","minLength":1},"run_definition_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"source_ref":{"type":"string","minLength":1},"source_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"input_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"output_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"request":{"type":"object"},"parameter_values_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"filter":{"type":"object","additionalProperties":false,"required":["occurrence","expression_cid"],"properties":{"occurrence":{"type":"string","pattern":"^/steps/(0|[1-9][0-9]*)/(filter|select)$"},"expression_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"select":{"type":"object","additionalProperties":false,"required":["occurrence","fields"],"properties":{"occurrence":{"type":"string","pattern":"^/steps/(0|[1-9][0-9]*)/(filter|select)$"},"fields":{"type":"array","minItems":1,"items":{"type":"object","additionalProperties":false,"required":["input","output"],"properties":{"input":{"type":"string","minLength":1},"output":{"type":"string","minLength":1}}}}}},"source_validation":{"type":"object","additionalProperties":false,"required":["scope","fields"],"properties":{"scope":{"const":"selected_scan"},"fields":{"type":"array","items":{"type":"string","minLength":1},"uniqueItems":true}}},"source_order_cid":{"anyOf":[{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},{"type":"null"}]},"logical_guards":{"type":"object","additionalProperties":false,"required":["max_rows","max_value_bytes"],"properties":{"max_rows":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_value_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}}},"$schema":"https://json-schema.org/draft/2020-12/schema"},"completed_observation":{"type":"object","additionalProperties":false,"required":["version","requirement_cid","owner","source_ref","source_contract_cid","parameter_values_cid","resolved_request_cid","snapshot","actual_access","coverage","output","retention"],"properties":{"version":{"const":"actql-query-observation/0.1"},"requirement_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"owner":{"type":"object","additionalProperties":false,"required":["program_source_cid","stage","input"],"properties":{"program_source_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"stage":{"type":"string","minLength":1},"input":{"type":"string","minLength":1},"run_definition_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"source_ref":{"type":"string","minLength":1},"source_contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"parameter_values_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"resolved_request_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"snapshot":{"anyOf":[{"type":"object","additionalProperties":false,"required":["contract_cid","token_cid"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"token_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},{"type":"null"}]},"actual_access":{"type":"object","additionalProperties":false,"required":["scope_cid","provider_scope_cid","received_rows","received_fields","received_bytes"],"properties":{"scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"provider_scope_cid":{"anyOf":[{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},{"type":"null"}]},"received_rows":{"type":"integer","minimum":0,"maximum":9007199254740991},"received_fields":{"type":"array","items":{"type":"string","minLength":1},"uniqueItems":true},"received_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"coverage":{"type":"object","additionalProperties":false,"required":["scope_cid","complete","source_validation_evidence_cid","filter_evidence_cid","select_evidence_cid"],"properties":{"scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"complete":{"const":true},"source_validation_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"filter_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"select_evidence_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},"output":{"type":"object","additionalProperties":false,"required":["contract_cid","rows_cid","row_count"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"rows_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"row_count":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"retention":{"const":"process"}},"$schema":"https://json-schema.org/draft/2020-12/schema"}},"semantics":{"owner":"program_source_cid_is_authority_bearing_program_definition_cid_not_program_semantics_or_source_text_hash","query_time_owner":"declared_query_time_dependency_requires_original_admitted_run_definition_cid_in_requirement_and_completed_observation_owner_with_same_nominal_context_and_saved_run_no_resample_no_grant","derivation":"checked_exclusive_scan_filter_select_without_backend_cost_or_placement","capture":"completed_select_output_before_any_consumer","identity":"sha256_of_canonical_json_utf8_entire_body_no_self_cid","request_values":"bound_wire_values_no_reinterpretation_of_business_param_or_literal","parameter_identity":"existing_typed_parameter_values_projection_of_used_request_and_query_names","source_validation":"all_known_fields_of_selected_scan_before_filter_including_rows_excluded_by_filter","demand":"existing_checked_expression_demand_without_eager_undemanded_evaluation","native":"preserve_mandatory_admission_and_demanded_failures_before_projection","logical_guards":"max_rows_on_capture_output_max_value_bytes_on_admitted_records_and_demanded_roots","physical_budget":"actual_received_bytes_rows_and_retention_independent_of_logical_output","failure":"atomic_no_success_capture_or_consumer_on_failure_or_cancellation","evidence":"verify_actual_execution_evidence_not_candidate_coverage_proposals_or_self_cid_only","snapshot":"source_specific_no_universal_snapshot_token_or_isolation_requirement","retention":"same_process_immutable_completed_observation_not_durable_run_or_recovery","invocation":"existing_invocation_rules_retain_actual_observation_identity_not_result_identity_only"}}

///|
let sheets_checked_plan_evidence : String =
  #|{"version":"actql-query-process-evidence-contract/0.1","dependencies":{"query_acquisition":{"path":"spec/contracts/actql-query-acquisition.json","pointer":"","cid":"sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc"}},"schemas":{"record":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["version","issuer","attempt","requirement_cid","role","snapshot","scan_scope_cid","actual_access","output"],"properties":{"version":{"const":"actql-query-process-evidence/0.1"},"issuer":{"type":"string","minLength":1},"attempt":{"type":"string","minLength":1},"requirement_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"role":{"enum":["source_validation","filter","select"]},"snapshot":{"anyOf":[{"type":"object","additionalProperties":false,"required":["contract_cid","token_cid"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"token_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"}}},{"type":"null"}]},"scan_scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"actual_access":{"type":"object","additionalProperties":false,"required":["scope_cid","provider_scope_cid","received_rows","received_fields","received_bytes"],"properties":{"scope_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"provider_scope_cid":{"anyOf":[{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},{"type":"null"}]},"received_rows":{"type":"integer","minimum":0,"maximum":9007199254740991},"received_fields":{"type":"array","items":{"type":"string","minLength":1},"uniqueItems":true},"received_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}},"output":{"type":"object","additionalProperties":false,"required":["contract_cid","rows_cid","row_count"],"properties":{"contract_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"rows_cid":{"type":"string","pattern":"^sha256:[0-9a-f]{64}$"},"row_count":{"type":"integer","minimum":0,"maximum":9007199254740991}}}}}},"semantics":{"preimage":"entire_record_canonical_json_utf8_sha256_no_self_cid","authority":"authorized_host_private_issuer_and_live_opaque_success_handle_not_wire_or_cid_alone","issuance":"after_complete_scan_validation_filter_select_limits_and_immutable_output_retention","attempt":"host_allocated_unique_within_unique_process_issuer_never_reused_or_caller_selected","binding":"exact_requirement_attempt_snapshot_scan_scope_actual_access_and_retained_output_for_all_three_roles","native":"authorized_source_execution_covers_full_selected_scan_not_only_host_received_rows_or_columns","source_order":"null_only_in_this_profile_relative_order_is_not_total_order_evidence","lifetime":"same_process_no_deserialization_rehydration_or_durable_capture","host_adapter":"host_authorized_execution_with_owned_consistent_read_view_full_scan_validation_and_query_not_driver_location_or_sql_success","read_view":"private_task_session_transaction_binding_not_snapshot_token_no_cross_attempt_or_read_view_substitution","access_accounting":"engine_internal_scan_host_row_receipt_and_retention_are_distinct_auxiliary_row_receipts_are_not_hidden_or_double_counted","receipt_scope":"one_logical_received_sequence_only_independent_validation_and_query_receipts_require_an_additional_admitted_contract","scan_failure":"invalid_excluded_rows_still_fail_no_global_diagnostic_order_or_total_order_from_validation_traversal"}}

///|
let sheets_checked_plan_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":4096,"max_replacements":4096,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
let sheets_checked_plan_program : String =
  #|{"version":"actql/0.1","id":"sheets-range-update","stages":[{"id":"capture","inputs":{"range":{"connector":"sheets-book","resource":"range_target"}},"steps":[{"filter":"true","as":"scanned"},{"select":["target"],"as":"out"}],"results":{"r":{"from":"out","fields":["target"]}}},{"id":"replace","inputs":{"captured":{"result":{"stage":"capture","result":"r"}}},"steps":[{"values":{"schema":{"rows":{"type":"array","nullable":false,"max_items":2,"items":{"type":"object","nullable":false,"fields":{"text":{"type":"string","nullable":false},"number":{"type":"number","nullable":false},"flag":{"type":"boolean","nullable":false}}}}},"rows":[{"rows":[{"text":"=literal é\r\n","number":0,"flag":false},{"text":"second","number":-2.5,"flag":true}]}]},"as":"values"},{"from":"values","cross_join":{"with":"captured","max_output_rows":1,"select":{"target":"right.target","rows":"left.rows"}},"as":"out"}],"results":{"r":{"from":"out","fields":["target","rows"]},"answer":{"from":"out","fields":["rows"]}},"effects":{"replace":{"command":{"from":{"result":"r"},"target":{"field":"target"},"contract":"__COMMAND__","input":{"rows":{"field":"rows"}}}}}}],"results":{"answer":{"from":{"stage":"replace","result":"answer"}}}}

///|
fn sheets_checked_plan_wire(value : Json) -> String raise {
  @identity.stringify_value(
    @identity.from_json(value, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
}

///|
fn sheets_checked_plan_members(wires : Array[String]) -> Json raise {
  let members = wires.map(wire => {
    let value = @json.parse(wire)
    ("sha256:" + @sha.hex(@utf8.encode(sheets_checked_plan_wire(value))), value)
  })
  members.sort_by((left, right) => {
    if left.0 < right.0 {
      -1
    } else if left.0 > right.0 {
      1
    } else {
      0
    }
  })
  Json::array(members.map(pair => pair.1))
}

///|
test "authored bounded range Program quotes the installed Sheets Source profile and original operation inventory" {
  let schema = "{\"target\":{\"nullable\":false,\"resource_kind\":\"sheet_range\",\"type\":\"resource_ref\"}}"
  let schema_cid = "sha256:" + @sha.hex(@utf8.encode(schema))
  let views : Json = {
    "views": [
      {
        "resource": "range_target",
        "resource_kind": "sheet_range",
        "schema_wire": schema.to_json(),
        "schema_cid": schema_cid.to_json(),
      },
    ],
  }
  // SAME two views selected by installed-sheets.restore for rangeCommand.
  let row_schema = "{\"flag\":{\"nullable\":true,\"type\":\"boolean\"},\"number\":{\"nullable\":true,\"type\":\"number\"},\"text\":{\"nullable\":false,\"type\":\"string\"}}"
  let row_schema_cid = "sha256:" + @sha.hex(@utf8.encode(row_schema))
  guard views is Object(view_root) && view_root["views"] is Array(view_entries) else {
    fail("authored views")
  }
  view_root["views"] = Json::array(
    [
      {
        "resource": "rows",
        "resource_kind": "sheet_rows",
        "schema_wire": row_schema.to_json(),
        "schema_cid": row_schema_cid.to_json(),
      },
      ..view_entries,
    ],
  )
  let declaration = @row_source_host.restore_relation_row_declaration(
    "sheets-book",
    "sheets",
    "sheets/0.1",
    sheets_checked_plan_wire(views),
    None,
  ).unwrap()
  let columns = "[{\"name\":\"text\",\"type\":\"string\",\"nullable\":false},{\"name\":\"number\",\"type\":\"number\",\"nullable\":true},{\"name\":\"flag\",\"type\":\"boolean\",\"nullable\":true}]"
  let rectangle = "{\"sheetId\":7,\"startRow\":2,\"endRow\":4,\"startColumn\":1,\"endColumn\":4}"
  let limits : @catalog.Limits = {
    max_bytes: 300000,
    max_nodes: 200000,
    max_depth: 32,
    max_cells: 6400,
  }
  let command_wire = @catalog.range_command_json(
    "sheets-book", columns, rectangle, limits,
  ).unwrap()
  let declared_wire = sheets_checked_plan_wire({
    "catalog": declaration.catalog.to_json(),
    "contracts": Json::array(declaration.contracts.map(wire => wire.to_json())),
  })
  guard @json.parse(
      @catalog.range_catalog_json(declared_wire, command_wire, limits).unwrap(),
    )
    is Object(declared) else {
    fail("generated range declaration")
  }
  guard @json.parse(command_wire) is Object(command_bundle) &&
    command_bundle["command"] is Object(command) &&
    command["command_id"] is String(command_id) else {
    fail("generated range Command")
  }
  guard declared["catalog"] is String(catalog) &&
    declared["contracts"] is Array(contracts) else {
    fail("generated range catalog")
  }
  let (schemas, capabilities) = @row_source_host.row_declaration_evidence_members(
    declaration,
  )
  guard @json.parse(sheets_checked_plan_environment) is Object(base) else {
    fail("public Environment")
  }
  base.remove("evidence_bundle_cid") |> ignore
  base["schema_snapshots"] = sheets_checked_plan_members(schemas)
  base["connector_capabilities"] = sheets_checked_plan_members(capabilities)
  base["source_views"] = sheets_checked_plan_members(declaration.view_bodies)
  base["contract_registry"] = sheets_checked_plan_members(
    contracts.map(value => {
      guard value is String(wire) else { fail("contract wire") }
      wire
    }),
  )
  base["connector_catalogs"] = Json::array([@json.parse(catalog)])
  base["connector_manifest"] = {
    "version": "actql-connectors/0.1",
    "connectors": Json::array([@json.parse(declaration.manifest_entry)]),
  }
  base["command_contracts"] = Json::array([Json::object(command)])
  let evidence = "sha256:" +
    @sha.hex(@utf8.encode(sheets_checked_plan_wire(Json::object(base))))
  base["evidence_bundle_cid"] = evidence.to_json()
  let environment = @publication_host.admit_client_check_environment(
    sheets_checked_plan_wire(Json::object(base)),
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document = sheets_checked_plan_program.replace(
    old="__COMMAND__",
    new=command_id,
  )
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "sheets-range-update",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = @client_host.prepare_installed_sequence_contracts(
    sheets_checked_plan_registry,
    sheets_checked_plan_values,
    Some(sheets_checked_plan_fragment),
    None,
  ).unwrap()
  let target = @catalog.range_reference(
      "https://sheets.example.test",
      "book",
      { sheet_id: 7, start_row: 2, end_row: 4, start_column: 1, end_column: 4, },
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      limits,
    )
    .unwrap()
    .stringify()
  let configuration = "{\"origin\":\"https://sheets.example.test\",\"spreadsheetId\":\"book\",\"range\":" +
    rectangle +
    ",\"columns\":" +
    columns +
    "}"
  guard command["contract_cid"] is String(command_cid) else {
    fail("Command CID")
  }
  let binding = @catalog.admit_range_binding(
    configuration,
    command_cid,
    "sha256:" + "b".repeat(64),
    target,
    limits,
  ).unwrap()
  let native = sheets_range_construction_profile(
    binding, 100000, 10000, 16, 2000000, 200000, 32,
  )
  let capture = sheets_range_capture_construction_profile(
    binding, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32,
  )
  // Same standard driver quote. Secret=1/metadata=0 and transport=0 are
  // deliberate lower bounds, not an installed configuration or allowance.
  let capacities = @client_host.installed_standard_driver_recipe_capacities(
    native,
    capture,
    1000000,
    100000,
    64,
    100000,
    10000,
    16,
    300000,
    2000000,
    0,
    0,
    false,
    1,
    7,
    16384,
    1000000,
    64,
    4,
    0L,
    response_read_quantum=16384,
  ).unwrap()
  let capture_body = @client_host.prepare_installed_effect_capture_recipe_extent(
    "sheets.update_range", capacities,
  ).unwrap()
  let request_body = @client_host.prepare_installed_effect_operation_extent(
    "sheets.update_range",
    capacities[2],
    0L,
    false,
  ).unwrap()
  let physical = @client_host.prepare_installed_effect_operation_extent(
    "sheets.update_range",
    capacities[3],
    2300001L,
    true,
  ).unwrap()
  let demand = @client_host.prepare_installed_effect_operation_demand_with_controls(
    prepared,
    1,
    "replace",
    [capture_body],
    [request_body, physical],
    capacities[4],
  ).unwrap()
  // Exact original sheetsGridReaderLimits vector, including its existing
  // default65536 secret bound. No cap or policy is reduced for this case.
  let reader_limits : Array[Int] = [
    2000000, 2000000, 200000, 32, 100, 100, 1, 100, 1, 1, 544, 1, 2000000, 12009902,
    401, 4,
  ]
  let request_quote = sheets_range_read_construction_capacity(
    149, 3, 7, 2, 4, 1, 4, 200000, 32,
  )
  let request_capacity = request_quote.unwrap()
  let common_reader = @client_host.installed_preserving_json_source_reader_capacity_with_request(
    reader_limits,
    3,
    65536,
    Some(@execution.execution_capacity(0L, 0L).unwrap()),
  ).unwrap()
  println(
    "CHECKED_SOURCE_REQUEST retained=\{@execution.execution_capacity_retained_bytes(request_capacity)} execution=\{@execution.execution_capacity_execution_bytes(request_capacity)}",
  )
  println(
    "CHECKED_SOURCE_COMMON retained=\{@execution.execution_capacity_retained_bytes(common_reader)} execution=\{@execution.execution_capacity_execution_bytes(common_reader)}",
  )
  let reader = @client_host.installed_preserving_json_source_reader_capacity_with_request(
    reader_limits, 3, 65536, request_quote,
  ).unwrap()
  println(
    "CHECKED_SOURCE_READER retained=\{@execution.execution_capacity_retained_bytes(reader)} execution=\{@execution.execution_capacity_execution_bytes(reader)}",
  )
  let plan = match
    @client_host.prepare_installed_effect_managed_plan(
      prepared,
      request,
      [declaration],
      sheets_checked_plan_query,
      sheets_checked_plan_evidence,
      [2000000L],
      [2000000L],
      contracts,
      sheets_checked_plan_values,
      Some(sheets_checked_plan_fragment),
      None,
      [demand],
      source_providers=Some([reader]),
      provider_factory=_ => [],
    ) {
    Ok(value) => value
    Err(Unsupported) => fail("checked original Plan: Unsupported")
    Err(ForeignOriginal) => fail("checked original Plan: ForeignOriginal")
    Err(SourceAcquisition(_)) =>
      fail("checked original Plan: SourceAcquisition")
    Err(_) => fail("checked original Plan: other typed refusal")
  }
  let (rows, members, held) = @client_host.prepared_installed_effect_managed_shape(
    plan,
  )
  assert_eq(rows, 1)
  assert_eq(members, 1)
  assert_true(held > 0)
  let (original, requirement, acquisition, _) = @client_host.prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  assert_true(physical_equal(original, declaration))
  @row_source_host.check_row_acquisition_original(
    acquisition, original, requirement,
  ).unwrap()
  |> ignore
  for index, quote in capture.unwrap() {
    println(
      "CHECKED_NATIVE_CAPTURE slot=\{index} retained=\{@execution.execution_capacity_retained_bytes(quote)} execution=\{@execution.execution_capacity_execution_bytes(quote)}",
    )
  }
  for index, quote in capacities {
    println(
      "CHECKED_DRIVER slot=\{index} retained=\{@execution.execution_capacity_retained_bytes(quote)} execution=\{@execution.execution_capacity_execution_bytes(quote)}",
    )
  }
  let required = @client_host.prepared_installed_effect_managed_requirements(
    plan,
  )
  println("CHECKED_RANGE_PLAN retained=\{required[4]} execution=\{required[5]}")
  let original = @client_host.client_local_preparation_initial_limits(
    @client_host.client_local_resource_policy(),
  ).unwrap()
  assert_true(
    required[4] <= original.retained_bytes,
    msg=required[4].to_string(),
  )
  assert_true(
    required[5] <= original.execution_bytes,
    msg=required[5].to_string(),
  )
}

///|
test "capture phase maximum retains whole original phases without combining unrelated units" {
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 5L,
  }
  let headers = { ..retained, record_headers: 100L, owned_wire_bytes: 0L, }
  let wire = { ..retained, owned_wire_bytes: 1601L, }
  for phases in [[headers, wire], [wire, headers], [headers, wire, headers]] {
    let quote = sheets_range_capture_phase_capacity(retained, phases).unwrap()
    assert_eq(@execution.execution_capacity_retained_bytes(quote), 5L)
    // Existing16-byte header and1-byte wire prices. Neither complete phase
    // coexists with the other: max(1600,1601)+5, never1600+1601+5.
    assert_eq(@execution.execution_capacity_execution_bytes(quote), 1606L)
  }
  let empty = sheets_range_capture_phase_capacity(retained, []).unwrap()
  assert_eq(@execution.execution_capacity_execution_bytes(empty), 5L)
  let invalid = { ..retained, reference_slots: -1L, }
  assert_true(
    sheets_range_capture_phase_capacity(retained, [headers, invalid]) is None,
  )
  let overflow = { ..retained, record_headers: 9223372036854775807L, }
  assert_true(sheets_range_capture_phase_capacity(retained, [overflow]) is None)
}

///|
test "completed native Json envelope dominates current pinned maps arrays and scalar wrappers" {
  // Json + String + numeric repr/Some are independently over-counted for
  // every node. Objects/arrays and total fields/items share the actual tree
  // census; the pinned current-map/array capacities are supplied separately.
  for n in [1, 2, 3, 16, 33] {
    let envelope = sheets_range_json_retained_inventory(256, n).unwrap()
    let count = n.to_int64()
    for objects in 0..<=n {
      for arrays in 0..<=(n - objects) {
        for fields in 0..<n {
          if objects == 0 && fields > 0 {
            continue
          }
          let o = objects.to_int64()
          let a = arrays.to_int64()
          let f = fields.to_int64()
          let items = count - 1L - f
          let maps = @shape.map_retained_extent(o, 8L * o + 4L * f, f).unwrap()
          let vectors = @shape.reference_array_retained_extent(
            a,
            8L * a + 2L * items,
          ).unwrap()
          assert_true(
            envelope.record_headers >=
            3L * count + maps.record_headers + vectors.record_headers,
          )
          assert_true(
            envelope.reference_slots >=
            3L * count + maps.reference_slots + vectors.reference_slots,
          )
          assert_true(
            envelope.scalar_words >=
            3L * count + maps.scalar_words + vectors.scalar_words,
          )
          assert_eq(envelope.owned_utf16_units, 256L)
        }
      }
    }
  }
}
