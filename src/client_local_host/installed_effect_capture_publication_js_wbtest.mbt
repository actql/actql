///|
// Same genuine Run/Read/Resource fixture, testing only the private byte-demand
// handoff. Its geometry is not a captured Run or a physical Store ACK. Public
// publication admission still requires the separately authenticated original.
fn enter_capture_publication_demand(
  read : ClientInstalledEffectCaptureRecovery,
  retained : Int64,
  workspace : Int64,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  read.material_completed = false
  read.transitioning = true
  preparation_module_call(
    () => grow_installed_effect_capture_publication(read, retained, workspace),
    () => read.transitioning = false,
  )
}

///|
test "publication metadata counts original lists and members independently of unrelated capture DATA" {
  // Quantity-only record geometry: null elements grant no contract/capture
  // authority. The production entrance uses its SAME authenticated record.
  let record = @identity.from_json(
    Json::object({
      "definitions": Json::array([Json::null()]),
      "artifacts": Json::array([Json::null()]),
      "derivations": Json::array([Json::null()]),
      "orderings": Json::array([Json::null()]),
      "retentions": Json::array([Json::null()]),
      "durable_bindings": Json::array([Json::null()]),
      "effect_source_artifacts": Json::array([Json::null()]),
    }),
    100,
    10,
    10000,
  )
  assert_eq(
    installed_effect_capture_publication_metadata_count(record, 1),
    Some(17),
  )
  let with_unrelated = @identity.object_with_string_field(
    record,
    "unrelated_capture_DATA",
    "x".repeat(10000),
  ).unwrap()
  assert_eq(
    installed_effect_capture_publication_metadata_count(with_unrelated, 1),
    Some(17),
  )
  assert_eq(
    installed_effect_capture_publication_metadata_count(record, 17),
    Some(33),
  )
  assert_eq(
    installed_effect_capture_publication_metadata_count(record, -1),
    None,
  )
  assert_eq(
    installed_effect_capture_publication_metadata_count(record, 2147483647),
    None,
  )
  assert_eq(
    installed_effect_capture_publication_metadata_count(
      @identity.object_with_replaced_fields(record, [
        (
          "definitions",
          @identity.from_json(Json::string("foreign array"), 1, 1, 100),
        ),
      ]).unwrap(),
      1,
    ),
    None,
  )
  for nodes in [100, 10000] {
    let without_metadata = request_effect_capture_recovery_capacity(
      400000,
      800,
      8000000,
      100000,
      64,
      nodes=Some(nodes),
      staged_envelope=true,
      envelope_nodes=Some(4),
      plaintext_bytes=Some(300000),
      envelope_units=400000,
    ).unwrap()
    let with_metadata = request_effect_capture_recovery_capacity(
      400000,
      800,
      8000000,
      100000,
      64,
      nodes=Some(nodes),
      staged_envelope=true,
      envelope_nodes=Some(4),
      plaintext_bytes=Some(300000),
      envelope_units=400000,
      publication_inputs=17,
    ).unwrap()
    // Four temporary vectors per element, each shared Array growth tariff
    // contributes three reference slots. All actual capture trees stay priced
    // independently, even when their unrelated node envelope is much larger.
    assert_eq(
      @execution.execution_capacity_retained_bytes(with_metadata) -
      @execution.execution_capacity_retained_bytes(without_metadata),
      17L * 4L * 3L * 8L,
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(with_metadata) -
      @execution.execution_capacity_execution_bytes(without_metadata),
      17L * 4L * 3L * 8L,
    )
  }
}

///|
test "publication demand preserves completed Read originals and retains output through completion and retirement" {
  let (run, ledger, read, _) = capture_validation_geometry_fixture()
  let before = @resources.ledger_usage(ledger)
  let material = read.material.unwrap()
  let fixed = read.fixed.unwrap()
  let work = run.effect_operation_controls.unwrap().dependency_work.unwrap()
  let wire = read.material_wire
  let envelope = read.material_envelope_wire
  // Geometry alone cannot create a prepared-capture publication capability.
  assert_true(
    installed_effect_capture_publication_input_limit(read)
    is Err(ForeignOriginal),
  )
  enter_capture_publication_demand(read, 728L, 4096L).unwrap()
  let active = @resources.ledger_usage(ledger)
  assert_eq(
    active.reserved_retention_bytes,
    before.reserved_retention_bytes + 728L,
  )
  assert_eq(
    active.reserved_execution_bytes,
    before.reserved_execution_bytes + 728L + 4096L,
  )
  assert_eq(active.live_reservations, before.live_reservations)
  assert_eq(active.planning_work, before.planning_work)
  assert_eq(active.attempts, before.attempts)
  assert_eq(read.publication_retained, 728L)
  assert_true(physical_equal(read.material.unwrap(), material))
  assert_true(physical_equal(read.fixed.unwrap(), fixed))
  assert_true(
    physical_equal(
      run.effect_operation_controls.unwrap().dependency_work.unwrap(),
      work,
    ),
  )
  assert_eq(read.material_wire, wire)
  assert_eq(read.material_envelope_wire, envelope)
  complete_installed_effect_capture_recovery(read).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(
    held.reserved_retention_bytes,
    before.reserved_retention_bytes + 728L,
  )
  assert_eq(
    held.reserved_execution_bytes,
    before.reserved_execution_bytes + 728L,
  )
  // A later commit is scratch-only, while a second real output joins the same
  // held owner. Neither completion refunds previously returned DATA.
  enter_capture_publication_demand(read, 0L, 8192L).unwrap()
  complete_installed_effect_capture_recovery(read).unwrap()
  assert_eq(@resources.ledger_usage(ledger), held)
  enter_capture_publication_demand(read, 120L, 2048L).unwrap()
  complete_installed_effect_capture_recovery(read).unwrap()
  assert_eq(read.publication_retained, 848L)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes + 848L,
  )
  close_capture_validation_fixture(run, ledger, read)
}

