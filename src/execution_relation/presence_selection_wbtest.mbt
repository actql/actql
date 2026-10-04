///|
fn presence_selection_fixture(
  empty? : Bool = false,
  workspace_limit? : Int = 10000,
  take? : Bool = false,
) -> (@lower.BoundPrepared, BoundedBindingRowsExecution, CapturedRows) raise {
  // A declared Required key is checked against every captured row. Do not
  // fabricate total-order evidence for the unordered Events fixture.
  let key = @evidence.declare_primary_key(
    input_cursor("[\"id\"]"),
    @carrier.relation(@carrier.typed_rows(presence_test_schema())),
    { max_fields: 2, max_name_bytes: 100, },
  ).unwrap()
  let owner = sort_input_owner(
    @pipeline.KeyedInput(key),
    if take {
      "[{\"take\":{\"count\":3,\"offset\":1}}]"
    } else {
      "[{\"sort\":[{\"id\":\"desc\"}]}]"
    },
  )
  let input = prepare_admitted_input(owner, 0, 4, stream_value_limits()).unwrap()
  if !empty {
    for
      wire in [
        "{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}", "{\"id\":4,\"p\":8}",
      ] {
      append_admitted_input_presence(
        input,
        read_retained_relation_row(
          input.buffer.schema,
          wire,
          retained_row_test_limits(),
          stream_value_limits(),
        ).unwrap(),
      ).unwrap()
    }
  }
  let captured = finish_admitted_input(input).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, captured, () => true).unwrap()
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [if take { "limit_0" } else { "sort_0" }],
    100000,
    10000,
  ).unwrap()
  let execution = start_bounded_binding_rows_supplied(
    @bounded.control(),
    generated,
    read,
    4,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    workspace_limit,
    10000,
  ).unwrap()
  (owner, execution, captured)
}

