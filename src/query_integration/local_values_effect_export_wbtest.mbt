///|
// Original installed Local Values dispatcher and an explicit Core test Ledger.
// This supplies no normal Native backing, authorization or Provider resource.
fn values_effect_export_fixture(
  empty? : Bool = false,
) -> (
  @strategy.CapturedEffectRunDAG,
  @strategy.CapturedEffectInputs,
  @client_local_host.LocalValuesExecution,
) raise {
  let (bound, captured, registry, values, fragment) = local_effect_dispatch_fixture(
    empty~,
  )
  let setup = @client_local_host.configure_source_free_effect_local_retained_host(
    bound,
    captured,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let execution = @client_local_host.execute_source_free_values_guarded(
    setup,
    64,
    1000,
    () => true,
  ).unwrap()
  let inputs = @strategy.pin_captured_effect_sources(captured, 2).unwrap()
  (captured, inputs, execution)
}

///|
fn values_effect_export_test_limits() -> (
  @execution.RetainedRowDecodeLimits,
  @publication_host.PublicationOutputExportLimits,
) {
  let wire = row_wire_limits()
  (
    { max_bytes: 10000, max_nodes: 1000, max_depth: 20, max_text_bytes: 10000, },
    {
      max_result_fields: 10,
      max_result_mapping_work: 100,
      max_result_order_work: 1000,
      max_result_workspace_entries: 20,
      max_rows: 10,
      values: {
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 10000,
      },
      payload_wire: wire,
      logical_wire: wire,
      schema: {
        max_fields: 10,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      max_batch_bytes: 64,
    },
  )
}

///|
// Select the independent authored name through the original local inventory,
// rather than assuming an Effect/member/public Result array position.
fn values_effect_export_test_index(
  inputs : @strategy.CapturedEffectInputs,
  name : String,
) -> Int raise {
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
    let occurrence = @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    )
    if @execution.managed_result_occurrence_name(occurrence) == name {
      return index
    }
  }
  fail("missing original local Result")
}

///|
fn values_effect_export_test_finish(
  exported : @strategy.CapturedEffectLocalResultExport,
) -> (@execution.CompletedRelationExportReceipt, Array[String]) raise {
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let mut complete = false
  for _ in 0..<100 {
    if @execution.advance_completed_result_relation_export(preparation, 64).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  let rows : Array[String] = []
  while @execution.next_completed_output_export_canonical_row(
          stream, 1000, 20, 1000,
        ).unwrap()
        is Some((_, _, row)) {
    rows.push(@identity.stringify_value(row, 10000, 1000, 20))
  }
  let (receipt, _) = @execution.finish_completed_relation_export(stream).unwrap()
  (receipt, rows)
}

///|
fn values_effect_export_test_close(
  captured : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  execution : @client_local_host.LocalValuesExecution,
) -> Unit raise {
  @strategy.release_captured_effect_inputs(inputs) |> ignore
  assert_true(execution.close())
  let usage = @resources.ledger_usage(
    @strategy.captured_dag_ledger(@strategy.captured_effect_run_dag(captured)),
  )
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "Local Values Effect export binds each original local Result and keeps empty Relation schema" {
  for empty in [false, true] {
    let (captured, inputs, execution) = values_effect_export_fixture(empty~)
    let (rows, limits) = values_effect_export_test_limits()
    for name in ["out", "other"] {
      let index = values_effect_export_test_index(inputs, name)
      let value = execution
        .prepare_effect_result_export(
          captured, inputs, index, rows, 100, 10000, limits,
        )
        .unwrap()
      let exported = value.captured_export().unwrap()
      assert_true(
        @strategy.captured_effect_local_result_export_retained(inputs, exported),
      )
      let (receipt, actual) = values_effect_export_test_finish(exported)
      assert_eq(actual, if empty { [] } else { ["{\"value\":1}"] })
      assert_eq(
        @execution.completed_relation_export_measurement(receipt).row_count,
        if empty {
          0
        } else {
          1
        },
      )
      assert_true(
        @strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, receipt,
        ),
      )
      value.close()
      value.close()
      assert_true(value.captured_export() is None)
      assert_false(
        @strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, receipt,
        ),
      )
      @execution.cancel_completed_relation_export_receipt(receipt)
      assert_true(@strategy.captured_effect_inputs_match_run(inputs, captured))
      assert_eq(
        execution.rows().unwrap(),
        if empty {
          []
        } else {
          ["{\"value\":1}"]
        },
      )
    }
    values_effect_export_test_close(captured, inputs, execution)
  }
}

