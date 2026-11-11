///|
fn serialized_infer_fixture_program(
  trailing_projection? : Bool = false,
) -> @publication_host.PreparedClientProgram {
  // Independently sealed Node crypto vector, not a product-derived oracle.
  let task =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:836444f3888092768af981447509670f2efc05bc047bf2665a951603c93b160d","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"document":{"media_type":"application/x-ndjson","nullable":false,"type":"content_ref"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:60859537e680a59e68650f78be73ce2c818e3f3f2e37460568c8a54877c03d7a","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:d0ff84aab70965d97df8303954e5ab59e9b554de3251ca53f55da56577eedde2","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let old_task = infer_fixture_environment
  .split("\"model_task_contracts\":[")
  .to_array()[1]
  .split("],\"schema_snapshots\":")
  .to_array()[0].to_owned()
  let environment = infer_fixture_environment
    .replace(
      old="\"model_task_contracts\":[" + old_task + "]",
      new="\"model_task_contracts\":[" + task + "]",
    )
    .replace(
      old="\"max_model_request_bytes_per_item\":1000",
      new="\"max_model_request_bytes_per_item\":4096",
    )
  let source =
    #|{"version":"actql/0.1","id":"generated-content-model","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":18}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"document":{"field":"content"}}},"as":"inferred"}],"results":{"answer":{"from":"inferred","fields":["name","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"answer"}}}}
  let source = if trailing_projection {
    source
    .replace(
      old="\"as\":\"inferred\"}],",
      new="\"as\":\"inferred\"},{\"select\":[\"name\",\"outcome\",\"value\"],\"as\":\"projected\"}],",
    )
    .replace(old="\"from\":\"inferred\"", new="\"from\":\"projected\"")
  } else {
    source
  }
  fixture_prepared(source~, environment_wire=environment)
}

///|
test "generated Content and Infer share checked Plan components without synthetic roots" {
  let step = 3
  let prepared = serialized_infer_fixture_program()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let sequence = @publication_host.client_standard_values_sequence_limits()
  assert_true(
    @publication_host.issue_prepared_client_serialization_plan_graph(
      prepared, 0, 1, policy, 2, 18, 3, sequence, 100000, 10000, 100,
    )
    is Err(_),
  )
  let content = @publication_host.issue_prepared_client_serialization_plan_component(
    prepared, 0, 1, policy, 2, 18, 3, sequence, 100000, 10000, 100,
  ).unwrap()
  let component = @canonical.from_json(
    @json.parse(@publication_host.client_serialization_plan_graph_wire(content)),
    10000,
    100,
    100000,
  )
  assert_true(
    @canonical.object_field(component, "root_refs")
    is Some(@canonical.Array(roots)) &&
    @canonical.array_values(roots).is_empty(),
  )
  // Independently sealed Model execution vector. These references do not
  // admit provider bodies, media transport or current egress authority.
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":1,"max_total_cost_units":0,"max_total_duration_ms":500,"max_total_token_reservation":33,"max_total_wire_bytes":133072,"media_input_contracts":{"document":"sha256:03213e7e836021f73b99d57eb5ea5855cd8430cd85b4a4079a8d92eede531507"},"model_task_contract_cid":"sha256:836444f3888092768af981447509670f2efc05bc047bf2665a951603c93b160d","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097","version":"actql-model-execution-contract/0.1"}
  let execution = @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    step,
    @utf8.encode(execution_wire),
    "sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
    100000,
  ).unwrap()
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let graph = @publication_host.issue_prepared_client_serialized_infer_plan_graph(
    occurrence, content, execution, sequence, 100000, 10000, 100,
  ).unwrap()
  let wire = @publication_host.client_infer_plan_graph_wire(graph)
  let plan_graph = @canonical.from_json(@json.parse(wire), 10000, 100, 100000)
  guard @canonical.object_field(plan_graph, "nodes")
    is Some(@canonical.Array(nodes)) else {
    abort("missing actual component nodes")
  }
  let ids = @canonical.array_values(nodes).map(node => {
    match @canonical.object_field(node, "node_id") {
      Some(@canonical.String(value)) => value
      _ => abort("missing node identity")
    }
  })
  assert_eq(ids, [
    "task_0_before_serialize_1", "task_0_serialize_1", "task_0_after_serialize_2",
    "task_0_infer_3",
  ])
  assert_true(!wire.contains("REL.serialize"))
  assert_true(
    @canonical.object_field(plan_graph, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.array_values(edges).length() == 3,
  )
  assert_true(
    @canonical.object_field(plan_graph, "root_refs")
    is Some(@canonical.Array(roots)) &&
    @canonical.array_values(roots).length() == 1,
  )
  let foreign = serialized_infer_fixture_program()
  assert_true(
    @publication_host.issue_prepared_client_serialized_infer_plan_graph(
      @publication_host.prepared_client_composed_infer_occurrence(foreign).unwrap(),
      content,
      execution,
      sequence,
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_infer_compilation(
    prepared, graph, manifests, 1000, 1000, 100000, 10000, 100,
  ).unwrap()
  assert_true(
    @publication_host.client_task_compilation_serialization(compilation)
    is Some(selected) &&
    physical_equal(selected, content),
  )
  let plan = @canonical.from_json(
    @json.parse(
      @publication_host.client_task_executable_plan_wire(
        @publication_host.client_task_compilation_plan(compilation),
      ),
    ),
    10000,
    100,
    100000,
  )
  let template = @canonical.from_json(
    @json.parse(
      @publication.run_evidence_value_json(
        @publication_host.client_task_compilation_template(compilation),
      ),
    ),
    10000,
    100,
    100000,
  )
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(plan, "required_profiles").unwrap(),
      10000,
      1000,
      20,
    ),
    @canonical.stringify_value(
      @canonical.object_field(template, "required_profile_contracts").unwrap(),
      10000,
      1000,
      20,
    ),
  )
  assert_true(
    @canonical.object_field(plan, "required_profiles")
    is Some(@canonical.Array(profiles)) &&
    @canonical.array_values(profiles).length() == 2,
  )
  assert_eq(
    @publication_host.client_task_compilation_result_names(compilation),
    ["answer"],
  )
  // Independent encoding of the component inventory: each real pure node
  // contributes once; neither barrier CID stands in for the entire AoA work.
  let component_cid = (index : Int) => {
    match
      @canonical.object_field(
        @canonical.array_values(nodes)[index],
        "logical_cid",
      ) {
      Some(@canonical.String(value)) => value
      _ => abort("missing pure component identity")
    }
  }
  let preimage = "[{\"logical_cid\":\"" +
    component_cid(0) +
    "\",\"node_id\":\"task_0_before_serialize_1\"},{\"logical_cid\":\"" +
    component_cid(2) +
    "\",\"node_id\":\"task_0_after_serialize_2\"}]"
  let compiled_contract = @canonical.from_json(
    @json.parse(
      @publication.publication_contract_json(
        @publication_host.client_task_compilation_compiled_plan(compilation),
      ),
    ),
    10000,
    100,
    100000,
  )
  assert_true(
    @canonical.object_field(compiled_contract, "aoa_logical_cid")
    is Some(@canonical.String(actual)) &&
    actual == "sha256:" + @sha.hex(@utf8.encode(preimage)),
  )
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  // The existing issuer re-admits the policy body; object allocation identity
  // is not its contract. Preserve its exact canonical original and CID.
  let original = @publication_host.client_compiled_run_serialization_policy_body(
    compiled,
  ).unwrap()
  assert_eq(
    @publication.captured_effect_dependency_body_cid(original),
    @publication.captured_effect_dependency_body_cid(policy),
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(original),
    @publication.captured_effect_dependency_body_json(policy),
  )
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "generated-scope", "generated-run", "2026-10-02T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let (output, candidate, live) = serialized_infer_fixture_output(prepared)
  let calls = Ref(0)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Err(@model.Timeout)
  }).unwrap()
  assert_true(
    start_serialized(foreign, step, graph, output, provider, standard_limits())
    is Err(_),
  )
  let active = start_serialized(
    prepared,
    step,
    graph,
    output,
    provider,
    standard_limits(),
  ).unwrap()
  bind_run(active, compiled, definition).unwrap()
  require_model_call_entry(active).unwrap()
  // The original execution owner consumes the real mapping, with no encoder
  // replay. Cancel after positive input work, before a Model dispatch permit.
  for _ in 0..<10000 {
    if active.phase is Identity {
      break
    }
    assert_true(advance(active, 1).unwrap() is Continue(_))
  }
  assert_true(active.phase is Identity && active.work > 0L)
  let rows = active.rows.unwrap()
  guard @relation.prepared_infer_rows_value(rows, 0, 0).unwrap().value
    is @admitted.Reference(reference) else {
    abort("typed Content was lost")
  }
  assert_eq(
    @admitted.reference_identity_cid(reference),
    @publication.generated_content_reference_identity(candidate),
  )
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(_))
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(live.val && @relation.completed_output_available(output))
  assert_eq(calls.val, 0)

  // Consume this same admitted mixed Plan through a real Model fixture call.
  // This finite fixture validates physical attachment bytes too, but not a
  // real byte Store, current egress authorization or network acknowledgement.
  let (_, _, generated_live, generation) = serialized_infer_fixture_material(
    prepared,
    run=Some(compiled),
    definition=Some(definition),
  )
  let generation = generation.unwrap()
  let exported_content = @input.export_client_content_generation_output(
    generation,
    compiled,
    definition,
    "sha256:" + "1".repeat(64),
  ).unwrap()
  let content_descriptor = @input.read_client_infer_retained_input_descriptor(
    @input.client_infer_retained_input_export_descriptor(exported_content),
  ).unwrap()
  assert_eq(content_descriptor.output_step, 1)
  assert_eq(content_descriptor.rows, 1)
  assert_eq(content_descriptor.columns, 5)
  let content_rows = @input.client_infer_retained_input_export_rows(
    exported_content,
  )
  assert_eq(content_rows.length(), 1)
  let exported_row = @canonical.from_json(
    @json.parse(content_rows[0]),
    1000,
    32,
    16384,
  )
  assert_eq(@canonical.object_field_count(exported_row), Some(5))
  assert_true(
    @canonical.object_field(exported_row, "name")
    is Some(@canonical.String("out.jsonl")),
  )
  assert_true(
    @canonical.object_field(exported_row, "row_count")
    is Some(@canonical.Number(2)),
  )
  assert_true(
    @canonical.object_field(exported_row, "size_bytes")
    is Some(@canonical.Number(18)),
  )
  assert_true(
    @input.export_client_content_generation_output(
      generation,
      compiled,
      definition,
      "sha256:" + "9".repeat(64),
    )
    is Err(@input.BindingMismatch),
  )
  let other_run = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    @input.export_client_content_generation_output(
      generation,
      other_run,
      definition,
      "sha256:" + "1".repeat(64),
    )
    is Err(@input.BindingMismatch),
  )
  assert_true(
    start_generated(
      prepared,
      other_run,
      generation,
      graph,
      provider,
      standard_limits(),
    )
    is Err(CallScope(ForeignInput)),
  )
  // Complete the post-generation guard in the ordinary Local provider, then
  // borrow that exact receiving edge into the boundary-only Model component.
  // This path must not re-run either VALUES, generation or the guard.
  let content_output = @publication_host.client_serialization_generation_output_for(
    generation, compiled,
  ).unwrap()
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  assert_true(
    @lower.prepare_sequence_with_infer_boundary(owner, step, sequence) is Err(_),
  )
  let semantic = @lower.prepare_sequence_with_infer_boundary(
    owner,
    step,
    sequence,
    serialization=Some(1),
  ).unwrap()
  assert_true(
    @lower.sequence_step(semantic, 1) is Some(@lower.SerializationBoundary(1)),
  )
  assert_true(
    @lower.sequence_step(semantic, step) is Some(@lower.InferBoundary(3)),
  )
  for invalid in [0, 2, 3, 4] {
    assert_true(
      @lower.prepare_sequence_with_infer_boundary(
        owner,
        step,
        sequence,
        serialization=Some(invalid),
      )
      is Err(_),
    )
  }
  let contracts = @relation.admit_relation_registry(
    @canonical.from_json(
      @json.parse(infer_fixture_registry),
      10000,
      100,
      100000,
    ),
    @canonical.from_json(@json.parse(infer_fixture_values), 10000, 100, 100000),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let whole = @relation.prepare_generated_sequence(
    contracts,
    semantic,
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), step).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let selected = @relation.select_generated_sequence_step(whole, step).unwrap()
  let child_provider = composed_local_provider(
    occurrence,
    standard_limits(),
    _ => Err(InvalidAdvance),
    _ => @connector.ComputeUnsupported,
    boundary_only=true,
  )
  assert_true(@local.managed_provider_accepts(child_provider, selected))
  assert_false(@local.managed_provider_accepts(child_provider, whole))
  assert_false(
    @local.managed_provider_accepts(
      child_provider,
      @relation.select_generated_sequence_step(whole, 1).unwrap(),
    ),
  )
  assert_true(
    @local.managed_provider_capacity(child_provider, selected) is Some(_),
  )
  assert_true(@local.managed_provider_capacity(child_provider, whole) is None)
  // The ordinary chain must select the same singleton child, not try to
  // evaluate Infer as a row kernel or require a whole-Unit replacement.
  let before_model = @relation.select_generated_sequence_range(whole, 2, 3).unwrap()
  let installed = @local.local_bounded_relation_provider(
    standard_limits().input,
    standard_limits().measurement,
    before_model,
    family=[child_provider],
  ).unwrap()
  assert_true(
    @local.managed_provider_capacity(installed, before_model) is Some(_),
  )
  assert_true(
    @local.local_bounded_relation_provider(
      standard_limits().input,
      standard_limits().measurement,
      before_model,
    )
    is None,
  )
  let segment = @relation.prepare_serialization_infer_input_segment(
    content_output, step, sequence, 100000, 10000,
  ).unwrap()
  let limits = standard_limits()
  let prefix_input = @relation.prepare_producer_read(
    owner,
    @relation.bind_completed_operation_input(owner, 2, 0, owner, content_output).unwrap(),
    1000,
    10000,
  ).unwrap()
  let prefix_provider = @local.local_bounded_relation_provider(
    limits.input,
    limits.measurement,
    segment,
  ).unwrap()
  let prefix = @local.start_managed_provider_with_inputs_and_execution(
    prefix_provider,
    segment,
    [@local.managed_provider_relation_input(prefix_input)],
    2,
    10000,
    limits.input,
  ).unwrap()
  let mut prefix_output = None
  for _ in 0..<10000 {
    match @local.advance_managed_provider(prefix, 1).unwrap() {
      @local.Continue(..) => ()
      @local.Complete(output, ..) => {
        prefix_output = Some(output)
        break
      }
      _ => abort("Checked post-generation guard must complete")
    }
  }
  let prefix_output = prefix_output.unwrap()
  let read = @relation.prepare_producer_read(
    owner,
    @relation.bind_completed_operation_input(
      owner, step, 0, owner, prefix_output,
    ).unwrap(),
    1000,
    10000,
  ).unwrap()
  assert_true(
    @relation.infer_completed_producer_input(owner, step, prefix_input) is None,
  )
  assert_true(
    @relation.infer_completed_producer_input(owner, step, read)
    is Some(original) &&
    physical_equal(original, prefix_output),
  )
  assert_true(
    @relation.infer_completed_producer_input(owner, step - 1, read) is None,
  )
  assert_true(
    start_generated_inputs(
      compiled,
      generation,
      graph,
      [@local.managed_provider_relation_input(prefix_input)],
      provider,
      limits,
    )
    is Err(CallScope(ForeignInput)),
  )
  let boundary = start_generated_inputs(
    compiled,
    generation,
    graph,
    [@local.managed_provider_relation_input(read)],
    provider,
    limits,
  ).unwrap()
  assert_true(
    start_generated_inputs(
      other_run,
      generation,
      graph,
      [@local.managed_provider_relation_input(read)],
      provider,
      limits,
    )
    is Err(CallScope(ForeignInput)),
  )
  bind_run(boundary, compiled, definition).unwrap()
  require_model_call_entry(boundary).unwrap()
  for _ in 0..<10000 {
    if boundary.phase is Identity {
      break
    }
    assert_true(advance(boundary, 1).unwrap() is Continue(_))
  }
  assert_true(boundary.phase is Identity && boundary.work > 0L)
  assert_true(
    physical_equal(
      @input.client_infer_completed_input(boundary.input).unwrap(),
      prefix_output,
    ),
  )
  assert_true(boundary.serialized_output is None)
  assert_true(
    physical_equal(boundary.serialized_generation.unwrap(), generation),
  )
  assert_eq(calls.val, 0)
  assert_true(cancel(boundary))
  assert_true(
    fixture_finish(boundary, initial_work=boundary.work) is Stopped(_),
  )
  assert_true(cleanup(boundary).unwrap())
  assert_true(@relation.completed_output_available(prefix_output))
  assert_true(@relation.completed_output_available(content_output))
  let selected_boundary = composed_local_provider(
    occurrence,
    limits,
    inputs => {
      start_generated_inputs(
        compiled, generation, graph, inputs, provider, limits,
      )
    },
    _ => @connector.ComputeUnsupported,
    boundary_only=true,
  )
  let selected_child = @local.start_managed_provider_with_inputs_and_execution(
    selected_boundary,
    selected,
    [@local.managed_provider_relation_input(read)],
    limits.output_rows,
    500000,
    limits.input,
  ).unwrap()
  assert_true(@local.cancel_managed_provider(selected_child))
  let mut selected_stopped = false
  for _ in 0..<10000 {
    match @local.advance_managed_provider(selected_child, 1).unwrap() {
      @local.Continue(..) => ()
      @local.Stopped(..) => {
        selected_stopped = true
        break
      }
      _ => abort("Cancelled exact generated Model child must stop")
    }
  }
  assert_true(selected_stopped)
  assert_true(@local.cleanup_managed_provider(selected_child).unwrap())
  assert_true(@relation.completed_output_available(prefix_output))
  assert_eq(calls.val, 0)
  let consumer = start_generated_inputs(
    compiled,
    generation,
    graph,
    [@local.managed_provider_relation_input(read)],
    provider,
    standard_limits(),
  ).unwrap()
  assert_true(consumer.prepared is None)
  bind_run(consumer, compiled, definition).unwrap()
  let configuration = evidence_account(@authorization.Allow)
  let permit = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    observe_current=() => Ok((configuration, "2026-10-02T00:00:00.000Z")),
  ).unwrap()
  bind_dispatch_admission(consumer, permit).unwrap()
  serialized_infer_fixture_physical(
    consumer, execution, provider, generated_live,
  )
  let terminal = fixture_finish(consumer)
  guard terminal is Complete(_, ..) else {
    let reason = match terminal {
      Failed(Model(issue), ..) => "mixed Model: " + issue.to_repr().to_string()
      Failed(CallScope(ForeignInput), ..) => "mixed CallScope ForeignInput"
      Failed(CallScope(ForeignOwner), ..) => "mixed CallScope ForeignOwner"
      Failed(CallScope(UnsupportedBindings), ..) =>
        "mixed CallScope UnsupportedBindings"
      Failed(IdentityExport(_), ..) => "mixed IdentityExport"
      Failed(Input(_), ..) => "mixed Input"
      _ => "mixed execution did not complete"
    }
    assert_true(false, msg=reason)
    abort("unreachable failed assertion")
  }
  assert_eq(calls.val, 1)
  let unused = issuance_ledger(65920L)
  assert_true(
    start_observation_issuance(consumer, unused, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(unused).reserved_retention_bytes, 0L)
  // An equally checked second generation under this Run is still not the
  // producer completion consumed by the Model owner.
  let (_, _, _, substitute) = serialized_infer_fixture_material(
    prepared,
    run=Some(compiled),
    definition=Some(definition),
  )
  assert_true(
    start_observation_issuance(consumer, unused, issuance_limits(), generations=[
      substitute.unwrap(),
    ])
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(unused).reserved_retention_bytes, 0L)
  // 16 * 4096 wire workspace + one 128-byte slot + 256-byte borrowed
  // Content inventory. This is an installed bound, not a measured peak.
  let ledger = issuance_ledger(65920L)
  let issued = start_observation_issuance(consumer, ledger, issuance_limits(), generations=[
    generation,
  ]).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 65920L)
  issuance_finish(issued)
  let (observation, _) = observation_issuance_value(issued).unwrap()
  assert_eq(@publication.model_observation_slot_count(observation), Some(1))
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      @publication.run_evidence_value_identity(
        @publication.bound_content_generation_value(
          @publication_host.client_serialization_generation_capture(generation).unwrap(),
        ).unwrap(),
      ),
    ),
  )
  let binding = bind_issued_invocation(consumer, compiled, definition, issued).unwrap()
  assert_true(invocation_binding_output(binding) is Some(_))
  let publishing = start_result_publication(
    binding,
    0,
    publication_result_limits(),
  ).unwrap()
  assert_false(advance_result_publication(publishing, 1).unwrap().0)
  let ready = start_result_publication(binding, 0, publication_result_limits()).unwrap()
  let mut prepared = false
  for _ in 0..<1000 {
    if advance_result_publication(ready, 1).unwrap().0 {
      prepared = true
      break
    }
  }
  assert_true(prepared)
  assert_true(!cleanup(consumer).unwrap())
  assert_true(!cleanup_observation_issuance(issued).unwrap())
  let pending_ledger = issuance_ledger(65920L)
  let pending = start_observation_issuance(
    consumer,
    pending_ledger,
    issuance_limits(),
    generations=[generation],
  ).unwrap()
  assert_false(advance_observation_issuance(pending, 1).unwrap().0)
  generated_live.val = false
  assert_true(
    @input.export_client_content_generation_output(
      generation,
      compiled,
      definition,
      "sha256:" + "1".repeat(64),
    )
    is Err(@input.BindingMismatch),
  )
  assert_true(
    advance_observation_issuance(pending, 1)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_true(observation_issuance_value(pending) is None)
  assert_true(observation_issuance_value(issued) is None)
  assert_true(invocation_binding_output(binding) is None)
  assert_true(invocation_binding_observation(binding) is None)
  assert_true(invocation_binding_invocation(binding) is None)
  assert_true(result_publication_selection(publishing) is None)
  assert_true(advance_result_publication(publishing, 1) is Err(InvalidState))
  assert_true(finish_result_publication(ready) is Err(InvalidState))
  assert_true(!cleanup(consumer).unwrap())
  assert_true(!cleanup_observation_issuance(issued).unwrap())
  assert_eq(
    @resources.ledger_usage(pending_ledger).reserved_retention_bytes,
    65920L,
  )
  assert_true(cleanup_observation_issuance(pending).unwrap())
  assert_true(pending.state.generations.is_empty())
  assert_eq(
    @resources.ledger_usage(pending_ledger).reserved_retention_bytes,
    0L,
  )
  assert_true(release_invocation_binding(binding))
  assert_true(release_result_publication(publishing))
  assert_true(release_result_publication(ready))
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(issued.state.generations.is_empty())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(cleanup(consumer).unwrap())
  assert_true(consumer.serialized_output is None)
  assert_true(@local.cleanup_managed_provider(prefix).unwrap())
  assert_eq(calls.val, 1)
}