///|
test "publication exact execution boundary and one-short refusal preserve the same output floor without double charge" {
  for shortage in [0L, 1L] {
    let (run, ledger, read, _) = capture_validation_geometry_fixture()
    enter_capture_publication_demand(read, 120L, 256L).unwrap()
    complete_installed_effect_capture_recovery(read).unwrap()
    let held = @resources.ledger_usage(ledger)
    let free = @resources.ledger_limits(ledger).execution_bytes -
      held.reserved_execution_bytes
    let pressure = @resources.reserve_capacity(
      ledger,
      0L,
      free - 728L - 4096L + shortage,
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = enter_capture_publication_demand(read, 728L, 4096L)
    if shortage == 1L {
      assert_true(result is Err(Ledger(@resources.ExecutionLimit)))
      assert_eq(@resources.ledger_usage(ledger), before)
      assert_eq(read.publication_retained, 120L)
      assert_false(read.material_completed)
      assert_true(
        installed_effect_capture_publication_input_limit(read)
        is Err(ForeignOriginal),
      )
    } else {
      result.unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        @resources.ledger_limits(ledger).execution_bytes,
      )
      assert_eq(read.publication_retained, 848L)
      complete_installed_effect_capture_recovery(read).unwrap()
    }
    @resources.settle_capacity(ledger, pressure).unwrap()
    close_capture_validation_fixture(run, ledger, read)
  }
}

///|
test "publication current reentry closing and foreign backing refusal preserve the original demand prefix" {
  // A failed current check poisons that original Run. Each independent mode
  // needs its own genuine fixture; no later success can erase that refusal.
  for selected in [1, 2, 3] {
    let owner : Ref[ClientInstalledEffectCaptureRecovery?] = Ref(None)
    let mode = Ref(0)
    let reentry = Ref(false)
    let (run, ledger, read, _) = capture_validation_geometry_fixture(current=() => {
      if mode.val == 1 {
        capture_recovery_current_refusal()
      }
      if mode.val == 2 {
        reentry.val = installed_effect_capture_publication_input_limit(
            owner.val.unwrap(),
          )
          is Err(Retired)
      }
      if mode.val == 3 {
        owner.val.unwrap().closing = true
      }
    })
    owner.val = Some(read)
    mode.val = selected
    let before = @resources.ledger_usage(ledger)
    let previous = read.publication_retained
    let result = enter_capture_publication_demand(read, 120L, 4096L)
    if selected == 2 {
      result.unwrap()
      assert_true(reentry.val)
      complete_installed_effect_capture_recovery(read).unwrap()
    } else {
      assert_true(result is Err(_))
      assert_eq(@resources.ledger_usage(ledger), before)
      assert_eq(read.publication_retained, previous)
    }
    mode.val = 0
    read.closing = false
    close_capture_validation_fixture(run, ledger, read)
    assert_true(
      installed_effect_capture_publication_input_limit(read) is Err(Retired),
    )
  }
  let (run, ledger, read, _) = capture_validation_geometry_fixture()
  let (foreign_run, foreign_ledger, foreign, _) = capture_validation_geometry_fixture()
  let copied = { ..read, ledger: Some(foreign_ledger), }
  let before = @resources.ledger_usage(ledger)
  let foreign_before = @resources.ledger_usage(foreign_ledger)
  assert_true(enter_capture_publication_demand(copied, 120L, 4096L) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
  close_capture_validation_fixture(foreign_run, foreign_ledger, foreign)
  close_capture_validation_fixture(run, ledger, read)
  assert_true(
    installed_effect_capture_publication_input_limit(read) is Err(Retired),
  )
}
