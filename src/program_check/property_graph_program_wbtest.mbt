///|
fn formal_property_suffix() -> String {
  "," +
  (
    #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[]},"as":"g"},{"match_nodes":{"definition":"N","label":"Node","where":"id > 0","fields":["id"]}},{"derive":{"value":"id"},"as":"projected"}
  )
}

///|
test "formal Property Graph constructor and MATCH select their distinct profile and existing resource owners" {
  for empty in [false, true] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      property_graph=true,
      graph_construction_limit=Some(1000),
      generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
      producer_suffix=formal_property_suffix(),
      producer_result_from="projected",
      extra_step_budget=3,
    )
    assert_eq(programs.length(), 1)
    let program = programs[0]
    let pipeline = unit_pipeline(program, 0).unwrap()
    assert_true(
      @pipeline.step_at(pipeline, 2).unwrap().operation
      is @pipeline.PropertyGraphConstruction(..),
    )
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut construction_checks = 0
    let mut match_checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      match @context.operation_closure_at(closure, i) {
        Some(ExecutionCheck(PropertyGraphConstructionExecution(check))) => {
          construction_checks += 1
          assert_eq(check.site.step, 2)
          assert_true(physical_equal(check.site.pipeline, pipeline))
          if check.envelope is Some(envelope) {
            assert_eq(@policy.ceiling_value(envelope.input_rows), 1000L)
            assert_eq(@policy.ceiling_value(envelope.output_nodes), 1000L)
            assert_eq(@policy.ceiling_value(envelope.output_edges), 1000L)
          }
        }
        Some(ExecutionCheck(GraphMatchExecution(check))) => {
          match_checks += 1
          assert_eq(check.site.step, 3)
          assert_true(physical_equal(check.site.pipeline, pipeline))
          assert_eq(@graph.match_property_definition(check.operation), Some(0))
        }
        _ => ()
      }
    }
    assert_eq(construction_checks, 4)
    assert_true(match_checks > 0)
    let mut count_roots = 0
    let mut law_roots = 0
    for i in 0..<@context.core_contract_root_count(program.contracts) {
      let root = @context.core_contract_root_at(program.contracts, i).unwrap()
      match root.site {
        OperationGraphCountRules(0, 0, step) if step == 2 || step == 3 => {
          assert_eq(root.body, PropertyGraphCountRules)
          count_roots += 1
        }
        OperationLaw(0, 0, step, _, _) if step == 2 || step == 3 => {
          assert_eq(root.body, AdoptedBody(@pipeline.PropertyGraphLaw))
          law_roots += 1
        }
        _ => ()
      }
    }
    assert_eq(count_roots, 2)
    assert_eq(law_roots, 2)
    assert_true(unit_publication_at(program, 0, 0) is Some(_))
  }
}

///|
test "legacy SGA declaration alone cannot claim the Property Graph profile" {
  try
    local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      sga=true,
      graph_construction_limit=Some(1000),
      generated_rows=Some("[{\"id\":1}]"),
      producer_suffix=formal_property_suffix(),
      producer_result_from="projected",
      extra_step_budget=3,
    )
  catch {
    Source(
      Checks(
        OperationProfiles(UnsupportedProfile(0, 0, 2, @pipeline.PropertyGraph))
      )
    ) => ()
    error => raise error
  } noraise {
    _ => fail("an explicit new-profile declaration is required")
  }
}
