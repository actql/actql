///|
fn terminal_serialization_whole_capture_fixture(split : Bool) -> Unit raise {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:40c45acbf81bdf192d79b7e8f65a5731ba6065b1d4b8cc7b4cab89ab4ac85c60",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"whole-content","stages":[{"id":"main","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"remote","select":["id"],"as":"selected"},{"assert_rows":{"unique_by":["id"]}},{"serialize":{"format":"jsonl","fields":["id"],"name":"ids.jsonl","order_by":[{"id":"asc"}],"bounds":{"max_rows":10,"max_bytes":1024}},"as":"file"}],"results":{"file":{"from":"file","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let prepared = if split {
    set_output_expression_prepared(
      text="FROM records |> SELECT id |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'ids.jsonl', max_rows = 10, max_bytes = 1024) |> RESULT file",
      format=@frontend.Text,
    )
  } else {
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
  }
  guard @publication_host.prepared_client_serialization_occurrences(prepared)
    is [(task, step)] else {
    fail("one checked terminal serialization")
  }
  let component = @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
    prepared,
    task,
    step,
    10,
    1024,
    10000,
    @publication_host.client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let direct = if split {
    @publication_host.select_client_direct_acquisition_occurrences(
      prepared, 1000000,
    ).unwrap()
  } else {
    @publication_host.client_serialization_plan_direct_occurrences(
      component, prepared,
    ).unwrap()
  }
  let (stage, ordinal, _) = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 0,
  ).unwrap()
  let original = @publication_host.prepare_client_source_acquisition(
    prepared, stage, ordinal,
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let source = prepare_installed_catalog_whole_source_capacity(
    prepared,
    original,
    contracts,
    installed_row_input_policy(100, 4096, 4096, 2, 5000),
    serialization=if split { None } else { Some(component) },
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "whole-content-capture",
  ).unwrap()
  if !split {
    assert_true(
      select_installed_source_input(prepared, request, stage, ordinal).unwrap()
      is @sourceviews.WholeInputRoute(_),
    )
    let plan = prepare_installed_managed_whole_serialization_sources_plan(
      prepared,
      request,
      component,
      [source],
      [4096L],
      [4096L],
      contracts,
    ).unwrap()
    assert_true(physical_equal(plan.whole_sources[0], source))
    assert_true(physical_equal(source.original, original))
    assert_true(plan.configuration is None)
    assert_true(plan.sequences.is_empty())
    assert_eq(plan.limits.attempts, 1)
    assert_eq(plan.limits.holdings, 1)
    assert_eq(plan.limits.transfer_bytes, 4096L)
    let foreign = @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
      prepared,
      task,
      step,
      10,
      1024,
      10000,
      @publication_host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ).unwrap()
    assert_true(
      prepare_installed_managed_whole_serialization_sources_plan(
        prepared,
        request,
        foreign,
        [source],
        [4096L],
        [4096L],
        contracts,
      )
      is Err(ForeignOriginal),
    )
  }
  // Actual Row and prefix children share the same live original census.
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 4096L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 65536L, 65536L).unwrap()
  @resources.begin_original_ledger_inventory(ledger, bootstrap, 3, 1, 0).unwrap()
  |> ignore
  let run = @row_source_host.start_accounted_row_input_acquisition(
    source.acquisition,
    source.provider,
    "whole-serialize-capture",
    _ => true,
    ledger,
    4096L,
    4096L,
  ).unwrap()
  let limits = @row_source_host.row_input_acquisition_limits(source.acquisition)
  @row_source_host.begin_row_run_with_page_limits(
    run,
    limits.page,
    limits.max_rows,
  ).unwrap()
  let wire = @utf8.encode("[{\"id\":2,\"amount\":20},{\"id\":1,\"amount\":10}]")
  let charge = @row_source_host.charge_row_run_page(run, wire).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(run, charge, wire).unwrap(),
    2,
  )
  @row_source_host.finish_row_run(run).unwrap()
  @row_source_host.begin_row_capture(run).unwrap()
  let mut captured = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(run, 256).unwrap().0 {
      captured = true
      break
    }
  }
  assert_true(captured)
  let capture = @row_source_host.capture_row_run(run).unwrap()
  assert_true(
    borrow_serialization_whole_captures([capture, capture], ledger, 1000)
    is None,
  )
  let originals = borrow_serialization_whole_captures([capture], ledger, 1000).unwrap()
  let (_, execution, measurement) = client_local_execution_limits()
  let (sequence, provider, capacity) = serialization_prefix_provider(
    prepared,
    task,
    step,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
    whole=true,
  ).unwrap()
  let prefix = if split {
    let upstream = prepare_terminal_serialization_upstream(
      prepared, task, 0, contracts,
    ).unwrap()
    let inputs = prepare_whole_serialization_prefix_inputs(
      prepared,
      upstream.sequence,
      originals,
      ledger,
      occurrence=Some(0),
    ).unwrap()
    let (priced, capacity) = price_terminal_serialization_upstreams(
      [upstream],
      inputs,
      capacity,
      execution,
      measurement,
    ).unwrap()
    let bounded = priced[0].execution
    assert_eq(bounded.rows.max_rows, 2)
    assert_true(
      bounded.rows.input_values.max_nodes <
      execution.rows.input_values.max_nodes,
    )
    assert_true(
      bounded.rows.output_values.max_nodes <
      execution.rows.output_values.max_nodes,
    )
    assert_eq(
      bounded.rows.input_values.max_text_bytes,
      execution.rows.input_values.max_text_bytes,
    )
    assert_eq(
      bounded.rows.output_values.max_text_bytes,
      execution.rows.output_values.max_text_bytes,
    )
    assert_eq(bounded.max_work, execution.max_work)
    let reservation = @resources.reserve_attempt(
      ledger,
      0L,
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
      quantities=@resources.quantity_neutral_amounts(ledger),
    ).unwrap()
    let prefix = serialization_prefix_reservation(ledger, reservation)
    start_retained_serialization_upstream(
      prefix, priced, sequence, provider, inputs, execution, measurement,
    ).unwrap()
    prefix
  } else {
    let inputs = prepare_whole_serialization_prefix_inputs(
      prepared, sequence, originals, ledger,
    ).unwrap()
    start_serialization_prefix_provider(
      sequence,
      provider,
      capacity,
      inputs,
      execution,
      measurement,
      ledger,
      None,
    ).unwrap()
  }
  let mut completed = None
  for _ in 0..<10000 {
    match advance_client_serialization_prefix(prefix, 256).unwrap() {
      @local.Complete(output, ..) => {
        completed = Some(output)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("the original Whole prefix did not complete")
    }
  }
  let encoder = @publication_host.start_client_serialization_encoder(
    component.barrier,
    max_rows=10,
    max_bytes=1024,
    max_value_nodes=1000,
    max_value_depth=100,
    max_frames=100,
  ).unwrap()
  let input = @publication_host.bind_client_serialization_completed_input(
    component.barrier,
    completed.unwrap(),
    encoder,
  ).unwrap()
  assert_eq(@publication_host.client_serialization_input_rows(input), 2)
  assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_true(
    borrow_serialization_whole_captures([capture], ledger, 1000) is None,
  )
}

