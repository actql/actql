///|
fn effect_operation_borrow_fixture() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
) {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  // Existing explicit 10-byte initial carrier tests original accounting only;
  // it is not the final normal Host constructor/implementation recipe.
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  (prepared, request, plan, owner, ledger)
}

///|
test "original implementation control material is debited before any grant or body constructor" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let baseline = effect_operation_plan_fixture(prepared, request, contracts)
  let plan = effect_operation_plan_with_control_fixture(
    prepared,
    request,
    contracts,
    baseline,
    @execution.execution_capacity(7L, 11L).unwrap(),
  ).unwrap()
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let before = @resources.ledger_usage(ledger)
  ignore(
    begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap(),
  )
  let held = @resources.ledger_usage(ledger)
  assert_eq(
    held.reserved_retention_bytes - before.reserved_retention_bytes,
    @execution.execution_capacity_retained_bytes(
      plan.operation_control_capacity,
    ),
  )
  assert_eq(
    held.reserved_execution_bytes - before.reserved_execution_bytes,
    @execution.execution_capacity_execution_bytes(
      plan.operation_control_capacity,
    ),
  )
  assert_eq(held.attempts, before.attempts)
  assert_eq(held.reserved_attempts, before.reserved_attempts)
  assert_eq(held.transferred_bytes, before.transferred_bytes)
  assert_eq(held.reserved_transfer_bytes, before.reserved_transfer_bytes)
  ignore(
    begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    held.reserved_retention_bytes,
  )
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
}

///|
test "Effect operation reserves original occurrence before construction and retains failed cleanup" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let before = @resources.ledger_usage(ledger)
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let reserved = @resources.ledger_usage(ledger)
  let control_retained = @execution.execution_capacity_retained_bytes(
    plan.operation_control_capacity,
  )
  let control_execution = @execution.execution_capacity_execution_bytes(
    plan.operation_control_capacity,
  )
  assert_eq(
    reserved.reserved_retention_bytes,
    before.reserved_retention_bytes + control_retained + 50L,
  )
  assert_eq(
    reserved.reserved_execution_bytes,
    before.reserved_execution_bytes + control_execution + 70L,
  )
  assert_eq(reserved.reserved_attempts, before.reserved_attempts)
  assert_true(start_installed_effect_operation(operation) is Err(Unsupported))
  assert_true(retire_installed_effect_operation(operation, false) is Ok(false))
  assert_eq(@resources.ledger_usage(ledger), reserved)
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes + control_retained,
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  assert_true(
    operation.owner is None &&
    operation.ledger is None &&
    operation.backing is None,
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect physical occurrence spends once and original lost reply stays uncertain after cleanup" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "operation",
  ).unwrap()
  assert_true(
    charge_installed_effect_operation(operation, 1L) is Err(Unsupported),
  )
  let before = @resources.ledger_usage(ledger)
  start_installed_effect_operation(operation).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 1)
  assert_true(start_installed_effect_operation(operation) is Err(AlreadyBound))
  charge_installed_effect_operation(operation, 5L).unwrap()
  mark_installed_effect_operation_transfer_uncertain(operation, 8L).unwrap()
  let unknown = @resources.ledger_usage(ledger)
  assert_eq(unknown.transferred_bytes, before.transferred_bytes + 5L)
  assert_eq(
    unknown.uncertain_transfer_bytes,
    before.uncertain_transfer_bytes + 8L,
  )
  assert_true(retire_installed_effect_operation(operation, false) is Ok(false))
  assert_eq(@resources.ledger_usage(ledger), unknown)
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  assert_eq(@resources.ledger_usage(ledger).attempts, unknown.attempts)
  assert_eq(
    @resources.ledger_usage(ledger).uncertain_transfer_bytes,
    unknown.uncertain_transfer_bytes,
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 0, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  // Actual physical cleanup does not invent an observed byte amount or
  // erase the existing B uncertainty history. Root remains pending here.
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
}

