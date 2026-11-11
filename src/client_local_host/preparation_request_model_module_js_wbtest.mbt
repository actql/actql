///|
fn request_model_module_declaration() -> @row_source_host.RowDeclaration {
  @row_source_host.generate_row_declaration(
    "model/source-fixture",
    "model_fixture",
    "model_fixture/0.1",
    [
      {
        resource: "r",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "number", nullable: false, },
          { name: "amount", value_type: "number", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 2,
    },
  ).unwrap()
}

///|
// Real Request/compiler/Source declaration/module/Scope owners. Installation
// and Resource admission are explicit component fixtures, not ordinary IO.
fn request_model_module_fixture(
  captured : Bool,
  current? : () -> Bool = () => true,
  original_input? : (
    ClientRequestPreparation[Array[Int]],
    Array[Int],
    @publication_host.PreparedClientProgram,
    @environment.ModelExecutionContract,
  )? = None,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  @publication_host.ClientTaskCompilation,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @row_source_host.RowDeclaration,
) raise {
  let declaration = request_model_module_declaration()
  let (parent, input, prepared) = match original_input {
    Some((parent, input, prepared, _)) => {
      assert_false(captured)
      (parent, input, prepared)
    }
    None =>
      request_model_input_fixture(
        captured~,
        current~,
        declaration=if captured { Some(declaration) } else { None },
      )
  }
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  if captured {
    for stage in 0..<2 {
      let facts = @publication_host.prepared_client_source_evidence_facts(
        prepared, stage, 0,
      ).unwrap()
      assert_eq(facts.source_ref, declaration.views[0].source_ref)
      assert_eq(facts.source_contract_cid, declaration.views[0].view_cid)
    }
  }
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let (occurrence, execution) = match original_input {
    Some((_, _, _, execution)) =>
      (
        @publication_host.prepared_client_composed_infer_occurrence(prepared).unwrap(),
        execution,
      )
    None => request_model_graph_inputs(prepared)
  }
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let compilation = prepare_request_model_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  // The first real compiled Run/Definition below must already be backed by
  // this SAME capacity, alongside the original Graph and compiler output.
  assert_true(
    parent.program_invocation_quote is Some((r, e)) &&
    @resources.preparation_capacity_working_extents(
      parent.program_capacity.unwrap(),
      input,
    ) ==
    Ok((r, e)),
  )
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "model-module-fixture", "same-original", "2026-10-31T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "model-module-fixture",
  ).unwrap()
  (
    parent, input, prepared, compilation, compiled, definition, request, contracts,
    holder, declaration,
  )
}

///|
test "Model module constructor reserves before factory and retains same module through Scope adoption and retirement" {
  for captured in [false, true] {
    let (
      parent,
      input,
      prepared,
      compilation,
      compiled,
      definition,
      request,
      contracts,
      holder,
      declaration,
    ) = request_model_module_fixture(captured)
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let calls = Ref(0)
    let observed = Ref(true)
    let factory = (_ : @execution.ExecutionCapacity) => {
      calls.val += 1
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      observed.val = observed.val &&
        parent.phase == Selecting &&
        during.0 > before.0 &&
        during.1 > before.1
      observed.val = observed.val &&
        abort_request_preparation_after_cleanup(parent) is Err(WrongPhase)
      []
    }
    let graph = compilation.infers[0]
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared,
    ).unwrap()
    let plan = if captured {
      let original = match
        prepare_request_model_capture_module(
          parent,
          input,
          request,
          compiled,
          definition,
          compilation,
          [declaration, declaration],
          original_row_query_contract_fixture,
          original_row_evidence_contract_fixture,
          [4096L, 4096L],
          [2048L, 2048L],
          contracts,
          true,
          0,
          factory,
        ) {
        Ok(value) => value
        Err(ModelSource(@row_source_host.Source(reason))) =>
          fail("original Source: " + @debug.to_string(reason))
        Err(issue) => {
          let original : Error = issue
          fail(@debug.to_string(original))
        }
      }
      assert_true(
        parent.program_captured is Some(same) && physical_equal(same, original),
      )
      assert_eq(original.captures.length(), 2)
      for index in 0..<2 {
        let capture = original.captures[index]
        assert_true(
          capture.acquisition is Some(acquisition) &&
          physical_equal(
            @row_source_host.row_acquisition_requirement(acquisition),
            capture.requirement,
          ),
        )
      }
      prepare_installed_mock_model_capture_plan_binding(
        original, compiled, definition, occurrence, graph, effect_model_plan_limits,
        500L, 700L, 20, 20, 20,
      ).unwrap()
    } else {
      let original = prepare_request_model_source_free_module(
        parent, input, request, compiled, definition, compilation, contracts, true,
        0, factory,
      ).unwrap()
      assert_true(
        parent.program_source_free is Some(same) &&
        physical_equal(same, original),
      )
      prepare_installed_mock_model_source_free_plan(
        original, request, compiled, definition, occurrence, graph, effect_model_plan_limits,
        500L, 700L, 20, 20, 20,
      ).unwrap()
    }
    assert_eq(calls.val, 1)
    assert_true(observed.val)
    assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
    let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
    complete_request_model_preparation(parent, input, plan).unwrap()
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    let run = begin_request_model_managed_run(parent, request, scope).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope, compiled, definition, graph, true,
      ).unwrap(),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
