///|
fn original_document_test_wire() -> String {
  // Independent saved-state bytes, not produced by the candidate writer.
  "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
}

///|
fn original_document_test_cursor(wire : String) -> @decode.Cursor {
  let node = @source.parse_json(wire, {
    max_input_bytes: 4000,
    max_nodes: 400,
    max_depth: 10,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 400,
    max_depth: 10,
    max_string_bytes: 100,
    max_total_string_bytes: 4000,
  }).unwrap()
}

///|
fn finish_document_test_read(
  read : OriginalStateDocumentRead,
  quantum : Int,
) -> (OriginalStateDocument, Int) {
  for work = 0 {
    match advance_original_state_document_read(read, quantum) {
      DocumentContinue(work=n) => continue work + n
      DocumentComplete(document, work=n) => break (document, work + n)
      DocumentFailed(_, ..) => abort("document unexpectedly failed")
    }
  }
}

///|
test "original state document borrowed child retains full owned tree limits and retirement" {
  // The saved state has 89 nodes. An enclosing array and a 65-byte sibling
  // add two nodes and one container level; child access retains all of them.
  // These independent shape counts are not physical-byte coefficients.
  let sibling = "x".repeat(65)
  let outer = original_document_test_cursor(
    "[\"" + sibling + "\"," + original_document_test_wire() + "]",
  )
  let child = @decode.element_at(outer, 1).unwrap()
  assert_eq(@decode.admission_usage(child), @decode.admission_usage(outer))
  let usage = @decode.admission_usage(child)
  assert_eq(usage.nodes, 91)
  assert_eq(usage.depth, 5)
  assert_eq(usage.largest_string_bytes, 65)
  assert_true(
    start_original_state_document_read(child, 1, 0, 0, 3) is Err(InvalidBounds),
  )
  let full : @decode.Limits = {
    max_nodes: 91,
    max_depth: 5,
    max_string_bytes: 65,
    max_total_string_bytes: 1000,
  }
  for
    too_small in [
      { ..full, max_nodes: 90, },
      { ..full, max_depth: 4, },
      { ..full, max_string_bytes: 64, },
    ] {
    assert_true(
      start_original_state_document_read_in_owned_tree(
        child, 1, 0, 0, 3, too_small,
      )
      is Err(InvalidBounds),
    )
  }
  let read = start_original_state_document_read_in_owned_tree(
    child, 1, 0, 0, 3, full,
  ).unwrap()
  let borrowed = read.document.unwrap()
  assert_true(
    advance_original_state_document_read(read, 1) is DocumentContinue(work=1),
  )
  cancel_original_state_document_read(read)
  assert_true(read.document is None && borrowed.source is None)
  assert_eq(original_state_document_usage(borrowed), None)
  // Retirement drops this document's borrow only, not the owning outer tree.
  assert_eq(@decode.text(@decode.element_at(outer, 0).unwrap()), Ok(sibling))
  let complete = start_original_state_document_read_in_owned_tree(
    child, 1, 0, 0, 3, full,
  ).unwrap()
  let (document, work) = finish_document_test_read(complete, 1)
  assert_eq(work, 3)
  assert_eq(
    @decode.admission_usage(document.source.unwrap()),
    @decode.admission_usage(outer),
  )
  retire_original_state_document(document)
  assert_eq(original_state_document_usage(document), None)
  assert_eq(@decode.admission_usage(child).nodes, 91)
}

///|
test "original state document fixed bytes preserve typed usage with constant work" {
  for quantum in [1, 2, 3, 50] {
    let source = original_document_test_cursor(original_document_test_wire())
    let read = start_original_state_document_read(source, 1, 0, 0, 3).unwrap()
    let (document, work) = finish_document_test_read(read, quantum)
    // Header/bootstrap, one read reservation, completion: independent 1+1+1.
    assert_eq(work, 3)
    assert_eq(original_state_document_usage(document).unwrap(), {
      planning_work: 17,
      attempts: 0,
      holdings: 0,
      reserved_attempts: 0,
      live_reservations: 2,
      live_delegations: 0,
      transferred_bytes: 0L,
      uncertain_transfer_bytes: 0L,
      reserved_transfer_bytes: 0L,
      held_bytes: 0L,
      reserved_retention_bytes: 10L,
      reserved_execution_bytes: 7L,
      peak_retention_bytes: 10L,
    })
    assert_eq(original_state_document_capacity_cursor(document), Some(Some(-3)))
    let original = document.source.unwrap()
    let reservation = document_reservation(
      document_at(document_at(original, 9), 0),
    ) catch {
      _ => abort("bad saved reservation")
    }
    assert_eq(reservation.serial, -2)
    assert_eq(reservation.retention, 7L)
    assert_eq(reservation.execution, 5L)
    assert_true(
      advance_original_state_document_read(read, 1)
      is DocumentFailed(Terminal, work=0),
    )
    retire_original_state_document(document)
    assert_true(document.source is None)
    assert_eq(original_state_document_usage(document), None)
    assert_eq(original_state_document_capacity_cursor(document), None)
  }
}

