///|
// Real existing Run/Read/Ledger constructors with explicit geometry inputs.
// These tests supply no AEAD, physical Store completion or captured authority.
// The trusted completion call is the tested component seam, not a new ACK.
fn capture_validation_geometry_fixture(
  current? : () -> Unit = () => (),
) -> (
  ClientInstalledManagedRun,
  @resources.Ledger,
  ClientInstalledEffectCaptureRecovery,
  @resources.LedgerUsage,
) raise {
  let (run, ledger, read) = installed_cold_read_fixture(current~)
  let envelope = "{\"ciphertext\":\"" + "A".repeat(400000) + "\"}"
  let inner = "{\"rows\":[{\"id\":\"original\",\"text\":\"😀漢字\"}]}"
  let plaintext = @identity.stringify_value(
    @identity.from_json(
      Json::object({
        "captured_run": Json::string(inner),
        "preview": Json::string(inner),
        "other": Json::string("retained original DATA"),
      }),
      100,
      10,
      10000,
    ),
    10000,
    100,
    10,
  )
  reserve_installed_effect_capture_encrypted(read, envelope.length()).unwrap()
  reserve_installed_effect_capture_envelope(read, envelope).unwrap()
  reserve_installed_effect_capture_decoded(read, plaintext).unwrap()
  assert_true(read.material_ready)
  let physical_peak = @resources.ledger_usage(ledger)
  complete_installed_effect_capture_recovery(read).unwrap()
  assert_true(read.material_envelope_wire == Some(envelope))
  assert_true(read.material_wire == Some(plaintext))
  (run, ledger, read, physical_peak)
}

///|
// Definition re-admission remains the existing full fixed constructor. Only
// the ended material packet is removed from this selected validation path.
fn capture_validation_definition_delta(
  read : ClientInstalledEffectCaptureRecovery,
) -> Int64 {
  let definition = read.definition.unwrap()
  let wire = @publication.publication_contract_json(definition)
  let (_, nodes, _) = @publication.publication_contract_wire_usage(definition).unwrap()
  @execution.execution_capacity_inventory_bytes([
    {
      unit: ValueNodeSlots,
      count: (wire.length() - nodes).to_int64(),
      copies: 1,
    },
  ]).unwrap()
}

