///|
fn contract_step_record(
  name : String,
) -> (@carrier.Carrier, Array[(@schema.FieldName, @value.CheckedValue)]) {
  let contract = @contract.object_contract(
    [(name, @contract.primitive(@contract.NumberType, nullable=false))],
    nullable=false,
    max_fields=1,
    max_name_bytes=2000,
  ).unwrap()
  let carrier = @carrier.relation(
    @carrier.rows(
      [(@schema.Unqualified("value"), Some(contract))],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  )
  let value = @value.admit(contract, cursor("{\"" + name + "\":1}"), {
    max_nodes: 3,
    max_depth: 2,
    max_text_bytes: 2000,
  }).unwrap()
  (carrier, [(@schema.Unqualified("value"), value)])
}

///|
test "record append resumes contract names with unchanged construction limits" {
  let name = String::make(130, 'a')
  let (carrier, fields) = contract_step_record(name)
  // Record wire [["value",{"<130 a>":1}]] is 148 bytes, five nodes.
  // Construction remains width+1+nodes=7; contract scans add no wire work.
  // Two wire arrays and the object need depth 3. Cursor 8+2+3*3=19
  // and the retained row (3) require 22 slots.
  for (work, success) in [(7, true), (6, false)] {
    let builder = prepare(carrier, {
      ..append_step_limits(22, work, 148),
      max_value_depth: 3,
    }).unwrap()
    let cursor = start_append(builder, fields).unwrap()
    assert_eq(advance_append(cursor), Ok(false))
    assert_true(cursor.phase is FieldContract)
    assert_eq(cursor.index, 0)
    assert_eq(cursor.fields.length(), 0)
    assert_eq(builder_workspace_slots(builder), 19)
    for _ in 0..<3 {
      assert_eq(advance_append(cursor), Ok(false))
      assert_true(cursor.phase is FieldContract)
      assert_eq(cursor.index, 0)
    }
    assert_eq(advance_append(cursor), Ok(false))
    assert_true(cursor.phase is FieldContract)
    assert_eq(advance_append(cursor), Ok(false))
    assert_true(cursor.phase is Fields)
    let mut terminal = false
    for _ in 0..<30 {
      if !terminal {
        match advance_append(cursor) {
          Ok(false) => ()
          Ok(true) => {
            assert_true(success)
            assert_eq(builder_construction_work(builder), 7)
            assert_eq(builder_retained_value_bytes(builder), 148)
            terminal = true
          }
          Err(issue) => {
            assert_false(success)
            assert_eq(issue, WorkLimit)
            terminal = true
          }
        }
      }
    }
    assert_true(terminal)
    if success {
      let output = finish(builder).unwrap()
      assert_eq(record_count(output), 1)
      discard(output)
      assert_eq(record_count(output), 0)
    } else {
      assert_eq(builder_record_count(builder), 0)
      assert_true(cancel(builder))
      assert_eq(builder_workspace_slots(builder), 0)
    }
  }
}

///|
test "record contract stack reserves exact extra custody before allocation" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let mut contract = number
  for _ in 0..<5 {
    contract = @contract.object_contract(
      [("a", contract), ("z", number)],
      nullable=false,
      max_fields=2,
      max_name_bytes=2,
    ).unwrap()
  }
  contract = @contract.with_nullability(contract, true)
  let carrier = @carrier.relation(
    @carrier.rows(
      [(@schema.Unqualified("value"), Some(contract))],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  )
  let checked = @value.admit(contract, cursor("null"), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 0,
  }).unwrap()
  // NULL's wire fits depth 2, but its five-level declared Object contract
  // has a peak of six frames: one name frame and five child iterators.
  // Root custody is fixed; 3*(6-1)=15 continuation slots exceed the six
  // reusable wire slots by nine. Base 16+9=25 is the comparison peak;
  // final record custody is only 16+3=19, after releasing the nine slots.
  for (slots, expected) in [(25, Ok(true)), (24, Err(WorkspaceLimit))] {
    let builder = prepare(carrier, {
      ..append_step_limits(slots, 10, 100),
      max_contract_work: 11,
    }).unwrap()
    let cursor = start_append(builder, [(@schema.Unqualified("value"), checked)]).unwrap()
    let (result, _) = identity_step_result(cursor, 100)
    assert_eq(result, expected)
    if expected == Ok(true) {
      assert_eq(builder_workspace_slots(builder), 3)
      assert_eq(cursor.contract_slots, 0)
      let output = finish(builder).unwrap()
      assert_true(record_field_at(output, 0, 0).unwrap().1.value is @value.Null)
      discard(output)
    } else {
      assert_true(cursor.contract_check is Some(_))
      assert_eq(builder_record_count(builder), 0)
      assert_true(builder_workspace_slots(builder) <= slots)
      assert_true(cleanup_append(cursor))
      assert_eq(builder_workspace_slots(builder), 0)
      assert_true(cancel(builder))
    }
  }
  let builder = prepare(carrier, {
    ..append_step_limits(25, 10, 100),
    max_contract_work: 10,
  }).unwrap()
  let cursor = start_append(builder, [(@schema.Unqualified("value"), checked)]).unwrap()
  assert_eq(identity_step_result(cursor, 100).0, Err(InvalidRecord))
  assert_eq(builder_record_count(builder), 0)
  assert_true(cancel(builder))
  assert_eq(builder_workspace_slots(builder), 0)
}

