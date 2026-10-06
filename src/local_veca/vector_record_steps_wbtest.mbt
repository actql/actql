///|
fn vector_record_source(
  producer : @lower.BoundPrepared,
  dimensions : Int,
  id_name? : String = "id",
  vector_name? : String = "embedding",
) -> @records.Completed {
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    {
      ..limits(),
      max_value_nodes: 1000,
      max_value_bytes: 8000,
      max_work: 10000,
    },
    32768L,
    fn() { true },
  ).unwrap()
  let vector = @value.prepare_vector_value(dimensions).unwrap()
  for _ in 0..<dimensions {
    guard @value.append_vector_component(vector, 1.0) else {
      abort("fixture Vector allocation failed")
    }
  }
  let checked = @value.finish_checked_vector_value(
    vector,
    @contract.vector_contract(dimensions.to_double(), nullable=false).unwrap(),
  ).unwrap()
  @records.append_record(builder, [
    (@schema.Unqualified(id_name), number(1.0)),
    (@schema.Unqualified("group"), number(7.0)),
    (@schema.Unqualified(vector_name), checked),
  ]).unwrap()
  @records.finish_output(builder).unwrap()
}

///|
test "Normalize and Score record emission has independent cumulative boundaries" {
  let producer = pool_producer_owner(dimensions=256)
  let source = vector_record_source(producer, 256)
  for score in [false, true] {
    let owner = if score {
      score_owner(producer, query="[" + Array::make(256, "1").join(",") + "]")
    } else {
      consumer_owner(producer)
    }
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    // Normalize: kernel 10+2*254+1 extra input field = 519;
    // append: three fields 31+254 Vector polls = 285; total 804.
    // Score: kernel 19+3 extra field polls+2*254 = 530;
    // append: four fields 37+254 = 291; total 821.
    let work = if score { 821 } else { 804 }
    // Normalize: 256+8 temporary, 56 append, 5 retained, 2 handles = 327.
    // Score: 270 ordering/output + 59 append + 9 cursor custody = 338.
    let workspace = if score { 338 } else { 327 }
    // Record wire nodes: Normalize 266, Score 269; key nodes 2;
    // width overhead: respectively 4 and 5. Logical work: 272 / 276.
    let construction = if score { 276 } else { 272 }
    let short_workspace = {
      ..limits(workspace=workspace - 1),
      max_work: 10000,
      max_value_nodes: 1000,
      max_value_bytes: 8000,
    }
    if score {
      assert_true(
        start_score(
          @bounded.control(),
          sequence(owner),
          0,
          input,
          short_workspace,
          32768L,
          fn() { true },
        )
        is Err(ScoreWorkspaceLimit),
      )
    } else {
      let short = start_normalize(
        @bounded.control(),
        sequence(owner),
        0,
        input,
        short_workspace,
        32768L,
        fn() { true },
      ).unwrap()
      assert_true(
        advance_normalize(short, 1).unwrap()
        is Failed(WorkspaceLimit, work=0L, progress=0L),
      )
      assert_eq(cleanup_normalize(short), Ok(true))
    }
    for quantum in [1, 7, 256] {
      for (ceiling, success) in [(work, true), (work - 1, false)] {
        let budget = {
          ..limits(workspace~),
          max_work: construction,
          max_value_nodes: 1000,
          max_value_bytes: 8000,
        }
        let mut done = false
        if score {
          let active = start_score_with_control_work_limit(
            @bounded.control(),
            sequence(owner),
            0,
            input,
            budget,
            32768L,
            fn() { true },
            ceiling,
          ).unwrap()
          for _ in 0..<900 {
            if !done {
              match advance_score(active, quantum).unwrap() {
                ScoreContinue(..) => ()
                ScoreComplete(output, work~, ..) => {
                  assert_true(success)
                  assert_eq(work, 821L)
                  let storage = @records.completed_storage(output).unwrap()
                  assert_eq(@storage.construction_work(storage), 276)
                  assert_true(
                    pool_field(storage, 0, "score").value
                    is @value.Number(256.0),
                  )
                  assert_true(@records.discard_completed(output))
                  done = true
                }
                ScoreFailed(issue, work~, ..) => {
                  assert_false(success)
                  assert_eq(issue, ScoreWorkLimit)
                  assert_eq(work, 820L)
                  done = true
                }
                _ => fail("Score emission selected an unrelated terminal")
              }
            }
          }
          assert_eq(cleanup_score(active), Ok(true))
        } else {
          let active = start_normalize_with_control_work_limit(
            @bounded.control(),
            sequence(owner),
            0,
            input,
            budget,
            32768L,
            fn() { true },
            ceiling,
          ).unwrap()
          for _ in 0..<900 {
            if !done {
              match advance_normalize(active, quantum).unwrap() {
                Continue(..) => ()
                Complete(output, work~, ..) => {
                  assert_true(success)
                  assert_eq(work, 804L)
                  let storage = @records.completed_storage(output).unwrap()
                  assert_eq(@storage.construction_work(storage), 272)
                  guard pool_field(storage, 0, "embedding").value
                    is @value.Vector(values) else {
                    fail("normalized Vector missing")
                  }
                  assert_eq(@value.element_count(values), 256)
                  for index in 0..<256 {
                    assert_eq(@value.element_at(values, index), Some(0.0625))
                  }
                  assert_true(@records.discard_completed(output))
                  done = true
                }
                Failed(issue, work~, ..) => {
                  assert_false(success)
                  assert_eq(issue, WorkLimit)
                  assert_eq(work, 803L)
                  done = true
                }
                _ => fail("Normalize emission selected an unrelated terminal")
              }
            }
          }
          assert_eq(cleanup_normalize(active), Ok(true))
        }
        assert_true(done)
        assert_true(@records.producer_read_available(input))
      }
    }
    let short_work = {
      ..limits(workspace~),
      max_work: construction - 1,
      max_value_nodes: 1000,
      max_value_bytes: 8000,
    }
    let mut refused = false
    if score {
      let short = start_score_with_control_work_limit(
        @bounded.control(),
        sequence(owner),
        0,
        input,
        short_work,
        32768L,
        fn() { true },
        work,
      ).unwrap()
      for _ in 0..<900 {
        if !refused {
          match advance_score(short, 7).unwrap() {
            ScoreContinue(..) => ()
            ScoreFailed(issue, ..) => {
              assert_eq(
                issue,
                ScoreOutput(@records.Storage(@storage.WorkLimit)),
              )
              assert_true(short.state.output_append is Some(_))
              refused = true
            }
            _ =>
              fail("Score logical work one-short published or failed elsewhere")
          }
        }
      }
      assert_eq(cleanup_score(short), Ok(true))
    } else {
      let short = start_normalize_with_control_work_limit(
        @bounded.control(),
        sequence(owner),
        0,
        input,
        short_work,
        32768L,
        fn() { true },
        work,
      ).unwrap()
      for _ in 0..<900 {
        if !refused {
          match advance_normalize(short, 7).unwrap() {
            Continue(..) => ()
            Failed(issue, ..) => {
              assert_eq(issue, Output(@records.Storage(@storage.WorkLimit)))
              assert_true(short.state.output_append is Some(_))
              refused = true
            }
            _ =>
              fail(
                "Normalize logical work one-short published or failed elsewhere",
              )
          }
        }
      }
      assert_eq(cleanup_normalize(short), Ok(true))
    }
    assert_true(refused)
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}

///|
test "Normalize and Score keep provisional record custody until confirmed stop" {
  let producer = pool_producer_owner(dimensions=256)
  let source = vector_record_source(producer, 256)
  let budget = {
    ..limits(),
    max_value_nodes: 1000,
    max_value_bytes: 8000,
    max_work: 10000,
  }
  let owner = consumer_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let active = start_normalize(
    control,
    sequence(owner),
    0,
    input,
    budget,
    32768L,
    fn() { true },
  ).unwrap()
  // Kernel 519 plus append prefix (fields/presence/key/begin) 14:
  // poll 600 is within the 256-component output Vector emission.
  for _ in 0..<600 {
    assert_true(advance_normalize(active, 1).unwrap() is Continue(..))
  }
  assert_true(active.state.phase is AppendRecord)
  assert_true(active.state.output_append is Some(_))
  let output = active.state.output.unwrap()
  let slots = @records.output_workspace_slots(output)
  assert_true(slots > 0)
  assert_true(@bounded.request_cancel(control))
  assert_eq(cleanup_normalize(active), Err(Execution(@bounded.NotStopped)))
  assert_eq(@records.output_workspace_slots(output), slots)
  assert_true(@records.producer_read_available(input))
  assert_true(
    advance_normalize(active, 1).unwrap()
    is Stopped(@bounded.Cancelled, work=600L, progress=0L),
  )
  assert_eq(cleanup_normalize(active), Ok(true))
  assert_eq(@records.output_workspace_slots(output), 0)
  assert_true(active.state.output_append is None)
  assert_eq(cleanup_normalize(active), Ok(false))
  let owner = score_owner(
    producer,
    query="[" + Array::make(256, "1").join(",") + "]",
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let active = start_score(control, sequence(owner), 0, input, budget, 32768L, fn() {
    true
  }).unwrap()
  for _ in 0..<600 {
    assert_true(advance_score(active, 1).unwrap() is ScoreContinue(..))
  }
  assert_true(active.state.phase is ScoreAppendRecord)
  assert_true(active.state.output_append is Some(_))
  let output = active.state.output.unwrap()
  let slots = @records.output_workspace_slots(output)
  assert_true(slots > 0)
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    cleanup_score(active),
    Err(ScoreExecutionIssue(@bounded.NotStopped)),
  )
  assert_eq(@records.output_workspace_slots(output), slots)
  assert_true(
    advance_score(active, 1).unwrap()
    is ScoreStopped(@bounded.Cancelled, work=600L, progress=1L),
  )
  assert_eq(cleanup_score(active), Ok(true))
  assert_eq(@records.output_workspace_slots(output), 0)
  assert_true(active.state.output_append is None)
  assert_eq(cleanup_score(active), Ok(false))
  assert_true(@records.producer_read_available(input))
  assert_true(@records.discard_completed(source))
}

///|
test "Normalize and Score reference names yield before consuming long roles" {
  let name = String::make(513, 'z')
  for identity in [false, true] {
    let producer = pool_producer_owner(
      id_name=if identity { name } else { "id" },
      vector_name=if identity { "embedding" } else { name },
    )
    let source = vector_record_source(
      producer,
      2,
      id_name=if identity { name } else { "id" },
      vector_name=if identity { "embedding" } else { name },
    )
    if !identity {
      let owner = consumer_owner(producer)
      let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
      let control = @bounded.control()
      let active = start_normalize(
        control,
        sequence(owner),
        0,
        input,
        limits(),
        32768L,
        fn() { true },
      ).unwrap()
      let mut found = false
      for _ in 0..<30 {
        assert_true(advance_normalize(active, 1).unwrap() is Continue(..))
        if active.state.phase is MatchComponent &&
          active.state.name_offset == 64 {
          found = true
          break
        }
      }
      assert_true(found)
      assert_true(@bounded.request_cancel(control))
      assert_eq(cleanup_normalize(active), Err(Execution(@bounded.NotStopped)))
      assert_true(advance_normalize(active, 1).unwrap() is Stopped(_))
      assert_eq(cleanup_normalize(active), Ok(true))
    }
    let owner = score_owner(producer)
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let control = @bounded.control()
    let active = start_score(
      control,
      sequence(owner),
      0,
      input,
      limits(),
      32768L,
      fn() { true },
    ).unwrap()
    let mut found = false
    for _ in 0..<30 {
      assert_true(advance_score(active, 1).unwrap() is ScoreContinue(..))
      if active.state.name_offset == 64 {
        assert_true(
          if identity {
            active.state.phase is ScoreMatchIdentity
          } else {
            active.state.phase is ScoreMatchComponent
          },
        )
        found = true
        break
      }
    }
    assert_true(found)
    assert_true(@bounded.request_cancel(control))
    assert_eq(
      cleanup_score(active),
      Err(ScoreExecutionIssue(@bounded.NotStopped)),
    )
    assert_true(advance_score(active, 1).unwrap() is ScoreStopped(_))
    assert_eq(cleanup_score(active), Ok(true))
    assert_true(@records.producer_read_available(input))
    assert_true(@records.discard_completed(source))
  }
}

///|
test "Score typed Text identity validation and ties keep bounded cursors" {
  let producer = pool_producer_owner(text_keys=true)
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    { ..limits(), max_value_bytes: 8000, max_work: 10000, },
    32768L,
    fn() { true },
  ).unwrap()
  let contract = @contract.primitive(@contract.StringType, nullable=false)
  let prefix = String::make(513, 'x')
  for suffix in ["b", "a"] {
    @records.append_record(builder, [
      (
        @schema.Unqualified("id"),
        @value.checked_text_value(prefix + suffix, contract).unwrap(),
      ),
      (
        @schema.Unqualified("group"),
        @value.checked_text_value("g", contract).unwrap(),
      ),
      (@schema.Unqualified("embedding"), vector("[1,0]")),
    ]).unwrap()
  }
  let source = @records.finish_output(builder).unwrap()
  let owner = score_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Text completion shares the last code-unit poll (no separate end poll).
  // Query/scratch 4; two records (1+1+3+3+1+514+2+1)=1052;
  // two merge emissions and 514-unit tie scan 516; copy 2;
  // emit setup 10; two appends (37+9 key chunks+9 value chunks)=110;
  // finish 1. Total 1695, without deriving work from a successful run.
  for quantum in [1, 7, 256] {
    let active = start_score(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      { ..limits(), max_value_bytes: 8000, max_work: 10000, },
      32768L,
      fn() { true },
    ).unwrap()
    let mut done = false
    for _ in 0..<3000 {
      if !done {
        match advance_score(active, quantum).unwrap() {
          ScoreContinue(..) => ()
          ScoreComplete(output, work~, ..) => {
            assert_eq(work, 1695L)
            let storage = @records.completed_storage(output).unwrap()
            assert_eq(@storage.record_count(storage), 2)
            for (index, suffix) in [(0, "a"), (1, "b")] {
              guard pool_field(storage, index, "id").value is @value.Text(text) else {
                fail("typed score identity missing")
              }
              assert_eq(text, prefix + suffix)
              assert_true(
                pool_field(storage, index, "score").value is @value.Number(1.0),
              )
            }
            assert_true(@records.discard_completed(output))
            done = true
          }
          _ => fail("Text identity score did not complete")
        }
      }
    }
    assert_true(done)
    assert_eq(cleanup_score(active), Ok(true))
  }
  for tie in [false, true] {
    let control = @bounded.control()
    let active = start_score(
      control,
      sequence(owner),
      0,
      input,
      { ..limits(), max_value_bytes: 8000, max_work: 10000, },
      32768L,
      fn() { true },
    ).unwrap()
    let mut found = false
    let mut stopped_work = 0L
    for _ in 0..<2000 {
      guard advance_score(active, 1).unwrap() is ScoreContinue(work~, ..) else {
        fail("typed identity comparison was drained synchronously")
      }
      let phase = if tie {
        active.state.phase is ScoreCompareTie
      } else {
        active.state.phase is ScoreValidateIdentities
      }
      if phase && active.state.key_comparison is Some(_) {
        found = true
        stopped_work = work
        break
      }
    }
    assert_true(found)
    assert_true(@bounded.request_cancel(control))
    assert_eq(
      cleanup_score(active),
      Err(ScoreExecutionIssue(@bounded.NotStopped)),
    )
    assert_true(active.state.key_comparison is Some(_))
    guard advance_score(active, 1).unwrap()
      is ScoreStopped(@bounded.Cancelled, work~, ..) else {
      fail("Text key cancellation was not observed")
    }
    assert_eq(work, stopped_work)
    assert_eq(cleanup_score(active), Ok(true))
    assert_true(active.state.key_comparison is None)
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}

///|
test "Normalize and Score yield while emitting an unused nested Array column" {
  let array_contract = @contract.array_contract(
    @contract.primitive(@contract.NumberType, nullable=false),
    nullable=false,
  ).unwrap()
  let rows = @carrier.rows(
    [
      (
        @schema.Unqualified("id"),
        Some(@contract.primitive(@contract.NumberType, nullable=false)),
      ),
      (@schema.Unqualified("unused"), Some(array_contract)),
      (
        @schema.Unqualified("embedding"),
        Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=3,
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
        max_work: 1000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
  let unused = @value.admit(
    array_contract,
    cursor("[" + Array::make(128, "1").join(",") + "]"),
    { max_nodes: 129, max_depth: 2, max_text_bytes: 0, },
  ).unwrap()
  let budget = { ..limits(), max_value_nodes: 1000, max_work: 10000, }
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    budget,
    32768L,
    fn() { true },
  ).unwrap()
  @records.append_record(builder, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("embedding"), vector("[1,0]")),
    (@schema.Unqualified("unused"), unused),
  ]).unwrap()
  let source = @records.finish_output(builder).unwrap()
  for score in [false, true] {
    let owner = if score {
      score_owner(producer)
    } else {
      consumer_owner(producer)
    }
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let control = @bounded.control()
    // Array wire: Read + 128*(next+child) + close = 258 polls.
    // At poll 200 the kernel is inside the unused Array emission.
    if score {
      let active = start_score(
        control,
        sequence(owner),
        0,
        input,
        budget,
        32768L,
        fn() { true },
      ).unwrap()
      for _ in 0..<200 {
        assert_true(advance_score(active, 1).unwrap() is ScoreContinue(..))
      }
      assert_true(active.state.phase is ScoreAppendRecord)
      assert_true(active.state.output_append is Some(_))
      let output = active.state.output.unwrap()
      let slots = @records.output_workspace_slots(output)
      assert_true(@bounded.request_cancel(control))
      assert_eq(
        cleanup_score(active),
        Err(ScoreExecutionIssue(@bounded.NotStopped)),
      )
      assert_eq(@records.output_workspace_slots(output), slots)
      assert_true(
        advance_score(active, 1).unwrap()
        is ScoreStopped(@bounded.Cancelled, work=200L, progress=1L),
      )
      assert_eq(cleanup_score(active), Ok(true))
      assert_eq(@records.output_workspace_slots(output), 0)
    } else {
      let active = start_normalize(
        control,
        sequence(owner),
        0,
        input,
        budget,
        32768L,
        fn() { true },
      ).unwrap()
      for _ in 0..<200 {
        assert_true(advance_normalize(active, 1).unwrap() is Continue(..))
      }
      assert_true(active.state.phase is AppendRecord)
      assert_true(active.state.output_append is Some(_))
      let output = active.state.output.unwrap()
      let slots = @records.output_workspace_slots(output)
      assert_true(@bounded.request_cancel(control))
      assert_eq(cleanup_normalize(active), Err(Execution(@bounded.NotStopped)))
      assert_eq(@records.output_workspace_slots(output), slots)
      assert_true(
        advance_normalize(active, 1).unwrap()
        is Stopped(@bounded.Cancelled, work=200L, progress=0L),
      )
      assert_eq(cleanup_normalize(active), Ok(true))
      assert_eq(@records.output_workspace_slots(output), 0)
    }
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}
