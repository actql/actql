///|
test "formal keyed join publication retains response and correlation provenance" {
  let (_, _, _, _, units) = remote_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    publish_join=true,
    through_check=true,
  )
  let policy = publication_source_policy(units[0].publications[0]).unwrap()
  assert_true(policy.unknown_provenance)
  assert_true(policy.policy is None)
  assert_eq(publication_policy_source_count(policy), 1)
  let response = publication_policy_source_at(policy, 0).unwrap()
  guard response.kind is KeyedResponse(binding) else {
    fail("keyed response was represented as a direct request")
  }
  assert_eq(@sourceviews.keyed_join_step(binding.join), 1)
  assert_eq(publication_policy_generator_count(policy), 1)
  assert_eq(publication_policy_edge_count(policy), 2)
  assert_eq(effective_policy_occurrence_count(policy.effective), 1)
  guard effective_policy_occurrence_at(policy.effective, 0)
    is Some(KeyedResponsePolicy(retained)) else {
    fail("missing response occurrence")
  }
  assert_true(physical_equal(response, retained))
  assert_true(physical_equal(response, units[0].source_execution[8]))
  // Independent canonical preimages from the fixture's pinned SourceView and
  // data-policy envelopes; SHA-256 calculated separately with Node crypto.
  assert_eq(
    response.subject.response_policy_cid,
    "sha256:93b2cf75a44af96bad21dc11d47ffd9811c12dc2bcfe7b11642ff86eb47a60fa",
  )
  assert_eq(
    policy.cid,
    "sha256:d2757b3265afd754380bbc31b515e6a902c01a4ddd71e91d7b1bbbe12722c680",
  )
}

///|
test "keyed publication rejects foreign gates and budgets the correlation traversal" {
  let (_, _, _, _, units) = remote_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    publish_join=true,
  )
  let (_, _, _, _, other) = remote_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    publish_join=true,
  )
  let unit = units[0]
  let publication = @context.publication_row_limit_result(
    unit.publication_rows[0],
  )
  try
    prepare_publication_source_policy(
      { ..unit, source_execution: other[0].source_execution, },
      publication,
      { work: 100000, bytes: 100000, nodes: 10000, depth: 100, },
    )
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("same-content foreign acquisition admitted")
  }
  let measured = IdentityBudget::{
    work: 100000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  let _ = prepare_publication_source_policy(unit, publication, measured).unwrap()
  let work = 100000 - measured.work
  let exact = IdentityBudget::{ work, bytes: 100000, nodes: 10000, depth: 100, }
  let _ = prepare_publication_source_policy(unit, publication, exact).unwrap()
  assert_eq(exact.work, 0)
  try
    prepare_publication_source_policy(unit, publication, {
      work: work - 1,
      bytes: 100000,
      nodes: 10000,
      depth: 100,
    })
  catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("partial policy escaped work limit")
  }
}

///|
test "formal checking of two keyed joins retains their own response occurrences" {
  let programs : Array[CheckedProgram] = []
  let (_, _, _, inventory, units) = remote_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    publish_join=true,
    second_join=true,
    through_check=true,
    checked_results=programs,
  )
  let unit = units[0]
  assert_eq(unit.source_execution.length(), 13)
  guard unit.source_execution[5].kind is KeyedRequest(first) &&
    unit.source_execution[9].kind is KeyedRequest(second) else {
    fail("missing keyed requests")
  }
  assert_true(physical_equal(first.producer, second.producer))
  assert_eq(keyed_input_proof_count(programs[0]), 2)
  assert_true(
    physical_equal(
      keyed_input_proof_bound(keyed_input_proof_at(programs[0], 0).unwrap()),
      keyed_input_proof_bound(keyed_input_proof_at(programs[0], 1).unwrap()),
    ),
  )
  audit_source_execution(inventory, unit.source_execution, {
    work: 1000,
    bytes: 0,
    nodes: 0,
    depth: 0,
  })
  assert_eq(unit.publications.length(), 2)
  let joins : Array[Int] = []
  for publication in unit.publications {
    let policy = publication_source_policy(publication).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    let response = publication_policy_source_at(policy, 0).unwrap()
    guard response.kind is KeyedResponse(binding) else {
      fail("missing keyed response")
    }
    joins.push(binding.index)
    assert_true(
      physical_equal(response, unit.source_execution[8 + binding.index * 4]),
    )
    // Right-only projection still depends on the left Values producer.
    assert_eq(publication_policy_generator_count(policy), 1)
    assert_eq(publication_policy_edge_count(policy), 2)
    assert_true(policy.unknown_provenance)
  }
  joins.sort()
  assert_eq(joins, [0, 1])
}