///|
fn close_capture_validation_fixture(
  run : ClientInstalledManagedRun,
  ledger : @resources.Ledger,
  read : ClientInstalledEffectCaptureRecovery,
) raise {
  retire_installed_effect_capture_recovery(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "completed Read validation keeps every returned alias and same Work without reacquiring physical buffers" {
  let (run, ledger, read, physical_peak) = capture_validation_geometry_fixture()
  let material = read.material.unwrap()
  let fixed = read.fixed.unwrap()
  let wire = read.material_wire.unwrap()
  let envelope = read.material_envelope_wire.unwrap()
  let nodes = read.material_nodes
  let control = run.effect_operation_controls.unwrap()
  let receipt = control.dependency_work.unwrap()
  @resources.resume_preparation_phase_work_continuation64(receipt).unwrap()
  let remaining = @resources.remaining_preparation_phase_work_continuation64(
    receipt,
  ).unwrap()
  @resources.spend_preparation_phase_work_continuation64(receipt, 7L).unwrap()
  @resources.return_preparation_phase_work_continuation64(receipt).unwrap()
  let completed = @resources.ledger_usage(ledger)
  begin_installed_effect_capture_validation(read).unwrap()
  let validating = @resources.ledger_usage(ledger)
  assert_eq(
    validating.reserved_retention_bytes,
    completed.reserved_retention_bytes +
    capture_validation_definition_delta(read),
  )
  assert_true(
    validating.reserved_execution_bytes > completed.reserved_execution_bytes,
  )
  assert_true(
    validating.reserved_execution_bytes < physical_peak.reserved_execution_bytes,
  )
  assert_eq(validating.planning_work, completed.planning_work)
  assert_eq(validating.attempts, completed.attempts)
  assert_eq(validating.live_reservations, completed.live_reservations)
  assert_true(physical_equal(read.material.unwrap(), material))
  assert_true(physical_equal(read.fixed.unwrap(), fixed))
  assert_true(physical_equal(control.dependency_work.unwrap(), receipt))
  assert_eq(read.material_wire, Some(wire))
  assert_eq(read.material_envelope_wire, Some(envelope))
  assert_eq(read.material_nodes, nodes)
  @resources.resume_preparation_phase_work_continuation64(receipt).unwrap()
  assert_eq(
    @resources.remaining_preparation_phase_work_continuation64(receipt),
    Ok(remaining - 7L),
  )
  @resources.return_preparation_phase_work_continuation64(receipt).unwrap()
  // Exercise the SAME genuinely admitted Definition under this constructor
  // packet. Parsing the retained geometry below grants no captured authority.
  let definition = read.definition.unwrap()
  let definition_wire = @publication.publication_contract_json(definition)
  let (definition_bytes, definition_nodes, definition_depth) = @publication.publication_contract_wire_usage(
    definition,
  ).unwrap()
  let admitted = @publication.admit_publication_contract(
    "run_definition", definition_wire, definition_bytes, definition_nodes, definition_depth,
  ).unwrap()
  assert_eq(@publication.publication_contract_json(admitted), definition_wire)
  let parsed = @source.parse_json(wire, {
    max_input_bytes: read.material_plaintext_bytes.unwrap(),
    max_nodes: read.material_nodes.unwrap(),
    max_depth: read.max_depth,
  }).unwrap()
  let record = @identity.from_source(
    parsed,
    read.material_nodes.unwrap(),
    read.max_depth,
    read.material_plaintext_bytes.unwrap(),
    data_keys=true,
  )
  assert_true(
    @identity.object_field(record, "captured_run") is Some(@identity.String(_)),
  )
  complete_installed_effect_capture_recovery(read).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    completed.reserved_retention_bytes,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    completed.reserved_execution_bytes,
  )
  close_capture_validation_fixture(run, ledger, read)
}

///|
test "validation exact execution boundary succeeds and one short preserves its failed original prefix" {
  let (probe_run, probe_ledger, probe, _) = capture_validation_geometry_fixture()
  let probe_completed = @resources.ledger_usage(probe_ledger)
  begin_installed_effect_capture_validation(probe).unwrap()
  let scratch = @resources.ledger_usage(probe_ledger).reserved_execution_bytes -
    probe_completed.reserved_execution_bytes
  assert_true(scratch > 0L)
  complete_installed_effect_capture_recovery(probe).unwrap()
  close_capture_validation_fixture(probe_run, probe_ledger, probe)
  // Each failure retains its own consumed completion receipt. A fresh fixture
  // supplies the exact case; an unsuccessful constructor invents no new ACK.
  for shortage in [1L, 0L] {
    let (run, ledger, read, _) = capture_validation_geometry_fixture()
    let completed = @resources.ledger_usage(ledger)
    let definition_delta = capture_validation_definition_delta(read)
    let material = read.material.unwrap()
    let fixed = read.fixed.unwrap()
    let receipt = run.effect_operation_controls.unwrap().dependency_work.unwrap()
    let free = @resources.ledger_limits(ledger).execution_bytes -
      completed.reserved_execution_bytes
    let pressure = @resources.reserve_capacity(
      ledger,
      0L,
      free - scratch + shortage,
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = begin_installed_effect_capture_validation(read)
    if shortage == 1L {
      assert_true(result is Err(Ledger(@resources.ExecutionLimit)))
      // Fixed Definition growth preceded material refusal and stays owned.
      // Neither that successful prefix nor the completed material is refunded.
      assert_eq(@resources.ledger_usage(ledger), {
        ..before,
        reserved_retention_bytes: before.reserved_retention_bytes +
        definition_delta,
        reserved_execution_bytes: before.reserved_execution_bytes +
        definition_delta,
      })
    } else {
      result.unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        @resources.ledger_limits(ledger).execution_bytes,
      )
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        before.reserved_retention_bytes + definition_delta,
      )
      complete_installed_effect_capture_recovery(read).unwrap()
    }
    assert_true(physical_equal(read.material.unwrap(), material))
    assert_true(physical_equal(read.fixed.unwrap(), fixed))
    assert_true(
      physical_equal(
        run.effect_operation_controls.unwrap().dependency_work.unwrap(),
        receipt,
      ),
    )
    @resources.settle_capacity(ledger, pressure).unwrap()
    if shortage == 1L {
      assert_true(begin_installed_effect_capture_validation(read) is Err(_))
    }
    close_capture_validation_fixture(run, ledger, read)
  }
}

