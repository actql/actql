///|
test "SourceView analytic publication retains exact calls and control provenance" {
  for
    (call, frame, missing) in [
      ("{\"fn\":\"count\"}", "", false),
      ("{\"fn\":\"min\",\"expr\":\"id\"}", "", false),
      ("{\"fn\":\"min\",\"expr\":\"1\"}", "", true),
      ("{\"fn\":\"row_number\"}", "", false),
      ("{\"fn\":\"lag\",\"expr\":\"id\"}", "", true),
      ("{\"fn\":\"lag\",\"expr\":\"id\",\"offset\":0}", "", true),
      ("{\"fn\":\"sum\",\"expr\":\"id\"}", "", false),
      ("{\"fn\":\"count\",\"expr\":\"1\",\"filter\":\"FALSE\"}", "", true),
      (
        "{\"fn\":\"count\"}", ",\"frame\":{\"start\":{\"preceding\":1},\"end\":\"current_row\"}",
        true,
      ),
    ] {
    let frame = if frame == "" &&
      !call.contains("row_number") &&
      !call.contains("lag") {
      ",\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"}"
    } else {
      frame
    }
    let program = checked_direct_program_fixture(
      analytic_body="{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"n\":" +
        call +
        "}" +
        frame +
        "}",
      numeric_profile=Some(numeric_profile_fixture()),
    )
    let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
    assert_eq(publication_policy_analytic_count(policy), 1)
    assert_eq(publication_policy_source_count(policy), 1)
    let retained = publication_policy_analytic_at(policy, 0).unwrap()
    assert_eq(retained.unknown_provenance, missing)
    assert_eq(retained.step, 1)
    guard @pipeline.step_at(program.units[0].pipeline, 1).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("not analytic")
    }
    assert_true(physical_equal(operation, retained.operation))
    assert_true(
      physical_equal(@relation.analytic(operation).unwrap(), retained.analytic),
    )
    assert_true(publication_policy_analytic_at(policy, -1) is None)
    assert_true(publication_policy_analytic_at(policy, 1) is None)
    if call.contains("sum") {
      assert_eq(unit_analytic_numeric_slot_count(program, 0), Some(1))
      let slot = unit_analytic_numeric_slot_at(program, 0, 0).unwrap()
      assert_eq(
        analytic_numeric_slot_operation(slot).source_ordinal,
        retained.step,
      )
    }
    let budget = IdentityBudget::{
      work: 1000000,
      bytes: 100000,
      nodes: 10000,
      depth: 100,
    }
    let result = @context.publication_row_limit_result(
      program.units[0].publications[0].selection,
    )
    let rebuilt = prepare_publication_source_policy(
      program.units[0],
      result,
      budget,
    ).unwrap()
    assert_eq(rebuilt.cid, policy.cid)
    let exact = IdentityBudget::{
      work: 1000000 - budget.work,
      bytes: 100000 - budget.bytes,
      nodes: 10000 - budget.nodes,
      depth: 100,
    }
    let short = IdentityBudget::{
      work: exact.work - 1,
      bytes: exact.bytes,
      nodes: exact.nodes,
      depth: 100,
    }
    let _ = prepare_publication_source_policy(program.units[0], result, exact).unwrap()
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    try
      prepare_publication_source_policy(program.units[0], result, short)
    catch {
      BudgetExceeded => ()
      error => raise error
    } noraise {
      _ => fail("analytic policy escaped preparation work")
    }
  }
}
