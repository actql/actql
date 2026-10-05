// Registered provider boundary tests; these do not claim Native Source I/O.

///|
let retained_source_registry : String =
  #|{"REL.select":{"inputs":["relation"],"output":"relation"},"REL.where":{"inputs":["relation"],"output":"relation"},"REL.assert_all":{"inputs":["relation"],"output":"relation"},"REL.assert_unique":{"inputs":["relation"],"output":"relation"},"REL.derive":{"inputs":["relation"],"output":"relation","execution_extensions":{"ordered_bindings":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.derive.ordered","cid":"sha256:18c717048b5ca41eca1be358683b26fba7f9c19ca70abe7ee1051aaa84bf6c62"}}},"REL.orderByStable":{"inputs":["relation"],"output":"relation"},"REL.limit":{"inputs":["relation"],"output":"relation"},"REL.topk":{"inputs":["relation"],"output":"relation"},"REL.window.fixed":{"inputs":["relation"],"output":"relation"},"REL.window.sliding":{"inputs":["relation"],"output":"relation"},"REL.window.project":{"inputs":["relation"],"output":"relation"},"REL.window.lag":{"inputs":["relation"],"output":"relation"},"REL.watermark":{"inputs":["relation"],"output":"relation"},"REL.pivot":{"inputs":["relation"],"output":"relation"},"REL.unpivot":{"inputs":["relation"],"output":"relation"},"REL.unnest":{"inputs":["relation"],"output":"relation"},"REL.dedupeRows":{"inputs":["relation"],"output":"relation"},"REL.json.pick":{"inputs":["relation"],"output":"relation"},"REL.join":{"inputs":["relation","relation"],"output":"relation"},"REL.groupBy":{"inputs":["relation"],"output":"relation"},"REL.distinct":{"inputs":["relation"],"output":"relation"},"REL.unionAll":{"inputs":["relation","relation"],"output":"relation"},"REL.except_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.intersect_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.cross_join":{"inputs":["relation","relation"],"output":"relation"},"REL.topk_partitioned":{"inputs":["relation"],"output":"relation"},"REL.analytic":{"inputs":["relation"],"output":"relation"},"SGA.normalize":{"inputs":["graph"],"output":"graph"},"SGA.reachable":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.bounds_check":{"inputs":["graph"],"output":"relation"},"SGA.degree_metrics":{"inputs":["graph"],"output":"relation"},"SGA.apply_delta":{"inputs":["graph","relation"],"output":"graph"},"SGA.diff":{"inputs":["graph","graph"],"output":"relation"},"SGA.graft":{"inputs":["graph","graph"],"output":"graph"},"SGA.union_structural":{"finite_inputs":{"repeated_input":"graph","minimum_inputs":2},"output":"graph"},"SGA.diff_structural":{"inputs":["graph","graph"],"output":"graph"},"SGA.match_nodes":{"inputs":["graph"],"output":"relation"},"SGA.match_edges":{"inputs":["graph"],"output":"relation"},"SGA.traverse":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.shortest_path":{"input_alternatives":[["graph"],["graph","relation"],["graph","relation","relation"]],"output":"relation"},"SGA.components":{"inputs":["graph"],"output":"relation"},"SGA.subgraph":{"input_alternatives":[["graph"],["graph","relation"]],"output":"graph"},"SGA.equal":{"inputs":["graph","graph"],"output":"relation"},"SGA.mean_structural":{"finite_inputs":{"repeated_input":"graph","minimum_inputs":1},"output":"graph"},"TEA.window.fixed_label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.sliding_assign":{"inputs":["event_stream"],"output":"event_stream"},"TEA.watermark.label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.session_assign":{"inputs":["event_stream"],"output":"event_stream"},"TEA.dedupe":{"inputs":["event_stream"],"output":"event_stream"},"TEA.join.asof":{"inputs":["event_stream","relation"],"output":"relation"},"TEA.sequence.match":{"inputs":["event_stream"],"output":"relation"},"TEA.time_series":{"inputs":[],"output":"relation"},"TEA.join.interval":{"inputs":["relation","relation"],"output":"relation"},"VEC.normalize_l2":{"inputs":["vector_set"],"output":"vector_set"},"VEC.score_sort":{"inputs":["vector_set"],"output":"vector_set"},"VEC.knn_join":{"inputs":["vector_set","vector_set"],"output":"relation"},"VEC.pool":{"inputs":["vector_set"],"output":"vector_set"},"VEC.merge_rankings":{"policy_inputs":{"max":{"inputs":["relation","relation"]},"weighted_sum":{"inputs":["relation","relation"]},"rrf":{"repeated_input":"relation","minimum_inputs":2}},"output":"relation"},"BRIDGE.graph.to_edge_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.graph.to_node_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.rows.to_graph":{"inputs":["relation","relation"],"output":"graph"},"BRIDGE.events.to_rows":{"inputs":["event_stream"],"output":"relation"},"BRIDGE.rows.to_events":{"inputs":["relation"],"output":"event_stream"},"BRIDGE.vectors.to_rows":{"inputs":["vector_set"],"output":"relation"},"BRIDGE.rows.to_vectors":{"inputs":["relation"],"output":"vector_set"},"EFFECT.plan":{"inputs":["relation"],"output":"relation"},"REL.values":{"inputs":[],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.values","cid":"sha256:9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b"}},"ACTQL.expression_fragment/0.1":{"inputs":["relation"],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/ACTQL.expression_fragment~10.1","cid":"sha256:95b3ee285ed5b097c01cc2d414603e051810ebf83c65cb94bceb18ee1477d1bf"}},"BRIDGE.rows.to_property_graph":{"finite_inputs":{"repeated_input":"relation","minimum_inputs":0},"output":"graph","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/BRIDGE.rows.to_property_graph","cid":"sha256:b00de8912497c6af1596debd1c59ee8d3477faf0391be40f64ac82ebc6d9ebb7"}}}

