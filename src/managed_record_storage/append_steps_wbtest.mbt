///|
fn append_step_limits(slots : Int, work : Int, bytes : Int) -> Limits {
  {
    ..limits(),
    max_workspace_slots: slots,
    max_work: work,
    max_value_bytes: bytes,
    max_total_value_bytes: bytes,
    max_retained_value_bytes: bytes,
    max_value_depth: 2,
  }
}

///|
test "record append keeps exact wire accounting across Text chunk yields" {
  // Wire [["value","<130 a>"]] has 144 bytes and four nodes. The old
  // construction discipline adds width+1=2: six units, not poll count.
  // Cursor 16+3*1+0+3*2=25 and retained row 1+2=3 coexist: 28 slots.
  let fields = relation_record(Array::make(130, "a").join(""))
  for
    (slots, work, bytes, expected) in [
      (28, 6, 144, None),
      (27, 6, 144, Some(WorkspaceLimit)),
      (28, 5, 144, Some(WorkLimit)),
      (28, 1000, 143, Some(ValueLimit)),
    ] {
    let builder = prepare(relation(), append_step_limits(slots, work, bytes)).unwrap()
    let cursor = start_append(builder, fields).unwrap()
    assert_true(builder_append_pending(builder))
    assert_eq(builder_workspace_slots(builder), 25)
    assert_true(finish(builder) is Err(Closed))
    assert_true(start_append(builder, fields) is Err(Closed))
    assert_eq(append(builder, fields), Err(Closed))
    let mut terminal = false
    let mut polls = 0
    for _ in 0..<30 {
      if !terminal {
        polls += 1
        match advance_append(cursor) {
          Ok(false) => assert_eq(builder_record_count(builder), 0)
          Ok(true) => {
            assert_eq(expected, None)
            assert_eq(builder_construction_work(builder), 6)
            assert_eq(builder_retained_value_bytes(builder), 144)
            assert_eq(builder_workspace_slots(builder), 3)
            terminal = true
          }
          Err(issue) => {
            assert_eq(expected, Some(issue))
            assert_eq(builder_record_count(builder), 0)
            assert_true(builder_append_pending(builder))
            terminal = true
          }
        }
      }
    }
    assert_true(terminal)
    if expected is None {
      assert_eq(polls, 15)
      assert_eq(advance_append(cursor), Err(Closed))
      assert_false(cleanup_append(cursor))
      let stored = finish(builder).unwrap()
      assert_eq(record_count(stored), 1)
      guard record_field_at(stored, 0, 0) is Some((_, value)) &&
        value.value is @value.Text(text) else {
        abort("stored Text missing")
      }
      assert_eq(text, Array::make(130, "a").join(""))
      discard(stored)
    } else {
      assert_true(cancel(builder))
      assert_false(cleanup_append(cursor))
      assert_false(cancel(builder))
      assert_eq(builder_workspace_slots(builder), 0)
      assert_eq(builder_retained_value_bytes(builder), 0)
    }
  }
}

///|
test "record append cancellation retains prior rows until builder cleanup" {
  let builder = prepare(relation(), limits()).unwrap()
  append(builder, relation_record("prior")).unwrap()
  let prior_bytes = builder_retained_value_bytes(builder)
  let cursor = start_append(
    builder,
    relation_record(Array::make(130, "a").join("")),
  ).unwrap()
  // Validate fields and required presence, then enter a long Text emission.
  for _ in 0..<10 {
    assert_eq(advance_append(cursor), Ok(false))
  }
  assert_true(cursor.wire is Some(_))
  assert_eq(builder_record_count(builder), 1)
  assert_eq(builder_retained_value_bytes(builder), prior_bytes)
  assert_true(cleanup_append(cursor))
  assert_false(cleanup_append(cursor))
  assert_eq(advance_append(cursor), Err(Closed))
  assert_eq(builder_record_count(builder), 1)
  assert_eq(builder_retained_value_bytes(builder), prior_bytes)
  assert_true(finish(builder) is Err(Closed))
  assert_true(cancel(builder))
  assert_eq(builder_record_count(builder), 0)
  assert_eq(builder_workspace_slots(builder), 0)
  assert_eq(builder_retained_value_bytes(builder), 0)
  assert_false(cancel(builder))
}

