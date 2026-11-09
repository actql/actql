///|
fn effect_host_preview_input_fixture(
  standard? : Bool = false,
  wide_controls? : Bool = false,
  current? : () -> Unit = () => (),
) -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
) {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let original = effect_operation_plan_fixture(prepared, request, contracts)
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let host = prepare_installed_effect_host_input_capture_recipe_extent(
    "operation",
    if standard {
      [@execution.execution_capacity(8L, 8L).unwrap(), empty]
    } else {
      [
        @execution.execution_capacity(8L, 8L).unwrap(),
        empty,
        empty,
        empty,
        empty,
        empty,
      ]
    },
    1000000,
    100000,
    64,
  ).unwrap()
  let before = original.operations[0]
  let members = before.member_extents.copy()
  members.push(host)
  let demand = if wide_controls {
    prepare_installed_effect_operation_demand_with_controls(
      prepared,
      0,
      "save",
      members,
      before.row_extents,
      standard_create_saved_control_capacity(1000000, 512, 16).unwrap(),
    ).unwrap()
  } else {
    prepare_installed_effect_operation_demand(
      prepared,
      0,
      "save",
      members,
      before.row_extents,
    ).unwrap()
  }
  let plan = prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  let requirements = prepared_installed_effect_managed_requirements(plan)
  // Explicit existing parent ports for this control/accounting unit only.
  // Product policy and normal Host admission are not changed by this fixture.
  if wide_controls {
    requirements[4] = 536870902L
    requirements[5] = 536870902L
  } else {
    requirements[4] += 1000000L
    requirements[5] += 1000000L
  }
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    requirements,
    current~,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  ignore(
    retain_installed_effect_operation_controls_before_construction(
      owner, prepared, request, plan,
    ).unwrap(),
  )
  (prepared, request, plan, owner, ledger)
}

///|
test "Host Preview deferred forest keeps original full text and codec maxima" {
  let (full, full_work) = installed_standard_host_preview_input_parts(
    4096,
    128,
    16,
    None,
  ).unwrap()
  let (initial, initial_work) = installed_standard_host_preview_input_parts(
    4096,
    128,
    16,
    Some(0),
  ).unwrap()
  let (actual, actual_work) = installed_standard_host_preview_input_parts(
    4096,
    128,
    16,
    Some(32),
  ).unwrap()
  assert_eq(initial.owned_utf16_units, full.owned_utf16_units)
  assert_eq(actual.owned_utf16_units, full.owned_utf16_units)
  assert_eq(initial.record_headers, 0L)
  assert_eq(initial.reference_slots, 0L)
  assert_eq(initial.scalar_words, 0L)
  assert_eq(
    @execution.preparation_representation_cost(initial_work).unwrap(),
    0L,
  )
  assert_true(
    actual.record_headers > 0L && actual.record_headers <= full.record_headers,
  )
  assert_true(
    @execution.preparation_representation_cost(actual_work).unwrap() <=
    @execution.preparation_representation_cost(full_work).unwrap(),
  )
  assert_true(
    installed_standard_host_preview_input_parts(4096, 128, 16, Some(4097))
    is None,
  )
}

///|
test "Host Preview grows same original control before parse and keeps its returned forest across later children" {
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture()
  assert_true(owner.effect_operation_controls.unwrap().host_input is None)
  let before = @resources.ledger_usage(ledger)
  let wire = "{\"rows\":[{\"id\":1}]}"
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, wire,
  ).unwrap()
  let active = @resources.ledger_usage(ledger)
  assert_true(active.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(active.attempts, before.attempts)
  assert_eq(active.transferred_bytes, before.transferred_bytes)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(held.reserved_retention_bytes, active.reserved_retention_bytes)
  assert_true(held.reserved_execution_bytes < active.reserved_execution_bytes)
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(owner, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, wire,
    )
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let child_usage = @resources.ledger_usage(ledger)
  assert_true(
    child_usage.reserved_retention_bytes > held.reserved_retention_bytes,
  )
  assert_true(child_usage.peak_retention_bytes > held.peak_retention_bytes)
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true) is Ok(true))
  // Retirement returns the live reservation, not its historical high-water mark.
  let returned = {
    ..held,
    peak_retention_bytes: child_usage.peak_retention_bytes,
  }
  assert_eq(@resources.ledger_usage(ledger), returned)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, "{\"different\":true}",
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), returned)
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
}

