///|
test "formal top k retains count binding order completion and partition semantics" {
  for partition in [None, Some("[]"), Some("[\"id\",\"id\"]")] {
    for parameter in [false, true] {
      let checked : Array[CheckedProgram] = []
      let key = if partition is Some(_) { "top_k_by" } else { "top_k" }
      let body = "{\"k\":" +
        (if parameter { "{\"$param\":\"n\"}" } else { "2" }) +
        ",\"by\":[{\"value\":\"desc\"}]" +
        (match partition {
          None => ""
          Some(keys) => ",\"partition_by\":" + keys
        }) +
        "}"
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        parameters=parameter,
        second_steps="[{\"" + key + "\":" + body + ",\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=2,
      )
      let program = checked[0]
      let pipeline = unit_pipeline(program, 1).unwrap()
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut selection = 0
      let mut partitions = 0
      let mut orders = 0
      let mut scalars = 0
      for i in 0..<@context.operation_closure_count(closure) {
        match @context.operation_closure_at(closure, i) {
          Some(ExecutionCheck(TopKExecution(check))) => {
            assert_true(physical_equal(check.site.pipeline, pipeline))
            assert_eq(check.input, @pipeline.Input(0))
            assert_eq(@policy.ceiling_value(check.output_ceiling), 1000L)
            assert_eq(
              @policy.ceiling_field(check.output_ceiling),
              "max_relation_output_rows",
            )
            assert_true(
              physical_equal(
                @policy.ceiling_policy(check.output_ceiling),
                check.policy,
              ),
            )
            assert_eq(
              check.count,
              if parameter {
                @relation.Parameter("n")
              } else {
                @relation.Literal(2L)
              },
            )
            assert_eq(@relation.ranking_term_count(check.operation), 1)
            assert_eq(
              @relation.top_k_partition_count(check.operation),
              if partition == Some("[\"id\",\"id\"]") {
                2
              } else {
                0
              },
            )
            assert_true(
              @relation.top_k_partition_at(check.operation, -1) is None,
            )
            assert_eq(@relation.top_k_count(check.operation), Some(check.count))
            for p in 0..<@relation.top_k_partition_count(check.operation) {
              assert_true(
                @relation.top_k_partition_at(check.operation, p).unwrap().field
                is Unqualified("id"),
              )
            }
            assert_true(
              @relation.top_k_partition_at(
                check.operation,
                @relation.top_k_partition_count(check.operation),
              )
              is None,
            )
            assert_eq(
              @context.operation_execution_phase(TopKExecution(check)),
              BeforeOperationOutput,
            )
            assert_eq(
              @context.operation_execution_failure(TopKExecution(check)),
              RejectOperationOutput,
            )
            match check.rule {
              SelectOrderedPrefix => selection += 1
              PartitionByCanonicalKeys => partitions += 1
            }
          }
          Some(StaticResolution(Order(link))) if physical_equal(
              link.site.pipeline,
              pipeline,
            ) => {
            guard link.resolution is @pipeline.KeyCompletion(completion) else {
              fail("top k did not retain candidate-key completion")
            }
            let fixed = partition == Some("[\"id\",\"id\"]")
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
            orders += 1
          }
          Some(StaticResolution(Scalar(link))) if physical_equal(
              link.site.pipeline,
              pipeline,
            ) => {
            assert_true(link.value is @context.Integer(1L))
            scalars += 1
          }
          _ => ()
        }
      }
      assert_eq(selection, 1)
      assert_eq(partitions, if partition is Some(_) { 1 } else { 0 })
      assert_eq(orders, 1)
      assert_eq(scalars, if parameter { 1 } else { 0 })
    }
  }
}

///|
test "top k rejects lost keys and invalid bound counts without partial Programs" {
  for partition in ["", "\"partition_by\":[],"] {
    let key = if partition == "" { "top_k" } else { "top_k_by" }
    for
      (prefix, count, supplied) in [
        ("{\"append\":{\"with\":\"again\"}},", "2", None),
        ("", "{\"$param\":\"n\"}", Some(supplied_fixture("{\"n\":0}"))),
        ("", "{\"$param\":\"n\"}", Some(supplied_fixture("{\"n\":1.5}"))),
        ("", "{\"$param\":\"n\"}", Some(supplied_fixture("{\"n\":-1}"))),
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
            "{\"" +
            key +
            "\":{" +
            partition +
            "\"k\":" +
            count +
            ",\"by\":[{\"value\":\"desc\"}]},\"as\":\"selected\"}]",
          second_result_from="selected",
          extra_step_budget=3,
        )
      catch {
        Source(_) | Closure(_) => ()
        e => raise e
      } noraise {
        _ => fail("invalid top k accepted")
      }
      assert_eq(checked.length(), 0)
    }
  }
}
