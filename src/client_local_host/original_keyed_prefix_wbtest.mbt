///|
priv struct OriginalKeyedPrefixFixture {
  prepared : @publication_host.PreparedClientProgram
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  plan : @publication_host.ClientInferPlanGraph
  keyed : @publication_host.ClientKeyedAcquisition
  scope : @publication_host.ClientModelReadScope
  ledger : @resources.Ledger
  direct : @row_source_host.RowRun
  capture : @row_source_host.RowSourceCapture
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
}

///|
fn original_keyed_prefix_fixture(
  borrowed_inputs? : Bool = false,
) -> OriginalKeyedPrefixFixture raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let (declaration, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture(
    relation_versions=true,
  )
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
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
  let capacity = client_original_keyed_left_prefix_capacity(
    prepared,
    keyed,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
  ).unwrap()
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let view = @row_source_host.row_declaration_view(
    declaration,
    facts.source_ref,
  ).unwrap()
  let source = @row_source_host.prepare_declared_row_source(
    requirement, "content-fixture", view,
  ).unwrap()
  let acquisition = @row_source_host.prepare_declared_row_acquisition(
    source, "fixture-original-version-prefix", original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
  let columns = @row_source_host.row_acquisition_columns(acquisition)
  // Arrival is deliberately c,a,b. The checked sort, not capture relabeling,
  // must produce the authored a,b,c sequence with versions v1,v2,v1.
  let page = @utf8.encode(
    "[" +
    [2, 0, 1].map(index => original_keyed_version_row(index, columns)).join(",") +
    "]",
  )
  // Existing selected provider allowances and bootstrap lifetime fixture only;
  // these are not normal-profile physical coefficients or a public grant.
  let extra = if borrowed_inputs {
    let units = @row_source_host.row_captured_inputs_construction_inventory(1).unwrap()
    let capacity = @execution.preparation_execution_capacity({
      retained: units,
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    }).unwrap()
    (
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    )
  } else {
    (0L, 0L)
  }
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 1,
    transfer_bytes: page.length().to_int64(),
    retained_bytes: @row_source_host.row_acquisition_retained_capacity(
      acquisition,
    ) +
    @execution.execution_capacity_retained_bytes(capacity) +
    3L +
    extra.0,
    execution_bytes: @row_source_host.row_acquisition_execution_capacity(
      acquisition,
    ) +
    4096L +
    @execution.execution_capacity_execution_bytes(capacity) +
    2L +
    extra.1,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(
    ledger,
    3L + extra.0,
    2L + extra.1,
  ).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 1, 0,
  ).unwrap()
  let direct = start_client_original_keyed_direct_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    acquisition,
    "original-version-prefix",
    _ => true,
    page.length().to_int64(),
    4096L,
  ).unwrap()
  let permits = wire => wire == original_keyed_child_resource(0)
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => permits(wire),
    permits,
  )
  @row_source_host.begin_row_run(
    direct,
    4096,
    3,
    3,
    reference_issuer=Some(issuer),
  ).unwrap()
  assert_eq(@row_source_host.accept_row_run_page(direct, page).unwrap(), 3)
  @row_source_host.finish_row_run(direct).unwrap()
  @row_source_host.begin_row_capture(direct).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(direct, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(direct).unwrap()
  {
    prepared,
    compiled,
    definition,
    plan,
    keyed,
    scope,
    ledger,
    direct,
    capture,
    execution,
    measurement,
  }
}

///|
fn original_keyed_prefix_start(
  value : OriginalKeyedPrefixFixture,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  start_client_original_keyed_left_prefix(
    value.scope,
    value.compiled,
    value.definition,
    value.plan,
    value.prepared,
    value.keyed,
    value.capture,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    value.execution,
    value.measurement,
    100,
    4096,
  )
}

