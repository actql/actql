///|
fn presence_filter_fixture(
  empty? : Bool = false,
  predicate? : String = "id < 4",
  input_limits? : ValueLimits = run_limits().input_values,
  workspace_limit? : Int = 10000,
  operations? : String? = None,
  wires? : Array[String]? = None,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  let source_owner = presence_output_owner()
  let supplied = prepare_admitted_output(
    source_owner,
    Step(0),
    4,
    stream_value_limits(),
  ).unwrap()
  if !empty {
    for
      wire in wires.unwrap_or([
        "{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}", "{\"id\":4,\"p\":8}",
      ]) {
      append_admitted_output_presence(
        supplied,
        read_retained_relation_row(
          supplied.buffer.schema,
          wire,
          retained_row_test_limits(),
          stream_value_limits(),
        ).unwrap(),
      ).unwrap()
    }
  }
  let rows = finish_admitted_output(supplied).unwrap()
  let completion = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(source_owner),
    ["events_0"],
    10000,
    1000,
  ).unwrap()
  let port = prepare_trusted_output_port(completion, Step(0), 1000, 10000, fn(
    _ : Unit,
  ) {
    Some(rows)
  }).unwrap()
  let source = complete_trusted_output(port, ()).unwrap()
  let owner = typed_receiver(
    source_owner,
    operations.unwrap_or("[{\"filter\":\"" + predicate + "\"}]"),
    target=Step(0),
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    if @lower.sequence_step(sequence, 0) is Some(@lower.RowStep(kernel)) &&
      @lower.kernel_is_distinct(kernel) {
      []
    } else {
      [
        if @lower.sequence_step(sequence, 0) is Some(@lower.RowStep(kernel)) &&
          @lower.kernel_body(kernel) is @lower.OrderedBindings(_) {
          bounded_binding_rows_ordered_context(sequence, rows=4L)
        } else {
          sequence_fragment_context(sequence, 0, 4L)
        },
      ]
    },
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let input = prepare_producer_read(
    owner,
    bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
    generated,
    input,
    4,
    input_limits,
    run_limits().output_values,
    100000,
    100,
    workspace_limit,
    10000,
  ).unwrap()
  (control, execution, input)
}

///|
fn presence_filter_complete(
  execution : BoundedBindingRowsExecution,
) -> CompletedOutput raise {
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => return output
      BoundedBindingRowsFailed(_, ..) => fail("presence filter failed")
      _ => fail("unexpected presence filter stop")
    }
  }
  fail("presence filter exceeded fixture bound")
}

///|
test "presence filter keeps omitted NULL and value cells attached to their rows" {
  let (_, execution, input) = presence_filter_fixture()
  let output = presence_filter_complete(execution)
  assert_eq(completed_row_count(output), 3)
  for row in 0..<3 {
    match completed_presence_cell(output, row, 0).unwrap() {
      Present(@admitted.Number(id)) => assert_eq(id, (row + 1).to_double())
      _ => fail("presence moved to another row")
    }
    assert_true(completed_cell(output, row, 1) is None)
  }
  assert_true(
    completed_presence_cell(output, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(output, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(output, 2, 1) is Ok(Absent))
  let stream = prepare_completed_output_export(
    output,
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
  // Literal canonical stream and its independent Node-crypto SHA-256. No
  // encoder-generated expected bytes, NULL filling or physical-layout pin.
  assert_eq(bytes, "[{\"id\":1,\"p\":7},{\"id\":2,\"p\":null},{\"id\":3}]")
  assert_eq(
    @sha.hex(@utf8.encode(bytes)),
    "12df04cee2e595d5e54cc4baecdbde4436c2dbf10ac66a643cdbdc784833827a",
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
    3,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
    append_completed_output_import_wire(
      importing,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let reloaded = finish_completed_output_import(importing).unwrap()
  assert_true(completed_output_same_occurrence(output, reloaded))
  assert_true(
    completed_presence_cell(reloaded, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(reloaded, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(reloaded, 2, 1) is Ok(Absent))
  for row in 0..<3 {
    match completed_cell(reloaded, row, 0) {
      Some(Number(id)) => assert_eq(id, (row + 1).to_double())
      _ => fail("reload detached row identity")
    }
  }
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
  assert_true(completed_output_available(output))
  assert_true(producer_read_available(input))
}

///|
test "presence filter preserves empty schema and admits rejected rows before evaluation" {
  let (_, execution, _) = presence_filter_fixture(empty=true)
  let output = presence_filter_complete(execution)
  assert_eq(completed_row_count(output), 0)
  assert_eq(completed_column_name(output, 0), Some("id"))
  assert_eq(completed_column_name(output, 1), Some("p"))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  // Four rows still consume input resources when the predicate rejects all.
  let (_, limited, input) = presence_filter_fixture(
    predicate="false",
    // Each row costs an object node and two value/presence nodes: twelve
    // total, not just the nine nodes of the eventual surviving rows.
    input_limits={ ..run_limits().input_values, max_nodes: 11, },
  )
  let mut failed = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(limited, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(InputLimit, ..) => {
        failed = true
        break
      }
      _ => fail("filter erased complete input admission")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(limited))
}

///|
test "presence filter cancellation never publishes private accepted rows" {
  let (control, execution, input) = presence_filter_fixture()
  let mut private_row = false
  for _ in 0..<1000 {
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if execution.state.output.unwrap().buffer.presence_rows.length() == 1 {
      private_row = true
      break
    }
  }
  assert_true(private_row)
  assert_true(execution.state.workspace.live > 0)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
  assert_eq(execution.state.workspace.live, 0)
  assert_true(execution.state.rows.val is None)
  assert_true(producer_read_available(input))
}

///|
test "presence filter synchronous sequence uses the same omission-preserving semantics" {
  let (control, bounded, input) = presence_filter_fixture()
  let owner = input.bound.receiver
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 0, 4L)],
    ["where_0"],
    100000,
    10000,
  ).unwrap()
  let completion = execute_generated_sequence(
    generated,
    [],
    compute_test_limits(),
    produced=[input.bound],
  ).unwrap()
  let output = completed_output(completion, Step(0)).unwrap()
  assert_eq(completed_row_count(output), 3)
  assert_true(
    completed_presence_cell(output, 0, 1) is Ok(Present(@admitted.Number(7))),
  )
  assert_true(
    completed_presence_cell(output, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(output, 2, 1) is Ok(Absent))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(bounded, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(cleanup_bounded_binding_rows(bounded).unwrap())
}

///|
test "presence filter keeps retained presence slots charged through cleanup" {
  let (_, execution, _) = presence_filter_fixture()
  let output = presence_filter_complete(execution)
  let peak = execution.state.workspace.peak
  // Three outer rows and two optional cell slots per row remain owned even
  // when a slot contains omission. They are not released at the row boundary.
  assert_true(execution.state.workspace.live >= 3 * (1 + 2))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
  assert_true(completed_output_available(output))
  let (_, limited, input) = presence_filter_fixture(workspace_limit=peak - 1)
  let mut failed = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(limited, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
        failed = true
        break
      }
      _ => fail("presence filter ignored its workspace frontier")
    }
  }
  assert_true(failed)
  assert_true(bounded_binding_rows_cleanup_pending(limited))
  assert_true(limited.state.workspace.live > 0)
  assert_true(producer_read_available(input))
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
  assert_eq(limited.state.workspace.live, 0)
}
