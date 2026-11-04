///|
// Actual JSON/Parameters/check/compiler/Model Plan and ordinary Node admission.
// Provider and Scope byte frames are explicit logical component ports, not a
// complete physical Model/Host recipe, permission or normal runtime acceptance.
fn expected_request_model_scope_controls(
  reservations : Int,
  holdings : Int,
  delegations : Int,
) -> Int64 {
  let initial = @resources.preparation_inventory_initial_control_slots(6, 0, 0).unwrap()
  let selected = @resources.preparation_inventory_initial_control_slots(
    Int::max(6, reservations),
    holdings,
    delegations,
  ).unwrap()
  // Independent field inventory: Model origin has five borrowed references;
  // Scope has four references and four partition/lifecycle words. Its later
  // read record adds one reference/two words, and Resource's resident claim
  // group slot adds one reference. Neither copies Program/Graph/CID backing.
  // Resource owns its census-slot shape and supplies only that slot delta.
  @execution.preparation_representation_cost({
    record_headers: 2L + selected.0 - initial.0,
    reference_slots: 11L + selected.1 - initial.1,
    scalar_words: 6L + selected.2 - initial.2,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
fn request_effect_model_plan_fixture(
  current? : () -> Bool = () => true,
  model_initial? : Bool = true,
  configure_quantities? : Bool = true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  ClientInstalledEffectManagedPlan,
  @publication_host.ClientRequestIdentity,
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
) raise {
  let (environment, document) = effect_model_plan_source()
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  // Compose the same selected profile before input, using the existing fold.
  // This explicit component entrance is not C's full physical first recipe.
  let initial_limits = if model_initial {
    @resources.add_ledger_limits(ordinary, effect_model_plan_limits).unwrap()
  } else {
    ordinary
  }
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=document,
    environment=Some(environment),
    effect_limits=Some(
      @publication_host.client_standard_effect_computation_limits(),
    ),
    initial_limits=Some(initial_limits),
  )
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_effect_program_check_preparation(child).unwrap()
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let capacity = parent.effect_capacity.unwrap()
  // Real original preparation-input work precedes Run binding. It must stay
  // consumed across configuration, Model Scope, adoption and final retirement.
  let operation = @resources.begin_preparation_io(capacity, input, 2L).unwrap()
  @resources.charge_preparation_io(operation, 1L).unwrap()
  @resources.finish_preparation_io_after_cleanup(operation).unwrap()
  if configure_quantities {
    @resources.configure_quantities(parent.ledger, {
      tokens: 128L,
      cost_units: 0L,
      duration_ms: 1000L,
    }).unwrap()
  }
  let construction = borrow_request_effect_plan_input(parent, input).unwrap()
  let (_, request, contracts, model) = effect_model_plan_for_prepared(prepared)
  let calls = Ref(0)
  let plan = effect_model_plan_fixture(
    prepared, request, contracts, model, calls,
  )
  assert_eq(calls.val, 1)
  // Runtime children reserve their own bodies on this SAME Ledger later.
  // They cannot prepay the Scope/census constructor or provide spare credit.
  (parent, input, plan, request, construction)
}

///|
test "Effect Scope funds its new origin and original census before binding without reserving runtime Plan twice" {
  let (parent, input, plan, request, construction) = request_effect_model_plan_fixture()
  let selected = plan.model.unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let increment = expected_request_model_scope_controls(
    selected.max_reservations,
    selected.max_holdings,
    selected.max_delegations,
  )
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((before.0 + increment, before.1 + increment)),
  )
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      selected.compiled,
      selected.definition,
      selected.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect Scope one-short growth retains one absolute quote and original Plan until retry or abort" {
  for retention in [true, false] {
    let (parent, input, plan, request, construction) = request_effect_model_plan_fixture()
    let selected = plan.model.unwrap()
    let capacity = parent.effect_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let increment = expected_request_model_scope_controls(
      selected.max_reservations,
      selected.max_holdings,
      selected.max_delegations,
    )
    let limits = @resources.ledger_limits(parent.ledger)
    let block = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - increment + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - increment + 1L
      },
    ).unwrap()
    assert_true(
      prepare_request_effect_model_read_scope(parent, input, plan)
      is Err(Preparation(Resource(_))),
    )
    let quote = parent.program_domain_quote
    assert_eq(quote, Some((before.0 + increment, before.1 + increment)))
    assert_true(parent.phase == EffectModelScopeQuoted)
    assert_true(
      parent.effect_plan is Some(original) && physical_equal(original, plan),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(before),
    )
    assert_true(
      complete_request_effect_preparation(parent, input, plan)
      is Err(WrongPhase),
    )
    let copied = { ..plan, rows: plan.rows, }
    assert_true(
      prepare_request_effect_model_read_scope(parent, input, copied)
      is Err(ForeignOriginal),
    )
    assert_true(
      prepare_request_effect_model_read_scope(parent, input, plan)
      is Err(Preparation(Resource(_))),
    )
    assert_eq(parent.program_domain_quote, quote)
    @resources.settle_capacity(parent.ledger, block).unwrap()
    let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
    assert_true(parent.program_domain_quote is None)
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((before.0 + increment, before.1 + increment)),
    )
    complete_request_effect_preparation(parent, input, plan).unwrap()
    @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
    let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope,
        selected.compiled,
        selected.definition,
        selected.graph,
        true,
      ).unwrap(),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
  let (parent, input, plan, _, construction) = request_effect_model_plan_fixture()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let limits = @resources.ledger_limits(parent.ledger)
  let block = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - before.0,
    0L,
  ).unwrap()
  assert_true(
    prepare_request_effect_model_read_scope(parent, input, plan)
    is Err(Preparation(Resource(_))),
  )
  @resources.settle_capacity(parent.ledger, block).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_domain_quote is None && parent.effect_plan is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "ordinary initial Model keeps actual work history and refuses exhausted work before allocation" {
  let (parent, input, plan, request, construction) = request_effect_model_plan_fixture(
    model_initial=false,
  )
  let ledger = parent.ledger
  let limits = @resources.ledger_limits(ledger)
  assert_false(installed_effect_limits_fit(plan.limits, limits))
  @resources.charge_planning(ledger, 1).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  assert_eq(@resources.ledger_usage(ledger).planning_work, before.planning_work)
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    before.transferred_bytes,
  )
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let owner = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
  assert_true(
    physical_equal(require_installed_managed_run(owner).unwrap(), ledger),
  )
  assert_eq(@resources.ledger_limits(ledger), limits)
  @resources.charge_planning(
    ledger,
    limits.planning_work - before.planning_work,
  ).unwrap()
  let exhausted = @resources.ledger_usage(ledger)
  assert_true(@resources.charge_planning(ledger, 1) is Err(PlanningLimit))
  assert_eq(@resources.ledger_usage(ledger), exhausted)
  let selected = plan.model.unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      selected.compiled,
      selected.definition,
      selected.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).planning_work, limits.planning_work)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "same Request Effect Model retains original Scope Plan input history and both cleanup owners" {
  let currents = Ref(0)
  let (parent, input, plan, request, construction) = request_effect_model_plan_fixture(current=() => {
      currents.val += 1
      true
    },
  )
  let selected = plan.model.unwrap()
  let ledger = parent.ledger
  let capacity = parent.effect_capacity.unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    capacity, input,
  ).unwrap()
  let extents = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let before = @resources.ledger_usage(ledger)
  let calls = currents.val
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  assert_eq(currents.val, calls + 1)
  let increment = expected_request_model_scope_controls(
    selected.max_reservations,
    selected.max_holdings,
    selected.max_delegations,
  )
  let after_scope = @resources.ledger_usage(ledger)
  assert_eq(
    after_scope.reserved_retention_bytes,
    before.reserved_retention_bytes + increment,
  )
  assert_eq(
    after_scope.reserved_execution_bytes,
    before.reserved_execution_bytes + increment,
  )
  assert_eq(after_scope.planning_work, before.planning_work)
  assert_eq(after_scope.attempts, before.attempts)
  assert_eq(after_scope.live_reservations, before.live_reservations)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((extents.0 + increment, extents.1 + increment)),
  )
  assert_true(
    @publication_host.client_model_read_scope_original_inventory(
      scope, ledger, identity,
    ),
  )
  assert_true(
    prepare_request_effect_model_read_scope(parent, input, plan)
    is Err(ForeignOriginal),
  )
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let held = borrow_request_effect_preparation(parent).unwrap()
  let calls = currents.val
  assert_true(
    begin_request_effect_managed_run(parent, request) is Err(Unsupported),
  )
  assert_eq(currents.val, calls)
  let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
  assert_eq(currents.val, calls + 1)
  assert_true(physical_equal(run.ledger.unwrap(), ledger))
  assert_true(
    run.preparation is Some(PlannedEffectManaged(_, original)) &&
    physical_equal(original, plan),
  )
  assert_true(parent.phase == Selected && parent.effect_plan is None)
  assert_true(
    preparation_initial_input(parent.initial, input)
    is Err(@resources.AlreadyConsumed),
  )
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  assert_true(
    physical_equal(
      @publication_host.handoff_client_model_read(
        read,
        selected.compiled,
        selected.definition,
        selected.graph,
      ).unwrap(),
      ledger,
    ),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_false(
    @publication_host.finish_client_model_read_inventory(
      read,
      selected.compiled,
      selected.definition,
      selected.graph,
      false,
    ).unwrap(),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @publication_host.finish_client_model_read_inventory(
      read,
      selected.compiled,
      selected.definition,
      selected.graph,
      true,
    ).unwrap(),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.ledger_usage(ledger).live_reservations > 0)
  assert_true(
    @resources.preparation_body_borrow_value(held) is Some(original) &&
    physical_equal(original, plan),
  )
  @resources.return_preparation_body_borrow(held).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_true(run.ledger is None)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.reserved_retention_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.planning_work, before.planning_work)
  assert_true(after.attempts >= 1 && after.transferred_bytes >= 1L)
  assert_eq(@resources.quantity_usage(ledger).consumed.tokens, 0L)
}

