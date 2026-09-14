///|
test "pooled SourceView publication retains member provenance and Carrier-specific obligations" {
  for vectors in [false, true] {
    for reduction in ["mean", "sum", "max"] {
      for
        grouping in [
          "\"by\":[\"id\"]", "\"by\":[\"id\"],\"output_id\":\"group_id\"", "\"by\":[\"id\",\"group\"]",
        ] {
        let steps = "{\"derive\":{\"group\":\"id\"}}," +
          (if vectors {
            "{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}"
          } else {
            "{\"assert_rows\":{\"unique_by\":[\"id\"]}}"
          }) +
          ",{\"pool_vectors\":{\"vector\":\"embedding\"," +
          grouping +
          ",\"method\":\"" +
          reduction +
          "\"}}"
        let program = checked_direct_program_fixture(vector_steps=steps)
        let unit = program.units[0]
        let policy = publication_source_policy(unit.publications[0]).unwrap()
        assert_eq(publication_policy_source_count(policy), 1)
        assert_eq(publication_policy_generator_count(policy), 1)
        assert_eq(
          publication_policy_carrier_step_count(policy),
          if vectors {
            3
          } else {
            2
          },
        )
        // Backward traversal sees the projection, then the pool.
        let retained = publication_policy_carrier_step_at(policy, 1).unwrap()
        guard retained.operation is Pool(operation) else {
          fail("missing retained pool")
        }
        assert_eq(retained.step, 4)
        assert_false(retained.unknown_provenance)
        guard @pipeline.step_at(unit.pipeline, 4).unwrap().operation
          is Pool(original) else {
          fail("pool owner lost")
        }
        assert_true(physical_equal(operation, original))
        assert_eq(@vector.pool_encodes_member_key(operation), !vectors)
        assert_eq(@vector.pool_key_declaration(operation) is Some(_), !vectors)
        assert_eq(
          @vector.pool_group_count(@vector.pooled_options(operation)),
          if grouping.contains("\"group\"") {
            2
          } else {
            1
          },
        )
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut resources = 0
        let mut encodings = 0
        let mut uniqueness = 0
        let mut folds = 0
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(PoolExecution(check))) {
            assert_true(physical_equal(check.operation, operation))
            assert_true(physical_equal(check.site.pipeline, unit.pipeline))
            assert_eq(check.input, Step(3))
            assert_eq(
              @context.operation_execution_failure(PoolExecution(check)),
              RejectOperationOutput,
            )
            match check.rule {
              ResolvePoolResources => {
                resources += 1
                assert_eq(@context.pool_resource_count(check), 5)
              }
              EncodePoolMemberKeyByScalarLengths => encodings += 1
              ValidatePoolMemberIdentityGlobally => uniqueness += 1
              EvaluateDeterministicPoolFold => folds += 1
              _ => ()
            }
          }
        }
        assert_eq((resources, uniqueness, folds), (1, 1, 1))
        assert_eq(encodings, if vectors { 0 } else { 1 })
      }
    }
  }
}

///|
test "publication policy support does not waive Relation pool member key evidence" {
  try
    checked_direct_program_fixture(
      vector_steps="{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"id\"],\"method\":\"mean\"}}",
    )
  catch {
    Source(SourceView(Program(Program(Pipeline(0, issue))))) =>
      assert_true(issue.kind is Vector(MissingEligiblePoolKey))
    error => raise error
  } noraise {
    _ => fail("policy transfer cannot invent a member candidate key")
  }
}