///|
test "Effect occurrence refuses foreign Plan request name and row before reserving" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let (_, foreign_request, _) = effect_operation_plan_inputs()
  let foreign_plan = effect_operation_plan_fixture(
    prepared,
    request,
    prepare_installed_sequence_contracts(
      source_query_original_registry,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    ).unwrap(),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, foreign_request, plan, 0, true, 0, 0, "operation",
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, foreign_plan, 0, true, 0, 0, "operation",
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner,
      prepared,
      request,
      plan,
      0,
      true,
      0,
      plan.rows,
      "operation",
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 0, 0, "foreign",
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect operation constructor fences same-parent reentry before current callback" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let owner_ref : Ref[ClientInstalledManagedRun?] = Ref(None)
  let refusals : Ref[Int] = Ref(0)
  let valid : Ref[Bool] = Ref(true)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if owner_ref.val is Some(owner) && owner.effect_operation_opening {
        valid.val = valid.val &&
          borrow_installed_effect_operation(
            owner, prepared, request, plan, 0, true, 2, 0, "operation",
          )
          is Err(AlreadyBound) &&
          retire_installed_managed_run(owner) is Err(CleanupPending)
        refusals.val += 1
      }
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  owner_ref.val = Some(owner)
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  assert_true(refusals.val > 0 && valid.val)
  assert_eq(owner.effect_operations.length(), 1)
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  retire_installed_managed_run(owner).unwrap()
  owner_ref.val = None
}

///|
test "one Effect operation borrow observes original current once for Plan and Ledger" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let calls : Ref[Int] = Ref(0)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let before = calls.val
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  assert_eq(calls.val - before, 1)
  assert_true(retire_installed_effect_operation(operation, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "atomic Effect borrow refuses callback retirement before any operation reservation" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let selected : Ref[ClientInstalledManagedRun?] = Ref(None)
  let invalidate : Ref[Bool] = Ref(false)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if invalidate.val && selected.val is Some(owner) {
        owner.ledger = None
      }
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  selected.val = Some(owner)
  let ledger = owner.ledger.unwrap()
  let before = @resources.ledger_usage(ledger)
  invalidate.val = true
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(Retired),
  )
  assert_true(owner.effect_operations.is_empty())
  assert_eq(@resources.ledger_usage(ledger), before)
  // The whitebox callback invalidated only this original owner's local link.
  // Restore that same link solely to discharge the fixture's cleanup duties.
  invalidate.val = false
  owner.ledger = Some(ledger)
  retire_installed_managed_run(owner).unwrap()
  selected.val = None
}

///|
extern "js" fn effect_plan_node_original(
  loader : PublicationTestLoader,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  contracts : ClientInstalledSequenceContracts,
  values : String,
  fragment : String,
  extent : ClientInstalledEffectOperationExtent,
  demand : (
    @publication_host.PreparedClientEffectComputation,
    Int,
    String,
    FixedArray[ClientInstalledEffectOperationExtent],
    FixedArray[ClientInstalledEffectOperationExtent],
  ) -> Result[
    ClientInstalledEffectOperationDemand,
    ClientInstalledManagedRunIssue,
  ],
  construct : (
    @publication_host.PreparedClientEffectComputation,
    @publication_host.ClientRequestIdentity,
    ClientInstalledSequenceContracts,
    FixedArray[ClientInstalledEffectOperationDemand],
  ) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue],
  sources : (@publication_host.PreparedClientEffectComputation) -> Int,
) -> ClientInstalledEffectManagedPlan =
  #|(loader,prepared,request,contracts,values,fragment,extent,demand,construct,sources) => {
  #| const helper=loader('../../../../../adapters/host-node/installed-effect-plan.mjs');
  #| const recipe=helper.captureInstalledEffectPlanRecipe(Object.freeze({memberOperations:Object.freeze([]),rowOperations:Object.freeze([Object.freeze({operation:'operation',extent})])}),4);
  #| const moon={clientProgramEffectAcquisitionCount:sources,clientProgramInstalledEffectOperationDemandPrepare:demand,
  #|   clientProgramInstalledEffectManagedPlanPrepare(...args){
  #|     if(args.length!==12||args[0]!==prepared||args[1]!==request||args[2].length||args[3]!==''||args[4]!==''||args[5].length||args[6].length||args[7]!==contracts||args[8]!==values||args[9]!==fragment||args[10]!==undefined)throw new Error('ChangedOriginalEffectPlanArguments');
  #|     return construct(args[0],args[1],args[7],args[11]);
  #|   }};
  #| return helper.prepareInstalledEffectManagedPlan({moon,facts:{prepared,identity:request},inputs:{installedContracts:contracts,values,fragment},unit:{stageIndex:0},members:[{effectId:'save'}],recipeFor:()=>recipe});
  #| }