// The component remains an explicit constructor port. Real Request capacity
// and original lowering are exercised here; ordinary physical IO is separate.
test "source-free Model component enters its one module after original input and capacity are retained" {
  let (
    parent,
    input,
    _,
    compilation,
    compiled,
    definition,
    request,
    contracts,
    holder,
    _,
  ) = request_model_module_fixture(false)
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let backed = Ref(false)
  let input_prefix : Ref[@execution.GeneratedSequence?] = Ref(None)
  let original = prepare_request_model_source_free_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    contracts,
    true,
    1,
    _ => [],
    component_factory=Some((extent, prefix, _) => {
      calls.val += 1
      input_prefix.val = Some(prefix)
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      )
      backed.val = parent.phase == Selecting &&
        during is Ok((r, e)) &&
        r > before.0 &&
        e > before.1
      @local.managed_provider(_ => false, _ => Some(extent), (_, _, _, _, _) => {
        Err(@connector.ComputeUnsupported)
      })
    }),
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_true(backed.val && input_prefix.val is Some(_))
  assert_true(
    parent.program_source_free is Some(same) && physical_equal(same, original),
  )
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model module current refusal enters no factory and preserves original failed Request custody" {
  let armed = Ref(false)
  let (
    parent,
    input,
    _,
    compilation,
    compiled,
    definition,
    request,
    contracts,
    holder,
    _,
  ) = request_model_module_fixture(false, current=() => !armed.val)
  let calls = Ref(0)
  armed.val = true
  assert_true(
    prepare_request_model_source_free_module(
      parent,
      input,
      request,
      compiled,
      definition,
      compilation,
      contracts,
      true,
      0,
      _ => {
        calls.val += 1
        []
      },
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_eq(calls.val, 0)
  assert_true(
    parent.phase == ProgramBodyFailed &&
    parent.program_source_free is None &&
    parent.program_compilation is Some(_),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model captured module retains original protocol refusal without factory or second constructor" {
  let (
    parent,
    input,
    _,
    compilation,
    compiled,
    definition,
    request,
    contracts,
    holder,
    declaration,
  ) = request_model_module_fixture(true)
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let calls = Ref(0)
  let invoke = () => {
    prepare_request_model_capture_module(
      parent,
      input,
      request,
      compiled,
      definition,
      compilation,
      [declaration, declaration],
      "{}",
      original_row_evidence_contract_fixture,
      [4096L, 4096L],
      [2048L, 2048L],
      contracts,
      true,
      0,
      _ => {
        calls.val += 1
        []
      },
    )
  }
  assert_true(invoke() is Err(ModelSource(@row_source_host.InvalidContracts)))
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(invoke() is Err(Preparation(ForeignOriginal)))
  assert_eq(calls.val, 0)
  assert_true(
    parent.phase == ProgramBodyFailed && parent.program_captured is None,
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model compiler metadata grow refusal keeps emitted artifact on original failed Request before Run issuance" {
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let observed = Ref(false)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    if selected.val is Some(owner) &&
      owner.program_compilation is Some(_) &&
      owner.program_invocation_quote is Some(_) {
      observed.val = true
      false
    } else {
      true
    }
  })
  let held = borrow_request_model_plan_input(parent, input).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  selected.val = Some(parent)
  assert_true(
    prepare_request_model_compilation(
      parent,
      input,
      graph,
      contracts,
      manifests~,
      compilation_limits=limits,
    )
    is Err(Preparation(Capacity(_))),
  )
  selected.val = None
  assert_true(
    observed.val &&
    parent.phase == ProgramBodyFailed &&
    parent.program_compilation is Some(@publication_host.Tasks(original)) &&
    physical_equal(original.infers[0], graph) &&
    parent.program_invocation_quote is Some(_),
  )
  assert_true(
    parent.program_source_free is None && parent.program_captured is None,
  )
  assert_false(@resources.return_preparation_body_borrow(held).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model Scope refuses a copied module even with same original compiler and unchanged Plan fields" {
  let (parent, input, plan, held) = request_model_fixture()
  let original = plan.source_free.unwrap()
  let copied = { ..original, configuration: original.configuration, }
  let foreign = { ..plan, source_free: Some(copied), }
  let before = request_preparation_accounting(parent)
  assert_true(
    prepare_request_model_read_scope(parent, input, foreign)
    is Err(ForeignOriginal),
  )
  assert_true(parent.program_model is None && parent.phase == ModelPlanReserved)
  assert_eq(request_preparation_accounting(parent), before)
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  complete_request_model_preparation(parent, input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(held).unwrap())
  let run = begin_request_model_managed_run(parent, plan.request, scope).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      plan.compiled,
      plan.definition,
      plan.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
// Exact public Source and installation DATA from the independent packed fixture.
// Existing component admission supplies this Request; no Model IO is performed.
fn request_model_guard_distinct_input() -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  @environment.ModelExecutionContract,
) raise {
  let document = "FROM (SELECT 7 AS id, 0 AS position UNION ALL SELECT 8 AS id, 1 AS position) |> ASSERT UNIQUE BY (id) |> WHERE position = 0 |> SELECT id |> EXTEND 'urgent' AS text |> INFER `model-task:packed-risk.v1` INPUT (text = text) AS assessment"
  let environment_wire =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:a19d4ee00ad1dc21744715592f74b7a4d21ab457da6980cab2dd35a371781cc7","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":4096,"max_replacements":4096,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[{"authored_model_selector":"packed-risk-model","connector_id":"models/packed","contract_cid":"sha256:b1014443602f88d4b88efb798b1941a6ea605a6f101841018f2ed93d345692e4","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:b933a5679a05948a057b3a4241256db0705f92dfbd26e8f595a7311236b09788","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:packed-risk.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let environment = @publication_host.admit_client_check_environment(
    environment_wire,
    "sha256:a19d4ee00ad1dc21744715592f74b7a4d21ab457da6980cab2dd35a371781cc7",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment, "{\"environmentCid\":\"sha256:a19d4ee00ad1dc21744715592f74b7a4d21ab457da6980cab2dd35a371781cc7\",\"aliases\":[]}",
  ).unwrap()
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let domain = {
    ..effect_model_plan_limits,
    retained_bytes: ordinary.retained_bytes,
    execution_bytes: ordinary.execution_bytes,
  }
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(
      input,
      initial_limits=Some(
        @resources.add_ledger_limits(ordinary, domain).unwrap(),
      ),
    ),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, document.length().to_int64(), 0L).unwrap()
  parse_request_query_syntax(parent, input, document, @frontend.Text).unwrap()
  |> ignore
  lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    None,
    public_primary=true,
  ).unwrap()
  |> ignore
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    environment,
    None,
    [],
    @publication_host.client_standard_program_preparation_limits().checking,
  ).unwrap()
  prepare_program_check_input(child).unwrap()
  prepare_program_check_prelude(child).unwrap() |> ignore
  prepare_program_check_registry(child).unwrap() |> ignore
  prepare_program_check_contents(child).unwrap() |> ignore
  prepare_program_check_references(child).unwrap() |> ignore
  prepare_program_check_policies(child).unwrap() |> ignore
  prepare_program_check_values(child).unwrap() |> ignore
  prepare_program_check_views(child).unwrap() |> ignore
  prepare_program_check_carriers(child).unwrap() |> ignore
  prepare_program_check_requests(child).unwrap() |> ignore
  reconcile_program_check_requests(child).unwrap()
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("guard-distinct original checker")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":1,"max_total_cost_units":0,"max_total_duration_ms":500,"max_total_token_reservation":33,"max_total_wire_bytes":66536,"media_input_contracts":{},"model_task_contract_cid":"sha256:b1014443602f88d4b88efb798b1941a6ea605a6f101841018f2ed93d345692e4","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:4a8c65bdf83e56d77622a3f79bc954e4d4fecc2307e7cc5c101f51165c136277","version":"actql-model-execution-contract/0.1"}
  let execution = @publication_host.read_client_infer_occurrence_model_execution(
    occurrence,
    @utf8.encode(execution_wire),
    "sha256:4a8c65bdf83e56d77622a3f79bc954e4d4fecc2307e7cc5c101f51165c136277",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  (parent, input, prepared, execution)
}

