///|
fn bounded_selection_fixture(
  wide? : Bool = false,
) -> (ManagedViewPlan[Int], ManagedCompletedOutput[Int], Ref[Bool]) raise {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live, index_cells=4)
  let steps = if wide {
    let fields = Array::makei(100, index => {
      "\"v" + index.to_string() + "\":\"n\""
    }).join(",")
    "[{\"derive\":{" + fields + "}}]"
  } else {
    "[{\"filter\":\"n > 0\"},{\"select\":[\"n\",\"s\"]}]"
  }
  let receiver = typed_receiver(owner, steps)
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let kernels = if wide {
    [row_kernel(receiver, 0)]
  } else {
    [row_kernel(receiver, 0), row_kernel(receiver, 1)]
  }
  let plan = prepare_managed_view_plan(input, kernels, 100000, 100000, 200).unwrap()
  (plan, source, live)
}

///|
test "selection preparation charges exact independent work across quanta" {
  for quantum in [1, 7, 64] {
    let (plan, source, _) = bounded_selection_fixture(wide=true)
    // 204 copied cells + 2 copied rows + 2 row checks + 102 column
    // checks + 204 aggregate visits = 514 existing logical work.
    let cursor = begin_managed_view_selection(plan, [0, 1], 204, 514).unwrap()
    assert_true(advance_managed_view_selection(cursor, 0) is Err(Closed))
    assert_false(cursor.closed)
    assert_true(take_managed_view_selection(cursor) is Err(Closed))
    let mut complete = false
    let mut steps = 0
    while !complete {
      let poll = advance_managed_view_selection(cursor, quantum).unwrap()
      assert_true(poll.1 > 0 && poll.1 <= quantum)
      steps += poll.1
      assert_true(steps <= 726)
      complete = poll.0
    }
    assert_eq(steps, 726)
    assert_eq(cursor.work, 0)
    let selection = take_managed_view_selection(cursor).unwrap()
    assert_true(cursor.index is None)
    assert_true(take_managed_view_selection(cursor) is Err(Closed))
    assert_false(cancel_managed_view_selection_preparation(cursor))
    assert_eq(selection.index.count, 204)
    assert_eq(selection.index.cells.length(), 1836)
    for column in 0..<102 {
      let facts = selection.facts.columns[column]
      // The source Text is é/😀; every other field is n or a copy.
      assert_eq(
        (facts.bytes, facts.nodes),
        if column == 1 {
          (10, 2)
        } else {
          (2, 2)
        },
      )
    }
    assert_eq(
      managed_output_measurement_index_cells(source.material.receipt),
      Some(4),
    )
  }
}

///|
test "selection work and cell one-short refuse without copied index publication" {
  for quantum in [1, 7, 64] {
    let (plan, source, _) = bounded_selection_fixture(wide=true)
    assert_true(
      begin_managed_view_selection(plan, [0, 1], 203, 514) is Err(Limit),
    )
    let cursor = begin_managed_view_selection(plan, [0, 1], 204, 513).unwrap()
    let mut failed = false
    while !failed {
      match advance_managed_view_selection(cursor, quantum) {
        Ok((false, _)) => ()
        Ok((true, _)) => fail("one-short work cannot finish")
        Err(Limit) => failed = true
        Err(_) => fail("unexpected selection failure")
      }
    }
    assert_true(cursor.closed)
    assert_true(cursor.index is None)
    assert_true(take_managed_view_selection(cursor) is Err(Closed))
    assert_eq(
      managed_output_measurement_index_cells(source.material.receipt),
      Some(4),
    )
  }
}

///|
test "selection cancellation and revocation keep source and discard partial copies" {
  for boundary in [1, 5, 100, 519, 521, 725] {
    for revoke in [false, true] {
      let (plan, source, live) = bounded_selection_fixture(wide=true)
      let cursor = begin_managed_view_selection(plan, [0, 1], 204, 514).unwrap()
      for _ in 0..<boundary {
        assert_true(advance_managed_view_selection(cursor, 1) is Ok((false, 1)))
      }
      let held = cursor.index
      if revoke {
        live.val = false
        assert_true(
          advance_managed_view_selection(cursor, 1) is Err(ForeignInput),
        )
      } else {
        assert_true(cancel_managed_view_selection_preparation(cursor))
        assert_true(advance_managed_view_selection(cursor, 1) is Err(Closed))
      }
      assert_false(cancel_managed_view_selection_preparation(cursor))
      assert_true(cursor.index is None)
      assert_eq(cursor.rows.length(), 0)
      assert_eq(cursor.columns.length(), 0)
      assert_eq(cursor.measurements.length(), 0)
      if held is Some(index) {
        assert_eq(index.count, 0)
        assert_eq(index.cells.length(), 0)
      }
      assert_eq(
        managed_output_measurement_index_cells(source.material.receipt),
        Some(4),
      )
    }
  }
}

