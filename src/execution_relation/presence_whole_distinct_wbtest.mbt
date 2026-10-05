///|
fn presence_whole_distinct_fixture(
  empty? : Bool = false,
  input_limits? : ValueLimits = run_limits().input_values,
  workspace_limit? : Int = 10000,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  presence_filter_fixture(
    operations=Some("[{\"distinct\":true}]"),
    wires=Some([
      "{\"id\":2,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":2}", "{\"id\":2,\"p\":7}",
    ]),
    empty~,
    input_limits~,
    workspace_limit~,
  )
}

///|
fn presence_whole_distinct_complete(
  execution : BoundedBindingRowsExecution,
) -> CompletedOutput raise {
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => return output
      BoundedBindingRowsFailed(issue, ..) => {
        let kind = match issue {
          InvalidExecution => "InvalidExecution"
          Rows(RowLimit) => "RowLimit"
          Rows(InvalidRows) => "InvalidRows"
          Rows(Comparison(_)) => "Comparison"
          InputLimit => "InputLimit"
          Capture(_) => "Capture"
          Completion(_) => "Completion"
          _ => "Other"
        }
        let phase = match execution.state.phase {
          SortRows => "SortRows"
          CopyPresenceRow => "CopyPresenceRow"
          MarkDistinct => "MarkDistinct"
          ChargeOutputRow => "ChargeOutputRow"
          ChargeCaptureRow => "ChargeCaptureRow"
          _ => "Other"
        }
        fail("whole-row distinct failed: " + kind + " at " + phase)
      }
      _ => fail("unexpected whole-row distinct stop")
    }
  }
  fail("whole-row distinct exceeded fixture bound")
}

///|
test "presence whole-row distinct must not become a guaranteed-key projection" {
  let (_, execution, input) = presence_whole_distinct_fixture()
  let output = presence_whole_distinct_complete(execution)
  assert_eq(completed_row_count(output), 3)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), Some("p"))
  // All three rows have the same guaranteed id. Only a repeated complete row
  // is removed; omission, explicit NULL and a value remain different rows.
  for row in 0..<3 {
    assert_true(completed_cell(output, row, 0) is Some(Number(2)))
  }
  assert_true(
    completed_presence_cell(output, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(output, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(output, 2, 1) is Ok(Absent))
  assert_true(completed_cell(output, 2, 1) is None)
  let owner = input.bound.receiver
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["distinct_0"],
    100000,
    10000,
  ).unwrap()
  let synchronous = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
    produced=[input.bound],
  ).unwrap()
  let synchronous = completed_output(synchronous, Step(0)).unwrap()
  assert_eq(completed_row_count(synchronous), 3)
  assert_true(
    completed_presence_cell(synchronous, 0, 1)
    is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(synchronous, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(synchronous, 2, 1) is Ok(Absent))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "presence whole-row distinct must retain omission through wire and reload" {
  let (_, execution, _) = presence_whole_distinct_fixture()
  let output = presence_whole_distinct_complete(execution)
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
  let expected = "[{\"id\":2,\"p\":7},{\"id\":2,\"p\":null},{\"id\":2}]"
  assert_eq(bytes, expected)
  // Independent SHA-256 of the literal retained rows, not product output.
  assert_eq(
    @sha.hex(@utf8.encode(bytes)),
    "e1352f176ca4892aace7da1e84d6dc1d261e8fd06fa790283811791964e6abcc",
  )
  let retained = retain_admitted_output_stream(
    completed_export_content(receipt),
    bytes,
    () => true,
  )
  let unavailable = bind_completed_output_export(
    receipt,
    retained_output_material(retained),
  ).unwrap()
  assert_true(completed_presence_cell(unavailable, 0, 1) is Err(_))
  let importing = prepare_completed_output_import(
    unavailable,
    4,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for wire in ["{\"id\":2,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":2}"] {
    append_completed_output_import_wire(
      importing,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let restored = finish_completed_output_import(importing).unwrap()
  assert_true(completed_output_same_occurrence(output, restored))
  assert_true(completed_presence_cell(restored, 2, 1) is Ok(Absent))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "presence whole-row distinct admits the full input and preserves empty schema" {
  let (_, empty, _) = presence_whole_distinct_fixture(empty=true)
  let output = presence_whole_distinct_complete(empty)
  assert_eq(completed_row_count(output), 0)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), Some("p"))
  assert_true(cleanup_bounded_binding_rows(empty).unwrap())
  let (_, limited, input) = presence_whole_distinct_fixture(input_limits={
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
      _ => fail("whole-row distinct discarded duplicate input admission")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
}

///|
test "presence whole-row distinct workspace and cancellation retain cleanup custody" {
  let (_, measured, _) = presence_whole_distinct_fixture()
  presence_whole_distinct_complete(measured) |> ignore
  let peak = measured.state.workspace.peak
  assert_true(cleanup_bounded_binding_rows(measured).unwrap())
  let (_, limited, _) = presence_whole_distinct_fixture(
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
      _ => fail("whole-row distinct ignored workspace frontier")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
  let (control, cancelled, input) = presence_whole_distinct_fixture()
  for _ in 0..<1000 {
    assert_true(
      advance_bounded_binding_rows(cancelled, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if cancelled.state.phase is SortRows {
      break
    }
  }
  assert_true(cancelled.state.phase is SortRows)
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

///|
test "presence whole-row distinct unavailable cells are not omissions" {
  let cursor : BoundedRowComparison = {
    left: -1,
    right: -1,
    terms: 0,
    term: 0,
    phase: -1,
    offset: 0,
    charge: { offset: 0, next: 0, remaining: 0, },
    tree: None,
  }
  assert_true(
    bounded_row_comparison_step_with(
      cursor,
      [{ column: 0, descending: false, nulls_first: false, }],
      { remaining: 100, max_frames: 100, },
      (_, _) => None,
      0,
      1,
      1,
      presence=Some((_, _) => Err(InvalidInput)),
      complete_values=true,
    )
    is Err(InvalidInput),
  )
}
