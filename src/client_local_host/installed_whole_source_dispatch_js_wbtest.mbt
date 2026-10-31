///|
// Actual existing Request check/compiler/adoption, declared Source and RowRun.
// Physical Account/transport/stop are explicit ports, not normal acceptance.
test "whole Source dispatch uses its exact Plan graph and existing Run Ledger" {
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
  let (read, original, acquisition, _) = begin_installed_managed_whole_source_read(
    owner, prepared, request, declaration,
  ).unwrap()
  assert_true(physical_equal(original, source.original))
  assert_true(physical_equal(acquisition, source.acquisition))
  assert_true(
    @strategy.graph_requires_acquisition_result_publication(
      @publication_host.prepared_client_graph(prepared),
    ),
  )
  assert_false(
    installed_managed_acquisition_result_publication(owner, prepared, request).unwrap(),
  )
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    physical_equal(
      installed_managed_whole_source_ledger(
        owner, prepared, request, source, 4096L, 4096L,
      ).unwrap(),
      parent.ledger,
    ),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(
    installed_managed_whole_source_ledger(
      owner, prepared, request, source, 4095L, 4096L,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_managed_whole_source_ledger(
      owner, prepared, request, source, 4096L, 4095L,
    )
    is Err(ForeignOriginal),
  )
  let foreign = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "b".repeat(64),
    "foreign-dispatch",
  ).unwrap()
  assert_true(
    installed_managed_acquisition_result_publication(owner, prepared, foreign)
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_managed_whole_source_ledger(
      owner, prepared, foreign, source, 4096L, 4096L,
    )
    is Err(ForeignOriginal),
  )
  retire_installed_source_read(read).unwrap()
  assert_true(
    installed_managed_whole_source_ledger(
      owner, prepared, request, source, 4096L, 4096L,
    )
    is Err(ForeignOriginal),
  )
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_true(
    installed_managed_acquisition_result_publication(owner, prepared, request)
    is Err(_),
  )
}
