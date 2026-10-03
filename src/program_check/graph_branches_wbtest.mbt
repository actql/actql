///|
test "formal Property Graph operands and definition scoped MATCH retain repeated producer ownership through Result import" {
  for empty in [true, false] {
    for repeated in [true, false] {
      for node_match in [true, false] {
        let programs : Array[CheckedProgram] = []
        let nodes = if repeated { "derived" } else { "seed" }
        let graph = ",{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"" +
          nodes +
          "\",\"key\":[\"id\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"all_columns\"}}]}],\"edges\":[{\"name\":\"E\",\"from\":\"derived\",\"key\":[\"id\"],\"source\":{\"definition\":\"N\",\"key\":[\"id\"]},\"target\":{\"definition\":\"N\",\"key\":[\"id\"]},\"labels\":[{\"name\":\"R\",\"properties\":{\"mode\":\"all_columns\"}}]}]},\"as\":\"g\"}"
        let projection = if node_match {
          ",{\"match_nodes\":{\"definition\":\"N\",\"label\":\"Node\",\"where\":\"true\",\"fields\":[\"id\"]}},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}"
        } else {
          ",{\"match_edges\":{\"definition\":\"E\",\"label\":\"R\",\"fields\":[\"id\",\"value\"]},\"as\":\"projected\"}"
        }
        let _ = local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          property_graph=true,
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
          extra_step_budget=if node_match { 3 } else { 2 },
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
        for name in (if node_match { ["id"] } else { ["id", "value"] }) {
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
        // Labels are a separate admitted set; MATCH never fabricates a nullable
        // legacy `rel` property or untyped source/target tuple columns.
        assert_true(@carrier.lookup(fields, Unqualified("rel")) is Absent)
        assert_true(step.input is None)
        assert_eq(@pipeline.input_occurrence_count(step), 2)
        let left = @pipeline.input_occurrence_at(step, 0).unwrap()
        let right = @pipeline.input_occurrence_at(step, 1).unwrap()
        assert_eq(left.role, @pipeline.Sample(0))
        assert_eq(right.role, @pipeline.Sample(1))
        assert_eq(left.target, @pipeline.Step(if repeated { 1 } else { 0 }))
        assert_eq(right.target, @pipeline.Step(1))
        let operations = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut endpoint_exclusions = 0
        let mut key_uniqueness = 0
        let mut resources = 0
        for i in 0..<@context.operation_closure_count(operations) {
          guard @context.operation_closure_at(operations, i)
            is Some(ExecutionCheck(PropertyGraphConstructionExecution(check))) else {
            continue
          }
          assert_true(physical_equal(check.site.pipeline, pipeline))
          assert_true(physical_equal(check.step, step))
          guard check.step.operation
            is @pipeline.PropertyGraphConstruction(inputs~, ..) else {
            fail("property occurrence owner lost")
          }
          assert_eq(inputs, [left.target, right.target])
          if check.rule is ExcludeNullKeysAndMissingEndpoints {
            endpoint_exclusions += 1
          }
          if check.rule is RejectDuplicateKeys {
            key_uniqueness += 1
          }
          if check.envelope is Some(_) {
            resources += 1
          }
        }
        // The retained closure visits the producer through both publications
        // and the consumer import. Each visit keeps all three obligations.
        assert_eq(endpoint_exclusions, 3)
        assert_eq(key_uniqueness, 3)
        assert_eq(resources, 3)
      }
    }
  }
}