///|
test "presence selection sort moves optional cells with their row identity" {
  let (owner, execution, _) = presence_selection_fixture()
  let output = presence_filter_complete(execution)
  for row in 0..<4 {
    assert_true(
      completed_cell(output, row, 0) is Some(Number(id)) &&
      id == (4 - row).to_double(),
    )
  }
  assert_true(
    completed_presence_cell(output, 0, 1) is Ok(Present(@admitted.Number(8))),
  )
  assert_true(completed_presence_cell(output, 1, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(output, 2, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(
    completed_presence_cell(output, 3, 1) is Ok(Present(@admitted.Number(7))),
  )
  let receiver = typed_receiver(
    owner,
    "[{\"take\":{\"count\":3,\"offset\":1}}]",
    target=Step(0),
  )
  let sequence = prepared_sequence(receiver)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_0"],
    100000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, output).unwrap(),
    100,
    10000,
  ).unwrap()
  let taking = start_bounded_binding_rows(
    @bounded.control(),
    generated,
    read,
    4,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  let result = presence_filter_complete(taking)
  assert_eq(completed_row_count(result), 3)
  for row in 0..<3 {
    assert_true(
      completed_cell(result, row, 0) is Some(Number(id)) &&
      id == (3 - row).to_double(),
    )
  }
  assert_true(completed_presence_cell(result, 0, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(result, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(
    completed_presence_cell(result, 2, 1) is Ok(Present(@admitted.Number(7))),
  )
  let stream = prepare_completed_output_export(
    result,
    3,
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
  assert_eq(bytes, "[{\"id\":3},{\"id\":2,\"p\":null},{\"id\":1,\"p\":7}]")
  // Independent SHA-256 of the literal canonical stream, not runtime output.
  assert_eq(
    @sha.hex(@utf8.encode(bytes)),
    "a0816b6c302bcb401187b6f01c5ad06f117f5d223a8aa881d7a38e7c8ee485b9",
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
    3,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for wire in ["{\"id\":3}", "{\"id\":2,\"p\":null}", "{\"id\":1,\"p\":7}"] {
    append_completed_output_import_wire(
      importing,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let reloaded = finish_completed_output_import(importing).unwrap()
  assert_true(completed_output_same_occurrence(result, reloaded))
  for row in 0..<3 {
    assert_true(
      completed_cell(reloaded, row, 0) is Some(Number(id)) &&
      id == (3 - row).to_double(),
    )
  }
  assert_true(completed_presence_cell(reloaded, 0, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(reloaded, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(
    completed_presence_cell(reloaded, 2, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(cleanup_bounded_binding_rows(taking).unwrap())
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
}

///|
test "presence selection empty and synchronous sort retain the same schema and cells" {
  for empty in [false, true] {
    let (owner, execution, captured) = presence_selection_fixture(empty~)
    let bounded = presence_filter_complete(execution)
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["sort_0"],
      100000,
      10000,
    ).unwrap()
    let complete = execute_generated_sequence(
      generated,
      [captured],
      compute_test_limits(),
    ).unwrap()
    let synchronous = completed_output(complete, Step(0)).unwrap()
    assert_eq(completed_row_count(bounded), if empty { 0 } else { 4 })
    assert_eq(completed_row_count(synchronous), completed_row_count(bounded))
    assert_eq(completed_column_name(bounded, 0), Some("id"))
    assert_eq(completed_column_name(bounded, 1), Some("p"))
    for row in 0..<completed_row_count(bounded) {
      assert_true(
        completed_presence_cell(synchronous, row, 0)
        is Ok(Present(@admitted.Number(id))) &&
        id == (4 - row).to_double(),
      )
    }
    if !empty {
      assert_true(
        completed_presence_cell(synchronous, 0, 1)
        is Ok(Present(@admitted.Number(8))),
      )
      assert_true(completed_presence_cell(synchronous, 1, 1) is Ok(Absent))
      assert_true(
        completed_presence_cell(synchronous, 2, 1)
        is Ok(Present(@admitted.Null)),
      )
      assert_true(
        completed_presence_cell(synchronous, 3, 1)
        is Ok(Present(@admitted.Number(7))),
      )
    }
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  }
}

///|
test "presence selection keeps private sort cells charged until cancellation cleanup" {
  let (_, execution, _) = presence_selection_fixture()
  let mut copied = false
  for _ in 0..<1000 {
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if execution.state.output.unwrap().buffer.presence_rows.length() == 1 {
      copied = true
      break
    }
  }
  assert_true(copied)
  assert_true(execution.state.workspace.live > 0)
  assert_true(@bounded.request_cancel(execution.state.engine))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
  assert_true(execution.state.rows.val is None)
  assert_false(bounded_binding_rows_cleanup_pending(execution))
}

///|
test "presence selection take keeps key completion and bounded retention accounting" {
  let (owner, execution, captured) = presence_selection_fixture(take=true)
  let output = presence_filter_complete(execution)
  let peak = execution.state.workspace.peak
  assert_true(execution.state.workspace.live >= 3 * (1 + 2))
  for row in 0..<3 {
    assert_true(
      completed_cell(output, row, 0) is Some(Number(id)) &&
      id == (row + 2).to_double(),
    )
  }
  assert_true(
    completed_presence_cell(output, 0, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(output, 1, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(output, 2, 1) is Ok(Present(@admitted.Number(8))),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["limit_0"],
    100000,
    10000,
  ).unwrap()
  let complete = execute_generated_sequence(
    generated,
    [captured],
    compute_test_limits(),
  ).unwrap()
  let synchronous = completed_output(complete, Step(0)).unwrap()
  for row in 0..<3 {
    assert_true(
      completed_cell(synchronous, row, 0) is Some(Number(id)) &&
      id == (row + 2).to_double(),
    )
  }
  assert_true(
    completed_presence_cell(synchronous, 0, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(synchronous, 1, 1) is Ok(Absent))
  assert_true(
    completed_presence_cell(synchronous, 2, 1)
    is Ok(Present(@admitted.Number(8))),
  )
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
  let (_, limited, _) = presence_selection_fixture(
    take=true,
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
      _ => fail("take ignored its presence workspace frontier")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(limited.state.workspace.live > 0)
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
  assert_eq(limited.state.workspace.live, 0)
}
