///|
test "original Source child shares a configured Model preparation without spending Model quantities" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
  )
  let requirement = original_row_requirement(prepared)
  let acquisition = original_row_acquisition_fixture(requirement)
  let retained = @row_source_host.row_acquisition_retained_capacity(acquisition)
  let execution = @row_source_host.row_acquisition_execution_capacity(
    acquisition,
  )
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 3,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: retained + 800L,
    execution_bytes: execution + 20L,
  }).unwrap()
  let input = [1]
  // Logical ownership/quantity connection only; no physical Model profile,
  // provider/Source I/O, Host/Account or public execution is claimed.
  let parent : @resources.PreparationCapacity[Array[Int], Unit] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=3,
  ).unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    parent, input,
  ).unwrap()
  let operation = @resources.begin_preparation_io(parent, input, 0L).unwrap()
  @resources.finish_preparation_io_after_cleanup(operation).unwrap()
  let amounts : @resources.QuantityAmounts = {
    tokens: 33L,
    cost_units: 7L,
    duration_ms: 19L,
  }
  @resources.configure_quantities(ledger, amounts).unwrap()
  @resources.grow_preparation_capacity_inventory(
    parent, input, 800L, 20L, 3, 1, 0,
  ).unwrap()
  let scope = @publication_host.bind_client_model_read_scope(
    compiled, definition, plan, ledger, identity,
  ).unwrap()
  let before = @resources.quantity_usage(ledger)
  let confirmations = Ref(0)
  let run = start_client_original_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    acquisition,
    "same-parent-model-source",
    _ => {
      confirmations.val += 1
      true
    },
    0L,
    0L,
  ).unwrap()
  assert_eq(confirmations.val, 0)
  assert_eq(@resources.quantity_usage(ledger), before)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    retained + 800L,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    execution + 20L,
  )
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.quantity_usage(ledger), before)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(parent, input).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
}

///|
test "original Content prefix returns exact rows while retaining Model quantities and parent input history" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture()
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 2,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: source_capture_values(),
      output_values: source_capture_values(),
    },
    max_work: 100000,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let registry = @identity.stringify_value(
    content_recovery_registered_body(),
    1000000,
    100000,
    100,
  )
  let values = @identity.stringify_value(
    content_recovery_registered_values(),
    1000000,
    100000,
    100,
  )
  let contracts = prepare_installed_sequence_contracts(
    registry,
    values,
    None,
    None,
  ).unwrap()
  let capacity = client_serialization_prefix_capacity(
    prepared,
    0,
    1,
    contracts,
    values,
    None,
    None,
    execution,
    measurement,
  ).unwrap()
  let r = @execution.execution_capacity_retained_bytes(capacity)
  let e = @execution.execution_capacity_execution_bytes(capacity)
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 3,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: r + 800L,
    execution_bytes: e + 20L,
  }).unwrap()
  let input = [1]
  let parent : @resources.PreparationCapacity[Array[Int], Unit] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=3,
  ).unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    parent, input,
  ).unwrap()
  let operation = @resources.begin_preparation_io(parent, input, 0L).unwrap()
  @resources.finish_preparation_io_after_cleanup(operation).unwrap()
  @resources.configure_quantities(ledger, {
    tokens: 33L,
    cost_units: 0L,
    duration_ms: 1000L,
  }).unwrap()
  @resources.grow_preparation_capacity_inventory(
    parent, input, 800L, 20L, 3, 1, 0,
  ).unwrap()
  let scope = @publication_host.bind_client_model_read_scope(
    compiled, definition, plan, ledger, identity,
  ).unwrap()
  let before = @resources.quantity_usage(ledger)
  let prefix = start_client_original_serialization_prefix(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    0,
    1,
    contracts,
    values,
    None,
    None,
    execution,
    measurement,
  ).unwrap()
  let mut output : @execution.CompletedOutput? = None
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => {
        output = Some(value)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("configured original Content prefix did not complete")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 100).unwrap(),
    "{\"id\":2}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 10000, 1000, 100).unwrap(),
    "{\"id\":1}",
  )
  assert_eq(@resources.quantity_usage(ledger), before)
  assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(parent, input).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.quantity_usage(ledger), before)
}

