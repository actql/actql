///|
fn source_policy_fixture(context : ReconciledContexts) -> SourceRowContexts {
  let source = @stages.operations_source(
    @stages.bound_operations(
      stage_operations(wired_stage_contexts(reconciled_wiring(context))),
    ),
  )
  let declarations = @binding_declarations.prepare(@stages.program(source), {
    max_bindings: 100,
    max_work: 100000,
  }).unwrap()
  let slots = @request_slots.collect(source, declarations, {
    max_work: 1000000,
    max_slots: 1000,
  }).unwrap()
  let requests = check_source_requests(context, slots, {
    max_work: 1000000,
    max_pairs: 1000,
    values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
  }).unwrap()
  check_source_row_bounds(requests, [], 1000000).unwrap()
}

///|
test "source policy joins exact owners and counts common preparation once" {
  let (context, capacity) = selected_fixture(false)
  let rows = source_policy_fixture(context)
  let policy = bind_capacity_policy(
    context,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  let result = bind_source_policy(rows, policy, 1000000).unwrap()
  assert_true(physical_equal(source_policy_rows(result), rows))
  assert_true(physical_equal(source_policy_selected(result), policy))
  assert_true(
    @environment.lookup_execution_policy(selected_lookup_execution(policy))
    is None,
  )
  let used = source_rows_work(rows) +
    selected_policy_usage(policy).work -
    reconciled_usage(context).work +
    1
  assert_eq(source_policy_work(result), used)
  let capacity_context = check_source_capacity(result, used).unwrap()
  assert_true(physical_equal(source_capacity_context(capacity_context), result))
  assert_eq(source_capacity_work(capacity_context), used)
  assert_true(source_capacity_stage(capacity_context, 0) is None)
  assert_true(check_source_capacity(result, used - 1) is Err(BudgetExceeded))
  assert_true(check_source_capacity(result, -1) is Err(InvalidLimits))
  assert_true(bind_source_policy(rows, policy, used) is Ok(_))
  assert_true(bind_source_policy(rows, policy, used - 1) is Err(BudgetExceeded))
  assert_true(bind_source_policy(rows, policy, -1) is Err(InvalidLimits))
  let (foreign, other_capacity) = selected_fixture(false)
  let other = bind_capacity_policy(
    foreign,
    other_capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  assert_eq(
    @policy.cid(@environment.capacity_policy(capacity)),
    @policy.cid(@environment.capacity_policy(other_capacity)),
  )
  assert_true(bind_source_policy(rows, other, 1000000) is Err(ForeignContext))
  let locals = []
  let mut index = 0
  while reconciled_local_at(context, index) is Some(item) {
    locals.push(item)
    index += 1
  }
  let reconstructed = attach_reconciled_inputs(
    reconciled_wiring(context),
    reconciled_snapshots(context),
    locals,
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  let same_environment = bind_capacity_policy(
    reconstructed,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  assert_true(
    physical_equal(
      @environment.lookup_execution_environment(
        selected_lookup_execution(same_environment),
      ),
      @environment.lookup_execution_environment(
        selected_lookup_execution(policy),
      ),
    ),
  )
  assert_true(
    bind_source_policy(rows, same_environment, 1000000) is Err(ForeignContext),
  )
  // Repeating a check on the same owner is allowed; equality of another owner is not.
  let again = bind_capacity_policy(
    context,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  assert_true(bind_source_policy(rows, again, used) is Ok(_))
}