///|
test "selection snapshots rows and rejects mutable pending width" {
  let (plan, _, _) = bounded_selection_fixture()
  let rows = [0, 1]
  let cursor = begin_managed_view_selection(plan, rows, 4, 14).unwrap()
  advance_managed_view_selection(cursor, 2).unwrap() |> ignore
  rows[0] = 1
  rows[1] = 0
  while !advance_managed_view_selection(cursor, 1).unwrap().0 {

  }
  let selection = take_managed_view_selection(cursor).unwrap()
  assert_eq(managed_view_selection_row(selection, 0), Some(0))
  assert_eq(managed_view_selection_row(selection, 1), Some(1))
  let rows = [0, 1]
  let pending = begin_managed_view_selection(plan, rows, 4, 14).unwrap()
  advance_managed_view_selection(pending, 1).unwrap() |> ignore
  rows.push(0)
  assert_true(
    advance_managed_view_selection(pending, 1) is Err(InvalidSelection),
  )
  assert_true(pending.closed)
}

///|
test "permutation and duplicates retain exact extra work and ordered selection guards" {
  for quantum in [1, 7, 64] {
    let (plan, _, _) = bounded_selection_fixture()
    // Increasing selection uses 14, permutation adds two duplicate checks.
    let cursor = begin_managed_view_selection(plan, [1, 0], 4, 16).unwrap()
    while !advance_managed_view_selection(cursor, quantum).unwrap().0 {

    }
    assert_eq(cursor.work, 0)
    let selected = take_managed_view_selection(cursor).unwrap()
    assert_eq(managed_view_selection_row(selected, 0), Some(1))
    assert_eq(
      managed_row_measurement_get(selected.index, 1),
      Some((6, 1, false)),
    )
    let rejected = begin_managed_view_selection(plan, [1, 0], 4, 16, validate_occurrence=fn(
      position,
      row,
    ) {
      position == row
    }).unwrap()
    assert_true(
      advance_managed_view_selection(rejected, 64) is Err(InvalidSelection),
    )
    let duplicate = begin_managed_view_selection(plan, [0, 0], 4, 14).unwrap()
    assert_true(
      advance_managed_view_selection(duplicate, 64) is Err(InvalidSelection),
    )
    let empty = begin_managed_view_selection(plan, [], 0, 2).unwrap()
    while !advance_managed_view_selection(empty, quantum).unwrap().0 {

    }
    assert_eq(take_managed_view_selection(empty).unwrap().index.count, 0)
  }
}

///|
test "virtual slice avoids a copied row map with exact work and cell limits" {
  for quantum in [1, 7, 64] {
    let (plan, source, _) = bounded_selection_fixture()
    assert_true(
      begin_managed_view_slice(plan, -1, 1, 2, 7) is Err(InvalidSelection),
    )
    assert_true(
      begin_managed_view_slice(plan, 1, 2, 2, 7) is Err(InvalidSelection),
    )
    assert_true(begin_managed_view_slice(plan, 1, 1, 1, 7) is Err(Limit))
    // Two cells copied, one row checked, two columns, two aggregate visits.
    let cursor = begin_managed_view_slice(plan, 1, 1, 2, 7, validate_occurrence=fn(
      position,
      row,
    ) {
      position == 0 && row == 1
    }).unwrap()
    let mut steps = 0
    let mut done = false
    while !done {
      let poll = advance_managed_view_selection(cursor, quantum).unwrap()
      steps += poll.1
      done = poll.0
    }
    assert_eq(steps, 18)
    assert_eq(cursor.work, 0)
    let selection = take_managed_view_selection(cursor).unwrap()
    assert_true(selection.rows is Slice(1, 1))
    assert_eq(
      managed_row_measurement_get(selection.index, 1),
      Some((6, 1, false)),
    )
    let short = begin_managed_view_slice(plan, 1, 1, 2, 6).unwrap()
    assert_true(advance_managed_view_selection(short, 64) is Err(Limit))
    assert_eq(
      managed_output_measurement_index_cells(source.material.receipt),
      Some(4),
    )
  }
}

///|
test "selection validation reentry cannot claim or reopen the active cursor" {
  for cancel in [false, true] {
    let (plan, source, _) = bounded_selection_fixture()
    let active : Ref[ManagedViewSelectionPreparation[Int]?] = Ref(None)
    let cursor = begin_managed_view_selection(plan, [0, 1], 4, 14, validate_occurrence=fn(
      _,
      _,
    ) {
      let cursor = active.val.unwrap()
      assert_true(advance_managed_view_selection(cursor, 1) is Err(Closed)) catch {
        _ => abort("reentry")
      }
      assert_true(take_managed_view_selection(cursor) is Err(Closed)) catch {
        _ => abort("claim")
      }
      if cancel {
        cancel_managed_view_selection_preparation(cursor) |> ignore
      }
      true
    }).unwrap()
    active.val = Some(cursor)
    if cancel {
      assert_true(advance_managed_view_selection(cursor, 64) is Err(Closed))
      assert_true(cursor.index is None)
    } else {
      assert_true(advance_managed_view_selection(cursor, 64) is Ok((true, _)))
      assert_eq(take_managed_view_selection(cursor).unwrap().index.count, 4)
    }
    active.val = None
    assert_eq(
      managed_output_measurement_index_cells(source.material.receipt),
      Some(4),
    )
  }
}
