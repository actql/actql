///|
fn publication_property_steps(split : Bool, node_match : Bool) -> String {
  let graph =
    #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"NODE_INPUT","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"derived","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["id"]},"labels":[{"name":"Link","properties":{"mode":"all_columns"}}]}]},"as":"g"}
  "," +
  graph.replace(old="NODE_INPUT", new=if split { "seed" } else { "derived" }) +
  (if node_match {
    ",{\"match_nodes\":{\"definition\":\"N\",\"label\":\"Node\",\"where\":\"true\",\"fields\":[\"id\"]}},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}"
  } else {
    ",{\"match_edges\":{\"definition\":\"E\",\"label\":\"Link\",\"fields\":[\"id\",\"value\"]},\"as\":\"projected\"}"
  })
}

///|
fn checked_property_publication(
  split : Bool,
  node_match : Bool,
  resources? : Bool = true,
) -> CheckedProgram raise {
  let prefix =
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"extra":{"type":"number","nullable":false}},"rows":[{"id":1,"extra":2},{"id":2,"extra":1}]},"as":"seed"},{"derive":{"value":"id"},"as":"derived"}
  checked_direct_program_fixture(
    graph_steps=prefix + publication_property_steps(split, node_match),
    graph_resources=resources,
    property_graph=true,
  )
}

///|
test "keyed Graph publication retains shared and distinct producer owners through scoped MATCH" {
  for split in [false, true] {
    for node_match in [false, true] {
      let program = checked_property_publication(split, node_match)
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      // The unused external Source cannot lend its provenance to these retained
      // Values producers. This is not admission of an unowned external definition.
      assert_eq(publication_policy_source_count(policy), 0)
      assert_eq(publication_policy_carrier_step_count(policy), 2)
      let retained = publication_policy_carrier_step_at(policy, 1).unwrap()
      guard retained.operation
        is PropertyGraphConstruction(inputs~, checked=operation) else {
        fail("keyed constructor owner lost")
      }
      assert_eq(retained.step, 2)
      assert_false(retained.unknown_provenance)
      let original_step = @pipeline.step_at(unit.pipeline, 2).unwrap()
      guard original_step.operation
        is PropertyGraphConstruction(checked=original, ..) else {
        fail("original constructor owner lost")
      }
      assert_true(physical_equal(operation, original))
      assert_eq(inputs.length(), 2)
      assert_eq(@pipeline.input_occurrence_count(original_step), 2)
      let mut occurrences = 0
      for i in 0..<publication_policy_edge_count(policy) {
        let edge = publication_policy_edge_at(policy, i).unwrap()
        if edge.step == retained.step {
          let original = @pipeline.input_occurrence_at(
            original_step, occurrences,
          ).unwrap()
          assert_eq(edge.occurrence.role, original.role)
          assert_eq(edge.occurrence.target, original.target)
          assert_eq(original.role, @pipeline.Sample(occurrences))
          occurrences += 1
        }
      }
      assert_eq(occurrences, 2)
      assert_eq(inputs[0] == inputs[1], !split)
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut uniqueness = 0
      let mut exclusions = 0
      let mut envelopes = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(PropertyGraphConstructionExecution(check))) {
          assert_true(physical_equal(check.operation, operation))
          assert_true(physical_equal(check.site.pipeline, unit.pipeline))
          assert_true(physical_equal(check.step, original_step))
          assert_eq(
            @context.operation_execution_failure(
              PropertyGraphConstructionExecution(check),
            ),
            RejectOperationOutput,
          )
          match check.rule {
            RejectDuplicateKeys => uniqueness += 1
            ExcludeNullKeysAndMissingEndpoints => exclusions += 1
            EnforcePropertyConstructionEnvelope => {
              let envelope = check.envelope.unwrap()
              assert_eq(@policy.ceiling_value(envelope.input_rows), 1000L)
              assert_eq(@policy.ceiling_value(envelope.output_nodes), 1000L)
              assert_eq(@policy.ceiling_value(envelope.output_edges), 1000L)
              envelopes += 1
            }
            _ => ()
          }
        }
      }
      assert_eq((uniqueness, exclusions, envelopes), (1, 1, 1))
    }
  }
}

///|
test "keyed Graph publication cannot waive missing construction resource selection" {
  try checked_property_publication(false, true, resources=false) catch {
    Closure(UnresolvedOperation(site)) => {
      assert_eq((site.stage, site.step), (0, 2))
      assert_true(
        site.requirement
        is @pipeline.ConstructionRequirement(ResolveGraphConstructionResources),
      )
    }
    error => raise error
  } noraise {
    _ => fail("publication cannot waive construction ceilings")
  }
}
