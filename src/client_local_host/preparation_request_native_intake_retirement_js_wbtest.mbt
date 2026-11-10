///|
// Source-level original reservation controls. No IO/Native/Host close is
// inferred from this completed-constructor accounting transition.
test "completed Native intake retains actual same output and spends no new grant" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1\"},\"parameters\":null}",
    8192, 128, 16,
  ).unwrap()
  reserve_request_native_intake_wire(parent, input, 65536).unwrap()
  let capacity = parent.capacity
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    retain_request_submitted_intent(parent, input, intent) is Err(WrongPhase),
  )
  assert_true(
    finish_request_native_intake_wire(parent, [1], intent)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  finish_request_native_intake_wire(parent, input, intent).unwrap()
  let after = @resources.ledger_usage(parent.ledger)
  assert_true(after.reserved_retention_bytes < before.reserved_retention_bytes)
  assert_true(after.reserved_execution_bytes < before.reserved_execution_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.attempts, before.attempts)
  assert_true(physical_equal(parent.capacity, capacity))
  assert_true(physical_equal(parent.submitted_intent.unwrap(), intent))
  assert_true(
    reserve_request_native_intake_wire(parent, input, 131072) is Err(WrongPhase),
  )
  assert_true(
    finish_request_native_intake_wire(parent, input, intent) is Err(WrongPhase),
  )
  retain_request_submitted_intent(parent, input, intent).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "failed Native intake return retains same output and original debit before exact retry" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1\"},\"parameters\":null}",
    8192, 128, 16,
  ).unwrap()
  let other = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 2\"},\"parameters\":null}",
    8192, 128, 16,
  ).unwrap()
  reserve_request_native_intake_wire(parent, input, 65536).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let work = @resources.begin_preparation_phase_work64(
    parent.capacity,
    input,
    @resources.HeaderInspection,
    1L,
  ).unwrap()
  assert_true(
    finish_request_native_intake_wire(parent, input, intent)
    is Err(Capacity(WorkActive)),
  )
  assert_true(physical_equal(parent.submitted_intent.unwrap(), intent))
  assert_true(parent.native_intake_base is Some(_))
  assert_eq(parent.native_intake_wire_bytes, 65536)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(
    finish_request_native_intake_wire(parent, input, other)
    is Err(ForeignOriginal),
  )
  assert_true(
    reserve_request_native_intake_wire(parent, input, 131072) is Err(WrongPhase),
  )
  assert_true(
    retain_request_submitted_intent(parent, input, intent) is Err(WrongPhase),
  )
  @resources.finish_preparation_phase_work64(work).unwrap() |> ignore
  finish_request_native_intake_wire(parent, input, intent).unwrap()
  match retain_request_submitted_intent(parent, input, intent) {
    Ok(_) => ()
    Err(Work(issue)) => fail("retained input work: " + @debug.to_string(issue))
    Err(Capacity(issue)) =>
      fail("retained input capacity: " + @debug.to_string(issue))
    Err(WrongPhase) => fail("retained input wrong phase")
    Err(ForeignOriginal) => fail("retained input foreign original")
    Err(_) => fail("retained input other issue")
  }
  assert_true(physical_equal(parent.submitted_intent.unwrap(), intent))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
