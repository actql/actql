///|
test "source Host and response bindings retain one exact request and ordered prerequisites" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (identity, _, _, _, units) = remote_construction_fixture(budget)
  assert_eq(units[0].source_execution.length(), 9)
  assert_true(
    physical_equal(units[0].source_execution[0].subject.owner, identity),
  )
  let policy_writer = @encode.writer(10000, 7, 1)
  emit_source_response_policy(
    units[0].source_execution[0].subject.response_policy,
    policy_writer,
  )
  let policy_bytes = @utf8.encode(@encode.finish(policy_writer))
  let exact_work = 13 + policy_bytes.length() + 7
  let exact = IdentityBudget::{
    work: exact_work,
    bytes: policy_bytes.length(),
    nodes: 7,
    depth: 1,
  }
  let checks = prepare_source_execution(identity, exact)
  assert_eq(exact.work, 0)
  assert_eq(exact.bytes, 0)
  assert_eq(exact.nodes, 0)
  assert_eq(checks.length(), 9)
  let host = checks[0]
  assert_true(host.subject.direct_policy is None)
  assert_eq(
    host.subject.response_policy_cid,
    "sha256:" + @sha.hex(policy_bytes),
  )
  let authorization = checks[1]
  let egress = checks[2]
  let resources = checks[3]
  let response = checks[4]
  assert_true(egress.kind is RequestEgress)
  assert_true(physical_equal(egress.subject, host.subject))
  assert_true(physical_equal(egress.prerequisites[0], authorization))
  assert_eq(egress.prerequisites.length(), 1)
  assert_true(egress.phase is BeforeProviderAccess)
  assert_true(egress.failure is PreventProviderAccess)
  assert_true(authorization.kind is ReadAuthorization)
  assert_true(authorization.phase is BeforeProviderAccess)
  assert_true(authorization.failure is PreventProviderAccess)
  assert_true(physical_equal(authorization.subject, host.subject))
  assert_true(physical_equal(authorization.prerequisites[0], host))
  assert_eq(authorization.prerequisites.length(), 1)
  assert_eq(host.subject.authority, ReadMetadata)
  assert_true(resources.kind is AcquisitionResources)
  assert_true(resources.phase is BeforeAndDuringAcquisition)
  assert_true(resources.failure is FailAcquisitionAtomically)
  assert_true(physical_equal(resources.subject, host.subject))
  assert_true(physical_equal(resources.prerequisites[0], host))
  assert_eq(resources.prerequisites.length(), 3)
  assert_true(physical_equal(resources.prerequisites[1], authorization))
  assert_true(physical_equal(resources.prerequisites[2], egress))
  assert_eq(response.prerequisites.length(), 2)
  assert_true(physical_equal(response.prerequisites[1], resources))
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
  let keyed_request = checks[5]
  let keyed_egress = checks[6]
  let keyed_resources = checks[7]
  let keyed_response = checks[8]
  guard keyed_request.kind is KeyedRequest(request_binding) &&
    keyed_resources.kind is KeyedResources(resource_binding) &&
    keyed_response.kind is KeyedResponse(response_binding) else {
    fail("keyed acquisition obligations were omitted")
  }
  assert_true(physical_equal(request_binding, resource_binding))
  assert_true(physical_equal(request_binding, response_binding))
  guard keyed_egress.kind is KeyedEgress(egress_binding) else {
    fail("correlation egress was omitted")
  }
  assert_true(physical_equal(egress_binding, request_binding))
  assert_true(physical_equal(keyed_egress.prerequisites[0], keyed_request))
  assert_eq(keyed_egress.prerequisites.length(), 1)
  assert_true(keyed_egress.phase is BeforeProviderAccess)
  assert_true(keyed_egress.failure is PreventProviderAccess)
  assert_eq(keyed_resources.prerequisites.length(), 2)
  assert_true(physical_equal(keyed_resources.prerequisites[1], keyed_egress))
  let axes = [
    Sensitivity,
    Completeness,
    Mime,
    Bytes,
    Availability,
    ProviderAccountBoundary,
    Region,
    CurrentHostPolicy,
  ]
  for check in [egress, keyed_egress] {
    assert_eq(source_egress_axis_count(check), axes.length())
    for i, axis in axes {
      assert_eq(source_egress_axis_at(check, i), Some(axis))
    }
    assert_eq(source_egress_field_count(check), 1)
    assert_true(
      source_egress_field_at(check, 0).unwrap().value
      is @sourceviews.CheckedLiteral(_),
    )
    for i in [-1, 8, 2147483647] {
      assert_true(source_egress_axis_at(check, i) is None)
      assert_true(source_egress_field_at(check, i) is None)
    }
    assert_true(source_egress_field_at(check, 1) is None)
  }
  assert_eq(source_egress_axis_count(host), 0)
  assert_eq(source_egress_field_count(host), 0)
  assert_true(source_egress_field_at(host, 0) is None)
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
  assert_true(keyed_request.phase is BeforeProviderAccess)
  assert_true(keyed_resources.phase is BeforeAndDuringAcquisition)
  assert_true(keyed_response.phase is BeforeSourceOutputUse)
  assert_true(keyed_resources.failure is FailAcquisitionAtomically)
  assert_true(keyed_response.failure is FailAcquisitionAtomically)
  assert_true(physical_equal(keyed_request.prerequisites[0], host))
  assert_eq(keyed_request.prerequisites.length(), 2)
  assert_true(physical_equal(keyed_request.prerequisites[1], resources))
  assert_true(physical_equal(keyed_resources.prerequisites[0], keyed_request))
  assert_eq(keyed_response.prerequisites.length(), 2)
  assert_true(physical_equal(keyed_response.prerequisites[0], keyed_resources))
  assert_true(physical_equal(keyed_response.prerequisites[1], response))
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
  let short = IdentityBudget::{
    work: exact_work - 1,
    bytes: policy_bytes.length(),
    nodes: 7,
    depth: 1,
  }
  try prepare_source_execution(identity, short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("partial source checks escaped")
  }
  assert_eq(short.work, exact_work - 1)
  assert_eq(short.bytes, policy_bytes.length())
  assert_eq(short.nodes, 7)
  for
    (bytes, nodes, depth) in [
      (policy_bytes.length() - 1, 7, 1),
      (policy_bytes.length(), 6, 1),
      (policy_bytes.length(), 7, 0),
    ] {
    let limited = IdentityBudget::{ work: exact_work, bytes, nodes, depth, }
    try prepare_source_execution(identity, limited) catch {
      UnitBuildFailure::Encoding(_) => ()
      error => raise error
    } noraise {
      _ => fail("source policy serialization escaped budget")
    }
    assert_eq(limited.work, exact_work)
    assert_eq(limited.bytes, bytes)
    assert_eq(limited.nodes, nodes)
  }
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
