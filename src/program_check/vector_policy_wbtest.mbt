///|
test "vector publication retains SourceView selection and generated embeddings through the owned bridge" {
  for metric in ["", "cosine", "dot", "l2"] {
    for normalize in [false, true] {
      let steps = "{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}" +
        (if normalize { ",{\"normalize_vectors\":true}" } else { "" }) +
        (if metric == "" {
          ""
        } else {
          ",{\"score_vectors\":{\"query\":[1,2],\"metric\":\"" + metric + "\"}}"
        })
      let program = checked_direct_program_fixture(vector_steps=steps)
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(publication_policy_source_count(policy), 1)
      assert_eq(publication_policy_generator_count(policy), 1)
      assert_eq(
        publication_policy_carrier_step_count(policy),
        2 + (if normalize { 1 } else { 0 }) + (if metric != "" { 1 } else { 0 }),
      )
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut scores = 0
      let mut vectors = 0
      for i in 0..<publication_policy_carrier_step_count(policy) {
        let retained = publication_policy_carrier_step_at(policy, i).unwrap()
        if retained.operation is Vector(operation) {
          vectors += 1
          guard @pipeline.step_at(unit.pipeline, retained.step).unwrap().operation
            is Vector(original) else {
            fail("vector operation lost")
          }
          assert_true(physical_equal(original, operation))
          let scored = @vector.operation(operation) == ScoreVectors
          assert_eq(retained.unknown_provenance, scored)
          if scored {
            scores += 1
            assert_eq(
              @vector.query_value_count(@vector.query(operation).unwrap()),
              Some(2),
            )
          }
          let mut resources = 0
          let mut identities = 0
          for j in 0..<@context.operation_closure_count(closure) {
            if @context.operation_closure_at(closure, j)
              is Some(ExecutionCheck(VectorExecution(check))) &&
              check.site.step == retained.step {
              assert_true(physical_equal(check.operation, operation))
              assert_true(physical_equal(check.site.pipeline, unit.pipeline))
              assert_eq(
                @context.operation_execution_failure(VectorExecution(check)),
                RejectOperationOutput,
              )
              if check.rule == RequireVectorResources {
                assert_eq(
                  @context.vector_resource_count(check),
                  if scored {
                    4
                  } else {
                    3
                  },
                )
                resources += 1
              }
              if check.rule == RequireVectorIdentityUniqueness {
                identities += 1
              }
            }
          }
          assert_eq((resources, identities), (1, 1))
        }
      }
      assert_eq(scores, if metric == "" { 0 } else { 1 })
      assert_eq(vectors, 1 + (if normalize { 1 } else { 0 }) + scores)
    }
  }
}

///|
test "bound vector query and later normalization retain distinct owned policy contributions" {
  let program = checked_direct_program_fixture(
    vector_steps="{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"score_vectors\":{\"query\":{\"$param\":\"q\"},\"metric\":\"dot\"}},{\"normalize_vectors\":true}",
  )
  let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
  assert_eq(publication_policy_source_count(policy), 1)
  assert_eq(publication_policy_generator_count(policy), 1)
  let mut queries = 0
  let mut normalizations = 0
  for i in 0..<publication_policy_carrier_step_count(policy) {
    let retained = publication_policy_carrier_step_at(policy, i).unwrap()
    if retained.operation is Vector(operation) {
      match @vector.operation(operation) {
        ScoreVectors => {
          let query = @vector.query(operation).unwrap()
          assert_eq(@vector.query_parameter(query), Some("q"))
          assert_eq(@vector.query_value_count(query), None)
          assert_true(retained.unknown_provenance)
          queries += 1
        }
        NormalizeVectors => {
          assert_eq(retained.step, 4)
          assert_false(retained.unknown_provenance)
          normalizations += 1
        }
        ToVectors => ()
      }
    }
  }
  assert_eq((queries, normalizations), (1, 1))
  assert_true(policy.unknown_provenance)
}
