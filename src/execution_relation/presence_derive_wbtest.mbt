///|
fn presence_derive_fixture(
  operations? : String = "[{\"derive\":{\"z\":\"id + 1\"}}]",
  empty? : Bool = false,
  workspace_limit? : Int = 10000,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  presence_filter_fixture(operations=Some(operations), empty~, workspace_limit~)
}

///|
fn assert_presence_derived(output : CompletedOutput) -> Unit raise {
  assert_eq(completed_row_count(output), 4)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), Some("p"))
  assert_eq(completed_column_name(output, 2), Some("z"))
  for row in 0..<4 {
    assert_true(
      completed_presence_cell(output, row, 0)
      is Ok(Present(@admitted.Number(id))) &&
      id == (row + 1).to_double(),
    )
    assert_true(
      completed_presence_cell(output, row, 2)
      is Ok(Present(@admitted.Number(z))) &&
      z == (row + 2).to_double(),
    )
    assert_true(completed_cell(output, row, 1) is None)
  }
  assert_true(
    completed_presence_cell(output, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(output, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(output, 2, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(output, 3, 1) is Ok(Present(@admitted.Number(8))),
  )
}

///|
test "presence derive bounded and synchronous paths keep cells with row identity" {
  for body in ["{\"z\":\"id + 1\"}", "[{\"z\":\"id + 1\"}]"] {
    let (_, bounded, input) = presence_derive_fixture(
      operations="[{\"derive\":" + body + "}]",
    )
    let output = presence_filter_complete(bounded)
    assert_presence_derived(output)
    let owner = input.bound.receiver
    let sequence = prepared_sequence(owner)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [
        if body.has_prefix("[") {
          bounded_binding_rows_ordered_context(sequence, rows=4L)
        } else {
          sequence_fragment_context(sequence, 0, 4L)
        },
      ],
      ["derive_0"],
      100000,
      10000,
    ).unwrap()
    let completed = execute_generated_sequence(
      generated,
      [],
      compute_test_limits(),
      produced=[input.bound],
    ).unwrap()
    assert_presence_derived(completed_output(completed, Step(0)).unwrap())
    assert_true(cleanup_bounded_binding_rows(bounded).unwrap())
  }
}

///|
test "presence derive Store wire preserves omission NULL and independent canonical content" {
  let (_, execution, _) = presence_derive_fixture()
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
  let wires = [
    "{\"id\":1,\"p\":7,\"z\":2}", "{\"id\":2,\"p\":null,\"z\":3}", "{\"id\":3,\"z\":4}",
    "{\"id\":4,\"p\":8,\"z\":5}",
  ]
  assert_eq(bytes, "[" + wires.join(",") + "]")
  assert_eq(
    @sha.hex(@utf8.encode(bytes)),
    "caf272fcb11ce8b682470d094749be0a0e28b6ef9bcd73e642f272744f997f99",
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
  for wire in wires {
    append_completed_output_import_wire(
      importing,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let reloaded = finish_completed_output_import(importing).unwrap()
  assert_true(completed_output_same_occurrence(output, reloaded))
  assert_presence_derived(reloaded)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "presence derive ordered replacement is dense and does not read absent input" {
  let (_, execution, input) = presence_derive_fixture(
    operations="[{\"derive\":[{\"p\":\"id + 1\"},{\"z\":\"p + 1\"}]}]",
  )
  let output = presence_filter_complete(execution)
  assert_eq(completed_row_count(output), 4)
  for row in 0..<4 {
    assert_true(
      completed_cell(output, row, 1) is Some(Number(p)) &&
      p == (row + 2).to_double(),
    )
    assert_true(
      completed_cell(output, row, 2) is Some(Number(z)) &&
      z == (row + 3).to_double(),
    )
  }
  let owner = input.bound.receiver
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [bounded_binding_rows_ordered_context(sequence, rows=4L)],
    ["derive_0"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
    produced=[input.bound],
  ).unwrap()
  assert_eq(
    completed_row_count(completed_output(completed, Step(0)).unwrap()),
    4,
  )
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "presence derive empty schema resource frontier and cancellation retain custody" {
  let (_, empty, _) = presence_derive_fixture(empty=true)
  let output = presence_filter_complete(empty)
  assert_eq(completed_row_count(output), 0)
  assert_eq(completed_column_name(output, 2), Some("z"))
  assert_true(cleanup_bounded_binding_rows(empty).unwrap())
  let (_, measured, _) = presence_derive_fixture()
  assert_presence_derived(presence_filter_complete(measured))
  let peak = measured.state.workspace.peak
  assert_true(measured.state.workspace.live >= 4 * (1 + 3))
  assert_true(cleanup_bounded_binding_rows(measured).unwrap())
  let (_, limited, input) = presence_derive_fixture(workspace_limit=peak - 1)
  let mut failed = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(limited, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
        failed = true
        break
      }
      _ => fail("derive ignored its workspace frontier")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
  let (control, cancelled, input) = presence_derive_fixture()
  for _ in 0..<1000 {
    assert_true(
      advance_bounded_binding_rows(cancelled, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if cancelled.state.output.unwrap().buffer.presence_rows.length() == 1 {
      break
    }
  }
  assert_eq(cancelled.state.output.unwrap().buffer.presence_rows.length(), 1)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(cancelled, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(bounded_binding_rows_cleanup_pending(cancelled))
  assert_true(cleanup_bounded_binding_rows(cancelled).unwrap())
  assert_eq(cancelled.state.workspace.live, 0)
  assert_true(cancelled.state.rows.val is None)
  assert_true(producer_read_available(input))
}

///|
test "presence derive arithmetic failure retains cleanup and never becomes NULL success" {
  let (_, execution, input) = presence_derive_fixture(
    operations="[{\"derive\":{\"z\":\"1 / (id - 2)\"}}]",
  )
  let mut failed = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(Evaluation(row, slot, issue)), ..) => {
        assert_eq(row, 1)
        assert_eq(slot, 0)
        assert_eq(issue.kind, Scalar(ArithmeticFailure))
        failed = true
        break
      }
      _ => fail("arithmetic failure was weakened")
    }
  }
  assert_true(failed)
  assert_true(execution.state.rows.val is None)
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
  assert_eq(execution.state.workspace.live, 0)
}