///|
test "original source-free Model Host preserves the guard-distinct graph and offset" {
  let original_input = request_model_guard_distinct_input()
  let (
    parent,
    input,
    prepared,
    compilation,
    compiled,
    definition,
    request,
    contracts,
    holder,
    _,
  ) = request_model_module_fixture(false, original_input=Some(original_input))
  let graph = compilation.infers[0]
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let component : Ref[@local.ManagedProvider?] = Ref(None)
  let model_open_calls = Ref(0)
  let provider_limits = @infer_host.standard_limits()
  let original_prefix : Ref[@execution.GeneratedSequence?] = Ref(None)
  let original = prepare_request_model_source_free_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    contracts,
    true,
    1,
    _ => [],
    component_factory=Some((_, prefix, _) => {
      original_prefix.val = Some(prefix)
      let provider = @infer_host.composed_local_provider(
        occurrence,
        provider_limits,
        _ => {
          model_open_calls.val += 1
          Err(@infer_host.InvalidAdvance)
        },
        _ => @connector.ComputeUnsupported,
        input_prefix=Some(prefix),
      )
      component.val = Some(provider)
      provider
    }),
  ).unwrap()
  let selected = original.configuration.unwrap()
  let plan = prepare_installed_mock_model_source_free_plan(
    original, request, compiled, definition, occurrence, graph, effect_model_plan_limits,
    500L, 700L, 20, 20, 20,
  ).unwrap()
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  complete_request_model_preparation(parent, input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  let run = begin_request_model_managed_run(parent, request, scope).unwrap()
  assert_true(
    physical_equal(require_installed_managed_run(run).unwrap(), parent.ledger),
  )
  let assets = @publication_host.client_local_product_assets()
  let opened = open_installed_managed_source_free_host(
    run,
    prepared,
    request,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    true,
  ).unwrap()
  let captured = run.source_free_captured.unwrap()
  let actual_graph = @strategy.captured_dag_graph(captured)
  let same_graph = physical_equal(actual_graph, selected.graph)
  let same_offset = @strategy.captured_compute_first_task(captured) ==
    selected.capacity_plan.graph_offset
  let provider = component.val.unwrap()
  let prefix = original_prefix.val.unwrap()
  assert_true(@local.managed_provider_accepts(provider, original.sequences[0]))
  assert_true(
    @local.managed_provider_capacity(provider, original.sequences[0]) is Some(_),
  )
  assert_eq(@execution.generated_sequence_step_count(prefix), 12)
  assert_eq(
    @publication_host.client_infer_occurrence_coordinates(occurrence).2,
    12,
  )
  let registration = @connector.capability_registration_at(selected.registry, 0).unwrap()
  let module_for = fn(candidate) {
    @local.prepare_local_compute_module(
      selected.registry,
      registration,
      original.sequences,
      selected.capacity_plan.execution,
      selected.capacity_plan.measurement,
      1000,
      1,
      managed_capacity=selected.capacity,
      managed_providers=[candidate],
    ).unwrap()
  }
  let original_module = module_for(provider)
  // Independent original Source coordinates: two Values roots, UNION ALL,
  // then its guard; no success oracle is obtained from a returned Result.
  assert_true(
    @local.local_module_bounded_values_obligation(original_module, 0, 0),
  )
  assert_true(
    @local.local_module_bounded_values_obligation(original_module, 0, 3),
  )
  assert_true(
    @local.local_module_bounded_append_obligation(original_module, 0, 6),
  )
  assert_true(
    @local.local_module_bounded_relation_obligation(
      original_module,
      0,
      7,
      @local.Assertion,
    ),
  )
  assert_false(
    @local.local_module_bounded_set_obligation(original_module, 0, 6),
  )
  assert_false(
    @local.local_module_bounded_cross_join_obligation(original_module, 0, 6),
  )
  assert_false(
    @local.local_module_bounded_append_obligation(original_module, 0, 7),
  )
  let unproven_provider = @local.managed_provider_with_inputs(
    actual => @local.managed_provider_accepts(provider, actual),
    actual => @local.managed_provider_capacity(provider, actual),
    (actual, inputs, rows, bytes, execution) => {
      @local.start_managed_provider_with_inputs_and_execution(
        provider, actual, inputs, rows, bytes, execution,
      )
    },
  )
  assert_false(
    @local.local_module_bounded_append_obligation(
      module_for(unproven_provider),
      0,
      6,
    ),
  )
  let (foreign_parent, foreign_input, foreign_prepared, _) = request_model_guard_distinct_input()
  let foreign_occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    foreign_prepared,
  ).unwrap()
  let foreign_prefix = prepare_client_composed_infer_prefix(
    foreign_prepared,
    foreign_occurrence,
    contracts,
    assets.values,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
  ).unwrap()
  assert_eq(@execution.generated_sequence_step_count(foreign_prefix), 12)
  assert_false(
    physical_equal(
      @execution.generated_sequence_owner(foreign_prefix),
      @execution.generated_sequence_owner(prefix),
    ),
  )
  for
    candidate in [
      @local.managed_provider_with_infer_relation_prefix(
        unproven_provider,
        foreign_prefix,
        12,
        provider_limits.input,
        provider_limits.measurement,
      ),
      @local.managed_provider_with_infer_relation_prefix(
        unproven_provider,
        prefix,
        13,
        provider_limits.input,
        provider_limits.measurement,
      ),
      @local.managed_provider_with_infer_relation_prefix(
        unproven_provider,
        @execution.select_generated_sequence_step(prefix, 0).unwrap(),
        12,
        provider_limits.input,
        provider_limits.measurement,
      ),
    ] {
    assert_false(
      @local.local_module_bounded_append_obligation(module_for(candidate), 0, 6),
    )
  }
  abort_request_preparation_after_cleanup(foreign_parent).unwrap()
  assert_eq(@resources.ledger_usage(foreign_parent.ledger).live_reservations, 0)
  ignore(foreign_input)
  @strategy.stop_captured_dag(captured)
  @strategy.refresh_captured_retention(captured)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, graph, true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(model_open_calls.val, 0)
  assert_true(same_graph && same_offset)
  assert_true(
    opened is Some(_),
    msg="the original bounded Model prefix must configure its Host",
  )
}
