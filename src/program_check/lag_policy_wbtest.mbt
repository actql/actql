///|
test "SourceView lag retains navigation policy and the exact execution occurrence" {
  for offset in ["", ",\"offset\":1", ",\"offset\":{\"$param\":\"distance\"}"] {
    let program = checked_direct_program_fixture(
      lag_body="{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"field\":\"id\",\"output\":\"previous\"" +
        offset +
        "}",
    )
    let publication = program.units[0].publications[0]
    let policy = publication_source_policy(publication).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_lag_count(policy), 1)
    assert_true(policy.unknown_provenance)
    let retained = publication_policy_lag_at(policy, 0).unwrap()
    assert_eq(retained.step, 1)
    assert_eq(retained.output, "previous")
    assert_true(retained.field.field is Unqualified("id"))
    assert_eq(
      retained.offset,
      if offset.contains("$param") {
        @relation.Parameter("distance")
      } else {
        @relation.Literal(1L)
      },
    )
    assert_true(publication_policy_lag_at(policy, -1) is None)
    assert_true(publication_policy_lag_at(policy, 1) is None)
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(LagExecution(check))) {
        checks += 1
        assert_true(physical_equal(check.operation, retained.operation))
        assert_eq(check.offset, retained.offset)
        assert_eq(check.site.step, retained.step)
      }
    }
    assert_eq(checks, 1)
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
      _ => fail("lag policy escaped preparation work")
    }
  }
}