///|
let retained_source_values : String =
  #|{"version":"actql-rel-values-execution/0.1","operation":"REL.values","inputs":[],"output":"relation","dependencies":{"canonical_value_contract":{"path":"spec/contracts/actql-protocol-schemas.json","pointer":"/schemas/canonical_value_contract","cid":"sha256:02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551"}},"params_schema":{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://smooth.dev/schemas/actql/rel-values-params-0.1.json","type":"object","additionalProperties":false,"required":["schema","rows"],"properties":{"schema":{"type":"object","minProperties":1,"propertyNames":{"pattern":"^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"},"additionalProperties":{"$ref":"#/$defs/value_contract"}},"rows":{"type":"array","items":{"type":"object","additionalProperties":{"$ref":"#/$defs/wire_value"}}}},"$defs":{"value_contract":{"oneOf":[{"type":"object","additionalProperties":false,"required":["type","nullable","precision","scale"],"properties":{"type":{"const":"decimal"},"nullable":{"type":"boolean"},"precision":{"type":"integer","minimum":1,"maximum":38},"scale":{"type":"integer","minimum":0,"maximum":38}},"allOf":[{"if":{"properties":{"precision":{"const":1}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":1}}}},{"if":{"properties":{"precision":{"const":2}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":2}}}},{"if":{"properties":{"precision":{"const":3}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":3}}}},{"if":{"properties":{"precision":{"const":4}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":4}}}},{"if":{"properties":{"precision":{"const":5}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":5}}}},{"if":{"properties":{"precision":{"const":6}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":6}}}},{"if":{"properties":{"precision":{"const":7}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":7}}}},{"if":{"properties":{"precision":{"const":8}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":8}}}},{"if":{"properties":{"precision":{"const":9}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":9}}}},{"if":{"properties":{"precision":{"const":10}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":10}}}},{"if":{"properties":{"precision":{"const":11}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":11}}}},{"if":{"properties":{"precision":{"const":12}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":12}}}},{"if":{"properties":{"precision":{"const":13}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":13}}}},{"if":{"properties":{"precision":{"const":14}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":14}}}},{"if":{"properties":{"precision":{"const":15}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":15}}}},{"if":{"properties":{"precision":{"const":16}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":16}}}},{"if":{"properties":{"precision":{"const":17}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":17}}}},{"if":{"properties":{"precision":{"const":18}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":18}}}},{"if":{"properties":{"precision":{"const":19}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":19}}}},{"if":{"properties":{"precision":{"const":20}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":20}}}},{"if":{"properties":{"precision":{"const":21}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":21}}}},{"if":{"properties":{"precision":{"const":22}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":22}}}},{"if":{"properties":{"precision":{"const":23}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":23}}}},{"if":{"properties":{"precision":{"const":24}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":24}}}},{"if":{"properties":{"precision":{"const":25}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":25}}}},{"if":{"properties":{"precision":{"const":26}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":26}}}},{"if":{"properties":{"precision":{"const":27}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":27}}}},{"if":{"properties":{"precision":{"const":28}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":28}}}},{"if":{"properties":{"precision":{"const":29}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":29}}}},{"if":{"properties":{"precision":{"const":30}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":30}}}},{"if":{"properties":{"precision":{"const":31}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":31}}}},{"if":{"properties":{"precision":{"const":32}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":32}}}},{"if":{"properties":{"precision":{"const":33}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":33}}}},{"if":{"properties":{"precision":{"const":34}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":34}}}},{"if":{"properties":{"precision":{"const":35}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":35}}}},{"if":{"properties":{"precision":{"const":36}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":36}}}},{"if":{"properties":{"precision":{"const":37}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":37}}}},{"if":{"properties":{"precision":{"const":38}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":38}}}}]},{"type":"object","additionalProperties":false,"required":["type","nullable"],"properties":{"type":{"const":"string"},"nullable":{"type":"boolean"},"min_length":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_codepoints":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_utf8_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991}}},{"type":"object","additionalProperties":false,"required":["type","nullable"],"properties":{"type":{"enum":["number","boolean","timestamp","date"]},"nullable":{"type":"boolean"}}},{"type":"object","additionalProperties":false,"required":["type","nullable","items"],"properties":{"type":{"const":"array"},"nullable":{"type":"boolean"},"items":{"$ref":"#/$defs/value_contract"},"max_items":{"type":"integer","minimum":0,"maximum":9007199254740991}}},{"type":"object","additionalProperties":false,"required":["type","nullable","additional_properties","fields"],"properties":{"type":{"const":"object"},"nullable":{"type":"boolean"},"additional_properties":{"const":false},"fields":{"type":"object","propertyNames":{"pattern":"^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"},"additionalProperties":{"$ref":"#/$defs/value_contract"}}}},{"type":"object","additionalProperties":false,"required":["type","nullable","dimensions","element_type"],"properties":{"type":{"const":"vector"},"nullable":{"type":"boolean"},"dimensions":{"type":"integer","minimum":1},"element_type":{"const":"f32"}}}]},"wire_value":{"oneOf":[{"type":["null","boolean","number","string"]},{"type":"array","items":{"$ref":"#/$defs/wire_value"}},{"type":"object","additionalProperties":{"$ref":"#/$defs/wire_value"}}]}}},"semantics":{"schema_form":"nonempty_field_map_of_complete_checked_constructible_contracts","cells":"bound_typed_wire_values_without_cell_wrappers","quotation":"remove_exact_singleton_literal_once_before_execution_params","parameter_resolution":"resolve_only_authored_cell_root_holes_before_execution_params","business_objects":"never_reinterpret_param_or_literal_members","row_fields":"exact_declared_set_including_nullable_fields","values":"recursive_declared_type_admission_without_cast_repair_or_rounding","strings":"preserve_well_formed_unicode_scalar_sequence_without_NFC_or_line_break_repair","object_member_names":"NFC_then_LF_reject_noncanonical_names_and_collisions","string_extents":"retained_unicode_scalars_and_UTF8_bytes","decimal":"canonical_fixed_scale_string_under_declared_precision_and_scale","empty_rows":"retain_declared_schema","row_order":"retain_occurrence_order","row_multiplicity":"retain_all_occurrences","object_key_order":"canonical_utf16_order_not_row_order","publication":"validate_all_rows_and_resolved_limits_before_publication","recursive_resources":{"selected_root_types":["array","object","vector"],"bytes":"sum_canonical_typed_wire_cell_bytes_across_all_occurrences_including_null_without_double_counting_nested_containers","byte_exclusions":["scalar_typed_cells","row_keys","row_wrappers","rows_wrapper","schema"],"host_byte_ceiling":"max_nested_value_bytes","depth":"declared_cell_type_scalar_0_vector_1_array_1_plus_items_object_1_plus_max_fields","depth_excludes":["row_wrapper","rows_wrapper"],"host_depth_ceiling":"max_nested_value_depth","empty_or_null":"type_depth_still_checked_zero_selected_cells_have_zero_bytes","failure":"atomic_before_any_consumer_without_truncation"},"unsupported_backend":"reject_runnable_plan_without_exact_registered_contract_support"}}