///|
fn serialized_infer_fixture_physical(
  active : Execution,
  execution : @environment.ModelExecutionContract,
  provider : @model.ModelProvider,
  live : Ref[Bool],
) -> Unit {
  // Original independently sealed dependency bodies, never supplied CIDs
  // pretending to authorize a media role or a successful physical request.
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(
      @utf8.encode(
        (
          #|{"payload":{"format":"fixture-content/0.1","instructions":"Inspect the exact JSONL attachment."},"self_cid":"sha256:d0ff84aab70965d97df8303954e5ab59e9b554de3251ca53f55da56577eedde2","version":"actql-model-prompt/0.1"}
        ),
      ),
    ),
    Some(
      @utf8.encode(
        (
          #|{"retryable_failures":[],"self_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","version":"actql-model-retry-policy/0.1"}
        ),
      ),
    ),
    Some(
      @utf8.encode(
        (
          #|{"delays_ms":[],"self_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","version":"actql-model-backoff/0.1"}
        ),
      ),
    ),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
    1000000,
    media=[
      (
        "document",
        @utf8.encode(
          (
            #|{"payload":{"classifications":["unknown"],"complete":true,"egress_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","max_bytes":18,"max_frames":null,"max_pages":null,"media_type":"application/x-ndjson","regions":["fixture-region"],"transfer_method":"inline_bytes"},"self_cid":"sha256:03213e7e836021f73b99d57eb5ea5855cd8430cd85b4a4079a8d92eede531507","version":"actql-model-media-input/0.1"}
          ),
        ),
      ),
    ],
  ).unwrap()
  let admitted = @model.admit_model_provider(
    provider,
    execution,
    dependencies,
    (_, prompt) => {
      @environment.model_dependency_identity(prompt) ==
      "sha256:d0ff84aab70965d97df8303954e5ab59e9b554de3251ca53f55da56577eedde2"
    },
  ).unwrap()
  bind_quantity_capacity(active, fixture_quantity_capacity(33L, 500L)).unwrap()
  bind_physical_preflight(active, request => {
    let check : Ref[@model.ModelContentByteCheck?] = Ref(None)
    let position = Ref(0)
    let payload = "{\"id\":2}\n{\"id\":1}\n"
    let finished = Ref(false)
    Ok({
      advance: () => {
        if finished.val {
          return Err(@model.InvalidProvider)
        }
        if check.val is None {
          let input = match
            @model.model_content_input(admitted, request, "document", -1) {
            Ok(Some(value)) => value
            _ => return Err(@model.Content(@model.Role))
          }
          check.val = Some(
            @model.start_model_content_byte_check(
              input,
              "fixture-region",
              "sha256:" + "a".repeat(64),
              None,
              None,
              () => live.val,
            ).unwrap(),
          )
          return Ok(None)
        }
        // The physical fixture owns this one finite original payload. Validate
        // one ASCII byte per quantum before dispatch, charging each byte.
        if position.val < payload.length() {
          @model.update_model_content_bytes(
            check.val.unwrap(),
            @utf8.encode(payload[position.val:position.val + 1].to_owned()),
          ).unwrap()
          |> ignore
          position.val += 1
          return Ok(None)
        }
        let attachment = @model.finish_model_content_bytes(check.val.unwrap()).unwrap()
        finished.val = true
        let physical = @model.model_physical_request_plan(
          request,
          4096L,
          { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
          () => {
            @model.model_provider_synchronous_invoke(provider).unwrap()(request)
          },
          attachments=[attachment],
        ).map(value => Some(value))
        physical
      },
      cleanup: () => true,
    })
  }).unwrap()
}

