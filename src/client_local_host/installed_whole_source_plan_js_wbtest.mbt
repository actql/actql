///|
// Actual existing Request check/compiler/adoption, declared Source and RowRun.
// Physical Account/transport/stop are explicit ports, not normal acceptance.
test "one original Request Plan captures whole unfiltered Source and leaves authored Compute pending" {
  let declaration = pure_provider_declaration()
  let document =
    #|{"version":"actql/0.1","id":"whole-source-plan","stages":[{"id":"read","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
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
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  assert_eq(@strategy.graph_captured_prefix(plan.graph), 0)
  assert_eq(plan.captures.length(), 0)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let owner = begin_request_capture_managed_run(parent, request).unwrap()
  assert_eq(
    installed_managed_source_input_kind(owner, prepared, request).unwrap(),
    "whole-input",
  )
  let (read, original, acquisition, _) = begin_installed_managed_whole_source_read(
    owner, prepared, request, declaration,
  ).unwrap()
  assert_true(physical_equal(original, source.original))
  assert_true(physical_equal(acquisition, source.acquisition))
  let stopped = Ref(false)
  // A foreign physical caller cannot consume this original read's start slot.
  // This unaccounted Ledger is negative DATA, never an installed supplier.
  let foreign = @resources.create_ledger(
    @resources.ledger_limits(parent.ledger),
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    start_installed_whole_source_read_rows(
      read,
      acquisition,
      "wrong-physical-original",
      _ => true,
      4096L,
      4096L,
      expected_ledger=Some(foreign),
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  // The existing caller still uses its unchanged default signature.
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
  let (_, dag, _) = open_installed_managed_capture_host(
    owner,
    prepared,
    request,
    [captured],
  ).unwrap()
  assert_false(@strategy.captured_task_completed(dag, 0))
  assert_eq(@strategy.next_captured_task(dag), Some(0))
  @row_source_host.check_row_input_compute_binding(capture, dag, 0).unwrap()
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
  assert_true(check_installed_source_read_current(read) is Err(Retired))
  let after = @resources.ledger_usage(parent.ledger)
  retire_installed_source_read(read).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger), after)
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
