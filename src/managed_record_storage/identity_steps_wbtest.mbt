// Calls selecting zero test only storage-owned custody, without enclosing
// kernel scratch. Explicit caller-scratch cases retain their separate charge.

///|
fn identity_step_builder(slots : Int, work : Int, bytes : Int) -> Builder {
  prepare_with_additional_identities(
    relation(),
    [@schema.Unqualified("value")],
    append_step_limits(slots, work, bytes),
  ).unwrap()
}

///|
fn identity_step_result(
  cursor : AppendCursor,
  bound : Int,
) -> (Result[Bool, Issue], Int) {
  for poll in 1..<(bound + 1) {
    let result = advance_append(cursor)
    if result != Ok(false) {
      return (result, poll)
    }
  }
  abort("identity append exceeded its finite poll bound")
}

///|
test "record identity hash keeps exact wire limits without assembled Text" {
  // ["<130 a>"] is 134 bytes and two nodes; the record is 144 bytes,
  // four nodes and width overhead two. Construction 8, total bytes 278.
  // Cursor 16+3+1+6=26 plus retained row three is 29 workspace slots.
  let text = String::make(130, 'a')
  for
    (slots, work, bytes, expected, expected_polls) in [
      (29, 8, 278, Ok(true), 22),
      (28, 8, 278, Err(WorkspaceLimit), 21),
      (29, 7, 278, Err(WorkLimit), 16),
      (29, 1000, 277, Err(ValueLimit), 21),
    ] {
    let builder = identity_step_builder(slots, work, bytes)
    let cursor = start_append(
      builder,
      relation_record(text),
      external_workspace_slots=0,
    ).unwrap()
    let (result, polls) = identity_step_result(cursor, 50)
    assert_eq(result, expected)
    assert_eq(polls, expected_polls)
    if expected == Ok(true) {
      assert_eq(builder_construction_work(builder), 8)
      assert_eq(builder_retained_value_bytes(builder), 278)
      assert_eq(builder_workspace_slots(builder), 3)
      assert_eq(builder.keys.length(), 1)
      let stored = finish(builder).unwrap()
      assert_eq(builder.keys.length(), 0)
      guard record_field_at(stored, 0, 0).unwrap().1.value
        is @value.Text(actual) else {
        abort("stored identity Text missing")
      }
      assert_eq(actual, text)
      discard(stored)
    } else {
      assert_eq(builder_record_count(builder), 0)
      assert_true(cancel(builder))
      assert_eq(builder_workspace_slots(builder), 0)
    }
  }
}

///|
test "record identity collision equality yields and retains cleanup custody" {
  let text = String::make(130, 'a')
  // A comparison reserves an additional 8+1+3*2=15 slots. With the
  // prior row (3) and append cursor (26), exact peak is 44, not 29.
  for (slots, expected) in [(44, DuplicateIdentity), (43, WorkspaceLimit)] {
    let builder = identity_step_builder(slots, 100, 1000)
    append(builder, relation_record(text)).unwrap()
    let cursor = start_append(
      builder,
      relation_record(text),
      external_workspace_slots=0,
    ).unwrap()
    let mut comparisons = 0
    let mut outcome = None
    for _ in 0..<100 {
      if outcome is None {
        if cursor.phase is CompareKey {
          comparisons += 1
          assert_eq(builder_workspace_slots(builder), 44)
        }
        match advance_append(cursor) {
          Ok(false) => ()
          Err(issue) => outcome = Some(issue)
          Ok(true) => abort("duplicate identity cannot commit")
        }
      }
    }
    assert_eq(outcome, Some(expected))
    assert_true(if slots == 44 { comparisons > 15 } else { comparisons == 0 })
    assert_eq(builder_record_count(builder), 1)
    assert_eq(builder_construction_work(builder), 8)
    assert_eq(builder_retained_value_bytes(builder), 278)
    assert_true(builder_append_pending(builder))
    assert_true(finish(builder) is Err(Closed))
    assert_true(cleanup_append(cursor))
    assert_false(cleanup_append(cursor))
    assert_eq(builder_workspace_slots(builder), 3)
    assert_true(cancel(builder))
    assert_eq(builder_workspace_slots(builder), 0)
    assert_eq(builder_retained_value_bytes(builder), 0)
  }
  let builder = identity_step_builder(44, 100, 1000)
  append(builder, relation_record(text)).unwrap()
  let cursor = start_append(
    builder,
    relation_record(text),
    external_workspace_slots=0,
  ).unwrap()
  for _ in 0..<100 {
    if cursor.phase is CompareKey && cursor.comparison.unwrap().left.offset > 0 {
      break
    }
    assert_eq(advance_append(cursor), Ok(false))
  }
  assert_true(cursor.phase is CompareKey)
  assert_eq(builder_workspace_slots(builder), 44)
  assert_true(cleanup_append(cursor))
  assert_true(cursor.comparison is None)
  assert_eq(advance_append(cursor), Err(Closed))
  assert_eq(builder_retained_value_bytes(builder), 278)
  assert_eq(builder_record_count(builder), 1)
  assert_true(cancel(builder))
}