///|
let retained_source_fragment : String =
  #|{"version":"actql-expression-fragment-execution/0.1","operation":"ACTQL.expression_fragment/0.1","inputs":["relation"],"output":"relation","dependencies":{"expression_contract":{"file":"spec/contracts/actql-expressions.json","pointer":"","cid":"sha256:e14e1d9434909f1d0a68dc0441a6260c07476d662d237517d548de4dff0ac50f"},"fragment_schema":{"file":"spec/contracts/actql-expressions.json","pointer":"/schemas/fragment","cid":"sha256:4d42600c1b3d42d660f2eb14a84342988c17646110f8995f80bf4dc4344ce3d4"}},"params_schema":{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"urn:actql:expression-fragment-params:0.1","type":"object","additionalProperties":false,"required":["fragment"],"properties":{"fragment":{"$ref":"urn:actql:expression-fragment:0.1"}}},"semantics":{"schema_resolution":"resolve_fragment_schema_from_exact_pinned_dependency_without_network_lookup","local_source":"exactly_one_request_pipeline_source_named_input","admission":"regenerate_and_compare_sealed_fragment_under_pinned_expression_contract_before_evaluation","fragment_identity":"hash_complete_canonical_fragment_excluding_only_root_fragment_cid","retained_material":"retain_opcode_and_complete_fragment_in_canonical_composition","inner_graph":"not_a_standalone_execution_artifact","carrier_projection":"validation_witness_only_never_hashed_executed_or_used_as_type_evidence","obligations":"enforce_fragment_input_root_output_limits_demands_and_runtime_checks","backend":"reject_execution_without_support_for_exact_contract_and_all_used_extensions","authority":"registration_does_not_establish_program_completion_or_execution_permission"}}

