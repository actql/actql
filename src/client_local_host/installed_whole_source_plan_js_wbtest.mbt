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
  let catalog_source = prepare_installed_catalog_whole_source_capacity(
    prepared,
    original,
    contracts,
    @row_source_host.row_input_acquisition_limits(source.acquisition),
  ).unwrap()
  assert_true(physical_equal(catalog_source.original, source.original))
  let expected_sql = "SELECT \"id\" FROM \"ma\"\"in\".\"récords\""
  let sql_bytes = @utf8.encode(expected_sql).length()
  assert_eq(
    render_installed_catalog_source_sql(
      catalog_source, "ma\"in", "récords", sql_bytes,
    ).unwrap(),
    expected_sql,
  )
  assert_true(
    render_installed_catalog_source_sql(
      catalog_source,
      "ma\"in",
      "récords",
      sql_bytes - 1,
    )
    is Err(_),
  )
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
  @row_source_host.check_native_row_input_original(run, acquisition).unwrap()
  assert_true(
    @row_source_host.check_native_row_input_original(
      run,
      catalog_source.acquisition,
    )
    is Err(_),
  )
  assert_true(
    begin_installed_managed_catalog_whole_source_read(
      owner, prepared, request, catalog_source,
    )
    is Err(ForeignOriginal),
  )
  let responses = @row_source_host.borrow_row_input_run_responses(
    run, acquisition,
  ).unwrap()
  @row_source_host.bind_row_run_response_borrow_cleanup(responses, () => {
    stopped.val
  }).unwrap()
  // Real SAME Read/RowRun reservation: completed physical constructor
  // workspace returns without discarding receiver/Plan remainder or stop duty.
  let before_reply = @resources.ledger_usage(parent.ledger)
  let expanded = @execution.add_execution_capacity(
    provider,
    @execution.execution_capacity(101L, 203L).unwrap(),
  ).unwrap()
  @row_source_host.grow_row_run_response_construction_capacity(
    responses, expanded,
  ).unwrap()
  let during_reply = @resources.ledger_usage(parent.ledger)
  assert_eq(
    during_reply.reserved_retention_bytes,
    before_reply.reserved_retention_bytes + 101L,
  )
  assert_eq(
    during_reply.reserved_execution_bytes,
    before_reply.reserved_execution_bytes + 203L,
  )
  @row_source_host.complete_row_run_response_construction_capacity(
    responses, provider,
  ).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger), {
    ..before_reply,
    peak_retention_bytes: during_reply.peak_retention_bytes,
  })
  assert_false(stopped.val)
  assert_true(
    @row_source_host.complete_row_run_response_construction_capacity(
      responses, expanded,
    )
    is Err(@row_source_host.Physical(@resources.InvalidCharge)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), {
    ..before_reply,
    peak_retention_bytes: during_reply.peak_retention_bytes,
  })
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
  let held = @resources.ledger_usage(parent.ledger)
  assert_true(held.held_bytes > before.held_bytes)
  assert_false(stopped.val)
  assert_eq(
    held.reserved_retention_bytes - before.reserved_retention_bytes,
    @execution.execution_capacity_retained_bytes(provider),
  )
  // Provider and the physical page still coexist before their ORIGINAL ACK;
  // returned receiver arrays stay funded independently in BOTH dimensions.
  assert_eq(
    held.reserved_execution_bytes -
    before.reserved_execution_bytes -
    @execution.execution_capacity_execution_bytes(provider) -
    4096L,
    held.held_bytes - before.held_bytes,
  )
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