///|
test "actual Node Effect plan helper returns the original typed Core Plan for same Request adoption" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(100L, 200L).unwrap(),
    10L,
    true,
  ).unwrap()
  let plan = effect_plan_node_original(
    publication_test_loader(publication_test_url()),
    prepared,
    request,
    contracts,
    source_query_original_values,
    source_query_original_fragment,
    extent,
    (original, stage, name, members, rows) => {
      prepare_installed_effect_operation_demand(
        original,
        stage,
        name,
        Array::from_fixed_array(members),
        Array::from_fixed_array(rows),
      )
    },
    (original, identity, selected, demands) => {
      prepare_installed_effect_managed_plan(
        original,
        identity,
        [],
        "",
        "",
        [],
        [],
        selected,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
        Array::from_fixed_array(demands),
        provider_factory=_ => [],
      )
    },
    original => {
      @strategy.graph_captured_prefix(
        @strategy.checked_effect_computation_graph(
          @publication_host.prepared_client_effect_computation_graph(original),
        ),
      )
    },
  )
  assert_true(physical_equal(plan.prepared, prepared))
  assert_true(physical_equal(plan.request, request))
  assert_true(
    physical_equal(
      prepared_installed_effect_managed_operation(plan, 0, true, 0, "operation").unwrap(),
      extent,
    ),
  )
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(owner, prepared, request).unwrap(),
      plan,
    ),
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect spent occurrence controls stay debited on the same Ledger until Run retirement" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let before = @resources.ledger_usage(ledger)
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(held.live_reservations, before.live_reservations + 2)
  assert_true(
    held.reserved_retention_bytes > before.reserved_retention_bytes + 50L,
  )
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  let closed_child = @resources.ledger_usage(ledger)
  assert_eq(closed_child.live_reservations, before.live_reservations + 1)
  assert_true(
    closed_child.reserved_retention_bytes > before.reserved_retention_bytes,
  )
  assert_eq(owner.effect_operations.length(), 1)
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  retire_installed_managed_run(owner).unwrap()
  assert_eq(owner.effect_operations.length(), 0)
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(_),
  )
}

///|
test "Effect cleanup refuses a copied operation view before and after original retirement" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let copied : ClientInstalledEffectOperationBorrow = { ..operation, }
  let before = @resources.ledger_usage(ledger)
  assert_true(
    retire_installed_effect_operation(copied, true) is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  let retired_copy : ClientInstalledEffectOperationBorrow = { ..operation, }
  assert_true(
    retire_installed_effect_operation(retired_copy, true)
    is Err(ForeignOriginal),
  )
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  retire_installed_managed_run(owner).unwrap()
}

///|
test "original Effect controls are debited once before the consumer borrows a body" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let before = @resources.ledger_usage(ledger)
  let copy : ClientInstalledEffectManagedPlan = { ..plan, }
  assert_true(
    begin_installed_effect_operation_controls(owner, prepared, request, copy)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    physical_equal(
      begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap(),
      plan,
    ),
  )
  let original = owner.effect_operation_controls.unwrap()
  let debited = @resources.ledger_usage(ledger)
  assert_eq(
    debited.reserved_retention_bytes,
    before.reserved_retention_bytes +
    @execution.execution_capacity_retained_bytes(
      plan.operation_control_capacity,
    ),
  )
  assert_true(
    physical_equal(
      begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap(),
      plan,
    ),
  )
  assert_true(
    physical_equal(original, owner.effect_operation_controls.unwrap()),
  )
  assert_eq(@resources.ledger_usage(ledger), debited)
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  assert_true(
    physical_equal(original, owner.effect_operation_controls.unwrap()),
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    debited.reserved_retention_bytes + 50L,
  )
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "one-short Effect controls refuse before any operation view is constructed" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let before = @resources.ledger_usage(ledger)
  let controls = @execution.execution_capacity_retained_bytes(
    plan.operation_control_capacity,
  )
  // Unused-capacity accounting fixture, not an actual allocated backing body.
  let bytes = @resources.ledger_limits(ledger).retained_bytes -
    before.held_bytes -
    before.reserved_retention_bytes -
    controls +
    1L
  assert_true(bytes > 0L)
  let pressure = @resources.reserve_capacity(ledger, bytes, 0L).unwrap()
  assert_true(
    begin_installed_effect_operation_controls(owner, prepared, request, plan)
    is Err(Ledger(@resources.RetentionLimit)),
  )
  assert_true(owner.effect_operation_controls is None)
  assert_eq(owner.effect_operations.length(), 0)
  assert_false(owner.effect_operation_opening)
  @resources.settle_capacity(ledger, pressure).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
