///|
fn pool_relation_carrier() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("id"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("group"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("embedding"),
          Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=3,
      max_name_bytes=16,
    ).unwrap(),
  )
}

///|
fn pool_producer_owner() -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}]",
      ),
      [("rows", pool_relation_carrier())],
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
}

///|
fn pool_owner(
  producer : @lower.BoundPrepared,
  reduction? : String = "sum",
  output_id? : String = "",
) -> @lower.BoundPrepared {
  let output = if output_id == "" {
    ""
  } else {
    ",\"output_id\":\"" + output_id + "\""
  }
  bind(
    @pipeline.check_with_evidence(
      cursor(
        "[{\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"" +
        reduction +
        "\"" +
        output +
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
fn second_input_pool_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"pool_vectors\":{\"by\":[\"group\"],\"method\":\"sum\"}}]"),
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
fn pool_source(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    limits(),
    8192L,
    fn() { live.val },
  ).unwrap()
  let rows = [
    (3.0, 2.0, "[4,4]"),
    (1.0, 1.0, "[1,2]"),
    (4.0, 2.0, "[2,6]"),
    (2.0, 1.0, "[3,4]"),
  ]
  for (id, group, components) in rows {
    @records.append_record(output, [
      (@schema.Unqualified("id"), number(id)),
      (@schema.Unqualified("group"), number(group)),
      (@schema.Unqualified("embedding"), vector(components)),
    ]).unwrap()
  }
  @records.finish_output(output).unwrap()
}

///|
fn empty_pool_source(owner : @lower.BoundPrepared) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    limits(),
    8192L,
    fn() { true },
  ).unwrap()
  @records.finish_output(output).unwrap()
}

///|
fn single_pool_source(owner : @lower.BoundPrepared) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    limits(),
    8192L,
    fn() { true },
  ).unwrap()
  @records.append_record(output, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("group"), number(1.0)),
    (@schema.Unqualified("embedding"), vector("[1,2]")),
  ]).unwrap()
  @records.finish_output(output).unwrap()
}

///|
fn finish_pool_execution(execution : PoolExecution) -> @records.Completed {
  while true {
    match advance_pool(execution, 1).unwrap() {
      PoolContinue(..) => ()
      PoolComplete(output, ..) => return output
      PoolFailed(_, ..) => abort("pool failed")
      PoolStopped(_, ..) => abort("pool stopped")
    }
  }
  abort("unreachable")
}

///|
fn pool_field(
  storage : @storage.Storage,
  record : Int,
  expected : String,
) -> @value.CheckedValue {
  let count = @storage.record_field_count(storage, record).unwrap()
  for field in 0..<count {
    guard @storage.record_field_at(storage, record, field)
      is Some((name, value)) else {
      abort("pool field")
    }
    if @schema.reference_name(name) == expected {
      return value
    }
  }
  abort("missing pool field")
}

///|
test "pool enforces cumulative empty-input control work" {
  let producer = pool_producer_owner()
  let source = empty_pool_source(producer)
  let owner = pool_owner(producer)
  let zero_input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_pool(
      @bounded.control(),
      sequence(owner),
      0,
      zero_input,
      limits(work=0),
      8192L,
      fn() { true },
    )
    is Err(PoolWorkLimit),
  )
  // An empty input still needs one terminal group-boundary check.
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_pool_with_control_work_limit(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    8192L,
    fn() { true },
    1,
  ).unwrap()
  assert_true(advance_pool(execution, 1).unwrap() is PoolContinue(work=1L, ..))
  guard advance_pool(execution, 1).unwrap() is PoolComplete(output, work=1L, ..) &&
    @records.completed_storage(output) is Some(material) else {
    fail("empty pool should finish at one work unit")
  }
  assert_eq(@storage.record_count(material), 0)
  assert_eq(cleanup_pool(execution), Ok(true))
  assert_true(@records.producer_read_available(input))
}

