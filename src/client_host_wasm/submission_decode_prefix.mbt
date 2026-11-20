///|
// Pre-admit quote construction as well as the original control: 40 control,
// 56 geometry, six 32-byte checked Some carriers, and 128 new call carriers
// (token Result 32, two private Some(token) 64, four callback captures 32).
// Existing fixed nonrecursive frames are not credits for allocated carriers.
fn submission_decode_controller_capacity() -> Int64 {
  40L + 56L + 6L * 32L + 128L
}

///|
fn submission_decode_prefix_capacity() -> Int64? {
  let row = @host.client_submitted_journal_retained_inventory(
    262144,
    3L * 262144L,
  )
  // Prior consumed loop value, current captured value, and miss/fallback value.
  // Their complete retained extents coexist with the paid controller. No old
  // physical-row transfer or historical Run capacity is used as a credit.
  guard @execution.preparation_representation_cost(row) is Some(one) else {
    return None
  }
  @execution.checked_preparation_add_product(
    40L + 48L + 56L + 6L * 32L + 128L,
    one,
    3L,
  )
}

///|
fn open_submission_decode_prefix(
  value : Instance,
  record : StoredSubmissionProjection,
) -> Result[@resources.CapacityReservation, Int] {
  if record.kind != 3 ||
    record.append_plan is Decoding(_, _) ||
    record.append_plan is DecodedRows(_, _, _) {
    return Err(-9)
  }
  // Every production caller point-selected this SAME private projection from
  // value.submissions before the original current/borrow checks. Do not add a
  // second live-projection iterator or a new physical/history observation here.
  let controller = submission_decode_controller_capacity()
  let capacity = match
    @resources.reserve_capacity(value.root, controller, controller) {
    Ok(value) => value
    Err(_) => return Err(-4)
  }
  let previous = record.append_plan
  record.append_plan = Decoding(capacity, previous)
  Ok(capacity)
}

///|
fn submission_decode_prefix_current(
  value : Instance,
  record : StoredSubmissionProjection,
  capacity : @resources.CapacityReservation,
) -> Bool {
  match record.append_plan {
    Decoding(original, _) =>
      physical_equal(original, capacity) &&
      @resources.capacity_reservation_covers(
        value.root,
        original,
        submission_decode_controller_capacity(),
        submission_decode_controller_capacity(),
      )
    DecodedRows(original, _, amount) =>
      physical_equal(original, capacity) &&
      amount >= submission_decode_controller_capacity() &&
      @resources.capacity_reservation_covers(
        value.root,
        original,
        amount,
        amount,
      )
    _ => false
  }
}

///|
fn prepare_submission_decode_prefix(
  value : Instance,
  record : StoredSubmissionProjection,
  capacity : @resources.CapacityReservation,
  bytes : Int,
) -> Int {
  // Preserve the existing fixed row profile; an observer must not select the
  // wider observed decoder profile as an accidental funding mechanism.
  if bytes < 1 || bytes > 262144 {
    return -31
  }
  if !submission_decode_prefix_current(value, record, capacity) {
    return -9
  }
  // A later row/current check consumes only the already admitted scalar.
  // No geometry or checked quote is reconstructed on this hot path.
  if record.append_plan is DecodedRows(_, _, _) {
    return 0
  }
  guard submission_decode_prefix_capacity() is Some(amount) else { return -4 }
  match
    @resources.grow_capacity_reservation(value.root, capacity, amount, amount) {
    Ok(_) => {
      guard record.append_plan is Decoding(original, previous) &&
        physical_equal(original, capacity) else {
        return -9
      }
      // Both old/new control variants fit the already admitted prefix peak.
      record.append_plan = DecodedRows(capacity, previous, amount)
      0
    }
    Err(_) => -4
  }
}

///|
// Caller consumes the returned record inside the same inventory body. Its
// reservation remains on the original projection until that whole body returns.
fn[Plan] read_scanned_submission_for_projection(
  value : Instance,
  record : StoredSubmissionProjection,
  capacity : @resources.CapacityReservation,
  row : @host.ClientJournalPhysicalRow,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  inspect_run : (@host.ClientJournalPhysicalRow) -> Result[
    @host.ClientRunJournalInspection,
    Int,
  ],
  task_original : @host.ClientTaskMaterialsOriginal[Plan]?,
) -> Result[@host.ClientSavedSubmissionSnapshot, Int] {
  let prepared = prepare_submission_decode_prefix(
    value,
    record,
    capacity,
    row.body.length(),
  )
  if prepared != 0 {
    return Err(prepared)
  }
  @host.read_client_scanned_submission_with_task_original(
    row, read, inspect_run, -31, task_original,
  )
}

///|
// Only after the synchronous body/aliases return, or the trusted cleanup
// entrance observes actual unwind. A failed settlement keeps SAME token/plan.
fn close_submission_decode_prefix(
  value : Instance,
  record : StoredSubmissionProjection,
) -> Int {
  match record.append_plan {
    Decoding(capacity, previous) | DecodedRows(capacity, previous, _) =>
      match @resources.settle_capacity(value.root, capacity) {
        Err(_) => -4
        Ok(_) => {
          record.append_plan = previous
          0
        }
      }
    _ => 0
  }
}

///|
fn finish_submission_decode_observation(
  value : Instance,
  record : StoredSubmissionProjection,
  result : Result[@host.ClientSubmittedJournalAppendPlan, Int],
) -> Result[@host.ClientSubmittedJournalAppendPlan, Int] {
  // Fresh insertion consumes its scanned records inside the inventory and
  // emits its original input's new wire. Retained target lookup returns before
  // that scan. Never settle a row prefix beneath an unexpected escaping alias.
  if record.append_plan is DecodedRows(_, _, _) &&
    result is Ok(@host.Retained(_)) {
    return Err(-31)
  }
  let settled = close_submission_decode_prefix(value, record)
  match result {
    Err(code) => Err(code)
    Ok(plan) => if settled == 0 { Ok(plan) } else { Err(settled) }
  }
}