///|
test "terminal Content keeps the exact Whole input acquisition without opening generic Compute" {
  terminal_serialization_whole_capture_fixture(false)
}

///|
test "terminal Content uses the actual completed Whole producer across checked stages" {
  terminal_serialization_whole_capture_fixture(true)
}

///|
test "terminal Content retains the narrow original Query acquisition stage" {
  let text = "FROM records |> WHERE id > 0 |> SELECT id |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'ids.jsonl', max_rows = 10, max_bytes = 1024) |> RESULT file"
  let prepared = set_output_expression_prepared(text~, format=@frontend.Text)
  guard @publication_host.prepared_client_serialization_occurrences(prepared)
    is [(task, step)] else {
    fail("one checked terminal serialization")
  }
  let component = @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
    prepared,
    task,
    step,
    10,
    1024,
    10000,
    @publication_host.client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "query-content-capture",
  ).unwrap()
  assert_true(
    select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.QueryRoute(_),
  )
  let original = original_row_requirement(prepared)
  let acquisition = original_row_acquisition_fixture(original)
  let capacity = installed_row_capture_capacity(acquisition).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let plan = prepare_installed_managed_query_serialization_source_plan(
    prepared, request, component, capacity, 4096L, 4096L, contracts,
  ).unwrap()
  assert_true(plan.configuration is None && plan.whole_sources.is_empty())
  assert_true(physical_equal(plan.captures[0], capacity))
  assert_true(physical_equal(plan.captures[0].requirement, original))
  let foreign = set_output_expression_prepared(text~, format=@frontend.Text)
  let foreign_capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(foreign)),
  ).unwrap()
  assert_true(
    prepare_installed_managed_query_serialization_source_plan(
      prepared, request, component, foreign_capacity, 4096L, 4096L, contracts,
    )
    is Err(ForeignOriginal),
  )
}
