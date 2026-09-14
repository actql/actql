///|
test "SourceView pivot preserves input policy and exact bucket and fill provenance" {
  for values in ["[]", "[\"2\",\"1\"]"] {
    for
      fill in [
        "", ",\"fill\":0", ",\"fill\":null", ",\"fill\":{\"$param\":\"threshold\"}",
      ] {
      let body = "{\"index\":[\"id\"],\"column\":\"category\",\"values\":" +
        values +
        ",\"value\":\"extra\",\"aggregate\":\"min\"" +
        fill +
        "}"
      let program = checked_direct_program_fixture(pivot_body=body)
      let unit = program.units[0]
      let output = unit.publications[0]
      let policy = publication_source_policy(output).unwrap()
      assert_eq(publication_policy_source_count(policy), 1)
      assert_eq(publication_policy_pivot_count(policy), 1)
      let retained = publication_policy_pivot_at(policy, 0).unwrap()
      let step = @pipeline.step_at(unit.pipeline, 1).unwrap()
      guard step.operation is @pipeline.Unary(operation) else {
        fail("not pivot")
      }
      assert_true(physical_equal(retained.operation, operation))
      assert_true(
        physical_equal(retained.pivot, @relation.pivot(operation).unwrap()),
      )
      assert_eq(retained.step, 1)
      assert_eq(retained.unknown_provenance, values != "[]" || fill != "")
      assert_eq(publication_policy_edge_count(policy), 3)
      assert_eq(publication_policy_derivation_count(policy), 1)
      assert_true(
        !publication_policy_derivation_at(policy, 0).unwrap().unknown_provenance,
      )
      if values != "[]" {
        assert_eq(@relation.pivot_value_at(retained.pivot, 0), Some("2"))
        assert_eq(@relation.pivot_column_at(retained.pivot, 0), Some("1"))
      }
      assert_true(publication_policy_pivot_at(policy, -1) is None)
      assert_true(publication_policy_pivot_at(policy, 1) is None)
      let source = publication_policy_source_at(policy, 0).unwrap()
      assert_true(source.kind is CarrierResponse)
      assert_true(physical_equal(source.subject.owner, program.identity))
      assert_eq(source.subject.stage, 0)
      assert_eq(source.subject.input, 0)
      // Retain the source's known reference even though request literals already
      // make this fixture's effective classification unknown.
      assert_eq(publication_policy_classification(policy), @environment.Unknown)
      let budget = IdentityBudget::{
        work: 1000000,
        bytes: 100000,
        nodes: 10000,
        depth: 100,
      }
      let resolution = @context.publication_row_limit_result(output.selection)
      let rebuilt = prepare_publication_source_policy(unit, resolution, budget).unwrap()
      assert_eq(rebuilt.cid, policy.cid)
      let work = 1000000 - budget.work
      let bytes = 100000 - budget.bytes
      let nodes = 10000 - budget.nodes
      let exact = IdentityBudget::{ work, bytes, nodes, depth: 100, }
      let _ = prepare_publication_source_policy(unit, resolution, exact).unwrap()
      assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
      let short = IdentityBudget::{ work: work - 1, bytes, nodes, depth: 100, }
      try prepare_publication_source_policy(unit, resolution, short) catch {
        BudgetExceeded => ()
        error => raise error
      } noraise {
        _ => fail("pivot policy escaped traversal budget")
      }
    }
  }
}
