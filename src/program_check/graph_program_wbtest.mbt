///|
test "formal Graph construction reaches owned closure without exposing partial success" {
  for empty in [true, false] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        sga=true,
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"}},{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=3,
      )
    catch {
      Closure(UnresolvedOperation(site)) => {
        assert_true(
          site.requirement
          is @pipeline.ConstructionRequirement(
            ResolveGraphConstructionResources
          ),
        )
        assert_eq(site.step, 2)
        assert_eq(site.stage, 0)
        assert_eq(site.index, 3)
        assert_true(
          @pipeline.step_at(site.pipeline, site.step).unwrap().operation
          is @pipeline.GraphConstruction(..),
        )
      }
      other => raise other
    } noraise {
      _ => fail("expected incomplete Graph closure")
    }
    assert_eq(programs.length(), 0)
  }
}
