///|
test "key coverage requires every component and preserves alias provenance" {
  let original = key(rows(false), "[\"b\",\"a\"]")
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  let op = checked(
    Select,
    "[{\"x\":\"b\"},{\"y\":\"b\"},{\"p\":\"a\"},{\"q\":\"a\"}]",
    original,
  )
  let projected = @relation_evidence.transfer_unary(original, op, caps).unwrap().key.unwrap()
  let set = @relation_evidence.singleton_key(projected)
  for
    fields in [
      [],
      [@row.Unqualified("x")],
      [Unqualified("x"), Unqualified("x")],
      [Qualified(Left, "x"), Unqualified("p")],
    ] {
    assert_true(
      @relation_evidence.select_covered_key(cursor("null"), set, fields, caps).unwrap().key
      is None,
    )
  }
  let fields = [@row.Unqualified("y"), Unqualified("q"), Unqualified("y")]
  let selection = @relation_evidence.select_covered_key(
    cursor("null"),
    set,
    fields,
    caps,
  ).unwrap()
  fields.clear()
  let selected = selection.key.unwrap()
  assert_eq(
    @relation_evidence.key_field_at(selected, 0).unwrap().name,
    Unqualified("q"),
  )
  assert_eq(
    @relation_evidence.key_field_at(selected, 1).unwrap().name,
    Unqualified("y"),
  )
  assert_eq(
    @relation_evidence.declared_key_field_at(selected, 0).unwrap().name,
    Unqualified("b"),
  )
  assert_eq(
    @relation_evidence.key_pending(selected),
    @relation_evidence.key_pending(original),
  )
  assert_eq(@relation_evidence.key_alias_count(projected, 0), 2)
  let exact : @relation_evidence.TransferLimits = {
    max_work: selection.work,
    max_name_bytes: selection.name_bytes,
  }
  let query = [@row.Unqualified("y"), Unqualified("q"), Unqualified("y")]
  assert_true(
    @relation_evidence.select_covered_key(cursor("null"), set, query, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_name_bytes: exact.max_name_bytes - 1, },
    ] {
    assert_true(
      @relation_evidence.select_covered_key(cursor("null"), set, query, cap)
      is Err({ kind: LimitExceeded, .. }),
    )
  }
}

///|
test "coverage retains nullable grouping keys without granting scalar completion" {
  let anchor = key(rows(true), "[\"a\"]")
  let op = checked(Group, "{\"by\":[\"b\"],\"aggregates\":{}}", anchor)
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  let set = @relation_evidence.advance_keys(None, op, caps).unwrap().keys
  let selected = @relation_evidence.select_covered_key(
    cursor("null"),
    set,
    [Unqualified("b")],
    caps,
  ).unwrap().key.unwrap()
  assert_true(
    @relation_evidence.key_field_at(selected, 0).unwrap().contract.unwrap().nullable,
  )
  assert_eq(@relation_evidence.key_origin(selected), GroupResult)
  assert_eq(@relation_evidence.key_pending(selected), [ValidateKeyProducer])
  assert_true(
    @relation_evidence.select_key(cursor("null"), set, ScalarIdentity, caps).unwrap().key
    is None,
  )
}

///|
test "coverage searches all witnesses and chooses a canonical covered tuple" {
  let input = rows(false)
  let a = key(input, "[\"a\"]")
  let b = key(input, "[\"b\"]")
  let ab = key(input, "[\"a\",\"b\"]")
  for keys in [[a, ab, b], [b, ab, a]] {
    let set = @relation_evidence.collect_keys(cursor("null"), input, keys, {
      max_keys: 3,
      max_work: 100,
      max_name_bytes: 100,
    }).unwrap()
    for
      fields in [[@row.Unqualified("b")], [Unqualified("b"), Unqualified("a")]] {
      let result = @relation_evidence.select_covered_key(
        cursor("null"),
        set,
        fields,
        { max_work: 100, max_name_bytes: 100, },
      ).unwrap().key.unwrap()
      assert_eq(@relation_evidence.key_field_count(result), 1)
      assert_eq(
        @relation_evidence.key_field_at(result, 0).unwrap().name,
        if fields.length() == 1 {
          Unqualified("b")
        } else {
          Unqualified("a")
        },
      )
    }
  }
}