///|
test "Host Preview refused growth leaves same original usage and input selection unchanged" {
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner,
      prepared,
      request,
      plan,
      "x".repeat(500000),
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(owner.effect_operation_controls.unwrap().host_input is None)
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, "{}",
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
test "standard two-role capture grows the same original Preview forest and keeps refusal retryable" {
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture(
    standard=true,
  )
  assert_true(owner.effect_operation_controls.unwrap().host_input is None)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner,
      prepared,
      request,
      plan,
      "x".repeat(500000),
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(owner.effect_operation_controls.unwrap().host_input is None)
  let wire = "{\"rows\":[{\"id\":1}]}"
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, wire,
  ).unwrap()
  let active = @resources.ledger_usage(ledger)
  assert_true(active.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(active.attempts, before.attempts)
  assert_eq(active.transferred_bytes, before.transferred_bytes)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let retained = @resources.ledger_usage(ledger)
  assert_eq(retained.reserved_retention_bytes, active.reserved_retention_bytes)
  assert_true(
    retained.reserved_execution_bytes < active.reserved_execution_bytes,
  )
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, wire,
    )
    is Err(AlreadyBound),
  )
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, "{\"foreign\":true}",
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), retained)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Preview decode selects same wire geometry instead of unrelated full recipe scratch on real Ledger" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture(
    wide_controls=true,
    current=() => calls.val += 1,
  )
  let wire = "{\"rows\":[{\"id\":1}]}"
  let host = installed_effect_host_preview_input_capacity(plan, wire).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(host)
  let execution = @execution.execution_capacity_execution_bytes(host)
  assert_true(retained > 0L && execution > retained)
  let control = owner.effect_operation_controls.unwrap()
  let token = control.reservation
  let before = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    before.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - execution).unwrap()
  let one_short = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let exhausted = @resources.ledger_usage(ledger)
  // The actual same-wire quote is required in full, even though the unrelated
  // recipe peak is no longer selected. A declined entry owns no parsed forest.
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, wire,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), exhausted)
  assert_true(control.host_input is None && control.constructor_frame is None)
  @resources.settle_capacity(ledger, one_short).unwrap()
  let occupied = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), occupied)
  assert_true(
    begin_installed_effect_operation_control_input(
      { ..owner, },
      prepared,
      request,
      plan,
      wire,
    )
    is Err(ForeignOriginal),
  )
  calls.val = 0
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, wire,
  ).unwrap()
  assert_true(calls.val > 0)
  let active = @resources.ledger_usage(ledger)
  assert_eq(
    active.reserved_retention_bytes - occupied.reserved_retention_bytes,
    retained,
  )
  assert_eq(
    active.reserved_execution_bytes - occupied.reserved_execution_bytes,
    execution,
  )
  assert_eq(active.held_bytes, occupied.held_bytes)
  assert_eq(active.attempts, occupied.attempts)
  assert_eq(active.transferred_bytes, occupied.transferred_bytes)
  assert_true(physical_equal(control.reservation, token))
  assert_true(
    control.constructor_frame is Some(Fixed(workspace, None)) &&
    workspace == execution - retained,
  )
  let (selected, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected),
    plan.operation_control_idle_execution + execution,
  )
  assert_eq(idle, plan.operation_control_idle_execution + retained)
  // No successful completion was issued: failed or pending parsing keeps the
  // same forest, full retained floor and scratch through ordinary current.
  check_installed_effect_managed_run(owner, prepared, request).unwrap()
  assert_eq(@resources.ledger_usage(ledger), active)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, wire,
    )
    is Err(AlreadyBound),
  )
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(held.reserved_retention_bytes, active.reserved_retention_bytes)
  assert_eq(
    held.reserved_execution_bytes - occupied.reserved_execution_bytes,
    retained,
  )
  assert_true(control.constructor_frame is None)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, "{\"different\":true}",
    )
    is Err(ForeignOriginal),
  )
  // A later generic callback still owes its complete original recipe quote.
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  @resources.settle_capacity(ledger, pressure).unwrap()
  begin_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Ledger open selects same scope constructor beside original Preview and preserves full retained floor" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture(
    wide_controls=true,
    current=() => calls.val += 1,
  )
  let wire = "{\"rows\":[{\"id\":1}]}"
  let input = installed_effect_host_preview_input_capacity(plan, wire).unwrap()
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, wire,
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  let original_input = control.host_input.unwrap()
  let token = control.reservation
  let root = "/original/effect-ledger"
  let workspace = installed_effect_ledger_open_workspace(root).unwrap()
  let base_r = @execution.execution_capacity_retained_bytes(
    plan.operation_control_capacity,
  )
  let base_idle = plan.operation_control_idle_execution
  let input_r = @execution.execution_capacity_retained_bytes(input)
  let input_e = @execution.execution_capacity_execution_bytes(input)
  let active_e = Int64::max(
    Int64::max(base_idle, base_r + workspace) + input_r,
    base_idle + input_e,
  )
  let needed = active_e - (base_idle + input_r)
  assert_true(needed > 0L)
  let before = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    before.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - needed).unwrap()
  let one_short = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let exhausted = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_ledger_open(
      owner, prepared, request, plan, root,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), exhausted)
  assert_true(control.constructor_frame is None)
  @resources.settle_capacity(ledger, one_short).unwrap()
  let occupied = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), occupied)
  assert_true(
    begin_installed_effect_operation_ledger_open(
      { ..owner, },
      prepared,
      request,
      plan,
      root,
    )
    is Err(ForeignOriginal),
  )
  calls.val = 0
  begin_installed_effect_operation_ledger_open(
    owner, prepared, request, plan, root,
  ).unwrap()
  assert_true(calls.val > 0)
  let active = @resources.ledger_usage(ledger)
  assert_eq(
    active.reserved_execution_bytes - occupied.reserved_execution_bytes,
    needed,
  )
  assert_eq(active.reserved_retention_bytes, occupied.reserved_retention_bytes)
  assert_eq(active.held_bytes, occupied.held_bytes)
  assert_eq(active.attempts, occupied.attempts)
  assert_eq(active.transferred_bytes, occupied.transferred_bytes)
  assert_true(physical_equal(control.reservation, token))
  assert_true(
    control.constructor_frame is Some(Fixed(actual, None)) &&
    actual == workspace,
  )
  let (current_wire, current_capacity) = control.host_input.unwrap()
  let (original_wire, original_capacity) = original_input
  assert_eq(current_wire, original_wire)
  assert_true(physical_equal(current_capacity, original_capacity))
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, wire,
    )
    is Err(AlreadyBound),
  )
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
  // A failed/opening callback has not completed this frame. Ordinary current
  // is neither a scratch return nor evidence that SQLite acknowledged close.
  check_installed_effect_managed_run(owner, prepared, request).unwrap()
  assert_eq(@resources.ledger_usage(ledger), active)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), occupied)
  assert_true(control.constructor_frame is None)
  @resources.settle_capacity(ledger, pressure).unwrap()
  begin_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_true(
    installed_effect_ledger_open_workspace(root + root).unwrap() > workspace,
  )
}

