///|
/// Actual ordinary Node supplier; no Source, Account, provider or I/O port.
// Retain the original Array object across this identity boundary. A FixedArray
// conversion would select a copy instead of the input admitted below.
#warnings("-deprecated")
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
  initial_limits? : @resources.LedgerLimits? = None,
) -> @resources.NodePreparationAdmission[Array[Int]] {
  let limits = match initial_limits {
    Some(original) => original
    None =>
      client_local_preparation_initial_limits(client_local_resource_policy()).unwrap()
  }
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
test "request parent reserves controls then grows its original snapshot reservation" {
  let input = [1]
  let policy = client_local_resource_policy()
  let initial = request_parent_fixture(input)
  let owner = begin_request_preparation(initial, input, policy).unwrap()
  let original = owner.capacity
  let (bootstrap, zero) = client_request_preparation_control_capacity(policy).unwrap()
  assert_eq(zero, 0L)
  let before = @resources.ledger_usage(owner.ledger)
  assert_eq(before.reserved_retention_bytes, bootstrap)
  assert_eq(before.reserved_execution_bytes, 0L)
  assert_eq(before.held_bytes, 0L)
  reserve_request_snapshot(owner, input, 16L, 2L).unwrap()
  let after = @resources.ledger_usage(owner.ledger)
  assert_true(physical_equal(owner.capacity, original))
  assert_true(
    owner.initial is NodeRequestInitial(original) &&
    physical_equal(original, initial),
  )
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(after.reserved_execution_bytes > 0L)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.held_bytes, 0L)
  assert_true(owner.phase == Open && owner.input is Some(_))
  abort_request_preparation_after_cleanup(owner).unwrap()
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
    reserve_request_snapshot(owner, [1], 16L, 2L) is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  assert_true(owner.phase == Open && owner.input is Some(_))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(owner.phase == Closed && owner.input is None)
  assert_true(
    reserve_request_snapshot(owner, input, 16L, 2L) is Err(WrongPhase),
  )
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
}

