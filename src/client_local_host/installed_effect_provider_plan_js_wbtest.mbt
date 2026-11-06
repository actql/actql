///|
test "base Source handoff retains the same Plan acquisition and checked input selection" {
  let plan = effect_operation_source_plan_fixture()
  let selection = select_installed_effect_source_input(
    plan.prepared,
    plan.request,
    0,
    0,
  ).unwrap()
  guard selection is @sourceviews.QueryRoute(query) else {
    fail("expected checked Query input")
  }
  let (_, requirement, _, _) = prepared_installed_effect_managed_source(plan, 0).unwrap()
  assert_eq(
    @planning.query_acquisition_source_evidence_facts(query).unwrap().source_ref,
    @planning.query_requirement_source(requirement).0,
  )
  let (input, initial, _, parent) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    parent,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (read, requirement, acquisition, capacity) = begin_installed_effect_managed_source_read(
    owner,
    plan.declarations[0],
    0,
  ).unwrap()
  assert_true(physical_equal(capacity, plan.captures[0]))
  assert_true(capacity.provider is None)
  assert_true(
    capacity.acquisition is Some(original) &&
    physical_equal(original, acquisition),
  )
  assert_true(
    read.requirement is Some(original) && physical_equal(original, requirement),
  )
  assert_true(
    begin_installed_effect_managed_source_read(owner, plan.declarations[0], 0)
    is Err(AlreadyBound),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
test "provider Source reader borrows only its same original planned Ledger and capture" {
  let provider = @execution.execution_capacity(1111L, 2222L).unwrap()
  let plan = effect_operation_source_plan_fixture(provider=Some(provider))
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  let read = begin_installed_managed_run_source_read(owner, 0).unwrap()
  attach_installed_source_read_acquisition(
    read, declaration, requirement, acquisition, 0, 0,
  ).unwrap()
  let ledger = prepare_installed_effect_managed_run_ledger(
    owner,
    plan.prepared,
    plan.request,
    [capacity],
    plan.transport_bytes,
    plan.transport_execution_bytes,
    plan.installed_contracts,
    plan.values_body,
    plan.fragment_body,
    plan.ordered_body,
  ).unwrap()
  assert_true(
    physical_equal(ledger, require_installed_managed_run(owner).unwrap()),
  )
  let copied = installed_provider_row_capture_capacity(
    acquisition,
    Some(provider),
  ).unwrap()
  assert_false(physical_equal(copied, capacity))
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      owner,
      plan.prepared,
      plan.request,
      [copied],
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "provider Source reader refuses a one-byte-short reservation before any physical Start" {
  let provider = @execution.execution_capacity(1111L, 2222L).unwrap()
  let plan = effect_operation_source_plan_fixture(provider=Some(provider))
  for retention in [true, false] {
    let (input, initial, ledger, capacity) = effect_parent_test_preparation(
      plan,
      prepared_installed_effect_managed_requirements(plan),
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial,
      input,
      capacity,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    let (read, _, acquisition, selected) = begin_installed_effect_managed_source_read(
      owner,
      plan.declarations[0],
      0,
    ).unwrap()
    assert_true(physical_equal(selected, plan.captures[0]))
    // The original acquisition owns its base reader. Its selected provider
    // adds the independently authored1111R/2222E before constructing a RowRun.
    let retained = @row_source_host.row_acquisition_retained_capacity(
        acquisition,
      ) +
      1111L
    let executing = @row_source_host.row_acquisition_execution_capacity(
        acquisition,
      ) +
      2222L
    let limits = @resources.ledger_limits(ledger)
    let usage = @resources.ledger_usage(ledger)
    let blocker = @resources.reserve_capacity(
      ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        retained +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes - executing + 1L
      },
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let starts = Ref(0)
    let result = start_installed_source_read_provider_rows(
      read,
      acquisition,
      Some(provider),
      "provider-source-one-short",
      _ => {
        starts.val += 1
        true
      },
      plan.transport_bytes[0],
      0L,
    )
    if retention {
      assert_true(result is Err(Acquisition(Physical(RetentionLimit))))
    } else {
      assert_true(result is Err(Acquisition(Physical(ExecutionLimit))))
    }
    assert_eq(starts.val, 0)
    assert_true(read.run is None)
    assert_eq(@resources.ledger_usage(ledger), before)
    retire_installed_source_read(read).unwrap()
    assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
    @resources.settle_capacity(ledger, blocker).unwrap()
    retire_installed_managed_run(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).attempts, usage.attempts)
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}

///|
test "provider Source handoff attaches the same original planned read once before a caller can substitute it" {
  let provider = @execution.execution_capacity(1111L, 2222L).unwrap()
  let plan = effect_operation_source_plan_fixture(provider=Some(provider))
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let foreign = effect_operation_source_plan_fixture(provider=Some(provider))
  assert_true(
    begin_installed_effect_managed_source_read(
      owner,
      foreign.declarations[0],
      0,
    )
    is Err(ForeignOriginal),
  )
  assert_true(owner.reads[0] is None)
  let (read, requirement, acquisition, capacity) = begin_installed_effect_managed_source_read(
    owner,
    plan.declarations[0],
    0,
  ).unwrap()
  assert_true(physical_equal(read, owner.reads[0].unwrap()))
  assert_true(
    read.requirement is Some(original) && physical_equal(original, requirement),
  )
  assert_true(
    read.acquisition is Some(original) && physical_equal(original, acquisition),
  )
  assert_true(physical_equal(capacity, plan.captures[0]))
  assert_true(
    begin_installed_effect_managed_source_read(owner, plan.declarations[0], 0)
    is Err(AlreadyBound),
  )
  assert_true(
    physical_equal(
      prepare_installed_effect_managed_run_ledger(
        owner,
        plan.prepared,
        plan.request,
        [capacity],
        plan.transport_bytes,
        plan.transport_execution_bytes,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
      ).unwrap(),
      require_installed_managed_run(owner).unwrap(),
    ),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_true(
    begin_installed_effect_managed_source_read(owner, plan.declarations[0], 0)
    is Err(Unsupported),
  )
}

///|
fn effect_native_source_plan_fixture(
  base : ClientInstalledEffectManagedPlan,
  inputs? : Array[ClientInstalledEffectSourceInput]? = None,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  let loader = publication_test_loader(publication_test_url())
  let native = prepare_installed_effect_duckdb_source_input(
    @planning.query_requirement_source(base.captures[0].requirement).0,
    "main",
    "records",
    capture_parent_contract(loader, "actql-query-acquisition.json"),
    capture_parent_contract(loader, "actql-query-process-evidence.json"),
    capture_parent_contract(loader, "actql-query-two-receipt.json"),
  ).unwrap()
  prepare_installed_effect_managed_source_plan(
    base.prepared,
    base.request,
    inputs.unwrap_or([native]),
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    base.transport_bytes,
    base.transport_execution_bytes,
    base.installed_contracts,
    base.values_body,
    base.fragment_body,
    base.ordered_body,
    base.operations,
    provider_factory=_ => [],
  )
}

///|
test "Effect native capture retains same Plan requirement capacity and Ledger without a Row read" {
  let base = effect_operation_source_plan_fixture()
  let plan = effect_native_source_plan_fixture(base).unwrap()
  assert_eq(plan.captures.length(), 1)
  assert_eq(plan.declarations.length(), 0)
  assert_eq(plan.acquisitions.length(), 0)
  assert_true(
    prepared_installed_effect_managed_source(plan, 0) is Err(Unsupported),
  )
  let mut currents = 0
  let (input, initial, _, parent) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => currents += 1,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    parent,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let before = currents
  let (requirement, capacity) = installed_effect_managed_duckdb_capture(
    owner,
    plan.prepared,
    plan.request,
    0,
  ).unwrap()
  assert_eq(currents - before, 1)
  assert_true(physical_equal(capacity, plan.captures[0]))
  assert_true(physical_equal(requirement, capacity.requirement))
  assert_true(
    @publication_host.client_query_requirement_matches_effect_program(
      plan.prepared,
      0,
      0,
      requirement,
    ),
  )
  assert_true(owner.reads[0] is None)
  let ledger = prepare_installed_effect_managed_run_ledger(
    owner,
    plan.prepared,
    plan.request,
    [capacity],
    plan.transport_bytes,
    plan.transport_execution_bytes,
    plan.installed_contracts,
    plan.values_body,
    plan.fragment_body,
    plan.ordered_body,
  ).unwrap()
  assert_true(
    physical_equal(ledger, require_installed_managed_run(owner).unwrap()),
  )
  let copied = { ..capacity, }
  assert_false(physical_equal(copied, capacity))
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      owner,
      plan.prepared,
      plan.request,
      [copied],
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  let foreign = effect_operation_source_plan_fixture()
  assert_true(
    installed_effect_managed_duckdb_capture(
      owner,
      foreign.prepared,
      plan.request,
      0,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_effect_managed_duckdb_capture(
      owner,
      plan.prepared,
      plan.request,
      1,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  retire_installed_managed_run(owner).unwrap()
  assert_true(
    installed_effect_managed_duckdb_capture(
      owner,
      plan.prepared,
      plan.request,
      0,
    )
    is Err(_),
  )
}

///|
test "Effect Source alternatives preserve original Row slot and reject absent or foreign native inputs" {
  let base = effect_operation_source_plan_fixture()
  let row = prepare_installed_effect_row_source_input(
    base.declarations[0],
    None,
  ).unwrap()
  let plan = effect_native_source_plan_fixture(base, inputs=Some([row])).unwrap()
  let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  assert_true(physical_equal(declaration, base.declarations[0]))
  assert_true(physical_equal(requirement, capacity.requirement))
  assert_true(physical_equal(acquisition, plan.acquisitions[0]))
  assert_true(capacity.original_input)
  assert_true(
    effect_native_source_plan_fixture(base, inputs=Some([]))
    is Err(ForeignOriginal),
  )
  let foreign = prepare_installed_effect_duckdb_source_input(
    "connector://foreign/records", "main", "records", "{}", "{}", "{}",
  ).unwrap()
  assert_true(
    effect_native_source_plan_fixture(base, inputs=Some([foreign]))
    is Err(ForeignOriginal),
  )
  let (input, initial, _, parent) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    parent,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  assert_true(
    installed_effect_managed_duckdb_capture(
      owner,
      plan.prepared,
      plan.request,
      0,
    )
    is Err(ForeignOriginal),
  )
  let (read, _, original, selected) = begin_installed_effect_managed_source_read(
    owner, declaration, 0,
  ).unwrap()
  assert_true(physical_equal(original, acquisition))
  assert_true(physical_equal(selected, capacity))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect mixed native and Row captures preserve checked occurrence order and original read slots" {
  let base = effect_operation_source_plan_fixture(additional_source=true)
  let loader = publication_test_loader(publication_test_url())
  let native = prepare_installed_effect_duckdb_source_input(
    @planning.query_requirement_source(base.captures[0].requirement).0,
    "main",
    "records",
    capture_parent_contract(loader, "actql-query-acquisition.json"),
    capture_parent_contract(loader, "actql-query-process-evidence.json"),
    capture_parent_contract(loader, "actql-query-two-receipt.json"),
  ).unwrap()
  let row = prepare_installed_effect_row_source_input(
    base.declarations[0],
    None,
  ).unwrap()
  for native_first in [true, false] {
    let inputs = if native_first { [native, row] } else { [row, native] }
    let plan = effect_native_source_plan_fixture(base, inputs=Some(inputs)).unwrap()
    assert_eq(plan.captures.length(), 2)
    assert_eq(plan.declarations.length(), 1)
    let native_index = if native_first { 0 } else { 1 }
    let row_index = 1 - native_index
    let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
      plan, row_index,
    ).unwrap()
    assert_true(physical_equal(declaration, base.declarations[0]))
    assert_true(physical_equal(acquisition, plan.acquisitions[0]))
    assert_true(physical_equal(requirement, capacity.requirement))
    assert_true(
      prepared_installed_effect_managed_source(plan, native_index)
      is Err(Unsupported),
    )
    let (input, initial, _, parent) = effect_parent_test_preparation(
      plan,
      prepared_installed_effect_managed_requirements(plan),
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial,
      input,
      parent,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    let (read, _, original, selected) = begin_installed_effect_managed_source_read(
      owner, declaration, row_index,
    ).unwrap()
    assert_true(physical_equal(original, acquisition))
    assert_true(physical_equal(selected, capacity))
    let (_, native_capacity) = installed_effect_managed_duckdb_capture(
      owner,
      plan.prepared,
      plan.request,
      native_index,
    ).unwrap()
    assert_true(physical_equal(native_capacity, plan.captures[native_index]))
    assert_true(owner.reads[native_index] is None)
    let ledger = prepare_installed_effect_managed_run_ledger(
      owner,
      plan.prepared,
      plan.request,
      plan.captures,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    ).unwrap()
    assert_true(
      physical_equal(ledger, require_installed_managed_run(owner).unwrap()),
    )
    retire_installed_source_read(read).unwrap()
    retire_installed_managed_run(owner).unwrap()
  }
}

///|
test "Effect native original capture reservation refuses exhaustion and current retirement without physical work" {
  let base = effect_operation_source_plan_fixture()
  let plan = effect_native_source_plan_fixture(base).unwrap()
  let (input, initial, ledger, parent) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    parent,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (_, capacity) = installed_effect_managed_duckdb_capture(
    owner,
    plan.prepared,
    plan.request,
    0,
  ).unwrap()
  let limits = @resources.ledger_limits(ledger)
  let usage = @resources.ledger_usage(ledger)
  let blocker = @resources.reserve_capacity(
    ledger,
    limits.retained_bytes - usage.held_bytes - usage.reserved_retention_bytes,
    0L,
  ).unwrap()
  let blocked = @resources.ledger_usage(ledger)
  assert_true(
    @resources.reserve_capacity(
      ledger,
      capacity.retained_bytes,
      capacity.execution_bytes,
    )
    is Err(RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), blocked)
  assert_eq(blocked.attempts, 0)
  assert_true(owner.reads[0] is None)
  @resources.settle_capacity(ledger, blocker).unwrap()
  retire_installed_managed_run(owner).unwrap()
  let selected : Ref[ClientInstalledManagedRun?] = { val: None, }
  let (input, initial, _, parent) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if selected.val is Some(original) {
        selected.val = None
        // Synchronous external current reentry may revoke the Run payload.
        original.preparation = None
      }
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    parent,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let original_preparation = owner.preparation
  selected.val = Some(owner)
  assert_true(
    installed_effect_managed_duckdb_capture(
      owner,
      plan.prepared,
      plan.request,
      0,
    )
    is Err(_),
  )
  assert_true(owner.reads[0] is None)
  // Restore only the explicit whitebox payload to retire the original parent;
  // the failed getter did not publish or recreate any capture or read.
  owner.preparation = original_preparation
  retire_installed_managed_run(owner).unwrap()
}

///|
test "installed Query keeps both original 71-field schemas under their separate field bounds" {
  // A real Account declaration has71 fields. Its physical capture keeps that
  // full schema while its selected business Result projects only id.
  let plan = effect_operation_source_plan_fixture(source_width=71)
  let (_, requirement, _, _) = prepared_installed_effect_managed_source(plan, 0).unwrap()
  let query = @query.query_sequence_requirement(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
  )
  let pipeline = @sourceviews.query_acquisition_pipeline(query)
  assert_eq(
    @schema.field_count(
      @pipeline.schema_at(pipeline, @sourceviews.query_acquisition_input(query)).unwrap(),
    ),
    71,
  )
  assert_eq(
    @schema.field_count(
      @pipeline.schema_at(
        pipeline,
        @sourceviews.query_acquisition_capture(query),
      ).unwrap(),
    ),
    71,
  )
}

///|
test "installed Query aggregate traversal does not relax an explicit issuer field bound" {
  let plan = effect_operation_source_plan_fixture(source_width=71)
  let (_, requirement, _, _) = prepared_installed_effect_managed_source(plan, 0).unwrap()
  assert_true(
    @planning.prepare_query_requirement(
      @planning.query_requirement_material(requirement),
      @planning.query_requirement_program(requirement),
      @planning.query_requirement_guards(requirement),
      installed_local_query_material_limits(),
    )
    is Err(FieldLimit),
  )
}

///|
test "installed Query backs two full individually bounded schema inventories" {
  let plan = effect_operation_source_plan_fixture(source_width=100)
  let (_, requirement, _, _) = prepared_installed_effect_managed_source(plan, 0).unwrap()
  let query = @query.query_sequence_requirement(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
  )
  let limits = installed_local_query_requirement_limits(query).unwrap()
  assert_eq(limits.max_fields, 200)
  let original = installed_local_query_material_limits()
  assert_eq(limits.max_work, original.max_work)
  assert_eq(limits.max_parameters, original.max_parameters)
  assert_eq(limits.max_bytes, original.max_bytes)
  assert_eq(limits.max_nodes, original.max_nodes)
  assert_eq(limits.max_depth, original.max_depth)
}
