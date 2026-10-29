///|
fn key_quantity_cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(text, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 1000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
}

///|
test "key constructor quantity retains original fields and singleton aliases without owning their input" {
  let one = primary_key_read_construction_inventory(1, 1, 0L).unwrap()
  // One original KeyedRelation/Usage, KeyField/name and fields/aliases/one
  // singleton backing, expanded through the pinned shared Array model.
  assert_eq(one.retained, {
    record_headers: 13L,
    reference_slots: 60L,
    scalar_words: 10L,
  })
  let two = primary_key_read_construction_inventory(2, 1, 0L).unwrap()
  assert_eq(two.retained, {
    record_headers: 18L,
    reference_slots: 86L,
    scalar_words: 13L,
  })
  let input = @carrier.relation(@carrier.unknown_rows())
  let source = key_quantity_cursor("[\"x\",\"y\"]")
  let actual = declare_primary_key(source, input, {
    max_fields: 2,
    max_name_bytes: 2,
  }).unwrap()
  assert_eq(key_field_count(actual), 2)
  assert_true(physical_equal(key_source(actual), source))
  assert_true(
    physical_equal(
      keyed_records(actual),
      @carrier.relation_rows(input).unwrap(),
    ),
  )
}

///|
test "key quantity is not key admission and keeps original empty duplicate and nontext refusals" {
  assert_true(primary_key_read_construction_inventory(0, 0, 0L) is Some(_))
  assert_true(primary_key_read_construction_inventory(-1, 0, 0L) is None)
  assert_true(primary_key_read_construction_inventory(1, -1, 0L) is None)
  assert_true(primary_key_read_construction_inventory(1, 0, -1L) is None)
  let input = @carrier.relation(@carrier.unknown_rows())
  for
    (wire, expected) in [
      ("[]", IssueKind::EmptyKey),
      ("[\"x\",\"x\"]", IssueKind::DuplicateKeyField("x")),
    ] {
    let result = declare_primary_key(key_quantity_cursor(wire), input, {
      max_fields: 2,
      max_name_bytes: 20,
    })
    match result {
      Err(issue) => assert_eq(issue.kind, expected)
      Ok(_) => fail("invalid key admitted")
    }
  }
  assert_true(
    declare_primary_key(key_quantity_cursor("[1]"), input, {
      max_fields: 1,
      max_name_bytes: 20,
    })
    is Err(_),
  )
}
