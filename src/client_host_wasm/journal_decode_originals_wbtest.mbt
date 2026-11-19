///|
// Pure closed decoder/real Ledger controls. No Store, Account grant, dispatch,
// normal Host or fuel qualification is supplied by this fixture.
fn journal_decode_fixture() -> (
  Instance,
  StoredJournalObservation,
  StoredJournalDecodeFrame,
  @buffers.BufferSlot,
) raise {
  let (value, _, parent) = sdk_row_original_fixture(33554432L)
  let slot = @buffers.reserve_output_buffer(value.pool, 2, 0L, () => true).unwrap()
  let row = submission_append_run_inspection(
    submission_identity_row(@utf8.encode(submission_identity_wire)),
  ).unwrap()
  let child : StoredJournalObservation = {
    material: 0,
    configuration: 0,
    physical: 43,
    slot,
    invoked: true,
    closing: false,
    outcome: None,
    admission_produced: false,
  }
  value.journal_observations[73] = child
  let frame = open_journal_decode_frame(
    value,
    73,
    child,
    @host.client_request_scope_cid(row.request),
  ).unwrap()
  (value, child, frame, parent)
}

///|
fn journal_decode_fixture_row() -> @host.ClientJournalPhysicalRow {
  let body = @utf8.encode(submission_identity_wire)
  let original = submission_append_run_inspection(submission_identity_row(body)).unwrap()
  { key: @host.client_request_scope_cid(original.request), revision: 7L, body, }
}

