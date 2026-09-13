///|
test "formal lag closes navigation order binding and nullable output" {
  for partition in ["[]", "[\"id\",\"id\"]"] {
    let units : Array[String] = []
    for offset in ["", ",\"offset\":1", ",\"offset\":{\"$param\":\"n\"}"] {
      let parameter = offset.contains("$param")
      let checked : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        parameters=parameter,
        second_steps="[{\"lag\":{\"partition_by\":" +
          partition +
          ",\"order_by\":[{\"value\":\"desc\"}],\"field\":\"value\",\"output\":\"previous\"" +
          offset +
          "}},{\"take\":1},{\"select\":[\"id\",{\"value\":\"previous\"}],\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=4,
      )
      let program = checked[0]
      units.push(program.units[1].definition_cid)
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut navigation = 0
      let mut order = 0
      let mut scalar = 0
      for i in 0..<@context.operation_closure_count(closure) {
        match @context.operation_closure_at(closure, i) {
          Some(ExecutionCheck(LagExecution(check))) => {
            navigation += 1
            assert_true(
              physical_equal(check.site.pipeline, program.units[1].pipeline),
            )
            assert_eq(check.site.step, 0)
            assert_eq(check.input, @pipeline.Input(0))
            assert_true(check.field.field is Unqualified("value"))
            assert_eq(check.output, "previous")
            assert_eq(
              check.offset,
              if parameter {
                @relation.Parameter("n")
              } else {
                @relation.Literal(1L)
              },
            )
            let (_, output, value) = @relation.lag_navigation(check.operation).unwrap()
            assert_eq(output, check.output)
            assert_eq(value, check.offset)
            assert_eq(
              @relation.lag_partition_count(check.operation),
              if partition == "[]" {
                0
              } else {
                2
              },
            )
            assert_true(@relation.lag_partition_at(check.operation, -1) is None)
            let output_schema = @relation.output_schema(check.operation)
            let field = @schema.lookup(output_schema, Unqualified("previous")).unwrap()
            assert_true(field.nullable)
            assert_true(field.shape is @contract.Number)
            for p in 0..<@relation.lag_partition_count(check.operation) {
              assert_true(
                @relation.lag_partition_at(check.operation, p).unwrap().field
                is Unqualified("id"),
              )
            }
            assert_true(
              @relation.lag_partition_at(
                check.operation,
                @relation.lag_partition_count(check.operation),
              )
              is None,
            )
            assert_eq(
              @context.operation_execution_phase(LagExecution(check)),
              BeforeOperationOutput,
            )
            assert_eq(
              @context.operation_execution_failure(LagExecution(check)),
              RejectOperationOutput,
            )
          }
          Some(StaticResolution(Order(link))) if link.site.stage == 1 &&
            link.site.step == 0 => {
            guard link.resolution is @pipeline.KeyCompletion(completion) else {
              fail("wrong lag order strategy")
            }
            let fixed = partition != "[]"
            assert_eq(
              @pipeline.sort_completion_count(completion),
              if fixed {
                0
              } else {
                1
              },
            )
            assert_eq(
              @pipeline.sort_completion_field(completion, 0),
              if fixed {
                None
              } else {
                Some(Unqualified("id"))
              },
            )
            order += 1
          }
          Some(StaticResolution(Scalar(link))) if link.site.stage == 1 &&
            link.site.step == 0 => {
            assert_true(link.value is @context.Integer(1L))
            scalar += 1
          }
          _ => ()
        }
      }
      assert_eq(navigation, 1)
      assert_eq(order, 1)
      assert_eq(scalar, if parameter { 1 } else { 0 })
    }
    // Canonical binding inserts offset=1 later. Source Unit identities retain
    // authored structure; this is not expression-text normalization.
    assert_true(units[0] != units[1])
  }
}

///|
test "formal lag rejects missing keys invalid offsets and output collisions atomically" {
  for
    (prefix, output, offset, supplied) in [
      ("{\"append\":{\"with\":\"again\"}},", "previous", "1", None),
      ("", "value", "1", None),
      ("", "previous", "0", None),
      (
        "",
        "previous",
        "{\"$param\":\"n\"}",
        Some(supplied_fixture("{\"n\":0}")),
      ),
      (
        "",
        "previous",
        "{\"$param\":\"n\"}",
        Some(supplied_fixture("{\"n\":1.5}")),
      ),
    ] {
    let checked : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        parameters=true,
        supplied~,
        second_steps="[" +
          prefix +
          "{\"lag\":{\"partition_by\":[],\"order_by\":[{\"value\":\"asc\"}],\"field\":\"value\",\"output\":\"" +
          output +
          "\",\"offset\":" +
          offset +
          "},\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=3,
      )
    catch {
      Source(_) | Closure(_) => ()
      e => raise e
    } noraise {
      _ => fail("invalid lag accepted")
    }
    assert_eq(checked.length(), 0)
  }
}