///|
test "full physical Read keeps its peak and a failed restart cannot reuse completed validation receipt" {
  // Separate fixtures preserve the failed physical restart. A failed begin is
  // never followed by a manufactured completion or restored success receipt.
  let (run, ledger, read, _) = capture_validation_geometry_fixture()
  let completed = @resources.ledger_usage(ledger)
  begin_installed_effect_capture_validation(read).unwrap()
  let scratch = @resources.ledger_usage(ledger).reserved_execution_bytes -
    completed.reserved_execution_bytes
  complete_installed_effect_capture_recovery(read).unwrap()
  let limit = @resources.ledger_limits(ledger).execution_bytes
  let pressure = @resources.reserve_capacity(
    ledger,
    0L,
    limit - completed.reserved_execution_bytes - scratch,
  ).unwrap()
  let material = read.material.unwrap()
  let fixed = read.fixed.unwrap()
  assert_true(
    begin_installed_effect_capture_recovery(read)
    is Err(Ledger(@resources.ExecutionLimit)),
  )
  assert_true(physical_equal(read.material.unwrap(), material))
  assert_true(physical_equal(read.fixed.unwrap(), fixed))
  @resources.settle_capacity(ledger, pressure).unwrap()
  assert_true(begin_installed_effect_capture_validation(read) is Err(_))
  close_capture_validation_fixture(run, ledger, read)
  let (run, ledger, read) = installed_cold_read_fixture()
  // No previous successful completion exists on this distinct Read.
  assert_true(begin_installed_effect_capture_validation(read) is Err(_))
  close_capture_validation_fixture(run, ledger, read)
}

///|
test "validation preserves foreign current reentry retirement and original cleanup responsibility" {
  let (foreign_run, foreign_ledger, foreign, _) = capture_validation_geometry_fixture()
  for selected in [1, 2, 3] {
    let owner : Ref[ClientInstalledEffectCaptureRecovery?] = Ref(None)
    let mode = Ref(0)
    let reentry = Ref(false)
    let (run, ledger, read, _) = capture_validation_geometry_fixture(current=() => {
      if mode.val == 1 {
        capture_recovery_current_refusal()
      }
      if mode.val == 2 {
        reentry.val = begin_installed_effect_capture_validation(
            owner.val.unwrap(),
          )
          is Err(Retired)
      }
      if mode.val == 3 {
        owner.val.unwrap().closing = true
      }
    })
    owner.val = Some(read)
    let copied = { ..read, ledger: Some(foreign_ledger), }
    let before = @resources.ledger_usage(ledger)
    let foreign_before = @resources.ledger_usage(foreign_ledger)
    assert_true(begin_installed_effect_capture_validation(copied) is Err(_))
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
    mode.val = selected
    let result = begin_installed_effect_capture_validation(read)
    if selected == 2 {
      result.unwrap()
      assert_true(reentry.val)
      complete_installed_effect_capture_recovery(read).unwrap()
    } else {
      assert_true(result is Err(_))
      assert_eq(@resources.ledger_usage(ledger), before)
    }
    mode.val = 0
    // This cut enables disposal only; no constructor resumes after closing.
    read.closing = false
    close_capture_validation_fixture(run, ledger, read)
    assert_true(begin_installed_effect_capture_validation(read) is Err(Retired))
  }
  close_capture_validation_fixture(foreign_run, foreign_ledger, foreign)
}

///|
test "Definition-only completion cannot authorize validation of the first later material" {
  let (run, ledger, read) = installed_cold_read_fixture()
  assert_true(read.material is None)
  complete_installed_effect_capture_recovery(read).unwrap()
  assert_true(read.material is None)
  // Geometry component seam only: no AEAD, Store ACK or captured authority.
  // A completed Definition predates this distinct material construction.
  let envelope = "{\"ciphertext\":\"" + "A".repeat(2048) + "\"}"
  reserve_installed_effect_capture_encrypted(read, envelope.length()).unwrap()
  assert_true(
    begin_installed_effect_capture_validation(read) is Err(ForeignOriginal),
  )
  reserve_installed_effect_capture_envelope(read, envelope).unwrap()
  assert_true(
    begin_installed_effect_capture_validation(read) is Err(ForeignOriginal),
  )
  reserve_installed_effect_capture_decoded(read, "{\"geometry\":true}").unwrap()
  assert_true(read.material_ready)
  assert_true(
    begin_installed_effect_capture_validation(read) is Err(ForeignOriginal),
  )
  complete_installed_effect_capture_recovery(read).unwrap()
  begin_installed_effect_capture_validation(read).unwrap()
  complete_installed_effect_capture_recovery(read).unwrap()
  close_capture_validation_fixture(run, ledger, read)
}
