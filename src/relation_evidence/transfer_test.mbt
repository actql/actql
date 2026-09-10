///|
fn checked(
  op : @relation.Operation,
  text : String,
  key : @relation_evidence.KeyedRelation,
) -> @relation.CheckedOperation {
  @relation.check(
    op,
    cursor(text),
    @carrier.complete_schema(@relation_evidence.keyed_records(key)).unwrap(),
    None,
    {
      max_work: 10000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "key transfer keeps composite alias alternatives and rejects unrelated schema handles" {
  let key = @relation_evidence.declare_primary_key(
    cursor("[\"b\",\"a\"]"),
    rows(false),
    { max_fields: 2, max_name_bytes: 2, },
  ).unwrap()
  let op = checked(
    Select,
    "[{\"x\":\"b\"},{\"y\":\"b\"},{\"p\":\"a\"},{\"q\":\"a\"}]",
    key,
  )
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  let transfer = @relation_evidence.transfer_unary(key, op, caps).unwrap()
  let projected = transfer.key.unwrap()
  assert_eq(@relation_evidence.key_field_count(projected), 2)
  assert_eq(@relation_evidence.key_alias_count(projected, 0), 2)
  assert_eq(@relation_evidence.key_alias_count(projected, 1), 2)
  let exact : @relation_evidence.TransferLimits = {
    max_work: transfer.work,
    max_name_bytes: transfer.name_bytes,
  }
  assert_true(@relation_evidence.transfer_unary(key, op, exact) is Ok(_))
  for
    limit in [
      { ..exact, max_work: transfer.work - 1, },
      { ..exact, max_name_bytes: transfer.name_bytes - 1, },
    ] {
    assert_true(
      @relation_evidence.transfer_unary(key, op, limit)
      is Err({ kind: LimitExceeded, .. }),
    )
  }
  let drop = checked(Drop, "[\"x\",\"p\"]", projected)
  let retained = @relation_evidence.transfer_unary(projected, drop, caps).unwrap().key.unwrap()
  assert_eq(
    @relation_evidence.declared_key_field_at(retained, 0).unwrap().name,
    Unqualified("b"),
  )
  assert_eq(
    @relation_evidence.declared_key_field_at(retained, 1).unwrap().name,
    Unqualified("a"),
  )
  assert_true(
    @carrier.lookup(
      @relation_evidence.declared_records(retained),
      Unqualified("a"),
    )
    is Present(_),
  )
  assert_true(
    @carrier.lookup(
      @relation_evidence.keyed_records(retained),
      Unqualified("a"),
    )
    is Absent,
  )
  assert_eq(
    @relation_evidence.key_field_at(retained, 0).unwrap().name,
    Unqualified("y"),
  )
  assert_eq(
    @relation_evidence.key_field_at(retained, 1).unwrap().name,
    Unqualified("q"),
  )
  let erase = checked(Derive, "[{\"q\":\"'replacement'\"}]", retained)
  assert_true(
    @relation_evidence.transfer_unary(retained, erase, caps).unwrap().key
    is None,
  )
  assert_eq(@relation_evidence.key_alias_count(projected, 0), 2)
  let other = @relation_evidence.declare_primary_key(
    cursor("[\"b\",\"a\"]"),
    rows(false),
    { max_fields: 2, max_name_bytes: 2, },
  ).unwrap()
  assert_true(
    @relation_evidence.transfer_unary(other, op, caps)
    is Err({ kind: InputContractMismatch, .. }),
  )
}