///|
test "stepped record append preserves identity uniqueness and field admission" {
  let builder = prepare(events(), limits()).unwrap()
  for duplicate in [false, true] {
    let cursor = start_append(builder, event_record("a", 1.0, "é")).unwrap()
    let mut terminal = false
    for _ in 0..<60 {
      if !terminal {
        match advance_append(cursor) {
          Ok(false) => ()
          Ok(true) => {
            assert_false(duplicate)
            terminal = true
          }
          Err(issue) => {
            assert_true(duplicate)
            assert_eq(issue, DuplicateIdentity)
            terminal = true
          }
        }
      }
    }
    assert_true(terminal)
    assert_eq(builder_record_count(builder), 1)
  }
  assert_true(cancel(builder))
  for
    fields in [
      event_record("a", 1.0, "payload").filter(pair => {
        @schema.reference_name(pair.0) != "payload"
      }),
      [(@schema.Unqualified("value"), number_for_append_steps())],
      [relation_record("x")[0], relation_record("y")[0]],
    ] {
    let builder = prepare(relation(), limits()).unwrap()
    let cursor = start_append(builder, fields).unwrap()
    let mut rejected = false
    for _ in 0..<20 {
      if !rejected {
        match advance_append(cursor) {
          Ok(false) => ()
          Err(issue) => {
            assert_eq(issue, InvalidRecord)
            rejected = true
          }
          Ok(true) => abort("invalid record cannot complete")
        }
      }
    }
    assert_true(rejected)
    assert_true(cancel(builder))
  }
}

///|
fn number_for_append_steps() -> @value.CheckedValue {
  @value.checked_number_value(
    1.0,
    @contract.primitive(@contract.NumberType, nullable=false),
  ).unwrap()
}

///|
test "record append reserves live caller scratch through commit and cleanup" {
  // Existing one-field cursor 25 + caller scratch 11 + retained row 3 = 39.
  // Scratch must also participate in dynamic contract/collision reservations.
  for (slots, expected) in [(39, Ok(true)), (38, Err(WorkspaceLimit))] {
    let builder = prepare(relation(), append_step_limits(slots, 6, 144)).unwrap()
    let fields = relation_record(String::make(130, 'a'))
    let cursor = start_append(builder, fields, external_workspace_slots=11).unwrap()
    assert_eq(builder_workspace_slots(builder), 36)
    let (result, _) = identity_step_result(cursor, 30)
    assert_eq(result, expected)
    if expected == Ok(true) {
      assert_eq(builder_workspace_slots(builder), 3)
      assert_eq(builder_construction_work(builder), 6)
      assert_false(cleanup_append(cursor))
    } else {
      assert_eq(builder_record_count(builder), 0)
      assert_true(builder_append_pending(builder))
      assert_true(cleanup_append(cursor))
      assert_false(cleanup_append(cursor))
    }
    assert_true(cancel(builder))
    assert_eq(builder_workspace_slots(builder), 0)
  }
  let builder = prepare(relation(), limits()).unwrap()
  assert_true(
    start_append(builder, relation_record("a"), external_workspace_slots=-1)
    is Err(InvalidLimits),
  )
  assert_eq(builder_workspace_slots(builder), 0)
  append(builder, relation_record("a")).unwrap()
  assert_true(cancel(builder))
  // Existing collision peak 44 also retains the same caller scratch (11).
  for (slots, expected) in [(55, DuplicateIdentity), (54, WorkspaceLimit)] {
    let builder = identity_step_builder(slots, 100, 1000)
    let fields = relation_record(String::make(130, 'a'))
    append(builder, fields).unwrap()
    let cursor = start_append(builder, fields, external_workspace_slots=11).unwrap()
    let (result, _) = identity_step_result(cursor, 100)
    assert_eq(result, Err(expected))
    assert_eq(builder_record_count(builder), 1)
    assert_true(cancel(builder))
    assert_eq(builder_workspace_slots(builder), 0)
  }
}
