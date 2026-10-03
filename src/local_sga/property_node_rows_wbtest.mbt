///|
fn property_node_rows_fixture(
  max_rows : Int,
  max_work : Int,
  started : Ref[Int],
) -> PropertyNodeRowsExecution {
  let (plan, storage) = property_node_row_fixture()
  start_property_node_rows_read(
    @storage.node_count(storage),
    max_rows,
    max_work,
    () => true,
    (node, remaining) => {
      started.val += 1
      start_property_node_row_read(
        plan,
        node,
        () => true,
        () => @storage.node_definition_index(storage, node),
        () => @storage.node_identity(storage, node),
        property => @storage.node_property(storage, node, property),
        property_node_row_values(),
        remaining,
        100,
      )
    },
  ).unwrap()
}

///|
test "bounded property Graph cursor preserves row presence and ack ownership" {
  let started = Ref(0)
  let cursor = property_node_rows_fixture(3, 500, started)
  let expected_suffix = [
    "\"p\":null}", "\"key_types\":[{\"kind\":\"number\"}]}}", "\"p\":7}",
  ]
  let mut rows = 0
  let mut complete = false
  for _ in 0..<500 {
    match advance_property_node_rows(cursor, 1).unwrap() {
      PropertyNodeRowsContinue(work~) => assert_true(work <= 1L)
      PropertyNodeRowsRow(row, work~) => {
        assert_true(work <= 1L)
        let writer = @encode.writer(1000, 100, 12)
        @execution.emit_conditional_row(row, writer)
        let encoded = @encode.finish(writer)
        assert_true(encoded.has_suffix(expected_suffix[rows]))
        assert_true(advance_property_node_rows(cursor, 1) is Err(RowPending))
        assert_eq(started.val, rows + 1)
        assert_true(acknowledge_property_node_rows_row(cursor, row).unwrap())
        rows += 1
      }
      PropertyNodeRowsComplete(work~) => {
        assert_true(work <= 1L)
        complete = true
        break
      }
      PropertyNodeRowsFailed(WorkLimit, ..) => fail("cursor work limit")
      PropertyNodeRowsFailed(Row(Row(Limit)), ..) =>
        fail("row work or value limit")
      PropertyNodeRowsFailed(Row(InputUnavailable), ..) =>
        fail("row input unavailable")
      PropertyNodeRowsFailed(_, ..) => fail("property Graph cursor failed")
      _ => fail("property Graph cursor stopped")
    }
  }
  assert_true(complete)
  assert_eq(rows, 3)
  assert_eq(started.val, 3)
  assert_true(cleanup_property_node_rows(cursor).unwrap())
  assert_true(cursor.available is None)
  assert_true(cursor.start_row is None)
}

///|
test "bounded property Graph cursor enforces row ceiling before another read" {
  let started = Ref(0)
  let cursor = property_node_rows_fixture(2, 500, started)
  let mut rows = 0
  let mut limited = false
  for _ in 0..<500 {
    match advance_property_node_rows(cursor, 1).unwrap() {
      PropertyNodeRowsContinue(..) => ()
      PropertyNodeRowsRow(row, ..) => {
        assert_true(acknowledge_property_node_rows_row(cursor, row).unwrap())
        rows += 1
      }
      PropertyNodeRowsFailed(RowLimit, ..) => {
        limited = true
        break
      }
      PropertyNodeRowsFailed(WorkLimit, ..) => fail("cursor work limit")
      PropertyNodeRowsFailed(Row(Row(Limit)), ..) =>
        fail("row work or value limit")
      PropertyNodeRowsFailed(_, ..) => fail("unexpected Graph cursor failure")
      _ => fail("unexpected Graph cursor result")
    }
  }
  assert_true(limited)
  assert_eq(rows, 2)
  assert_eq(started.val, 2)
  assert_true(cleanup_property_node_rows(cursor).unwrap())
  let zero = property_node_rows_fixture(3, 0, Ref(0))
  assert_true(
    advance_property_node_rows(zero, 1).unwrap()
    is PropertyNodeRowsFailed(WorkLimit, ..),
  )
  assert_true(cleanup_property_node_rows(zero).unwrap())
  let one = property_node_rows_fixture(3, 1, Ref(0))
  assert_true(
    advance_property_node_rows(one, 1).unwrap()
    is PropertyNodeRowsContinue(work=1L),
  )
  assert_true(
    advance_property_node_rows(one, 1).unwrap()
    is PropertyNodeRowsFailed(WorkLimit, work=0L),
  )
  assert_true(cleanup_property_node_rows(one).unwrap())
}

