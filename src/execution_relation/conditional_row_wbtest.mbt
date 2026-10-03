///|
fn conditional_row_test_schema() -> @schema.ConditionalSchema {
  @schema.from_conditional_fields(
    [
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=true),
        @schema.FieldPresence::Conditional,
      ),
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        @schema.FieldPresence::Required,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
}

///|
fn conditional_row_test_wire() -> RetainedRowDecodeLimits {
  { max_bytes: 128, max_nodes: 16, max_depth: 4, max_text_bytes: 32, }
}

///|
fn conditional_row_test_values() -> ValueLimits {
  { max_nodes: 5, max_text_bytes: 3, max_depth: 2, max_work: 8, }
}

///|
test "conditional rows roundtrip absent and explicit null separately" {
  let schema = conditional_row_test_schema()
  let examples = ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"]
  for index in 0..<examples.length() {
    let row = decode_conditional_row_wire(
      schema,
      examples[index],
      conditional_row_test_wire(),
      conditional_row_test_values(),
    ).unwrap()
    let writer = @encode.writer(128, 16, 4)
    emit_conditional_row(row, writer)
    assert_eq(@encode.finish(writer), examples[index])
    assert_true(conditional_row_cell(row, 0) is Some(Some(_)))
    assert_true(
      conditional_required_cell(row, 0)
      is Some({ value: @admitted.Number(_), .. }),
    )
    assert_true(conditional_required_cell(row, 1) is None)
    if index == 2 {
      assert_true(conditional_row_cell(row, 1) is Some(None))
    } else if index == 1 {
      assert_true(
        conditional_row_cell(row, 1)
        is Some(Some({ value: @admitted.Null, .. })),
      )
    }
  }
}

///|
test "conditional rows reject required gaps, wrong types and unknown fields" {
  let schema = conditional_row_test_schema()
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"p\":7}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(Row(MissingRequired(0))),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":\"wrong\"}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(Value(0, _)),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"other\":7}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(Decode(_)),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"id\":2}",
      conditional_row_test_wire(),
      conditional_row_test_values(),
    )
    is Err(InvalidJson),
  )
}

///|
test "conditional presence charges absent slots and supports cancellation" {
  let schema = conditional_row_test_schema()
  let exact = decode_conditional_row_wire(
    schema,
    "{\"id\":1,\"p\":7}",
    conditional_row_test_wire(),
    conditional_row_test_values(),
  ).unwrap()
  assert_eq(conditional_row_usage(exact).nodes, 5)
  assert_eq(conditional_row_usage(exact).text_bytes, 3)
  assert_eq(conditional_row_usage(exact).work, 8)
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"p\":7}",
      conditional_row_test_wire(),
      { ..conditional_row_test_values(), max_work: 7, },
    )
    is Err(Row(Limit)),
  )
  assert_true(
    decode_conditional_row_wire(
      schema,
      "{\"id\":1,\"p\":7}",
      conditional_row_test_wire(),
      { ..conditional_row_test_values(), max_nodes: 4, },
    )
    is Err(Row(Limit)),
  )
  let builder = prepare_conditional_row(schema, conditional_row_test_values()).unwrap()
  let id_contract = @schema.presence_field_contract(
    @schema.presence_field_at(schema, 0).unwrap(),
  )
  let id = @admitted.checked_number_value(1.0, id_contract).unwrap()
  append_conditional_cell(builder, Some(id)).unwrap()
  assert_true(cancel_conditional_row(builder))
  assert_true(finish_conditional_row(builder) is Err(Closed))

  let invalid = prepare_conditional_row(schema, conditional_row_test_values()).unwrap()
  let wrong_contract = @contract.primitive(NumberType, nullable=false)
  let wrong = @admitted.checked_number_value(1.0, wrong_contract).unwrap()
  assert_true(
    append_conditional_cell(invalid, Some(wrong)) is Err(ForeignValue(0)),
  )
  assert_true(finish_conditional_row(invalid) is Err(Closed))
}

