///|
fn dedupe_owner(
  producer : @lower.BoundPrepared,
  by : String,
  order_by : String,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"dedupe_events\":{\"by\":" +
        by +
        ",\"order_by\":" +
        order_by +
        "}}]",
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
fn dedupe_source(
  producer : @lower.BoundPrepared,
  rows : Array[(Double, Double, String)],
) -> @records.Completed {
  let output = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  for (identity, occurred_at, payload) in rows {
    @records.append_record(output, [
      (@schema.Unqualified("event_id"), number(identity)),
      (@schema.Unqualified("occurred_at"), number(occurred_at)),
      (@schema.Unqualified("payload"), text(payload)),
    ]).unwrap()
  }
  @records.finish_output(output).unwrap()
}

///|
fn finish_dedupe(execution : DedupeExecution) -> @records.Completed {
  while true {
    match advance_dedupe(execution, 1).unwrap() {
      DedupeContinue(..) => ()
      DedupeComplete(output, ..) => return output
      DedupeFailed(_, ..) => abort("dedupe failed")
      DedupeStopped(_, ..) => abort("dedupe stopped")
    }
  }
  abort("unreachable")
}

///|
test "event dedupe view observes cancellation without releasing its producer" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [(1.0, 2.0, "a")])
  let material = @records.completed_material(source).unwrap()
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let view = @lifecycle.material_prepare_view(material, owner, 0, producer).unwrap()
  let control = @bounded.control()
  let execution = start_dedupe_view(
    control,
    sequence(owner),
    0,
    view,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_dedupe(execution, 1).unwrap() is DedupeContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_dedupe(execution, 1).unwrap() is DedupeStopped(_))
  assert_eq(cleanup_dedupe(execution), Ok(true))
  assert_true(@lifecycle.material_available(material))
  assert_true(@lifecycle.reclaim_material(material))
}

///|
test "event dedupe view retains exact work and workspace boundaries" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [(1.0, 2.0, "a")])
  let material = @records.completed_material(source).unwrap()
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  for
    (work, workspace, accepted) in [
      (59, 71, true),
      (58, 71, false),
      (59, 70, false),
    ] {
    let view = @lifecycle.material_prepare_view(material, owner, 0, producer).unwrap()
    let execution = start_dedupe_view(
      @bounded.control(),
      sequence(owner),
      0,
      view,
      limits(workspace~),
      4096L,
      fn() { true },
      control_work_limit=Some(work),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<70 {
      if !terminal {
        match advance_dedupe(execution, 1).unwrap() {
          DedupeContinue(..) => ()
          DedupeComplete(output, ..) => {
            assert_true(accepted)
            assert_true(@records.discard_completed(output))
            terminal = true
          }
          DedupeFailed(DedupeControlWorkLimit, ..) => {
            assert_false(accepted)
            assert_eq(work, 58)
            terminal = true
          }
          DedupeFailed(DedupeWorkspaceLimit, ..) => {
            assert_false(accepted)
            assert_eq(workspace, 70)
            terminal = true
          }
          _ => fail("unexpected dedupe view result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(cleanup_dedupe(execution), Ok(true))
    assert_true(@lifecycle.material_available(material))
  }
  assert_true(@lifecycle.reclaim_material(material))
}

///|
test "event dedupe selects authored order and emits canonical groups" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [
    (1.0, 20.0, "a"),
    (2.0, 10.0, "a"),
    (3.0, 30.0, "b"),
    (4.0, 5.0, "b"),
  ])
  let owner = dedupe_owner(
    producer, "[\"payload\",\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_dedupe(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(dedupe_max_noninterruptible_value_nodes(execution), 1)
  assert_eq(dedupe_max_noninterruptible_value_bytes(execution), 1000)
  let completed = finish_dedupe(execution)
  assert_true(dedupe_stopped(execution))
  assert_true(dedupe_cleanup_pending(execution))
  assert_eq(cleanup_dedupe(execution), Ok(true))
  let output = @records.completed_storage(completed).unwrap()
  assert_eq(@storage.record_count(output), 2)
  guard field(output, 0, "event_id").value is @value.Number(first) &&
    field(output, 1, "event_id").value is @value.Number(second) else {
    fail("dedupe identity")
  }
  assert_eq(first, 2.0)
  assert_eq(second, 4.0)
}

///|
test "event dedupe orders text keys by typed UTF-16 order" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [
    (1.0, 1.0, "a"),
    (2.0, 1.0, "\u{e000}"),
    (3.0, 1.0, "A"),
    (4.0, 1.0, "\u{10000}"),
  ])
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_dedupe(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  let completed = finish_dedupe(execution)
  let output = @records.completed_storage(completed).unwrap()
  assert_eq(@storage.record_count(output), 4)
  for (record, expected) in [(0, 3.0), (1, 1.0), (2, 4.0), (3, 2.0)] {
    guard field(output, record, "event_id").value is @value.Number(actual) else {
      fail("event identity")
    }
    assert_eq(actual, expected)
  }
  assert_eq(cleanup_dedupe(execution), Ok(true))
  assert_true(@records.discard_completed(completed))
  assert_true(@records.discard_completed(source))
}

///|
test "event dedupe supports global selection and empty input" {
  let producer = producer_owner(false)
  let owner = dedupe_owner(
    producer, "[]", "[{\"field\":\"occurred_at\",\"dir\":\"desc\",\"nulls\":\"last\"}]",
  )
  for
    (rows, expected) in [
      ([(1.0, 20.0, "a"), (2.0, 10.0, "b")], Some(1.0)),
      ([], None),
    ] {
    let source = dedupe_source(producer, rows)
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let completed = finish_dedupe(
      start_dedupe(
        @bounded.control(),
        sequence(owner),
        0,
        input,
        limits(),
        4096L,
        fn() { true },
      ).unwrap(),
    )
    let output = @records.completed_storage(completed).unwrap()
    match expected {
      Some(value) => {
        assert_eq(@storage.record_count(output), 1)
        guard field(output, 0, "event_id").value is @value.Number(actual) else {
          fail("global identity")
        }
        assert_eq(actual, value)
      }
      None => assert_eq(@storage.record_count(output), 0)
    }
  }
}

///|
test "event dedupe fails an unresolved top tie before publication" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [(1.0, 10.0, "a"), (2.0, 10.0, "a")])
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_dedupe(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    4096L,
    fn() { true },
  ).unwrap()
  while true {
    match advance_dedupe(execution, 1).unwrap() {
      DedupeContinue(..) => ()
      DedupeFailed(DedupeTopTie(0, 1), progress=0L, ..) => break
      DedupeFailed(_, ..) => abort("unexpected dedupe failure")
      DedupeComplete(_, ..) => fail("tie output escaped")
      DedupeStopped(_, ..) => fail("tie stopped")
    }
  }
  assert_eq(cleanup_dedupe(execution), Ok(true))
}

