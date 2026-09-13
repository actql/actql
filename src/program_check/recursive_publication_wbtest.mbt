///|
test "source construction retains values recursive scope before Result projection" {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}"
  let row = "{\"id\":1,\"payload\":[[1,2]]}"
  for
    (rows, bytes) in [
      ("[]", 0),
      ("[" + row + "]", 7),
      ("[" + row + "," + row + "]", 14),
    ] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (_, closed, _, _, units) = local_construction_fixture(
      budget,
      generated_rows=Some(rows),
      generated_schema=schema,
      nested_bytes=Some(14),
      nested_depth=Some(2),
    ) catch {
      LocalConstructionFailure::Source(
        SourceFailure::SourceView(
          @context.SourceViewContextIssue::Program(
            @context.SourceViewProgramIssue::Program(
              @results.LocalProgramIssue::Pipeline(_, issue)
            )
          )
        )
      ) => {
        @debug.debug(issue.kind)
        fail("pipeline preparation")
      }
      e => raise e
    }
    let operations = @context.stage_requirement_operations(closed)
    let mut found = false
    for i in 0..<@context.operation_closure_count(operations) {
      if @context.operation_closure_at(operations, i)
        is Some(ExecutionCheck(ValuesPublication(check))) {
        assert_eq(check.recursive.bytes, bytes)
        assert_eq(check.recursive.type_depth, 2)
        assert_eq(check.recursive.selected_fields, 1)
        assert_eq(@policy.ceiling_value(check.recursive.byte_ceiling), 14L)
        assert_eq(@policy.ceiling_value(check.recursive.depth_ceiling), 2L)
        assert_true(check.recursive_limit is Some(_))
        found = true
      }
    }
    assert_true(found)
    // The public Result omits payload; that cannot erase the generator's
    // earlier recursive-value enforcement requirement.
    assert_eq(units[0].publications.length(), 1)
  }
  for
    (rows, byte_limit, depth_limit, depth_failure) in [
      ("[]", 14, 1, true),
      ("[" + row + "," + row + "]", 13, 2, false),
    ] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let before = (budget.work, budget.bytes, budget.nodes)
    try
      local_construction_fixture(
        budget,
        generated_rows=Some(rows),
        generated_schema=schema,
        nested_bytes=Some(byte_limit),
        nested_depth=Some(depth_limit),
      )
    catch {
      LocalConstructionFailure::Closure(
        ConstructionFailure::Values(@context.Recursive(_, issue))
      ) =>
        if depth_failure {
          assert_true(issue is @context.DepthExceeded)
        } else {
          assert_true(issue is @context.BytesExceeded)
        }
      e => raise e
    } noraise {
      _ => fail("recursive values limit escaped construction")
    }
    assert_eq((budget.work, budget.bytes, budget.nodes), before)
  }
}
