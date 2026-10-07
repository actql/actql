///|
test "Values output name admission starts before its one-short resume refusal" {
  // values_0 twice (16), id (2), label (5): exactly 23 UTF-8 bytes.
  let (_, started) = bounded_values_fixture(name_bytes=22)
  assert_true(started is Ok(_))
  let execution = started.unwrap()
  let mut refused = false
  for _ in 0..<1000 {
    match advance_bounded_values(execution, 1).unwrap() {
      BoundedValuesContinue(..) => ()
      BoundedValuesFailed(Completion(Limit), ..) => {
        refused = true
        break
      }
      _ => fail("expected Values completion name limit")
    }
  }
  assert_true(refused)
  assert_eq(execution.state.row, 0)
  assert_true(execution.state.rows.val is None)
  assert_false(execution.accepted.val)
  assert_true(cleanup_bounded_values(execution).unwrap())
  assert_false(cleanup_bounded_values(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
}

///|
test "Append output name admission starts before its one-short resume refusal" {
  // append_0 twice (16), id (2): exactly 18 UTF-8 bytes.
  let (_, started, reads) = bounded_append_fixture(name_bytes=17)
  assert_true(started is Ok(_))
  let execution = started.unwrap()
  let mut refused = false
  for _ in 0..<1000 {
    match advance_bounded_append(execution, 1).unwrap() {
      BoundedAppendContinue(..) => ()
      BoundedAppendFailed(Completion(Limit), ..) => {
        refused = true
        break
      }
      _ => fail("expected Append completion name limit")
    }
  }
  assert_true(refused)
  assert_eq(execution.state.left_row, 0)
  assert_true(execution.state.input_scan.frames.is_empty())
  assert_true(reads.all(producer_read_available))
  assert_true(cleanup_binary_output_fixture(Append(execution)))
  assert_false(cleanup_binary_output_fixture(Append(execution)))
}

///|
test "Set output name admission starts before its one-short resume refusal" {
  // except_0 twice plus id: 18 bytes; intersect_0 twice plus id: 24.
  for (operation, exact) in [("except", 18), ("intersect", 24)] {
    for duplicates in ["all", "distinct"] {
      let (_, started, reads) = bounded_set_fixture(
        operation~,
        duplicates~,
        name_bytes=exact - 1,
      )
      assert_true(started is Ok(_))
      let execution = started.unwrap()
      let mut refused = false
      for _ in 0..<1000 {
        match advance_bounded_set(execution, 1).unwrap() {
          BoundedSetContinue(..) => ()
          BoundedSetFailed(Completion(Limit), ..) => {
            refused = true
            break
          }
          _ => fail("expected Set completion name limit")
        }
      }
      assert_true(refused)
      assert_true(execution.state.seed.is_empty())
      assert_true(execution.state.input_scan.frames.is_empty())
      assert_true(reads.all(producer_read_available))
      assert_true(cleanup_binary_output_fixture(Set(execution)))
      assert_false(cleanup_binary_output_fixture(Set(execution)))
    }
  }
}

///|
test "Cross Join output name admission starts before its one-short resume refusal" {
  // cross_join_0 twice (24), id (2), tag (3): exactly 29 UTF-8 bytes.
  let (_, started, reads) = bounded_cross_fixture(name_bytes=28)
  assert_true(started is Ok(_))
  let execution = started.unwrap()
  let mut refused = false
  for _ in 0..<1000 {
    match advance_bounded_cross_join(execution, 1).unwrap() {
      BoundedCrossJoinContinue(..) => ()
      BoundedCrossJoinFailed(Completion(Limit), ..) => {
        refused = true
        break
      }
      _ => fail("expected Cross Join completion name limit")
    }
  }
  assert_true(refused)
  assert_eq(execution.state.emitted, 0)
  assert_true(execution.state.input_scan.frames.is_empty())
  assert_true(reads.all(producer_read_available))
  assert_true(cleanup_binary_output_fixture(Cross(execution)))
  assert_false(cleanup_binary_output_fixture(Cross(execution)))
}

///|
fn binary_port_fixture(
  kind : Int,
) -> (@bounded.Control, BinaryOutputFixture, Array[ProducerRead]) raise {
  match kind {
    0 => {
      let (control, started, reads) = bounded_append_fixture(name_bytes=18)
      (control, Append(started.unwrap()), reads)
    }
    2 => {
      let (control, started, reads) = bounded_cross_fixture(name_bytes=29)
      (control, Cross(started.unwrap()), reads)
    }
    _ => {
      let intersect = kind == 3 || kind == 5
      let (control, started, reads) = bounded_set_fixture(
        operation=if intersect { "intersect" } else { "except" },
        duplicates=if kind >= 4 { "distinct" } else { "all" },
        left_rows="[{\"id\":1},{\"id\":1},{\"id\":2}]",
        right_rows="[{\"id\":1}]",
        name_bytes=if intersect { 24 } else { 18 },
      )
      (control, Set(started.unwrap()), reads)
    }
  }
}

///|
fn binary_port_cursor(value : BinaryOutputFixture) -> TrustedOutputPreparation? {
  match value {
    Append(value) => value.state.port_preparation
    Set(value) => value.state.port_preparation
    Cross(value) => value.state.port_preparation
  }
}

///|
fn binary_port_usage(value : BinaryOutputFixture) -> (Int, Int, Int) {
  match value {
    Append(value) =>
      (
        value.state.control.remaining,
        value.state.workspace.live,
        value.state.workspace.peak,
      )
    Set(value) =>
      (
        value.state.control.remaining,
        value.state.workspace.live,
        value.state.workspace.peak,
      )
    Cross(value) =>
      (
        value.state.control.remaining,
        value.state.workspace.live,
        value.state.workspace.peak,
      )
  }
}

///|
fn advance_binary_port_fixture(
  value : BinaryOutputFixture,
  quantum : Int,
) -> (CompletedOutput?, Int64) raise {
  match value {
    Append(value) =>
      match advance_bounded_append(value, quantum).unwrap() {
        BoundedAppendContinue(work~, ..) => (None, work)
        BoundedAppendComplete(output, work~, ..) => (Some(output), work)
        _ => fail("Append port preparation or execution failed")
      }
    Set(value) =>
      match advance_bounded_set(value, quantum).unwrap() {
        BoundedSetContinue(work~, ..) => (None, work)
        BoundedSetComplete(output, work~, ..) => (Some(output), work)
        _ => fail("Set port preparation or execution failed")
      }
    Cross(value) =>
      match advance_bounded_cross_join(value, quantum).unwrap() {
        BoundedCrossJoinContinue(work~, ..) => (None, work)
        BoundedCrossJoinComplete(output, work~, ..) => (Some(output), work)
        _ => fail("Cross Join port preparation or execution failed")
      }
  }
}

///|
/// Keep earlier input-admission stop fixtures at their original boundary.
fn finish_binary_port_fixture(value : BinaryOutputFixture) -> Int64 raise {
  let mut work = 0L
  for _ in 0..<1000 {
    if binary_port_cursor(value) is None {
      return work
    }
    let (output, next_work) = advance_binary_port_fixture(value, 1)
    assert_true(output is None)
    assert_eq(next_work, work + 1L)
    work = next_work
  }
  fail("completion port did not prepare within finite metadata steps")
}

///|
test "binary completion names preserve exact bytes logical charges and order across quanta" {
  for kind in 0..<6 {
    let mut usage : (Int, Int, Int)? = None
    let mut total_work : Int64? = None
    for quantum in [1, 7, 256] {
      let (_, execution, reads) = binary_port_fixture(kind)
      let cursor = binary_port_cursor(execution).unwrap()
      assert_eq(cursor.offset, 0)
      let mut output : CompletedOutput? = None
      let mut work = 0L
      for _ in 0..<2000 {
        let (next_output, next_work) = advance_binary_port_fixture(
          execution, quantum,
        )
        assert_true(next_work >= work && next_work - work <= quantum.to_int64())
        work = next_work
        if next_output is Some(_) {
          output = next_output
          break
        }
      }
      let output = output.unwrap()
      let ids = match kind {
        0 => [1.0, 2.0, 3.0]
        1 => [1.0, 2.0]
        2 => [1.0, 1.0, 2.0, 2.0]
        4 => [2.0]
        _ => [1.0]
      }
      assert_eq(completed_row_count(output), ids.length())
      assert_eq(completed_column_name(output, 0), Some("id"))
      for row, id in ids {
        assert_true(
          completed_cell(output, row, 0) is Some(Number(value)) && value == id,
        )
        if kind == 2 {
          let tag = if row % 2 == 0 { "a" } else { "b" }
          assert_true(
            completed_cell(output, row, 1) is Some(Text(value)) && value == tag,
          )
        }
      }
      if usage is Some(expected) {
        assert_eq(binary_port_usage(execution), expected)
      }
      if total_work is Some(expected) {
        assert_eq(work, expected)
      }
      usage = Some(binary_port_usage(execution))
      total_work = Some(work)
      assert_eq(cursor.bytes, 0)
      assert_true(cursor.closed)
      assert_true(binary_port_cursor(execution) is None)
      assert_true(reads.all(producer_read_available))
      assert_true(cleanup_binary_output_fixture(execution))
      assert_false(cleanup_binary_output_fixture(execution))
      cancel_trusted_output_preparation(cursor)
      assert_eq(completed_column_name(output, 0), Some("id"))
      assert_false(cursor.names.is_empty())
      assert_true(reads.all(producer_read_available))
    }
  }
}

///|
test "binary completion port stops within each name phase before input scan" {
  for kind in 0..<6 {
    for phase in 0..<4 {
      let (control, execution, reads) = binary_port_fixture(kind)
      let cursor = binary_port_cursor(execution).unwrap()
      let mut reached = false
      for _ in 0..<1000 {
        if cursor.phase == phase && cursor.offset > 0 {
          reached = true
          break
        }
        assert_true(advance_binary_output_fixture(execution) is Continue)
      }
      assert_true(reached)
      let usage = binary_port_usage(execution)
      let pending_names = cursor.names.length()
      assert_true(reads.all(producer_read_available))
      assert_true(@bounded.request_cancel(control))
      assert_false(cursor.closed)
      assert_true(advance_binary_output_fixture(execution) is Stopped)
      assert_false(cursor.closed)
      assert_eq(cursor.names.length(), pending_names)
      assert_eq(binary_port_usage(execution), usage)
      assert_true(binary_port_cursor(execution) is Some(_))
      assert_true(cleanup_binary_output_fixture(execution))
      assert_false(cleanup_binary_output_fixture(execution))
      assert_true(cursor.closed)
      assert_true(cursor.names.is_empty())
      assert_true(binary_port_cursor(execution) is None)
      assert_true(reads.all(producer_read_available))
    }
  }
}

///|
test "Values completion Unicode admission preserves exact bytes and logical charges" {
  // values_0 twice (16), id (2), and 256 ASCII plus emoji (260): 278.
  let name = "x".repeat(256) + "😀"
  let mut usage : (Int, Int)? = None
  let mut total_work : Int64? = None
  for quantum in [1, 7, 256] {
    let (_, started) = bounded_values_fixture(
      max_work=10000,
      max_entries=100,
      name_bytes=278,
      label_name=name,
    )
    let execution = started.unwrap()
    let cursor = execution.state.port_preparation.unwrap()
    assert_eq(cursor.offset, 0)
    assert_true(execution.state.port is None)
    let mut output : CompletedOutput? = None
    let mut work = 0L
    for _ in 0..<5000 {
      let next_work = match
        advance_bounded_values(execution, quantum).unwrap() {
        BoundedValuesContinue(work~, ..) => work
        BoundedValuesComplete(value, work~, ..) => {
          output = Some(value)
          work
        }
        BoundedValuesFailed(Rows(RowLimit), ..) =>
          fail("Values workspace limit")
        BoundedValuesFailed(InputLimit, ..) => fail("Values input limit")
        BoundedValuesFailed(Completion(Limit), ..) => fail("Values name limit")
        _ => fail("exact Values name admission failed")
      }
      assert_true(next_work >= work && next_work - work <= quantum.to_int64())
      work = next_work
      if output is Some(_) {
        break
      }
    }
    let output = output.unwrap()
    assert_eq(completed_row_count(output), 2)
    assert_eq(completed_column_name(output, 0), Some("id"))
    assert_eq(completed_column_name(output, 1), Some(name))
    assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
    assert_true(completed_cell(output, 1, 0) is Some(Number(2.0)))
    assert_true(completed_cell(output, 0, 1) is Some(Text("one")))
    assert_true(completed_cell(output, 1, 1) is Some(Text("two")))
    let current = (
      execution.state.control.remaining,
      execution.state.workspace.peak,
    )
    if usage is Some(expected) {
      assert_eq(current, expected)
    }
    if total_work is Some(expected) {
      assert_eq(work, expected)
    }
    usage = Some(current)
    total_work = Some(work)
    assert_eq(cursor.bytes, 0)
    assert_true(cursor.closed)
    assert_true(cleanup_bounded_values(execution).unwrap())
    assert_false(cleanup_bounded_values(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    cancel_trusted_output_preparation(cursor)
    assert_eq(completed_column_name(output, 1), Some(name))
    assert_eq(cursor.names.length(), 2)
  }
  let (_, started) = bounded_values_fixture(
    max_work=10000,
    max_entries=100,
    name_bytes=277,
    label_name=name,
  )
  let execution = started.unwrap()
  let mut refused = false
  for _ in 0..<1000 {
    match advance_bounded_values(execution, 1).unwrap() {
      BoundedValuesContinue(..) => ()
      BoundedValuesFailed(Completion(Limit), ..) => {
        refused = true
        break
      }
      _ => fail("expected Unicode Values completion name limit")
    }
  }
  assert_true(refused)
  assert_eq(execution.state.row, 0)
  assert_true(cleanup_bounded_values(execution).unwrap())
}

///|
test "Values completion stops inside every preparation phase before cell demand" {
  for phase in 0..<4 {
    let (control, started) = bounded_values_fixture()
    let execution = started.unwrap()
    let cursor = execution.state.port_preparation.unwrap()
    let mut reached = false
    for _ in 0..<1000 {
      if cursor.phase == phase && cursor.offset > 0 {
        reached = true
        break
      }
      assert_true(
        advance_bounded_values(execution, 1).unwrap()
        is BoundedValuesContinue(..),
      )
    }
    assert_true(reached)
    let remaining = execution.state.control.remaining
    let pending_names = cursor.names.length()
    assert_true(@bounded.request_cancel(control))
    assert_false(cursor.closed)
    assert_true(
      advance_bounded_values(execution, 1).unwrap()
      is BoundedValuesStopped(_, ..),
    )
    assert_false(cursor.closed)
    assert_eq(cursor.names.length(), pending_names)
    assert_eq(execution.state.control.remaining, remaining)
    assert_true(execution.state.port is None)
    assert_true(execution.state.rows.val is None)
    assert_false(execution.accepted.val)
    assert_true(cleanup_bounded_values(execution).unwrap())
    assert_false(cleanup_bounded_values(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(cursor.closed)
    assert_true(cursor.names.is_empty())
    assert_true(execution.state.port_preparation is None)
  }
}
