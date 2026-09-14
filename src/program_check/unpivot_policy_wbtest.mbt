///|
test "SourceView unpivot retains labels and repeated occurrences with expansion obligations" {
  for columns in ["[\"extra\"]", "[\"extra\",\"extra\"]", "[\"extra\",\"id\"]"] {
    let program = checked_direct_program_fixture(
      unpivot_body="{\"columns\":" +
        columns +
        ",\"keep\":[\"id\"],\"name_column\":\"label\",\"value_column\":\"amount\"}",
    )
    let publication = program.units[0].publications[0]
    let policy = publication_source_policy(publication).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_unpivot_count(policy), 1)
    assert_true(policy.unknown_provenance)
    let retained = publication_policy_unpivot_at(policy, 0).unwrap()
    assert_eq(retained.step, 0)
    let count = if columns == "[\"extra\"]" { 1 } else { 2 }
    assert_eq(@relation.unpivot_columns_count(retained.operation), count)
    assert_true(
      @relation.unpivot_column_at(retained.operation, 0).unwrap().field
      is Unqualified("extra"),
    )
    assert_eq(
      @relation.unpivot_outputs(retained.operation),
      Some(("label", "amount")),
    )
    assert_true(publication_policy_unpivot_at(policy, -1) is None)
    assert_true(publication_policy_unpivot_at(policy, 1) is None)
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut emitted = 0
    let mut bounded = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(ExpansionExecution(check))) {
        assert_true(physical_equal(check.operation, retained.operation))
        assert_eq(check.site.step, retained.step)
        match check.rule {
          EmitUnpivotOccurrences => emitted += 1
          EnforceOutputEnvelope(_) => bounded += 1
          _ => fail("wrong unpivot obligation")
        }
      }
    }
    assert_eq((emitted, bounded), (1, 1))
    let budget = IdentityBudget::{
      work: 1000000,
      bytes: 100000,
      nodes: 10000,
      depth: 100,
    }
    let result = @context.publication_row_limit_result(publication.selection)
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
      _ => fail("unpivot policy escaped preparation work")
    }
  }
}
