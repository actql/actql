///|
fn deep_nullable_vector_source(
  depth : Int,
) -> (@lower.BoundPrepared, @records.Completed) {
  let number_contract = @contract.primitive(
    @contract.NumberType,
    nullable=false,
  )
  let mut deep_contract = number_contract
  for _ in 0..<depth {
    deep_contract = @contract.object_contract(
      [("a", deep_contract), ("z", number_contract)],
      nullable=false,
      max_fields=2,
      max_name_bytes=2,
    ).unwrap()
  }
  deep_contract = @contract.with_nullability(deep_contract, true)
  let vector_contract = @contract.vector_contract(1.0, nullable=false).unwrap()
  let rows = @carrier.rows(
    [
      (@schema.Unqualified("id"), Some(number_contract)),
      (@schema.Unqualified("group"), Some(number_contract)),
      (@schema.Unqualified("embedding"), Some(vector_contract)),
      (@schema.Unqualified("unused"), Some(deep_contract)),
    ],
    field_set=@carrier.Closed,
    max_fields=4,
    max_name_bytes=32,
  ).unwrap()
  let producer = bind(
    @pipeline.check_carriers(
      cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}]",
      ),
      [("rows", @carrier.relation(rows))],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
  let unused = @value.admit(deep_contract, cursor("null"), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 0,
  }).unwrap()
  let embedding = @value.admit(vector_contract, cursor("[1]"), {
    max_nodes: 2,
    max_depth: 2,
    max_text_bytes: 0,
  }).unwrap()
  let source_builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    { ..limits(), max_work: 10000, },
    32768L,
    fn() { true },
  ).unwrap()
  @records.append_record(source_builder, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("group"), number(7.0)),
    (@schema.Unqualified("embedding"), embedding),
    (@schema.Unqualified("unused"), unused),
  ]).unwrap()
  let source = @records.finish_output(source_builder).unwrap()
  (producer, source)
}

///|
test "Normalize reserves caller fields during deeper nullable contract append" {
  let (producer, source) = deep_nullable_vector_source(16)
  let owner = consumer_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Fixed append: 16 + 3*4 + 1 + 3*10 = 59.
  // Kernel admission: (1 + 2*4 + 2) + 59 + (4+2) + 2 = 78.
  // Sixteen Object levels need seventeen contract frames. Root custody
  // is fixed; 3*(17-1-10)=18 additional slots make cursor custody 77.
  // Four caller field entries remain live: 77+4=81, before handles.
  assert_eq(@storage.append_workspace_slots(4, 1, 10), Some(59))
  assert_eq(1 + 2 * 4 + 2 + 59 + 4 + 2 + 2, 78)
  assert_eq(59 + 3 * (17 - 1 - 10) + 4, 81)
  for
    (slots, should_refuse) in [
      (1000, false),
      (90, false),
      (78, true),
      (89, true),
    ] {
    let active = start_normalize_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      { ..limits(workspace=slots), max_work: 10000, },
      32768L,
      fn() { true },
      10000,
    ).unwrap()
    let mut done = false
    let mut refused = false
    let mut saw_append = false
    for _ in 0..<1000 {
      if !done {
        match advance_normalize(active, 1).unwrap() {
          Continue(..) =>
            if active.state.output_append is Some(_) {
              saw_append = true
              assert_eq(active.state.fields.length(), 4)
            }
          Complete(output, ..) => {
            let storage = @records.completed_storage(output).unwrap()
            assert_eq(@storage.record_count(storage), 1)
            assert_true(pool_field(storage, 0, "unused").value is @value.Null)
            assert_true(@records.discard_completed(output))
            done = true
          }
          Failed(issue, ..) => {
            assert_eq(issue, Output(@records.Storage(@storage.WorkspaceLimit)))
            refused = true
            done = true
          }
          _ => fail("deep nullable contract selected an unrelated terminal")
        }
      }
    }
    assert_true(done)
    assert_true(saw_append)
    assert_eq(cleanup_normalize(active), Ok(true))
    assert_eq(cleanup_normalize(active), Ok(false))
    assert_true(@records.producer_read_available(input))
    assert_eq(refused, should_refuse)
  }
  assert_true(@records.discard_completed(source))
}

