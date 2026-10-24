///|
// Actual common capture -> acquired prefix integration. The only transport
// acknowledgement is a deterministic fixture; no installed Source, Model
// send, numeric Node profile or public admission is asserted by these tests.
priv struct OriginalCapturedPrefixFixture {
  prepared : @publication_host.PreparedClientProgram
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  plan : @publication_host.ClientInferPlanGraph
  scope : @publication_host.ClientModelReadScope
  ledger : @resources.Ledger
  bootstrap : @resources.CapacityReservation
  run : @row_source_host.RowRun
  capture : @row_source_host.RowSourceCapture
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  verify_hook : Ref[(() -> Unit)?]
}

///|
fn original_captured_prefix_fixture(
  checked? : (
    @publication_host.PreparedClientProgram,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
    @publication_host.ClientInferPlanGraph,
  )? = None,
) -> OriginalCapturedPrefixFixture raise {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  let (prepared, compiled, definition, plan) = match checked {
    Some(value) => value
    None => original_prefix_execution_fixture(source=true)
  }
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
  let capacity = client_acquired_serialization_prefix_capacity(
    prepared,
    1,
    1,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
  ).unwrap()
  let requirement = original_row_requirement(prepared)
  let acquisition = original_row_acquisition_fixture(requirement)
  let page = @utf8.encode(
    "[{\"id\":2,\"amount\":null},{\"id\":1,\"amount\":7}]",
  )
  // Existing Row/provider allowances plus independent bootstrap/read lifetime
  // fixture amounts. These are not new physical allocation coefficients.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 3,
    holdings: 1,
    transfer_bytes: page.length().to_int64(),
    retained_bytes: @row_source_host.row_acquisition_retained_capacity(
      acquisition,
    ) +
    @execution.execution_capacity_retained_bytes(capacity) +
    3L +
    7L,
    execution_bytes: @row_source_host.row_acquisition_execution_capacity(
      acquisition,
    ) +
    @execution.execution_capacity_execution_bytes(capacity) +
    128L +
    2L +
    5L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 3, 1, 0,
  ).unwrap()
  let verify_hook : Ref[(() -> Unit)?] = Ref(None)
  let run = start_client_original_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    acquisition,
    "original-captured-prefix",
    _ => {
      if verify_hook.val is Some(hook) {
        // A one-shot test hook exercises synchronous reentry in the original
        // verifier, without changing its transport acknowledgement meaning.
        verify_hook.val = None
        hook()
      }
      true
    },
    page.length().to_int64(),
    128L,
  ).unwrap()
  @row_source_host.begin_row_run(run, 128, 2, 2).unwrap()
  assert_eq(@row_source_host.accept_row_run_page(run, page).unwrap(), 2)
  @row_source_host.finish_row_run(run).unwrap()
  @row_source_host.begin_row_capture(run).unwrap()
  let mut completed = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(run, 7).unwrap().0 {
      completed = true
      break
    }
  }
  assert_true(completed)
  let capture = @row_source_host.capture_row_run(run).unwrap()
  {
    prepared,
    compiled,
    definition,
    plan,
    scope,
    ledger,
    bootstrap,
    run,
    capture,
    execution,
    measurement,
    verify_hook,
  }
}

///|
fn original_captured_prefix_start(
  value : OriginalCapturedPrefixFixture,
  task? : Int = 1,
  step? : Int = 1,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  start_client_original_captured_serialization_prefix(
    value.scope,
    value.compiled,
    value.definition,
    value.plan,
    value.prepared,
    task,
    step,
    value.capture,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    value.execution,
    value.measurement,
  )
}

///|
fn original_captured_prefix_close(
  value : OriginalCapturedPrefixFixture,
) -> Unit raise {
  @row_source_host.close_accounted_row_run(value.run).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      value.scope,
      value.compiled,
      value.definition,
      value.plan,
      true,
    ).unwrap(),
  )
  assert_false(@resources.capacity_reservation_open(value.bootstrap))
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(value.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(value.ledger).reserved_execution_bytes, 0L)
}

///|
test "original captured Source executes the checked sorted prefix without reacquisition or a replacement Ledger" {
  let value = original_captured_prefix_fixture()
  let before = @resources.ledger_usage(value.ledger)
  assert_eq(before.attempts, 1)
  assert_eq(before.holdings, 1)
  assert_true(before.held_bytes > 0L)
  assert_eq(before.reserved_retention_bytes, 3L)
  let prefix = original_captured_prefix_start(value).unwrap()
  assert_true(physical_equal(prefix.ledger, value.ledger))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 2)
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_eq(
    @resources.ledger_usage(value.ledger).transferred_bytes,
    before.transferred_bytes,
  )
  let mut output : @execution.CompletedOutput? = None
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(result, ..) => {
        output = Some(result)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original captured prefix failed before completion")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  // The Program requires ascending id for SERIALIZE. Ordinary sorted output
  // uses the canonical schema order amount,id, not provider arrival order.
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 100).unwrap(),
    "{\"amount\":7,\"id\":1}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 10000, 1000, 100).unwrap(),
    "{\"amount\":null,\"id\":2}",
  )
  assert_true(client_serialization_prefix_work(prefix).unwrap() > 0L)
  assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_eq(@resources.ledger_usage(value.ledger).reserved_retention_bytes, 3L)
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_eq(
    @query.captured_source_row_count(
      @row_source_host.row_capture_source(value.capture).unwrap(),
    ),
    Some(2),
  )
  // A spent prefix cannot be revived after cleanup, even with remaining
  // attempt/capacity room. The original source remains its own live holding.
  let after = @resources.ledger_usage(value.ledger)
  assert_true(
    original_captured_prefix_start(value)
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_eq(@resources.ledger_usage(value.ledger), after)
  let read = @publication_host.prepare_client_model_read(value.scope, 7L, 5L).unwrap()
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  @publication_host.settle_client_model_read(read, true).unwrap()
  original_captured_prefix_close(value)
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 2)
  assert_eq(
    @resources.ledger_usage(value.ledger).transferred_bytes,
    before.transferred_bytes,
  )
}

