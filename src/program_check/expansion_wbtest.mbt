///|
test "formal unpivot closes occurrence and envelope checks without dropping repeated columns" {
  for columns in ["[\"value\"]", "[\"value\",\"value\"]"] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      producer_suffix=",{\"sort\":[{\"id\":\"asc\"}]},{\"unpivot\":{\"columns\":" +
        columns +
        ",\"keep\":[\"id\"],\"name_column\":\"name\",\"value_column\":\"value\"},\"as\":\"expanded\"}",
      producer_result_from="expanded",
      extra_step_budget=2,
    )
    let program = checked[0]
    let keys = @pipeline.candidate_keys(
      unit_pipeline(program, 0).unwrap(),
      Step(2),
    ).unwrap()
    assert_eq(
      @evidence.key_witness_count(keys),
      if columns == "[\"value\"]" {
        1
      } else {
        0
      },
    )
    if columns == "[\"value\"]" {
      let key = @evidence.key_witness_at(keys, 0).unwrap()
      assert_eq(@evidence.key_origin(key), UnpivotResult)
      assert_true(@evidence.key_unpivot_input(key) is Some(_))
    }
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut emitted = 0
    let mut envelopes = 0
    let mut imported = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(ExpansionExecution(check))) else {
        continue
      }
      assert_true(
        physical_equal(check.site.pipeline, unit_pipeline(program, 0).unwrap()),
      )
      assert_eq(check.site.step, 2)
      assert_eq(check.input, @pipeline.Step(1))
      assert_eq(
        @relation.unpivot_columns_count(check.operation),
        if columns == "[\"value\"]" {
          1
        } else {
          2
        },
      )
      for j in 0..<@relation.unpivot_columns_count(check.operation) {
        assert_true(
          @relation.unpivot_column_at(check.operation, j).unwrap().field
          is Unqualified("value"),
        )
      }
      assert_true(@relation.unpivot_column_at(check.operation, -1) is None)
      assert_true(
        @relation.unpivot_column_at(
          check.operation,
          @relation.unpivot_columns_count(check.operation),
        )
        is None,
      )
      assert_eq(@relation.unpivot_keep_count(check.operation), 1)
      assert_true(
        @relation.unpivot_keep_at(check.operation, 0).unwrap().field
        is Unqualified("id"),
      )
      assert_true(@relation.unpivot_keep_at(check.operation, 1) is None)
      assert_eq(
        @relation.unpivot_outputs(check.operation),
        Some(("name", "value")),
      )
      assert_eq(
        @context.operation_execution_phase(ExpansionExecution(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        @context.operation_execution_failure(ExpansionExecution(check)),
        RejectOperationOutput,
      )
      match check.rule {
        EmitUnpivotOccurrences => emitted += 1
        EnforceOutputEnvelope(ceiling) => {
          envelopes += 1
          assert_eq(@policy.ceiling_value(ceiling), 1000L)
          assert_true(
            physical_equal(@policy.ceiling_policy(ceiling), check.policy),
          )
        }
        _ => fail("wrong expansion rule")
      }
      if check.site.stage != 0 {
        imported += 1
      }
    }
    assert_true(emitted > 0)
    assert_eq(envelopes, emitted)
    assert_true(imported > 0)
    let profiles = @context.operation_resolution_profiles(
      @context.operation_closure_index(closure),
    )
    let count = @context.operation_closure_count(closure)
    let rebuilt = @context.index_program_operation_resolutions(
      profiles, 10000000, count,
    ).unwrap()
    let work = @context.operation_resolution_work(rebuilt)
    assert_true(
      @context.index_program_operation_resolutions(profiles, work, count)
      is Ok(_),
    )
    assert_true(
      @context.index_program_operation_resolutions(profiles, work - 1, count)
      is Err(BudgetExceeded),
    )
    assert_true(
      @context.index_program_operation_resolutions(profiles, work, count - 1)
      is Err(BudgetExceeded),
    )
  }
}

///|
test "formal unpivot imports a retained parent and generated label key" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    second_stage=true,
    through_check=true,
    checked_results=checked,
    producer_suffix=",{\"unpivot\":{\"columns\":[\"value\"],\"keep\":[\"id\"],\"name_column\":\"value\",\"value_column\":\"sample\"},\"as\":\"expanded\"}",
    producer_result_from="expanded",
    extra_step_budget=1,
    second_steps="[{\"take\":1,\"as\":\"chosen\"}]",
    second_result_from="chosen",
  )
  let program = checked[0]
  let imported = @pipeline.candidate_keys(
    unit_pipeline(program, 1).unwrap(),
    Input(0),
  ).unwrap()
  assert_eq(@evidence.key_witness_count(imported), 1)
  let witness = @evidence.key_witness_at(imported, 0).unwrap()
  assert_eq(@evidence.key_origin(witness), UnpivotResult)
  assert_eq(@evidence.key_field_count(witness), 2)
  assert_true(@evidence.key_unpivot_input(witness) is Some(_))
  assert_true(@evidence.key_pending(witness).contains(ValidateKeyProducer))
  assert_true(
    @pipeline.take_order(unit_pipeline(program, 1).unwrap(), 0) is Some(_),
  )
}