///|
test "original state document exact work bounds reject before returning a cursor" {
  let source = original_document_test_cursor(original_document_test_wire())
  assert_true(
    start_original_state_document_read(source, 1, 0, 0, 2) is Err(WorkLimit),
  )
  assert_true(
    start_original_state_document_read(source, 0, 0, 0, 3) is Err(InvalidBounds),
  )
  assert_true(
    start_original_state_document_read(source, 2147483647, 0, 0, 3)
    is Err(InvalidBounds),
  )
  // Body-declared bounds cannot replace the independently supplied bounds.
  assert_true(
    start_original_state_document_read(source, 2, 0, 0, 3) is Err(InvalidRecord),
  )
}

///|
test "original state document canonical scalar and closed header refusals" {
  let wire = original_document_test_wire()
  // Build the rejection input without declaring a future owned contract.
  let future_version = "actql-original-ledger-state/" + "0.2"
  for
    (old, replacement) in [
      ("\"17\"", "17"),
      ("\"17\"", "\"017\""),
      ("\"17\"", "\"+17\""),
      ("\"0\"", "\"-0\""),
      ("\"7\"", "\"9223372036854775808\""),
      ("\"reading\"", "\"handed_off\""),
      ("true,true,false", "true,true,true"),
      ("actql-original-ledger-state/0.1", future_version),
    ] {
    let source = original_document_test_cursor(
      wire.replace(old~, new=replacement),
    )
    assert_true(
      start_original_state_document_read(source, 1, 0, 0, 3)
      is Err(InvalidRecord),
    )
  }
  let extra = original_document_test_cursor(
    wire.replace(old="[],[]]", new="[],[],null]"),
  )
  assert_true(
    start_original_state_document_read(extra, 1, 0, 0, 3) is Err(InvalidRecord),
  )
}

///|
test "original state document failed record and cancellation retire borrowed source" {
  let malformed = original_document_test_wire().replace(
    old="\"-2\",\"0\",\"7\",\"5\",true,false",
    new="\"-2\",\"0\",\"7\",\"5\",true,null",
  )
  let source = original_document_test_cursor(malformed)
  let read = start_original_state_document_read(source, 1, 0, 0, 3).unwrap()
  let candidate = read.document.unwrap()
  assert_true(
    advance_original_state_document_read(read, 1) is DocumentContinue(work=1),
  )
  assert_true(
    advance_original_state_document_read(read, 1)
    is DocumentFailed(InvalidRecord, work=1),
  )
  assert_true(read.document is None && candidate.source is None)
  assert_eq(original_state_document_usage(candidate), None)
  let other = start_original_state_document_read(
    original_document_test_cursor(original_document_test_wire()),
    1,
    0,
    0,
    3,
  ).unwrap()
  let borrowed = other.document.unwrap()
  assert_true(
    advance_original_state_document_read(other, 0)
    is DocumentFailed(InvalidQuantum, work=0),
  )
  assert_true(
    advance_original_state_document_read(other, 1) is DocumentContinue(work=1),
  )
  cancel_original_state_document_read(other)
  cancel_original_state_document_read(other)
  assert_true(other.document is None && borrowed.source is None)
  assert_true(
    advance_original_state_document_read(other, 1)
    is DocumentFailed(Terminal, work=0),
  )
}

///|
test "original state document large unknown quantity and exhausted serial are data not authority" {
  let quantities = original_document_test_wire().replace(
    old="null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"]",
    new="[\"9223372036854775807\",\"17\",\"19\"],[[\"0\",\"0\",\"0\"],[\"9223372036854775807\",\"0\",\"19\"],[\"0\",\"7\",\"0\"]],[null,\"0\",\"0\"]",
  )
  let ledger = create_ledger({
    planning_work: 1,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }).unwrap()
  let before = ledger_usage(ledger)
  let read = start_original_state_document_read(
    original_document_test_cursor(quantities),
    1,
    0,
    0,
    3,
  ).unwrap()
  let (document, _) = finish_document_test_read(read, 1)
  assert_eq(original_state_document_quantities(document).unwrap().uncertain, {
    tokens: 9223372036854775807L,
    cost_units: 0L,
    duration_ms: 19L,
  })
  assert_eq(
    original_state_document_quantities(document).unwrap().consumed.cost_units,
    7L,
  )
  assert_eq(original_state_document_capacity_cursor(document), Some(None))
  // Structural decoding intentionally cannot authenticate these self-reported
  // fields, restore a fresh Ledger or make an original reservation usable.
  assert_eq(ledger_usage(ledger), before)
  assert_true(ledger.original_inventory is None)
  retire_original_state_document(document)
}

