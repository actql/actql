///|
/// Actual ordinary Node supplier; no Source, Account, provider or I/O port.
extern "js" fn request_parent_test_original(
  loader : PublicationTestLoader,
  input : Array[Int],
  quote : Array[Int64],
  current : () -> Bool,
  pending : () -> Bool,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,input,quote,current,pending) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(input,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},()=>{if(!current())throw new Error('RequestParentOriginalRetired')},pending,'local-preparation')

///|
fn request_parent_fixture(
  input : Array[Int],
  current? : () -> Bool = () => true,
  pending? : () -> Bool = () => false,
) -> @resources.NodePreparationAdmission[Array[Int]] {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let original = request_parent_test_original(
    publication_test_loader(publication_test_url()),
    input,
    [
      limits.planning_work.to_int64(),
      limits.attempts.to_int64(),
      limits.holdings.to_int64(),
      limits.transfer_bytes,
      limits.retained_bytes,
      limits.execution_bytes,
    ],
    current,
    pending,
  )
  @resources.prepare_node_local_preparation_admission(original, input).unwrap()
}

///|
test "request parent reserves controls before body selection and continues one original debit" {
  let input = [1]
  let policy = client_local_resource_policy()
  let initial = request_parent_fixture(input)
  let owner = begin_request_preparation(initial, input, policy).unwrap()
  let (bootstrap, zero) = client_request_preparation_control_capacity(policy).unwrap()
  assert_eq(zero, 0L)
  let before = @resources.ledger_usage(owner.ledger)
  assert_eq(before.reserved_retention_bytes, bootstrap)
  assert_eq(before.reserved_execution_bytes, 0L)
  assert_eq(before.held_bytes, 0L)
  assert_true(owner.phase == Open && owner.input is Some(_))
  let next = select_closed_values_preparation(
    owner,
    input,
    module_containers=empty_family_module_containers,
  ).unwrap()
  assert_true(physical_equal(next.initial, initial))
  let (body, scratch) = client_closed_values_initial_control_capacity(
    policy,
    module_containers=empty_family_module_containers,
  ).unwrap()
  let after = @resources.ledger_usage(owner.ledger)
  assert_eq(after.reserved_retention_bytes, bootstrap + body)
  assert_eq(after.reserved_execution_bytes, scratch)
  assert_eq(after.held_bytes, 0L)
  assert_true(owner.phase == Selected && owner.input is None)
  assert_true(
    select_closed_values_preparation(
      owner,
      input,
      module_containers=empty_family_module_containers,
    )
    is Err(WrongPhase),
  )
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(WrongPhase))
  assert_eq(@resources.ledger_usage(owner.ledger), after)
  // Exercise the real next driver's first operation, not only its constructor.
  // Its work remains on the same original until that driver retires it.
  assert_true(begin_closed_values_header(next) is Ok(_))
  abort_closed_values_preparation_after_cleanup(next).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
}

///|
test "request parent foreign input cannot select or resize its retained original" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    select_closed_values_preparation(
      owner,
      [1],
      module_containers=empty_family_module_containers,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  assert_true(owner.phase == Open && owner.input is Some(_))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(owner.phase == Closed && owner.input is None)
  assert_true(
    select_closed_values_preparation(
      owner,
      input,
      module_containers=empty_family_module_containers,
    )
    is Err(WrongPhase),
  )
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
}

///|
test "request parent selection currentness cannot reenter select or retire the same reservation" {
  let input = [1]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let entered = Ref(false)
  let refused = Ref(false)
  let initial = request_parent_fixture(input, current=() => {
    if armed.val && !entered.val {
      entered.val = true
      let owner = selected.val.unwrap()
      refused.val = select_closed_values_preparation(
          owner,
          input,
          module_containers=empty_family_module_containers,
        )
        is Err(WrongPhase) &&
        abort_request_preparation_after_cleanup(owner) is Err(WrongPhase)
    }
    true
  })
  let owner = begin_request_preparation(
    initial,
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(owner)
  armed.val = true
  let next = select_closed_values_preparation(
    owner,
    input,
    module_containers=empty_family_module_containers,
  ).unwrap()
  assert_true(entered.val && refused.val)
  abort_closed_values_preparation_after_cleanup(next).unwrap()
}

///|
test "request parent original-current failure preserves its charged original cleanup" {
  let input = [1]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  current.val = false
  assert_true(
    select_closed_values_preparation(
      owner,
      input,
      module_containers=empty_family_module_containers,
    )
    is Err(Capacity(_)),
  )
  assert_true(owner.phase == Open && owner.input is Some(_))
  assert_eq(
    @resources.ledger_usage(owner.ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  // Currentness refusal never acknowledges cleanup; the exact original stop
  // remains independently callable after this callback's scratch unwound.
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
}

///|
test "request parent keeps original unknown stop without inferring a new cleanup acknowledgement" {
  let input = [1]
  let pending = Ref(false)
  let owner = begin_request_preparation(
    request_parent_fixture(input, pending=() => pending.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  pending.val = true
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_true(owner.phase == Retiring)
  assert_true(
    select_closed_values_preparation(
      owner,
      input,
      module_containers=empty_family_module_containers,
    )
    is Err(WrongPhase),
  )
  // The original imported stop was attempted and its failure is retained.
  // A later false callback is not another issued physical acknowledgement.
  pending.val = false
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_true(owner.phase == Retiring && owner.input is None)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
}

///|
test "Request diagnostic accounting observes one reservation across typed continuation and stop" {
  let input = [7]
  let policy = client_local_resource_policy()
  let initial = request_parent_fixture(input)
  let owner = begin_request_preparation(initial, input, policy).unwrap()
  let before = request_preparation_accounting(owner)
  assert_eq(before, @resources.preparation_capacity_accounting(owner.capacity))
  let next = select_closed_values_preparation(
    owner,
    input,
    module_containers=empty_family_module_containers,
  ).unwrap()
  let active = request_preparation_accounting(owner)
  assert_eq(active, @resources.preparation_capacity_accounting(next.capacity))
  assert_true(active.0 > before.0)
  abort_closed_values_preparation_after_cleanup(next).unwrap()
  let stopped = request_preparation_accounting(owner)
  assert_eq(stopped, @resources.preparation_capacity_accounting(next.capacity))
  assert_eq(
    (stopped.0, stopped.1, stopped.2, stopped.4, stopped.5),
    (0L, 0L, 0L, 0L, 0L),
  )
  assert_eq(stopped.3, active.3)
}
