///|
fn buffered_bridge_reclamation_fixture() -> (
  ManagedProducerBridge[Int],
  ManagedCompletedOutput[Int],
) raise {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), row_count=24)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\",\"s\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let bridge = prepare_managed_producer_bridge(
    input,
    24,
    stream_value_limits(),
    1000,
    10000,
    deferred_reclamation=true,
  ).unwrap()
  for row in 0..<24 {
    let text = "{\"n\":" +
      (row + 1).to_string() +
      ",\"s\":" +
      (if row == 0 { "\"é\"" } else { "\"😀\"" }) +
      "}"
    append_managed_producer_bridge_wire(
      bridge,
      text,
      retained_row_test_limits(),
    ).unwrap()
  }
  (bridge, source)
}

///|
fn private_import_row_entries(buffer : AdmittedRowBuffer) -> Int {
  buffer.rows.fold(init=buffer.rows.length(), (count, row) => {
    count + row.length()
  }) +
  buffer.presence_rows.fold(init=buffer.presence_rows.length(), (count, row) => {
    count + row.cells.length()
  })
}

///|
test "bridge cancellation retains private rows across exact cleanup slices" {
  let (bridge, source) = buffered_bridge_reclamation_fixture()
  let work = bridge.admitted.buffer.budget.work
  close_managed_producer_bridge(bridge)
  assert_false(bridge.live.val)
  assert_eq(private_import_row_entries(bridge.admitted.buffer), 72)
  assert_false(advance_close_managed_producer_bridge(bridge, 0))
  assert_eq(private_import_row_entries(bridge.admitted.buffer), 72)
  assert_false(advance_close_managed_producer_bridge(bridge, 64))
  assert_eq(private_import_row_entries(bridge.admitted.buffer), 8)
  assert_true(managed_completed_output_available(source))
  assert_true(advance_close_managed_producer_bridge(bridge, 64))
  assert_eq(bridge.admitted.buffer.rows.capacity(), 0)
  assert_eq(bridge.admitted.buffer.budget.work, work)
  assert_true(advance_close_managed_producer_bridge(bridge, 64))
  assert_true(
    finish_managed_producer_bridge(bridge, 1000, 10000) is Err(Closed),
  )
}

///|
test "bridge append failure retains rows and producer until sliced cleanup" {
  let (bridge, source) = buffered_bridge_reclamation_fixture()
  assert_true(
    append_managed_producer_bridge_wire(
      bridge,
      "{\"n\":\"wrong type\",\"s\":\"text\"}",
      retained_row_test_limits(),
    )
    is Err(Wire(_)),
  )
  assert_eq(private_import_row_entries(bridge.admitted.buffer), 72)
  let work = bridge.admitted.buffer.budget.work
  assert_false(advance_close_managed_producer_bridge(bridge, 64))
  assert_true(advance_close_managed_producer_bridge(bridge, 64))
  assert_eq(bridge.admitted.buffer.budget.work, work)
  assert_true(managed_completed_output_available(source))
}

///|
test "failed bridge completion reclaims sealed unaccepted rows" {
  let (prepared, source) = buffered_bridge_reclamation_fixture()
  // Reject only the existing trusted handoff boundary, after admission seals.
  let rejected_port = { ..prepared.port, verify: (_ : Unit) => None, }
  let bridge = { ..prepared, port: rejected_port, }
  assert_true(
    finish_managed_producer_bridge(bridge, 1000, 10000)
    is Err(Completion(Unverified)),
  )
  assert_true(bridge.finished)
  assert_false(bridge.handed_off)
  assert_true(bridge.rows.val is Some(_))
  assert_false(bridge.admitted.buffer.open)
  assert_false(advance_close_managed_producer_bridge(bridge, 64))
  assert_eq(private_import_row_entries(bridge.admitted.buffer), 8)
  assert_true(bridge.rows.val is None)
  assert_true(advance_close_managed_producer_bridge(bridge, 64))
  assert_true(managed_completed_output_available(source))
}

