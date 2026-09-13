///|
test "effective policy deduplicates references without dropping contributing occurrences" {
  let program = checked_direct_program_fixture(unused_source=true)
  let first = source_execution_subject(source_execution_at(program, 0).unwrap()).direct_policy.unwrap()
  let second = source_execution_subject(
    source_execution_at(program, 5).unwrap(),
  ).direct_policy.unwrap()
  assert_true(first.response_cid != second.response_cid)
  let source_cid = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  let (low, high) = if first.response_cid < second.response_cid {
    (first.response_cid, second.response_cid)
  } else {
    (second.response_cid, first.response_cid)
  }
  let expected = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[\"" +
    source_cid +
    "\"],\"source_response_policy_cids\":[\"" +
    low +
    "\",\"" +
    high +
    "\"],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  for inputs in [[first, second, first], [second, first, first]] {
    let budget = IdentityBudget::{
      work: 100000,
      bytes: 100000,
      nodes: 100000,
      depth: 100,
    }
    let value = prepare_effective_policy(inputs, false, budget)
    assert_eq(effective_policy_occurrence_count(value), 3)
    assert_true(
      physical_equal(
        effective_policy_occurrence_at(value, 0).unwrap(),
        inputs[0],
      ),
    )
    let retained = inputs[0]
    inputs[0] = first
    assert_true(
      physical_equal(
        effective_policy_occurrence_at(value, 0).unwrap(),
        retained,
      ),
    )
    assert_eq(value.sources.length(), 1)
    assert_eq(value.responses.length(), 2)
    let writer = @encode.writer(10000, 100, 10)
    emit_effective_policy(value, writer)
    assert_eq(@encode.finish(writer), expected)
    assert_true(effective_policy_occurrence_at(value, -1) is None)
    assert_true(effective_policy_occurrence_at(value, 3) is None)
    let used = 100000 - budget.work
    let exact = IdentityBudget::{
      work: used,
      bytes: 100000,
      nodes: 100000,
      depth: 100,
    }
    // Reuse the retained occurrence sequence, not the mutated caller array.
    let _ = prepare_effective_policy(value.occurrences, false, exact)
    assert_eq(exact.work, 0)
    try
      prepare_effective_policy(value.occurrences, false, {
        work: used - 1,
        bytes: 100000,
        nodes: 100000,
        depth: 100,
      })
    catch {
      BudgetExceeded => ()
      e => raise e
    } noraise {
      _ => fail("policy union escaped work budget")
    }
  }
}

///|
test "empty policy sets are unknown without inventing missing occurrences" {
  for unknown in [false, true] {
    let value = prepare_effective_policy([], unknown, {
      work: 0,
      bytes: 0,
      nodes: 0,
      depth: 0,
    })
    assert_eq(effective_policy_classification(value), @environment.Unknown)
    assert_eq(value.unknown_provenance, unknown)
    assert_eq(effective_policy_occurrence_count(value), 0)
    let writer = @encode.writer(10000, 100, 10)
    emit_effective_policy(value, writer)
    assert_eq(
      @encode.finish(writer),
      "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":" +
      (if unknown { "true" } else { "false" }) +
      ",\"version\":\"actql-effective-data-policy/0.1\"}",
    )
  }
}
