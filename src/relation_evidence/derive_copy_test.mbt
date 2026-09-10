///|
test "derive copies preserve key aliases with snapshot and prior-slot resolution" {
  let a = key(rows(false), "[\"a\"]")
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  for
    text in [
      "{\"x\":\"a\",\"y\":{\"field\":\"a\"}}", "[{\"x\":\"a\"},{\"a\":\"0\"},{\"y\":\"x\"}]",
      "[{\"a\":\"(a)\"},{\"x\":\"a\"},{\"y\":\"x\"}]",
    ] {
    let op = checked(Derive, text, a)
    let result = @relation_evidence.transfer_unary(a, op, caps).unwrap()
    let transferred = result.key.unwrap()
    let names = Array::makei(
      @relation_evidence.key_alias_count(transferred, 0),
      i => @relation_evidence.key_alias_at(transferred, 0, i).unwrap().name,
    )
    assert_true(names.contains(Unqualified("x")))
    assert_true(names.contains(Unqualified("y")))
    let drop = checked(Drop, "[\"a\",\"x\"]", transferred)
    let remaining = @relation_evidence.transfer_unary(transferred, drop, caps).unwrap().key.unwrap()
    assert_eq(
      @relation_evidence.key_field_at(remaining, 0).unwrap().name,
      Unqualified("y"),
    )
    assert_eq(
      @relation_evidence.declared_key_field_at(remaining, 0).unwrap().name,
      Unqualified("a"),
    )
    let exact : @relation_evidence.TransferLimits = {
      max_work: result.work,
      max_name_bytes: result.name_bytes,
    }
    assert_true(@relation_evidence.transfer_unary(a, op, exact) is Ok(_))
    for
      cap in [
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_name_bytes: exact.max_name_bytes - 1, },
      ] {
      assert_true(
        @relation_evidence.transfer_unary(a, op, cap)
        is Err({ kind: LimitExceeded, .. }),
      )
    }
  }
}

///|
test "computed values and copies of overwritten slots do not invent key lineage" {
  let a = key(rows(false), "[\"a\"]")
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  for
    text in [
      "[{\"a\":\"'replacement'\"},{\"x\":\"a\"}]", "[{\"x\":\"a || ''\"},{\"a\":\"'replacement'\"}]",
      "[{\"x\":{\"template\":\"{a}\"}},{\"a\":\"'replacement'\"}]",
    ] {
    let op = checked(Derive, text, a)
    assert_true(
      @relation_evidence.transfer_unary(a, op, caps).unwrap().key is None,
    )
  }
  let input = rows(false)
  let a = key(input, "[\"a\"]")
  let b = key(input, "[\"b\"]")
  let set = @relation_evidence.collect_keys(cursor("null"), input, [a, b], {
    max_keys: 2,
    max_work: 100,
    max_name_bytes: 100,
  }).unwrap()
  let op = checked(Derive, "[{\"x\":\"a\"},{\"a\":\"b\"},{\"b\":\"x\"}]", a)
  let result = @relation_evidence.transfer_keys(set, op, caps).unwrap().keys
  assert_eq(@relation_evidence.key_witness_count(result), 2)
  let first = @relation_evidence.key_witness_at(result, 0).unwrap()
  let second = @relation_evidence.key_witness_at(result, 1).unwrap()
  assert_eq(@relation_evidence.key_alias_count(first, 0), 2)
  assert_eq(
    @relation_evidence.key_field_at(second, 0).unwrap().name,
    Unqualified("a"),
  )
}
