///|
test "omitted infer key refuses foreign records with an equal row contract" {
  let original = infer_input()
  let original_keys = keys(original, ["[\"id\"]"])
  let foreign = infer_input()
  let original_records = @carrier.relation_rows(original).unwrap()
  let foreign_records = @carrier.relation_rows(foreign).unwrap()
  assert_false(physical_equal(original_records, foreign_records))
  assert_true(
    @contract.type_equal(
      @schema.as_object(@carrier.complete_schema(original_records).unwrap()).unwrap(),
      @schema.as_object(@carrier.complete_schema(foreign_records).unwrap()).unwrap(),
      1000,
    ),
  )
  assert_true(
    check(body(key=None), foreign, Some(original_keys), tasks(), None, limits())
    is Err({ kind: InputKeyOwnerMismatch, .. }),
  )
}

///|
test "omitted infer key rejects stale projection evidence and retains its actual transfer" {
  let original = infer_input()
  let original_keys = keys(original, ["[\"id\"]"])
  let projection = @relation.check(
    Select,
    cursor("[{\"ticket\":\"id\"},\"text\"]"),
    @carrier.complete_schema(@carrier.relation_rows(original).unwrap()).unwrap(),
    None,
    {
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_tokens: 1000,
    },
  ).unwrap()
  let transferred = @evidence.advance_keys(Some(original_keys), projection, {
      max_work: 10000,
      max_name_bytes: 10000,
    }).unwrap().keys
  let projected = @carrier.relation(@evidence.key_set_records(transferred))
  let installed = tasks()
  // A key from the earlier producer is not proof about the projected records,
  // even when a real key transfer exists for the same source field.
  assert_true(
    check(
      body(key=None),
      projected,
      Some(original_keys),
      installed,
      None,
      limits(),
    )
    is Err({ kind: InputKeyOwnerMismatch, .. }),
  )
  let checked = check(
    body(key=None),
    projected,
    Some(transferred),
    installed,
    None,
    limits(),
  ).unwrap()
  assert_eq(key_count(checked), 1)
  assert_eq(key_at(checked, 0).unwrap().field, @schema.Unqualified("ticket"))
  assert_true(
    physical_equal(
      input_records(checked),
      @evidence.key_set_records(transferred),
    ),
  )
  assert_true(
    physical_equal(
      key_witness(checked),
      @evidence.key_witness_at(transferred, 0).unwrap(),
    ),
  )
}