///|
test "formal unnest preserves outer nullability and optional array bounds" {
  for outer in [false, true] {
    for
      bound in ["", ",\"max_items\":0", ",\"max_items\":1", ",\"max_items\":3"] {
      let checked : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        local_schema=Some(
          "{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":false}" +
          bound +
          "}}",
        ),
        producer_suffix=",{\"sort\":[{\"id\":\"asc\"}]},{\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"with_index\":true,\"outer\":" +
          outer.to_string() +
          "}},{\"select\":[\"id\",{\"value\":\"item\"}],\"as\":\"expanded\"}",
        producer_result_from="expanded",
        extra_step_budget=3,
      )
      let program = checked[0]
      let pipeline = unit_pipeline(program, 0).unwrap()
      let expanded_keys = @pipeline.candidate_keys(pipeline, Step(2)).unwrap()
      let singleton = outer &&
        (bound == ",\"max_items\":0" || bound == ",\"max_items\":1")
      assert_eq(
        @evidence.key_witness_count(expanded_keys),
        if !outer || singleton {
          1
        } else {
          0
        },
      )
      if !outer || singleton {
        let key = @evidence.key_witness_at(expanded_keys, 0).unwrap()
        assert_eq(@evidence.key_origin(key), UnnestResult)
        assert_true(@evidence.key_unnest_input(key) is Some(_))
        assert_true(@evidence.key_pending(key).contains(ValidateKeyProducer))
      }
      // The publication removes the index, so only the independent outer
      // singleton proof can survive into the next stage.
      let imported = @pipeline.candidate_keys(
        unit_pipeline(program, 1).unwrap(),
        Input(0),
      ).unwrap()
      assert_eq(
        @evidence.key_witness_count(imported),
        if singleton {
          1
        } else {
          0
        },
      )
      if singleton {
        let key = @evidence.key_witness_at(imported, 0).unwrap()
        assert_eq(@evidence.key_origin(key), UnnestResult)
        assert_true(@evidence.key_unnest_input(key) is Some(_))
      }
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut emitted = 0
      let mut envelopes = 0
      for i in 0..<@context.operation_closure_count(closure) {
        guard @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(ExpansionExecution(check))) else {
          continue
        }
        assert_true(
          physical_equal(
            check.site.pipeline,
            unit_pipeline(program, 0).unwrap(),
          ),
        )
        assert_eq(check.input, @pipeline.Step(1))
        guard @relation.reshape(check.operation)
          is Some(
            Unnest(column~, element~, index~, outer=retained_outer, max_items~)
          ) else {
          fail("expected unnest")
        }
        assert_true(column is Unqualified("items"))
        assert_eq(element, "item")
        assert_eq(index, Some("item_index"))
        assert_eq(retained_outer, outer)
        assert_eq(
          max_items,
          if bound == "" {
            None
          } else if bound == ",\"max_items\":0" {
            Some(0L)
          } else if bound == ",\"max_items\":1" {
            Some(1L)
          } else {
            Some(3L)
          },
        )
        let output = @relation.output_schema(check.operation)
        assert_eq(
          @schema.lookup(output, Unqualified("item")).unwrap().nullable,
          outer,
        )
        assert_eq(
          @schema.lookup(output, Unqualified("item_index")).unwrap().nullable,
          outer,
        )
        assert_eq(@schema.field_count(output), 5)
        match check.rule {
          EmitArrayOccurrences => emitted += 1
          EnforceOutputEnvelope(ceiling) => {
            envelopes += 1
            assert_eq(@policy.ceiling_value(ceiling), 1000L)
            assert_true(
              physical_equal(@policy.ceiling_policy(ceiling), check.policy),
            )
          }
          _ => fail("wrong expansion rule")
        }
      }
      assert_true(emitted > 0)
      assert_eq(envelopes, emitted)
    }
  }
}

///|
test "formal expansion rejects invalid bodies and missing selection order" {
  for
    body in [
      "{\"unpivot\":{\"columns\":[],\"keep\":[\"id\"],\"name_column\":\"name\",\"value_column\":\"value\"}}",
      "{\"unpivot\":{\"columns\":[\"value\"],\"keep\":[\"id\",\"id\"],\"name_column\":\"name\",\"value_column\":\"value\"}}",
      "{\"unnest\":{\"column\":\"id\",\"as\":\"item\"}}", "{\"unnest\":{\"column\":\"items\",\"as\":\"value\"}}",
      "{\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"with_index\":false}}",
      // Repeated occurrences cannot acquire uniqueness from the name column.
       "{\"unpivot\":{\"columns\":[\"value\",\"value\"],\"keep\":[\"id\"],\"name_column\":\"name\",\"value_column\":\"value\"}}",
      // Outer index is nullable and cannot by itself establish a candidate key.
       "{\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"with_index\":true,\"outer\":true}}",
    ] {
    let checked : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        local_schema=Some(
          "{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
        ),
        producer_suffix="," +
          body +
          ",{\"take\":1},{\"select\":[\"id\",\"value\"],\"as\":\"expanded\"}",
        producer_result_from="expanded",
        extra_step_budget=3,
      )
    catch {
      Source(_) | Closure(_) => ()
      e => raise e
    } noraise {
      _ => fail("invalid or unordered expansion accepted: " + body)
    }
    assert_eq(checked.length(), 0)
  }
}
