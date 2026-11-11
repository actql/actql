///|
// Actual existing Request check/compiler/adoption, declared Source and RowRun.
// Physical Account/transport/stop are explicit ports, not normal acceptance.
fn whole_source_result_publication_fixture(
  retained_output : Bool,
  selected_result? : Bool = false,
  filtered_root? : Bool = false,
  filtered_rows? : Bool = false,
  native_geometry? : Bool = false,
) -> Unit raise {
  let declaration = pure_provider_declaration()
  let document = if filtered_rows {
    (
      #|{"version":"actql/0.1","id":"whole-source-plan","stages":[{"id":"read","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"filter":"id > 1","as":"eligible"},{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
    )
  } else if filtered_root {
    (
      #|{"version":"actql/0.1","id":"whole-source-plan","stages":[{"id":"read","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"filter":"true","as":"eligible"},{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
    )
  } else {
    (
      #|{"version":"actql/0.1","id":"whole-source-plan","stages":[{"id":"read","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
    )
  }
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(pure_provider_environment(declaration)),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("unfiltered whole Source must check")
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
  reserve_request_program_plan(parent, input).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "whole-source-plan",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let provider = installed_json_source_reader_capacity(
    [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4],
    1,
    3,
  ).unwrap()
  let selected = select_installed_source_input(prepared, request, 0, 0).unwrap()
  guard selected is @sourceviews.WholeInputRoute(original) else {
    fail("unfiltered Source must select whole input before Plan construction")
  }
  assert_eq(
    @strategy.graph_captured_prefix(
      @publication_host.prepared_client_graph(prepared),
    ),
    1,
  )
  let source = prepare_installed_whole_source_capacity(
    prepared,
    original,
    declaration,
    contracts,
    {
      max_rows: 128,
      page: { max_bytes: 4096, max_nodes: 1000, max_depth: 20, max_rows: 128, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 1,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
    Some(provider),
  ).unwrap()
  let plan = prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    source,
    4096L,
    4096L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output~,
    provider_factory=_ => [],
  ).unwrap()
  assert_eq(@strategy.graph_captured_prefix(plan.graph), 0)
  assert_eq(plan.captures.length(), 0)
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  match
    prepare_request_capture_module_body(
      parent,
      input,
      plan,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      provider_factory=_ => [],
    ) {
    Ok(_) => ()
    Err(Preparation(_)) => fail("whole module: Preparation")
    Err(CapacityExceeded(_)) =>
      fail("whole module: unexpected source-free capacity refusal")
    Err(QueryTime(_)) => fail("whole module: QueryTime")
    Err(
      ModelGraph(_)
      | SerializationGraph(_)
      | ModelBinding(_)
      | ModelQuery(_)
      | ModelSource(_)
      | ContentQuery(_)
      | ContentSource(_)
    ) => fail("whole module: unexpected domain constructor")
    Err(Installed(_)) => fail("whole module: Installed")
    Err(Construction(issue)) => {
      let label = match issue {
        InvalidLimits => "InvalidLimits"
        Graph(_) => "Graph"
        TaskGraph(Fragment(Pipeline(Sequence(_)))) =>
          "TaskGraph.Fragment.Pipeline.Sequence"
        TaskGraph(Fragment(Pipeline(_))) => "TaskGraph.Fragment.Pipeline"
        TaskGraph(Fragment(_)) => "TaskGraph.Fragment"
        TaskGraph(_) => "TaskGraph"
        Material(_) => "Material"
        Facts(_) => "Facts"
        Witnesses(_) => "Witnesses"
        FactManifest(_) => "FactManifest"
        Encoding => "Encoding"
      }
      fail("whole module: Construction." + label)
    }
    Err(ValuesCompilation(_)) => fail("whole module: ValuesCompilation")
    Err(TaskCompilation(issue)) => {
      let label = match issue {
        Plan(TaskGraph(UnsupportedGraph)) => "Plan.TaskGraph.UnsupportedGraph"
        Plan(TaskGraph(Fragment(Pipeline(Sequence(_))))) =>
          "Plan.TaskGraph.Fragment.Pipeline.Sequence"
        Plan(TaskGraph(Fragment(Pipeline(_)))) =>
          "Plan.TaskGraph.Fragment.Pipeline"
        Plan(TaskGraph(Fragment(_))) => "Plan.TaskGraph.Fragment"
        Plan(TaskGraph(Root(_))) => "Plan.TaskGraph.Root"
        Plan(TaskGraph(_)) => "Plan.TaskGraph"
        Plan(Material(_)) => "Plan.Material"
        Plan(Facts(_)) => "Plan.Facts"
        Plan(Witnesses(_)) => "Plan.Witnesses"
        Plan(FactManifest(_)) => "Plan.FactManifest"
        Plan(_) => "Plan.Other"
        Material(_) => "Material"
        Graph(_) => "Graph"
        Template(_) => "Template"
        CompiledPlan(_) => "CompiledPlan"
        Encoding => "Encoding"
        ForeignInferOwner => "ForeignInferOwner"
        ForeignSerializationOwner => "ForeignSerializationOwner"
      }
      fail("whole module: TaskCompilation." + label)
    }
  }
  let owner = begin_request_capture_managed_run(parent, request).unwrap()
  if native_geometry {
    let before = @resources.ledger_usage(owner.ledger.unwrap())
    let (physical, rows, entries, evidence_entries) = installed_managed_capture_publication_geometry_original(
      owner, prepared, request,
    ).unwrap()
    assert_true(physical_equal(physical, plan.graph))
    assert_true(physical_equal(rows, plan.capacity_plan.imports.row))
    assert_eq(entries, plan.capacity_plan.execution.rows.metadata_entries)
    assert_eq(
      evidence_entries,
      plan.capacity_plan.execution.rows.retained_entries,
    )
    assert_eq(@strategy.graph_captured_prefix(physical), 0)
    assert_eq(@resources.ledger_usage(owner.ledger.unwrap()), before)
    assert_true(
      installed_managed_capture_publication_geometry_original(
        { ..owner, },
        prepared,
        request,
      )
      is None,
    )
    let foreign = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "foreign-native-geometry",
    ).unwrap()
    assert_true(
      installed_managed_capture_publication_geometry_original(
        owner, prepared, foreign,
      )
      is None,
    )
    assert_eq(
      @row_source_host.row_input_acquisition_target_resource(source.acquisition),
      "records",
    )
    let tasks = @strategy.graph_task_count(physical).to_int64()
    let ports = @strategy.graph_data_count(physical).to_int64()
    // Independent fixed task-loop vector; no new Resource or runtime grant.
    let expected = (16L + 12L * tasks + 2L * ports) * 16L +
      (32L + 16L * tasks + 4L * ports) * 8L +
      (8L + 4L * tasks + ports) * 8L
    let controller = source_input_local_tasks_control_capacity(physical).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(controller),
      expected,
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(controller),
      expected,
    )
    assert_true(retained_effect_local_tasks_control_capacity(physical) is None)
  }
  let (read, original, acquisition, _) = if native_geometry {
    assert_true(
      begin_installed_managed_whole_source_read_on_ledger(
        owner,
        prepared,
        request,
        declaration,
        source,
        owner.ledger.unwrap(),
        4095L,
        4096L,
      )
      is Err(ForeignOriginal),
    )
    assert_true(owner.reads[0] is None)
    begin_installed_managed_whole_source_read_on_ledger(
      owner,
      prepared,
      request,
      declaration,
      source,
      owner.ledger.unwrap(),
      4096L,
      4096L,
    ).unwrap()
  } else {
    begin_installed_managed_whole_source_read(
      owner, prepared, request, declaration,
    ).unwrap()
  }
  assert_true(physical_equal(original, source.original))
  assert_true(physical_equal(acquisition, source.acquisition))
  let stopped = Ref(false)
  let run = start_installed_whole_source_read_rows(
    read,
    acquisition,
    "whole-input-plan",
    _ => true,
    4096L,
    4096L,
  ).unwrap()
  @row_source_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 4096, max_nodes: 1000, max_depth: 20, max_rows: 128, },
    128,
  ).unwrap()
  let responses = @row_source_host.borrow_row_input_run_responses(
    run, acquisition,
  ).unwrap()
  @row_source_host.bind_row_run_response_borrow_cleanup(responses, () => {
    stopped.val
  }).unwrap()
  let body = @utf8.encode("[{\"id\":2},{\"id\":1}]")
  let charge = @row_source_host.charge_row_run_page(run, body).unwrap()
  @row_source_host.accept_charged_row_run_page(run, charge, body).unwrap()
  |> ignore
  @row_source_host.finish_row_run(run).unwrap()
  @row_source_host.begin_row_capture(run).unwrap()
  let mut ready = false
  for _ in 0..<10000 {
    let (done, _) = @row_source_host.advance_row_capture(run, 1).unwrap()
    if done {
      ready = true
      break
    }
  }
  assert_true(ready)
  let capture = @row_source_host.capture_row_run(run).unwrap()
  let captured = @row_source_host.row_capture_source(capture).unwrap()
  assert_eq(@query.captured_source_row_count(captured), Some(2))
  assert_eq(
    installed_managed_publication_source_kind(owner, prepared).unwrap(),
    "whole-input",
  )
  let compiled = match
    installed_managed_run_compilation_original(owner, prepared).unwrap() {
    @publication_host.Tasks(compilation) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        compilation,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    _ => fail("whole input must retain actual Tasks compilation")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "whole-source-publication", "whole-input-plan", "2026-10-30T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let limits = original_keyed_content_workspace().export_limits
  let identity = @query.identify_captured_source_relation(
    captured,
    128,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let logical = @publication_host.issue_captured_whole_source_input_logical(
    plan.graph,
    captured,
    identity,
    original,
  ).unwrap()
  let authority = "sha256:" + "2".repeat(64)
  let policy = @publication_host.prepared_client_publication_data_policy_cid(
    prepared,
  ).unwrap()
  let facts = @row_source_host.row_input_acquisition_facts(acquisition)
  let evidence = @row_source_host.issue_row_input_source_evidence(
    acquisition,
    capture,
    identity,
    logical,
    authority,
    facts.source_data_policy_cid,
    "2026-10-30T00:00:01.000Z",
  ).unwrap()
  let tight = @utf8.encode(@publication.run_evidence_value_json(evidence)).length() -
    1
  assert_true(
    @publication_host.issue_client_compiled_whole_source_invocation(
      compiled, definition, captured, identity, original, evidence, logical, authority,
      policy, "2026-10-30T00:00:00.000Z", "2026-10-30T00:00:01.000Z", tight, 8192,
      64,
    )
    is Err(_),
  )
  let (observation, invocation) = issue_program_whole_source_publication_invocation(
    owner, prepared, compiled, definition, capture, identity, evidence, logical,
    authority, policy, "2026-10-30T00:00:00.000Z", "2026-10-30T00:00:01.000Z", 65536,
    8192, 64,
  ).unwrap()
  assert_true(physical_equal(owner.publication_definition.unwrap(), definition))
  assert_true(physical_equal(owner.publication_invocation.unwrap(), invocation))
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      @publication.run_evidence_value_identity(evidence),
    ),
  )
  assert_true(
    issue_program_whole_source_publication_invocation(
      owner, prepared, compiled, definition, capture, identity, evidence, logical,
      authority, policy, "2026-10-30T00:00:00.000Z", "2026-10-30T00:00:01.000Z",
      65536, 8192, 64,
    )
    is Err(WrongPhase),
  )
  let (host, dag, _) = open_installed_managed_capture_host(
    owner,
    prepared,
    request,
    [captured],
  ).unwrap()
  let publication = reserve_program_publication(owner, prepared).unwrap()
  let execution = match
    execute_source_free_values_guarded(host, 64, 10000, () => true) {
    Ok(value) => value
    Err(original) => {
      let label = match local_values_execution_failure_issue(original) {
        InvalidLimits => "InvalidLimits"
        Fenced => "Fenced"
        UnsupportedGraph => "UnsupportedGraph"
        MissingLocalModule => "MissingLocalModule"
        Driver(Configuration(InputUnavailable)) =>
          "Driver.Configuration.InputUnavailable"
        Driver(Configuration(_)) => "Driver.Configuration"
        Driver(Execution(ActivationNotAuthorized)) =>
          "Driver.Execution.ActivationNotAuthorized"
        Driver(Execution(UnsupportedGraph)) =>
          "Driver.Execution.UnsupportedGraph"
        Driver(Execution(ForeignCapture)) => "Driver.Execution.ForeignCapture"
        Driver(Execution(ForeignCandidate)) =>
          "Driver.Execution.ForeignCandidate"
        Driver(Execution(NotReady)) => "Driver.Execution.NotReady"
        Driver(Execution(Read(_))) => "Driver.Execution.Read"
        Driver(Execution(Physical(issue))) =>
          match issue {
            AttemptLimit => "Driver.Execution.Physical.AttemptLimit"
            TransferLimit => "Driver.Execution.Physical.TransferLimit"
            RetentionLimit => "Driver.Execution.Physical.RetentionLimit"
            ExecutionLimit => "Driver.Execution.Physical.ExecutionLimit"
            InvalidLimits => "Driver.Execution.Physical.InvalidLimits"
            IdentityOverflow => "Driver.Execution.Physical.IdentityOverflow"
            PlanningLimit => "Driver.Execution.Physical.PlanningLimit"
            HoldingLimit => "Driver.Execution.Physical.HoldingLimit"
            TokenLimit => "Driver.Execution.Physical.TokenLimit"
            CostLimit => "Driver.Execution.Physical.CostLimit"
            DurationLimit => "Driver.Execution.Physical.DurationLimit"
            ForeignOwner => "Driver.Execution.Physical.ForeignOwner"
            ClosedReservation => "Driver.Execution.Physical.ClosedReservation"
            ClosedHolding => "Driver.Execution.Physical.ClosedHolding"
            InvalidCharge => "Driver.Execution.Physical.InvalidCharge"
            ResourceParked => "Driver.Execution.Physical.ResourceParked"
            ChildFundingUnavailable =>
              "Driver.Execution.Physical.ChildFundingUnavailable"
          }
        Driver(Execution(_)) => "Driver.Execution.Other"
        Driver(ManagedValues(_)) => "Driver.ManagedValues"
        Driver(ManagedCompletion(_)) => "Driver.ManagedCompletion"
        Driver(_) => "Driver.Other"
        FinalizationLimit => "FinalizationLimit"
        Estimate(_) => "Estimate"
        MissingOutput => "MissingOutput"
      }
      fail("whole result execution: " + label)
    }
  }
  assert_eq(
    execution.rows().unwrap(),
    if filtered_rows {
      ["{\"id\":2}"]
    } else {
      ["{\"id\":2}", "{\"id\":1}"]
    },
  )
  assert_true(@strategy.captured_task_completed(dag, 0))
  let export_limits = installed_managed_publication_limits(
    owner, prepared, 10000000,
  ).unwrap()
  let (bridge, output) = execution
    .prepare_publication_bridge(
      plan.capacity_plan.imports.row,
      plan.capacity_plan.metadata.bridge_entries,
      plan.capacity_plan.metadata.name_bytes,
      export_limits,
    )
    .unwrap()
  let transformation = if selected_result {
    let original_graph = @publication_host.prepared_client_graph(prepared)
    let physical_graph = @strategy.captured_dag_graph(dag)
    assert_false(physical_equal(original_graph, physical_graph))
    assert_true(
      physical_equal(
        @strategy.graph_program(original_graph),
        @strategy.graph_program(physical_graph),
      ),
    )
    assert_true(
      physical_equal(
        @strategy.graph_result_occurrence(original_graph, 0).unwrap(),
        @strategy.graph_result_occurrence(physical_graph, 0).unwrap(),
      ),
    )
    let selection = @publication_host.prepare_client_compiled_result_transformation(
      compiled, 0, 65536, 8192, 64,
    ).unwrap()
    assert_true(
      @publication_host.client_result_transformation_matches(
        selection, prepared, 0,
      ),
    )
    match
      @publication_host.start_captured_managed_result_transformation(
        selection,
        dag,
        0,
        execution.completed,
        bridge,
        output,
        export_limits,
      ) {
      Ok(value) => value
      Err(
        @publication_host.CapturedClientResultTransformationIssue::ForeignSelection
      ) =>
        fail(
          "same original Source Result selection refused as ForeignSelection",
        )
      Err(_) =>
        fail(
          "same original Source Result selection refused at another boundary",
        )
    }
  } else {
    @publication_host.start_captured_managed_result_publication_export(
      dag,
      0,
      execution.completed,
      bridge,
      output,
      export_limits,
    ).unwrap()
  }
  let mut transformed = false
  for _ in 0..<10000 {
    let (done, work) = transformation.advance(64).unwrap()
    assert_true(work <= 64)
    if done {
      transformed = true
      break
    }
  }
  assert_true(transformed)
  let stream = transformation.finish().unwrap()
  let wire = StringBuilder()
  while stream.next().unwrap() is Some(chunk) {
    wire.write_string(chunk)
  }
  wire.write_string(stream.finish().unwrap())
  // No authored/inherited order exists: the checked Result uses its
  // canonical field ordering, independently of physical input arrival.
  assert_eq(
    wire.to_string(),
    if filtered_rows {
      "[{\"id\":2}]"
    } else {
      "[{\"id\":1},{\"id\":2}]"
    },
  )
  assert_true(physical_equal(publication.run.unwrap(), dag))
  stream
  .issue_result_evidence(
    authority,
    [@publication.run_evidence_value_identity(evidence)],
    @publication.publication_contract_identity(definition),
    policy,
    "sha256:" + "5".repeat(64),
    65536,
    8192,
    64,
  )
  .unwrap()
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
    "9".repeat(64) +
    "\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
    "a".repeat(64) +
    "\"}",
    65536,
    8192,
    64,
  ).unwrap()
  stream.issue_artifact(invocation, retention, 65536, 8192, 64).unwrap()
  |> ignore
  let snapshot = begin_program_snapshot(publication, stream).unwrap()
  let mut snapshot_done = false
  for _ in 0..<10000 {
    let (done, work) = advance_program_snapshot(snapshot, 64).unwrap()
    assert_true(work <= 64)
    if done {
      snapshot_done = true
      break
    }
  }
  assert_true(snapshot_done)
  let retained_result = finish_program_snapshot(snapshot).unwrap()
  assert_true(
    physical_equal(publication.completed_snapshots[0], retained_result),
  )
  assert_true(finish_program_snapshot(snapshot) is Err(ForeignOriginal))
  stream.cancel()
  @execution.close_managed_publication_bridge(bridge)
  assert_true(execution.close())
  assert_true(
    installed_managed_publication_limits(owner, prepared, 100000) is Some(_),
  )
  assert_true(retire_installed_source_read(read) is Err(_))
  assert_true(@resources.ledger_usage(parent.ledger).live_reservations > 0)
  stopped.val = true
  let mut retired = false
  for _ in 0..<10000 {
    if retire_installed_source_read(read) is Ok(_) {
      retired = true
      break
    }
  }
  assert_true(retired)
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "whole Source executes its authored root and publishes the same original Result before release" {
  whole_source_result_publication_fixture(true)
}

///|
test "whole Source ordinary publication completes with non-retained output on the same parent" {
  whole_source_result_publication_fixture(false)
}

///|
test "whole Source compiled Result selection follows its original physical graph view" {
  whole_source_result_publication_fixture(false, selected_result=true)
}

///|
test "filtered root Source selects complete input before Plan and publishes its same original Result" {
  whole_source_result_publication_fixture(
    false,
    selected_result=true,
    filtered_root=true,
  )
}

///|
test "root Source preserves its actual filter and Result while acquiring the complete original input" {
  whole_source_result_publication_fixture(
    false,
    selected_result=true,
    filtered_rows=true,
  )
}

///|
test "Native Whole bridge borrows its SAME physical Plan geometry and task-loop inventory" {
  whole_source_result_publication_fixture(false, native_geometry=true)
}
