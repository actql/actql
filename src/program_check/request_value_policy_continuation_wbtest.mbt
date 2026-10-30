///|
fn policy_continuation_limits() -> CompileLimits {
  {
    ..distinct_compile_limits(),
    work: 1000000,
    artifacts: { bytes: 1000000, nodes: 100000, depth: 100, },
  }
}

///|
test "policy-only continuation retains checked facts and propagates through imported Results" {
  for imported in [false, true] {
    let original = checked_direct_program_fixture(
      selected_environment=Some(request_policy_internal_environment()),
      request_parameter=true,
      imported~,
    )
    let check = original.units[0].source_execution[0]
    let proof = bind_host_verified_request_value_policy(
      check,
      @environment.source_view_data_policy(
        check.subject.response_policy.authoritative,
      ),
      1000000,
      1000000,
      100000,
      100,
    )
    let (result, spent, complete) = observe_supplement_checked_request_value_policies_owned(
      original,
      [proof],
      policy_continuation_limits(),
    )
    let selected = result.unwrap()
    assert_true(complete && spent > 0)
    assert_true(physical_equal(selected.source, original.source))
    assert_true(physical_equal(selected.identity, original.identity))
    assert_true(physical_equal(selected.requirements, original.requirements))
    assert_true(physical_equal(selected.gates, original.gates))
    assert_true(physical_equal(selected.contracts, original.contracts))
    assert_true(
      physical_equal(selected.catalog_references, original.catalog_references),
    )
    assert_true(physical_equal(selected.nest_limits, original.nest_limits))
    assert_true(physical_equal(selected.numeric_slots, original.numeric_slots))
    let subject = selected.units[0].source_execution[0].subject
    assert_true(
      physical_equal(subject.response_policy, check.subject.response_policy),
    )
    assert_true(physical_equal(subject.authority, check.subject.authority))
    assert_true(subject.request_value_policy is Some(_))
    for index, unit in selected.units {
      let before = original.units[index]
      assert_true(physical_equal(unit.pipeline, before.pipeline))
      assert_true(
        physical_equal(unit.publication_rows, before.publication_rows),
      )
      assert_true(physical_equal(unit.interfaces, before.interfaces))
      assert_eq(unit.definition_cid, before.definition_cid)
      for i, publication in unit.publications {
        let old = before.publications[i]
        assert_true(physical_equal(publication.rows, old.rows))
        assert_true(physical_equal(publication.bytes, old.bytes))
        assert_true(physical_equal(publication.proofs, old.proofs))
        let policy = publication.source_policy.unwrap()
        assert_false(policy.unknown_provenance)
        assert_eq(publication_policy_classification(policy), Internal)
      }
    }
    // The original object and its unknown-policy verdict remain immutable.
    assert_true(check.subject.request_value_policy is None)
    assert_true(
      original.units[0].publications[0].source_policy.unwrap().unknown_provenance,
    )
  }
}

///|
test "policy-only keyed continuation retains original producer bounds and converted proofs" {
  let checked = []
  remote_construction_fixture(
    request_policy_budget(),
    second_join=true,
    publish_join=true,
    through_check=true,
    checked_results=checked,
    selected_environment=Some(request_policy_internal_environment()),
  )
  |> ignore
  let original = checked[0]
  let check = original.units[0].source_execution[0]
  let proof = bind_host_verified_request_value_policy(
    check,
    @environment.source_view_data_policy(
      check.subject.response_policy.authoritative,
    ),
    1000000,
    1000000,
    100000,
    100,
  )
  let (result, _, complete) = observe_supplement_checked_request_value_policies_owned(
    original,
    [proof],
    policy_continuation_limits(),
  )
  let selected = result.unwrap()
  assert_true(complete)
  assert_true(original.keyed_input_proofs.length() > 1)
  for index, proof in selected.keyed_input_proofs {
    let old = original.keyed_input_proofs[index]
    guard proof.execution.kind is KeyedRequest(binding) &&
      old.execution.kind is KeyedRequest(previous) else {
      fail("original keyed occurrence must survive policy supplementation")
    }
    assert_true(physical_equal(binding, previous))
    assert_true(physical_equal(proof.source, old.source))
    match (proof.proof, old.proof) {
      (Some(value), Some(old)) => assert_true(physical_equal(value, old))
      (None, None) => ()
      _ => fail("converted proof changed")
    }
    assert_true(proof.execution.subject.request_value_policy is Some(_))
  }
  // The VALUES-side correlation remains unattested; a static request proof
  // cannot manufacture policy evidence for that independent original edge.
  assert_true(
    selected.units[0].publications[0].source_policy.unwrap().unknown_provenance,
  )
}

///|
test "policy-only continuation keeps exact and one-short work bounds" {
  let original = checked_direct_program_fixture(
    selected_environment=Some(request_policy_internal_environment()),
  )
  let check = original.units[0].source_execution[0]
  let evidence = [
    bind_host_verified_request_value_policy(
      check,
      @environment.source_view_data_policy(
        check.subject.response_policy.authoritative,
      ),
      1000000,
      1000000,
      100000,
      100,
    ),
  ]
  let limits = policy_continuation_limits()
  let (_, spent, complete) = observe_supplement_checked_request_value_policies_owned(
    original, evidence, limits,
  )
  assert_true(complete && spent > 1)
  let (result, exact, complete) = observe_supplement_checked_request_value_policies_owned(
    original,
    evidence,
    { ..limits, work: spent, },
  )
  assert_true(result is Ok(_) && complete && exact == spent)
  let (result, charged, complete) = observe_supplement_checked_request_value_policies_owned(
    original,
    evidence,
    { ..limits, work: spent - 1, },
  )
  assert_true(result is Err(Units(BudgetExceeded)))
  assert_false(complete)
  assert_eq(charged, spent - 1)
}