///|
test "pool enforces cumulative one-record control work" {
  let producer = pool_producer_owner()
  let source = single_pool_source(producer)
  let owner = pool_owner(producer)
  // Admission and field scan: 17; scratch: 1; group boundary: 1;
  // two component folds: 6; three output fields: 3; commit: 1;
  // terminal group boundary: 1. Total: 30 work units.
  for (ceiling, accepted) in [(30, true), (29, false)] {
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_pool_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      8192L,
      fn() { true },
      ceiling,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<36 {
      if !terminal {
        match advance_pool(execution, 1).unwrap() {
          PoolContinue(work=next, ..) => {
            assert_true(next >= charged && next - charged <= 1L)
            charged = next
          }
          PoolComplete(output, work=next, ..) => {
            assert_true(accepted)
            assert_eq(next, 30L)
            guard @records.completed_storage(output) is Some(material) else {
              fail("pooled output missing")
            }
            assert_eq(@storage.record_count(material), 1)
            charged = next
            terminal = true
          }
          PoolFailed(PoolWorkLimit, work=next, ..) => {
            assert_false(accepted)
            assert_eq(next, 29L)
            assert_true(pool_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("pool work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_eq(cleanup_pool(execution), Ok(true))
    assert_true(@records.producer_read_available(input))
  }
}

///|
test "pool orders groups and folds members by semantic identity" {
  let producer = pool_producer_owner()
  let source_live = Ref(true)
  let source = pool_source(producer, source_live)
  let owner = pool_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_pool(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    8192L,
    fn() { true },
  ).unwrap()
  assert_eq(pool_max_noninterruptible_value_nodes(execution), 100)
  assert_eq(pool_max_noninterruptible_value_bytes(execution), 1000)
  let completed = finish_pool_execution(execution)
  assert_true(pool_stopped(execution))
  assert_true(pool_cleanup_pending(execution))
  assert_eq(cleanup_pool(execution), Ok(true))
  source_live.val = false
  assert_true(@records.completed_available(completed))
  let storage = @records.completed_storage(completed).unwrap()
  assert_eq(@storage.record_count(storage), 2)
  for
    (record, expected_group, left, right) in [
      (0, 1.0, 4.0, 6.0),
      (1, 2.0, 6.0, 10.0),
    ] {
    guard pool_field(storage, record, "group").value is @value.Number(group) &&
      pool_field(storage, record, "member_count").value is @value.Number(count) &&
      pool_field(storage, record, "embedding").value
      is @value.Vector(components) else {
      fail("pooled output")
    }
    assert_eq(group, expected_group)
    assert_eq(count, 2.0)
    assert_eq(@value.element_at(components, 0), Some(left))
    assert_eq(@value.element_at(components, 1), Some(right))
  }
  let downstream = pool_owner(owner)
  let first = @records.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  let second = @records.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  assert_false(@records.producer_read_same(first, second))
  assert_eq(
    @storage.record_count(@records.producer_read_storage(first).unwrap()),
    2,
  )
  assert_eq(
    @storage.record_count(@records.producer_read_storage(second).unwrap()),
    2,
  )
}

///|
test "pool executes mean, max, and a renamed output identity" {
  for
    (reduction_name, expected) in [
      ("mean", [(2.0, 3.0), (3.0, 5.0)]),
      ("max", [(3.0, 4.0), (4.0, 6.0)]),
    ] {
    let producer = pool_producer_owner()
    let source = pool_source(producer, Ref(true))
    let owner = pool_owner(
      producer,
      reduction=reduction_name,
      output_id="pool_id",
    )
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_pool(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      8192L,
      fn() { true },
    ).unwrap()
    let storage = @records.completed_storage(finish_pool_execution(execution)).unwrap()
    assert_eq(@storage.record_count(storage), 2)
    for record in 0..<2 {
      guard pool_field(storage, record, "group").value is @value.Number(group) &&
        pool_field(storage, record, "pool_id").value is @value.Number(identity) &&
        pool_field(storage, record, "embedding").value
        is @value.Vector(components) else {
        fail("pooled reduction output")
      }
      assert_eq(group, (record + 1).to_double())
      assert_eq(identity, group)
      assert_eq(@value.element_at(components, 0), Some(expected[record].0))
      assert_eq(@value.element_at(components, 1), Some(expected[record].1))
    }
    assert_eq(cleanup_pool(execution), Ok(true))
  }
}

///|
test "pool admits structural workspace before allocating sort state" {
  let producer = pool_producer_owner()
  let source = pool_source(producer, Ref(true))
  let owner = pool_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let required = pool_workspace(4, 2, 1, 1, 3).unwrap()
  assert_true(
    start_pool(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(workspace=required - 1),
      8192L,
      fn() { true },
    )
    is Err(PoolWorkspaceLimit),
  )
  let control = @bounded.control()
  let admitted = start_pool(
    control,
    sequence(owner),
    0,
    input,
    limits(workspace=required),
    8192L,
    fn() { true },
  ).unwrap()
  assert_true(advance_pool(admitted, 1).unwrap() is PoolContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_pool(admitted, 1).unwrap() is PoolStopped(_))
  assert_eq(cleanup_pool(admitted), Ok(true))
}

///|
test "pool completes at its exact structural workspace boundary" {
  let producer = pool_producer_owner()
  let source = pool_source(producer, Ref(true))
  let owner = pool_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let required = pool_workspace(4, 2, 1, 1, 3).unwrap()
  let execution = start_pool(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(workspace=required),
    8192L,
    fn() { true },
  ).unwrap()
  let completed = finish_pool_execution(execution)
  guard @records.completed_storage(completed) is Some(material) else {
    fail("pooled output missing")
  }
  assert_eq(@storage.record_count(material), 2)
  assert_eq(cleanup_pool(execution), Ok(true))
}

///|
test "pool admits only the exact external operation input" {
  let first_owner = pool_producer_owner()
  let second_owner = pool_producer_owner()
  let first = pool_source(first_owner, Ref(true))
  let second = pool_source(second_owner, Ref(true))
  let owner = second_input_pool_owner(first_owner, second_owner)
  let wrong = @records.prepare_producer_read(owner, 0, first_owner, first).unwrap()
  assert_true(
    start_pool(@bounded.control(), sequence(owner), 0, wrong, limits(), 8192L, fn() {
      true
    })
    is Err(InvalidPoolKernel),
  )
  let exact = @records.prepare_producer_read(owner, 1, second_owner, second).unwrap()
  let control = @bounded.control()
  let execution = start_pool(
    control,
    sequence(owner),
    0,
    exact,
    limits(),
    8192L,
    fn() { true },
  ).unwrap()
  assert_true(advance_pool(execution, 1).unwrap() is PoolContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_pool(execution, 1).unwrap() is PoolStopped(_))
  assert_eq(cleanup_pool(execution), Ok(true))
}

///|
test "pool observes cancellation and reclaims partial output" {
  let producer = pool_producer_owner()
  let source = pool_source(producer, Ref(true))
  let owner = pool_owner(producer, reduction="mean")
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let execution = start_pool(
    control,
    sequence(owner),
    0,
    input,
    limits(),
    8192L,
    fn() { true },
  ).unwrap()
  assert_true(advance_pool(execution, 1).unwrap() is PoolContinue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_pool(execution, 1).unwrap() is PoolStopped(_))
  assert_true(pool_stopped(execution))
  assert_true(pool_cleanup_pending(execution))
  assert_eq(cleanup_pool(execution), Ok(true))
  assert_false(pool_cleanup_pending(execution))
}