///|
test "configured Model keyed empty listing keeps original input and quantity custody through assembly cleanup" {
  let (declaration, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture(
    selector_free=true,
  )
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let view = @row_source_host.row_declaration_view(
    declaration,
    facts.source_ref,
  ).unwrap()
  let source = @row_source_host.prepare_declared_row_source(
    requirement, "content-fixture", view,
  ).unwrap()
  let acquisition = @row_source_host.prepare_declared_row_acquisition(
    source, "fixture-original-keyed-quantity-empty", original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
  // Independently calculated existing empty assembly envelope:
  // retention = 64*8 + 4096; workspace = 64*32 + 64*8 + 4096.
  // These canonical-layout budgets are not a normal Node physical profile.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 3,
    holdings: 1,
    transfer_bytes: 4096L,
    retained_bytes: @row_source_host.row_acquisition_retained_capacity(
      acquisition,
    ) +
    4608L +
    3L,
    execution_bytes: @row_source_host.row_acquisition_execution_capacity(
      acquisition,
    ) +
    4096L +
    6656L +
    2L,
  }).unwrap()
  let input = [1]
  let parent : @resources.PreparationCapacity[Array[Int], Unit] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    3L,
    2L,
    max_borrowers=4,
  ).unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    parent, input,
  ).unwrap()
  let original_input = @resources.begin_preparation_io(parent, input, 0L).unwrap()
  @resources.finish_preparation_io_after_cleanup(original_input).unwrap()
  @resources.configure_quantities(ledger, {
    tokens: 33L,
    cost_units: 7L,
    duration_ms: 19L,
  }).unwrap()
  @resources.grow_preparation_capacity_inventory(parent, input, 3L, 2L, 4, 1, 0).unwrap()
  let scope = @publication_host.bind_client_model_read_scope(
    compiled, definition, plan, ledger, identity,
  ).unwrap()
  let quantity_before = @resources.quantity_usage(ledger)
  let cleanup_requested = Ref(false)
  let run = start_client_original_keyed_direct_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    acquisition,
    "model-quantity-empty-direct",
    _ => {
      if cleanup_requested.val {
        @publication_host.finish_client_model_read_scope(
          scope, compiled, definition, plan, false,
        )
        |> ignore
      }
      true
    },
    4096L,
    4096L,
  ).unwrap()
  // The listing profile requires an installed Ref issuer even for zero rows.
  // This one refuses all issuance; an empty page must never call it.
  let reference_calls = Ref(0)
  let reference_issuer = @admitted.bind_reference_issuer(
    (_, _) => {
      reference_calls.val += 1
      false
    },
    _ => false,
  )
  @row_source_host.begin_row_run(
    run,
    4096,
    3,
    3,
    reference_issuer=Some(reference_issuer),
  ).unwrap()
  @row_source_host.begin_row_run_listing_request(run, None, 0L).unwrap()
  // Independently authored terminal protocol envelope, not an empty query
  // response inferred from absent pages or a successful selected prefix.
  let body = @utf8.encode(
    "{\"items\":[],\"request_token\":null,\"next_token\":null}",
  )
  @row_source_host.begin_row_run_listing_page(run, body, 0L).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    match @row_source_host.advance_row_run_listing_page(run, 1, 0L).unwrap() {
      @row_source_host.ListingPageContinue(_) => ()
      @row_source_host.ListingPageComplete(rows~, ..) => {
        assert_eq(rows, 0)
        complete = true
        break
      }
    }
  }
  assert_true(complete)
  @row_source_host.finish_row_run(run).unwrap()
  @row_source_host.begin_row_capture(run).unwrap()
  complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(run, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(run).unwrap()
  assert_eq(reference_calls.val, 0)
  let captured_usage = @resources.ledger_usage(ledger)
  assert_eq(captured_usage.attempts, 2)
  assert_eq(captured_usage.holdings, 1)
  let lookup = start_client_original_keyed_lookup(
    scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096, 64, 64,
  ).unwrap()
  let assembled_usage = @resources.ledger_usage(ledger)
  assert_eq(assembled_usage.attempts, captured_usage.attempts)
  assert_eq(
    assembled_usage.reserved_attempts,
    captured_usage.reserved_attempts + 1,
  )
  assert_eq(assembled_usage.reserved_retention_bytes, 4611L)
  assert_eq(assembled_usage.reserved_execution_bytes, 6658L)
  assert_eq(assembled_usage.holdings, 1)
  // Zero progress is neither cleanup acknowledgment nor permission to return
  // the buffer's reservation. It must not close the original Direct child.
  assert_false(
    @publication_host.cleanup_client_keyed_lookup_input(lookup, 0).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger), assembled_usage)
  assert_true(@row_source_host.row_capture_source(capture) is Ok(_))
  assert_true(
    @publication_host.cleanup_client_keyed_lookup_input(lookup, 8).unwrap(),
  )
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.attempts, captured_usage.attempts)
  assert_eq(retired.reserved_attempts, captured_usage.reserved_attempts)
  assert_eq(retired.holdings, 1)
  assert_eq(retired.reserved_retention_bytes, 3L)
  assert_eq(retired.reserved_execution_bytes, 2L)
  assert_true(@row_source_host.row_capture_source(capture) is Ok(_))
  assert_true(
    start_client_original_keyed_lookup(
      scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096, 64,
      64,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), retired)
  // A liveness callback can begin original cleanup synchronously and still
  // return true. The AFTER-callback fence must revoke use without certifying
  // physical close or returning the Direct holding. Cleanup remains callable.
  cleanup_requested.val = true
  assert_true(@row_source_host.row_capture_source(capture) is Err(_))
  assert_false(
    @publication_host.client_original_keyed_capture_available(
      scope, compiled, definition, plan, prepared, keyed,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger).holdings, 1)
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_true(@row_source_host.row_capture_source(capture) is Err(_))
  // The original physical child's ACK returns its live holding slot. Issued
  // token identity and consumed work/transfer are independent of that slot.
  assert_eq(@resources.ledger_usage(ledger).holdings, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(parent, input).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.quantity_usage(ledger), quantity_before)
  assert_eq(@resources.ledger_usage(ledger).attempts, 2)
}
