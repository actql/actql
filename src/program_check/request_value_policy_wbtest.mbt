///|
fn request_policy_budget() -> IdentityBudget {
  { work: 1000000, bytes: 1000000, nodes: 100000, depth: 100, }
}

///|
test "trusted subject inventory shares work bytes and nodes across requests" {
  let program = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
  )
  let check = program.units[0].source_execution[0]
  let budget = request_policy_budget()
  let expected = request_value_policy_subject_body(check, budget)
  let work = 1000000 - budget.work + 1
  let bytes = 1000000 - budget.bytes
  let nodes = 100000 - budget.nodes
  assert_eq(
    request_value_policy_subject_wires([check], work, bytes, nodes, 100),
    [expected],
  )
  for
    (w, b, n) in [
      (work, 1000000, 100000),
      (1000000, bytes, 100000),
      (1000000, 1000000, nodes),
    ] {
    try request_value_policy_subject_wires([check, check], w, b, n, 100) catch {
      BudgetExceeded | Encoding(_) => ()
      error => raise error
    } noraise {
      _ => fail("request inventory reset its aggregate allowance")
    }
  }
}

///|
test "trusted subject reader and admitted CID binder retain exact request provenance" {
  let environment = request_policy_internal_environment()
  let program = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_parameter=true,
  )
  let check = program.units[0].source_execution[0]
  let wire = request_value_policy_subject_wire(
    check, 1000000, 1000000, 100000, 100,
  )
  assert_true(wire.contains("\"request\":{\"id\":1,\"tenant\":null}"))
  assert_true(wire.contains("\"origin\":\"default\",\"parameter\":\"key\""))
  assert_true(
    wire.contains(@context.program_identity_definition_cid(program.identity)),
  )
  let cid = @environment.contract_identity(
      @environment.data_policy_envelope(
        @environment.source_view_data_policy(
          check.subject.response_policy.authoritative,
        ),
      ),
    ).2
  let evidence = bind_host_verified_request_value_policy_cid(
    check, cid, 1000000, 1000000, 100000, 100,
  )
  let selected = checking_environment(
    environment,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let augmented = checking_environment_with_request_value_policies(selected, [
    evidence,
  ])
  assert_true(physical_equal(augmented.wire, selected.wire))
  assert_eq(augmented.request_value_policies.length(), 1)
  try
    bind_host_verified_request_value_policy_cid(
      check,
      "sha256:" + "0".repeat(64),
      1000000,
      1000000,
      100000,
      100,
    )
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("unadmitted policy CID supplied request provenance")
  }
}

///|
test "equal default and supplied request values do not exchange provenance" {
  let environment = request_policy_internal_environment()
  let original = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_parameter=true,
  )
  let check = original.units[0].source_execution[0]
  let policy = @environment.source_view_data_policy(
    check.subject.response_policy.authoritative,
  )
  let evidence = bind_host_verified_request_value_policy(
    check, policy, 1000000, 1000000, 100000, 100,
  )
  let defaults = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_parameter=true,
    request_value_policies=[evidence],
  )
  assert_eq(
    defaults.units[0].source_execution[0].subject.direct_policy.unwrap().classification,
    Internal,
  )
  let supplied = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_parameter=true,
    supplied=Some(supplied_fixture("{\"key\":1}")),
    request_value_policies=[evidence],
  )
  assert_eq(
    @context.program_identity_definition_cid(original.identity),
    @context.program_identity_definition_cid(supplied.identity),
  )
  assert_eq(
    @context.program_identity_parameter_values_cid(original.identity),
    @context.program_identity_parameter_values_cid(supplied.identity),
  )
  assert_true(
    supplied.units[0].source_execution[0].subject.direct_policy.unwrap().unknown_provenance,
  )
  let evidence = bind_host_verified_request_value_policy(
    supplied.units[0].source_execution[0],
    policy,
    1000000,
    1000000,
    100000,
    100,
  )
  let verified = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_parameter=true,
    supplied=Some(supplied_fixture("{\"key\":1}")),
    request_value_policies=[evidence],
  )
  assert_eq(
    verified.units[0].source_execution[0].subject.direct_policy.unwrap().classification,
    Internal,
  )
  let changed = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_parameter=true,
    supplied=Some(supplied_fixture("{\"key\":2}")),
    request_value_policies=[evidence],
  )
  assert_true(
    changed.units[0].source_execution[0].subject.direct_policy.unwrap().unknown_provenance,
  )
}