///|
fn original_keyed_prefix_close(
  value : OriginalKeyedPrefixFixture,
) -> Unit raise {
  @row_source_host.close_accounted_row_run(value.direct).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      value.scope,
      value.compiled,
      value.definition,
      value.plan,
      true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(value.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(value.ledger).reserved_execution_bytes, 0L)
}

///|
test "original keyed left prefix executes unique sort take and binds the actual join port without reacquisition" {
  let value = original_keyed_prefix_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let prefix = original_keyed_prefix_start(value).unwrap()
  assert_true(physical_equal(prefix.ledger, value.ledger))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts)
  assert_eq(
    @resources.ledger_usage(value.ledger).reserved_attempts,
    before.reserved_attempts + 1,
  )
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_eq(
    @resources.ledger_usage(value.ledger).transferred_bytes,
    before.transferred_bytes,
  )
  let admitted = @resources.ledger_usage(value.ledger)
  assert_true(
    original_keyed_prefix_start(value)
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_eq(@resources.ledger_usage(value.ledger), admitted)
  let mut output : @execution.CompletedOutput? = None
  for _ in 0..<10000 {
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(result, ..) => {
        output = Some(result)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original keyed left prefix failed before completion")
    }
  }
  let output = output.unwrap()
  let owner = @publication_host.client_keyed_acquisition_owner(value.keyed)
  assert_true(
    @execution.completed_output_matches_port(output, owner, @pipeline.Step(4)),
  )
  assert_false(
    @execution.completed_output_matches_port(output, owner, @pipeline.Step(1)),
  )
  assert_eq(@execution.completed_row_count(output), 3)
  let (_, _, join) = @publication_host.client_keyed_acquisition_coordinates(
    value.keyed,
  ).unwrap()
  let bound = @execution.bind_completed_operation_input(
    owner, join, 0, owner, output,
  ).unwrap()
  let read = @execution.prepare_producer_read(owner, bound, 100, 4096).unwrap()
  for row in 0..<3 {
    let wire = @execution.completed_output_row_wire(
      output, row, 10000, 1000, 100,
    ).unwrap()
    // Canonical schema order is authored independently of the output/provider.
    // The authored Source SELECT exports precisely these three columns.
    let expected = original_keyed_version_row(row, [
      "name", "resource", "version",
    ])
    assert_eq(wire, expected)
  }
  assert_true(@execution.producer_read_available(read))
  assert_true(client_serialization_prefix_work(prefix).unwrap() > 0L)
  assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_false(@resources.reservation_open(prefix.reservation))
  assert_eq(@resources.ledger_usage(value.ledger).reserved_retention_bytes, 3L)
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  original_keyed_prefix_close(value)
}

///|
test "original keyed left prefix cancellation retires only its provider reservation after positive work" {
  let value = original_keyed_prefix_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let prefix = original_keyed_prefix_start(value).unwrap()
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
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_eq(@resources.ledger_usage(value.ledger).reserved_retention_bytes, 3L)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  original_keyed_prefix_close(value)
}

///|
test "original keyed left prefix refuses a foreign Scope and a closing original before provider reservation" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let value = original_keyed_prefix_fixture()
  let foreign = original_keyed_prefix_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let other = @resources.ledger_usage(foreign.ledger)
  assert_true(
    start_client_original_keyed_left_prefix(
      foreign.scope,
      value.compiled,
      value.definition,
      value.plan,
      value.prepared,
      value.keyed,
      value.capture,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      value.execution,
      value.measurement,
      100,
      4096,
    )
    is Err(Original(@publication_host.ForeignRun)),
  )
  assert_eq(@resources.ledger_usage(value.ledger), before)
  assert_eq(@resources.ledger_usage(foreign.ledger), other)
  assert_false(
    @publication_host.finish_client_model_read_scope(
      value.scope,
      value.compiled,
      value.definition,
      value.plan,
      false,
    ).unwrap(),
  )
  // Closing revokes the actual Row capture before the later Scope loan.
  assert_true(
    original_keyed_prefix_start(value) is Err(Capture(@query.Unavailable)),
  )
  assert_eq(@resources.ledger_usage(value.ledger), before)
  original_keyed_prefix_close(value)
  original_keyed_prefix_close(foreign)
}

