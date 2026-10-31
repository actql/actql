///|
// Existing bound QueryTime, Request/compiler and fixed Model profile only.
// The initial/factory ports do not prove normal physical backing or Model IO.
test "same Request source-free Model module needs its original bound QueryTime" {
  let (parent, input, prepared) = request_model_input_fixture(
    with_query_time=true,
  )
  assert_true(
    @publication_host.prepared_client_requires_query_time(
      prepared, 100000, 10000,
    ).unwrap(),
  )
  let held = borrow_request_model_plan_input(parent, input).unwrap()
  let (occurrence, graph) = request_model_graph_fixture(prepared)
  let compilation = prepare_request_model_compilation(
    parent,
    input,
    graph,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-model-time", "original", "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "request-model-time",
  ).unwrap()
  let original = @publication_host.prepare_client_query_time(
    prepared, request, "2026-10-31T00:00:00.000Z",
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    original, prepared, compiled, definition, request,
  ).unwrap()
  |> ignore
  let contracts = request_program_module_contracts()
  let assets = @publication_host.client_local_product_assets()
  // This existing typed constructor already accepts the original bound pair.
  assert_true(
    source_free_installed_managed_preparation_owned(
      Pure(prepared),
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      true,
      query_time=Some((original, request)),
    )
    is Ok(_),
  )
  // Compare the actual selected wrapper with the original bound context.
  let calls = Ref(0)
  let selected = prepare_installed_mock_model_source_free_with_contracts(
    prepared,
    compilation,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      []
    },
    query_time=Some((original, request)),
  ).unwrap()
  assert_eq(calls.val, 1)
  let expected = @publication_host.client_query_time_preparation_context(
    original,
  ).unwrap()
  assert_false(selected.sequences.is_empty())
  for sequence in selected.sequences {
    assert_true(
      @execution.generated_sequence_query_time(sequence) is Some(actual) &&
      physical_equal(actual, expected),
    )
  }
  assert_true(selected._observed_query_time is Some((time, bound)) &&
    physical_equal(time, original) && physical_equal(bound, request))
  let copied_request = @publication_host.prepare_source_free_client_request_identity(
    prepared, "sha256:" + "a".repeat(64), "request-model-time",
  ).unwrap()
  assert_true(
    prepare_installed_mock_model_source_free_plan(
      selected, copied_request, compiled, definition, occurrence, graph,
      effect_model_plan_limits, 500L, 700L, 20, 20, 20,
    ) is Err(ForeignOriginal),
  )
  let other_definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-model-time", "other", "2026-10-31T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    prepare_installed_mock_model_source_free_plan(
      selected, request, compiled, other_definition, occurrence, graph,
      effect_model_plan_limits, 500L, 700L, 20, 20, 20,
    ) is Err(ForeignOriginal),
  )
  let plan = prepare_installed_mock_model_source_free_plan(
    selected, request, compiled, definition, occurrence, graph,
    effect_model_plan_limits, 500L, 700L, 20, 20, 20,
  ).unwrap()
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  complete_request_model_preparation(parent, input, plan).unwrap()
  let run = begin_request_model_managed_run(parent, request, scope).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@publication_host.finish_client_model_read_scope(
    scope, plan.compiled, plan.definition, plan.graph, true,
  ).unwrap())
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  @resources.return_preparation_body_borrow(held).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