test "member capture and row constructor retain distinct original same Request reservations" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  // Accounting fixture DATA only; this is not the normal capture recipe or
  // constructor census. Both handles use the actual original Plan and Ledger.
  let extent = prepare_installed_effect_operation_extent(
    "capture",
    @execution.execution_capacity(50L, 70L).unwrap(),
    0L,
    false,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [extent],
    [extent],
  ).unwrap()
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
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  assert_true(
    physical_equal(
      begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap(),
      plan,
    ),
  )
  let before = @resources.ledger_usage(ledger)
  let capture_prefix = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let row = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "capture",
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes + 100L,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes + 140L,
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, false, 0, 1, "capture",
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, false, 0, 0, "capture",
    )
    is Err(AlreadyBound),
  )
  assert_false(
    retire_installed_effect_operation(capture_prefix, false).unwrap(),
  )
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(capture_prefix, true).unwrap())
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(row, true).unwrap())
  let released = @resources.ledger_usage(ledger)
  assert_eq(released.live_reservations, before.live_reservations)
  assert_eq(released.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(released.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(released.peak_retention_bytes, before.peak_retention_bytes + 100L)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "ordinary prepaid Effect operation controls still observe current once for a body borrow" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let calls = Ref(0)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  assert_true(
    physical_equal(
      begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap(),
      plan,
    ),
  )
  let original = owner.effect_operation_controls.unwrap()
  let before = calls.val
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  assert_eq(calls.val, before + 1)
  assert_true(
    owner.effect_operation_controls is Some(control) &&
    physical_equal(control, original),
  )
  assert_true(retire_installed_effect_operation(operation, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect control initialization returns the original Plan after one current and preserves reuse" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let calls = Ref(0)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let before = calls.val
  let first = begin_installed_effect_operation_controls(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(calls.val, before + 1)
  assert_true(physical_equal(first, plan))
  let control = owner.effect_operation_controls.unwrap()
  let debited = @resources.ledger_usage(owner.ledger.unwrap())
  let before = calls.val
  let again = begin_installed_effect_operation_controls(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(calls.val, before + 1)
  assert_true(physical_equal(again, plan))
  assert_true(
    owner.effect_operation_controls is Some(original) &&
    physical_equal(original, control),
  )
  assert_eq(@resources.ledger_usage(owner.ledger.unwrap()), debited)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "zero Effect occurrences still retain the fixed control initialization frame" {
  let capacity = installed_effect_operation_control_capacity(0).unwrap()
  // Existing conservative Host-call upper:34 headers16 +145 refs8 +18 words8.
  // This is the fixed call, not an invented operation or an attempt allowance.
  let fixed_frame = 34L * 16L + 145L * 8L + 18L * 8L
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity)
  assert_true(retained >= fixed_frame)
  assert_true(execution >= retained)
}

///|
// Actual checked Program/Compute/operation Plan; no physical grant or normal
// runtime here. The same closed row fact supplies capture storage only once.
test "standard capture extent resolves same checked zero and three rows before its original member borrow" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  for count in [0, 3] {
    let rows = if count == 0 {
      "[]"
    } else {
      "[{\"id\":1},{\"id\":2},{\"id\":3}]"
    }
    let document = "{\"version\":\"actql/0.1\",\"id\":\"standard-capture-rows\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
      rows +
      "},\"as\":\"seed\"}],\"results\":{\"rows\":{\"from\":\"seed\",\"fields\":[\"id\"]}},\"effects\":{\"save\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"rows\"},\"id\":\"id\",\"set\":{\"Name\":{\"field\":\"id\"}}}}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
    let prepared = @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    let request = @publication_host.prepare_client_effect_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "standard-capture-rows",
      "sha256:" + "b".repeat(64),
    ).unwrap()
    let template = prepare_installed_effect_capture_extent(
      "capture",
      @execution.execution_capacity(13L, 17L).unwrap(),
      @execution.execution_capacity(37L, 61L).unwrap(),
    ).unwrap()
    let demand = prepare_installed_effect_operation_demand(
      prepared,
      0,
      "save",
      [template],
      [],
    ).unwrap()
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
    assert_eq(plan.rows, count)
    assert_true(
      physical_equal(
        plan.capacity_plan,
        plan.source_free.unwrap().capacity_plan,
      ),
    )
    let selected = prepared_installed_effect_managed_operation(
      plan, 0, false, 0, "capture",
    ).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected.capacity),
      13L + 37L * count.to_int64(),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(selected.capacity),
      17L + 61L * count.to_int64(),
    )
    assert_true(selected.checked_row_capacity is None)
    assert_true(template.checked_row_capacity is Some(_))
    assert_eq(
      @execution.execution_capacity_retained_bytes(template.capacity),
      13L,
    )
    assert_eq(prepared_installed_effect_managed_capture_children(plan), 1)
    assert_eq(plan.limits.attempts, plan._observed_compute_limits.attempts)
    assert_eq(
      plan.limits.transfer_bytes,
      plan._observed_compute_limits.transfer_bytes,
    )
    let (input, initial, _, capacity) = effect_parent_test_preparation(
      plan,
      prepared_installed_effect_managed_requirements(plan),
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, plan,
    ).unwrap()
    let ledger = owner.ledger.unwrap()
    let before = @resources.ledger_usage(ledger)
    let child = borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, false, 0, 0, "capture",
    ).unwrap()
    let during = @resources.ledger_usage(ledger)
    assert_eq(
      during.reserved_retention_bytes,
      before.reserved_retention_bytes +
      @execution.execution_capacity_retained_bytes(
        plan.operation_control_capacity,
      ) +
      13L +
      37L * count.to_int64(),
    )
    assert_true(retire_installed_effect_operation(child, false) is Ok(false))
    assert_eq(@resources.ledger_usage(ledger), during)
    assert_true(retire_installed_effect_operation(child, true) is Ok(true))
    assert_true(
      borrow_installed_effect_operation(
        owner, prepared, request, plan, 0, false, 0, 0, "capture",
      )
      is Err(AlreadyBound),
    )
    retire_installed_managed_run(owner).unwrap()
  }
}

