///|
// Actual checked Values/Effect/Plan and adopted same-Run numeric resources.
// The existing fixture uses in-memory physical ports and Allow DATA; this is
// Core funding/current evidence, not ordinary Account/Journal/STORE acceptance.
fn dependency_original_fixture(
  current? : () -> Unit = () => (),
  selected_environment? : @checked.CheckEnvironment? = None,
) -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
  @strategy.CapturedEffectRunDAG,
  LocalValuesExecution,
) raise {
  let (prepared, request, plan, owner, ledger) = native_control_fixture(
    current~,
    selected_environment~,
  )
  let (host, captured, _) = open_installed_effect_managed_host(
      owner,
      effect_parent_bound_run(prepared),
      [],
    )
    .unwrap()
    .unwrap()
  let execution = execute_retained_effect_local_tasks_guarded(
    host,
    captured,
    1,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  (prepared, request, plan, owner, ledger, captured, execution)
}

///|
test "same original dependency pin and static bodies retain measured numeric prefix with bounded current" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(current=() => {
      calls.val += 1
    },
  )
  let before = @resources.ledger_usage(ledger)
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  let pinned = @resources.ledger_usage(ledger)
  assert_true(pinned.reserved_retention_bytes > before.reserved_retention_bytes)
  let original = owner.effect_operation_controls.unwrap()
  assert_true(original.dependency_work is Some(_))
  let current = calls.val
  let planning = pinned.planning_work
  let bodies = prepare_installed_effect_dependency_bodies(
    owner, prepared, request, plan, inputs, 0, 1000000, 100000, 64,
  ).unwrap()
  assert_eq(bodies.length(), 6)
  assert_true(calls.val > current && calls.val - current <= 20)
  assert_eq(@resources.ledger_usage(ledger).planning_work, planning)
  assert_true(
    physical_equal(original, owner.effect_operation_controls.unwrap()),
  )
  let held = @resources.ledger_usage(ledger)
  assert_true(held.reserved_retention_bytes > pinned.reserved_retention_bytes)
  assert_eq(held.attempts, before.attempts)
  assert_eq(held.transferred_bytes, before.transferred_bytes)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "dependency initial one-byte-short grow refuses before Work or pin construction" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let control = owner.effect_operation_controls.unwrap()
  let fixed = installed_effect_dependency_fixed_capacity(
    0,
    @strategy.captured_effect_dependency_unit_count(captured),
    64,
  ).unwrap()
  let (capacity, _) = installed_effect_control_capacity(
    Some(control),
    plan,
    dependency_capacity=Some(fixed),
  ).unwrap()
  let target = @execution.execution_capacity_execution_bytes(capacity)
  let (_, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  let delta = target - idle
  assert_true(delta > 0L)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    @resources.ledger_usage(ledger).reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - delta + 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    pin_installed_effect_sources(owner, prepared, request, plan, captured, 64)
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(control.dependency_started)
  assert_true(
    control.dependency_work is None && control.dependency_inputs is None,
  )
  @resources.settle_capacity(ledger, pressure).unwrap()
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "dependency original refuses copied owner and foreign retained inputs before metadata allocation" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(current=() => {
      calls.val += 1
    },
  )
  let (
    foreign_prepared,
    foreign_request,
    foreign_plan,
    foreign,
    _,
    foreign_capture,
    foreign_execution,
  ) = dependency_original_fixture()
  let foreign_inputs = pin_installed_effect_sources(
    foreign, foreign_prepared, foreign_request, foreign_plan, foreign_capture, 64,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let current = calls.val
  assert_true(
    pin_installed_effect_sources(
      { ..owner, },
      prepared,
      request,
      plan,
      captured,
      64,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_effect_dependency_bodies(
      owner, prepared, request, plan, foreign_inputs, 0, 1000000, 100000, 64,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(calls.val, current)
  assert_true(@strategy.release_captured_effect_inputs(foreign_inputs))
  assert_true(foreign_execution.close())
  retire_installed_managed_run(foreign).unwrap()
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "completed dependency construction hands the same control back to its next original child" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  let bodies = prepare_installed_effect_dependency_bodies(
    owner, prepared, request, plan, inputs, 0, 1000000, 100000, 64,
  ).unwrap()
  assert_eq(bodies.length(), 6)
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  begin_installed_effect_operation_construction(child).unwrap()
  complete_installed_effect_operation_construction(child).unwrap()
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "dependency successful cut refuses current cancellation and preserves its original peak" {
  let armed = Ref(false)
  let pending = Ref(false)
  let current_calls = Ref(0)
  let borrowed : Ref[ClientInstalledManagedRun?] = Ref(None)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(current=() => {
      current_calls.val += 1
      if armed.val {
        armed.val = false
        let original = borrowed.val.unwrap()
        pending.val = retire_installed_managed_run(original)
          is Err(CleanupPending)
        original.effect_operation_closing = true
      }
    },
  )
  borrowed.val = Some(owner)
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, _) else {
    fail("original adopted Effect preparation required")
  }
  retain_installed_effect_dependency_capacity(
    owner,
    preparation,
    admission,
    plan,
    ledger,
    control,
    @execution.execution_capacity(17L, 4096L).unwrap(),
  ).unwrap()
  let peak = @resources.ledger_usage(ledger)
  let previous = control.dependency_capacity.unwrap()
  armed.val = true
  let before_current = current_calls.val
  assert_true(
    complete_installed_effect_dependency_construction(
      owner, prepared, request, plan,
    )
    is Err(Retired),
  )
  assert_true(pending.val && owner.effect_operation_closing)
  assert_eq(current_calls.val - before_current, 1)
  assert_eq(@resources.ledger_usage(ledger), peak)
  assert_true(physical_equal(control.dependency_capacity.unwrap(), previous))
  assert_false(owner.effect_operation_opening)
  // The callback's first retirement was Pending, never an ACK. Test cleanup
  // now ends the actual original input/execution and then retires that owner.
  owner.effect_operation_closing = false
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "original canonical Relation packet uses exact export bytes and refuses an equal CID with changed wire" {
  let text = StringBuilder()
  text.write_string("{\"sort\":\"relation\",\"value\":[")
  let document = StringBuilder()
  for _ in 0..<49152 {
    document.write_string("x")
  }
  for row in 0..<16 {
    if row > 0 {
      text.write_string(",")
    }
    text.write_string("{\"document\":\"")
    text.write_string(document.to_string())
    text.write_string("\",\"id\":")
    text.write_string(row.to_string())
    text.write_string("}")
  }
  text.write_string("]}")
  let wire = text.to_string()
  let bytes = wire.length() // This independent fixture is entirely ASCII.
  let cid = "sha256:" + @sha.text_hex(wire).unwrap()
  let observed = installed_effect_dependency_wire_geometry(
    wire,
    2000000,
    1000,
    10,
    _ => true,
  ).unwrap()
  let geometry = installed_effect_dependency_original_relation_geometry(
    wire,
    cid,
    bytes,
    51,
    3,
    observed,
    _ => true,
  ).unwrap()
  assert_eq(geometry.bytes, bytes)
  assert_eq(geometry.nodes, 51)
  assert_eq(geometry.depth, 3)
  let exact = installed_effect_dependency_body_capacity(geometry).unwrap()
  let raw = installed_effect_dependency_wire_capacity(
    observed, 1000000000, 1000, 10,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(exact) <
    @execution.execution_capacity_retained_bytes(raw),
  )
  // The complete original packet is paid before strict parsing/canonical CID
  // admission. This is a constructor/quote test, not an Artifact authority.
  let body = @publication.admit_captured_effect_dependency_body(
    "relation_value",
    Some(cid),
    wire,
    bytes,
    51,
    3,
  ).unwrap()
  assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
  assert_eq(@publication.captured_effect_dependency_body_cid(body), cid)
  let changed = wire.replace(old="\"id\":0", new="\"id\":9")
  let changed_geometry = installed_effect_dependency_wire_geometry(
    changed,
    2000000,
    1000,
    10,
    _ => true,
  ).unwrap()
  assert_true(
    installed_effect_dependency_original_relation_geometry(
      changed,
      cid,
      bytes,
      51,
      3,
      changed_geometry,
      _ => true,
    )
    is None,
  )
  assert_true(
    installed_effect_dependency_original_relation_geometry(
      wire,
      cid,
      bytes,
      51,
      3,
      observed,
      _ => false,
    )
    is None,
  )
}

///|
test "original Relation packet real one-byte-short parent refuses before constructor and cleans up" {
  let (_, _, plan, owner, ledger, _, execution) = dependency_original_fixture()
  let control = owner.effect_operation_controls.unwrap()
  let preparation = owner.preparation.unwrap()
  guard preparation is PlannedEffectManaged(admission, _) else {
    fail("expected original Effect admission")
  }
  let geometry : @encode.EncodingConstructionGeometry = {
    bytes: 100000,
    nodes: 6,
    depth: 3,
    arrays: 1,
    objects: 2,
    fields: 3,
    largest_object: 2,
    strings: 2,
    text_units: 99900,
  }
  let packet = installed_effect_dependency_body_capacity(geometry).unwrap()
  let (capacity, _) = installed_effect_control_capacity(
    Some(control),
    plan,
    dependency_capacity=Some(packet),
  ).unwrap()
  let required = @execution.execution_capacity_execution_bytes(capacity)
  let before = @resources.ledger_usage(ledger)
  let (_, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  let delta = required - idle
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    before.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - delta + 1L).unwrap()
  let pressured = @resources.ledger_usage(ledger)
  assert_true(
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, packet,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), pressured)
  @resources.settle_capacity(ledger, pressure).unwrap()
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