///|
test "standard Ledger family prices selected rows and keeps larger policies generic" {
  let one = installed_effect_ledger_family_workspace(
    [1],
    100000,
    1000000,
    64,
    4,
  ).unwrap()
  let two = installed_effect_ledger_family_workspace(
    [1, 1],
    100000,
    1000000,
    64,
    4,
  ).unwrap()
  assert_true(two > one)
  assert_true(
    installed_effect_ledger_family_workspace([0], 100000, 1000000, 64, 4).unwrap() <
    one,
  )
  assert_true(
    installed_effect_ledger_family_workspace([1], 100000, 10, 64, 4).unwrap() <
    one,
  )
  for counts in [[], [-1], [100001]] {
    assert_true(
      installed_effect_ledger_family_workspace(counts, 100000, 1000000, 64, 4)
      is None,
    )
  }
  assert_true(
    installed_effect_ledger_family_workspace([1], 100001, 1000000, 64, 4)
    is None,
  )
  assert_true(
    installed_effect_ledger_family_workspace([1], 100000, 1000001, 64, 4)
    is None,
  )
  assert_true(
    installed_effect_ledger_family_workspace([1], 100000, 1000000, 65, 4)
    is None,
  )
  assert_true(
    installed_effect_ledger_family_workspace([1], 100000, 1000000, 64, 5)
    is None,
  )
}