///|
test "original captured prefix rejects foreign capture wrong coordinates and descriptor issuance before a new reservation" {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  let value = original_captured_prefix_fixture()
  let foreign = original_captured_prefix_fixture()
  let other_ledger = original_captured_prefix_fixture(
    checked=Some((value.prepared, value.compiled, value.definition, value.plan)),
  )
  let before = @resources.ledger_usage(value.ledger)
  assert_true(
    original_captured_prefix_start(value, step=2)
    is Err(Original(@publication_host.ForeignRun)),
  )
  assert_true(
    original_captured_prefix_start(value, task=0)
    is Err(Original(@publication_host.ForeignRun)),
  )
  assert_true(
    start_client_original_captured_serialization_prefix(
      value.scope,
      value.compiled,
      value.definition,
      value.plan,
      value.prepared,
      1,
      1,
      foreign.capture,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      value.execution,
      value.measurement,
    )
    is Err(Original(@publication_host.ForeignRun)),
  )
  // This capture belongs to the SAME checked Program/owner, but to a different
  // actual Ledger/Scope holding. Nominal Program matching alone is insufficient.
  assert_true(
    start_client_original_captured_serialization_prefix(
      value.scope,
      value.compiled,
      value.definition,
      value.plan,
      value.prepared,
      1,
      1,
      other_ledger.capture,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      value.execution,
      value.measurement,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_eq(@resources.ledger_usage(value.ledger), before)
  let read = @publication_host.prepare_client_model_read(value.scope, 7L, 5L).unwrap()
  let issued = @resources.ledger_usage(value.ledger)
  assert_true(
    original_captured_prefix_start(value)
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_eq(@resources.ledger_usage(value.ledger), issued)
  @publication_host.settle_client_model_read(read, true).unwrap()
  original_captured_prefix_close(value)
  original_captured_prefix_close(foreign)
  original_captured_prefix_close(other_ledger)
}

///|
test "original Row prefix guard rechecks custody after the verifier synchronously starts cleanup" {
  let source_contracts = prepare_installed_sequence_contracts(source_query_original_registry, source_query_original_values, Some(source_query_original_fragment), None).unwrap()
  let value = original_captured_prefix_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let cleanup_result : Ref[Bool?] = Ref(None)
  value.verify_hook.val = Some(fn() {
    cleanup_result.val = Some(
      @publication_host.finish_client_model_read_scope(
        value.scope,
        value.compiled,
        value.definition,
        value.plan,
        false,
      ).unwrap(),
    )
  })
  // The original verifier still returns true; transport success must not
  // erase the closing phase it caused during the same liveness check.
  assert_true(
    @row_source_host.row_capture_original_prefix_requirement(
      value.capture,
      value.ledger,
    )
    is None,
  )
  assert_eq(cleanup_result.val, Some(false))
  assert_eq(@resources.ledger_usage(value.ledger), before)
  assert_true(@resources.capacity_reservation_open(value.bootstrap))
  assert_true(
    original_captured_prefix_start(value)
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_eq(@resources.ledger_usage(value.ledger), before)
  original_captured_prefix_close(value)

  let late = original_captured_prefix_fixture()
  let source = @row_source_host.row_capture_source(late.capture).unwrap()
  let read : Ref[@publication_host.ClientModelReadPreparation?] = Ref(None)
  late.verify_hook.val = Some(fn() {
    // Input binding invokes the existing liveness callback after the wrapper's
    // initial guard. The snapshot must prevent the later prefix reservation.
    read.val = Some(
      @publication_host.prepare_client_model_read(late.scope, 7L, 5L).unwrap(),
    )
  })
  assert_true(
    start_client_acquired_serialization_prefix_owned(
      late.prepared,
      1,
      1,
      source,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      late.execution,
      late.measurement,
      late.ledger,
      None,
      None,
      Some(late.capture),
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_true(read.val is Some(_))
  assert_eq(@resources.ledger_usage(late.ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(late.ledger).reserved_retention_bytes, 10L)
  assert_true(@resources.capacity_reservation_open(late.bootstrap))
  @publication_host.settle_client_model_read(read.val.unwrap(), true).unwrap()
  original_captured_prefix_close(late)
}

///|
test "original captured prefix cancellation keeps the source until both existing children clean up" {
  let value = original_captured_prefix_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let prefix = original_captured_prefix_start(value).unwrap()
  advance_client_serialization_prefix(prefix, 1).unwrap() |> ignore
  assert_true(client_serialization_prefix_work(prefix).unwrap() > 0L)
  assert_true(cancel_client_serialization_prefix(prefix))
  let mut cleaned = false
  for _ in 0..<1000 {
    if cleanup_client_serialization_prefix(prefix).unwrap() {
      cleaned = true
      break
    }
    advance_client_serialization_prefix(prefix, 1).unwrap() |> ignore
  }
  assert_true(cleaned)
  assert_false(@resources.reservation_open(prefix.reservation))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 2)
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_eq(@resources.ledger_usage(value.ledger).reserved_retention_bytes, 3L)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  original_captured_prefix_close(value)
  assert_true(@row_source_host.row_capture_source(value.capture) is Err(_))
}