///|
fn retained_source_sequence(
  prepared : @publication_host.PreparedClientProgram,
) -> (@query.QuerySequence, @context.ProgramSourceIdentity) {
  let requirement = @local_host.prepare_local_query_requirement(
    prepared,
    0,
    0,
    retained_source_registry,
    retained_source_values,
    Some(retained_source_fragment),
    None,
  ).unwrap()
  (
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
    @planning.query_requirement_program(requirement),
  )
}

///|
fn retained_source_limits() -> NativeRemoteStandardTransferSourceLimits {
  {
    max_rows: 10,
    max_wire_bytes: 1000,
    max_read_bytes: 3,
    max_entries: 100,
    max_name_bytes: 10000,
    values: {
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 10,
      max_work: 200000,
    },
    wire: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
  }
}

///|
fn retained_source_setup(
  run? : (
    @publication_host.PreparedClientProgram,
    @publication_host.ClientTaskCompilation,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )? = None,
) -> (
  NativeRemoteRetainedTaskInput,
  @remote.DispatchRequest,
  @query.QuerySequence,
  @context.ProgramSourceIdentity,
  NativeRemoteRetainedInputCurrent,
  NativeRemoteStandardRowCodec,
) {
  let (prepared, compilation, allowed, definition) = run.unwrap_or_else(
    retained_transfer_run,
  )
  let edge = @publication_host.prepare_client_retained_input_edge(
    prepared,
    compilation,
    @publication_host.client_compiled_run_admission(allowed),
    definition,
    1,
    0,
  ).unwrap()
  let (producer, transfer, receipt, site) = retained_transfer_fixture(
    true,
    edge=Some(edge),
  )
  let current = retained_transfer_current(
    site,
    standard_transfer_input_cid("c"),
  )
  let input = prepare_native_remote_retained_task_input(
    producer, transfer, receipt, "use-a", current, 262144,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    standard_transfer_input_cid("c"),
    "retained-caller",
  ).unwrap()
  let selected : @publication_host.ClientValuesSiteSelection = {
    site_key: "site-a",
    site_generation: 1,
    runtime_bundle_cid: standard_transfer_input_cid("a"),
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
    obligations_cid: standard_transfer_input_cid("2"),
    budget_cid: standard_transfer_input_cid("3"),
    evidence_issuer_capability_cid: standard_transfer_input_cid("4"),
    grant_cid: standard_transfer_input_cid("5"),
  }
  let dispatch = @publication_host.prepare_client_retained_task_dispatch(
    prepared,
    compilation,
    @publication_host.client_compiled_run_admission(allowed),
    definition,
    request,
    1,
    1,
    "consumer-dispatch",
    selected,
    input.common,
    current.common,
  ).unwrap()
  let (sequence, program) = retained_source_sequence(prepared)
  let codec = register_native_remote_standard_row_codec(
    @transfer.request_schema_contract_cid(input.physical.request),
    @transfer.request_view_contract_cid(input.physical.request),
    @transfer.request_codec_contract_cid(input.physical.request),
  ).unwrap()
  (input, dispatch, sequence, program, current, codec)
}