///|
test "keyed response keeps verified static values separate from correlation provenance" {
  let environment = request_policy_internal_environment()
  let original = remote_construction_fixture(
    request_policy_budget(),
    through_check=true,
    selected_environment=Some(environment),
  )
  let check = original.4[0].source_execution[0]
  let policy = @environment.source_view_data_policy(
    check.subject.response_policy.authoritative,
  )
  let evidence = bind_host_verified_request_value_policy(
    check, policy, 1000000, 1000000, 100000, 100,
  )
  let rechecked = remote_construction_fixture(
    request_policy_budget(),
    through_check=true,
    selected_environment=Some(environment),
    request_value_policies=[evidence],
  )
  let response = rechecked.4[0].source_execution[8]
  assert_true(response.kind is KeyedResponse(_))
  assert_true(response.subject.direct_policy is None)
  assert_true(response.subject.request_value_policy is Some(_))
  let effective = prepare_effective_policy(
    [KeyedResponsePolicy(response)],
    false,
    request_policy_budget(),
  )
  assert_true(!effective.unknown_provenance)
  assert_eq(effective.classification, Internal)
  // This fixture's actual left VALUES producer remains unattested. A request
  // attestation must not supply policy for correlated values from another edge.
  let joined = remote_construction_fixture(
    request_policy_budget(),
    through_check=true,
    publish_join=true,
    selected_environment=Some(environment),
  )
  let joined_check = joined.4[0].source_execution[0]
  let joined_evidence = bind_host_verified_request_value_policy(
    joined_check, policy, 1000000, 1000000, 100000, 100,
  )
  let joined = remote_construction_fixture(
    request_policy_budget(),
    through_check=true,
    publish_join=true,
    selected_environment=Some(environment),
    request_value_policies=[joined_evidence],
  )
  let output = joined.4[0].publications[0].source_policy.unwrap()
  assert_true(output.unknown_provenance)
  assert_eq(publication_policy_classification(output), Unknown)
}

///|
test "Host-verified request policy closes exact request provenance through formal recheck" {
  let environment = request_policy_internal_environment()
  let original = checked_direct_program_fixture(
    selected_environment=Some(environment),
  )
  let check = original.units[0].source_execution[0]
  let policy = @environment.source_view_data_policy(
    check.subject.response_policy.authoritative,
  )
  assert_eq(@environment.data_classification(policy), Internal)
  assert_true(check.subject.direct_policy.unwrap().unknown_provenance)
  assert_eq(check.subject.direct_policy.unwrap().classification, Unknown)
  let evidence = bind_host_verified_request_value_policy(
    check, policy, 1000000, 1000000, 100000, 100,
  )
  // Independently fixed SHA-256 of canonical {"id":1,"tenant":null}.
  assert_eq(
    evidence.request_cid,
    "sha256:7df0345ab601b8de75cad0bc51a7c1eac7aebc9641c54ce11e4b965b5adb221e",
  )
  let rechecked = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_value_policies=[evidence],
  )
  assert_true(!physical_equal(original.identity, rechecked.identity))
  let subject = rechecked.units[0].source_execution[0].subject
  assert_true(subject.request_value_policy is Some(_))
  assert_true(!subject.direct_policy.unwrap().unknown_provenance)
  assert_eq(subject.direct_policy.unwrap().classification, Internal)
  let output = rechecked.units[0].publications[0].source_policy.unwrap()
  assert_true(!output.unknown_provenance)
  assert_eq(publication_policy_classification(output), Internal)
  assert_eq(output.effective.sources.length(), 1)
  assert_eq(output.effective.responses.length(), 1)
  // The response and request intentionally share one explicitly verified
  // Envelope; policy-set deduplication must retain their separate occurrences.
  assert_true(
    effective_policy_occurrence_at(output.effective, 0)
    is Some(DirectPolicy({ request_value_policy: Some(_), .. })),
  )
}

