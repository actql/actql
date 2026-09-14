///|
test "nearest publication retains SourceView policy on either role across all Carrier pairs" {
  for candidate_vectors in [false, true] {
    for query_vectors in [false, true] {
      for remote_queries in [false, true] {
        for metric in ["cosine", "dot", "l2"] {
          let remote = if remote_queries {
            query_vectors
          } else {
            candidate_vectors
          }
          let generated = if remote_queries {
            candidate_vectors
          } else {
            query_vectors
          }
          let remote_name = if remote { "cv" } else { "c" }
          let generated_name = if generated { "qv" } else { "q" }
          let candidates = if remote_queries {
            generated_name
          } else {
            remote_name
          }
          let queries = if remote_queries {
            remote_name
          } else {
            generated_name
          }
          let remote_target = @pipeline.Step(if remote { 3 } else { 2 })
          let generated_target = @pipeline.Step(if generated { 5 } else { 4 })
          let steps = "{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"c\"},{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"cv\"},{\"from\":\"embeddings\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"q\"},{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"qv\"},{\"from\":\"" +
            candidates +
            "\",\"nearest\":{\"queries\":\"" +
            queries +
            "\",\"metric\":\"" +
            metric +
            "\",\"k\":2,\"candidate_id\":\"id\",\"query_id\":\"id\"}},{\"select\":[{\"id\":\"query_id\"}]}"
          let program = checked_direct_program_fixture(
            vector_steps=steps,
            vector_projection=false,
            vector_step_limit=10,
          )
          let unit = program.units[0]
          let policy = publication_source_policy(unit.publications[0]).unwrap()
          assert_eq(publication_policy_source_count(policy), 1)
          assert_eq(publication_policy_generator_count(policy), 1)
          let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
          guard retained.operation is Nearest(queries=target, checked=operation) else {
            fail("nearest lost")
          }
          assert_eq(retained.step, 6)
          assert_eq(
            target,
            if remote_queries {
              remote_target
            } else {
              generated_target
            },
          )
          assert_true(retained.unknown_provenance)
          guard @pipeline.step_at(unit.pipeline, 6).unwrap().operation
            is Nearest(checked=original, ..) else {
            fail("nearest owner lost")
          }
          assert_true(physical_equal(operation, original))
          let mut edges = 0
          for i in 0..<publication_policy_edge_count(policy) {
            let edge = publication_policy_edge_at(policy, i).unwrap()
            if edge.step == 6 {
              let original = @pipeline.input_occurrence_at(
                @pipeline.step_at(unit.pipeline, 6).unwrap(),
                edges,
              ).unwrap()
              assert_eq(edge.occurrence.target, original.target)
              assert_eq(edge.occurrence.role, original.role)
              edges += 1
            }
          }
          assert_eq(edges, 2)
          let closure = @context.stage_requirement_operations(
            requirements(program),
          )
          let mut resources = 0
          let mut ranks = 0
          for i in 0..<@context.operation_closure_count(closure) {
            if @context.operation_closure_at(closure, i)
              is Some(ExecutionCheck(NearestExecution(check))) {
              assert_true(physical_equal(check.operation, operation))
              assert_eq(
                check.candidates,
                if remote_queries {
                  generated_target
                } else {
                  remote_target
                },
              )
              assert_eq(check.queries, target)
              assert_eq(
                @context.operation_execution_failure(NearestExecution(check)),
                RejectOperationOutput,
              )
              match check.rule {
                ResolveNearestResources => {
                  resources += 1
                  assert_eq(@context.nearest_resource_count(check), 5)
                }
                AssignContiguousOneBasedRanks => ranks += 1
                _ => ()
              }
            }
          }
          assert_eq((resources, ranks), (1, 1))
        }
      }
    }
  }
}

///|
test "nearest shared producer retains two roles without duplicating policy vertices" {
  for predicate in ["TRUE", "FALSE"] {
    let program = checked_direct_program_fixture(
      vector_steps="{\"filter\":\"" +
        predicate +
        "\"},{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"v\"},{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":1}},{\"select\":[{\"id\":\"query_id\"}]}",
      vector_projection=false,
    )
    let unit = program.units[0]
    let policy = publication_source_policy(unit.publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_generator_count(policy), 1)
    assert_eq(publication_policy_carrier_step_count(policy), 2)
    let mut edges = 0
    for i in 0..<publication_policy_edge_count(policy) {
      let edge = publication_policy_edge_at(policy, i).unwrap()
      if edge.step == 4 {
        assert_eq(edge.occurrence.target, Step(3))
        edges += 1
      }
    }
    assert_eq(edges, 2)
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut resources = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(NearestExecution(check))) &&
        check.rule is ResolveNearestResources {
        assert_eq(check.candidates, Step(3))
        assert_eq(check.queries, Step(3))
        assert_eq(@context.nearest_resource_count(check), 5)
        resources += 1
      }
    }
    assert_eq(resources, 1)
  }
}
