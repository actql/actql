///|
fn json_pick_schema(parent_nullable : Bool, leaf : String) -> String {
  "{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"object\",\"nullable\":" +
  parent_nullable.to_string() +
  ",\"fields\":{\"0\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"leaf\":{\"type\":\"" +
  leaf +
  "\",\"nullable\":false}}}}}}"
}

///|
test "formal json pick rejects invalid traversals without partial Programs" {
  for
    (schema, path, output) in [
      (json_pick_schema(false, "number"), "[]", "picked"),
      (json_pick_schema(false, "number"), "[\"0\",\"missing\"]", "picked"),
      (
        json_pick_schema(false, "number"),
        "[\"0\",\"leaf\",\"child\"]",
        "picked",
      ),
      (json_pick_schema(false, "json"), "[\"0\",\"leaf\",\"child\"]", "picked"),
      (json_pick_schema(false, "number"), "[\"0\",\"leaf\"]", "value"),
      (
        "{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"string\",\"nullable\":false}}",
        "[\"0\"]", "picked",
      ),
    ] {
    let checked : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        local_schema=Some(schema),
        producer_suffix=",{\"json_pick\":{\"column\":\"payload\",\"path\":" +
          path +
          ",\"output\":\"" +
          output +
          "\"},\"as\":\"selected\"}",
        producer_result_from="selected",
        extra_step_budget=1,
      )
    catch {
      Source(_) => ()
      e => raise e
    } noraise {
      _ => fail("invalid traversal accepted")
    }
    assert_eq(checked.length(), 0)
  }
}

///|
test "formal json pick retains exact object paths nullable contracts and imported ownership" {
  for nullable in [false, true] {
    for leaf in ["number", "json"] {
      let checked : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        local_schema=Some(json_pick_schema(nullable, leaf)),
        producer_suffix=",{\"json_pick\":{\"column\":\"payload\",\"path\":[\"0\",\"leaf\"],\"output\":\"picked\"}},{\"select\":[\"id\",{\"value\":\"picked\"}],\"as\":\"selected\"}",
        producer_result_from="selected",
        second_steps="[{\"select\":[\"id\",\"value\"],\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=3,
      )
      let program = checked[0]
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut owned = 0
      let mut imports = 0
      for i in 0..<@context.operation_closure_count(closure) {
        guard @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(JsonPickExecution(check))) else {
          continue
        }
        assert_true(
          physical_equal(check.site.pipeline, program.units[0].pipeline),
        )
        assert_eq(check.site.step, 1)
        assert_eq(check.input, @pipeline.Step(0))
        let (column, output) = @relation.json_pick_source(check.operation).unwrap()
        assert_true(column is Unqualified("payload"))
        assert_eq(output, "picked")
        assert_eq(@relation.json_pick_path_count(check.operation), 2)
        assert_eq(@relation.json_pick_path_at(check.operation, 0), Some("0"))
        assert_eq(@relation.json_pick_path_at(check.operation, 1), Some("leaf"))
        assert_true(@relation.json_pick_path_at(check.operation, 2) is None)
        assert_true(@relation.json_pick_path_at(check.operation, -1) is None)
        let schema = @relation.output_schema(check.operation)
        let picked = @schema.lookup(schema, Unqualified("picked")).unwrap()
        assert_eq(picked.nullable, nullable)
        assert_true(
          if leaf == "number" {
            picked.shape is @contract.Number
          } else {
            picked.shape is @contract.Json
          },
        )
        assert_eq(@schema.field_count(schema), 4)
        assert_eq(
          @context.operation_execution_phase(JsonPickExecution(check)),
          BeforeOperationOutput,
        )
        assert_eq(
          @context.operation_execution_failure(JsonPickExecution(check)),
          RejectOperationOutput,
        )
        if check.site.stage == 0 {
          owned += 1
        } else {
          imports += 1
        }
      }
      assert_eq(owned, 1)
      assert_true(imports > 0)
    }
  }
}
