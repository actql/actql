///|
test "cold decoded capture grows the SAME Request before parse and keeps exact wire DATA" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [191]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original = owner.capacity
  reserve_request_effect_capture_recovery(
    owner, input, request, definition, 256, 10000, 1000, 64,
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  let wire = "{\"bodies\":[{\"x\":1},{\"x\":2}]}"
  reserve_request_effect_capture_decoded(
    owner, input, request, definition, wire,
  ).unwrap()
  let held = @resources.ledger_usage(owner.ledger)
  assert_true(physical_equal(owner.capacity, original))
  assert_true(held.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(held.reserved_execution_bytes > before.reserved_execution_bytes)
  assert_eq(held.live_reservations, before.live_reservations)
  assert_eq(held.attempts, before.attempts)
  assert_eq(held.transferred_bytes, before.transferred_bytes)
  let material = request_effect_capture_material(
    owner, input, request, definition,
  ).unwrap()
  let work = material.work.unwrap()
  reserve_request_effect_capture_decoded(
    owner, input, request, definition, wire,
  ).unwrap()
  assert_true(physical_equal(material.work.unwrap(), work))
  assert_eq(@resources.ledger_usage(owner.ledger), held)
  assert_true(
    reserve_request_effect_capture_decoded(
      owner, input, request, definition, "{}",
    )
    is Err(_),
  )
  assert_true(material.wire == Some(wire))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(material.work is None)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
}

///|
test "cold decoded capture refuses foreign input current and small original capacity before admission" {
  let (_, request, definition) = capture_recovery_originals()
  let (_, foreign_request, foreign_definition) = capture_recovery_originals(
    run_id="other-cold",
  )
  let input = [192]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_effect_capture_recovery(
    owner, input, request, definition, 128, 10000, 1000, 64,
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_effect_capture_decoded(
      owner,
      [192],
      request,
      definition,
      "{}",
    )
    is Err(_),
  )
  assert_true(
    reserve_request_effect_capture_decoded(
      owner, input, foreign_request, foreign_definition, "{}",
    )
    is Err(_),
  )
  current.val = false
  assert_true(
    reserve_request_effect_capture_decoded(
      owner, input, request, definition, "{}",
    )
    is Err(_),
  )
  assert_true(
    request_effect_capture_material(owner, input, request, definition).unwrap().wire
    is None,
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  abort_request_preparation_after_cleanup(owner).unwrap()
  let small_input = [193]
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let small = begin_request_preparation(
    request_parent_fixture(
      small_input,
      initial_limits=Some({
        ..limits,
        retained_bytes: 1500000L,
        execution_bytes: 1500000L,
      }),
    ),
    small_input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_effect_capture_recovery(
    small, small_input, request, definition, 512, 10000, 1000, 64,
  ).unwrap()
  let before = @resources.ledger_usage(small.ledger)
  let dense = "[" + "{},".repeat(160) + "{}]"
  assert_true(
    reserve_request_effect_capture_decoded(
      small, small_input, request, definition, dense,
    )
    is Err(Capacity(_)),
  )
  assert_true(
    request_effect_capture_material(small, small_input, request, definition).unwrap().wire
    is None,
  )
  assert_eq(@resources.ledger_usage(small.ledger), before)
  abort_request_preparation_after_cleanup(small).unwrap()
}

///|
test "cold capture one Work phase is consumed on failed admission and never refilled" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [194]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let record : Json = {
    "run_definition": @publication.publication_contract_json(definition),
    "captured_run": "{}",
  }
  let wire = record.stringify()
  reserve_request_effect_capture_recovery(
    owner,
    input,
    request,
    definition,
    wire.length() + 128,
    10000,
    1000,
    64,
  ).unwrap()
  reserve_request_effect_capture_decoded(
    owner, input, request, definition, wire,
  ).unwrap()
  let material = request_effect_capture_material(
    owner, input, request, definition,
  ).unwrap()
  let work = material.work.unwrap()
  assert_true(
    admit_request_effect_captured_run(owner, input, request, definition, "{}")
    is Err(Policy),
  )
  assert_true(physical_equal(material.work.unwrap(), work))
  @resources.resume_preparation_phase_work_continuation64(work).unwrap()
  // Consume the real SAME receipt's remaining work, rather than forging a
  // numeric marker or giving the next constructor another allowance.
  let maximum = request_effect_capture_phase_work_bound(
    owner, input, request, definition, wire,
  ).unwrap()
  let consumed = wire.length().to_int64() * 5L
  @resources.spend_preparation_phase_work_continuation64(
    work,
    maximum - consumed,
  ).unwrap()
  @resources.return_preparation_phase_work_continuation64(work).unwrap()
  assert_true(
    admit_request_effect_captured_run(owner, input, request, definition, "{}")
    is Err(Work(@resources.WorkLimit)),
  )
  assert_true(physical_equal(material.work.unwrap(), work))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(material.work is None)
}

///|
test "staged cold envelope funds bytes then lexical nodes and shares exactly one Work phase with plaintext" {
  let (_, request, definition) = capture_recovery_originals()
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let selected = {
    ..limits,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  }
  let document : Json = {
    "version": "actql-private-publication-evidence/0.1",
    "nonce": "AA==",
    "tag": "AA==",
    "ciphertext": "A".repeat(4096),
  }
  let envelope = document.stringify()
  let legacy_input = [195]
  let legacy = begin_request_preparation(
    request_parent_fixture(legacy_input, initial_limits=Some(selected)),
    legacy_input,
    client_local_resource_policy(),
  ).unwrap()
  assert_true(
    reserve_request_effect_capture_recovery(
      legacy,
      legacy_input,
      request,
      definition,
      envelope.length(),
      10000,
      1000,
      64,
    )
    is Err(Capacity(_)),
  )
  abort_request_preparation_after_cleanup(legacy).unwrap()
  let input = [196]
  let owner = begin_request_preparation(
    request_parent_fixture(input, initial_limits=Some(selected)),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_effect_capture_encrypted(
    owner,
    input,
    request,
    definition,
    envelope.length(),
    10000,
    1000,
    64,
  ).unwrap()
  assert_true(
    reserve_request_effect_capture_decoded(
      owner, input, request, definition, "{}",
    )
    is Err(ForeignOriginal),
  )
  let before = @resources.ledger_usage(owner.ledger)
  reserve_request_effect_capture_envelope(
    owner, input, request, definition, envelope,
  ).unwrap()
  let material = request_effect_capture_material(
    owner, input, request, definition,
  ).unwrap()
  let receipt = material.work.unwrap()
  assert_true(material.envelope_nodes is Some(_))
  assert_true(
    @resources.ledger_usage(owner.ledger).reserved_execution_bytes >
    before.reserved_execution_bytes,
  )
  assert_true(
    reserve_request_effect_capture_envelope(
      owner, input, request, definition, "{}",
    )
    is Err(ForeignOriginal),
  )
  reserve_request_effect_capture_decoded(
    owner, input, request, definition, "{}",
  ).unwrap()
  assert_true(physical_equal(material.work.unwrap(), receipt))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(material.work is None)
  assert_true(
    @resources.resume_preparation_phase_work_continuation64(receipt)
    is Err(@resources.Closed),
  )
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
}