///|
test "bounded property Graph cursor stops after progress and retains cleanup" {
  let started = Ref(0)
  let cursor = property_node_rows_fixture(3, 500, started)
  let mut first = None
  for _ in 0..<200 {
    match advance_property_node_rows(cursor, 1).unwrap() {
      PropertyNodeRowsContinue(..) => ()
      PropertyNodeRowsRow(row, ..) => {
        first = Some(row)
        break
      }
      PropertyNodeRowsFailed(WorkLimit, ..) => fail("cursor work limit")
      PropertyNodeRowsFailed(Row(Row(Limit)), ..) =>
        fail("row work or value limit")
      PropertyNodeRowsFailed(_, ..) => fail("first Graph row failed")
      _ => fail("first Graph row was not produced")
    }
  }
  assert_true(
    acknowledge_property_node_rows_row(cursor, first.unwrap()).unwrap(),
  )
  assert_true(
    advance_property_node_rows(cursor, 1).unwrap()
    is PropertyNodeRowsContinue(work=1L),
  )
  assert_eq(started.val, 2)
  assert_true(cancel_property_node_rows(cursor))
  assert_true(
    acknowledge_property_node_rows_row(cursor, first.unwrap()) is Err(Closed),
  )
  assert_true(
    advance_property_node_rows(cursor, 1).unwrap()
    is PropertyNodeRowsStopped(work=0L),
  )
  assert_true(cleanup_property_node_rows(cursor).unwrap())
  assert_true(cleanup_property_node_rows(cursor).unwrap())
  assert_true(cursor.available is None)
  assert_true(cursor.start_row is None)
  assert_true(cursor.active is None)
}

///|
test "bounded property Graph cursor revocation stops its active child before cleanup" {
  let (plan, storage) = property_node_row_fixture()
  let live = Ref(true)
  let cursor = start_property_node_rows_read(
    @storage.node_count(storage),
    3,
    500,
    () => live.val,
    (node, remaining) => {
      start_property_node_row_read(
        plan,
        node,
        () => live.val,
        () => @storage.node_definition_index(storage, node),
        () => @storage.node_identity(storage, node),
        property => @storage.node_property(storage, node, property),
        property_node_row_values(),
        remaining,
        100,
      )
    },
  ).unwrap()
  assert_true(
    advance_property_node_rows(cursor, 1).unwrap()
    is PropertyNodeRowsContinue(work=1L),
  )
  live.val = false
  assert_true(
    advance_property_node_rows(cursor, 1).unwrap()
    is PropertyNodeRowsFailed(InputUnavailable, work=0L),
  )
  assert_true(cleanup_property_node_rows(cursor).unwrap())
  assert_true(cursor.active is None)
  assert_true(cursor.available is None)
}

///|
test "bounded property Graph cursor keeps an unacknowledged row private on cancel" {
  let cursor = property_node_rows_fixture(3, 500, Ref(0))
  let mut pending = None
  for _ in 0..<200 {
    match advance_property_node_rows(cursor, 1).unwrap() {
      PropertyNodeRowsContinue(..) => ()
      PropertyNodeRowsRow(row, ..) => {
        pending = Some(row)
        break
      }
      _ => fail("unacknowledged Graph row was not produced")
    }
  }
  assert_true(pending is Some(_))
  assert_true(cancel_property_node_rows(cursor))
  assert_true(
    advance_property_node_rows(cursor, 1).unwrap()
    is PropertyNodeRowsStopped(work=0L),
  )
  assert_true(cleanup_property_node_rows(cursor).unwrap())
  assert_true(cursor.pending is None)
  assert_true(cursor.active is None)
  assert_true(cursor.available is None)
  assert_true(
    acknowledge_property_node_rows_row(cursor, pending.unwrap()) is Err(Closed),
  )
}

///|
test "empty property Graph cursor completes without starting a row" {
  let started = Ref(0)
  let cursor = start_property_node_rows_read(0, 0, 0, () => true, (_, _) => {
    started.val += 1
    Err(InvalidNode)
  }).unwrap()
  assert_true(
    advance_property_node_rows(cursor, 1).unwrap()
    is PropertyNodeRowsComplete(work=0L),
  )
  assert_eq(started.val, 0)
  assert_true(cleanup_property_node_rows(cursor).unwrap())
}
