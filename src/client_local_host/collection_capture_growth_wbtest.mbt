///|
fn collection_capture_execution_case(
  refuse : Bool,
  finalization_quantum? : Int = 64,
  memory? : Int64 = 1073741824L,
  retention_refuse? : Bool = false,
) -> Unit raise {
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
  assert_true(client_local_text_free_scalar_sequences(original.sequences))
  // The five original ten-row dimensions produce 100000 candidate rows.
  // Their FILTER retains an input-root entry for each row before evaluation;
  // the ordinary Plan must select structural slots for that exact inventory.
  assert_true(plan.execution.rows.operation_entries > 100000)
  assert_true(
    client_local_capacity_plan_matches(
      plan,
      original.sequences,
      plan.admitted_rows,
    ),
  )
  assert_false(
    client_local_capacity_plan_matches(
      {
        ..plan,
        execution: {
          ..plan.execution,
          rows: { ..plan.execution.rows, operation_entries: 10000, },
        },
      },
      original.sequences,
      plan.admitted_rows,
    ),
  )
  let demand = plan.scalar_demand.unwrap()
  assert_true(demand.name_bytes > 500000)
  assert_eq(plan.execution.rows.output_values.max_text_bytes, demand.name_bytes)
  assert_eq(plan.execution.rows.input_values.max_text_bytes, demand.name_bytes)
  let mut filter : (Int, Int)? = None
  for task, sequence in original.sequences {
    for index in 0..<@execution.generated_sequence_step_count(sequence) {
      if @execution.generated_sequence_step_at(sequence, index)
        is Some(@lower.RowStep(kernel)) &&
        @lower.kernel_is_filter(kernel) {
        assert_true(filter is None)
        filter = Some(
          (
            task,
            @execution.generated_sequence_step_index_at(sequence, index).unwrap(),
          ),
        )
      }
    }
  }
  guard filter is Some((filter_task, filter_step)) else {
    fail("original collection predicate required")
  }
  let requirements = @execution.generated_sequence_requirements(
    original.sequences[filter_task],
    10000,
  ).unwrap()
  let fragment = @lower.sequence_requirements_fragment_for_step(
    requirements, filter_step,
  ).unwrap()
  assert_eq(
    fragment.logical.max_work,
    plan.execution.rows.input_values.max_work.to_int64(),
  )
  // A quote is not the ordinary admission. Supply the original finite Run
  // authority explicitly, as the existing whole-Source chain fixtures do.
  let limits = {
    ..original.limits,
    // Match the original public full-collection capture selection. The
    // separate 512 MiB negative below retains its original finite refusal.
    retained_bytes: memory,
    execution_bytes: memory,
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
  let attempts_before_filter : Ref[Int?] = Ref(None)
  let current = if refuse || retention_refuse {
    fn() {
      let usage = @resources.ledger_usage(ledger)
      let next = @strategy.next_captured_task(captured)
      if next == Some(filter_task) && attempts_before_filter.val is None {
        attempts_before_filter.val = Some(usage.attempts)
      }
      let selected = if retention_refuse {
        // The original attempt has started and paid its startup envelope.
        // Occupy only the remaining SAME Ledger retention before its first
        // imported row asks for actual DATA growth, preserving the policy.
        attempts_before_filter.val
        .map(before => usage.attempts > before)
        .unwrap_or(false)
      } else {
        next == Some(filter_task)
      }
      if blocker.val is None && selected {
        blocker.val = Some(
          @resources.reserve_capacity(
            ledger,
            if retention_refuse {
              limits.retained_bytes -
              usage.held_bytes -
              usage.reserved_retention_bytes
            } else {
              0L
            },
            if retention_refuse {
              0L
            } else {
              limits.execution_bytes - usage.reserved_execution_bytes
            },
          ).unwrap(),
        )
      }
      true
    }
  } else {
    () => true
  }
  let result = execute_source_free_local_tasks_guarded(
    setup, finalization_quantum, 100000, current,
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
  if retention_refuse {
    assert_true(blocker.val is Some(_))
    guard result is Err(failure) else {
      fail("occupied original retention allowance completed")
    }
    let primary = local_values_execution_failure_issue(failure)
    guard primary
      is Driver(ExecutionCapacityRefusal(physical, needed, available, policy)) else {
      fail("original quota refusal missing")
    }
    assert_true(physical is @resources.RetentionLimit)
    assert_true(needed > available)
    assert_true(available >= 0L && available <= policy)
    assert_eq(policy, 536870912L)
    @resources.settle_capacity(ledger, blocker.val.unwrap()).unwrap()
    for _ in 0..<10000 {
      if retry_local_values_execution_failure_cleanup(failure) {
        break
      }
    }
    assert_false(local_values_execution_failure_cleanup_pending(failure))
    assert_true(
      physical_equal(primary, local_values_execution_failure_issue(failure)),
    )
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
        Driver(ExecutionCapacityRefusal(physical, required, available, policy)) =>
          "capacity " +
          @debug.to_string((physical, required, available, policy))
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
  collection_capture_execution_case(true, memory=536870912L)
}

///|
test "ordinary collection cannot borrow occupied 512 MiB retention and drains partial input cleanup" {
  collection_capture_execution_case(
    false,
    memory=536870912L,
    retention_refuse=true,
  )
}

///|
test "collection finalization keeps exact rows at the installed Node quantum" {
  collection_capture_execution_case(false, finalization_quantum=32)
}

///|
fn collection_cross_text_proof_case(
  sql : String,
  expected : Bool,
  fallback_text? : Int = 500000,
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
  // A complete leaf proof may use the caller's finite work-derived Text
  // envelope. Nested/unproved values retain the independent general policy;
  // a text-free output alone cannot narrow its input or children.
  let selected_work = 765432
  let plan = client_local_capacity_plan(
    sequences,
    @publication_host.prepared_client_values_max_rows(prepared),
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
    source_free_max_work=Some(selected_work),
  )
  if expected {
    let names = plan.scalar_demand.unwrap().name_bytes
    assert_eq(plan.execution.rows.input_values.max_text_bytes, names)
    assert_eq(plan.execution.rows.output_values.max_text_bytes, names)
  } else {
    assert_eq(plan.execution.rows.input_values.max_text_bytes, fallback_text)
    assert_eq(plan.execution.rows.output_values.max_text_bytes, fallback_text)
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
    (sql, fallback_text) in [
      (
        "SELECT LENGTH(a.text) AS n FROM (SELECT 'text' AS text) a CROSS JOIN (SELECT 1 AS n) b",
        765432,
      ),
      (
        "SELECT a.items AS items FROM (SELECT [1,2] AS items) a CROSS JOIN (SELECT 1 AS n) b",
        500000,
      ),
    ] {
    collection_cross_text_proof_case(sql, false, fallback_text~)
  }
}

///|
test "collection CrossJoin cannot hide a dormant text child behind numeric output" {
  collection_cross_text_proof_case(
    "SELECT CASE WHEN FALSE THEN LENGTH(REPEAT('x',4)) ELSE a.n END AS n FROM (SELECT 1 AS n) a CROSS JOIN (SELECT 2 AS n) b",
    false,
  )
}

///|
test "ordinary FILTER entry demand uses checked scalar structures and finite overflow fallback" {
  let prepared = collection_capacity_selected_prepared(
    "SELECT n FROM (SELECT 1 AS n UNION ALL SELECT 2 AS n) WHERE n + 3 * n < 10",
    100000,
  )
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
  let mut found = false
  for sequence in sequences {
    for index in 0..<@execution.generated_sequence_step_count(sequence) {
      if @execution.generated_sequence_step_at(sequence, index)
        is Some(@lower.RowStep(kernel)) &&
        @lower.kernel_body(kernel) is @lower.Filter(predicate) {
        let i = @schema.field_count(@lower.kernel_input_schema(kernel))
        let o = @schema.field_count(@lower.kernel_output_schema(kernel))
        let expression = client_local_filter_expression_slots(predicate, 100)
        assert_true(expression > 0)
        assert_eq(
          client_local_request_operation_entries([sequence], 10001, 10000, 100),
          10001 + 3 * i + 4 * o + expression + 8,
        )
        assert_eq(
          client_local_request_operation_entries([sequence], 10001, 10000, 0),
          10000,
        )
        assert_eq(
          client_local_request_operation_entries(
            [sequence],
            2147483647,
            10000,
            100,
          ),
          10000,
        )
        found = true
      }
    }
  }
  assert_true(found)
  let unknown = collection_capacity_selected_prepared(
    "SELECT n FROM (SELECT 1 AS n UNION ALL SELECT 2 AS n) WHERE CAST(n AS STRING) = '1'",
    100000,
  )
  let sequences = prepare_client_local_sequences_owned(
    Pure(unknown),
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_eq(
    client_local_request_operation_entries(sequences, 10001, 10000, 100),
    10000,
  )
}

///|
test "ordinary literal Array entry demand funds the original constructor and preserves explicit caps" {
  let sql = "SELECT [" + Array::make(4000, "0").join(",") + "] AS cells"
  let prepared = collection_capacity_selected_prepared(sql, 100000)
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  // Constructor/Plan correspondence only. Use the ordinary Request's stored
  // compiler codec and authored 30M work selection, rather than the legacy
  // unowned helper's smaller metadata codec. Run admission remains separate.
  let sequences = prepare_client_local_sequences_owned(
    Pure(prepared),
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    source_free_max_work=Some(30000000),
    compilation_limits=Some(
      @publication_host.client_standard_pure_compilation_limits(),
    ),
  ).unwrap()
  let plan = client_local_capacity_plan(
    sequences,
    100000,
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
    source_free_max_work=Some(30000000),
  )
  assert_true(plan.execution.rows.operation_entries >= 12016)
  assert_true(
    client_local_capacity_plan_matches(plan, sequences, plan.admitted_rows),
  )
  assert_false(
    client_local_capacity_plan_matches(
      {
        ..plan,
        execution: {
          ..plan.execution,
          rows: { ..plan.execution.rows, operation_entries: 10000, },
        },
      },
      sequences,
      plan.admitted_rows,
    ),
  )
  let mut found = false
  for sequence in sequences {
    for index in 0..<@execution.generated_sequence_step_count(sequence) {
      guard @execution.generated_sequence_step_at(sequence, index)
        is Some(@lower.RowStep(kernel)) &&
        @lower.kernel_bindings(kernel) is Some(bindings) &&
        @lower.bindings_count(bindings) == 1 &&
        @lower.binding_at(bindings, 0) is Some((_, expression)) &&
        @lower.expression_primitive_array_length(expression) == Some(4000) else {
        continue
      }
      found = true
      let i = @schema.field_count(@lower.kernel_input_schema(kernel))
      let o = @schema.field_count(@lower.kernel_output_schema(kernel))
      assert_eq(
        client_local_request_operation_entries([sequence], 1, 10000, 100),
        1 + 3 * i + 4 * o + 12016,
      )
      assert_eq(
        client_local_request_operation_entries(
          [sequence],
          2147483647,
          10000,
          100,
        ),
        10000,
      )
      for entries in [8, plan.execution.rows.operation_entries] {
        let active = @execution.start_expression_execution(
          expression,
          Map([]),
          [],
          1000000,
          100,
          entries,
        ).unwrap()
        let mut finished = false
        for _ in 0..<1000000 {
          match @execution.advance_expression_execution(active) {
            Ok(@execution.ExpressionContinue) => ()
            Ok(
              @execution.ExpressionComplete(
                @execution.Captured(@admitted.Array(items))
              )
            ) => {
              assert_true(entries > 10000)
              assert_eq(@admitted.element_count(items), 4000)
              for item in 0..<4000 {
                assert_true(
                  @admitted.element_at(items, item)
                  is Some(@admitted.Number(0.0)),
                )
              }
              finished = true
              break
            }
            Err(issue) if entries == 8 => {
              assert_true(issue.kind is @execution.WorkspaceLimit)
              finished = true
              break
            }
            _ => fail("original literal Array constructor changed")
          }
        }
        assert_true(finished)
        assert_true(@execution.cancel_expression_execution(active))
      }
    }
  }
  assert_true(found)
}
