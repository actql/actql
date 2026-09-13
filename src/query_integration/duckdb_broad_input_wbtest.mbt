///|
fn broad_admitted_number(
  owner : @lower.BoundPrepared,
  value : String,
) -> @admitted.CheckedValue {
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Input(0),
  ).unwrap()
  let contract = @schema.field_at(schema, 0).unwrap().contract
  @admitted.admit(contract, input_cursor(value), {
    max_nodes: 1,
    max_text_bytes: 0,
    max_depth: 0,
  }).unwrap()
}

///|
test "physical broad chunks bind to Local residual without repeating value admission" {
  let (query, owner) = query_sequence_fixture()
  let prepared = @query.prepare_query_sequence(
    query,
    query_generated(owner),
    10000,
  ).unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Input(0),
  ).unwrap()
  let receiver = @duckdb.prepare_physical_result(
    schema,
    [("id", @duckdb.Float64)],
    { max_rows: 3, max_cells: 3, max_nodes: 3, max_text_bytes: 0, },
    100,
  ).unwrap()
  let limits : @execution.ValueLimits = {
    max_nodes: 6,
    max_text_bytes: 6,
    max_depth: 2,
    max_work: 12,
  }
  let builder = @execution.prepare_admitted_input(owner, 0, 3, limits).unwrap()
  for payload in ["4008000000000000", "3ff0000000000000", "4000000000000000"] {
    let batch = @duckdb.admit_physical_chunk(receiver, 1, [
      input_cursor("[\"" + payload + "\"]"),
    ]).unwrap()
    let row = [@duckdb.physical_batch_cell(batch, 0, 0).unwrap()]
    @execution.append_admitted_input(builder, row).unwrap()
    row.clear()
  }
  let captured = @execution.finish_admitted_input(builder).unwrap()
  assert_eq(@execution.captured_usage(captured), {
    nodes: 6,
    text_bytes: 6,
    work: 12,
  })
  assert_eq(@execution.captured_row_count(captured), 3)
  assert_false(@execution.cancel_admitted_input(builder))
  assert_true(@execution.finish_admitted_input(builder) is Err(ClosedCapture))
  let receipt = @query.bind_query_receipt(prepared, captured).unwrap()
  assert_true(physical_equal(@query.query_receipt_rows(receipt), captured))
  assert_true(
    @query.execute_query_receipt(prepared, receipt, {
      ..compute_test_limits(),
      max_work: 0,
    })
    is Err(Execution(_)),
  )
  for _ in 0..<2 {
    let (completed, _) = @query.execute_query_receipt_guarded(
      prepared,
      receipt,
      compute_test_limits(),
      max_output_rows=2,
      max_value_bytes=100,
      { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    ).unwrap()
    let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
  }
  let (other_query, other_owner) = query_sequence_fixture()
  let other = @query.prepare_query_sequence(
    other_query,
    query_generated(other_owner),
    10000,
  ).unwrap()
  assert_true(@query.bind_query_receipt(other, captured) is Err(ForeignReceipt))
}

///|
test "admitted input retention charges exact row keys and occurrences and latches exhaustion" {
  let (_, owner) = query_sequence_fixture()
  let value = broad_admitted_number(owner, "3")
  let exact : @execution.ValueLimits = {
    max_nodes: 4,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 8,
  }
  for
    limits in [
      exact,
      { ..exact, max_nodes: 3, },
      { ..exact, max_text_bytes: 3, },
      { ..exact, max_work: 7, },
    ] {
    let builder = @execution.prepare_admitted_input(owner, 0, 2, limits).unwrap()
    @execution.append_admitted_input(builder, [value]).unwrap()
    let added = @execution.append_admitted_input(builder, [value])
    if limits == exact {
      added.unwrap()
      let rows = @execution.finish_admitted_input(builder).unwrap()
      assert_eq(@execution.captured_usage(rows), {
        nodes: 4,
        text_bytes: 4,
        work: 8,
      })
    } else {
      assert_true(added is Err(CaptureLimit))
      assert_true(
        @execution.finish_admitted_input(builder) is Err(ClosedCapture),
      )
      assert_true(
        @execution.append_admitted_input(builder, [value]) is Err(ClosedCapture),
      )
    }
  }
}

///|
test "admitted input rejects equal foreign contracts and cancellation cannot clear sealed rows" {
  let (_, owner) = query_sequence_fixture()
  let limits = run_limits().input_values
  let wrong = @admitted.admit(
    @value_contract.primitive(@value_contract.NumberType, nullable=false),
    input_cursor("3"),
    { max_nodes: 1, max_text_bytes: 0, max_depth: 0, },
  ).unwrap()
  let builder = @execution.prepare_admitted_input(owner, 0, 2, limits).unwrap()
  assert_true(
    @execution.append_admitted_input(builder, [wrong])
    is Err(ForeignCheckedValue(0, 0)),
  )
  assert_true(@execution.finish_admitted_input(builder) is Err(ClosedCapture))
  let cancelled = @execution.prepare_admitted_input(owner, 0, 2, limits).unwrap()
  @execution.append_admitted_input(cancelled, [
    broad_admitted_number(owner, "3"),
  ]).unwrap()
  assert_true(@execution.cancel_admitted_input(cancelled))
  assert_true(@execution.finish_admitted_input(cancelled) is Err(ClosedCapture))
}