///|
test "event dedupe admits scratch before allocation and observes cancellation" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [
    (1.0, 20.0, "a"),
    (2.0, 10.0, "a"),
    (3.0, 30.0, "b"),
    (4.0, 5.0, "b"),
  ])
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let too_small = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_dedupe(
      @bounded.control(),
      sequence(owner),
      0,
      too_small,
      limits(workspace=20),
      4096L,
      fn() { true },
    )
    is Err(DedupeWorkspaceLimit),
  )

  let control = @bounded.control()
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_dedupe(
    control,
    sequence(owner),
    0,
    input,
    limits(workspace=21),
    4096L,
    fn() { true },
  ).unwrap()
  assert_true(advance_dedupe(execution, 1).unwrap() is DedupeContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_dedupe(execution, 1).unwrap()
    is DedupeStopped(@bounded.Cancelled, progress=0L, work=1L),
  )
  assert_eq(cleanup_dedupe(execution), Ok(true))
}

///|
test "event dedupe initializes predicate cells within the resume quantum" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [
    (1.0, 1.0, "a"),
    (2.0, 2.0, "b"),
    (3.0, 3.0, "c"),
    (4.0, 4.0, "d"),
    (5.0, 5.0, "e"),
    (6.0, 6.0, "f"),
    (7.0, 7.0, "g"),
    (8.0, 8.0, "h"),
  ])
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_dedupe(
      @bounded.control(),
      sequence(owner),
      0,
      read,
      limits(workspace=41, max_input_records=7),
      4096L,
      fn() { true },
    )
    is Err(DedupeInputLimit),
  )
  let control = @bounded.control()
  let execution = start_dedupe(
    control,
    sequence(owner),
    0,
    read,
    limits(workspace=41),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(dedupe_initialization_progress(execution), (0, 0))
  assert_true(
    advance_dedupe(execution, 1).unwrap()
    is DedupeContinue(progress=0L, work=1L),
  )
  assert_eq(dedupe_initialization_progress(execution), (1, 0))
  for step in 2..<17 {
    assert_true(
      advance_dedupe(execution, 1).unwrap() is DedupeContinue(progress=0L, ..),
    )
    assert_eq(dedupe_initialization_progress(execution), (step, 0))
  }
  assert_true(advance_dedupe(execution, 1).unwrap() is DedupeContinue(_))
  assert_eq(dedupe_initialization_progress(execution), (16, 0))
  assert_true(advance_dedupe(execution, 1).unwrap() is DedupeContinue(_))
  assert_eq(dedupe_initialization_progress(execution), (16, 1))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_dedupe(execution, 1).unwrap()
    is DedupeStopped(@bounded.Cancelled, progress=0L, work=18L),
  )
  assert_eq(cleanup_dedupe(execution), Ok(true))
  assert_true(@records.producer_read_available(read))

  let stopped_control = @bounded.control()
  assert_true(@bounded.request_cancel(stopped_control))
  let stopped_read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let stopped = start_dedupe(
    stopped_control,
    sequence(owner),
    0,
    stopped_read,
    limits(workspace=41),
    4096L,
    fn() { true },
  ).unwrap()
  assert_eq(dedupe_initialization_progress(stopped), (0, 0))
  assert_true(
    advance_dedupe(stopped, 1).unwrap()
    is DedupeStopped(@bounded.Cancelled, progress=0L, work=0L),
  )
  assert_eq(dedupe_initialization_progress(stopped), (0, 0))
  assert_eq(cleanup_dedupe(stopped), Ok(true))
  assert_true(@records.discard_completed(source))
}