///|
test "journal same-frame pure original avoids repeated construction but keeps row changes distinct" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let constructions = Ref(0)
  let observe = _ => {
    constructions.val += 1
    Ok(())
  }
  let first = journal_decode_run_inspection(
    value,
    child,
    frame,
    row,
    before_construction=Some(observe),
  ).unwrap()
  assert_eq(constructions.val, 3)
  let usage = @resources.ledger_usage(value.root)
  let same = journal_decode_run_inspection(
    value,
    child,
    frame,
    { ..row, body: @utf8.encode(submission_identity_wire), },
    before_construction=Some(observe),
  ).unwrap()
  assert_true(physical_equal(first.request, same.request))
  assert_true(physical_equal(first.definition, same.definition))
  assert_eq(constructions.val, 3)
  assert_eq(@resources.ledger_usage(value.root), usage)
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      { ..row, revision: 8L, },
      before_construction=Some(observe),
    ).unwrap(),
  )
  assert_eq(constructions.val, 6)
  let changed = {
    ..row,
    body: @utf8.encode(
      submission_identity_wire.replace(
        old="\"cancellation_requested\":false",
        new="\"cancellation_requested\":true",
      ),
    ),
  }
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      changed,
      before_construction=Some(observe),
    ).unwrap(),
  )
  assert_eq(constructions.val, 9)
  ignore(
    journal_decode_run_inspection(
      value,
      child,
      frame,
      { ..row, key: "foreign-key", },
      before_construction=Some(observe),
    ).unwrap(),
  )
  assert_eq(constructions.val, 12)
  assert_true(
    journal_decode_run_inspection(value, { ..child, physical: 44, }, frame, row)
    is Err(-2),
  )
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  assert_true(
    journal_decode_run_inspection(value, child, frame, row) is Err(-2),
  )
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame one-short retention keeps the original full decoder path" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let (retention, _) = journal_decode_row_capacity(row).unwrap()
  let usage = @resources.ledger_usage(value.root)
  let available = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let blocker = @resources.reserve_capacity(
    value.root,
    available - retention + 1L,
    0L,
  ).unwrap()
  let limited = @resources.ledger_usage(value.root)
  let constructions = Ref(0)
  for _ in 0..<2 {
    ignore(
      journal_decode_run_inspection(
        value,
        child,
        frame,
        row,
        before_construction=Some(_ => {
          constructions.val += 1
          Ok(())
        }),
      ).unwrap(),
    )
  }
  assert_eq(constructions.val, 6)
  assert_true(frame.rows is None)
  assert_eq(@resources.ledger_usage(value.root), limited)
  @resources.settle_capacity(value.root, blocker).unwrap()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  assert_true(frame.rows is Some(_))
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame selected output backing survives frame exit until actual child close" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let selected = journal_decode_run_inspection(value, child, frame, row).unwrap()
  let selected_cell = frame.selected.unwrap()
  let selected_token = selected_cell.capacity
  ignore(
    journal_decode_run_inspection(value, child, frame, {
      ..row,
      key: "other-row",
    }).unwrap(),
  )
  let foreign_token = frame.rows.unwrap().capacity
  assert_eq(dispose_journal_decode_rows(value, frame, true), 0)
  assert_false(@resources.capacity_reservation_open(foreign_token))
  assert_true(@resources.capacity_reservation_open(selected_token))
  assert_true(physical_equal(frame.rows.unwrap(), selected_cell))
  assert_true(
    physical_equal(selected_cell.decoded.unwrap().0.request, selected.request),
  )
  assert_true(
    journal_decode_run_inspection(value, child, frame, row) is Err(-2),
  )
  // Result DATA is consumed while its SAME original child still owns backing.
  assert_true(
    @resources.capacity_reservation_covers(
      value.root,
      selected_token,
      selected_cell.retention,
      0L,
    ),
  )
  let usage = @resources.ledger_usage(value.root)
  let available = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let close_blocker = @resources.reserve_capacity(
    value.root,
    available - 1L,
    0L,
  ).unwrap()
  // Close needs no fresh storage/admission even with only one free byte.
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  @resources.settle_capacity(value.root, close_blocker).unwrap()
  assert_false(@resources.capacity_reservation_open(selected_token))
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame reentry and unsupported originals retain their primary refusal" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  let entered = Ref(false)
  let nested_refusal = Ref(false)
  let refusal = journal_decode_run_inspection(
    value,
    child,
    frame,
    row,
    before_construction=Some(_ => {
      if !entered.val {
        entered.val = true
        nested_refusal.val = journal_decode_run_inspection(
            value, child, frame, row,
          )
          is Err(-33)
      }
      // Ignoring a nested refusal must not turn the outer construction green.
      Ok(())
    }),
  )
  assert_true(refusal is Err(-33))
  assert_true(nested_refusal.val)
  assert_true(frame.rows.unwrap().decoded is None)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
  let (value, child, frame, parent) = journal_decode_fixture()
  let unsupported = {
    ..row,
    body: @utf8.encode(
      submission_identity_wire.replace(
        old="\"checkpoint\":null",
        new="\"checkpoint\":\"[]\"",
      ),
    ),
  }
  assert_true(
    journal_decode_run_inspection(value, child, frame, unsupported) is Err(-42),
  )
  assert_true(frame.rows.unwrap().decoded is None)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame partial cleanup retains only exact pending tokens and original error" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  let tail = frame.rows.unwrap()
  ignore(
    journal_decode_run_inspection(value, child, frame, { ..row, revision: 8L, }).unwrap(),
  )
  let head = frame.rows.unwrap()
  let foreign = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 1024L,
    execution_bytes: 1024L,
  }).unwrap()
  let foreign_token = @resources.reserve_capacity(foreign, 1L, 0L).unwrap()
  let wrong = { ..tail, capacity: foreign_token, }
  head.next = Some(wrong)
  child.outcome = Some(Observed(Err(-42), Some(frame)))
  assert_eq(close_journal_observation(value.nonce, 73), -4)
  assert_false(@resources.capacity_reservation_open(head.capacity))
  assert_true(@resources.capacity_reservation_open(tail.capacity))
  assert_true(@resources.capacity_reservation_open(foreign_token))
  assert_true(physical_equal(frame.rows.unwrap(), wrong))
  assert_true(child.outcome is Some(Observed(Err(-42), _)))
  // Restore this explicit foreign-token corruption fixture, not business state.
  frame.rows = Some(tail)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  @resources.settle_capacity(foreign, foreign_token).unwrap()
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame one-short frame admission preserves unmodified pure inspection" {
  let (value, child, frame, parent) = journal_decode_fixture()
  assert_eq(close_journal_decode_frame(value, frame), 0)
  child.outcome = None
  let row = journal_decode_fixture_row()
  let usage = @resources.ledger_usage(value.root)
  let available = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let blocker = @resources.reserve_capacity(
    value.root,
    available - journal_decode_frame_capacity().unwrap() + 1L,
    0L,
  ).unwrap()
  let before = @resources.ledger_usage(value.root)
  assert_true(open_journal_decode_frame(value, 73, child, row.key) is None)
  assert_true(child.outcome is None)
  assert_eq(@resources.ledger_usage(value.root), before)
  let original = submission_append_run_inspection(row).unwrap()
  assert_eq(@host.client_request_scope_cid(original.request), row.key)
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  @resources.settle_capacity(value.root, blocker).unwrap()
  sdk_row_original_fixture_close(value, parent)
}

///|
test "journal same-frame outer codec reuse never skips the original SDK purpose validator" {
  let (value, child, frame, parent) = journal_decode_fixture()
  let row = journal_decode_fixture_row()
  ignore(journal_decode_run_inspection(value, child, frame, row).unwrap())
  let cell = frame.rows.unwrap()
  let (decoded, policy, observation) = cell.decoded.unwrap()
  // Explicit private-DATA corruption control: the purpose validator must still
  // see this unsupported field even on the exact-body outer-codec hit.
  cell.decoded = Some(
    ({ ..decoded, checkpoint: Some("[]"), }, policy, observation),
  )
  assert_true(
    journal_decode_run_inspection(value, child, frame, row) is Err(-42),
  )
  assert_eq(close_journal_observation(value.nonce, 73), 0)
  sdk_row_original_fixture_close(value, parent)
}
