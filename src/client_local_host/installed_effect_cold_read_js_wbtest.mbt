///|
fn installed_cold_read_fixture(
  current? : () -> Unit = () => (),
) -> (
  ClientInstalledManagedRun,
  @resources.Ledger,
  ClientInstalledEffectCaptureRecovery,
) raise {
  let (prepared, request, _, run, ledger) = native_control_fixture(current~)
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    request_program_module_manifests(),
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "scope", "cold-installed-read", "2026-10-25T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let read = prepare_installed_effect_capture_recovery(
    run, prepared, request, definition, 8000000, 100000, 64,
  ).unwrap()
  (run, ledger, read)
}

///|
test "cold installed Read funds encrypted bytes then actual nodes on one original publication Work" {
  let (run, ledger, read) = installed_cold_read_fixture()
  let control = run.effect_operation_controls.unwrap()
  assert_true(control.dependency_work is None)
  assert_true(control.dependency_inventory is None)
  // Constructor geometry only: this does not claim AEAD or a physical Store
  // ACK. The actual encrypted/cold workflow supplies those separate proofs.
  let envelope = "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"AA==\",\"tag\":\"AA==\",\"ciphertext\":\"" +
    "A".repeat(5000000) +
    "\"}"
  let before = @resources.ledger_usage(ledger)
  assert_true(
    reserve_installed_effect_capture_recovery(read, envelope.length())
    is Err(Ledger(@resources.RetentionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  reserve_installed_effect_capture_encrypted(read, envelope.length()).unwrap()
  let receipt = control.dependency_work.unwrap()
  assert_true(read.material_staged_envelope)
  let bytes_only = @resources.ledger_usage(ledger)
  assert_eq(bytes_only.planning_work, before.planning_work)
  assert_eq(bytes_only.attempts, before.attempts)
  assert_eq(bytes_only.reserved_attempts, before.reserved_attempts)
  reserve_installed_effect_capture_encrypted(read, envelope.length()).unwrap()
  assert_true(physical_equal(control.dependency_work.unwrap(), receipt))
  assert_eq(@resources.ledger_usage(ledger), bytes_only)
  reserve_installed_effect_capture_envelope(read, envelope).unwrap()
  assert_true(read.material_envelope_nodes is Some(nodes) && nodes < 100)
  assert_true(
    reserve_installed_effect_capture_envelope(read, "{}")
    is Err(ForeignOriginal),
  )
  reserve_installed_effect_capture_decoded(read, "{}").unwrap()
  assert_true(installed_effect_capture_prepared_available(read))
  // Availability grants no semantic shortcut: an unrelated captured body
  // still fails exact Definition/captured-wire correspondence.
  assert_true(
    admit_installed_effect_captured_run(read, "{}") is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, before.planning_work)
  retire_installed_effect_capture_recovery(read).unwrap()
  assert_true(physical_equal(control.dependency_work.unwrap(), receipt))
  retire_installed_managed_run(run).unwrap()
  assert_true(control.dependency_work is None)
  assert_true(
    @resources.resume_preparation_phase_work_continuation64(receipt)
    is Err(@resources.Closed),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "cold installed Read cannot restart spent Work or evade its original current fence" {
  let (run, ledger, read) = installed_cold_read_fixture()
  let envelope = "{\"ciphertext\":\"" + "A".repeat(1000) + "\"}"
  reserve_installed_effect_capture_encrypted(read, envelope.length()).unwrap()
  let control = run.effect_operation_controls.unwrap()
  let receipt = control.dependency_work.unwrap()
  let policy = @resources.ledger_limits(ledger)
  let maximum = 256L + (policy.retained_bytes + policy.execution_bytes) * 128L
  @resources.resume_preparation_phase_work_continuation64(receipt).unwrap()
  @resources.spend_preparation_phase_work_continuation64(receipt, maximum - 1L).unwrap()
  @resources.return_preparation_phase_work_continuation64(receipt).unwrap()
  assert_true(
    reserve_installed_effect_capture_envelope(read, envelope) is Err(_),
  )
  reserve_installed_effect_capture_encrypted(read, envelope.length()).unwrap()
  assert_true(physical_equal(control.dependency_work.unwrap(), receipt))
  assert_true(
    reserve_installed_effect_capture_envelope(read, envelope) is Err(_),
  )
  retire_installed_effect_capture_recovery(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  let armed = Ref(false)
  let (run, ledger, read) = installed_cold_read_fixture(current=() => {
    if armed.val {
      capture_recovery_current_refusal()
    }
  })
  let before = @resources.ledger_usage(ledger)
  armed.val = true
  assert_true(reserve_installed_effect_capture_encrypted(read, 1000) is Err(_))
  assert_true(read.material is None)
  assert_true(run.effect_operation_controls.unwrap().dependency_work is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  armed.val = false
  retire_installed_effect_capture_recovery(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "capture node bounds cover literal and multiply escaped Unicode trees with the real parser" {
  let cases = [
    "null", "true", "1", "\"scalar\"", "[]", "{}", "[0,true,null,{},[]]", "{\"a\":[1,true,null],\"b\":{\"x\":\"quoted\"}}",
    "\"\\u007b\\u0022x\\u0022\\u003a\\u005b1\\u002c\\u007b\\u007d\\u005d\\u007d\"",
    "{\"text\":\"\\u005c\\u005c\\u005c\\u0022\\n\\t\\ud83d\\ude00\"}",
  ]
  for original in cases {
    let mut wire = original
    for _ in 0..<5 {
      let upper = effect_capture_wire_nodes(wire).unwrap()
      let mut current = wire
      for _ in 0..<8 {
        let parsed = @source.parse_json_measured(current, {
          max_input_bytes: 2000000,
          max_nodes: upper,
          max_depth: 64,
        }).unwrap()
        assert_true(parsed.usage.nodes <= upper)
        match parsed.node.value {
          @source.String(inner) =>
            if @source.parse_json(inner, {
                max_input_bytes: 2000000,
                max_nodes: upper,
                max_depth: 64,
              })
              is Ok(_) {
              current = inner
            } else {
              break
            }
          _ => break
        }
      }
      wire = @identity.stringify_value(
        @identity.from_json(Json::string(wire), 1, 1, 2000000),
        2000000,
        1,
        1,
      )
    }
  }
  assert_true(
    @source.parse_json("[1,]", {
      max_input_bytes: 100,
      max_nodes: effect_capture_wire_nodes("[1,]").unwrap(),
      max_depth: 64,
    })
    is Err(_),
  )
}

///|
test "escaped capture scalar reserves once on the original 512MiB Read without promoting quote bytes to tree nodes" {
  let wire = @identity.stringify_value(
    @identity.from_json(Json::string("\"".repeat(400000)), 1, 1, 2000000),
    2000000,
    1,
    1,
  )
  let parsed = @source.parse_json_measured(wire, {
    max_input_bytes: 2000000,
    max_nodes: effect_capture_wire_nodes(wire).unwrap(),
    max_depth: 64,
  }).unwrap()
  assert_eq(parsed.usage.nodes, 1)
  let (run, ledger, read) = installed_cold_read_fixture()
  let before = @resources.ledger_usage(ledger)
  let envelope = "{\"ciphertext\":\"" + "A".repeat(1100000) + "\"}"
  // Geometry admission only. This deliberately makes no claim that a scalar
  // is a valid captured Run or that these bytes have a physical AEAD receipt.
  reserve_installed_effect_capture_encrypted(read, envelope.length()).unwrap()
  reserve_installed_effect_capture_envelope(read, envelope).unwrap()
  reserve_installed_effect_capture_decoded(read, wire).unwrap()
  assert_true(installed_effect_capture_prepared_available(read))
  assert_true(
    @resources.ledger_usage(ledger).reserved_execution_bytes <= 536870912L,
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, before.planning_work)
  assert_true(admit_installed_effect_captured_run(read, wire) is Err(_))
  retire_installed_effect_capture_recovery(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
