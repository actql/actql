///|
test "source Host and response bindings retain one exact request and ordered prerequisites" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (identity, _, _, _, units) = remote_construction_fixture(budget)
  assert_eq(units[0].source_execution.length(), 5)
  assert_true(
    physical_equal(units[0].source_execution[0].subject.owner, identity),
  )
  let exact = IdentityBudget::{ work: 9, bytes: 0, nodes: 0, depth: 0, }
  let checks = prepare_source_execution(identity, exact)
  assert_eq(exact.work, 0)
  assert_eq(checks.length(), 5)
  let host = checks[0]
  let response = checks[1]
  assert_true(host.kind is HostCombination)
  assert_true(host.phase is BeforeProviderAccess)
  assert_true(host.failure is PreventProviderAccess)
  assert_eq(host.prerequisites.length(), 0)
  assert_true(response.kind is CarrierResponse)
  assert_true(response.phase is BeforeSourceOutputUse)
  assert_true(response.failure is RejectSourceOutput)
  assert_true(physical_equal(response.prerequisites[0], host))
  assert_true(physical_equal(response.subject, host.subject))
  assert_true(physical_equal(host.subject.owner, identity))
  assert_eq(host.subject.stage, 0)
  assert_eq(host.subject.input, 0)
  guard host.subject.request is @sourceviews.Keyed(mode, _) else {
    fail("keyed request became a direct acquisition")
  }
  assert_true(
    physical_equal(host.subject.source, @sourceviews.keyed_mode_input(mode)),
  )
  guard checks[2].kind is KeyedRequest(request_binding) &&
    checks[3].kind is KeyedResources(resource_binding) &&
    checks[4].kind is KeyedResponse(response_binding) else {
    fail("keyed acquisition obligations were omitted")
  }
  assert_true(physical_equal(request_binding, resource_binding))
  assert_true(physical_equal(request_binding, response_binding))
  assert_eq(request_binding.stage, 0)
  assert_eq(request_binding.index, 0)
  assert_eq(@sourceviews.keyed_join_step(request_binding.join), 1)
  assert_eq(request_binding.counts.input_rows, 1L)
  assert_eq(request_binding.counts.rows_per_key, 2L)
  assert_eq(request_binding.counts.response_rows, 2L)
  assert_true(
    physical_equal(
      request_binding.producer,
      @context.source_producer_at(request_binding.owner, 0, 0).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      request_binding.bounds,
      @context.source_capacity_stage(
        @context.source_producer_capacity(request_binding.owner),
        0,
      ).unwrap(),
    ),
  )
  assert_true(checks[2].phase is BeforeProviderAccess)
  assert_true(checks[3].phase is BeforeAndDuringAcquisition)
  assert_true(checks[4].phase is BeforeSourceOutputUse)
  assert_true(checks[3].failure is FailAcquisitionAtomically)
  assert_true(checks[4].failure is FailAcquisitionAtomically)
  assert_true(physical_equal(checks[2].prerequisites[0], host))
  assert_true(physical_equal(checks[3].prerequisites[0], checks[2]))
  assert_eq(checks[4].prerequisites.length(), 2)
  assert_true(physical_equal(checks[4].prerequisites[0], checks[3]))
  assert_true(physical_equal(checks[4].prerequisites[1], response))
  let policy = host.subject.response_policy
  assert_true(physical_equal(policy.source, host.subject.source))
  assert_true(policy.minimum is None)
  assert_true(policy.classification is @environment.Unknown)
  assert_true(
    @environment.data_classification(
      @environment.source_view_data_policy(policy.authoritative),
    )
    is @environment.Unknown,
  )
  let short = IdentityBudget::{ work: 8, bytes: 0, nodes: 0, depth: 0, }
  try prepare_source_execution(identity, short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("partial source checks escaped")
  }
  assert_eq(short.work, 8)
}

///|
test "source execution audit rejects selected SourceViews and bounds Local inventory traversal" {
  let local_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, local_inventory, _) = local_construction_fixture(
    local_budget,
    second_stage=true,
  )
  let exact = IdentityBudget::{ work: 2, bytes: 0, nodes: 0, depth: 0, }
  audit_source_execution(local_inventory, exact)
  assert_eq(exact.work, 0)
  let short = IdentityBudget::{ work: 1, bytes: 0, nodes: 0, depth: 0, }
  try audit_source_execution(local_inventory, short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("source inventory traversal escaped its budget")
  }

  let remote_budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, remote, _) = remote_construction_fixture(remote_budget)
  try audit_source_execution(remote, remote_budget) catch {
    UnitBuildFailure::UnclosedSourceExecution(0, 0) => ()
    error => raise error
  } noraise {
    _ => fail("mode support substituted for complete source execution closure")
  }
}
