///|
fn field_binding_carrier(name : String) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified(name),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=1000,
    ).unwrap(),
  )
}

///|
test "record field binding yields before a long declared name is accepted" {
  let name = String::make(130, 'a')
  let builder = prepare(field_binding_carrier(name), limits()).unwrap()
  let cursor = start_append(builder, [
    (@schema.Unqualified(name), number_for_append_steps()),
  ]).unwrap()
  assert_eq(advance_append(cursor), Ok(false))
  assert_eq(cursor.fields.length(), 0)
  assert_eq(cursor.index, 0)
  assert_eq(builder_record_count(builder), 0)
  assert_true(builder_append_pending(builder))
  assert_true(cleanup_append(cursor))
  assert_false(cleanup_append(cursor))
  assert_eq(advance_append(cursor), Err(Closed))
  assert_true(cancel(builder))
  assert_eq(builder_workspace_slots(builder), 0)
}

///|
test "record field names keep independent wire and workspace boundaries" {
  let name = String::make(130, 'a')
  // [["<130 a>",1]]: 138 bytes, four nodes, width+1=2 work.
  // Cursor 16+3+6=25 and retained row three coexist at the 28-slot peak.
  for
    (slots, work, bytes, expected) in [
      (28, 6, 138, Ok(true)),
      (27, 6, 138, Err(WorkspaceLimit)),
      (28, 5, 138, Err(WorkLimit)),
      (28, 1000, 137, Err(ValueLimit)),
    ] {
    let builder = prepare(
      field_binding_carrier(name),
      append_step_limits(slots, work, bytes),
    ).unwrap()
    let cursor = start_append(builder, [
      (@schema.Unqualified(name), number_for_append_steps()),
    ]).unwrap()
    let (outcome, _) = identity_step_result(cursor, 60)
    assert_eq(outcome, expected)
    if expected == Ok(true) {
      assert_eq(builder_construction_work(builder), 6)
      let stored = finish(builder).unwrap()
      let (field, value) = record_field_at(stored, 0, 0).unwrap()
      assert_eq(field, @schema.Unqualified(name))
      assert_true(value.value is @value.Number(1.0))
      discard(stored)
      assert_eq(record_count(stored), 0)
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
test "record name fingerprint collisions retain exact field identity" {
  // 97*33+98 == 98*33+65; these distinct names share a djb2 bucket.
  let records = @carrier.rows(
    [
      (
        @schema.Unqualified("ab"),
        Some(@contract.primitive(@contract.NumberType, nullable=false)),
      ),
      (
        @schema.Unqualified("bA"),
        Some(@contract.primitive(@contract.NumberType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=2,
    max_name_bytes=4,
  ).unwrap()
  let builder = prepare(@carrier.relation(records), limits()).unwrap()
  let fields = [
    (@schema.Unqualified("ab"), number_for_append_steps()),
    (@schema.Unqualified("bA"), number_for_append_steps()),
  ]
  let cursor = start_append(builder, fields).unwrap()
  assert_eq(identity_step_result(cursor, 100).0, Ok(true))
  let stored = finish(builder).unwrap()
  assert_eq(record_field_at(stored, 0, 0).unwrap().0, @schema.Unqualified("ab"))
  assert_eq(record_field_at(stored, 0, 1).unwrap().0, @schema.Unqualified("bA"))
  discard(stored)
}

///|
test "record field binding preserves long duplicate missing and absent refusal" {
  let name = String::make(130, 'a')
  let value = number_for_append_steps()
  for
    fields in [
      [(@schema.Unqualified(name), value), (@schema.Unqualified(name), value)],
      [(@schema.Unqualified(String::make(129, 'a') + "b"), value)],
      [],
    ] {
    let builder = prepare(field_binding_carrier(name), limits()).unwrap()
    let cursor = start_append(builder, fields).unwrap()
    assert_eq(identity_step_result(cursor, 100).0, Err(InvalidRecord))
    assert_eq(builder_record_count(builder), 0)
    assert_true(cancel(builder))
    assert_eq(builder_workspace_slots(builder), 0)
  }
}

///|
test "record name comparison keeps UTF16 order and qualified role without flattening" {
  let text = String::make(63, 'a') + "😀" + String::make(65, 'é')
  let left = record_name(@schema.Qualified(@schema.Left, text))
  let binding = start_record_name(left)
  assert_false(advance_record_name_hash(binding))
  assert_false(advance_record_name_hash(binding))
  assert_true(advance_record_name_hash(binding))
  binding.offset = 0
  assert_eq(compare_record_name(binding, left, 64), (None, 64))
  assert_eq(compare_record_name(binding, left, 64), (None, 64))
  assert_eq(compare_record_name(binding, left, 64), (Some(0), 7))
  binding.offset = 0
  assert_eq(
    compare_record_name(
      binding,
      record_name(@schema.Qualified(@schema.Right, text)),
      64,
    ),
    (Some(1), 1),
  )
}

///|
test "record name continuation binds the captured field across caller mutation" {
  let name = String::make(130, 'a')
  let builder = prepare(field_binding_carrier(name), limits()).unwrap()
  let fields = [(@schema.Unqualified(name), number_for_append_steps())]
  let cursor = start_append(builder, fields).unwrap()
  assert_eq(advance_append(cursor), Ok(false))
  fields[0] = (@schema.Unqualified("foreign"), number_for_append_steps())
  assert_eq(identity_step_result(cursor, 100).0, Ok(true))
  let stored = finish(builder).unwrap()
  assert_eq(record_field_at(stored, 0, 0).unwrap().0, @schema.Unqualified(name))
  discard(stored)
}

///|
test "record prior identity name scan retains earlier rows through cleanup" {
  let name = String::make(130, 'a')
  let builder = prepare_with_additional_identities(
    field_binding_carrier(name),
    [@schema.Unqualified(name)],
    limits(),
  ).unwrap()
  let fields = [(@schema.Unqualified(name), number_for_append_steps())]
  assert_eq(append(builder, fields), Ok(()))
  let retained = builder_retained_value_bytes(builder)
  let cursor = start_append(builder, fields).unwrap()
  let mut reached = false
  for _ in 0..<100 {
    if cursor.phase is ReadPriorIdentity &&
      cursor.binding is Some(binding) &&
      binding.offset > 0 {
      reached = true
      break
    }
    assert_eq(advance_append(cursor), Ok(false))
  }
  assert_true(reached)
  assert_eq(builder_record_count(builder), 1)
  assert_eq(builder_retained_value_bytes(builder), retained)
  assert_true(cleanup_append(cursor))
  assert_false(cleanup_append(cursor))
  assert_true(cursor.binding is None)
  assert_eq(builder_record_count(builder), 1)
  assert_eq(builder_retained_value_bytes(builder), retained)
  assert_true(cancel(builder))
  assert_false(cancel(builder))
  assert_eq(builder_retained_value_bytes(builder), 0)
  assert_eq(builder_workspace_slots(builder), 0)
}

///|
test "record schema binding preserves typed qualification after spelling equality" {
  let text = String::make(130, 'a')
  let name = @schema.Qualified(@schema.Left, text)
  let records = @carrier.rows(
    [(name, Some(@contract.primitive(@contract.NumberType, nullable=false)))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=135,
  ).unwrap()
  for
    (supplied, success) in [
      (name, true),
      (@schema.Unqualified("left." + text), false),
      (@schema.Qualified(@schema.Right, text), false),
    ] {
    let builder = prepare(@carrier.relation(records), limits()).unwrap()
    let cursor = start_append(builder, [(supplied, number_for_append_steps())]).unwrap()
    assert_eq(
      identity_step_result(cursor, 100).0,
      if success {
        Ok(true)
      } else {
        Err(InvalidRecord)
      },
    )
    if success {
      let stored = finish(builder).unwrap()
      assert_eq(record_field_at(stored, 0, 0).unwrap().0, name)
      discard(stored)
    } else {
      assert_eq(builder_record_count(builder), 0)
      assert_true(cancel(builder))
    }
  }
}

///|
test "record name collision buckets yield before traversing every prior field" {
  // ab and bA have the same two-unit polynomial contribution. Four independent
  // pair choices give sixteen distinct eight-unit names in one bucket.
  let names = Array::makei(16, bits => {
    Array::makei(4, pair => if (bits & (1 << pair)) == 0 { "ab" } else { "bA" }).join(
      "",
    )
  })
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let knowledge = @carrier.rows(
    names.map(name => (@schema.Unqualified(name), Some(number))),
    field_set=@carrier.Closed,
    max_fields=16,
    max_name_bytes=128,
  ).unwrap()
  let builder = prepare(@carrier.relation(knowledge), {
    ..limits(),
    max_fields_per_record: 16,
  }).unwrap()
  let fields = names.map(name => {
    (@schema.Unqualified(name), number_for_append_steps())
  })
  let cursor = start_append(builder, fields).unwrap()
  let mut yielded = false
  for _ in 0..<100 {
    if cursor.fields.length() > 8 &&
      cursor.phase is FieldBinding &&
      cursor.binding is Some(binding) &&
      binding.phase is BucketName {
      assert_true(cursor.fields.length() > 8)
      assert_true(binding.candidate >= 0)
      yielded = true
      break
    }
    assert_eq(advance_append(cursor), Ok(false))
  }
  assert_true(yielded)
  assert_eq(builder_record_count(builder), 0)
  assert_true(cleanup_append(cursor))
  assert_false(cleanup_append(cursor))
  assert_eq(cursor.name_links.length(), 0)
  assert_eq(cursor.actual.length(), 0)
  assert_true(cancel(builder))
}

///|
test "empty record append retains its original workspace boundary" {
  // No field means no name cursor or links. Fixed eight plus depth-one
  // stacks (three) and retained record custody (two) give thirteen slots.
  for (slots, expected) in [(13, Ok(true)), (12, Err(WorkspaceLimit))] {
    let builder = prepare(@carrier.relation(@carrier.unknown_rows()), {
      ..append_step_limits(slots, 2, 2),
      max_value_depth: 1,
    }).unwrap()
    let cursor = start_append(builder, []).unwrap()
    assert_eq(identity_step_result(cursor, 10).0, expected)
    assert_true(cursor.binding is None)
    if expected == Ok(true) {
      assert_eq(builder_construction_work(builder), 2)
      let output = finish(builder).unwrap()
      assert_eq(record_count(output), 1)
      assert_eq(record_field_count(output, 0), Some(0))
      discard(output)
    } else {
      assert_true(cancel(builder))
    }
  }
}