///|
test "original keyed left prefix refuses workspace one above remaining retention before provider allocation" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let value = original_keyed_prefix_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let selected = client_original_keyed_left_prefix_capacity(
    value.prepared,
    value.keyed,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    value.execution,
    value.measurement,
  ).unwrap()
  // The original Row allowance exceeds its actual capture holding. Use the
  // actual remaining capacity for this reservation-boundary test, not that
  // allowance as though all its bytes were held. This does not independently
  // establish a physical normal-profile bound or its component coefficients.
  let available = @resources.ledger_limits(value.ledger).retained_bytes -
    before.held_bytes -
    before.reserved_retention_bytes
  let extra = available -
    @execution.execution_capacity_retained_bytes(selected) +
    1L
  let workspace = @execution.execution_capacity(extra, extra).unwrap()
  assert_true(
    start_client_original_keyed_left_prefix(
      value.scope,
      value.compiled,
      value.definition,
      value.plan,
      value.prepared,
      value.keyed,
      value.capture,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      value.execution,
      value.measurement,
      100,
      4096,
      workspace=Some(workspace),
    )
    is Err(Physical(@resources.RetentionLimit)),
  )
  assert_eq(@resources.ledger_usage(value.ledger), before)
  assert_eq(before.attempts, 1)
  assert_eq(before.holdings, 1)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  original_keyed_prefix_close(value)
}

///|
test "borrowed original capture inventory keeps failed prefix cleanup identities" {
  let value = original_keyed_prefix_fixture(borrowed_inputs=true)
  let supplied = [value.capture]
  let inventory = @row_source_host.retain_row_captured_inputs(
    supplied,
    value.ledger,
    2,
  ).unwrap()
  assert_eq(@row_source_host.row_captured_inputs_count(inventory), 1)
  assert_true(
    physical_equal(
      @row_source_host.row_captured_input_at(inventory, 0).unwrap(),
      value.capture,
    ),
  )
  assert_true(@row_source_host.row_captured_input_at(inventory, 1) is None)
  supplied.clear()
  assert_true(
    @row_source_host.row_captures_original_prefix_available(
      inventory,
      value.ledger,
    ),
  )
  assert_true(
    @row_source_host.retain_row_captured_inputs(
      [value.capture, value.capture],
      value.ledger,
      4,
    )
    is None,
  )
  assert_true(
    @row_source_host.retain_row_captured_inputs(
      [value.capture],
      value.ledger,
      1,
    )
    is None,
  )
  let prefix = original_keyed_prefix_start(value).unwrap()
  assert_true(
    @row_source_host.row_captures_original_prefix_available(
      inventory,
      value.ledger,
      prefix=Some(prefix.reservation),
    ),
  )
  @row_source_host.close_accounted_row_run(value.direct).unwrap()
  assert_false(
    @row_source_host.row_captures_original_prefix_available(
      inventory,
      value.ledger,
      prefix=Some(prefix.reservation),
    ),
  )
  // Row has retired its holding. The borrowed tuple still checks the SAME
  // recorded originals; cancellation must not strand prefix cleanup.
  assert_true(
    @row_source_host.row_captures_original_keyed_prefix_dependents_retired(
      inventory,
      value.ledger,
      prefix.reservation,
    ),
  )
  assert_true(cancel_client_serialization_prefix(prefix))
  let mut retired = false
  for _ in 0..<10000 {
    if cleanup_client_serialization_prefix(prefix).unwrap() {
      retired = true
      break
    }
    advance_client_serialization_prefix(prefix, 1).unwrap() |> ignore
  }
  assert_true(retired)
  original_keyed_prefix_close(value)
}