///|
fn serialized_infer_fixture_output(
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @relation.CompletedOutput,
  @publication.GeneratedContentReference,
  Ref[Bool],
) raise {
  let (output, candidate, live, _) = serialized_infer_fixture_material(prepared)
  (output, candidate, live)
}

///|
fn serialized_infer_fixture_material(
  prepared : @publication_host.PreparedClientProgram,
  run? : @publication_host.ClientCompiledRun? = None,
  definition? : @publication.PublicationContract? = None,
) -> (
  @relation.CompletedOutput,
  @publication.GeneratedContentReference,
  Ref[Bool],
  @publication_host.ClientSerializationGeneration?,
) raise {
  let limits = standard_limits()
  let sequence = @input.prepare_client_serialization_prefix(
    prepared,
    0,
    1,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
    None,
    None,
  ).unwrap()
  let active = @relation.start_bounded_values(
    @bounded.control(),
    sequence,
    2,
    limits.output_values,
    limits.output_values,
    100000,
    100,
    1000,
    10000,
  ).unwrap()
  let mut source = None
  for _ in 0..<10000 {
    match @relation.advance_bounded_values(active, 1).unwrap() {
      BoundedValuesContinue(..) => ()
      BoundedValuesComplete(output, ..) => {
        source = Some(output)
        break
      }
      _ => abort("actual generated input failed")
    }
  }
  let barrier = @publication_host.prepare_client_serialization(
    prepared,
    0,
    1,
    max_work=3,
  ).unwrap()
  let encoder = @publication_host.start_client_serialization_encoder(
    barrier,
    max_rows=2,
    max_bytes=18,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  let input = @publication_host.bind_client_serialization_completed_input(
    barrier,
    source.unwrap(),
    encoder,
  ).unwrap()
  let identity = match run {
    None => None
    Some(compiled) => {
      let wire : @relation.RowWireLimits = {
        max_columns: 100,
        max_order_work: 1000,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 100,
      }
      let scan = @publication_host.start_client_serialization_input_identity(
        input,
        limits.output_values,
        wire,
        wire,
        { max_fields: 100, max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
        10000,
        10000,
      ).unwrap()
      let mut ready = false
      for _ in 0..<10000 {
        if @relation.advance_completed_relation_identity_scan(scan, 7).unwrap().0 {
          ready = true
          break
        }
      }
      assert_true(ready)
      let receipt = @relation.finish_completed_relation_identity_scan(scan).unwrap()
      let identity = @publication_host.bind_client_serialization_input_identity(
        compiled, input, receipt, 16384, 256, 16,
      ).unwrap()
      @relation.cancel_completed_relation_export_receipt(receipt)
      Some(identity)
    }
  }
  let bytes = StringBuilder()
  for phase in 0..<3 {
    if phase > 0 {
      @publication_host.start_client_serialization_input_row(input, phase - 1).unwrap()
    }
    for _ in 0..<10000 {
      match @publication.advance_content_bytes(encoder, 1) {
        ContentBytesContinue(piece, ..) => bytes.write_string(piece)
        ContentBytesReady(piece, ..) => {
          bytes.write_string(piece)
          break
        }
        _ => abort("actual serializer failed")
      }
    }
  }
  assert_eq(bytes.to_string(), "{\"id\":2}\n{\"id\":1}\n")
  let completion = @publication.finish_content_bytes(encoder).unwrap()
  assert_eq(
    completion.content_cid,
    "sha256:982974408fc3063d258439d976049c7f4863d98bedfe933132af17b3636ffd60",
  )
  let reference_limits : @admitted.ReferenceLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }
  let candidate = @publication.prepare_generated_content_reference(
    encoder,
    {
      content_store_id: "fixture",
      content_store_cid: "sha256:" + "1".repeat(64),
      workspace_scope_cid: "sha256:" + "2".repeat(64),
      storage_scope: "workspace",
      retention_class: "fixture",
      expires_at: None,
      availability_evidence_cid: "sha256:" + "3".repeat(64),
      effective_data_policy_cid: match run {
        None => "sha256:" + "4".repeat(64)
        Some(compiled) =>
          @publication.captured_effect_dependency_body_cid(
            @publication_host.client_compiled_run_serialization_policy_body(
              compiled,
            ).unwrap(),
          )
      },
      data_classification: if run is Some(_) {
        "unknown"
      } else {
        "internal"
      },
      issuer_contract_cid: "sha256:" + "5".repeat(64),
      capture_authority_cid: "sha256:" + "6".repeat(64),
    },
    reference_limits,
  ).unwrap()
  let live = Ref(true)
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => {
      live.val &&
      wire == @publication.generated_content_reference_wire(candidate)
    },
    _ => live.val,
  )
  let content = @publication.issue_generated_content_reference(
    candidate, issuer, reference_limits,
  ).unwrap()
  let generation = match run {
    None => None
    Some(compiled) =>
      Some(
        @publication_host.complete_client_serialization_generation(
          compiled,
          definition.unwrap(),
          input,
          identity.unwrap(),
          candidate,
          content,
          () => live.val,
          limits.output_values,
          1000,
        ).unwrap(),
      )
  }
  let output = match generation {
    Some(value) =>
      @publication_host.client_serialization_generation_output_for(
        value,
        run.unwrap(),
      ).unwrap()
    None =>
      @publication_host.complete_client_serialization_output(
        input,
        candidate,
        content,
        () => live.val,
        limits.output_values,
        1000,
      ).unwrap()
  }
  // The generation owns finished bytes independently of the input rows.
  assert_true(@relation.cleanup_bounded_values(active).unwrap())
  assert_true(@relation.completed_output_available(output))
  (output, candidate, live, generation)
}

