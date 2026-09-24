///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="local-veca-normalize.aql",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn vector_carrier() -> @carrier.Carrier {
  let rows = @carrier.rows(
    [
      (
        @schema.Unqualified("id"),
        Some(@contract.primitive(@contract.NumberType, nullable=false)),
      ),
      (
        @schema.Unqualified("embedding"),
        Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=2,
    max_name_bytes=11,
  ).unwrap()
  @carrier.vectors(
    rows,
    ids=[@schema.Unqualified("id")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
}

///|
fn relation_carrier() -> @carrier.Carrier {
  guard vector_carrier() is @carrier.VectorValue(vectors) else {
    abort("vectors")
  }
  @carrier.relation(@carrier.vector_records(vectors))
}

///|
fn bind(checked : @pipeline.CheckedPipeline) -> @lower.BoundPrepared {
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn producer_owner() -> @lower.BoundPrepared {
  bind(
    @pipeline.check_carriers(
      cursor(
        "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}]",
      ),
      [("rows", relation_carrier())],
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
fn consumer_owner(producer : @lower.BoundPrepared) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"normalize_vectors\":true}]"),
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
fn second_input_normalize_owner(
  first : @lower.BoundPrepared,
  second : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor("[{\"normalize_vectors\":true}]"),
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
fn sequence(owner : @lower.BoundPrepared) -> @lower.PreparedSequence {
  @lower.prepare_sequence(owner, {
    max_steps: 10,
    max_rows: 100,
    max_cells: 1000,
    max_bindings: 100,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }).unwrap()
}

///|
fn limits(workspace? : Int = 1000, work? : Int = 1000) -> @storage.Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: work,
    max_workspace_slots: workspace,
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn vector(text : String) -> @value.CheckedValue {
  @value.admit(
    @contract.vector_contract(2.0, nullable=false).unwrap(),
    cursor(text),
    { max_nodes: 3, max_depth: 2, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn source_vectors(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
  components : String,
) -> @records.Completed {
  let output = @records.prepare_output(
    owner,
    @pipeline.Step(0),
    limits(),
    2048L,
    fn() { live.val },
  ).unwrap()
  @records.append_record(output, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("embedding"), vector(components)),
  ]).unwrap()
  @records.finish_output(output).unwrap()
}

///|
fn finish(execution : NormalizeExecution) -> @records.Completed {
  while true {
    match advance_normalize(execution, 1).unwrap() {
      Continue(..) => ()
      Complete(output, ..) => return output
      Failed(_, ..) => abort("normalize failed")
      Stopped(_, ..) => abort("normalize stopped")
    }
  }
  abort("unreachable")
}

///|
test "normalize computes f32 output and feeds two exact consumers" {
  let producer = producer_owner()
  let source_live = Ref(true)
  let source = source_vectors(producer, source_live, "[3,4]")
  let owner = consumer_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let output_live = Ref(true)
  let execution = start_normalize(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    2048L,
    fn() { output_live.val },
  ).unwrap()
  assert_eq(normalize_max_noninterruptible_value_nodes(execution), 100)
  let completed = finish(execution)
  assert_true(normalize_stopped(execution))
  assert_true(normalize_cleanup_pending(execution))
  assert_eq(cleanup_normalize(execution), Ok(true))
  source_live.val = false
  assert_true(@records.completed_available(completed))
  let material = @records.completed_storage(completed).unwrap()
  guard @storage.record_field_at(material, 0, 1)
    is Some((_, { value: @value.Vector(values), .. })) else {
    fail("normalized vector")
  }
  assert_eq(@value.element_count(values), 2)
  assert_eq(@value.element_at(values, 0), Some(0.6000000238418579))
  assert_eq(@value.element_at(values, 1), Some(0.800000011920929))

  let downstream = consumer_owner(owner)
  let first = @records.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  let second = @records.prepare_producer_read(downstream, 0, owner, completed).unwrap()
  assert_false(@records.producer_read_same(first, second))
  assert_eq(
    @storage.record_count(@records.producer_read_storage(first).unwrap()),
    1,
  )
  assert_eq(
    @storage.record_count(@records.producer_read_storage(second).unwrap()),
    1,
  )
}

///|
test "vector normalize admits only the exact external operation input" {
  let first_owner = producer_owner()
  let second_owner = producer_owner()
  let first = source_vectors(first_owner, Ref(true), "[1,0]")
  let second = source_vectors(second_owner, Ref(true), "[0,1]")
  let owner = second_input_normalize_owner(first_owner, second_owner)
  let wrong = @records.prepare_producer_read(owner, 0, first_owner, first).unwrap()
  assert_true(
    start_normalize(
      @bounded.control(),
      sequence(owner),
      0,
      wrong,
      limits(),
      2048L,
      fn() { true },
    )
    is Err(InvalidKernel),
  )
  let exact = @records.prepare_producer_read(owner, 1, second_owner, second).unwrap()
  let control = @bounded.control()
  let execution = start_normalize(
    control,
    sequence(owner),
    0,
    exact,
    limits(),
    2048L,
    fn() { true },
  ).unwrap()
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(advance_normalize(execution, 1).unwrap() is Stopped(_))
  assert_eq(cleanup_normalize(execution), Ok(true))
}

///|
test "normalize rejects zero vectors without publishing partial output" {
  let producer = producer_owner()
  let source = source_vectors(producer, Ref(true), "[0,0]")
  let owner = consumer_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_normalize(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(),
    2048L,
    fn() { true },
  ).unwrap()
  while true {
    match advance_normalize(execution, 1).unwrap() {
      Continue(..) => continue
      Failed(Numeric(@numeric.ZeroVector), progress=0L, ..) => break
      _ => fail("zero vector failure")
    }
  }
  assert_true(normalize_stopped(execution))
  assert_true(normalize_cleanup_pending(execution))
  assert_eq(cleanup_normalize(execution), Ok(true))
}

///|
test "normalize admits workspace before building record temporaries" {
  let producer = producer_owner()
  let source = source_vectors(producer, Ref(true), "[3,4]")
  let owner = consumer_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let execution = start_normalize(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(workspace=7),
    2048L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_normalize(execution, 1).unwrap()
    is Failed(WorkspaceLimit, progress=0L, work=0L),
  )
  assert_eq(cleanup_normalize(execution), Ok(true))
}

///|
test "normalize accepts its exact temporary workspace" {
  let producer = producer_owner()
  let source = source_vectors(producer, Ref(true), "[3,4]")
  let owner = consumer_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Two field tuples, two transient slots, and two vector components overlap.
  let execution = start_normalize(
    @bounded.control(),
    sequence(owner),
    0,
    input,
    limits(workspace=8),
    2048L,
    fn() { true },
  ).unwrap()
  let completed = finish(execution)
  assert_true(@records.completed_available(completed))
  assert_eq(cleanup_normalize(execution), Ok(true))
}

///|
test "normalize observes cancellation between component work units" {
  let producer = producer_owner()
  let source = source_vectors(producer, Ref(true), "[3,4]")
  let owner = consumer_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let execution = start_normalize(
    control,
    sequence(owner),
    0,
    input,
    limits(),
    2048L,
    fn() { true },
  ).unwrap()
  assert_true(advance_normalize(execution, 1).unwrap() is Continue(_))
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_normalize(execution, 1).unwrap()
    is Stopped(@bounded.Cancelled, progress=0L, work=1L),
  )
  assert_true(normalize_stopped(execution))
  assert_eq(cleanup_normalize(execution), Ok(true))
}

///|
test "normalize enforces cumulative control work across resumes" {
  let producer = producer_owner()
  let source = source_vectors(producer, Ref(true), "[3,4]")
  let owner = consumer_owner(producer)
  let zero_input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  assert_true(
    start_normalize(
      @bounded.control(),
      sequence(owner),
      0,
      zero_input,
      limits(work=0),
      2048L,
      fn() { true },
    )
    is Err(WorkLimit),
  )
  // One begin, two field reads, two norm folds, one divisor, two component
  // emissions, one record commit, and one finish are ten control units.
  for (ceiling, accepted) in [(10, true), (9, false)] {
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_normalize_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(),
      2048L,
      fn() { true },
      ceiling,
    ).unwrap()
    let mut terminal = false
    let mut charged = 0L
    for _ in 0..<16 {
      if !terminal {
        match advance_normalize(execution, 1).unwrap() {
          Continue(work=next, ..) => {
            assert_true(next >= charged && next - charged <= 1L)
            charged = next
          }
          Complete(output, work=next, ..) => {
            assert_true(accepted)
            assert_eq(next - charged, 1L)
            assert_true(@records.completed_available(output))
            charged = next
            terminal = true
          }
          Failed(WorkLimit, work=next, ..) => {
            assert_false(accepted)
            assert_eq(next, charged)
            assert_true(normalize_cleanup_pending(execution))
            terminal = true
          }
          _ => fail("normalize control-work boundary had another result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(charged, ceiling.to_int64())
    assert_eq(cleanup_normalize(execution), Ok(true))
    assert_true(@records.producer_read_available(input))
  }
}
