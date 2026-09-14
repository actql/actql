///|
test "SourceView unnest retains input policy and expansion checks across outer and index modes" {
  for array in ["[id]", "[id, id]", "if(TRUE, [], [id])"] {
    for outer in [false, true] {
      for index in ["", ",\"with_index\":true", ",\"with_index\":\"position\""] {
        let program = checked_direct_program_fixture(
          array_expression=array,
          unnest_body="{\"column\":\"items\",\"as\":\"item\",\"outer\":" +
            outer.to_string() +
            index +
            "}",
        )
        let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
        assert_eq(publication_policy_source_count(policy), 1)
        assert_eq(publication_policy_unnest_count(policy), 1)
        let retained = publication_policy_unnest_at(policy, 0).unwrap()
        assert_eq(retained.step, 1)
        assert_eq(
          publication_policy_derivation_at(policy, 0).unwrap().unknown_provenance,
          array.contains("TRUE"),
        )
        guard @relation.reshape(retained.operation)
          is Some(Unnest(outer=kept, index=position, ..)) else {
          fail("not unnest")
        }
        assert_eq(kept, outer)
        assert_eq(
          position,
          if index == "" {
            None
          } else if index.contains("true") {
            Some("item_index")
          } else {
            Some("position")
          },
        )
        assert_true(publication_policy_unnest_at(policy, -1) is None)
        assert_true(publication_policy_unnest_at(policy, 1) is None)
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut emitted = 0
        let mut bounded = 0
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(ExpansionExecution(check))) {
            assert_true(physical_equal(check.operation, retained.operation))
            assert_eq(check.site.step, retained.step)
            match check.rule {
              EmitArrayOccurrences => emitted += 1
              EnforceOutputEnvelope(_) => bounded += 1
              _ => fail("wrong unnest obligation")
            }
          }
        }
        assert_eq((emitted, bounded), (1, 1))
      }
    }
  }
}
