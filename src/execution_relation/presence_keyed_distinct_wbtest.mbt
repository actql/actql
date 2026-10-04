///|
fn presence_keyed_distinct_fixture(
  empty? : Bool = false,
  input_limits? : ValueLimits = run_limits().input_values,
  workspace_limit? : Int = 10000,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  presence_filter_fixture(
    operations=Some("[{\"distinct\":[\"id\"]}]"),
    wires=Some([
      "{\"id\":2,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":2}", "{\"id\":1,\"p\":8}",
    ]),
    empty~,
    input_limits~,
    workspace_limit~,
  )
}

///|
fn assert_presence_keyed_distinct(output : CompletedOutput) -> Unit raise {
  assert_eq(completed_row_count(output), 2)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), None)
  assert_true(completed_cell(output, 0, 0) is Some(Number(2)))
  assert_true(completed_cell(output, 1, 0) is Some(Number(1)))
}

///|
test "presence keyed distinct bounded and synchronous paths ignore unprojected cell states" {
  let (_, bounded, input) = presence_keyed_distinct_fixture()
  assert_presence_keyed_distinct(presence_filter_complete(bounded))
  let owner = input.bound.receiver
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["distinct_0"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
    produced=[input.bound],
  ).unwrap()
  assert_presence_keyed_distinct(completed_output(completed, Step(0)).unwrap())
  // The input's optional columns have not been filled, erased or changed.
  assert_true(
    completed_presence_cell(input.bound.output, 0, 1)
    is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(input.bound.output, 1, 1)
    is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(input.bound.output, 2, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(input.bound.output, 3, 1)
    is Ok(Present(@admitted.Number(8))),
  )
  assert_true(cleanup_bounded_binding_rows(bounded).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "presence keyed distinct retains exact projection bytes and verified Store reload" {
  let (_, execution, _) = presence_keyed_distinct_fixture()
  let output = presence_filter_complete(execution)
  let stream = prepare_completed_output_export(
    output,
    4,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let saved = StringBuilder()
  while next_completed_output_export(stream).unwrap() is Some(part) {
    saved.write_string(part)
  }
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  saved.write_string(tail)
  let bytes = saved.to_string()
  assert_eq(bytes, "[{\"id\":2},{\"id\":1}]")
  // Independent SHA-256 of the literal projected rows, not encoder output.
  assert_eq(
    @sha.hex(@utf8.encode(bytes)),
    "1546ad5b6653e302e9e61296e1bbf4d7746e91c5cea80e5e1731a4b2523ad25a",
  )
  let retained = retain_admitted_output_stream(
    completed_export_content(receipt),
    bytes,
    () => true,
  )
  let saved_output = bind_completed_output_export(
    receipt,
    retained_output_material(retained),
  ).unwrap()
  assert_true(completed_cell(saved_output, 0, 0) is None)
  let importing = prepare_completed_output_import(
    saved_output,
    4,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for wire in ["{\"id\":2}", "{\"id\":1}"] {
    append_completed_output_import_wire(
      importing,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let reloaded = finish_completed_output_import(importing).unwrap()
  assert_true(completed_output_same_occurrence(output, reloaded))
  assert_presence_keyed_distinct(reloaded)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "presence keyed distinct admits erased columns and retains empty output schema" {
  let (_, empty, _) = presence_keyed_distinct_fixture(empty=true)
  let output = presence_filter_complete(empty)
  assert_eq(completed_row_count(output), 0)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), None)
  assert_true(cleanup_bounded_binding_rows(empty).unwrap())
  // All four original two-column rows count, even though only two id cells
  // survive. Omission still occupies its presence slot in the input budget.
  let (_, limited, input) = presence_keyed_distinct_fixture(input_limits={
    ..run_limits().input_values,
    max_nodes: 11,
  })
  let mut failed = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(limited, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(InputLimit, ..) => {
        failed = true
        break
      }
      _ => fail("keyed distinct discarded input admission")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
}

///|
test "presence keyed distinct workspace failure and cancellation keep cleanup custody" {
  let (_, measured, _) = presence_keyed_distinct_fixture()
  assert_presence_keyed_distinct(presence_filter_complete(measured))
  let peak = measured.state.workspace.peak
  assert_true(cleanup_bounded_binding_rows(measured).unwrap())
  let (_, limited, _) = presence_keyed_distinct_fixture(
    workspace_limit=peak - 1,
  )
  let mut failed = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(limited, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
        failed = true
        break
      }
      _ => fail("keyed distinct ignored its workspace frontier")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
  let (control, cancelled, input) = presence_keyed_distinct_fixture()
  for _ in 0..<1000 {
    assert_true(
      advance_bounded_binding_rows(cancelled, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if cancelled.state.phase is SortRows ||
      cancelled.state.phase is InitializeDistinctKeep {
      break
    }
  }
  assert_true(
    cancelled.state.phase is SortRows ||
    cancelled.state.phase is InitializeDistinctKeep,
  )
  assert_true(cancelled.state.workspace.live > 0)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(cancelled, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(cancelled.state.rows.val is None)
  assert_true(bounded_binding_rows_cleanup_pending(cancelled))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(cancelled).unwrap())
  assert_false(cleanup_bounded_binding_rows(cancelled).unwrap())
  assert_eq(cancelled.state.workspace.live, 0)
}
