///|
fn qualified_name_records() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Qualified(@schema.Left, String::make(130, 'a')),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=135,
    ).unwrap(),
  )
}

///|
test "qualified record emission preserves independently derived limits" {
  let field = @schema.Qualified(@schema.Left, String::make(130, 'a'))
  // [["left.<130 a>",1]]: 135 name bytes plus eight structural/value bytes,
  // four wire nodes plus width+1=2 work; cursor25 plus retained-row3.
  for
    (slots, work, bytes, expected) in [
      (28, 6, 143, Ok(true)),
      (27, 6, 143, Err(WorkspaceLimit)),
      (28, 5, 143, Err(WorkLimit)),
      (28, 1000, 142, Err(ValueLimit)),
    ] {
    let builder = prepare(
      qualified_name_records(),
      append_step_limits(slots, work, bytes),
    ).unwrap()
    let cursor = start_append(builder, [(field, number_for_append_steps())]).unwrap()
    let (result, _) = identity_step_result(cursor, 100)
    assert_eq(result, expected)
    if expected == Ok(true) {
      assert_eq(builder_construction_work(builder), 6)
      assert_eq(builder_retained_value_bytes(builder), 143)
      let stored = finish(builder).unwrap()
      assert_eq(record_field_at(stored, 0, 0).unwrap().0, field)
      discard(stored)
    } else {
      assert_eq(builder_record_count(builder), 0)
      assert_true(builder_append_pending(builder))
      assert_true(cancel(builder))
      assert_eq(builder_workspace_slots(builder), 0)
      assert_eq(builder_retained_value_bytes(builder), 0)
    }
  }
}

///|
test "qualified emission cancellation keeps prior rows until separate cleanup" {
  let field = @schema.Qualified(@schema.Left, String::make(130, 'a'))
  let builder = prepare(qualified_name_records(), limits()).unwrap()
  let fields = [(field, number_for_append_steps())]
  assert_eq(append(builder, fields), Ok(()))
  let retained = builder_retained_value_bytes(builder)
  let cursor = start_append(builder, fields).unwrap()
  let mut found = false
  for _ in 0..<100 {
    if cursor.phase is FieldName {
      assert_eq(advance_append(cursor), Ok(false))
      assert_true(cursor.phase is FieldName)
      found = true
      break
    }
    assert_eq(advance_append(cursor), Ok(false))
  }
  assert_true(found)
  assert_eq(builder_record_count(builder), 1)
  assert_eq(builder_retained_value_bytes(builder), retained)
  assert_true(cleanup_append(cursor))
  assert_false(cleanup_append(cursor))
  assert_true(cursor.name is None)
  assert_true(cursor.writer is None)
  assert_eq(builder_record_count(builder), 1)
  assert_eq(builder_retained_value_bytes(builder), retained)
  assert_eq(advance_append(cursor), Err(Closed))
  assert_true(cancel(builder))
  assert_false(cancel(builder))
  assert_eq(builder_workspace_slots(builder), 0)
  assert_eq(builder_retained_value_bytes(builder), 0)
}
