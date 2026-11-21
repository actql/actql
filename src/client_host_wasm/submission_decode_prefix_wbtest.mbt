///|
// Real same-Root Ledger/pool/projection custody with explicit pure fixture
// ports. No Host, Account/current grant, physical I/O or normal acceptance.
fn submission_decode_prefix_fixture() -> (
  Instance,
  StoredSubmissionProjection,
  @buffers.BufferSlot,
) raise {
  let (value, _, source) = sdk_row_original_fixture(33554432L)
  // This control needs an owned projection slot, not a produced transport.
  // Its original 4096-byte pool already contains the two-byte input.
  let slot = @buffers.reserve_output_buffer(value.pool, 2, 0L, () => true).unwrap()
  let record : StoredSubmissionProjection = {
    configuration: 0,
    kind: 3,
    borrow: Ok(@buffers.borrow_buffer(value.pool, source, () => true).unwrap()),
    slot,
    saved_result: None,
    saved_snapshot: None,
    append_plan: Idle,
    failure_preparation: None,
    failure_plan: None,
    cancellation_append: None,
    unpublished_state: None,
    invoked: false,
    produced: false,
    output_closed: false,
  }
  value.submissions[7] = record
  (value, record, source)
}

///|
fn submission_decode_prefix_fixture_close(
  value : Instance,
  source : @buffers.BufferSlot,
) -> Unit raise {
  assert_eq(close_submission_projection(value.nonce, 7), 0)
  sdk_row_original_fixture_close(value, source)
  assert_eq(@resources.ledger_usage(value.root).reserved_retention_bytes, 0L)
}

///|
test "scanned prefix exact existing geometry and one-short refusal before codec IO" {
  // Same existing Native geometry, not measured heap or a new tariff.
  let units = @host.client_submitted_journal_retained_inventory(262144, 786432L)
  assert_eq(units.record_headers, 32L)
  assert_eq(units.reference_slots, 64L)
  assert_eq(units.scalar_words, 32L)
  assert_eq(units.owned_utf16_units, 786503L)
  assert_eq(units.owned_wire_bytes, 262144L)
  assert_eq(@execution.preparation_representation_cost(units), Some(1836430L))
  assert_eq(submission_decode_prefix_capacity(), Some(5509754L))
  println("prefix geometry complete: 5509754")
  let (value, record, source) = submission_decode_prefix_fixture()
  println("prefix original fixture complete")
  let capacity = open_submission_decode_prefix(value, record).unwrap()
  let usage = @resources.ledger_usage(value.root)
  let remaining = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let additional = submission_decode_prefix_capacity().unwrap() -
    submission_decode_controller_capacity()
  println(
    "prefix original remaining=\{remaining}; required_growth=\{additional}",
  )
  let blocker = @resources.reserve_capacity(
    value.root,
    remaining - additional + 1L,
    0L,
  ).unwrap()
  let reads = Ref(0)
  let original : @host.ClientTaskMaterialsOriginal[Unit]? = None
  // If construction ran, this malformed body would return -31, not -4.
  assert_true(
    read_scanned_submission_for_projection(
      value,
      record,
      capacity,
      { key: "bad", revision: 0L, body: b"{}", },
      (_, _) => {
        reads.val += 1
        Err(-71)
      },
      _ => Err(-72),
      original,
    )
    is Err(-4),
  )
  assert_eq(reads.val, 0)
  assert_true(
    record.append_plan is Decoding(same, Idle) && physical_equal(same, capacity),
  )
  assert_true(
    @resources.capacity_reservation_covers(value.root, capacity, 416L, 416L),
  )
  @resources.settle_capacity(value.root, blocker).unwrap()
  submission_decode_prefix_fixture_close(value, source)
}

///|
test "scanned prefix covers constructor failure through original projection cleanup" {
  let (value, record, source) = submission_decode_prefix_fixture()
  let before = @resources.ledger_usage(value.root)
  let capacity = open_submission_decode_prefix(value, record).unwrap()
  let reads = Ref(0)
  let original : @host.ClientTaskMaterialsOriginal[Unit]? = None
  assert_true(
    read_scanned_submission_for_projection(
      value,
      record,
      capacity,
      { key: "bad", revision: 0L, body: b"{}", },
      (_, _) => {
        reads.val += 1
        Err(-71)
      },
      _ => Err(-72),
      original,
    )
    is Err(-31),
  )
  assert_eq(reads.val, 0)
  assert_true(
    record.append_plan is DecodedRows(same, Idle, amount) &&
    physical_equal(same, capacity) &&
    amount == 5509754L,
  )
  assert_true(
    @resources.capacity_reservation_covers(
      value.root,
      capacity,
      5509754L,
      5509754L,
    ),
  )
  assert_true(open_submission_decode_prefix(value, record) is Err(-9))
  let same_grown_control = record.append_plan
  assert_eq(prepare_submission_decode_prefix(value, record, capacity, 2), 0)
  assert_true(physical_equal(record.append_plan, same_grown_control))
  assert_true(submission_decode_prefix_current(value, record, capacity))
  assert_eq(
    @resources.ledger_usage(value.root).reserved_retention_bytes,
    before.reserved_retention_bytes + 5509754L,
  )
  submission_decode_prefix_fixture_close(value, source)
}