///|
test "event dedupe admits exact and one-short cumulative control work" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [(1.0, 2.0, "a")])
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // One record with two terms and three fields takes five initialization,
  // fourteen loading, one sort, three grouping, and eight output/final steps.
  // Stepped append adds 6*3+2*1+8=28 polls: 31+28=59.
  for (budget, accepted) in [(59, true), (58, false)] {
    let execution = start_dedupe(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      4096L,
      fn() { true },
      control_work_limit=Some(budget),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<70 {
      if terminal {
        break
      }
      match advance_dedupe(execution, 1).unwrap() {
        DedupeContinue(work~, ..) => assert_true(work <= budget.to_int64())
        DedupeComplete(output, progress~, work~) => {
          assert_true(accepted)
          assert_eq((progress, work), (1L, 59L))
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        DedupeFailed(DedupeControlWorkLimit, progress~, work~) => {
          assert_false(accepted)
          assert_eq((progress, work), (1L, 58L))
          assert_true(dedupe_cleanup_pending(execution))
          terminal = true
        }
        _ => fail("unexpected dedupe control-work outcome")
      }
    }
    assert_true(terminal)
    assert_eq(cleanup_dedupe(execution), Ok(true))
    assert_true(@records.producer_read_available(input))
  }
  assert_true(
    start_dedupe(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      4096L,
      fn() { true },
      control_work_limit=Some(0),
    )
    is Err(DedupeControlWorkLimit),
  )
  assert_true(@records.discard_completed(source))
}

///|
test "event dedupe admits exact and one-short output workspace" {
  let producer = producer_owner(false)
  let source = dedupe_source(producer, [(1.0, 2.0, "a")])
  let owner = dedupe_owner(
    producer, "[\"payload\"]", "[{\"field\":\"occurred_at\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
  )
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Five sorting slots + three borrowed fields + append handle = nine.
  // Cursor 56, next row five, caller nine, name position one: peak 71.
  for (workspace, accepted) in [(71, true), (70, false)] {
    let execution = start_dedupe(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(workspace~),
      4096L,
      fn() { true },
    ).unwrap()
    let mut terminal = false
    for _ in 0..<70 {
      if terminal {
        break
      }
      match advance_dedupe(execution, 1).unwrap() {
        DedupeContinue(..) => ()
        DedupeComplete(output, ..) => {
          assert_true(accepted)
          assert_true(@records.discard_completed(output))
          terminal = true
        }
        DedupeFailed(DedupeWorkspaceLimit, ..) => {
          assert_false(accepted)
          assert_true(dedupe_cleanup_pending(execution))
          terminal = true
        }
        _ => fail("unexpected dedupe workspace outcome")
      }
    }
    assert_true(terminal)
    assert_eq(cleanup_dedupe(execution), Ok(true))
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}