///|
test "absent mismatched duplicate and foreign request evidence remain unknown" {
  let environment = request_policy_internal_environment()
  let original = checked_direct_program_fixture(
    selected_environment=Some(environment),
  )
  let check = original.units[0].source_execution[0]
  let policy = @environment.source_view_data_policy(
    check.subject.response_policy.authoritative,
  )
  let evidence = bind_host_verified_request_value_policy(
    check, policy, 1000000, 1000000, 100000, 100,
  )
  for
    entries in [
      [],
      [evidence, evidence],
      [{ ..evidence, program_cid: "sha256:" + "0".repeat(64), }],
      [{ ..evidence, parameters_cid: "sha256:" + "0".repeat(64), }],
      [{ ..evidence, request_cid: "sha256:" + "0".repeat(64), }],
      [{ ..evidence, source_view_cid: "sha256:" + "0".repeat(64), }],
      [{ ..evidence, stage: 1, }],
      [{ ..evidence, input: 1, }],
      [{ ..evidence, environment: request_policy_internal_environment(), }],
    ] {
    let result = checked_direct_program_fixture(
      selected_environment=Some(environment),
      request_value_policies=entries,
    )
    let output = result.units[0].publications[0].source_policy.unwrap()
    assert_true(output.unknown_provenance)
    assert_eq(publication_policy_classification(output), Unknown)
  }
  let changed = checked_direct_program_fixture(
    selected_environment=Some(environment),
    request_value_policies=[evidence],
    input_name="other",
  )
  assert_true(
    changed.units[0].source_execution[0].subject.direct_policy.unwrap().unknown_provenance,
  )
  let foreign = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
  )
  let foreign_policy = @environment.source_view_data_policy(
    foreign.units[0].source_execution[0].subject.response_policy.authoritative,
  )
  try
    bind_host_verified_request_value_policy(
      check, foreign_policy, 1000000, 1000000, 100000, 100,
    )
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("foreign policy owner admitted")
  }
}

///|
test "request evidence preserves an admitted unknown classification" {
  let original = checked_direct_program_fixture()
  let check = original.units[0].source_execution[0]
  let policy = @environment.source_view_data_policy(
    check.subject.response_policy.authoritative,
  )
  let evidence = bind_host_verified_request_value_policy(
    check, policy, 1000000, 1000000, 100000, 100,
  )
  let execution = prepare_source_execution(
    original.identity,
    request_policy_budget(),
    request_value_policies=[evidence],
  )
  let direct = execution[0].subject.direct_policy.unwrap()
  assert_true(!direct.unknown_provenance)
  assert_eq(direct.classification, Unknown)
  let effective = prepare_effective_policy(
    [DirectPolicy(direct)],
    false,
    request_policy_budget(),
  )
  assert_eq(effective.classification, Unknown)
  assert_true(!effective.unknown_provenance)
}

///|
test "request evidence hashing and selection consume the shared bounded budget" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
  )
  let check = original.units[0].source_execution[0]
  let policy = @environment.source_view_data_policy(
    check.subject.response_policy.authoritative,
  )
  let evidence = bind_host_verified_request_value_policy(
    check, policy, 1000000, 1000000, 100000, 100,
  )
  let before = request_policy_budget()
  let result = select_request_value_policy(
    original.identity,
    0,
    0,
    check.subject.request,
    check.subject.response_policy,
    [evidence],
    before,
  )
  assert_true(result is Some(_))
  let work = 1000000 - before.work
  let bytes = 1000000 - before.bytes
  let nodes = 100000 - before.nodes
  // Independent small-fixture work ledger: three CID comparisons216,
  // evidence visit1, origin collection/sort19, origin comparison12,
  // request collection/sort11, canonical22 bytes +3 nodes, request CID72.
  assert_eq((work, bytes, nodes), (356, 22, 3))
  let exact = IdentityBudget::{ work, bytes, nodes, depth: 100, }
  assert_true(
    select_request_value_policy(
      original.identity,
      0,
      0,
      check.subject.request,
      check.subject.response_policy,
      [evidence],
      exact,
    )
    is Some(_),
  )
  assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
  for
    short in [
      IdentityBudget::{ work: work - 1, bytes, nodes, depth: 100, },
      IdentityBudget::{ work, bytes: bytes - 1, nodes, depth: 100, },
      IdentityBudget::{ work, bytes, nodes: nodes - 1, depth: 100, },
    ] {
    try
      select_request_value_policy(
        original.identity,
        0,
        0,
        check.subject.request,
        check.subject.response_policy,
        [evidence],
        short,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("request policy escaped its aggregate budget")
    }
  }
}
