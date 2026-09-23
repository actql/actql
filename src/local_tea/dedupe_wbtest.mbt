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
      limits(workspace=19),
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
    limits(workspace=20),
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