///|
test "scanned prefix stays owned after callback return through record consumption" {
  let (value, record, source) = submission_decode_prefix_fixture()
  let capacity = open_submission_decode_prefix(value, record).unwrap()
  let rows = targeted_snapshot_rows()
  let original : @host.ClientTaskMaterialsOriginal[Unit]? = None
  {
    let observed = read_scanned_submission_for_projection(
      value,
      record,
      capacity,
      rows[3].1,
      (table, key) => targeted_row_read(rows, table, key),
      submission_append_run_inspection,
      original,
    ).unwrap()
    assert_true(record.append_plan is DecodedRows(_, _, _))
    assert_true(submission_decode_prefix_current(value, record, capacity))
    assert_eq(@host.client_saved_submission_row(observed).revision, 6L)
    assert_true(
      @host.client_saved_submission_record(observed).run_admission is Some(_),
    )
    assert_true(@resources.capacity_reservation_open(capacity))
  }
  // All result aliases above are consumed before settlement, not at callback return.
  assert_true(
    finish_submission_decode_observation(value, record, Err(-71)) is Err(-71),
  )
  assert_true(record.append_plan is Idle)
  assert_false(@resources.capacity_reservation_open(capacity))
  submission_decode_prefix_fixture_close(value, source)
}

///|
test "scanned prefix foreign settlement cannot hide original cause or clear pool owner" {
  let (value, record, source) = submission_decode_prefix_fixture()
  let capacity = open_submission_decode_prefix(value, record).unwrap()
  let original_cell = record.append_plan
  let foreign = @resources.create_ledger({
    planning_work: 8,
    attempts: 8,
    holdings: 8,
    transfer_bytes: 4096L,
    retained_bytes: 4096L,
    execution_bytes: 4096L,
  }).unwrap()
  let impostor = @resources.reserve_capacity(foreign, 416L, 416L).unwrap()
  // Explicit corruption counter, not a runtime failure or foreign-state adoption.
  record.append_plan = Decoding(impostor, Idle)
  assert_false(submission_decode_prefix_current(value, record, impostor))
  assert_true(
    finish_submission_decode_observation(value, record, Err(-71)) is Err(-71),
  )
  assert_true(
    record.append_plan is Decoding(same, Idle) && physical_equal(same, impostor),
  )
  assert_eq(close_pool(value.nonce), -4)
  assert_true(
    value.submissions.get(7) is Some(same) && physical_equal(same, record),
  )
  assert_true(
    record.append_plan is Decoding(same, Idle) && physical_equal(same, impostor),
  )
  // Restore the same original token, never issue/refill a replacement purpose.
  record.append_plan = original_cell
  @resources.settle_capacity(foreign, impostor).unwrap()
  assert_eq(close_submission_decode_prefix(value, record), 0)
  assert_false(@resources.capacity_reservation_open(capacity))
  submission_decode_prefix_fixture_close(value, source)
}

///|
test "scanned prefix restores same previous Ready plan after original-token settlement" {
  let (value, record, source) = submission_decode_prefix_fixture()
  // This explicit pure fixture backs its pre-existing Ready snapshot before
  // construction; it is not a new product holder or historical reuse route.
  let prior_backing = @resources.reserve_capacity(
    value.root,
    5509754L,
    5509754L,
  ).unwrap()
  let rows = targeted_snapshot_rows()
  let original : @host.ClientTaskMaterialsOriginal[Unit]? = None
  let prior = @host.read_client_saved_submission_with_task_original(
      @host.decode_client_submitted_journal_row(rows[3].1.body).unwrap().reference,
      (table, key) => targeted_row_read(rows, table, key),
      submission_append_run_inspection,
      -31,
      original,
    )
    .unwrap()
    .unwrap()
  let previous = Ready(@host.Retained(prior))
  record.append_plan = previous
  let capacity = open_submission_decode_prefix(value, record).unwrap()
  assert_eq(prepare_submission_decode_prefix(value, record, capacity, 2), 0)
  assert_true(
    record.append_plan is DecodedRows(same, saved, amount) &&
    physical_equal(same, capacity) &&
    physical_equal(saved, previous) &&
    amount == 5509754L,
  )
  assert_true(
    finish_submission_decode_observation(value, record, Err(-71)) is Err(-71),
  )
  assert_true(physical_equal(record.append_plan, previous))
  assert_true(
    record.append_plan is Ready(@host.Retained(same)) &&
    physical_equal(same, prior),
  )
  assert_false(@resources.capacity_reservation_open(capacity))
  assert_eq(close_submission_projection(value.nonce, 7), 0)
  @resources.settle_capacity(value.root, prior_backing).unwrap()
  sdk_row_original_fixture_close(value, source)
  assert_eq(@resources.ledger_usage(value.root).reserved_retention_bytes, 0L)
}

///|
test "scanned prefix admits quote carriers before first geometry construction" {
  let (value, record, source) = submission_decode_prefix_fixture()
  assert_eq(submission_decode_controller_capacity(), 416L)
  let usage = @resources.ledger_usage(value.root)
  let remaining = @resources.ledger_limits(value.root).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let blocker = @resources.reserve_capacity(value.root, remaining - 415L, 0L).unwrap()
  let blocked = @resources.ledger_usage(value.root)
  assert_true(open_submission_decode_prefix(value, record) is Err(-4))
  assert_true(record.append_plan is Idle)
  assert_eq(
    @resources.ledger_usage(value.root).reserved_retention_bytes,
    blocked.reserved_retention_bytes,
  )
  @resources.settle_capacity(value.root, blocker).unwrap()
  submission_decode_prefix_fixture_close(value, source)
}
