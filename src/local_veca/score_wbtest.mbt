///|
fn score_owner(
  producer : @lower.BoundPrepared,
  query? : String = "[1,0]",
  metric? : String = "dot",
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"score_vectors\":{\"query\":" +
        query +
        ",\"metric\":\"" +
        metric +
        "\"}}]",
      ),
      [
        (
          "prior",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(producer)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"prior\"")),
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
}

///|
fn second_input_score_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"score_vectors\":{\"query\":[1,0],\"metric\":\"dot\"}}]"),
      [
        (
          "first",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(first)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
        (
          "second",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(second)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(cursor("\"second\"")),
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
}

///|
fn scored_source(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  for (id, components) in [(2.0, "[1,0]"), (1.0, "[1,0]"), (3.0, "[0,1]")] {
    @records.append_record(output, [
      (@schema.Unqualified("id"), number(id)),
      (@schema.Unqualified("embedding"), vector(components)),
    ]).unwrap()
  }
  @records.finish_output(output).unwrap()
}

///|
fn empty_scored_source(owner : @lower.BoundPrepared) -> @records.Completed {
  @records.finish_output(
    @records.prepare_output(owner, @pipeline.Step(0), limits(), 4096L, fn() {
      true
    }).unwrap(),
  ).unwrap()
}

///|
fn single_scored_source(owner : @lower.BoundPrepared) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  @records.append_record(output, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("embedding"), vector("[1,0]")),
  ]).unwrap()
  @records.finish_output(output).unwrap()
}

///|
fn finish_score_execution(execution : ScoreExecution) -> @records.Completed {
  while true {
    match advance_score(execution, 1).unwrap() {
      ScoreContinue(..) => ()
      ScoreComplete(output, ..) => return output
      ScoreFailed(_, ..) => abort("score failed")
      ScoreStopped(_, ..) => abort("score stopped")
    }
  }
  abort("unreachable")
}

///|
fn scored_field(
  storage : @storage.Storage,
  record : Int,
  expected : String,
) -> @value.CheckedValue {
  let count = @storage.record_field_count(storage, record).unwrap()
  for field in 0..<count {
    guard @storage.record_field_at(storage, record, field)
      is Some((name, value)) else {
      abort("score field")
    }
    if @schema.reference_name(name) == expected {
      return value
    }
  }
  abort("missing score field")
}

