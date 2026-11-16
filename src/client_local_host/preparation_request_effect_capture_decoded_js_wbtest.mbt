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
  let remaining = @resources.remaining_preparation_phase_work_continuation64(
    work,
  ).unwrap()
  @resources.spend_preparation_phase_work_continuation64(work, remaining).unwrap()
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
test "cold decoded capture refines escaped record Strings on one original Read and spent Work phase" {
  let (_, request, definition) = capture_recovery_originals()
  let item : Json = { "k": "{\"x\":0,\"y\":1}" }
  let item = item.stringify()
  let body = "[" + (item + ",").repeat(4000) + item + "]"
  let captured : Json = { "body": body }
  let captured = captured.stringify()
  let document : Json = {
    "run_definition": @publication.publication_contract_json(definition),
    "captured_run": captured,
    "preview": body,
    "padding": "p".repeat(1800000),
  }
  let wire = document.stringify()
  let envelope : Json = {
    "version": "actql-private-publication-evidence/0.1",
    "nonce": "AA==",
    "tag": "AA==",
    "ciphertext": "A".repeat((wire.length() * 4 + 2) / 3),
  }
  let envelope = envelope.stringify()
  let input = [197]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let expected_work : Ref[@resources.PreparationPhaseWorkContinuation64?] = Ref(
    None,
  )
  let same_work = Ref(true)
  let targets : Array[Int64] = []
  let reentry = Ref(false)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if selected.val is Some(owner) && owner.phase == Selecting {
        if expected_work.val is Some(work) &&
          owner.program_domain_compilation_inputs
          is Some(RequestEffectCaptureRecovery(_, _, Some(material))) {
          same_work.val = same_work.val &&
            material.work is Some(current) &&
            physical_equal(current, work)
        }
        if owner.program_domain_quote is Some((retained, _)) {
          targets.push(retained)
        }
        reentry.val = reserve_request_effect_capture_decoded(
            owner, input, request, definition, "{}",
          )
          is Err(ForeignOriginal)
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(owner)
  let original = owner.capacity
  let limits = @resources.ledger_limits(owner.ledger)
  assert_eq(limits.retained_bytes, 536870912L)
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
  reserve_request_effect_capture_envelope(
    owner, input, request, definition, envelope,
  ).unwrap()
  let material = request_effect_capture_material(
    owner, input, request, definition,
  ).unwrap()
  let work = material.work.unwrap()
  expected_work.val = Some(work)
  @resources.resume_preparation_phase_work_continuation64(work).unwrap()
  let remaining = @resources.remaining_preparation_phase_work_continuation64(
    work,
  ).unwrap()
  @resources.return_preparation_phase_work_continuation64(work).unwrap()
  let coarse = effect_capture_wire_nodes(wire).unwrap()
  // This actual nested spelling reproduces the old refusal without changing
  // the original Request budget or making its small outer node count policy.
  let old_decoded = request_effect_capture_decoded_capacity(
    wire.length(),
    coarse,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(old_decoded) >
    limits.retained_bytes,
  )
  let before = @resources.ledger_usage(owner.ledger)
  let before_target = owner.program_domain_quote.unwrap().0
  targets.clear()
  let decoded = reserve_request_effect_capture_decoded(
    owner, input, request, definition, wire,
  )
  let after = @resources.ledger_usage(owner.ledger)
  let old_read = request_effect_capture_recovery_capacity(
    envelope.length(),
    @publication.publication_contract_json(definition).length(),
    material.max_wire_bytes,
    material.max_nodes,
    material.max_depth,
    staged_envelope=true,
    envelope_nodes=material.envelope_nodes,
    plaintext_bytes=material.plaintext_bytes,
    envelope_units=envelope.length(),
  ).unwrap()
  let old_total = standard_create_sum_capacities([old_read, old_decoded]).unwrap()
  println(
    "cold capture census: units=\{wire.length()} coarse=\{coarse} refined=\{@debug.to_string(material.decoded_nodes)} oldR=\{@execution.execution_capacity_retained_bytes(old_total)} oldE=\{@execution.execution_capacity_execution_bytes(old_total)} beforeR=\{before.reserved_retention_bytes} beforeE=\{before.reserved_execution_bytes} afterR=\{after.reserved_retention_bytes} afterE=\{after.reserved_execution_bytes}",
  )
  match decoded {
    Ok(_) => ()
    Err(issue) =>
      fail(
        "cold decoded refusal: " +
        @debug.to_string(issue) +
        " targets=" +
        @debug.to_string(targets),
      )
  }
  assert_true(physical_equal(owner.capacity, original))
  assert_true(physical_equal(material.work.unwrap(), work))
  assert_true(same_work.val)
  assert_eq(material.nodes, Some(coarse))
  assert_true(coarse > material.max_nodes)
  assert_true(material.decoded_nodes.unwrap() < coarse)
  assert_true(after.reserved_retention_bytes <= limits.retained_bytes)
  assert_true(after.reserved_execution_bytes <= limits.execution_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_true(reentry.val)
  // Observe the actual same-owner resize targets, rather than pinning calls
  // or a private quote number. Preflight construction precedes final backing.
  let final_target = owner.program_domain_quote.unwrap().0
  assert_true(
    targets.any(value => value > before_target && value < final_target),
  )
  assert_true(targets.any(value => value == final_target))
  @resources.resume_preparation_phase_work_continuation64(work).unwrap()
  let next = @resources.remaining_preparation_phase_work_continuation64(work).unwrap()
  assert_true(next < remaining)
  @resources.return_preparation_phase_work_continuation64(work).unwrap()
  assert_true(
    reserve_request_effect_capture_decoded(
      owner,
      input,
      request,
      definition,
      wire + " ",
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), after)
  // The memory census never admits the embedded fabricated contract.
  assert_true(
    admit_request_effect_captured_run(
      owner, input, request, definition, captured,
    )
    is Err(Policy),
  )
  assert_true(material.captured is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(material.work is None)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
}

///|
test "cold decoded census keeps later normalization funded for every actual key" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [198]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let wire = "{\"" + "k".repeat(2000000) + "\":null}"
  let envelope : Json = {
    "version": "actql-private-publication-evidence/0.1",
    "nonce": "AA==",
    "tag": "AA==",
    "ciphertext": "A".repeat((wire.length() * 4 + 2) / 3),
  }
  let envelope = envelope.stringify()
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
  reserve_request_effect_capture_envelope(
    owner, input, request, definition, envelope,
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_effect_capture_decoded(
      owner, input, request, definition, wire,
    )
    is Err(Capacity(_)),
  )
  let material = request_effect_capture_material(
    owner, input, request, definition,
  ).unwrap()
  // The raw census succeeded; its actual key cannot borrow a small value-key
  // assumption. The later original normalizer still refuses its full quote.
  assert_true(material.decoded_nodes is Some(_))
  assert_eq(material.decoded_key_units, Some(2000000))
  assert_eq(material.decoded_key_total, Some(2000000))
  assert_true(material.wire is None)
  let prefix = @resources.ledger_usage(owner.ledger)
  assert_true(prefix.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(prefix.live_reservations, before.live_reservations)
  assert_eq(prefix.transferred_bytes, before.transferred_bytes)
  assert_true(
    reserve_request_effect_capture_decoded(
      owner,
      input,
      request,
      definition,
      wire + " ",
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), prefix)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(material.work is None)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
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