///|
test "actual serialized Content reaches checked Infer mapping without replaying the producer" {
  for quantum in [1, 7] {
    let prepared = serialized_infer_fixture_program()
    let (output, candidate, live) = serialized_infer_fixture_output(prepared)
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared,
    ).unwrap()
    let limits = standard_limits()
    assert_true(
      @input.prepare_client_infer_prefix(
        prepared,
        0,
        3,
        infer_fixture_installed_contracts(),
        infer_fixture_values,
      )
      is None,
    )
    let segment = if quantum == 1 {
      @relation.prepare_serialization_consumer_segment(
        output,
        2,
        @publication_host.client_standard_values_sequence_limits(),
        100000,
        10000,
      ).unwrap()
    } else {
      @relation.prepare_serialization_infer_input_segment(
        output,
        3,
        @publication_host.client_standard_values_sequence_limits(),
        100000,
        10000,
      ).unwrap()
    }
    for terminal in [0, 1, 3, 4] {
      assert_true(
        @relation.prepare_serialization_consumer_segment(
          output,
          terminal,
          @publication_host.client_standard_values_sequence_limits(),
          100000,
          10000,
        )
        is None,
      )
    }
    assert_eq(@relation.generated_sequence_step_count(segment), 1)
    assert_eq(@relation.generated_sequence_step_index_at(segment, 0), Some(2))
    assert_true(
      @lower.sequence_step(@relation.generated_prepared_sequence(segment), 1)
      is Some(@lower.CompletedProducerBoundary(1)),
    )
    // The selected suffix cannot be run through the full-sequence entry.
    assert_true(
      @relation.execute_generated_sequence(segment, [], limits.input) is Err(_),
    )
    let active = @input.start_client_serialized_infer_input(
      occurrence,
      segment,
      1,
      output,
      limits.input,
      limits.measurement,
      limits.mapping,
    ).unwrap()
    let mut rows = None
    for _ in 0..<10000 {
      match @input.advance_client_infer_input(active, quantum).unwrap() {
        Continue(..) => ()
        Complete(value, ..) => {
          rows = Some(value)
          break
        }
        _ => abort("serialized input suffix failed")
      }
    }
    let rows = rows.unwrap()
    assert_eq(@relation.prepared_infer_rows_count(rows), 1)
    guard @relation.prepared_infer_rows_value(rows, 0, 0).unwrap().value
      is @admitted.Reference(reference) else {
      abort("original typed Content lost")
    }
    guard @relation.completed_cell(output, 0, 0)
      is Some(@relation.Captured(original)) &&
      original is @admitted.Reference(original_reference) else {
      abort("original completion must expose the issued opaque Ref")
    }
    assert_true(physical_equal(reference, original_reference))
    assert_eq(
      @admitted.reference_identity_cid(reference),
      @publication.generated_content_reference_identity(candidate),
    )
    assert_eq(
      @admitted.reference_wire(reference),
      @publication.generated_content_reference_wire(candidate),
    )
    let completion = @input.client_infer_completion_preparation(active, rows).unwrap()
    assert_true(@relation.infer_completion_matches_rows(completion, rows))
    assert_eq(@relation.completion_preparation_terminal_step(completion), 3)
    let consumer = @relation.acquire_prepared_infer_rows(rows).unwrap()
    assert_true(@input.cleanup_client_infer_input(active) is Ok(false))
    assert_true(@relation.completed_output_available(output))
    assert_true(@relation.release_prepared_infer_rows_use(consumer))
    assert_true(@input.cleanup_client_infer_input(active) is Ok(true))
    assert_true(@input.cleanup_client_infer_input(active) is Ok(true))
    assert_true(@relation.completed_output_available(output))
    live.val = false
    assert_false(@relation.completed_output_available(output))
  }
}