///|
test "same Request Model Scope refuses a replacement Plan equal Request and foreign live census" {
  let (parent, input, plan, request, construction) = request_effect_model_plan_fixture()
  let selected = plan.model.unwrap()
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  let replacement = effect_model_plan_fixture(
    plan.prepared,
    request,
    plan.installed_contracts,
    selected,
    Ref(0),
  )
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    complete_request_effect_preparation(parent, input, replacement)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(
    parent.effect_plan is Some(original) && physical_equal(original, plan),
  )
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let foreign_input = [1]
  let foreign_ledger = @resources.create_ledger(selected.limits).unwrap()
  let foreign : @resources.PreparationCapacity[Array[Int], Unit] = @resources.reserve_preparation_capacity_inventory(
    foreign_ledger,
    foreign_input,
    3L,
    2L,
    max_borrowers=2,
  ).unwrap()
  let foreign_identity = @resources.preparation_capacity_inventory_original(
    foreign, foreign_input,
  ).unwrap()
  let foreign_scope = @publication_host.bind_client_model_read_scope(
    selected.compiled,
    selected.definition,
    selected.graph,
    foreign_ledger,
    foreign_identity,
  ).unwrap()
  assert_true(
    @publication_host.client_model_read_scope_live(
      foreign_scope,
      selected.compiled,
      selected.definition,
      selected.graph,
    ),
  )
  assert_true(
    begin_request_effect_model_managed_run(parent, request, foreign_scope)
    is Err(ForeignOriginal),
  )
  let equal_request = @publication_host.prepare_client_effect_request_identity(
    plan.prepared,
    "sha256:" + "a".repeat(64),
    "model-effect-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(
    begin_request_effect_model_managed_run(parent, equal_request, scope)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(parent.phase == EffectBodyReady)
  @publication_host.finish_client_model_read_scope(
    foreign_scope,
    selected.compiled,
    selected.definition,
    selected.graph,
    true,
  ).unwrap()
  |> ignore
  @resources.abort_preparation_capacity_after_cleanup(foreign, foreign_input).unwrap()
  |> ignore
  @publication_host.finish_client_model_read_scope(
    scope,
    selected.compiled,
    selected.definition,
    selected.graph,
    true,
  ).unwrap()
  |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model Scope closing inside original adoption current leaves the same Request cleanup owner" {
  let armed = Ref(false)
  let acknowledged = Ref(false)
  let original : Ref[
    (@publication_host.ClientModelReadScope, ClientInstalledEffectModelDemand)?,
  ] = Ref(None)
  let (parent, input, plan, request, construction) = request_effect_model_plan_fixture(current=() => {
      if armed.val {
        armed.val = false
        let (scope, selected) = original.val.unwrap()
        acknowledged.val = @publication_host.finish_client_model_read_scope(
          scope,
          selected.compiled,
          selected.definition,
          selected.graph,
          true,
        ).unwrap()
      }
      true
    },
  )
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  original.val = Some((scope, plan.model.unwrap()))
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let before = @resources.ledger_usage(parent.ledger)
  armed.val = true
  assert_true(
    begin_request_effect_model_managed_run(parent, request, scope)
    is Err(
      Resource(
        @resources.ImportedChildLedgerIssue::Resource(
          @resources.ClosedReservation
        )
      )
    ),
  )
  assert_true(acknowledged.val)
  assert_true(parent.phase == EffectBodyReady && parent.input is Some(_))
  assert_true(preparation_initial_input(parent.initial, input) is Ok(_))
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect Model configures selected quantities on its original preparation before read binding without resetting input work" {
  let declarations : Array[@resources.QuantityAmounts] = [
    { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    { tokens: 1000L, cost_units: 1000L, duration_ms: 2000L, },
  ]
  for installed in declarations {
    let (parent, input, plan, request, construction) = request_effect_model_plan_fixture(
      configure_quantities=false,
    )
    let selected = plan.model.unwrap()
    let before = @resources.ledger_usage(parent.ledger)
    assert_true(@resources.quantity_configuration_matches(parent.ledger, None))
    let scope = prepare_request_effect_model_read_scope(
      parent,
      input,
      plan,
      quantity_limits=Some(installed),
    ).unwrap()
    assert_true(
      @resources.quantity_configuration_matches(
        parent.ledger,
        Some({
          tokens: Int64::min(installed.tokens, 128L),
          cost_units: 0L,
          duration_ms: Int64::min(installed.duration_ms, 1000L),
        }),
      ),
    )
    assert_eq(@resources.ledger_usage(parent.ledger).attempts, before.attempts)
    assert_eq(
      @resources.ledger_usage(parent.ledger).transferred_bytes,
      before.transferred_bytes,
    )
    assert_true(before.attempts > 0 && before.transferred_bytes > 0L)
    complete_request_effect_preparation(parent, input, plan).unwrap()
    @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
    let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope,
        selected.compiled,
        selected.definition,
        selected.graph,
        true,
      ).unwrap(),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(parent.ledger).attempts, before.attempts)
  }
}