///|
test "record identity digest collisions never replace exact wire equality" {
  let builder = identity_step_builder(44, 100, 1000)
  let first = String::make(130, 'a')
  let second = String::make(130, 'b')
  append(builder, relation_record(first)).unwrap()
  let cursor = start_append(
    builder,
    relation_record(second),
    external_workspace_slots=0,
  ).unwrap()
  // Force the first record into the second digest bucket at the boundary.
  // This tests collision safety without assuming an actual SHA-256 collision.
  while !(cursor.phase is FinishKey) {
    assert_eq(advance_append(cursor), Ok(false))
  }
  assert_eq(advance_append(cursor), Ok(false))
  assert_eq(cursor.key.length(), 64)
  builder.keys[cursor.key] = builder.values[0]
  // Repeat the lookup boundary with the forced bucket, not another Compute.
  cursor.candidate = Some(builder.values[0])
  cursor.workspace += 15
  cursor.comparison_slots = 15
  cursor.prior_identities = Some([])
  cursor.phase = ReadPriorIdentity
  let (result, _) = identity_step_result(cursor, 100)
  assert_eq(result, Ok(true))
  assert_eq(builder_record_count(builder), 2)
  assert_eq(builder_construction_work(builder), 16)
  assert_eq(builder_retained_value_bytes(builder), 556)
  assert_true(builder.values[1].prior_identity is Some(_))
  // The same second identity must still be rejected by the legacy caller.
  assert_eq(append(builder, relation_record(second)), Err(DuplicateIdentity))
  assert_true(cancel(builder))
}

///|
test "record identity streaming equality preserves Unicode and escaped chunks" {
  let builder = prepare(events(), limits()).unwrap()
  for
    (left, right, equal) in [
      ("é", "e\u0301", false),
      ("\r\n", "\n", false),
      (String::make(130, '\u0001'), String::make(130, '\u0001'), true),
      (String::make(63, 'a') + "😀", String::make(63, 'a') + "😀", true),
      (String::make(130, 'a') + "b", String::make(130, 'a') + "c", false),
    ] {
    let contract = @contract.primitive(@contract.StringType, nullable=false)
    let values_left = [@value.checked_text_value(left, contract).unwrap()]
    let values_right = [@value.checked_text_value(right, contract).unwrap()]
    let comparison : IdentityComparison = {
      left: identity_stream(builder, values_left),
      right: identity_stream(builder, values_right),
    }
    let mut outcome = None
    for _ in 0..<100 {
      if outcome is None {
        outcome = advance_identity_comparison(comparison)
        assert_true(comparison.left.piece.length() <= 388)
        assert_true(comparison.right.piece.length() <= 388)
      }
    }
    assert_eq(outcome, Some(equal))
    cancel_identity_comparison(comparison)
  }
  assert_true(cancel(builder))
}

///|
test "record identity equality ignores emitter fragment boundaries" {
  let builder = prepare(relation(), limits()).unwrap()
  // Vector and declared numeric Array have the same canonical wire but different child
  // continuation schedules. This private comparator tests wire equality only;
  // it does not make structured values eligible Carrier identity fields.
  let vector = checked(
    @contract.vector_contract(2.0, nullable=false).unwrap(),
    "[1,2]",
  )
  let array = checked(
    @contract.array_contract(
      @contract.primitive(@contract.NumberType, nullable=false),
      nullable=false,
    ).unwrap(),
    "[1,2]",
  )
  assert_true(identity_equal(builder, [vector], [array]))
  let different = checked(
    @contract.array_contract(
      @contract.primitive(@contract.NumberType, nullable=false),
      nullable=false,
    ).unwrap(),
    "[1,3]",
  )
  assert_false(identity_equal(builder, [vector], [different]))
  assert_true(cancel(builder))
}