///|
test "request parent snapshot currentness cannot reenter growth or retire the same reservation" {
  let input = [1]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let armed = Ref(false)
  let entered = Ref(false)
  let refused = Ref(false)
  let initial = request_parent_fixture(input, current=() => {
    if armed.val && !entered.val {
      entered.val = true
      let owner = selected.val.unwrap()
      refused.val = reserve_request_snapshot(owner, input, 16L, 2L)
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
  reserve_request_snapshot(owner, input, 16L, 2L).unwrap()
  assert_true(entered.val && refused.val)
  abort_request_preparation_after_cleanup(owner).unwrap()
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
    reserve_request_snapshot(owner, input, 16L, 2L) is Err(Capacity(_)),
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
    reserve_request_snapshot(owner, input, 16L, 2L) is Err(WrongPhase),
  )
  // The original imported stop was attempted and its failure is retained.
  // A later false callback is not another issued physical acknowledgement.
  pending.val = false
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_true(owner.phase == Retiring && owner.input is None)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
}

///|
test "Request diagnostic accounting observes one reservation across snapshot growth and stop" {
  let input = [7]
  let policy = client_local_resource_policy()
  let initial = request_parent_fixture(input)
  let owner = begin_request_preparation(initial, input, policy).unwrap()
  let before = request_preparation_accounting(owner)
  assert_eq(before, @resources.preparation_capacity_accounting(owner.capacity))
  reserve_request_snapshot(owner, input, 16L, 2L).unwrap()
  let active = request_preparation_accounting(owner)
  assert_eq(active, @resources.preparation_capacity_accounting(owner.capacity))
  assert_true(active.0 > before.0)
  abort_request_preparation_after_cleanup(owner).unwrap()
  let stopped = request_preparation_accounting(owner)
  assert_eq(stopped, @resources.preparation_capacity_accounting(owner.capacity))
  assert_eq(
    (stopped.0, stopped.1, stopped.2, stopped.4, stopped.5),
    (0L, 0L, 0L, 0L, 0L),
  )
  assert_eq(stopped.3, active.3)
}

///|
test "fixed Request control envelope preserves original upper bound through the common tariff" {
  // The retained-wire tuple/Some and its Request field add 2H/2R/2W.
  // Native intake additionally retains its baseline tuple/Some, Request slot
  // and monotone byte scalar: 2H/2R/3W. Neither is domain payload storage.
  // This fixed control belongs to the original parent before domain growth.
  assert_eq(
    10736L + 16L * 2L + 8L * 2L + 8L * 2L + 16L * 2L + 8L * 2L + 8L * 3L,
    10872L,
  )
  assert_eq(
    @execution.preparation_representation_cost(
      request_preparation_fixed_control_envelope,
    ),
    Some(10872L),
  )
  assert_eq(
    client_request_preparation_control_capacity(client_local_resource_policy()),
    Some((14968L, 0L)),
  )
  let growth = @resources.preparation_inventory_growth_entry_construction()
  assert_eq(
    @execution.preparation_representation_cost({
      record_headers: growth.record_headers,
      reference_slots: growth.reference_slots,
      scalar_words: growth.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
    Some(368L),
  )
  let growth = @resources.preparation_inventory_growth_entry_construction()
  assert_eq(
    @execution.preparation_representation_cost({
      record_headers: growth.record_headers,
      reference_slots: growth.reference_slots,
      scalar_words: growth.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
    Some(368L),
  )
  assert_eq(request_preparation_fixed_control_envelope.owned_utf16_units, 0L)
  assert_eq(request_preparation_fixed_control_envelope.owned_wire_bytes, 0L)
}

///|
test "fixed Request control envelope leaves proportional snapshot growth on its same original reservation" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let reservation = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  assert_eq(before.reserved_retention_bytes, 14968L)
  reserve_request_snapshot(owner, input, 16L, 2L).unwrap()
  let small = @resources.ledger_usage(owner.ledger)
  reserve_request_snapshot(owner, input, 256L, 32L).unwrap()
  let large = @resources.ledger_usage(owner.ledger)
  assert_true(physical_equal(reservation, owner.capacity))
  assert_eq(small.live_reservations, before.live_reservations)
  assert_eq(large.live_reservations, before.live_reservations)
  assert_true(large.reserved_retention_bytes > small.reserved_retention_bytes)
  assert_true(large.reserved_execution_bytes > small.reserved_execution_bytes)
  assert_eq(
    large.reserved_retention_bytes - small.reserved_retention_bytes,
    request_snapshot_data_bytes(256L, 32L).unwrap() -
    request_snapshot_data_bytes(16L, 2L).unwrap(),
  )
  assert_eq(
    client_request_preparation_control_capacity(client_local_resource_policy()),
    Some((14968L, 0L)),
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "Node Request keeps its original full sealed envelope requirement" {
  let input = [1]
  let policy = client_local_resource_policy()
  let ceiling = client_local_preparation_initial_limits(policy).unwrap()
  let (controls, _) = client_request_preparation_control_capacity(policy).unwrap()
  let initial = request_parent_fixture(
    input,
    initial_limits=Some({
      ..ceiling,
      retained_bytes: controls,
      execution_bytes: 0L,
    }),
  )
  assert_true(begin_request_preparation(initial, input, policy) is Err(Policy))
  @resources.cleanup_node_preparation_admission(initial).unwrap()
}

///|
// The original physical owner may still be pending after the continued
// reservation has retired. Its payload-Read control record cannot survive in
// this outer Request while that same Read waits for its last strong alias.
test "Request drops retired continuation aliases before original physical cleanup ACK" {
  let input = [71]
  let pending = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, pending=() => pending.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(owner, input, 16L, 2L).unwrap()
  let continued : @resources.PreparationCapacity[Array[Int], ClientInstalledEffectManagedPlan] =
    @resources.continue_preparation_capacity(owner.capacity, input).unwrap()
  owner.effect_capacity = Some(continued)
  owner.phase = EffectCompiled
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_true(owner.effect_capacity is None)
  assert_true(owner.program_capacity is None && owner.snapshot_base is None)
  assert_true(owner.phase == Retiring && owner.input is None)
  let retired = @resources.ledger_usage(owner.ledger)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  // Only the SAME physical owner's initial cleanup is retried. The consumed
  // Unit capacity cannot be retired again or interpreted as another body.
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_eq(@resources.ledger_usage(owner.ledger), retired)
  pending.val = false
  // A changed callback is not the original physical ACK. Node's uncertain
  // stop stays pending; the actual Native component supplies its own close.
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_true(owner.phase == Retiring && owner.input is None)
}

///|
test "Request keeps live continuation until original constructor borrower returns" {
  let input = [72]
  let owner = begin_request_preparation(
    request_parent_fixture(input), input, client_local_resource_policy(),
  ).unwrap()
  let continued : @resources.PreparationCapacity[Array[Int], ClientInstalledEffectManagedPlan] =
    @resources.continue_preparation_capacity(owner.capacity, input).unwrap()
  owner.effect_capacity = Some(continued)
  owner.phase = EffectCompiled
  let usage = @resources.ledger_usage(owner.ledger)
  let holder = @resources.reserve_preparation_construction_input(
    continued, input, 42,
    usage.reserved_retention_bytes, usage.reserved_execution_bytes,
  ).unwrap()
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(WrongPhase))
  assert_true(owner.input is Some(original) && physical_equal(original, input))
  assert_true(owner.effect_capacity is Some(original) && physical_equal(original, continued))
  assert_eq(@resources.preparation_body_borrow_value(holder), Some(42))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(owner.phase == Closed && owner.effect_capacity is None)
}
