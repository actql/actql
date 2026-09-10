///|
test "sole string completion counts distinct fields rather than witnesses" {
  let input = rows(false)
  let a = key(input, "[\"a\"]")
  let b = key(input, "[\"b\"]")
  let ab = key(input, "[\"a\",\"b\"]")
  let set = @relation_evidence.collect_keys(
    cursor("null"),
    input,
    [a, a, b, ab],
    { max_keys: 4, max_work: 100, max_name_bytes: 100, },
  ).unwrap()
  let result = @relation_evidence.select_sole_string_key(cursor("null"), set, {
    max_work: 100,
    max_name_bytes: 100,
  }).unwrap()
  assert_eq(
    @relation_evidence.key_field_at(result.key.unwrap(), 0).unwrap().name,
    Unqualified("a"),
  )
  let exact : @relation_evidence.TransferLimits = {
    max_work: result.work,
    max_name_bytes: result.name_bytes,
  }
  assert_true(
    @relation_evidence.select_sole_string_key(cursor("null"), set, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_name_bytes: exact.max_name_bytes - 1, },
    ] {
    assert_true(
      @relation_evidence.select_sole_string_key(cursor("null"), set, cap)
      is Err({ kind: LimitExceeded, .. }),
    )
  }
  let op = checked(Select, "[{\"x\":\"a\"},{\"y\":\"a\"},\"b\"]", a)
  let aliases = @relation_evidence.transfer_keys(set, op, {
      max_work: 1000,
      max_name_bytes: 1000,
    }).unwrap().keys
  assert_true(
    @relation_evidence.select_sole_string_key(cursor("null"), aliases, {
      max_work: 100,
      max_name_bytes: 100,
    }).unwrap().key
    is None,
  )
  let first = @relation_evidence.key_witness_at(aliases, 0).unwrap()
  let drop = checked(Drop, "[\"x\"]", first)
  let remaining = @relation_evidence.transfer_keys(aliases, drop, {
      max_work: 1000,
      max_name_bytes: 1000,
    }).unwrap().keys
  let key = @relation_evidence.select_sole_string_key(
    cursor("null"),
    remaining,
    { max_work: 100, max_name_bytes: 100, },
  ).unwrap().key.unwrap()
  assert_eq(
    @relation_evidence.key_field_at(key, 0).unwrap().name,
    Unqualified("y"),
  )
  assert_eq(
    @relation_evidence.declared_key_field_at(key, 0).unwrap().name,
    Unqualified("a"),
  )
}