///|
test "vector caller reservations survive cancellation until confirmed stop" {
  for score in [false, true] {
    let (producer, source) = deep_nullable_vector_source(
      if score {
        18
      } else {
        16
      },
    )
    let owner = if score {
      score_owner(producer, query="[1]")
    } else {
      consumer_owner(producer)
    }
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let control = @bounded.control()
    let budget = { ..limits(), max_work: 10000, }
    if score {
      let active = start_score_with_control_work_limit(
        control,
        sequence(owner),
        0,
        input,
        budget,
        32768L,
        fn() { true },
        10000,
      ).unwrap()
      let output = active.state.output.unwrap()
      let mut growing = false
      for _ in 0..<1000 {
        assert_true(advance_score(active, 1).unwrap() is ScoreContinue(..))
        if @records.output_workspace_slots(output) > 62 + 19 {
          growing = true
          break
        }
      }
      assert_true(growing)
      assert_true(active.state.output_append is Some(_))
      let held = @records.output_workspace_slots(output)
      assert_true(@bounded.request_cancel(control))
      assert_eq(
        cleanup_score(active),
        Err(ScoreExecutionIssue(@bounded.NotStopped)),
      )
      assert_eq(@records.output_workspace_slots(output), held)
      assert_true(@records.producer_read_available(input))
      assert_true(
        advance_score(active, 1).unwrap()
        is ScoreStopped(@bounded.Cancelled, ..),
      )
      assert_eq(cleanup_score(active), Ok(true))
      assert_eq(@records.output_workspace_slots(output), 0)
      assert_true(active.state.output_append is None)
      assert_eq(cleanup_score(active), Ok(false))
    } else {
      let active = start_normalize_with_control_work_limit(
        control,
        sequence(owner),
        0,
        input,
        budget,
        32768L,
        fn() { true },
        10000,
      ).unwrap()
      let output = active.state.output.unwrap()
      let mut growing = false
      for _ in 0..<1000 {
        assert_true(advance_normalize(active, 1).unwrap() is Continue(..))
        if @records.output_workspace_slots(output) > 59 + 13 {
          growing = true
          break
        }
      }
      assert_true(growing)
      assert_true(active.state.output_append is Some(_))
      let held = @records.output_workspace_slots(output)
      assert_true(@bounded.request_cancel(control))
      assert_eq(cleanup_normalize(active), Err(Execution(@bounded.NotStopped)))
      assert_eq(@records.output_workspace_slots(output), held)
      assert_true(@records.producer_read_available(input))
      assert_true(
        advance_normalize(active, 1).unwrap() is Stopped(@bounded.Cancelled, ..),
      )
      assert_eq(cleanup_normalize(active), Ok(true))
      assert_eq(@records.output_workspace_slots(output), 0)
      assert_true(active.state.output_append is None)
      assert_eq(cleanup_normalize(active), Ok(false))
    }
    assert_true(@records.producer_read_available(input))
    assert_true(@records.discard_completed(source))
  }
}

///|
test "Score reserves caller fields during deeper nullable contract append" {
  let (producer, source) = deep_nullable_vector_source(18)
  let owner = score_owner(producer, query="[1]")
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Five output fields: append 62; caller 1+3+5+1+9=19; retained 7.
  // Eighteen Object levels require 3*(19-1-10)=24 extra slots.
  // Shared append alone uses 86; five caller fields make 91, above 88.
  assert_eq(@storage.append_workspace_slots(5, 1, 10), Some(62))
  assert_eq(1 + 3 + 5 + 1 + 9 + 62 + 7, 88)
  assert_eq(62 + 3 * (19 - 1 - 10) + 5, 91)
  // Existing conservative caller reservation gives an exact peak of 105.
  assert_eq(1 + 3 + 5 + 1 + 9 + 62 + 24, 105)
  for
    (slots, should_refuse) in [
      (1000, false),
      (105, false),
      (88, true),
      (104, true),
    ] {
    let active = start_score_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      { ..limits(workspace=slots), max_work: 10000, },
      32768L,
      fn() { true },
      10000,
    ).unwrap()
    let mut done = false
    let mut refused = false
    let mut saw_append = false
    for _ in 0..<1000 {
      if !done {
        match advance_score(active, 1).unwrap() {
          ScoreContinue(..) =>
            if active.state.output_append is Some(_) {
              saw_append = true
              assert_eq(active.state.emit_fields.length(), 5)
            }
          ScoreComplete(output, ..) => {
            let storage = @records.completed_storage(output).unwrap()
            assert_eq(@storage.record_count(storage), 1)
            assert_true(pool_field(storage, 0, "unused").value is @value.Null)
            assert_true(
              pool_field(storage, 0, "score").value is @value.Number(1.0),
            )
            assert_true(@records.discard_completed(output))
            done = true
          }
          ScoreFailed(issue, ..) => {
            assert_eq(
              issue,
              ScoreOutput(@records.Storage(@storage.WorkspaceLimit)),
            )
            refused = true
            done = true
          }
          _ =>
            fail("deep nullable contract selected an unrelated Score terminal")
        }
      }
    }
    assert_true(done)
    assert_true(saw_append)
    assert_eq(cleanup_score(active), Ok(true))
    assert_eq(cleanup_score(active), Ok(false))
    assert_true(@records.producer_read_available(input))
    assert_eq(refused, should_refuse)
  }
  assert_true(@records.discard_completed(source))
}
