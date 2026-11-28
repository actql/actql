///|
// Original logical Node preparation only. No SDK snapshot, provider or physical
// cleanup is supplied by these explicit component fixture boundaries.
fn request_handoff_fixture() -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramJsonPreparation[Array[Int], Unit],
  Array[Int],
) raise {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let child = prepare_request_program_json_preparation(
    parent,
    input,
    request_json_effect_source,
    @publication_host.client_standard_program_preparation_limits().checking.input,
  ).unwrap()
  for _ in 0..<(request_json_effect_source.length() + 1) {
    match advance_program_json_preparation(child, 64).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(_, ..) => break
      @source.JsonSourceFailed(_, ..) => fail("original source refused")
    }
  }
  finish_program_json_preparation(child).unwrap()
  (parent, child, input)
}

///|
fn request_handoff_fixture_cleanup(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
) -> Unit raise {
  // Only after the taken DATA's lexical consumer and synchronous aliases have
  // unwound. This explicit fixture invokes the existing original Resource
  // teardown; it is not the missing production next-child retirement API.
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(parent.capacity, input).unwrap(),
  )
  preparation_initial_cleanup(parent.initial).unwrap()
}

///|
test "cleared Source controller cannot let the original parent abort a transferred Program" {
  let (parent, child, input) = request_handoff_fixture()
  construct_program_json_preparation(child).unwrap()
  reconcile_program_json_preparation_structure(child).unwrap()
  let held = @resources.ledger_usage(parent.ledger)
  {
    let program = take_program_json_preparation_program(child).unwrap()
    clear_program_json_preparation(child).unwrap()
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    assert_eq(@resources.ledger_usage(parent.ledger), held)
    assert_eq(program.id, "request-json-é")
    assert_eq(@syntax.stage_count(program), 1)
    assert_true(child.source is None && child.program is None)
    assert_true(take_program_json_preparation_program(child) is Err(WrongPhase))
  }
  request_handoff_fixture_cleanup(parent, input)
}

///|
test "handoff clear controls keep the taken original index live through repeated clear" {
  let (parent, child, input) = request_handoff_fixture()
  let held = @resources.ledger_usage(parent.ledger)
  {
    let indexed = take_program_json_preparation_input(child).unwrap()
    let root = @syntax.program_input_cursor(indexed)
    clear_program_json_preparation(child).unwrap()
    clear_program_json_preparation(child).unwrap()
    assert_true(child.phase == Transferred)
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    assert_eq(@resources.ledger_usage(parent.ledger), held)
    let (_, id) = @decode.field_at(root, 1).unwrap()
    assert_eq(@decode.text(id), Ok("request-json-é"))
    assert_true(take_program_json_preparation_input(child) is Err(WrongPhase))
  }
  request_handoff_fixture_cleanup(parent, input)
}

///|
test "handoff clear controls retain legitimate pre-transfer parent retirement" {
  let (parent, child, _) = request_handoff_fixture()
  let before = @resources.ledger_usage(parent.ledger)
  clear_program_json_preparation(child).unwrap()
  clear_program_json_preparation(child).unwrap()
  assert_true(child.phase == Retired)
  abort_request_preparation_after_cleanup(parent).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  let after = @resources.ledger_usage(parent.ledger)
  assert_true(parent.phase == Closed)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.planning_work, before.planning_work)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.live_reservations, 0)
}

///|
test "restored Local Request retains consumed Ledger history before preparation" {
  let input = [1]
  let policy = client_local_resource_policy()
  let original = @resources.create_ledger(
    client_local_preparation_initial_limits(policy).unwrap(),
  ).unwrap()
  @resources.charge_planning(original, 19).unwrap()
  let spent_capacity = @resources.reserve_capacity(original, 32768L, 0L).unwrap()
  @resources.settle_capacity(original, spent_capacity).unwrap()
  let first = @resources.reserve_attempt(original, 0L, 0L, 0L).unwrap()
  @resources.consume_reserved_attempt(original, first).unwrap()
  @resources.settle_reservation(original, first).unwrap()
  let saved = @resources.capture_quiescent_ledger_state(original).unwrap()
  let wire = @resources.encode_ledger_continuation_state(saved).unwrap()
  assert_true(
    admit_installed_debug_ledger_wire(" " + wire) is Err(InvalidRecord),
  )
  let decoded = admit_installed_debug_ledger_wire(wire).unwrap()
  let initial = request_parent_fixture(input)
  assert_true(
    begin_restored_request_preparation(initial, [1], policy, decoded)
    is Err(Initial(ForeignOriginal)),
  )
  let owner = match
    begin_restored_request_preparation(initial, input, policy, decoded) {
    Ok(owner) => owner
    Err(issue) => fail(@debug.to_string(issue))
  }
  let usage = @resources.ledger_usage(owner.ledger)
  assert_eq(usage.planning_work, 19)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.peak_retention_bytes, 32768L)
  assert_true(usage.reserved_retention_bytes > 0L)
  assert_true(
    owner.initial is NodeRequestInitial(retained) &&
    physical_equal(retained, initial),
  )
  reserve_request_snapshot(owner, input, 16L, 2L).unwrap()
  @resources.charge_planning(owner.ledger, 3).unwrap()
  let next = @resources.reserve_attempt(owner.ledger, 0L, 0L, 0L).unwrap()
  assert_eq(
    @resources.reservation_serial(next),
    @resources.reservation_serial(first) + 1,
  )
  @resources.consume_reserved_attempt(owner.ledger, next).unwrap()
  @resources.settle_reservation(owner.ledger, next).unwrap()
  abort_request_preparation_after_cleanup(owner).unwrap()
  let after = @resources.ledger_usage(owner.ledger)
  assert_eq(after.planning_work, 22)
  assert_eq(after.attempts, 2)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.live_reservations, 0)
}
