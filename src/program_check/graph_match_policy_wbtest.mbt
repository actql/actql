///|
test "current Graph matches preserve original Source policy and typed selector provenance" {
  // Independently hash the authored constructor and fixed SourceView body
  // preimage. The two producer occurrences remain ordered, even when shared.
  let domain = "sha256:e95f67084a112ecd81cf96752d7dcffc731922c81ee7946fcf8ab2ef11a5b4a5"
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    domain +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
  for
    (body, unknown) in [
      (
        "{\"match_nodes\":{\"definition\":\"N\",\"ids\":[" +
        identity +
        "," +
        identity +
        "],\"fields\":[\"id\"]}}",
        true,
      ),
      (
        "{\"match_nodes\":{\"definition\":\"N\",\"where\":\"id = id\",\"fields\":[\"id\"]}}",
        false,
      ),
      (
        "{\"match_nodes\":{\"definition\":\"N\",\"where\":\"id > 0\",\"fields\":[\"id\"]}}",
        true,
      ),
      ("{\"match_edges\":{\"definition\":\"E\",\"fields\":[\"id\"]}}", false),
      (
        "{\"match_edges\":{\"definition\":\"E\",\"types\":[],\"fields\":[\"id\"]}}",
        false,
      ),
      (
        "{\"match_edges\":{\"definition\":\"E\",\"types\":[\"R\",\"R\"],\"fields\":[\"id\"]}}",
        true,
      ),
      (
        "{\"match_edges\":{\"definition\":\"E\",\"types\":[],\"where\":\"id > 0\",\"fields\":[\"id\"]}}",
        true,
      ),
    ] {
    let graph_body =
      #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"remote","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"remote","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["extra"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"}
    let program = checked_direct_program_fixture(
      graph_steps=graph_body + "," + body,
      property_graph=true,
    )
    assert_eq(source_graph_domain(program, 0), domain)
    let unit = program.units[0]
    let policy = publication_source_policy(unit.publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
    assert_eq(retained.step, 1)
    assert_eq(retained.unknown_provenance, unknown)
    guard retained.operation is GraphMatch(operation) else {
      fail("match owner lost")
    }
    guard @pipeline.step_at(unit.pipeline, 1).unwrap().operation
      is GraphMatch(original) else {
      fail("original match lost")
    }
    assert_true(physical_equal(original, operation))
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut admission = 0
    let mut resources = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(GraphMatchExecution(check))) {
        assert_true(physical_equal(check.operation, operation))
        assert_true(physical_equal(check.site.pipeline, unit.pipeline))
        assert_eq(check.input, Step(0))
        if check.rule == AdmitGraph {
          admission += 1
        }
        if check.rule == EnforceMatchResources {
          resources += 1
          assert_eq(@context.graph_match_resource_count(check), 3)
          assert_eq(@policy.ceiling_value(check.output_rows), 1000L)
        }
      }
    }
    assert_eq(admission, 1)
    assert_eq(resources, 1)
  }
}