///|
test "required conditional columns enter the existing dense output owner" {
  let owner = capture_fixture()
  let target = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(1),
  ).unwrap()
  let n = @schema.lookup(target, Unqualified("n")).unwrap()
  let s = @schema.lookup(target, Unqualified("s")).unwrap()
  let conditional = @schema.from_conditional_fields(
    [
      (Unqualified("n"), n, @schema.Required),
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=true),
        @schema.Conditional,
      ),
      (Unqualified("s"), s, @schema.Required),
    ],
    max_fields=3,
    max_name_bytes=3,
  ).unwrap()
  let row = output_fixture_row(owner, 0)
  let builder = prepare_conditional_row(conditional, {
    max_nodes: 9,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 13,
  }).unwrap()
  append_conditional_cell(builder, Some(row[0])).unwrap()
  append_conditional_cell(builder, None).unwrap()
  append_conditional_cell(builder, Some(row[1])).unwrap()
  let row = finish_conditional_row(builder).unwrap()
  let output = prepare_admitted_output(owner, Step(1), 1, {
    max_nodes: 3,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 7,
  }).unwrap()
  let active = start_conditional_required_output_preparation(
    output,
    conditional,
    1,
    16,
    4,
    index => if index == 0 { Some(row) } else { None },
  ).unwrap()
  assert_true(conditional_required_output_rows(active) is None)
  let mut dense = None
  for _ in 0..<16 {
    match advance_conditional_required_output_preparation(active, 1).unwrap() {
      AdmittedOutputContinue(..) => ()
      AdmittedOutputComplete(rows, ..) => {
        dense = Some(rows)
        break
      }
      _ => fail("required projection did not complete")
    }
  }
  let dense = dense.unwrap()
  assert_true(conditional_required_output_rows(active) is Some(_))
  assert_eq(admitted_output_row_count(dense), 1)
  assert_true(admitted_output_cell(dense, 0, 0) is Some(@admitted.Number(1.0)))
  assert_true(admitted_output_cell(dense, 0, 1) is Some(@admitted.Text("é")))
  assert_eq(admitted_output_usage(dense), { nodes: 3, text_bytes: 4, work: 7, })
  assert_true(cleanup_conditional_required_output_preparation(active).unwrap())
  assert_true(conditional_required_output_rows(active) is None)
  let one_short = prepare_admitted_output(owner, Step(1), 1, {
    max_nodes: 3,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 7,
  }).unwrap()
  let rejected = start_conditional_required_output_preparation(
    one_short,
    conditional,
    1,
    15,
    4,
    index => if index == 0 { Some(row) } else { None },
  ).unwrap()
  let mut limited = false
  for _ in 0..<16 {
    match
      advance_conditional_required_output_preparation(rejected, 1).unwrap() {
      AdmittedOutputContinue(..) => ()
      AdmittedOutputFailed(CaptureLimit, ..) => {
        limited = true
        break
      }
      _ => fail("one-short required projection completed")
    }
  }
  assert_true(limited)
  assert_true(conditional_required_output_rows(rejected) is None)
  assert_true(
    cleanup_conditional_required_output_preparation(rejected).unwrap(),
  )
  let cancelled_output = prepare_admitted_output(owner, Step(1), 1, {
    max_nodes: 3,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 7,
  }).unwrap()
  let cancelled = start_conditional_required_output_preparation(
    cancelled_output,
    conditional,
    1,
    16,
    4,
    index => if index == 0 { Some(row) } else { None },
  ).unwrap()
  for _ in 0..<5 {
    assert_true(
      advance_conditional_required_output_preparation(cancelled, 1).unwrap()
      is AdmittedOutputContinue(..),
    )
  }
  assert_true(cancelled.source.row is Some(_))
  assert_true(cancel_conditional_required_output_preparation(cancelled))
  assert_true(
    advance_conditional_required_output_preparation(cancelled, 1).unwrap()
    is AdmittedOutputStopped(..),
  )
  assert_true(conditional_required_output_rows(cancelled) is None)
  assert_true(
    cleanup_conditional_required_output_preparation(cancelled).unwrap(),
  )
  assert_true(cancelled.source.row is None)
  assert_true(cancelled_output.buffer.rows.is_empty())
  let empty_output = prepare_admitted_output(owner, Step(1), 0, {
    max_nodes: 0,
    max_text_bytes: 0,
    max_depth: 0,
    max_work: 0,
  }).unwrap()
  let empty = start_conditional_required_output_preparation(
    empty_output,
    conditional,
    0,
    4,
    0,
    _ => None,
  ).unwrap()
  let mut empty_rows = None
  for _ in 0..<4 {
    match advance_conditional_required_output_preparation(empty, 1).unwrap() {
      AdmittedOutputContinue(..) => ()
      AdmittedOutputComplete(rows, ..) => {
        empty_rows = Some(rows)
        break
      }
      _ => fail("empty required projection failed")
    }
  }
  assert_eq(admitted_output_row_count(empty_rows.unwrap()), 0)
  assert_true(cleanup_conditional_required_output_preparation(empty).unwrap())
}

///|
test "required projection rejects a renamed field before publishing output" {
  let owner = capture_fixture()
  let target = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(1),
  ).unwrap()
  let n = @schema.lookup(target, Unqualified("n")).unwrap()
  let s = @schema.lookup(target, Unqualified("s")).unwrap()
  let conditional = @schema.from_conditional_fields(
    [
      (Unqualified("s"), s, @schema.Required),
      (Unqualified("x"), n, @schema.Required),
    ],
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  let supplied = output_fixture_row(owner, 0)
  let builder = prepare_conditional_row(conditional, {
    max_nodes: 5,
    max_text_bytes: 5,
    max_depth: 2,
    max_work: 10,
  }).unwrap()
  append_conditional_cell(builder, Some(supplied[1])).unwrap()
  append_conditional_cell(builder, Some(supplied[0])).unwrap()
  let row = finish_conditional_row(builder).unwrap()
  let output = prepare_admitted_output(owner, Step(1), 1, {
    max_nodes: 10,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 20,
  }).unwrap()
  let active = start_conditional_required_output_preparation(
    output,
    conditional,
    1,
    64,
    8,
    index => if index == 0 { Some(row) } else { None },
  ).unwrap()
  let mut rejected = false
  for _ in 0..<64 {
    match advance_conditional_required_output_preparation(active, 1).unwrap() {
      AdmittedOutputContinue(..) => ()
      AdmittedOutputFailed(InvalidCheckedRow, ..) => {
        rejected = true
        break
      }
      _ => fail("renamed required field was accepted")
    }
  }
  assert_true(rejected)
  assert_true(finish_admitted_output(output) is Err(ClosedCapture))
  assert_true(cleanup_conditional_required_output_preparation(active).unwrap())
  let empty_output = prepare_admitted_output(owner, Step(1), 0, {
    max_nodes: 0,
    max_text_bytes: 0,
    max_depth: 0,
    max_work: 0,
  }).unwrap()
  let empty = start_conditional_required_output_preparation(
    empty_output,
    conditional,
    0,
    4,
    0,
    _ => None,
  ).unwrap()
  assert_true(
    advance_conditional_required_output_preparation(empty, 1).unwrap()
    is AdmittedOutputFailed(InvalidCheckedRow, ..),
  )
  assert_true(conditional_required_output_rows(empty) is None)
  assert_true(cleanup_conditional_required_output_preparation(empty).unwrap())
}
