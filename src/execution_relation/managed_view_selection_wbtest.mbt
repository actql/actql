///|
test "managed selected output carries an independent index to the next consumer" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live, index_cells=4)
  let receiver = typed_receiver(
    owner, "[{\"take\":1},{\"select\":[\"n\",\"s\"]}]",
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0), row_kernel(receiver, 1)],
    1000,
    10000,
    100,
  ).unwrap()
  let rows = [0]
  let selection = prepare_managed_view_selection(plan, rows, 2, 100).unwrap()
  rows[0] = 1
  assert_eq(managed_view_selection_row(selection, 0), Some(0))
  assert_false(
    physical_equal(
      selection.index.cells,
      source.material.receipt.row_measurements.unwrap().cells,
    ),
  )
  let stream = prepare_managed_output_values(
    receiver,
    Step(1),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(stream, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 8, 5L, fn() { true }))).unwrap()
  let token = Ref(())
  let port = prepare_managed_selected_view_output_port(selection, stream, (
    proof : Ref[Unit],
  ) => physical_equal(proof, token)).unwrap()
  assert_true(
    prepare_managed_selected_view_output_port(selection, stream, (_ : Ref[Unit]) => {
      true
    })
    is Err(Closed),
  )
  let receipt = finish_managed_view_output(port, token).unwrap()
  assert_true(port.index is None)
  assert_false(cancel_managed_view_output_port(port))
  assert_eq(managed_output_value_measurement(receipt), (3, 5, 2))
  assert_eq(managed_output_measurement_index_cells(receipt), Some(2))
  let material = retain_managed_output(retention, receipt).unwrap()
  let generated = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let completion = prepare_managed_completion_port(
    managed_test_profile(),
    generated,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(material),
    managed_inputs=[input],
  ).unwrap()
  let output = complete_managed_output(completion, ()).unwrap()
  live.val = false
  assert_true(managed_completed_output_available(output))
  let next = typed_receiver(receiver, "[{\"select\":[\"s\"]}]")
  let next_input = prepare_managed_producer_read(
    next, 0, receiver, output, 1000, 10000,
  ).unwrap()
  let next_plan = prepare_managed_view_plan(
    next_input,
    [row_kernel(next, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  for _ in 0..<2 {
    let facts = managed_view_selection_measurements(next_plan, [0], 100).unwrap()[0].unwrap()
    assert_eq(facts.bytes, 4)
    assert_eq(facts.nodes, 1)
  }
}

///|
test "managed selected index transfer is bounded and cannot manufacture computed facts" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(owner, "[{\"derive\":{\"new\":\"n + 1\"}}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  assert_true(
    prepare_managed_view_selection(plan, [0, 1], 6, 100)
    is Err(UnsupportedColumns),
  )
  assert_true(
    prepare_managed_view_selection(plan, [0, 1], 5, 100) is Err(Limit),
  )
  assert_true(prepare_managed_view_selection(plan, [0, 1], 6, 1) is Err(Limit))
}

///|
test "failed selected port installation drops only the consumed copied index" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\",\"s\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  let selection = prepare_managed_view_selection(plan, [0, 1], 4, 1000).unwrap()
  let stream = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  cancel_managed_output_values(stream) |> ignore
  assert_true(
    prepare_managed_selected_view_output_port(selection, stream, (_ : Unit) => {
      true
    })
    is Err(Closed),
  )
  assert_true(selection.claimed)
  assert_eq(selection.index.count, 0)
  assert_eq(
    managed_output_measurement_index_cells(source.material.receipt),
    Some(4),
  )
}

///|
test "reentrant selected finish does not discard the active verification index" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\",\"s\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  let selection = prepare_managed_view_selection(plan, [0, 1], 4, 1000).unwrap()
  let stream = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let reenter : Ref[(() -> Bool)?] = Ref(None)
  let port = prepare_managed_selected_view_output_port(selection, stream, (
    _ : Unit,
  ) => reenter.val.unwrap()()).unwrap()
  reenter.val = Some(fn() {
    finish_managed_view_output(port, ()) is Err(Closed) &&
    selection.index.count == 4
  })
  let receipt = finish_managed_view_output(port, ()).unwrap()
  assert_eq(managed_output_measurement_index_cells(receipt), Some(4))
  assert_false(cancel_managed_view_output_port(port))
  assert_eq(managed_output_measurement_index_cells(receipt), Some(4))
  reenter.val = None
}

///|
test "managed selected index cannot publish after failed verification or revocation" {
  for mode in 0..<5 {
    let owner = capture_fixture()
    let live = Ref(true)
    let source = managed_read_fixture(owner, live, index_cells=4)
    let receiver = typed_receiver(owner, "[{\"take\":1},{\"select\":[\"s\"]}]")
    let input = prepare_managed_producer_read(
      receiver, 0, owner, source, 1000, 10000,
    ).unwrap()
    let plan = prepare_managed_view_plan(
      input,
      [row_kernel(receiver, 0), row_kernel(receiver, 1)],
      1000,
      10000,
      100,
    ).unwrap()
    let selection = prepare_managed_view_selection(plan, [0], 1, 100).unwrap()
    let stream = prepare_managed_output_values(
      receiver,
      Step(1),
      2,
      stream_value_limits(),
      100,
      managed_test_measure_limits(),
    ).unwrap()
    let port = prepare_managed_selected_view_output_port(selection, stream, (
      _ : Unit,
    ) => mode != 0).unwrap()
    if mode == 1 {
      live.val = false
    }
    if mode == 2 {
      cancel_managed_view_output_port(port) |> ignore
    }
    if mode == 3 {
      cancel_managed_output_values(stream) |> ignore
    }
    if mode == 4 {
      cancel_managed_output_values(stream) |> ignore
      assert_false(cancel_managed_view_output_port(port))
    }
    let result = finish_managed_view_output(port, ())
    match mode {
      0 => assert_true(result is Err(Unverified))
      1 => assert_true(result is Err(ForeignBinding))
      _ => assert_true(result is Err(Closed))
    }
    assert_true(finish_managed_output_values(stream) is Err(Closed))
    assert_true(
      prepare_managed_selected_view_output_port(selection, stream, (_ : Unit) => {
        true
      })
      is Err(Closed),
    )
    assert_true(stream.row_measurements is None)
    assert_true(port.index is None)
    assert_eq(selection.index.count, 0)
    assert_eq(
      managed_output_measurement_index_cells(source.material.receipt),
      Some(4),
    )
  }
}
