///|
test "values generator reaches source construction without synthetic Local inputs" {
  for rows in ["[]", "[{\"id\":1}]", "[{\"id\":1},{\"id\":1}]"] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (_, closed, _, _, units) = local_construction_fixture(
      budget,
      generated_rows=Some(rows),
    )
    assert_eq(units.length(), 1)
    assert_eq(
      @context.local_input_closure_count(
        @context.stage_requirement_inputs(closed),
      ),
      0,
    )
    let operations = @context.stage_requirement_operations(closed)
    let mut publications = 0
    for i in 0..<@context.operation_closure_count(operations) {
      match @context.operation_closure_at(operations, i).unwrap() {
        ExecutionCheck(ValuesPublication(check)) => {
          assert_eq(check.site.stage, 0)
          assert_eq(check.site.step, 0)
          publications += 1
        }
        _ => ()
      }
    }
    assert_eq(publications, 1)
    assert_eq(
      @context.publication_closure_count(
        @context.stage_requirement_publications(closed),
      ),
      1,
    )
  }
}

///|
test "generator values are checked before construction can expose a Unit" {
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
      generated_rows=Some("[{\"id\":1},{\"id\":null}]"),
    )
  catch {
    LocalConstructionFailure::Source(
      SourceFailure::SourceView(
        @context.SourceViewContextIssue::Program(
          @context.SourceViewProgramIssue::Program(
            @results.LocalProgramIssue::Pipeline(_, issue)
          )
        )
      )
    ) => assert_true(issue.kind is @pipeline.Values(_))
    e => raise e
  } noraise {
    _ => fail("invalid second row escaped source construction")
  }
  assert_eq((budget.work, budget.bytes, budget.nodes), before)
}
