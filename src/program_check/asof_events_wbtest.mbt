///|
test "formal asof consumes Events identity and Relation search proofs without losing Carrier roles" {
  for kind in ["inner", "left"] {
    for direction in ["backward", "forward", "nearest"] {
      let programs : Array[CheckedProgram] = []
      ignore(
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          tea=true,
          second_steps="[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"value\":2}]},\"as\":\"seed\"},{\"to_events\":{\"id\":\"id\",\"time\":\"value\"}},{\"asof_join\":{\"with\":\"seed\",\"kind\":\"" +
            kind +
            "\",\"by\":[],\"left_time\":\"id\",\"right_time\":\"id\",\"direction\":\"" +
            direction +
            "\",\"tolerance\":1,\"select\":{\"id\":\"left.id\",\"value\":\"right.value\"}},\"as\":\"selected\"}]",
          second_result_from="selected",
          second_join_capacity=true,
          second_join_step=2,
          generated_proofs=[keyed_sourceview_claim()],
          extra_step_budget=3,
        ),
      )
      let program = programs[0]
      let pipeline = unit_pipeline(program, 1).unwrap()
      guard @pipeline.step_at(pipeline, 1).unwrap().output
        is @carrier.EventValue(events) else {
        fail("expected Events operand")
      }
      assert_eq(events.identity.name, @schema.Unqualified("id"))
      assert_eq(events.time.name, @schema.Unqualified("value"))
      guard @pipeline.step_at(pipeline, 2).unwrap().output
        is @carrier.Relation(records) else {
        fail("asof must emit Relation")
      }
      assert_eq(
        @schema.lookup(
          @carrier.complete_schema(records).unwrap(),
          @schema.Unqualified("value"),
        ).unwrap().nullable,
        kind == "left",
      )
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut identities = 0
      let mut clocks = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(AsOfExecution(check))) {
          assert_true(physical_equal(check.site.pipeline, pipeline))
          assert_eq(check.left, @pipeline.Step(1))
          assert_eq(check.right, @pipeline.Step(0))
          assert_eq(@join.asof_identity(check.operation), [
            @schema.Unqualified("id"),
          ])
          assert_eq(check.left_time, @schema.Unqualified("id"))
          assert_false(check.left_timestamp)
          if check.rule is ValidateAsOfLeftIdentity {
            identities += 1
          }
          if check.rule is AdmitAsOfClocksAndDistances {
            clocks += 1
          }
        }
      }
      assert_eq(identities, 1)
      assert_eq(clocks, 1)
      assert_eq(unit_asof_search_limit_count(program, 1), Some(1))
      let limit = unit_asof_search_limit_at(program, 1, 0).unwrap()
      let writer = @encode.writer(100000, 10000, 100)
      emit_asof_search_limit(limit, writer)
      let text = @encode.finish(writer)
      assert_true(text.contains("\"unit\":\"pair_visits\""))
      assert_true(
        text.contains(
          "unit:" + unit_definition_cid(program, 1).unwrap() + "#/steps/2",
        ),
      )
      assert_false(text.contains("checked-step:"))
      for side in 0..<2 {
        let proof = asof_search_limit_proof_at(limit, side, 0).unwrap()
        assert_eq(proof_source(proof).source_ordinal, 0)
        assert_eq(
          proof_source(proof).unit_definition_cid,
          unit_definition_cid(program, 1).unwrap(),
        )
      }
    }
  }
}
