///|
test "formal named Graph operands and both row bridges retain ownership through Result import" {
  for empty in [true, false] {
    for repeated in [true, false] {
      for bridge in ["node_rows", "edge_rows"] {
        let programs : Array[CheckedProgram] = []
        let nodes = if repeated { "derived" } else { "seed" }
        let graph = ",{\"graph\":{\"nodes\":{\"from\":\"" +
          nodes +
          "\",\"id\":\"id\"},\"edges\":{\"from\":\"derived\",\"source\":\"id\",\"target\":\"value\"}},\"as\":\"g\"}"
        let projection = if bridge == "node_rows" {
          ",{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}"
        } else {
          ",{\"edge_rows\":true,\"as\":\"projected\"}"
        }
        let _ = local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          sga=true,
          graph_construction_limit=Some(1000),
          generated_rows=Some(
            if empty {
              "[]"
            } else {
              "[{\"id\":1},{\"id\":2}]"
            },
          ),
          producer_suffix=graph + projection,
          producer_result_from="projected",
          extra_step_budget=if bridge == "node_rows" { 3 } else { 2 },
        )
        assert_eq(programs.length(), 1)
        let program = programs[0]
        assert_eq(unit_count(program), 2)
        assert_true(unit_publication_at(program, 0, 0) is Some(_))
        assert_true(unit_publication_at(program, 1, 0) is Some(_))
        let pipeline = unit_pipeline(program, 0).unwrap()
        let step = @pipeline.step_at(pipeline, 2).unwrap()
        guard @pipeline.step_at(pipeline, 3).unwrap().output
          is @carrier.Relation(fields) else {
          fail("Graph bridge must produce a Relation")
        }
        for
          name in (if bridge == "node_rows" {
            ["id"]
          } else {
            ["src", "dst", "id", "value"]
          }) {
          guard @carrier.lookup(fields, Unqualified(name)) is Present(field) &&
            field.contract is Some(contract) else {
            fail("missing typed role")
          }
          assert_true(
            @contract.type_equal(
              contract,
              @contract.primitive(NumberType, nullable=false),
              10,
            ),
          )
        }
        if bridge == "edge_rows" {
          guard @carrier.lookup(fields, Unqualified("rel")) is Present(field) &&
            field.contract is Some(contract) else {
            fail("missing label role")
          }
          assert_true(
            @contract.type_equal(
              contract,
              @contract.primitive(StringType, nullable=true),
              10,
            ),
          )
        }
        assert_true(step.input is None)
        assert_eq(@pipeline.input_occurrence_count(step), 2)
        let left = @pipeline.input_occurrence_at(step, 0).unwrap()
        let right = @pipeline.input_occurrence_at(step, 1).unwrap()
        assert_eq(left.role, @pipeline.Left)
        assert_eq(right.role, @pipeline.Right)
        assert_eq(left.target, @pipeline.Step(if repeated { 1 } else { 0 }))
        assert_eq(right.target, @pipeline.Step(1))
        let operations = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut endpoints = 0
        let mut resources = 0
        for i in 0..<@context.operation_closure_count(operations) {
          guard @context.operation_closure_at(operations, i)
            is Some(ExecutionCheck(GraphConstructionExecution(check))) else {
            continue
          }
          assert_true(physical_equal(check.site.pipeline, pipeline))
          assert_true(physical_equal(check.step, step))
          assert_eq(check.nodes, Some(left.target))
          assert_eq(check.edges, right.target)
          if check.rule is CloseDeclaredEndpoints {
            endpoints += 1
          }
          if check.envelope is Some(_) {
            resources += 1
          }
        }
        assert_true(endpoints > 0)
        assert_eq(resources, endpoints)
      }
    }
  }
}