///|
test "Local Values Effect export refuses a same-byte foreign Run or pin set before borrowing rows" {
  let (captured, inputs, execution) = values_effect_export_fixture()
  let (foreign, foreign_inputs, foreign_execution) = values_effect_export_fixture()
  let (rows, limits) = values_effect_export_test_limits()
  assert_true(
    execution.prepare_effect_result_export(
      foreign, foreign_inputs, 0, rows, 100, 10000, limits,
    )
    is Err(@client_local_host.ForeignInput),
  )
  assert_true(
    execution.prepare_effect_result_export(
      captured, foreign_inputs, 0, rows, 100, 10000, limits,
    )
    is Err(@client_local_host.ForeignInput),
  )
  assert_true(
    execution.prepare_effect_result_export(
      captured, inputs, -1, rows, 100, 10000, limits,
    )
    is Err(@client_local_host.MissingResult),
  )
  assert_eq(execution.rows().unwrap(), ["{\"value\":1}"])
  assert_eq(foreign_execution.rows().unwrap(), ["{\"value\":1}"])
  values_effect_export_test_close(captured, inputs, execution)
  values_effect_export_test_close(foreign, foreign_inputs, foreign_execution)
}

///|
test "Local Values Effect export observes original alias retirement without closing Compute" {
  let (captured, inputs, execution) = values_effect_export_fixture()
  let (rows, limits) = values_effect_export_test_limits()
  let index = values_effect_export_test_index(inputs, "out")
  let value = execution
    .prepare_effect_result_export(
      captured, inputs, index, rows, 100, 10000, limits,
    )
    .unwrap()
  let exported = value.captured_export().unwrap()
  let borrow = @strategy.captured_effect_local_result_borrow(
    @strategy.captured_effect_local_result_export_result(exported),
  )
  assert_true(@strategy.release_captured_any_result_borrow(borrow))
  // inputs.live alone remains true. The callback-free original pin fence must
  // observe retirement of this exact consumer instead of trusting that flag.
  assert_true(@strategy.captured_effect_inputs_match_run(inputs, captured))
  assert_false(
    @strategy.captured_effect_local_result_export_retained(inputs, exported),
  )
  assert_true(value.captured_export() is None)
  assert_eq(execution.rows().unwrap(), ["{\"value\":1}"])
  value.close()
  values_effect_export_test_close(captured, inputs, execution)
}

///|
test "Local Values Effect export keeps original row and field bounds without losing the completed Run" {
  let (captured, inputs, execution) = values_effect_export_fixture()
  let (rows, limits) = values_effect_export_test_limits()
  let index = values_effect_export_test_index(inputs, "out")
  assert_true(
    execution.prepare_effect_result_export(
      captured,
      inputs,
      index,
      { ..rows, max_bytes: 1, },
      100,
      10000,
      limits,
    )
    is Err(@client_local_host.Bridge(_)),
  )
  assert_true(
    execution.prepare_effect_result_export(
      captured,
      inputs,
      index,
      rows,
      100,
      10000,
      { ..limits, max_result_fields: 0, },
    )
    is Err(@client_local_host.Export(_)),
  )
  let value = execution
    .prepare_effect_result_export(
      captured, inputs, index, rows, 100, 10000, limits,
    )
    .unwrap()
  let (receipt, actual) = values_effect_export_test_finish(
    value.captured_export().unwrap(),
  )
  assert_eq(actual, ["{\"value\":1}"])
  @execution.cancel_completed_relation_export_receipt(receipt)
  value.close()
  values_effect_export_test_close(captured, inputs, execution)
  assert_true(
    execution.prepare_effect_result_export(
      captured, inputs, index, rows, 100, 10000, limits,
    )
    is Err(@client_local_host.MissingOutput),
  )
}

///|
test "Local Values ordinary Named Result export preserves its canonical payload after shared bridge extraction" {
  let (captured, inputs, execution) = values_effect_export_fixture()
  let (rows, limits) = values_effect_export_test_limits()
  let value = match
    execution.prepare_result_export(0, rows, 100, 10000, limits) {
    Ok(value) => value
    Err(issue) => {
      let cause = match issue {
        MissingOutput => "MissingOutput"
        UnknownResult => "UnknownResult"
        Bridge(_) => "Bridge"
        Export(Retain(_)) => "Retain"
        Export(Output(_)) => "Output"
        Export(_) => "Export"
        Transformation(ForeignSelection) => "Transformation.ForeignSelection"
        Transformation(InvalidState) => "Transformation.InvalidState"
        Transformation(_) => "Transformation.Other"
      }
      fail("Original ordinary Named Result export: " + cause)
    }
  }
  let stream = value.output_export()
  let mut wire = ""
  while stream.next().unwrap() is Some(batch) {
    wire += batch
  }
  wire += stream.finish().unwrap()
  assert_eq(wire, "[{\"value\":1}]")
  assert_eq(
    stream.content_cid().unwrap(),
    "sha256:" + @sha.hex(@utf8.encode("[{\"value\":1}]")),
  )
  value.close()
  assert_eq(execution.rows().unwrap(), ["{\"value\":1}"])
  values_effect_export_test_close(captured, inputs, execution)
}
