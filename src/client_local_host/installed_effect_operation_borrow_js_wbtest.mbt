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
  begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap()
  let original = owner.effect_operation_controls.unwrap()
  let debited = @resources.ledger_usage(ledger)
  assert_eq(
    debited.reserved_retention_bytes,
    before.reserved_retention_bytes +
    @execution.execution_capacity_retained_bytes(
      plan.operation_control_capacity,
    ),
  )
  begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap()
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
  begin_installed_effect_operation_controls(owner, prepared, request, plan).unwrap()
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