///|
test "bridge handoff revocation never clears transferred immutable rows" {
  let (bridge, source) = buffered_bridge_reclamation_fixture()
  let read = finish_managed_producer_bridge(bridge, 1000, 10000).unwrap()
  assert_true(bridge.handed_off)
  assert_true(producer_read_cell(read, 23, 0) is Some(Number(24)))
  assert_true(advance_close_managed_producer_bridge(bridge, 1))
  assert_false(producer_read_available(read))
  assert_eq(private_import_row_entries(bridge.admitted.buffer), 72)
  let rows = bridge.rows.val.unwrap()
  assert_true(admitted_output_cell(rows, 23, 0) is Some(Number(24)))
  assert_true(managed_completed_output_available(source))
}

///|
fn buffered_completed_import_fixture(
  reverse? : Bool = false,
) -> (CompletedOutputImport, CompletedOutput) raise {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true), row_count=24)
  let importing = prepare_completed_output_import(
    source,
    24,
    stream_value_limits(),
    row_wire_limits(),
    64,
    deferred_reclamation=true,
  ).unwrap()
  for row in 0..<24 {
    append_completed_output_import(
      importing,
      output_fixture_row(owner, if reverse { 23 - row } else { row }),
    ).unwrap()
  }
  (importing, source)
}

///|
test "completed import cancellation yields between private cells without new work" {
  let (importing, source) = buffered_completed_import_fixture()
  let work = importing.admitted.buffer.budget.work
  assert_true(cancel_completed_output_import(importing))
  assert_eq(private_import_row_entries(importing.admitted.buffer), 72)
  assert_false(advance_cancel_completed_output_import(importing, 0))
  let mut polls = 0
  for _ in 0..<72 {
    polls += 1
    let done = advance_cancel_completed_output_import(importing, 1)
    assert_eq(private_import_row_entries(importing.admitted.buffer), 72 - polls)
    assert_eq(done, polls == 72)
  }
  assert_eq(importing.admitted.buffer.budget.work, work)
  assert_eq(importing.admitted.buffer.rows.capacity(), 0)
  assert_eq(importing.stream.buffer.rows.capacity(), 0)
  assert_true(completed_output_available(source))
  assert_true(finish_completed_output_import(importing) is Err(Closed))
  assert_true(advance_cancel_completed_output_import(importing, 1))
}

///|
test "failed import identity verification retains rows until sliced reclamation" {
  let (importing, source) = buffered_completed_import_fixture(reverse=true)
  assert_true(
    finish_completed_output_import(importing) is Err(IdentityMismatch),
  )
  assert_false(importing.completed)
  assert_eq(private_import_row_entries(importing.admitted.buffer), 72)
  assert_false(advance_cancel_completed_output_import(importing, 64))
  assert_eq(private_import_row_entries(importing.admitted.buffer), 8)
  assert_true(advance_cancel_completed_output_import(importing, 64))
  assert_true(completed_output_available(source))
}

///|
test "completed conversion rows survive cleanup while active readers delay mutation" {
  let (importing, source) = buffered_completed_import_fixture()
  let output = finish_completed_output_import(importing).unwrap()
  assert_true(importing.completed)
  assert_true(advance_cancel_completed_output_import(importing, 1))
  assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
  assert_true(completed_cell(output, 23, 0) is Some(Number(24)))
  assert_eq(private_import_row_entries(importing.admitted.buffer), 72)
  assert_true(completed_output_available(source))
  let (pending, _) = buffered_completed_import_fixture()
  pending.reading = true
  assert_false(advance_cancel_completed_output_import(pending, 64))
  assert_false(pending.open)
  assert_eq(private_import_row_entries(pending.admitted.buffer), 72)
  pending.reading = false
  assert_false(advance_cancel_completed_output_import(pending, 64))
  assert_eq(private_import_row_entries(pending.admitted.buffer), 8)
  assert_true(advance_cancel_completed_output_import(pending, 64))
}