///|
test "standard Ledger family coholds actual snapshot and nested codec on same token through failed current" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture(
    wide_controls=true,
    current=() => calls.val += 1,
  )
  let wire = "{\"rows\":[{\"id\":1}]}"
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, wire,
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  let token = control.reservation
  let before = @resources.ledger_usage(ledger)
  let outer = installed_effect_ledger_family_workspace(
    [1],
    100000,
    1000000,
    64,
    4,
  ).unwrap()
  assert_true(
    begin_installed_effect_operation_ledger_family(
      { ..owner, },
      prepared,
      request,
      plan,
      [1],
      100000,
      1000000,
      64,
      4,
    )
    is Err(ForeignOriginal),
  )
  begin_installed_effect_operation_ledger_family(
    owner,
    prepared,
    request,
    plan,
    [1],
    100000,
    1000000,
    64,
    4,
  ).unwrap()
  assert_true(control.constructor_frame is Some(Ledger(w)) && w == outer)
  let outer_usage = @resources.ledger_usage(ledger)
  assert_eq(
    outer_usage.reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_true(calls.val > 0)
  begin_installed_effect_operation_ledger_codec(
    owner,
    prepared,
    request,
    plan,
    None,
    64,
    4,
  ).unwrap()
  let codec_r = control.ledger_codec_retained
  let codec_w = control.ledger_codec_workspace
  let base_r = @execution.execution_capacity_retained_bytes(
    plan.operation_control_capacity,
  )
  let base_idle = plan.operation_control_idle_execution
  let (_, host) = control.host_input.unwrap()
  let host_r = @execution.execution_capacity_retained_bytes(host)
  let host_e = @execution.execution_capacity_execution_bytes(host)
  let expected = Int64::max(
    Int64::max(base_idle, base_r + codec_r + codec_w + outer) + host_r,
    base_idle + host_e,
  )
  let (selected, _) = installed_effect_control_capacity(Some(control), plan).unwrap()
  assert_eq(@execution.execution_capacity_execution_bytes(selected), expected)
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected),
    base_r + codec_r + host_r,
  )
  let active = @resources.ledger_usage(ledger)
  assert_true(
    active.reserved_execution_bytes >= outer_usage.reserved_execution_bytes,
  )
  assert_eq(
    active.reserved_retention_bytes - before.reserved_retention_bytes,
    codec_r,
  )
  assert_eq(active.held_bytes, before.held_bytes)
  assert_eq(active.attempts, before.attempts)
  assert_eq(active.transferred_bytes, before.transferred_bytes)
  assert_true(physical_equal(token, control.reservation))
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
  assert_true(
    complete_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(AlreadyBound),
  )
  // An interrupted/failed callback has issued no codec completion. Ordinary
  // original current MUST retain both the snapshot and this same codec peak.
  check_installed_effect_managed_run(owner, prepared, request).unwrap()
  assert_eq(@resources.ledger_usage(ledger), active)
  complete_installed_effect_operation_ledger_codec(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), {
    ..outer_usage,
    peak_retention_bytes: active.peak_retention_bytes,
  })
  begin_installed_effect_operation_ledger_codec(
    owner,
    prepared,
    request,
    plan,
    Some("{\"x\":1}"),
    64,
    4,
  ).unwrap()
  complete_installed_effect_operation_ledger_codec(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), {
    ..outer_usage,
    peak_retention_bytes: active.peak_retention_bytes,
  })
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), {
    ..before,
    peak_retention_bytes: active.peak_retention_bytes,
  })
  // Larger policies use the original full generic family, not this floor.
  begin_installed_effect_operation_ledger_family(
    owner,
    prepared,
    request,
    plan,
    [1],
    100001,
    1000000,
    64,
    4,
  ).unwrap()
  assert_true(control.constructor_frame is None)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "standard Ledger family real pressure refuses nested codec without returning outer responsibility" {
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture(
    wide_controls=true,
  )
  begin_installed_effect_operation_ledger_family(
    owner,
    prepared,
    request,
    plan,
    [1],
    100000,
    1000000,
    64,
    4,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  let outer = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    outer.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining).unwrap()
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
    is Err(Ledger(ExecutionLimit)),
  )
  assert_true(!control.ledger_codec_active)
  assert_true(control.constructor_frame is Some(Ledger(_)))
  @resources.settle_capacity(ledger, pressure).unwrap()
  assert_eq(@resources.ledger_usage(ledger), outer)
  check_installed_effect_managed_run(owner, prepared, request).unwrap()
  assert_eq(@resources.ledger_usage(ledger), outer)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
