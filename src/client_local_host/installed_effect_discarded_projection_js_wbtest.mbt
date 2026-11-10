///|
fn discarded_projection_extent(
  r : Int64,
  e : Int64,
  remaining : @execution.ExecutionCapacity,
) -> ClientInstalledEffectOperationExtent {
  prepare_installed_effect_discarded_projection_extent(
    prepare_installed_effect_operation_extent(
      "send",
      @execution.execution_capacity(r, e).unwrap(),
      7L,
      true,
    ).unwrap(),
    remaining,
  ).unwrap()
}

///|
test "discarded Unit projection keeps full failed peak then reduces only the admitted remainder" {
  let remaining = @execution.execution_capacity(3L, 3L).unwrap()
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    parent_limit=Some(536870912L),
    projection_retained=Some(remaining),
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  start_installed_effect_operation(child).unwrap()
  let old = @resources.ledger_usage(ledger)
  let room = @resources.ledger_limits(ledger).execution_bytes -
    old.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, room - 40L + 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_input(
      child,
      discarded_projection_extent(9L, 48L, remaining),
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.settle_capacity(ledger, pressure).unwrap()
  begin_installed_effect_operation_input(
    child,
    discarded_projection_extent(9L, 48L, remaining),
  ).unwrap()
  guard child.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(token)) else {
    fail("missing physical token")
  }
  @resources.charge_transfer(ledger, token, 2L).unwrap()
  @resources.mark_cleanup_pending(ledger, token).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_eq(
    @resources.reservation_capacity_amounts(ledger, token).unwrap(),
    (9L, 48L),
  )
  // A failed/not-yet-disposed projector has no completed call: keep full peak.
  require_installed_effect_operation_plan(owner, prepared, request).unwrap()
  |> ignore
  assert_eq(@resources.ledger_usage(ledger), before)
  complete_installed_effect_discarded_response_projection(child).unwrap()
  assert_eq(
    @resources.reservation_capacity_amounts(ledger, token).unwrap(),
    (3L, 3L),
  )
  assert_eq(@resources.ledger_usage(ledger), {
    ..before,
    reserved_retention_bytes: before.reserved_retention_bytes - 6L,
    reserved_execution_bytes: before.reserved_execution_bytes - 45L,
  })
  assert_true(@resources.reservation_open(token))
  assert_true(@resources.reservation_pending(token))
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  let completed = @resources.ledger_usage(ledger)
  complete_installed_effect_discarded_response_projection(child).unwrap()
  assert_eq(@resources.ledger_usage(ledger), completed)
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "discarded projection cannot change its remainder after Plan admission or use an unbound slot" {
  let remaining = @execution.execution_capacity(3L, 3L).unwrap()
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    projection_retained=Some(remaining),
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  start_installed_effect_operation(child).unwrap()
  let before = @resources.ledger_usage(ledger)
  let changed = discarded_projection_extent(
    9L,
    48L,
    @execution.execution_capacity(0L, 0L).unwrap(),
  )
  assert_true(
    begin_installed_effect_operation_input(child, changed)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    prepare_installed_effect_staged_extent(
      discarded_projection_extent(9L, 48L, remaining),
      changed,
    )
    is Err(Unsupported),
  )
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture()
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  start_installed_effect_operation(child).unwrap()
  begin_installed_effect_operation_input(
    child,
    prepare_installed_effect_operation_extent(
      "send",
      @execution.execution_capacity(9L, 48L).unwrap(),
      7L,
      true,
    ).unwrap(),
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    complete_installed_effect_discarded_response_projection(child)
    is Err(Unsupported),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "discarded projection preserves the same original current reentry fence" {
  let selected : Ref[ClientInstalledEffectOperationBorrow?] = Ref(None)
  let reenter = Ref(false)
  let remaining = @execution.execution_capacity(3L, 3L).unwrap()
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    projection_retained=Some(remaining),
    current=() => if reenter.val { selected.val.unwrap().retired = true },
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  selected.val = Some(child)
  start_installed_effect_operation(child).unwrap()
  begin_installed_effect_operation_input(
    child,
    discarded_projection_extent(9L, 48L, remaining),
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  reenter.val = true
  assert_true(
    complete_installed_effect_discarded_response_projection(child)
    is Err(Retired),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  reenter.val = false
  child.retired = false
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "discarded HubSpot recipe keeps actual HTTP secret and live Reader carriers while initial peak remains full" {
  let limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
  let native = @hubspot_catalog.effect_metadata_construction_capacity(
    4096, 9, limits,
  ).unwrap()
  let reader = @hubspot_catalog.effect_metadata_disposed_construction_capacity().unwrap()
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let full = hubspot_full_metadata_response_quote(native)
  let remaining = hubspot_full_metadata_response_quote(reader)
  let raw = hubspot_full_metadata_response_quote(empty)
  assert_true(
    @execution.execution_capacity_retained_bytes(remaining) >
    @execution.execution_capacity_retained_bytes(raw),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(full) -
    @execution.execution_capacity_retained_bytes(remaining),
    @execution.execution_capacity_retained_bytes(native) -
    @execution.execution_capacity_retained_bytes(reader),
  )
  let original = prepare_installed_effect_operation_extent(
    "schema-after", full, 7L, true,
  ).unwrap()
  let bound = prepare_installed_effect_discarded_projection_extent(
    original, remaining,
  ).unwrap()
  assert_true(
    installed_effect_operation_response_backing_fits(
      bound,
      524288,
      16384,
      response_read_quantum=16384,
    ),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(bound.capacity),
    @execution.execution_capacity_retained_bytes(full),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(bound.capacity),
    @execution.execution_capacity_execution_bytes(full),
  )
}
