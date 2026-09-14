///|
test "ranking publication retains repeated weighted inputs and original producer evidence" {
  let usages : Array[Int] = []
  for count in [2, 3, 4] {
    for nested in [false, true] {
      let weights = "[0," + Array::make(count - 1, "1").join(",") + "]"
      let inputs = "[" + Array::make(count - 1, "\"n\"").join(",") + "]"
      let fusion = "{\"merge_rankings\":{\"with\":" +
        inputs +
        ",\"by\":[\"query_id\",\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":1,\"rank_window\":1,\"weights\":" +
        weights +
        "}}},\"as\":\"f\"}"
      let steps = "{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"v\"},{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":2},\"as\":\"n\"}," +
        fusion +
        (if nested {
          ",{\"merge_rankings\":{\"with\":[\"f\",\"n\"],\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":1,\"rank_window\":1,\"weights\":[1,0,2]}}}}"
        } else {
          ""
        }) +
        ",{\"select\":[{\"id\":\"query_id\"}]}"
      let program = checked_direct_program_fixture(
        vector_steps=steps,
        vector_projection=false,
      )
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(publication_policy_source_count(policy), 1)
      assert_eq(publication_policy_generator_count(policy), 1)
      assert_eq(
        publication_policy_carrier_step_count(policy),
        if nested {
          4
        } else {
          3
        },
      )
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut fusions = 0
      for i in 0..<publication_policy_carrier_step_count(policy) {
        let retained = publication_policy_carrier_step_at(policy, i).unwrap()
        if retained.operation is Ranking(operation) {
          fusions += 1
          guard @pipeline.step_at(unit.pipeline, retained.step).unwrap().operation
            is Ranking(original) else {
            fail("ranking owner lost")
          }
          assert_true(physical_equal(operation, original))
          assert_true(retained.unknown_provenance)
          let expected = if retained.step == 4 { count } else { 3 }
          assert_eq(@vector.merged_ranking_input_count(operation), expected)
          let mut edges = 0
          for j in 0..<publication_policy_edge_count(policy) {
            let edge = publication_policy_edge_at(policy, j).unwrap()
            if edge.step == retained.step {
              assert_eq(edge.occurrence.role, Sample(edges))
              assert_eq(
                edge.occurrence.target,
                Step(if retained.step == 4 || edges == 2 { 3 } else { 4 }),
              )
              edges += 1
            }
          }
          assert_eq(edges, expected)
          let mut resources = 0
          let mut complete = 0
          for j in 0..<@context.operation_closure_count(closure) {
            if @context.operation_closure_at(closure, j)
              is Some(ExecutionCheck(RankingExecution(check))) &&
              check.site.step == retained.step {
              assert_true(physical_equal(check.operation, operation))
              assert_eq(@context.ranking_execution_input_count(check), expected)
              for input in 0..<expected {
                let (_, shape) = @context.ranking_execution_input_at(
                  check, input,
                ).unwrap()
                assert_true(
                  physical_equal(
                    shape,
                    @vector.merged_ranking_input_at(operation, input).unwrap(),
                  ),
                )
              }
              if check.rule == RequireRankingResources {
                resources += 1
              }
              if check.rule == AdmitCompleteRankings {
                complete += 1
              }
            }
          }
          assert_eq((resources, complete), (1, 1))
        }
      }
      assert_eq(fusions, if nested { 2 } else { 1 })
      if !nested {
        let result = @context.publication_row_limit_result(
          unit.publications[0].selection,
        )
        let budget = IdentityBudget::{
          work: 1000000,
          bytes: 100000,
          nodes: 10000,
          depth: 100,
        }
        let rebuilt = prepare_publication_source_policy(unit, result, budget).unwrap()
        assert_eq(rebuilt.cid, policy.cid)
        let work = 1000000 - budget.work
        usages.push(work)
        try
          prepare_publication_source_policy(unit, result, {
            work: work - 1,
            bytes: 100000,
            nodes: 10000,
            depth: 100,
          })
        catch {
          BudgetExceeded => ()
          error => raise error
        } noraise {
          _ => fail("ranking policy exceeded aggregate work")
        }
      }
    }
  }
  // Each extra repeated input charges its retained edge and target visit.
  // The already-owned producer subgraph is not traversed again.
  assert_eq(usages[1] - usages[0], 2)
  assert_eq(usages[2] - usages[1], 2)
}

///|
test "SourceView fusion policy cannot authenticate authored score semantics" {
  for
    reduction in ["\"max\"", "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"] {
    try
      checked_direct_program_fixture(
        vector_steps="{\"derive\":{\"score\":\"id\"},\"as\":\"n\"},{\"merge_rankings\":{\"with\":\"n\",\"by\":[],\"candidate\":\"id\",\"score\":\"score\",\"k\":2,\"score_policy\":" +
          reduction +
          ",\"score_contract\":{\"domain\":\"d\",\"normalization\":\"n\",\"range\":[0,10]}}},{\"select\":[\"id\"]}",
        vector_projection=false,
      )
    catch {
      Source(SourceView(Program(Program(Pipeline(0, issue))))) =>
        assert_true(issue.kind is Vector(MissingScoreContract))
      error => raise error
    } noraise {
      _ => fail("authored score options cannot grant input score evidence")
    }
  }
}