///|
test "serialized Infer completion uses its selected prefix before a later checked projection" {
  let prepared = serialized_infer_fixture_program(trailing_projection=true)
  let (output, _, live) = serialized_infer_fixture_output(prepared)
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let limits = standard_limits()
  let segment = @relation.prepare_serialization_infer_input_segment(
    output,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
  ).unwrap()
  assert_eq(@relation.generated_sequence_step_count(segment), 1)
  assert_eq(@relation.generated_sequence_step_index_at(segment, 0), Some(2))
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let semantic = @lower.prepare_sequence_with_infer_boundary(
    owner,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    serialization=Some(1),
  ).unwrap()
  let contracts = @relation.admit_relation_registry(
    @canonical.from_json(
      @json.parse(infer_fixture_registry),
      10000,
      100,
      100000,
    ),
    @canonical.from_json(@json.parse(infer_fixture_values), 10000, 100, 100000),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let whole = @relation.prepare_generated_sequence(
    contracts,
    semantic,
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 2).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let selected = @relation.select_generated_sequence_range(whole, 2, 2).unwrap()
  assert_true(@lower.sequence_count(semantic) > 3)
  let active = @input.start_client_serialized_infer_input(
    occurrence,
    segment,
    1,
    output,
    limits.input,
    limits.measurement,
    limits.mapping,
  ).unwrap()
  let mut rows = None
  for _ in 0..<10000 {
    match @input.advance_client_infer_input(active, 7).unwrap() {
      Continue(..) => ()
      Complete(value, ..) => {
        rows = Some(value)
        break
      }
      _ => abort("original serialized prefix did not complete")
    }
  }
  let rows = rows.unwrap()
  let completion = @relation.prepare_infer_completion(selected, rows, 3).unwrap()
  assert_true(@relation.infer_completion_matches_rows(completion, rows))
  assert_eq(@relation.completion_preparation_terminal_step(completion), 3)
  assert_true(
    @relation.prepare_infer_completion(
      @relation.select_generated_sequence_range(whole, 1, 1).unwrap(),
      rows,
      3,
    )
    is None,
  )
  assert_true(@input.cleanup_client_infer_input(active).unwrap())
  assert_true(@relation.prepare_infer_completion(selected, rows, 3) is None)
  assert_true(@relation.completed_output_available(output))
  live.val = false
  assert_false(@relation.completed_output_available(output))
}

///|
test "completed Infer mapping rejects equal foreign owners and keeps borrowed cleanup separate" {
  let prepared = fixture_prepared()
  let (producer, _, _, _) = call_identity_fixture(prepared)
  let live = Ref(true)
  let output = @relation.restrict_completed_output(
    @input.client_infer_completed_input(producer).unwrap(),
    () => live.val,
  )
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let foreign = @publication_host.prepared_client_composed_infer_occurrence(
    fixture_prepared(),
  ).unwrap()
  let limits = standard_limits()
  assert_true(
    @input.start_client_completed_infer_input(foreign, output, limits.mapping)
    is Err(Mapping(ForeignInput)),
  )
  let active = @input.start_client_completed_infer_input(
    occurrence,
    output,
    limits.mapping,
  ).unwrap()
  assert_true(@input.cleanup_client_infer_input(active) is Ok(false))
  assert_true(@input.cancel_client_infer_input(active))
  assert_true(
    @input.advance_client_infer_input(active, 1).unwrap() is Stopped(..),
  )
  assert_true(@input.cleanup_client_infer_input(active) is Ok(true))
  assert_true(@relation.completed_output_available(output))
  assert_true(@input.cleanup_client_infer_input(producer) is Ok(true))
  assert_true(@input.client_infer_completed_input(producer) is None)
  // Logical cleanup and a borrowed representation's physical lifetime are
  // separate facts. Narrow that original lifetime through its installed fence.
  live.val = false
  assert_false(@relation.completed_output_available(output))
  assert_true(
    @input.start_client_completed_infer_input(
      occurrence,
      output,
      limits.mapping,
    )
    is Err(Mapping(InputUnavailable)),
  )
}

///|
test "serialized Infer refuses foreign occurrences and revoked Content after positive work" {
  let prepared = serialized_infer_fixture_program()
  let (output, _, live) = serialized_infer_fixture_output(prepared)
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let foreign = @publication_host.prepared_client_composed_infer_occurrence(
    serialized_infer_fixture_program(),
  ).unwrap()
  let limits = standard_limits()
  let sequence = @relation.prepare_serialization_infer_input_segment(
    output,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
  ).unwrap()
  assert_true(
    @input.start_client_serialized_infer_input(
      foreign,
      sequence,
      1,
      output,
      limits.input,
      limits.measurement,
      limits.mapping,
    )
    is Err(UnsupportedProgram),
  )
  let active = @input.start_client_serialized_infer_input(
    occurrence,
    sequence,
    1,
    output,
    limits.input,
    limits.measurement,
    limits.mapping,
  ).unwrap()
  guard @input.advance_client_infer_input(active, 1).unwrap() is Continue(work~) else {
    abort("expected positive bounded suffix work")
  }
  assert_true(work > 0L)
  live.val = false
  let mut refused = false
  for _ in 0..<10000 {
    match @input.advance_client_infer_input(active, 1).unwrap() {
      Continue(..) => ()
      Failed(_, ..) => {
        refused = true
        break
      }
      _ => abort("revoked original Content cannot complete mapping")
    }
  }
  assert_true(refused)
  assert_true(@input.client_infer_completed_input(active) is None)
  assert_true(@input.cleanup_client_infer_input(active) is Ok(true))
  assert_true(@input.cleanup_client_infer_input(active) is Ok(true))
  assert_true(
    @relation.prepare_serialization_infer_input_segment(
      output,
      3,
      @publication_host.client_standard_values_sequence_limits(),
      100000,
      10000,
    )
    is None,
  )
  assert_true(
    @relation.prepare_serialization_consumer_segment(
      output,
      2,
      @publication_host.client_standard_values_sequence_limits(),
      100000,
      10000,
    )
    is None,
  )
}

///|
test "serialized Infer cancellation and mapping exhaustion preserve generation custody" {
  for cancel in [true, false] {
    let prepared = serialized_infer_fixture_program()
    let (output, _, live) = serialized_infer_fixture_output(prepared)
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared,
    ).unwrap()
    let limits = standard_limits()
    let sequence = @relation.prepare_serialization_infer_input_segment(
      output,
      3,
      @publication_host.client_standard_values_sequence_limits(),
      100000,
      10000,
    ).unwrap()
    let active = @input.start_client_serialized_infer_input(
      occurrence,
      sequence,
      1,
      output,
      limits.input,
      limits.measurement,
      if cancel {
        limits.mapping
      } else {
        { ..limits.mapping, max_work: 0, }
      },
    ).unwrap()
    guard @input.advance_client_infer_input(active, 1).unwrap()
      is Continue(work~) else {
      abort("expected positive suffix work before stopping")
    }
    assert_true(work > 0L)
    assert_true(@input.cleanup_client_infer_input(active) is Ok(false))
    if cancel {
      assert_true(@input.cancel_client_infer_input(active))
    }
    let mut ended = false
    for _ in 0..<10000 {
      match @input.advance_client_infer_input(active, 1).unwrap() {
        Continue(..) => ()
        Stopped(..) if cancel => {
          ended = true
          break
        }
        Failed(Mapping(WorkLimit), ..) if !cancel => {
          ended = true
          break
        }
        _ =>
          abort(
            "no Model input completion after cancellation or exhausted mapping",
          )
      }
    }
    assert_true(ended)
    assert_true(@input.cleanup_client_infer_input(active) is Ok(true))
    assert_true(@input.cleanup_client_infer_input(active) is Ok(true))
    assert_true(@relation.completed_output_available(output))
    assert_true(live.val)
    live.val = false
    assert_false(@relation.completed_output_available(output))
  }
}

