///|
test "explicit retained conversion enables Local and survives source copy loss" {
  let owner = capture_fixture()
  let live = Ref(true)
  let (source, _) = retained_fixture(owner, live)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let original_read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let conversion = prepare_completed_output_import(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(conversion, output_fixture_row(owner, row)).unwrap()
  }
  let output = finish_completed_output_import(conversion).unwrap()
  assert_true(completed_output_same_occurrence(source, output))
  let (unrelated, _) = retained_fixture(owner, Ref(true))
  assert_false(completed_output_same_occurrence(unrelated, output))
  assert_true(completed_has_cell_access(output))
  assert_true(completed_output_matches_port(output, owner, Step(1)))
  assert_eq(
    row_wire_cid(identify_completed_rows(output, row_wire_limits()).unwrap()),
    row_wire_cid(identify_completed_rows(source, row_wire_limits()).unwrap()),
  )
  live.val = false
  assert_false(completed_output_available(source))
  assert_false(completed_output_same_occurrence(source, output))
  assert_true(completed_output_available(output))
  let read = rebind_producer_representation(original_read, output).unwrap()
  assert_true(physical_equal(read.bound.identity, original_read.bound.identity))
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let consumer = execute_fixed_producer_input(
    generated,
    read,
    compute_test_limits(),
  ).unwrap()
  let result = completed_output(consumer, Step(0)).unwrap()
  assert_true(completed_output_matches_inputs(result, [original_read]))
  assert_true(completed_cell(result, 0, 0) is Some(Number(1)))
  assert_true(completed_cell(result, 1, 0) is Some(Number(2)))
  assert_true(finish_completed_output_import(conversion) is Err(Closed))
}

///|
test "ordinary Relation reads retain exact managed consumer bindings" {
  let owner = capture_fixture()
  let live = Ref(true)
  let (source, _) = retained_fixture(owner, live)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let binding = ordinary_relation_input_binding(read)
  assert_true(managed_input_binding_matches_input(binding, receiver, 0))
  assert_true(managed_input_binding_matches_ordinary_read(binding, read))
  assert_eq(
    managed_input_binding_profile_cid(binding),
    managed_execution_profile_cid(selected_managed_execution_profile()),
  )
  let other = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  assert_false(producer_read_same_binding(read, other))
  assert_false(managed_input_binding_matches_ordinary_read(binding, other))
  live.val = false
  assert_false(managed_input_binding_available(binding))
  assert_false(managed_input_binding_matches_ordinary_read(binding, read))
}

///|
test "conversion preserves logical restrictions and completed consumer independence" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let permission = Ref(true)
  let restricted = restrict_completed_output(source, fn() { permission.val })
  let conversion = prepare_completed_output_import(
    restricted,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(conversion, output_fixture_row(owner, row)).unwrap()
  }
  let copy = finish_completed_output_import(conversion).unwrap()
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, copy).unwrap(),
    1000,
    10000,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let completed = execute_fixed_producer_input(
    generated,
    read,
    compute_test_limits(),
  ).unwrap()
  permission.val = false
  assert_false(completed_output_available(copy))
  assert_false(producer_read_available(read))
  let result = completed_output(completed, Step(0)).unwrap()
  assert_true(completed_cell(result, 0, 0) is Some(Number(1)))
}

///|
test "conversion cannot publish different order truncated values or expired input" {
  let owner = capture_fixture()
  for case_ in 0..<4 {
    let live = Ref(true)
    let (source, _) = retained_fixture(owner, live)
    let conversion = prepare_completed_output_import(
      source,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    let rows = match case_ {
      0 => [1, 0]
      1 => [0]
      _ => [0, 1]
    }
    for row in rows {
      append_completed_output_import(conversion, output_fixture_row(owner, row)).unwrap()
    }
    if case_ == 2 {
      live.val = false
    }
    if case_ == 3 {
      cancel_completed_output_import(conversion) |> ignore
    }
    assert_true(finish_completed_output_import(conversion) is Err(_))
    assert_true(conversion.admitted.buffer.rows.is_empty())
    assert_true(finish_completed_output_import(conversion) is Err(Closed))
  }
}

///|
test "representation rebinding rejects equal independent completion and preserves restrictions" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let (other, _) = retained_fixture(owner, Ref(true))
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let permission = Ref(true)
  let original = prepare_producer_read(
    receiver,
    bind_live_completed_input(receiver, 0, owner, source, fn() {
      permission.val
    }).unwrap(),
    1000,
    10000,
  ).unwrap()
  let conversion = prepare_completed_output_import(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in 0..<2 {
    append_completed_output_import(conversion, output_fixture_row(owner, row)).unwrap()
  }
  let copy = finish_completed_output_import(conversion).unwrap()
  assert_true(
    rebind_producer_representation(original, other)
    is Err(ForeignRepresentation),
  )
  let replacement = rebind_producer_representation(original, copy).unwrap()
  assert_true(producer_read_available(replacement))
  assert_true(
    physical_equal(replacement.bound.identity, original.bound.identity),
  )
  permission.val = false
  assert_true(completed_output_available(copy))
  assert_false(producer_read_available(replacement))
  assert_true(
    rebind_producer_representation(original, copy) is Err(ProducerUnavailable),
  )
}

///|
test "conversion discards text without weakening exact row batch capacity" {
  let owner = capture_fixture()
  for cap in [18, 19, 20] {
    let (source, _) = retained_fixture(owner, Ref(true))
    let conversion = prepare_completed_output_import(
      source,
      2,
      stream_value_limits(),
      row_wire_limits(),
      cap,
    ).unwrap()
    append_completed_output_import(conversion, output_fixture_row(owner, 0)).unwrap()
    if cap == 18 {
      assert_true(
        append_completed_output_import(conversion, output_fixture_row(owner, 1))
        is Err(Encoding(Wire(Encoding(@encode.OutputLimit)))),
      )
      assert_true(finish_completed_output_import(conversion) is Err(Closed))
    } else {
      append_completed_output_import(conversion, output_fixture_row(owner, 1)).unwrap()
      let completed = finish_completed_output_import(conversion).unwrap()
      assert_true(completed_output_same_occurrence(source, completed))
      // Internal cell order follows canonical schema references, separately
      // from the authored select declaration [s, n].
      assert_eq(completed_column_name(completed, 0), Some("n"))
      assert_eq(completed_column_name(completed, 1), Some("s"))
      assert_true(completed_cell(completed, 0, 0) is Some(Number(1)))
      assert_true(completed_cell(completed, 1, 0) is Some(Number(2)))
      assert_true(completed_cell(completed, 0, 1) is Some(Text("é")))
      assert_true(completed_cell(completed, 1, 1) is Some(Text("😀")))
      assert_true(finish_completed_output_import(conversion) is Err(Closed))
    }
  }
}