///|
test "checked retained physical input returns its borrow without reclaiming either holding" {
  let (input, dispatch, sequence, program, current, codec) = retained_source_setup()
  let streams : Ref[Int] = { val: 0, }
  let releases : Ref[Int] = { val: 0, }
  let live : Ref[Bool] = { val: true, }
  let physical = register_native_remote_standard_physical_source(
    input.physical,
    () => live.val,
    (max_bytes, emit) => {
      streams.val += 1
      let row = b"{\"id\":3}"
      let mut offset = 0
      while offset < row.length() {
        let count = Int::min(max_bytes, row.length() - offset)
        match
          emit(0, Bytes::from_array(Array::makei(count, i => row[offset + i]))) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        offset += count
      }
      Ok(())
    },
    () => {
      releases.val += 1
      live.val = false
      true
    },
  )
  let source = acquire_native_remote_retained_physical_source(
    input,
    physical,
    dispatch,
    codec,
    sequence,
    program,
    retained_source_limits(),
    current,
  ).unwrap()
  assert_eq(streams.val, 1)
  assert_eq(releases.val, 0)
  assert_true(
    @query.captured_source_available(
      native_remote_standard_transfer_captured_source(source),
    ),
  )
  assert_true(finish_native_remote_standard_transfer_source(source))
  assert_true(finish_native_remote_standard_transfer_source(source))
  assert_eq(releases.val, 1)
  assert_false(
    @query.captured_source_available(
      native_remote_standard_transfer_captured_source(source),
    ),
  )
  assert_true(
    @publication_host.client_retained_input_producer_available(
      @publication_host.client_retained_task_input_producer(input.common),
    ),
  )
  assert_true(
    @transfer.record_is_destination_committed(
      @publication_host.client_retained_task_input_transfer_record(input.common),
    ),
  )
}

///|
test "equal-content foreign capture preparation is rejected before a physical read" {
  let (input, dispatch, _, _, current, codec) = retained_source_setup()
  let (foreign_prepared, _, _, _) = retained_transfer_run()
  let (sequence, program) = retained_source_sequence(foreign_prepared)
  let streams : Ref[Int] = { val: 0, }
  let releases : Ref[Int] = { val: 0, }
  let physical = register_native_remote_standard_physical_source(
    input.physical,
    () => true,
    (_, _) => {
      streams.val += 1
      Err("unexpected-read")
    },
    () => {
      releases.val += 1
      true
    },
  )
  assert_true(
    acquire_native_remote_retained_physical_source(
      input,
      physical,
      dispatch,
      codec,
      sequence,
      program,
      retained_source_limits(),
      current,
    )
    is Err(ForeignCapture),
  )
  assert_eq(streams.val, 0)
  assert_eq(releases.val, 0)
}

