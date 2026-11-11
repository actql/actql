///|
fn collection_capture_execution_case(refuse : Bool) -> Unit raise {
  let digits : Array[String] = []
  for n in 0..<10 {
    digits.push("SELECT " + n.to_string() + " AS n")
  }
  let sql = "WITH d AS (" +
    digits.join(" UNION ALL ") +
    ") SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < 9999"
  let prepared = collection_capacity_selected_prepared(
    sql,
    client_local_materialized_row_ceiling(client_local_resource_policy()).unwrap(),
  )
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  let plan = original.capacity_plan
  println(
    "collection-original-demand " +
    @debug.to_string(
      (
        plan.scalar_demand.map(value => value.name_bytes),
        plan.execution.rows.output_values.max_text_bytes,
      ),
    ),
  )
  assert_true(client_local_text_free_scalar_sequences(original.sequences))
  let demand = plan.scalar_demand.unwrap()
  assert_true(demand.name_bytes > 500000)
  assert_eq(plan.execution.rows.output_values.max_text_bytes, demand.name_bytes)
  assert_eq(plan.execution.rows.input_values.max_text_bytes, demand.name_bytes)
  let requirements = @execution.generated_sequence_requirements(
    original.sequences[43],
    10000,
  ).unwrap()
  let fragment = @lower.sequence_requirements_fragment_for_step(
    requirements, 43,
  ).unwrap()
  assert_eq(
    fragment.logical.max_work,
    plan.execution.rows.input_values.max_work.to_int64(),
  )
  let reported = Ref(false)
  for slot, sequence in original.sequences {
    for index in 0..<@execution.generated_sequence_step_count(sequence) {
      if @execution.generated_sequence_step_index_at(sequence, index) ==
        Some(41) &&
        !reported.val {
        reported.val = true
        let kind = match
          @execution.generated_sequence_step_at(sequence, index) {
          Some(@lower.CrossJoinStep(_)) => "cross_join"
          Some(@lower.AppendStep(_)) => "append"
          Some(@lower.RowStep(_)) => "row"
          _ => "other"
        }
        assert_eq((slot, kind), (41, "cross_join"))
      }
    }
  }
  // A quote is not the ordinary admission. Supply the original finite Run
  // authority explicitly, as the existing whole-Source chain fixtures do.
  let limits = {
    ..original.limits,
    retained_bytes: client_local_retained_byte_ceiling(),
    execution_bytes: client_local_execution_byte_ceiling(),
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  let setup = open_checked_local_host(
    prepared,
    None,
    contracts,
    assets.values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
    retained_output=false,
    acquisition_ledger=Some(ledger),
    source_free_preparation=Some(original),
  ).unwrap()
  let captured = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let blocker : Ref[@resources.CapacityReservation?] = Ref(None)
  let current = if refuse {
    fn() {
      if blocker.val is None &&
        @strategy.next_captured_task(captured) == Some(43) {
        let usage = @resources.ledger_usage(ledger)
        blocker.val = Some(
          @resources.reserve_capacity(
            ledger,
            0L,
            limits.execution_bytes - usage.reserved_execution_bytes,
          ).unwrap(),
        )
      }
      true
    }
  } else {
    () => true
  }
  let result = execute_source_free_local_tasks_guarded(
    setup, 64, 100000, current,
  )
  if refuse {
    guard result is Err(failure) else {
      fail("occupied original execution allowance completed")
    }
    assert_true(blocker.val is Some(_))
    assert_true(failure.issue is Driver(Execution(Physical(ExecutionLimit))))
    assert_true(retry_local_values_execution_failure_cleanup(failure))
    @resources.settle_capacity(ledger, blocker.val.unwrap()).unwrap()
    let usage = @resources.ledger_usage(ledger)
    assert_eq(
      (
        usage.live_reservations,
        usage.held_bytes,
        usage.reserved_retention_bytes,
        usage.reserved_execution_bytes,
      ),
      (0, 0L, 0L, 0L),
    )
    return
  }
  let output = match result {
    Ok(value) => value
    Err(failure) => {
      let issue = local_values_execution_failure_issue(failure)
      let cleaned = retry_local_values_execution_failure_cleanup(failure)
      let detail = match issue {
        Driver(Configuration(Execution(Capture(step, capture)))) =>
          @debug.to_string((step, capture))
        Driver(Execution(Physical(physical))) =>
          "Physical " + @debug.to_string(physical)
        Driver(Configuration(Execution(Rows(step, LogicalRows(logical))))) =>
          "LogicalRows " + @debug.to_string((step, logical))
        Driver(Configuration(Execution(Rows(step, RowLimit)))) =>
          "RowLimit step=" + step.to_string()
        Driver(Configuration(Execution(Rows(step, _)))) =>
          "Rows other step=" + step.to_string()
        Driver(Configuration(Execution(InputLimit))) => "InputLimit"
        Driver(Configuration(Execution(InputSet))) => "InputSet"
        Driver(Configuration(InvalidLimits)) => "Configuration InvalidLimits"
        Driver(Configuration(_)) => "Configuration other"
        Driver(_) => "Driver other"
        FinalizationLimit => "FinalizationLimit"
        _ => "different original failure"
      }
      fail(
        "collection-capture-original-failure " +
        detail +
        " cleanup=" +
        cleaned.to_string(),
      )
    }
  }
  let rows = output.rows().unwrap()
  assert_eq(rows.length(), 9999)
  for row in rows {
    assert_eq(row, "{\"n\":0}")
  }
  assert_true(output.close())
  let usage = @resources.ledger_usage(ledger)
  assert_eq(
    (
      usage.live_reservations,
      usage.held_bytes,
      usage.reserved_retention_bytes,
      usage.reserved_execution_bytes,
    ),
    (0, 0L, 0L, 0L),
  )
}

///|
test "ordinary collection 9999 executes under its original Local capture policy" {
  collection_capture_execution_case(false)
}

///|
test "ordinary collection 9999 cannot borrow occupied execution allowance" {
  collection_capture_execution_case(true)
}

///|
fn collection_cross_text_proof_case(
  sql : String,
  expected : Bool,
) -> Unit raise {
  let prepared = collection_capacity_selected_prepared(sql, 100)
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = prepare_client_local_sequences_owned(
    Pure(prepared),
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(client_local_text_free_scalar_sequences(sequences), expected)
  let plan = client_local_capacity_plan(
    sequences,
    @publication_host.prepared_client_values_max_rows(prepared),
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
  )
  if expected {
    let names = plan.scalar_demand.unwrap().name_bytes
    assert_eq(plan.execution.rows.input_values.max_text_bytes, names)
    assert_eq(plan.execution.rows.output_values.max_text_bytes, names)
  } else {
    assert_eq(plan.execution.rows.input_values.max_text_bytes, 500000)
    assert_eq(plan.execution.rows.output_values.max_text_bytes, 500000)
  }
  assert_false(client_local_text_free_scalar_sequences(sequences, max_work=0))
  assert_false(client_local_text_free_scalar_sequences(sequences, max_slots=0))
}

///|
test "collection CrossJoin keeps checked scalar copy names on its original demand" {
  collection_cross_text_proof_case(
    "SELECT a.n AS left_n, b.n AS right_n FROM (SELECT 1 AS n UNION ALL SELECT 2 AS n) a CROSS JOIN (SELECT 3 AS n) b",
    true,
  )
}

///|
test "collection CrossJoin retains text input and nested value fallback" {
  for
    sql in [
      "SELECT LENGTH(a.text) AS n FROM (SELECT 'text' AS text) a CROSS JOIN (SELECT 1 AS n) b",
      "SELECT a.items AS items FROM (SELECT [1,2] AS items) a CROSS JOIN (SELECT 1 AS n) b",
    ] {
    collection_cross_text_proof_case(sql, false)
  }
}

///|
test "collection CrossJoin cannot hide a dormant text child behind numeric output" {
  collection_cross_text_proof_case(
    "SELECT CASE WHEN FALSE THEN LENGTH(REPEAT('x',4)) ELSE a.n END AS n FROM (SELECT 1 AS n) a CROSS JOIN (SELECT 2 AS n) b",
    false,
  )
}