///|
test "original state document retains spent issuance cursor and pending unknown original record" {
  // Independent live census: unknown attempt and funded read. The expired
  // zero-byte capacity token is absent; its spent issuance cursor is preserved.
  let wire = "[\"actql-original-ledger-state/0.1\",[\"19\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"18\",\"1\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"3\",\"0\"],[\"0\",\"0\",\"0\"],[\"9223372036854775807\",\"17\",\"19\"],[[\"0\",\"0\",\"0\"],[\"9223372036854775807\",\"0\",\"19\"],[\"0\",\"7\",\"0\"]],[\"-4\",\"1\",\"0\"],[\"3\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"0\",\"0\",\"0\",true,true,null,[\"9223372036854775807\",\"0\",\"19\"],[false,true,false],null,false,true],[\"-3\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  let source = original_document_test_cursor(wire)
  for quantum in [1, 3, 50] {
    let read = start_original_state_document_read(source, 3, 0, 0, 5).unwrap()
    let (document, work) = finish_document_test_read(read, quantum)
    assert_eq(work, 4) // header + two live tokens + completion
    let records = document_at(document.source.unwrap(), 9) catch {
      _ => abort("records missing")
    }
    let attempt = document_reservation(document_at(records, 0)) catch {
      _ => abort("attempt missing")
    }
    let original_read = document_reservation(document_at(records, 1)) catch {
      _ => abort("original read missing")
    }
    assert_eq(attempt.serial, 0)
    assert_true(attempt.open && attempt.cleanup_pending)
    assert_eq(
      attempt.uncertain_quantities,
      Some({ tokens: 9223372036854775807L, cost_units: 0L, duration_ms: 19L, }),
    )
    assert_eq(attempt.observed_quantities, (false, true, false))
    assert_eq(original_read.serial, -3)
    assert_true(original_read.open && !original_read.cleanup_pending)
    assert_eq(original_read.retention, 7L)
    assert_eq(original_state_document_capacity_cursor(document), Some(Some(-4)))
    retire_original_state_document(document)
  }
}

///|
test "original state document validates holding delegation and completed output shapes" {
  let wire = "[\"actql-original-ledger-state/0.1\",[\"22\",\"5\",\"5\",\"11\",\"20\",\"10\"],[\"21\",\"0\",\"1\",\"0\",\"0\",\"2\",\"2\",\"12\",\"9\",\"14\",\"2\",\"4\",\"1\"],[\"1\",\"1\",\"1\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"2\",\"1\"],[\"3\",\"1\",\"1\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"0\",\"0\",\"0\",\"1\",true,true,null,null,[false,false,false],[\"0\",\"2\",\"1\"],true,false],[\"1\",\"2\",\"2\",\"1\",true,false,null,null,[false,false,false],null,true,false],[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[[\"0\",\"0\",\"2\",true]],[[\"1\",[\"1\",\"1\",\"1\",\"2\",\"2\",\"1\"],[\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\"]]]]"
  let read = start_original_state_document_read(
    original_document_test_cursor(wire),
    3,
    1,
    1,
    7,
  ).unwrap()
  let (document, work) = finish_document_test_read(read, 2)
  assert_eq(work, 7) // header + three reservations + holding + delegation + end
  assert_eq(document.counts, (3, 1, 1))
  assert_eq(document.state.delegated, (1, 1, 1))
  let completed = document_reservation(
    document_at(document_at(document.source.unwrap(), 9), 0),
  ) catch {
    _ => abort("completed output missing")
  }
  assert_eq(completed.completed_output, Some((Some(0), 2L, 1L)))
  for
    (old, replacement) in [
      ("[[\"0\",\"0\",\"2\",true]]", "[[\"0\",\"0\",\"2\",true,null]]"),
      (
        "[[\"1\",[\"1\",\"1\",\"1\",\"2\",\"2\",\"1\"]", "[[\"1\",[\"1\",\"1\",\"1\",\"2\",\"2\"]",
      ),
    ] {
    let malformed = start_original_state_document_read(
      original_document_test_cursor(wire.replace(old~, new=replacement)),
      3,
      1,
      1,
      7,
    ).unwrap()
    assert_true(
      advance_original_state_document_read(malformed, 7)
      is DocumentFailed(InvalidRecord, ..),
    )
    assert_true(malformed.document is None)
  }
  retire_original_state_document(document)
}