///|
fn generated_original_startup_plan(
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.ClientInferPlanGraph raise {
  let step = 3
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let sequence = @publication_host.client_standard_values_sequence_limits()
  assert_true(
    @publication_host.issue_prepared_client_serialization_plan_graph(
      prepared, 0, 1, policy, 2, 18, 3, sequence, 100000, 10000, 100,
    )
    is Err(_),
  )
  let content = @publication_host.issue_prepared_client_serialization_plan_component(
    prepared, 0, 1, policy, 2, 18, 3, sequence, 100000, 10000, 100,
  ).unwrap()
  let component = @canonical.from_json(
    @json.parse(@publication_host.client_serialization_plan_graph_wire(content)),
    10000,
    100,
    100000,
  )
  assert_true(
    @canonical.object_field(component, "root_refs")
    is Some(@canonical.Array(roots)) &&
    @canonical.array_values(roots).is_empty(),
  )
  // Independently sealed Model execution vector. These references do not
  // admit provider bodies, media transport or current egress authority.
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":1,"max_total_cost_units":0,"max_total_duration_ms":500,"max_total_token_reservation":33,"max_total_wire_bytes":133072,"media_input_contracts":{"document":"sha256:03213e7e836021f73b99d57eb5ea5855cd8430cd85b4a4079a8d92eede531507"},"model_task_contract_cid":"sha256:836444f3888092768af981447509670f2efc05bc047bf2665a951603c93b160d","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097","version":"actql-model-execution-contract/0.1"}
  let execution = @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    step,
    @utf8.encode(execution_wire),
    "sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
    100000,
  ).unwrap()
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let graph = @publication_host.issue_prepared_client_serialized_infer_plan_graph(
    occurrence, content, execution, sequence, 100000, 10000, 100,
  ).unwrap()
  graph
}