///|
// Actual checked Source/Request and RowRun with explicit physical reader ports.
// This isolates cumulative capture policy; it is not ordinary Table acceptance.
fn whole_source_selected_capture_bytes_fixture(
  selected_bytes : Int,
  max_pages? : Int = 3,
  explicit_small? : Bool = false,
) -> Unit raise {
  let declaration = @row_source_host.generate_row_declaration(
    "pure-provider",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "number", nullable: false, },
          { name: "document", value_type: "string", nullable: false, },
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
  let document =
    #|{"version":"actql/0.1","id":"whole-source-bytes","stages":[{"id":"read","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id","document"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","document"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(
      pure_provider_environment(declaration, artifact_bytes=Some(1000)),
    ),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("whole Source must check under its selected original Host policy")
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
    "same-whole-source-bytes",
  ).unwrap()
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("unfiltered Source must retain whole input")
  }
  let physical_bytes = selected_bytes
  assert_true(
    @resources.ledger_limits(parent.ledger).retained_bytes <= 536870912L,
  )
  assert_true(
    @resources.ledger_limits(parent.ledger).execution_bytes <= 536870912L,
  )
  let output_policy = installed_source_listing_policy(
    @publication_host.prepared_client_graph(prepared),
  )
  assert_eq(
    @capacity.ceiling_value(
      @capacity.ceiling(output_policy, "max_artifact_bytes").unwrap(),
    ),
    1000L,
  )
  let limits = if explicit_small {
    installed_row_input_policy(16, physical_bytes, 400000, 32, 16)
  } else {
    installed_source_row_input_policy(
      max_pages, 16, physical_bytes, 400000, 32, 16,
    ).unwrap()
  }
  assert_eq(limits.page.max_bytes, physical_bytes)
  assert_eq(limits.max_rows, 16)
  assert_eq(
    limits.retention.max_text_bytes,
    if explicit_small {
      500000
    } else {
      max_pages * selected_bytes
    },
  )
  if !explicit_small {
    assert_eq(limits.wire.max_bytes, max_pages * selected_bytes)
  }
  let contracts = request_program_module_contracts()
  let source = prepare_installed_whole_source_capacity(
    prepared,
    original,
    declaration,
    contracts,
    limits,
    None,
  ).unwrap()
  let initial = @row_source_host.row_input_acquisition_capacity(
    source.acquisition,
    None,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(initial) <
    limits.retention.max_text_bytes.to_int64(),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(initial) <
    limits.retention.max_text_bytes.to_int64(),
  )
  let plan = match
    prepare_installed_managed_whole_source_plan(
      prepared,
      request,
      source,
      physical_bytes.to_int64(),
      physical_bytes.to_int64(),
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      retained_output=true,
      provider_factory=_ => [],
      runtime_admission=true,
    ) {
    Ok(value) => value
    Err(Unsupported) => fail("whole Plan unsupported")
    Err(ForeignOriginal) => fail("whole Plan foreign original")
    Err(MetadataCapacityUnavailable) => fail("whole Plan metadata unavailable")
    Err(InsufficientCapacity) => fail("whole Plan capacity unavailable")
    Err(_) => fail("whole Plan other refusal")
  }
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let owner = begin_request_capture_managed_run(parent, request).unwrap()
  let (read, _, acquisition, _) = begin_installed_managed_whole_source_read(
    owner, prepared, request, declaration,
  ).unwrap()
  let run = start_installed_whole_source_read_rows(
    read,
    acquisition,
    "same-whole-source-bytes",
    _ => true,
    physical_bytes.to_int64(),
    physical_bytes.to_int64(),
  ).unwrap()
  @row_source_host.begin_row_run_with_page_limits(run, limits.page, 16).unwrap()
  let rows = Array::makei(16, index => {
    "{\"id\":" +
    index.to_string() +
    ",\"document\":\"" +
    "x".repeat(49152 + index) +
    "\"}"
  })
  let body = @utf8.encode("[" + rows.join(",") + "]")
  let total_text = 16 * 49152 + 16 * 15 / 2
  assert_eq(total_text, 786552)
  assert_eq(body.length() < limits.page.max_bytes, selected_bytes > 786552)
  let before = @resources.ledger_usage(parent.ledger)
  let mut refused = false
  match @row_source_host.charge_row_run_page(run, body) {
    Err(Physical(TransferLimit)) if selected_bytes < body.length() =>
      refused = true
    Err(_) => fail("unexpected Source charge refusal")
    Ok(charge) =>
      match @row_source_host.accept_charged_row_run_page(run, charge, body) {
        Ok(count) => assert_eq(count, 16)
        Err(Source(Capture(CaptureLimit))) if explicit_small => refused = true
        Err(_) => fail("unexpected page admission refusal")
      }
  }
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes >
    before.reserved_retention_bytes ||
    refused,
  )
  let mut ready = false
  if !refused {
    @row_source_host.finish_row_run(run).unwrap()
    @row_source_host.begin_row_capture(run).unwrap()
    for _ in 0..<10000 {
      match @row_source_host.advance_row_capture(run, 256) {
        Ok((done, _)) =>
          if done {
            ready = true
            break
          }
        Err(Source(Capture(CaptureLimit))) => {
          refused = true
          break
        }
        Err(_) => fail("unexpected capture refusal")
      }
    }
  }
  if explicit_small || selected_bytes < total_text {
    assert_true(refused)
    assert_false(ready)
    assert_true(@row_source_host.capture_row_run(run) is Err(_))
  } else {
    assert_true(ready)
    assert_false(refused)
    let capture = match @row_source_host.capture_row_run(run) {
      Ok(value) => value
      Err(Physical(issue)) =>
        fail(
          "original capture physical refusal: " +
          @debug.to_string(issue) +
          " usage " +
          @debug.to_string(@resources.ledger_usage(parent.ledger)),
        )
      Err(Source(_)) => fail("original capture Source refusal")
      Err(Consumer(_)) => fail("original capture consumer refusal")
      Err(_) => fail("original capture state refusal")
    }
    let captured = @row_source_host.row_capture_source(capture).unwrap()
    assert_eq(@query.captured_source_row_count(captured), Some(16))
    let original_read = @query.captured_source_original_input_read(captured).unwrap()
    for index in 0..<16 {
      let wire = @execution.supplied_relation_read_row_wire(
        original_read,
        index,
        limits.wire,
      ).unwrap()
      let decoded = @json.parse(wire)
      // Verify every complete document, including the original ordinal suffix.
      guard decoded is Object(row) else { fail("original row wire") }
      assert_eq(row["document"], Json::string("x".repeat(49152 + index)))
      assert_eq(row["id"], Json::number(index.to_double()))
    }
  }
  let mut retired = false
  for _ in 0..<10000 {
    match retire_installed_source_read(read) {
      Ok(_) => {
        retired = true
        break
      }
      Err(CleanupPending) => ()
      Err(_) => fail("original whole Source cleanup")
    }
  }
  assert_true(retired)
  retire_installed_managed_run(owner).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "Whole Source captures 786552 text bytes under the same selected Host policy" {
  whole_source_selected_capture_bytes_fixture(4194304)
}

///|
test "Whole Source keeps selected Host and explicit small capture refusal with cleanup" {
  whole_source_selected_capture_bytes_fixture(500000, max_pages=1)
  whole_source_selected_capture_bytes_fixture(4194304, explicit_small=true)
}