///|
test "score enforces cumulative empty-input control work" {
  let producer = producer_owner()
  let source = empty_scored_source(producer)
  let owner = score_owner(producer)
  let zero_input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_score(
      @bounded.control(),
      sequence(owner),
      0,
      zero_input,
      limits(work=0),
      4096L,
      fn() { true },
    )
    is Err(ScoreWorkLimit),
  )
  // Two query components and one output finish are required even with no
  // input records. Scratch and merge phases have no work on empty input.
  for (ceiling, accepted) in [(3, true), (2, false)] {
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_score_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      4096L,
      fn() { true },
      ceiling,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<8 {
      if !terminal {
        match advance_score(execution, 1).unwrap() {
          ScoreContinue(work=next, ..) => {
            assert_true(next >= charged && next - charged <= 1L)
            charged = next
          }
          ScoreComplete(output, work=next, ..) => {
            assert_true(accepted)
            assert_eq(next - charged, 1L)
            guard @records.completed_storage(output) is Some(material) else {
              fail("empty score output missing")
            }
            assert_eq(@storage.record_count(material), 0)
            charged = next
            terminal = true
          }
          ScoreFailed(ScoreWorkLimit, work=next, ..) => {
            assert_false(accepted)
            assert_eq(next, charged)
            assert_true(score_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("empty score work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_eq(cleanup_score(execution), Ok(true))
    assert_true(@records.producer_read_available(input))
  }
}

///|
test "score enforces cumulative one-record control work" {
  let producer = producer_owner()
  let source = single_scored_source(producer)
  let owner = score_owner(producer)
  // Query validation: 2; scratch: 1; record start and field/identity scan:
  // 7; score fold and finish: 3; emit fields, score, commit, and finish: 5.
  for (ceiling, accepted) in [(18, true), (17, false)] {
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_score_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      4096L,
      fn() { true },
      ceiling,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<24 {
      if !terminal {
        match advance_score(execution, 1).unwrap() {
          ScoreContinue(work=next, ..) => {
            assert_true(next >= charged && next - charged <= 1L)
            charged = next
          }
          ScoreComplete(output, work=next, ..) => {
            assert_true(accepted)
            assert_eq(next - charged, 1L)
            guard @records.completed_storage(output) is Some(material) else {
              fail("scored output missing")
            }
            assert_eq(@storage.record_count(material), 1)
            charged = next
            terminal = true
          }
          ScoreFailed(ScoreWorkLimit, work=next, ..) => {
            assert_false(accepted)
            assert_eq(next, charged)
            assert_true(score_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("one-record score work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_eq(cleanup_score(execution), Ok(true))
    assert_true(@records.producer_read_available(input))
  }
}

///|
test "score orders by value then typed identity and feeds two consumers" {
  let producer = producer_owner()
  let source_live = Ref(true)
  let source = scored_source(producer, source_live)
  let owner = score_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_score(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(score_max_noninterruptible_value_nodes(execution), 100)
  assert_eq(score_max_noninterruptible_value_bytes(execution), 1000)
  let completed = finish_score_execution(execution)
  assert_true(score_stopped(execution))
  assert_true(score_cleanup_pending(execution))
  assert_eq(cleanup_score(execution), Ok(true))
  source_live.val = false
  assert_true(@records.completed_available(completed))
  let material = @records.completed_storage(completed).unwrap()
  assert_eq(@storage.record_count(material), 3)
  for
    (record, expected_id, expected_score) in [
      (0, 1.0, 1.0),
      (1, 2.0, 1.0),
      (2, 3.0, 0.0),
    ] {
    guard scored_field(material, record, "id").value is @value.Number(id) &&
      scored_field(material, record, "score").value is @value.Number(score) else {
      fail("numeric score output")
    }
    assert_eq(id, expected_id)
    assert_eq(score, expected_score)
  }

  let downstream = consumer_owner(owner)
  let first = @records.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  let second = @records.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  assert_false(@records.producer_read_same(first, second))
  assert_eq(
    @storage.record_count(@records.producer_read_storage(first).unwrap()),
    3,
  )
  assert_eq(
    @storage.record_count(@records.producer_read_storage(second).unwrap()),
    3,
  )
}

///|
test "vector score admits only the exact external operation input" {
  let first_owner = producer_owner()
  let second_owner = producer_owner()
  let first = scored_source(first_owner, Ref(true))
  let second = scored_source(second_owner, Ref(true))
  let owner = second_input_score_owner(first_owner, second_owner)
  let wrong = @records.prepare_producer_read(owner, 0, first_owner, first).unwrap()
  assert_true(
    start_score(
      @bounded.control(),
      sequence(owner),
      0,
      wrong,
      limits(),
      4096L,
      fn() { true },
    )
    is Err(InvalidScoreKernel),
  )
  let exact = @records.prepare_producer_read(owner, 1, second_owner, second).unwrap()
  let control = @bounded.control()
  let execution = start_score(
    control,
    sequence(owner),
    0,
    exact,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_score(execution, 1).unwrap() is ScoreContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_score(execution, 1).unwrap() is ScoreStopped(_))
  assert_eq(cleanup_score(execution), Ok(true))
}

///|
test "score connects cosine and negative-L2 runtime metrics" {
  for
    (metric, first, last) in [
      ("cosine", 1.0, 0.0),
      ("l2", 0.0, -1.4142135623730951),
    ] {
    let producer = producer_owner()
    let source = scored_source(producer, Ref(true))
    let owner = score_owner(producer, metric~)
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_score(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      4096L,
      fn() { true },
    ).unwrap()
    let completed = finish_score_execution(execution)
    let material = @records.completed_storage(completed).unwrap()
    guard scored_field(material, 0, "score").value is @value.Number(best) &&
      scored_field(material, 2, "score").value is @value.Number(worst) else {
      fail("metric score output")
    }
    assert_eq(best, first)
    assert_eq(worst, last)
    assert_eq(cleanup_score(execution), Ok(true))
  }
}

///|
test "score validates a finite f32 query even for empty input" {
  let producer = producer_owner()
  let source = empty_scored_source(producer)
  let owner = score_owner(producer, query="[3.5e38,0]")
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_score(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_score(execution, 1).unwrap()
    is ScoreFailed(ScoreNumeric(@numeric.NonFinite), progress=0L, work=1L),
  )
  assert_eq(cleanup_score(execution), Ok(true))
}

///|
test "score admits complete ordering workspace before execution" {
  let producer = producer_owner()
  let source = scored_source(producer, Ref(true))
  let owner = score_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_score(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(workspace=29),
      4096L,
      fn() { true },
    )
    is Err(ScoreWorkspaceLimit),
  )
}

///|
test "score completes at its exact ordering workspace boundary" {
  let producer = producer_owner()
  let source = scored_source(producer, Ref(true))
  let owner = score_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Three score slots and five retained slots per record, plus two query
  // components, three output fields, and one identity slot total 30.
  let execution = start_score(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(workspace=30),
    4096L,
    fn() { true },
  ).unwrap()
  let completed = finish_score_execution(execution)
  guard @records.completed_storage(completed) is Some(material) else {
    fail("score output missing")
  }
  assert_eq(@storage.record_count(material), 3)
  assert_eq(cleanup_score(execution), Ok(true))
}

///|
test "score observes cancellation between bounded work units" {
  let producer = producer_owner()
  let source = scored_source(producer, Ref(true))
  let owner = score_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let execution = start_score(
    control,
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_score(execution, 1).unwrap() is ScoreContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_score(execution, 1).unwrap()
    is ScoreStopped(@bounded.Cancelled, progress=0L, work=1L),
  )
  assert_true(score_stopped(execution))
  assert_eq(cleanup_score(execution), Ok(true))
}