///|
test "generated original Model startup uses the same broader parent before any provider invocation" {
  let prepared = serialized_infer_fixture_program()
  let graph = generated_original_startup_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, graph)
  let (_, _, _, generation) = serialized_infer_fixture_material(
    prepared,
    run=Some(compiled),
    definition=Some(definition),
  )
  let limits = standard_limits()
  // Explicit logical component frames. The parent also funds Content/Effect
  // duties, so it is deliberately broader than this one Model's ceiling.
  let ledger = @resources.create_ledger(limits.model.ledger).unwrap()
  let quantities : @model.ModelQuantityCapacity = {
    limits: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
  @resources.configure_quantities(ledger, quantities.limits).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, graph, ledger, bootstrap, 12, 8, 4,
  ).unwrap()
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, graph, 7L, 5L,
  ).unwrap()
  let calls = Ref(0)
  let provider = original_funded_start_provider(calls)
  let active = start_original_generated(
    prepared,
    compiled,
    generation.unwrap(),
    graph,
    provider,
    limits,
    definition,
    consumer,
    7L,
    5L,
    100L,
    5L,
  ).unwrap()
  bind_run(active, compiled, definition).unwrap()
  bind_quantity_capacity(active, quantities).unwrap()
  // Startup only: preserve the installed media checks and forbid physical send.
  require_model_call_entry(active).unwrap()
  restrict_model_send_slots(active, [false]).unwrap()
  for _ in 0..<10000 {
    if active.model is Some(_) {
      break
    }
    assert_true(
      advance(active, 1).unwrap() is Continue(_),
      msg="same generated parent startup must not refuse RequestIdentity",
    )
  }
  assert_true(active.model is Some(_))
  assert_eq(calls.val, 0)
  assert_true(active.original_preparation.unwrap().startup is Some(_))
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(_))
  assert_true(cleanup(active).unwrap())
  original_composed_test_release(ledger, consumer)
}