///|
test "record contract cancellation retains prior rows until owner cleanup" {
  let (carrier, fields) = contract_step_record(String::make(130, 'a'))
  let builder = prepare(carrier, {
    ..append_step_limits(40, 100, 1000),
    max_value_depth: 3,
  }).unwrap()
  append(builder, fields).unwrap()
  let bytes = builder_retained_value_bytes(builder)
  let cursor = start_append(builder, fields).unwrap()
  assert_eq(advance_append(cursor), Ok(false))
  assert_eq(advance_append(cursor), Ok(false))
  assert_true(cursor.phase is FieldContract)
  assert_true(cursor.contract_check is Some(_))
  assert_eq(builder_record_count(builder), 1)
  assert_true(finish(builder) is Err(Closed))
  assert_true(cleanup_append(cursor))
  assert_false(cleanup_append(cursor))
  assert_true(cursor.contract_check is None)
  assert_eq(builder_record_count(builder), 1)
  assert_eq(builder_retained_value_bytes(builder), bytes)
  assert_eq(builder_workspace_slots(builder), 3)
  assert_true(cancel(builder))
  assert_eq(builder_workspace_slots(builder), 0)
  assert_eq(builder_retained_value_bytes(builder), 0)
}

///|
test "record contract mismatch fails before wire commit with typed custody" {
  let prefix = String::make(129, 'a')
  let (carrier, _) = contract_step_record(prefix + "a")
  let (_, foreign) = contract_step_record(prefix + "b")
  let builder = prepare(carrier, {
    ..append_step_limits(22, 100, 1000),
    max_value_depth: 3,
  }).unwrap()
  let cursor = start_append(builder, foreign).unwrap()
  for _ in 0..<3 {
    assert_eq(advance_append(cursor), Ok(false))
    assert_true(cursor.phase is FieldContract)
  }
  assert_eq(advance_append(cursor), Err(InvalidRecord))
  assert_eq(builder_record_count(builder), 0)
  assert_eq(builder_construction_work(builder), 0)
  assert_eq(builder_retained_value_bytes(builder), 0)
  assert_true(cursor.writer is None)
  assert_true(builder_append_pending(builder))
  assert_true(finish(builder) is Err(Closed))
  assert_true(cleanup_append(cursor))
  assert_false(cleanup_append(cursor))
  assert_eq(builder_workspace_slots(builder), 0)
  assert_true(cancel(builder))
}

///|
test "record contract continuation binds the field it actually validated" {
  let prefix = String::make(129, 'a')
  let (carrier, fields) = contract_step_record(prefix + "a")
  let (_, foreign) = contract_step_record(prefix + "b")
  let original = fields[0].1
  let builder = prepare(carrier, {
    ..append_step_limits(22, 100, 1000),
    max_value_depth: 3,
  }).unwrap()
  let cursor = start_append(builder, fields).unwrap()
  assert_eq(advance_append(cursor), Ok(false))
  assert_true(cursor.phase is FieldContract)
  // Caller mutation cannot substitute a different value after its contract
  // was chosen for comparison. This fixture mutates no admitted value.
  fields[0] = foreign[0]
  assert_eq(identity_step_result(cursor, 100).0, Ok(true))
  let output = finish(builder).unwrap()
  assert_true(
    physical_equal(record_field_at(output, 0, 0).unwrap().1, original),
  )
  assert_true(cursor.contract_field is None)
  discard(output)
}
