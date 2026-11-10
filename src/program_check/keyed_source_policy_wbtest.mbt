///|
fn keyed_source_policy_fixture(
  verified? : Bool = false,
) -> CheckedProgram raise {
  let environment = request_policy_internal_environment()
  let originals : Array[CheckedProgram] = []
  let _ = remote_construction_fixture(
    request_policy_budget(),
    through_check=true,
    checked_results=originals,
    selected_environment=Some(environment),
  )
  if !verified {
    return originals[0]
  }
  let check = originals[0].units[0].source_execution[0]
  let policy = @environment.source_view_data_policy(
    check.subject.response_policy.authoritative,
  )
  let evidence = bind_host_verified_request_value_policy(
    check, policy, 1000000, 1000000, 100000, 100,
  )
  let checked : Array[CheckedProgram] = []
  let _ = remote_construction_fixture(
    request_policy_budget(),
    through_check=true,
    checked_results=checked,
    selected_environment=Some(environment),
    request_value_policies=[evidence],
  )
  checked[0]
}

///|
fn keyed_source_policy_execution(
  program : CheckedProgram,
) -> KeyedExecution raise {
  let check = keyed_input_proof_execution(
    keyed_input_proof_at(program, 0).unwrap(),
  )
  guard check.kind is KeyedRequest(execution) else {
    fail("original keyed execution")
  }
  execution
}

///|
test "keyed Plan policies keep static attestation separate from unknown correlated values and response" {
  let program = keyed_source_policy_fixture(verified=true)
  let execution = keyed_source_policy_execution(program)
  let policies = prepare_keyed_acquisition_source_policies(
    program, execution, 1000000, 1000000, 100000, 100,
  )
  assert_true(
    physical_equal(
      policies.original,
      keyed_input_proof_execution(keyed_input_proof_at(program, 0).unwrap()),
    ),
  )
  assert_eq(
    effective_policy_classification(policies.request),
    @environment.Unknown,
  )
  assert_true(policies.request.unknown_provenance)
  assert_eq(effective_policy_source_count(policies.request), 1)
  assert_true(effective_policy_source_at(policies.request, 0) is Some(_))
  assert_true(effective_policy_source_at(policies.request, 1) is None)
  assert_true(policies.request.responses.is_empty())
  assert_eq(
    publication_policy_classification(policies.output.unwrap()),
    @environment.Unknown,
  )
  assert_eq(policies.output.unwrap().effective.responses.length(), 1)
  assert_eq(publication_policy_source_count(policies.left.unwrap()), 0)
}

///|
test "keyed Plan policy constructor refuses a same-wire foreign execution and exhausted shared work" {
  let program = keyed_source_policy_fixture()
  let foreign = keyed_source_policy_fixture()
  try
    prepare_keyed_acquisition_source_policies(
      program,
      keyed_source_policy_execution(foreign),
      1000000,
      1000000,
      100000,
      100,
    )
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("foreign keyed policy owner")
  }
  let execution = keyed_source_policy_execution(program)
  try
    prepare_keyed_acquisition_source_policies(
      program, execution, 0, 1000000, 100000, 100,
    )
  catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("keyed policy traversal reset work")
  }
  let original = prepare_keyed_acquisition_source_policies(
    program, execution, 1000000, 1000000, 100000, 100,
  )
  assert_true(
    physical_equal(
      original.original,
      keyed_input_proof_execution(keyed_input_proof_at(program, 0).unwrap()),
    ),
  )
}

///|
test "static keyed policy occurrence retains missing provenance and rejects a response as its subject" {
  let program = keyed_source_policy_fixture()
  let check = keyed_input_proof_execution(
    keyed_input_proof_at(program, 0).unwrap(),
  )
  let value = prepare_effective_policy(
    [KeyedStaticRequestPolicy(check)],
    false,
    request_policy_budget(),
  )
  assert_eq(value.classification, @environment.Unknown)
  assert_true(value.unknown_provenance)
  assert_eq(effective_policy_source_count(value), 0)
  assert_true(value.responses.is_empty())
  guard effective_policy_occurrence_at(value, 0)
    is Some(KeyedStaticRequestPolicy(original)) else {
    fail("original missing static policy occurrence")
  }
  assert_true(physical_equal(original, check))
  try
    prepare_effective_policy(
      [KeyedStaticRequestPolicy(program.units[0].source_execution[8])],
      false,
      request_policy_budget(),
    )
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("response substituted for Request subject")
  }
}