///|
test "completed Effect row constructor returns only workspace on SAME token and current once" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let calls = Ref(0)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let observations = calls.val
  complete_installed_effect_operation_construction(operation).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(calls.val, observations + 1)
  assert_eq(after, {
    ..before,
    reserved_execution_bytes: before.reserved_execution_bytes - 20L,
  })
  assert_true(operation.backing is Some(_))
  assert_true(retire_installed_effect_operation(operation, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  complete_installed_effect_operation_construction(operation).unwrap()
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  let copied = { ..operation, }
  assert_true(
    complete_installed_effect_operation_construction(copied)
    is Err(ForeignOriginal),
  )
  assert_true(retire_installed_effect_operation(operation, true).unwrap())
  assert_true(
    complete_installed_effect_operation_construction(operation) is Err(Retired),
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect construction completion cannot dispose a physical operation or reentered retired original" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let on_current : Ref[() -> Unit] = Ref(() => ())
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => (on_current.val)(),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let physical = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "operation",
  ).unwrap()
  let physical_held = @resources.ledger_usage(ledger)
  assert_true(
    complete_installed_effect_operation_construction(physical)
    is Err(Unsupported),
  )
  assert_eq(@resources.ledger_usage(ledger), physical_held)
  assert_true(retire_installed_effect_operation(physical, true).unwrap())
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let retired_during_current = Ref(false)
  on_current.val = () => {
    on_current.val = () => ()
    retired_during_current.val = retire_installed_effect_operation(
        operation, true,
      )
      is Ok(true)
  }
  assert_true(
    complete_installed_effect_operation_construction(operation) is Err(Retired),
  )
  assert_true(retired_during_current.val)
  assert_true(operation.retired)
  assert_false(owner.effect_operation_opening)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "actual response normalization completes scratch on the original Effect token while its Cursor remains readable" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let before_plan = effect_operation_plan_fixture(prepared, request, contracts)
  let capacity = installed_json_effect_response_construction_capacity(
    @execution.execution_capacity(17L, 23L).unwrap(),
    256,
    16,
    4,
  ).unwrap()
  let rows = before_plan.operations[0].row_extents.copy()
  rows[2] = prepare_installed_effect_operation_extent(
    "operation", capacity, 0L, false,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    before_plan.operations[0].member_extents,
    rows,
  ).unwrap()
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
  let calls = Ref(0)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  // These are the actual Source byte parser and indexed decoder, after the
  // original occurrence debit. The decomposed key uses the real NFC path.
  {
    let source = @source.parse_json_bytes(
      @utf8.encode("{\"é\":\"東京\"}"),
      { max_input_bytes: 256, max_nodes: 16, max_depth: 4, },
    ).unwrap()
    let cursor = @decode.admit(source, {
      max_nodes: 16,
      max_depth: 4,
      max_string_bytes: 256,
      max_total_string_bytes: 256,
    }).unwrap()
    let before = @resources.ledger_usage(ledger)
    let observed = calls.val
    complete_installed_effect_operation_construction(child).unwrap()
    assert_eq(calls.val, observed + 1)
    assert_eq(@resources.ledger_usage(ledger), {
      ..before,
      reserved_execution_bytes: before.reserved_execution_bytes -
      (
        @execution.execution_capacity_execution_bytes(capacity) -
        @execution.execution_capacity_retained_bytes(capacity)
      ),
    })
    let object = @decode.open_object(cursor).unwrap()
    assert_eq(@decode.text(@decode.lookup(object, "é").unwrap()), Ok("東京"))
    assert_true(retire_installed_effect_operation(child, false) is Ok(false))
    assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  }
  // No Source/Cursor output escapes this block. The existing original cleanup
  // can now retire that same token; no physical operation/ACK is involved.
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "retained constructor entry grows the same original backing only at work and preserves spent occurrence" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let calls = Ref(0)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_true(
    complete_installed_effect_operation_construction(child) is Err(Unsupported),
  )
  let observations = calls.val
  begin_installed_effect_operation_construction(child).unwrap()
  assert_eq(calls.val, observations + 1)
  assert_eq(@resources.ledger_usage(ledger), {
    ..held,
    reserved_execution_bytes: held.reserved_execution_bytes + 20L,
  })
  assert_true(
    begin_installed_effect_operation_construction(child) is Err(AlreadyBound),
  )
  complete_installed_effect_operation_construction(child).unwrap()
  let completed = @resources.ledger_usage(ledger)
  assert_eq(completed, held)
  assert_true(
    begin_installed_effect_operation_construction(child) is Err(AlreadyBound),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  assert_true(
    begin_installed_effect_operation_construction(child) is Err(Retired),
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "retained constructor entry refuses insufficient growth without changing backing or borrowing a new slot" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let usage = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    usage.reserved_execution_bytes
  let occupied = @resources.reserve_capacity(ledger, 0L, remaining).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_construction(child)
    is Err(Ledger(@resources.LedgerIssue::ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(!child.started)
  @resources.settle_capacity(ledger, occupied).unwrap()
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "retained constructor entry keeps original reentry retirement and physical purpose refusal" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let selected : Ref[ClientInstalledEffectOperationBorrow?] = Ref(None)
  let retire_on_current = Ref(false)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if retire_on_current.val {
        retire_on_current.val = false
        retire_installed_effect_operation(selected.val.unwrap(), true).unwrap()
        |> ignore
      }
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let copy = { ..child, }
  assert_true(
    begin_installed_effect_operation_construction(copy) is Err(ForeignOriginal),
  )
  selected.val = Some(child)
  retire_on_current.val = true
  assert_true(
    begin_installed_effect_operation_construction(child) is Err(Retired),
  )
  assert_true(child.retired)
  assert_true(
    retain_installed_effect_operation_construction(
      owner, prepared, request, plan, 0, true, 0, 0, "operation",
    )
    is Err(Unsupported),
  )
  let physical = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "operation",
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_construction(physical) is Err(Unsupported),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(retire_installed_effect_operation(physical, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "actual same Plan constructors keep all original outputs while sequential entry returns only scratch" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_constructor_peak_fixture(prepared, request, contracts, true)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap()
  |> ignore
  let before = @resources.ledger_usage(ledger)
  let member_constructor = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let row = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, true, 0, 0, "request",
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(
    held.reserved_retention_bytes - before.reserved_retention_bytes,
    140L,
  )
  assert_eq(
    held.reserved_execution_bytes - before.reserved_execution_bytes,
    140L,
  )
  begin_installed_effect_operation_construction(member_constructor).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    held.reserved_execution_bytes + 20L,
  )
  complete_installed_effect_operation_construction(member_constructor).unwrap()
  assert_eq(@resources.ledger_usage(ledger), held)
  begin_installed_effect_operation_construction(row).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    held.reserved_execution_bytes + 40L,
  )
  complete_installed_effect_operation_construction(row).unwrap()
  assert_eq(@resources.ledger_usage(ledger), held)
  // Completion did not return either output, coordinate or reservation slot.
  assert_true(!member_constructor.retired && !row.retired)
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(
    retire_installed_effect_operation(member_constructor, true).unwrap(),
  )
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(row, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "control constructor entry retains original outputs before Source then grows and returns same reservation workspace" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let baseline = effect_operation_plan_fixture(prepared, request, contracts)
  let plan = effect_operation_plan_with_control_fixture(
    prepared,
    request,
    contracts,
    baseline,
    @execution.execution_capacity(7L, 11L).unwrap(),
  ).unwrap()
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let before = @resources.ledger_usage(ledger)
  retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  ).unwrap()
  |> ignore
  let control = owner.effect_operation_controls.unwrap()
  let held = @resources.ledger_usage(ledger)
  let retained = @execution.execution_capacity_retained_bytes(
    plan.operation_control_capacity,
  )
  let execution = @execution.execution_capacity_execution_bytes(
    plan.operation_control_capacity,
  )
  assert_eq(
    held.reserved_retention_bytes - before.reserved_retention_bytes,
    retained,
  )
  assert_eq(
    held.reserved_execution_bytes - before.reserved_execution_bytes,
    plan.operation_control_idle_execution,
  )
  assert_eq(held.reserved_attempts, before.reserved_attempts)
  assert_eq(held.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_true(
    complete_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(AlreadyBound),
  )
  begin_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  assert_true(control.construction_active)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes -
    before.reserved_execution_bytes,
    execution,
  )
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(AlreadyBound),
  )
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  assert_true(!control.construction_active)
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_true(physical_equal(owner.effect_operation_controls.unwrap(), control))
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  assert_true(physical_equal(owner.effect_operation_controls.unwrap(), control))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  begin_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
}

///|
test "control constructor refused growth keeps same retained inventory and original mode without refund" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let baseline = effect_operation_plan_fixture(prepared, request, contracts)
  let plan = effect_operation_plan_with_control_fixture(
    prepared,
    request,
    contracts,
    baseline,
    @execution.execution_capacity(7L, 11L).unwrap(),
  ).unwrap()
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  ).unwrap()
  |> ignore
  let control = owner.effect_operation_controls.unwrap()
  let before = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    before.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining).unwrap()
  let occupied = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(Ledger(@resources.LedgerIssue::ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), occupied)
  assert_true(!control.construction_active)
  assert_true(
    begin_installed_effect_operation_controls(owner, prepared, request, plan)
    is Err(ForeignOriginal),
  )
  let copy = { ..owner, }
  assert_true(
    begin_installed_effect_operation_control_construction(
      copy, prepared, request, plan,
    )
    is Err(ForeignOriginal),
  )
  @resources.settle_capacity(ledger, pressure).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
// Real same-parent Resource reservations, not Source I/O or a physical ACK.
// An unresolved input holding must not be treated as reusable workspace.
test "unsettled input workspace refuses same original Effect entry until actual reservation settlement" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_constructor_peak_fixture(prepared, request, contracts, true)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, true, 0, 0, "request",
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  // This original request constructor has90 retained +40 scratch bytes.
  // Leave39 available while the SAME input reservation is unresolved.
  let free = @resources.ledger_limits(ledger).execution_bytes -
    held.reserved_execution_bytes
  let input_reservation = @resources.reserve_capacity(ledger, 0L, free - 39L).unwrap()
  let unresolved = @resources.ledger_usage(ledger)
  for _ in 0..<2 {
    assert_true(
      begin_installed_effect_operation_construction(child)
      is Err(Ledger(@resources.LedgerIssue::ExecutionLimit)),
    )
    assert_eq(@resources.ledger_usage(ledger), unresolved)
    assert_false(child.started)
    assert_false(child.retired)
  }
  // Only the existing actual settlement returns this input reservation.
  // No absence/terminal observation, synthetic ACK or new child is involved.
  @resources.settle_capacity(ledger, input_reservation).unwrap()
  begin_installed_effect_operation_construction(child).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    held.reserved_execution_bytes + 40L,
  )
  complete_installed_effect_operation_construction(child).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    held.reserved_execution_bytes,
  )
  assert_true(
    begin_installed_effect_operation_construction(child) is Err(AlreadyBound),
  )
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "saved Ledger codec keeps maximum retained and Receipt workspace but stages only normalizing scratch" {
  let full = standard_create_saved_control_capacity(1000000, 512, 16).unwrap()
  let staged = standard_create_saved_control_capacity(
    1000000,
    512,
    16,
    defer_ledger_codec=true,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(full),
    @execution.execution_capacity_retained_bytes(staged),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(staged) <
    @execution.execution_capacity_execution_bytes(full),
  )
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let baseline = effect_operation_plan_fixture(prepared, request, contracts)
  let plan = effect_operation_plan_with_control_fixture(
    prepared, request, contracts, baseline, staged,
  ).unwrap()
  let quote = prepared_installed_effect_managed_requirements(plan)
  // Same finite parent authorizes the codec's original full bound. The staged
  // Plan does not reserve that unconstructed future workspace at adoption.
  quote[5] += @execution.execution_capacity_execution_bytes(full) -
    @execution.execution_capacity_execution_bytes(staged)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan, quote,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  ).unwrap()
  |> ignore
  let control = owner.effect_operation_controls.unwrap()
  assert_true(
    begin_installed_effect_operation_ledger_codec(
      owner,
      prepared,
      request,
      plan,
      Some("{}"),
      512,
      16,
    )
    is Err(AlreadyBound),
  )
  begin_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let baseline_usage = @resources.ledger_usage(ledger)
  let reservation = control.reservation
  for wire in [Some("{}"), None, Some("x".repeat(1000000))] {
    begin_installed_effect_operation_ledger_codec(
      owner, prepared, request, plan, wire, 512, 16,
    ).unwrap()
    let active = @resources.ledger_usage(ledger)
    assert_true(control.ledger_codec_active)
    let (same_active, _) = installed_effect_control_capacity(
      Some(control),
      plan,
    ).unwrap()
    let active_delta = @execution.execution_capacity_execution_bytes(
        same_active,
      ) -
      @execution.execution_capacity_execution_bytes(
        plan.operation_control_capacity,
      )
    assert_eq(
      active.reserved_execution_bytes - baseline_usage.reserved_execution_bytes,
      active_delta,
    )
    assert_eq(
      active.reserved_retention_bytes,
      baseline_usage.reserved_retention_bytes,
    )
    assert_eq(active.attempts, baseline_usage.attempts)
    assert_eq(active.reserved_attempts, baseline_usage.reserved_attempts)
    assert_eq(active.transferred_bytes, baseline_usage.transferred_bytes)
    assert_eq(
      active.reserved_transfer_bytes,
      baseline_usage.reserved_transfer_bytes,
    )
    assert_true(
      begin_installed_effect_operation_ledger_codec(
        owner, prepared, request, plan, wire, 512, 16,
      )
      is Err(AlreadyBound),
    )
    assert_true(
      complete_installed_effect_operation_control_construction(
        owner, prepared, request, plan,
      )
      is Err(AlreadyBound),
    )
    complete_installed_effect_operation_ledger_codec(
      owner, prepared, request, plan,
    ).unwrap()
    assert_eq(@resources.ledger_usage(ledger), baseline_usage)
    assert_true(physical_equal(control.reservation, reservation))
  }
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
test "saved Ledger codec refused growth retains same prefix and permits only original retry after actual capacity returns" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let baseline = effect_operation_plan_fixture(prepared, request, contracts)
  let full = standard_create_saved_control_capacity(1000000, 512, 16).unwrap()
  let staged = standard_create_saved_control_capacity(
    1000000,
    512,
    16,
    defer_ledger_codec=true,
  ).unwrap()
  let plan = effect_operation_plan_with_control_fixture(
    prepared, request, contracts, baseline, staged,
  ).unwrap()
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[5] += @execution.execution_capacity_execution_bytes(full)
  let (input, initial, _, admitted) = effect_parent_test_preparation(
    plan, quote,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, admitted, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  ).unwrap()
  |> ignore
  begin_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  let before = @resources.ledger_usage(ledger)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    before.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining).unwrap()
  let occupied = @resources.ledger_usage(ledger)
  let original = "x".repeat(1000000)
  assert_true(
    begin_installed_effect_operation_ledger_codec(
      owner,
      prepared,
      request,
      plan,
      Some(original),
      512,
      16,
    )
    is Err(Ledger(@resources.LedgerIssue::ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), occupied)
  assert_true(control.construction_active && !control.ledger_codec_active)
  let foreign = { ..owner, }
  assert_true(
    begin_installed_effect_operation_ledger_codec(
      foreign,
      prepared,
      request,
      plan,
      Some(original),
      512,
      16,
    )
    is Err(ForeignOriginal),
  )
  @resources.settle_capacity(ledger, pressure).unwrap()
  begin_installed_effect_operation_ledger_codec(
    owner,
    prepared,
    request,
    plan,
    Some(original),
    512,
    16,
  ).unwrap()
  // A failed callback would leave this same active peak; outer completion
  // cannot acknowledge it. Only its real synchronous success calls complete.
  assert_true(control.ledger_codec_active)
  assert_true(
    complete_installed_effect_operation_control_construction(
      owner, prepared, request, plan,
    )
    is Err(AlreadyBound),
  )
  complete_installed_effect_operation_ledger_codec(
    owner, prepared, request, plan,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
}
