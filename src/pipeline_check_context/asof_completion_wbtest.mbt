///|
fn asof_test_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 50,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 50,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
test "asof key completion preserves tuples and debts separately from its journal" {
  for explicit_identity in [false, true] {
    for complete_ties in [false, true] {
      let schema = @schema.from_fields(
        ["id", "part", "clock"].map(name => {
          (
            @schema.Unqualified(name),
            @contract.primitive(NumberType, nullable=false),
          )
        }),
        max_fields=3,
        max_name_bytes=100,
      ).unwrap()
      let key = @evidence.declare_primary_key(
        asof_test_cursor("[\"id\",\"part\"]"),
        @carrier.relation(@carrier.typed_rows(schema)),
        { max_fields: 2, max_name_bytes: 100, },
      ).unwrap()
      let source = asof_test_cursor(
        "[{\"from\":\"l\",\"asof_join\":{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"clock\",\"right_time\":\"clock\",\"direction\":\"nearest\",\"tolerance\":100," +
        (if explicit_identity { "\"left_id\":\"id\"," } else { "" }) +
        "\"right_tie_break\":" +
        (if complete_ties {
          "[\"id\",\"part\"]"
        } else {
          "[\"clock\",\"clock\"]"
        }) +
        ",\"select\":{\"id\":\"left.id\",\"part\":\"left.part\"}}}]",
      )
      let pipeline = @pipeline.check_with_evidence(
        source,
        [("l", @pipeline.KeyedInput(key)), ("r", @pipeline.KeyedInput(key))],
        None,
        None,
        {
          max_steps: 10,
          max_work: 100000,
          max_text_bytes: 100000,
          max_nodes: 10000,
          max_tokens: 10000,
          max_depth: 100,
        },
      ).unwrap()
      let step = @pipeline.step_at(pipeline, 0).unwrap()
      guard step.operation is @pipeline.AsOfJoin(checked=operation, ..) else {
        fail("asof")
      }
      assert_eq(
        @join.asof_identity(operation),
        if explicit_identity {
          [Unqualified("id")]
        } else {
          [Unqualified("id"), Unqualified("part")]
        },
      )
      assert_eq(
        @join.asof_completed_tie_break(operation),
        if complete_ties {
          [Unqualified("id"), Unqualified("part")]
        } else {
          [
            Unqualified("clock"),
            Unqualified("clock"),
            Unqualified("id"),
            Unqualified("part"),
          ]
        },
      )
      let obligations = @pipeline.operation_obligation_group_at(
        step.operation,
        0,
      ).unwrap()
      let mut journals = 0
      let mut debts = 0
      for index in 0..<@pipeline.operation_obligations_count(obligations) {
        let site = {
          stage: 0,
          producer_visit: 0,
          step: 0,
          group: 0,
          index,
          pipeline,
          obligations,
          requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
        }
        if asof_key_completion(site, index).unwrap() is Some(completion) {
          journals += 1
          assert_true(physical_equal(completion.site, site))
          assert_true(physical_equal(completion.operation, operation))
          assert_true(
            physical_equal(
              completion.key,
              @join.asof_key_completion(operation, completion.side).unwrap(),
            ),
          )
          assert_eq(
            completion.input,
            if completion.side == @schema.Left {
              @pipeline.Input(0)
            } else {
              @pipeline.Input(1)
            },
          )
          assert_eq(@evidence.key_field_count(completion.key), 2)
          assert_eq(resolution_occurrence(AsOfCompletion(completion)).0, index)
          assert_true(
            asof_key_completion({ ..site, index: 100, }, index)
            is Err(ForeignOccurrence(0)),
          )
        }
        if asof_execution_check(site).unwrap() is Some(AsOfExecution(check)) &&
          check.rule is ValidateAsOfKey(side, obligation) {
          debts += 1
          let selected = check.key.unwrap()
          assert_true(
            physical_equal(
              selected,
              @join.asof_key_completion(operation, side).unwrap(),
            ),
          )
          assert_true(@evidence.key_pending(selected).contains(obligation))
          assert_eq(
            operation_execution_phase(AsOfExecution(check)),
            BeforeOperationInputUse,
          )
          assert_eq(
            operation_execution_failure(AsOfExecution(check)),
            RejectOperationOutput,
          )
          assert_true(asof_key_completion(site, index).unwrap() is None)
        }
      }
      assert_eq(
        journals,
        (if explicit_identity { 0 } else { 1 }) +
        (if complete_ties { 0 } else { 1 }),
      )
      assert_eq(
        debts,
        @evidence.key_pending_count(key) *
        (if explicit_identity { 1 } else { 2 }),
      )
    }
  }
}
