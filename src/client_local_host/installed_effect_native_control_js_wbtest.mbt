///|
fn native_control_fixture(
  current? : () -> Unit = () => (),
) -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
) raise {
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    parent_limit=Some(536870912L),
    current~,
  )
  retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  ).unwrap()
  |> ignore
  (prepared, request, plan, owner, ledger)
}

///|
test "same control funds native Unit scratch beside full retention and returns only explicit completion" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = native_control_fixture(current=() => {
    calls.val += 1
  })
  let native = @hubspot_catalog.effect_catalog_recheck_construction_capacity(
    65536,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  let (base, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  let before = @resources.ledger_usage(ledger)
  let current = calls.val
  begin_installed_effect_operation_control_construction(
    owner,
    prepared,
    request,
    plan,
    native=Some(native),
  ).unwrap()
  assert_eq(calls.val, current + 1)
  let active = @resources.ledger_usage(ledger)
  assert_eq(active.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(
    active.reserved_execution_bytes - before.reserved_execution_bytes,
    Int64::max(
      idle,
      @execution.execution_capacity_retained_bytes(base) +
      @execution.execution_capacity_execution_bytes(native),
    ) -
    idle,
  )
  assert_true(control.construction_active)
  // Fresh original: ledger_codec_active is still false and no input wire
  // was selected. With entering=true, only the existing Fixed-frame branch
  // causes AlreadyBound here, not a previous codec or a closed constructor.
  assert_true(
    begin_installed_effect_operation_ledger_codec(
      owner,
      prepared,
      request,
      plan,
      None,
      64,
      4,
    )
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(ledger), active)
  // A same-owner current observation cannot return an active/failed prefix.
  require_installed_effect_operation_plan(owner, prepared, request).unwrap()
  |> ignore
  assert_eq(@resources.ledger_usage(ledger), active)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(control.construction_active)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "native scratch refuses one byte short before caller work and preserves original Ledger" {
  let (prepared, request, plan, owner, ledger) = native_control_fixture()
  let native = @hubspot_catalog.effect_catalog_recheck_construction_capacity(
    65536,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  let (base, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  let delta = Int64::max(
      idle,
      @execution.execution_capacity_retained_bytes(base) +
      @execution.execution_capacity_execution_bytes(native),
    ) -
    idle
  assert_true(delta > 0L)
  let usage = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    usage.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - delta + 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner,
      prepared,
      request,
      plan,
      native=Some(native),
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(control.construction_active)
  @resources.settle_capacity(ledger, pressure).unwrap()
  begin_installed_effect_operation_control_construction(
    owner,
    prepared,
    request,
    plan,
    native=Some(native),
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner,
      prepared,
      request,
      plan,
      native=Some(@execution.execution_capacity(1L, 2L).unwrap()),
    )
    is Err(Unsupported),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "native scratch still rejects reentry after the original current callback" {
  let selected : Ref[ClientInstalledManagedRun?] = Ref(None)
  let invalidate = Ref(false)
  let (prepared, request, plan, owner, ledger) = native_control_fixture(current=() => {
    if invalidate.val {
      selected.val.unwrap().ledger = None
    }
  })
  selected.val = Some(owner)
  let before = @resources.ledger_usage(ledger)
  invalidate.val = true
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner,
      prepared,
      request,
      plan,
      native=Some(
        @hubspot_catalog.effect_catalog_recheck_construction_capacity(256).unwrap(),
      ),
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(owner.effect_operation_controls.unwrap().construction_active)
  // Restore only this explicit no-I/O reentry fixture for its own cleanup.
  invalidate.val = false
  owner.ledger = Some(ledger)
  retire_installed_managed_run(owner).unwrap()
}
