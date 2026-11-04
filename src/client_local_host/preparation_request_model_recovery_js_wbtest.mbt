///|
test "saved Model constructors share original restoration reservation without a new compiler or Run" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [181]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  let calls = Ref(0)
  let observed = Ref(true)
  for bodies in [["{\"saved\":true}"], ["{}", "{}", "{}"], ["{}", "{}", "{}"]] {
    let previous = @resources.ledger_usage(owner.ledger)
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      bodies.length(),
      index => {
        observed.val = observed.val && owner.phase == Selecting
        observed.val = observed.val &&
          reserve_request_model_recovery_materials(
            owner,
            input,
            request,
            definition,
            0,
            _ => "",
            0,
          )
          is Err(ForeignOriginal)
        calls.val += 1
        bodies[index]
      },
      bodies.length(),
    ).unwrap()
    let after = @resources.ledger_usage(owner.ledger)
    assert_true(
      after.reserved_retention_bytes > previous.reserved_retention_bytes,
    )
    assert_true(
      after.reserved_execution_bytes >= previous.reserved_execution_bytes,
    )
    assert_eq(after.live_reservations, before.live_reservations)
    assert_eq(after.attempts, before.attempts)
    assert_eq(after.transferred_bytes, before.transferred_bytes)
    assert_true(physical_equal(owner.capacity, original))
    assert_true(
      owner.program_capacity is None && owner.compiled_program is None,
    )
    assert_true(
      owner.program_compilation is None && owner.program_check is None,
    )
    assert_true(owner.phase == ModelRecovery)
  }
  assert_eq(calls.val, 7)
  assert_true(observed.val)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  assert_true(owner.phase == Closed)
}

///|
test "saved Model reservation rejects foreign pair and current refusal before reading another material" {
  let (_, request, definition) = capture_recovery_originals()
  let (_, foreign, foreign_definition) = capture_recovery_originals()
  let input = [182]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    request,
    definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let retained = @resources.ledger_usage(owner.ledger)
  let calls = Ref(0)
  for
    (selected_input, selected_request, selected_definition) in [
      ([182], request, definition),
      (input, foreign, definition),
      (input, request, foreign_definition),
    ] {
    assert_true(
      reserve_request_model_recovery_materials(
        owner,
        selected_input,
        selected_request,
        selected_definition,
        1,
        _ => {
          calls.val += 1
          "{}"
        },
        1,
      )
      is Err(ForeignOriginal),
    )
    assert_eq(@resources.ledger_usage(owner.ledger), retained)
  }
  current.val = false
  assert_true(
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      1,
      _ => {
        calls.val += 1
        "{}"
      },
      1,
    )
    is Err(Capacity(_)),
  )
  assert_eq(calls.val, 0)
  current.val = true
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "saved Model growth failure keeps original capacity and physical cleanup pending" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [183]
  let pending = Ref(false)
  let owner = begin_request_preparation(
    request_parent_fixture(input, pending=() => pending.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    request,
    definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let previous = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      1,
      _ => "x".repeat(1000000),
      1,
    )
    is Err(Capacity(_)),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), previous)
  pending.val = true
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(_))
  assert_true(owner.phase == Retiring && owner.input is None)
  pending.val = false
  // A later empty callback cannot fabricate the original stop ACK.
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}
