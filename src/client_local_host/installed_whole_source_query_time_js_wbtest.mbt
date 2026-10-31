///|
// Original Request/compiler/QueryTime and whole-Source DATA connection only.
// Initial capacity/provider frames are existing explicit component fixtures;
// this case does not prove normal constructor or physical Source funding.
test "whole Source timed Plan and module retain the first original invocation" {
  let declaration = pure_provider_declaration()
  let document =
    #|{"version":"actql/0.1","id":"whole-source-time","stages":[{"id":"read","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id"],"as":"selected"},{"derive":{"observed":"current_timestamp()"},"as":"observed"}],"results":{"out":{"from":"observed","fields":["id","observed"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(pure_provider_environment(declaration)),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("original unfiltered timed Source must check")
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
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "whole-source-time",
  ).unwrap()
  let contracts = request_program_module_contracts()
  let factory : (@execution.ExecutionCapacity) -> Array[@local.ManagedProvider] = _ => {
    []
  }
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  guard artifact is @publication_host.Tasks(compilation) else {
    fail("whole Source must retain its original Task compilation")
  }
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "whole-source-time", "original", "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let time = @publication_host.prepare_client_query_time(
    prepared, request, "2026-10-31T00:00:00.000Z",
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    time, prepared, compiled, definition, request,
  ).unwrap()
  |> ignore
  let invocation = @publication_host.client_query_time_preparation_invocation(
    time, prepared,
  )
  assert_true(invocation is Some(_))
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("unfiltered Source must retain its actual whole input route")
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
    Some(
      installed_json_source_reader_capacity(
        [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4],
        1,
        3,
      ).unwrap(),
    ),
  ).unwrap()
  assert_true(
    prepare_installed_managed_whole_source_plan_at_query_time(
      prepared,
      request,
      source,
      4096L,
      4096L,
      contracts,
      contracts.original.values_body,
      contracts.original.fragment_body,
      contracts.original.ordered_body,
      None,
      retained_output=true,
      provider_factory=factory,
    )
    is Err(ForeignOriginal),
  )
  let copied_request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "whole-source-time",
  ).unwrap()
  assert_false(physical_equal(copied_request, request))
  assert_true(
    prepare_installed_managed_whole_source_plan_at_query_time(
      prepared,
      copied_request,
      source,
      4096L,
      4096L,
      contracts,
      contracts.original.values_body,
      contracts.original.fragment_body,
      contracts.original.ordered_body,
      invocation,
      retained_output=true,
      provider_factory=factory,
    )
    is Err(ForeignOriginal),
  )
  let plan = prepare_installed_managed_whole_source_plan_at_query_time(
    prepared,
    request,
    source,
    4096L,
    4096L,
    contracts,
    contracts.original.values_body,
    contracts.original.fragment_body,
    contracts.original.ordered_body,
    invocation,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  assert_eq(@strategy.graph_captured_prefix(plan.graph), 0)
  assert_true(
    plan._observed_query_time is Some(original) &&
    physical_equal(original, time),
  )
  let expected = @publication_host.client_query_time_preparation_context(time).unwrap()
  assert_false(plan.sequences.is_empty())
  for sequence in plan.sequences {
    assert_true(
      @execution.generated_sequence_query_time(sequence) is Some(actual) &&
      physical_equal(actual, expected),
    )
  }
  prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests~,
    compilation_limits~,
    provider_factory=factory,
    invocation~,
  ).unwrap()
  assert_true(
    plan.compilation is Some(@publication_host.Tasks(actual)) &&
    physical_equal(actual, compilation),
  )
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  guard installed_managed_run_invocation_original(run, prepared)
    is Some((actual_time, actual_request, actual_compiled, actual_definition)) else {
    fail("same adopted whole Source must retain its original timed invocation")
  }
  assert_true(physical_equal(actual_time, time))
  assert_true(physical_equal(actual_request, request))
  assert_true(physical_equal(actual_compiled, compiled))
  assert_true(physical_equal(actual_definition, definition))
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