///|
test "retained input stream failure keeps borrow cleanup retryable" {
  let (input, dispatch, sequence, program, current, codec) = retained_source_setup()
  let cleanup_ready : Ref[Bool] = { val: false, }
  let releases : Ref[Int] = { val: 0, }
  let physical = register_native_remote_standard_physical_source(
    input.physical,
    () => true,
    (_, _) => Err("interrupted-transfer-read"),
    () => {
      releases.val += 1
      cleanup_ready.val
    },
  )
  let failure = match
    acquire_native_remote_retained_physical_source(
      input,
      physical,
      dispatch,
      codec,
      sequence,
      program,
      retained_source_limits(),
      current,
    ) {
    Err(Source(failure)) => failure
    _ => abort("retained stream did not preserve the physical cleanup owner")
  }
  assert_false(retry_native_remote_standard_input_failure_cleanup(failure))
  assert_true(native_remote_standard_input_failure_cleanup_pending(failure))
  cleanup_ready.val = true
  assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
  assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
  assert_eq(releases.val, 2)
  assert_true(
    @publication_host.client_retained_input_producer_available(
      @publication_host.client_retained_task_input_producer(input.common),
    ),
  )
}

///|
test "a producer dispatch cannot enter the retained consumer physical reader" {
  let (input, _, sequence, program, current, codec) = retained_source_setup()
  let reads : Ref[Int] = { val: 0, }
  let releases : Ref[Int] = { val: 0, }
  let physical = register_native_remote_standard_physical_source(
    input.physical,
    () => true,
    (_, _) => {
      reads.val += 1
      Err("unexpected-read")
    },
    () => {
      releases.val += 1
      true
    },
  )
  let producer_dispatch = @publication_host.client_retained_input_producer_dispatch(
    @publication_host.client_retained_task_input_producer(input.common),
  )
  assert_true(
    acquire_native_remote_retained_physical_source(
      input,
      physical,
      producer_dispatch,
      codec,
      sequence,
      program,
      retained_source_limits(),
      current,
    )
    is Err(ForeignConsumer),
  )
  assert_eq(reads.val, 0)
  assert_eq(releases.val, 0)
}

///|
test "authorization loss during a retained stream prevents captured completion" {
  let (input, dispatch, sequence, program, _, codec) = retained_source_setup()
  let authorized : Ref[Bool] = { val: true, }
  let releases : Ref[Int] = { val: 0, }
  let current = install_native_remote_retained_input_current(
    () => {
      @site.create_site(
        "site-a",
        1,
        standard_transfer_input_cid("a"),
        4,
        4,
        1048576L,
        1048576L,
      ).unwrap()
    },
    () => standard_transfer_input_cid("c"),
    () => 1791158400000L,
    (_, _) => authorized.val,
  )
  let physical = register_native_remote_standard_physical_source(
    input.physical,
    () => true,
    (_, emit) => {
      match emit(0, b"{\"id\":3}") {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      authorized.val = false
      Ok(())
    },
    () => {
      releases.val += 1
      true
    },
  )
  let limits : NativeRemoteStandardTransferSourceLimits = {
    ..retained_source_limits(),
    max_read_bytes: 8,
  }
  let failure = match
    acquire_native_remote_retained_physical_source(
      input, physical, dispatch, codec, sequence, program, limits, current,
    ) {
    Err(Source(failure)) => failure
    _ => abort("revoked retained stream established a captured completion")
  }
  assert_eq(releases.val, 0)
  assert_true(retry_native_remote_standard_input_failure_cleanup(failure))
  assert_eq(releases.val, 1)
}
