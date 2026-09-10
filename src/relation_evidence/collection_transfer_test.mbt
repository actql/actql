///|
test "collection transfer loses only affected witnesses and shares output contracts" {
  let input = rows(false)
  let a = key(input, "[\"a\"]")
  let b = key(input, "[\"b\"]")
  let set = @relation_evidence.collect_keys(cursor("null"), input, [a, b], {
    max_keys: 2,
    max_work: 100,
    max_name_bytes: 100,
  }).unwrap()
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  let projection = checked(Select, "[{\"x\":\"a\"},{\"y\":\"a\"},\"b\"]", a)
  let projected = @relation_evidence.transfer_keys(set, projection, caps).unwrap()
  assert_eq(@relation_evidence.key_witness_count(projected.keys), 2)
  let first = @relation_evidence.key_witness_at(projected.keys, 0).unwrap()
  assert_eq(@relation_evidence.key_alias_count(first, 0), 2)
  // Collection validation accepts every result against the one shared output.
  ignore(
    @relation_evidence.collect_keys(
      cursor("null"),
      @carrier.relation(@relation_evidence.key_set_records(projected.keys)),
      [first, @relation_evidence.key_witness_at(projected.keys, 1).unwrap()],
      { max_keys: 2, max_work: 100, max_name_bytes: 100, },
    ).unwrap(),
  )
  let drop = checked(Drop, "[\"x\",\"y\"]", first)
  let remaining = @relation_evidence.transfer_keys(projected.keys, drop, caps).unwrap().keys
  assert_eq(@relation_evidence.key_witness_count(remaining), 1)
  let survivor = @relation_evidence.key_witness_at(remaining, 0).unwrap()
  assert_eq(
    @relation_evidence.key_field_at(survivor, 0).unwrap().name,
    Unqualified("b"),
  )
  let overwrite = checked(Derive, "[{\"b\":\"0\"}]", survivor)
  let empty = @relation_evidence.transfer_keys(remaining, overwrite, caps).unwrap().keys
  assert_eq(@relation_evidence.key_witness_count(empty), 0)
  assert_true(
    @carrier.lookup(@relation_evidence.key_set_records(empty), Unqualified("b"))
    is Present(_),
  )
  assert_eq(@relation_evidence.key_witness_count(set), 2)
  assert_eq(
    @relation_evidence.key_field_at(a, 0).unwrap().name,
    Unqualified("a"),
  )
  let exact : @relation_evidence.TransferLimits = {
    max_work: projected.work,
    max_name_bytes: projected.name_bytes,
  }
  assert_true(@relation_evidence.transfer_keys(set, projection, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_name_bytes: exact.max_name_bytes - 1, },
    ] {
    assert_true(
      @relation_evidence.transfer_keys(set, projection, cap)
      is Err({ kind: LimitExceeded, .. }),
    )
  }
  let unrelated = checked(Select, "[\"a\",\"b\"]", key(rows(false), "[\"a\"]"))
  assert_true(
    @relation_evidence.transfer_keys(set, unrelated, caps)
    is Err({ kind: InputContractMismatch, .. }),
  )
}

///|
test "mapping preparation and output schema allocation do not multiply by witness count" {
  let input = rows(false)
  let a = key(input, "[\"a\"]")
  let b = key(input, "[\"b\"]")
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  let one = @relation_evidence.collect_keys(cursor("null"), input, [a], {
    max_keys: 2,
    max_work: 100,
    max_name_bytes: 100,
  }).unwrap()
  let two = @relation_evidence.collect_keys(cursor("null"), input, [a, b], {
    max_keys: 2,
    max_work: 100,
    max_name_bytes: 100,
  }).unwrap()
  let op = checked(Select, "[{\"x\":\"a\"},{\"y\":\"a\"},{\"z\":\"b\"}]", a)
  let first = @relation_evidence.transfer_keys(one, op, caps).unwrap()
  let second = @relation_evidence.transfer_keys(two, op, caps).unwrap()
  // Extra witness + component + alias + emitted alias; no second projection scan.
  assert_eq(second.work - first.work, 4)
  assert_eq(second.name_bytes - first.name_bytes, 2)
  for text in ["true"] {
    let op = checked(Distinct, text, a)
    let retained = @relation_evidence.transfer_keys(two, op, caps).unwrap().keys
    assert_eq(@relation_evidence.key_witness_count(retained), 2)
  }
}
