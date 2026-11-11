///|
test "original input workspace independently accounts overlap and one short" {
  let (retained, execution) = row_original_input_capacity()
  // Eight 2 MB wire/text representations, 100k tree slots at 64 units,
  // 4096 control slots, plus four transient wires for execution.
  assert_eq(retained, 22404096L)
  assert_eq(execution, 30404096L)
  for shortage in 0..<3 {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 22404096L - (if shortage == 1 { 1L } else { 0L }),
      execution_bytes: 30404096L - (if shortage == 2 { 1L } else { 0L }),
    }).unwrap()
    let before = @resources.ledger_usage(ledger)
    let admitted = @resources.reserve_attempt(ledger, 0L, retained, execution)
    if shortage == 0 {
      let reservation = admitted.unwrap()
      @resources.mark_cleanup_pending(ledger, reservation).unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        22404096L,
      )
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        30404096L,
      )
      @resources.settle_reservation(ledger, reservation).unwrap()
      let settled = @resources.ledger_usage(ledger)
      assert_eq(settled.reserved_retention_bytes, 0L)
      assert_eq(settled.reserved_execution_bytes, 0L)
      assert_true(
        @resources.settle_reservation(ledger, reservation)
        is Err(@resources.ClosedReservation),
      )
      assert_eq(@resources.ledger_usage(ledger), settled)
    } else {
      assert_true(
        if shortage == 1 {
          admitted is Err(@resources.RetentionLimit)
        } else {
          admitted is Err(@resources.ExecutionLimit)
        },
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    }
  }
}

///|
test "original input cleanup revokes reads before sliced backing reclamation" {
  let (owner, schema) = row_presence_owner()
  let input = @execution.prepare_bounded_admitted_input(
    owner,
    0,
    3,
    row_presence_retention(),
  ).unwrap()
  for wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
    row_presence_append(input, schema, wire).unwrap()
  }
  let captured = @execution.finish_admitted_input(input).unwrap()
  let live = Ref(true)
  let read = @execution.prepare_supplied_relation_read(owner, 0, captured, () => {
    live.val
  }).unwrap()
  let restored : RowRestoredOriginalInput = { input, read, live, }
  assert_true(restored_row_original_read(restored) is Some(_))
  let work = @execution.admitted_input_work(input)
  assert_false(close_restored_row_original_input(restored, 1))
  assert_eq(@execution.captured_row_count(captured), 3)
  assert_true(restored_row_original_read(restored) is None)
  assert_false(@execution.supplied_relation_read_available(read))
  assert_true(@execution.supplied_relation_read_cell(read, 0, 0) is None)
  let mut polls = 1
  while !close_restored_row_original_input(restored, 1) {
    polls += 1
    assert_true(polls < 10)
  }
  polls += 1
  // Three rows, two owned cell references and one row slot per row.
  assert_eq(polls, 9)
  assert_eq(@execution.captured_row_count(captured), 0)
  assert_eq(
    @execution.admitted_input_work(input),
    work,
    msg="cleanup reports no new compute work",
  )
  assert_true(close_restored_row_original_input(restored, 1))
  assert_eq(@execution.admitted_input_work(input), work)
}

///|
test "shared original snapshot engine preserves omitted and explicit null cells" {
  let (owner, schema) = row_presence_owner()
  let input = @execution.prepare_bounded_admitted_input(
    owner,
    0,
    3,
    row_presence_retention(),
  ).unwrap()
  let expected = ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"]
  for wire in expected {
    row_presence_append(input, schema, wire).unwrap()
  }
  let captured = @execution.finish_admitted_input(input).unwrap()
  let live = Ref(true)
  let read = @execution.prepare_supplied_relation_read(owner, 0, captured, () => {
    live.val
  }).unwrap()
  let (schema_cid, rows_cid, rows) = row_original_capture_export_facts(
    export_row_original_read(read).unwrap(),
  )
  assert_eq(rows, expected)
  live.val = false
  discard_failed_original_input(input)
  let available = Ref(true)
  let restored = restore_original_read_with_limits(
    owner,
    0,
    schema_cid,
    rows_cid,
    rows,
    100,
    {
      max_nodes: 100000,
      max_text_bytes: 2000000,
      max_depth: 64,
      max_work: 20000000,
    },
    original_capture_wire_limits(),
    original_capture_schema_limits(),
    () => available.val,
  ).unwrap()
  let restored_read = restored_row_original_read(restored).unwrap()
  assert_eq(
    row_original_capture_export_facts(
      export_row_original_read(restored_read).unwrap(),
    ),
    (schema_cid, rows_cid, expected),
  )
  available.val = false
  assert_true(restored_row_original_read(restored) is None)
  let mut closed = false
  for _ in 0..<20 {
    if close_restored_row_original_input(restored, 1) {
      closed = true
      break
    }
  }
  assert_true(closed)
  assert_true(
    restore_original_read_with_limits(
      owner,
      0,
      schema_cid,
      rows_cid,
      ["{\"id\":1,\"p\":null}"],
      100,
      row_presence_retention(),
      original_capture_wire_limits(),
      original_capture_schema_limits(),
      () => true,
    )
    is Err(InvalidBinding),
  )
}