///|
test "generated Model consumes its original physical allowance through Content preflight and actual provider call" {
  for full_startup in [false, true] {
    let prepared = serialized_infer_fixture_program()
    let graph = generated_original_startup_plan(prepared)
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared,
    ).unwrap()
    let selected = prepared_composed_bounds(occurrence, graph).unwrap()
    let (compiled, definition) = original_input_capacity_run(prepared, graph)
    let (_, _, live, generation) = serialized_infer_fixture_material(
      prepared,
      run=Some(compiled),
      definition=Some(definition),
    )
    // These are independently declared startup controls, not the complete
    // native Model allowance. The same Plan funds both, once, on one parent.
    let startup_retained = if full_startup {
      selected.model.ledger.retained_bytes
    } else {
      14464L
    }
    let startup_execution = if full_startup {
      selected.model.ledger.execution_bytes
    } else {
      14464L
    }
    let model_limits = {
      ..selected.model.ledger,
      retained_bytes: selected.model.ledger.retained_bytes + startup_retained,
      execution_bytes: selected.model.ledger.execution_bytes + startup_execution,
    }
    let ledger = @resources.create_ledger({
      ..model_limits,
      retained_bytes: model_limits.retained_bytes + 3L + 7L,
      execution_bytes: model_limits.execution_bytes + 2L + 5L,
    }).unwrap()
    @resources.configure_quantities(ledger, {
      tokens: 33L,
      cost_units: 0L,
      duration_ms: 500L,
    }).unwrap()
    let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
    let scope = @publication_host.begin_client_model_read_scope(
      compiled,
      definition,
      graph,
      ledger,
      bootstrap,
      12,
      8,
      4,
      model_limits=Some(model_limits),
    ).unwrap()
    let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
    let consumer = @publication_host.claim_client_model_read_preparation(
      read, compiled, definition, graph, 7L, 5L,
    ).unwrap()
    let calls = Ref(0)
    let provider = original_funded_start_provider(calls)
    let active = start_original_generated(
      prepared,
      compiled,
      generation.unwrap(),
      graph,
      provider,
      standard_limits(),
      definition,
      consumer,
      7L,
      5L,
      startup_retained,
      startup_execution,
    ).unwrap()
    assert_true(
      @publication_host.client_model_read_consumer_model_limits(
        consumer, compiled, definition, graph,
      ).unwrap()
      is Some(original) &&
      physical_equal(original, model_limits),
    )
    bind_run(active, compiled, definition).unwrap()
    let account = evidence_account(@authorization.Allow)
    let permit = @publication_host.issue_client_infer_dispatch_admission(
      compiled,
      definition,
      account,
      "fixture-principal",
      "2026-10-12T00:00:00.000Z",
      observe_current=() => Ok((account, "2026-10-12T00:00:00.000Z")),
    ).unwrap()
    bind_dispatch_admission(active, permit).unwrap()
    serialized_infer_fixture_physical(
      active,
      @publication_host.client_infer_plan_graph_execution_contract(graph),
      provider,
      live,
    )
    let terminal = fixture_finish(active)
    assert_true(
      terminal is Complete(_, ..),
      msg="original generated call must complete through physical preflight",
    )
    assert_eq(calls.val, 1)
    assert_true(
      @publication_host.client_model_read_consumer_model_limits(
        consumer, compiled, definition, graph,
      )
      is Err(@publication_host.ForeignRun),
    )
    let usage = @resources.quantity_usage(ledger)
    assert_eq(usage.consumed.tokens, 3L)
    assert_eq(@resources.ledger_usage(ledger).attempts, 1)
    assert_true(cleanup(active).unwrap())
    original_composed_test_release(ledger, consumer)
    assert_eq(@resources.quantity_usage(ledger), usage)
  }
}
