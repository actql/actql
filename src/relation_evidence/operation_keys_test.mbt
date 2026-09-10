///|
test "checked operation keys retain producer provenance instead of input assertions" {
  let input = rows(false)
  let anchor = key(input, "[\"a\"]")
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  let cases : Array[
    (@relation.Operation, String, @relation_evidence.KeyOrigin, Int),
  ] = [
    (Group, "{\"by\":[\"a\"],\"aggregates\":{}}", GroupResult, 1),
    (Distinct, "[\"a\"]", DistinctResult, 1),
    (Distinct, "true", DistinctResult, 2),
    (
      DedupeRows,
      "{\"by\":[\"a\",\"a\"],\"order_by\":[{\"b\":\"asc\"}]}",
      DedupeResult,
      1,
    ),
    (AssertRows, "{\"unique_by\":[\"a\",\"b\"]}", UniqueAssertion, 2),
    (
      Pivot,
      "{\"index\":[\"a\"],\"column\":\"a\",\"value\":\"b\",\"values\":[],\"aggregate\":\"sum\"}",
      PivotResult,
      1,
    ),
  ]
  for (operation, body, origin, count) in cases {
    let op = checked(operation, body, anchor)
    let result = @relation_evidence.advance_keys(None, op, caps).unwrap()
    assert_eq(@relation_evidence.key_witness_count(result.keys), 1)
    let produced = @relation_evidence.key_witness_at(result.keys, 0).unwrap()
    assert_eq(@relation_evidence.key_origin(produced), origin)
    assert_eq(@relation_evidence.key_field_count(produced), count)
    assert_true(@relation_evidence.key_producer(produced) is Some(_))
    assert_eq(@relation_evidence.key_pending(produced), [ValidateKeyProducer])
    let filtered = checked(Filter, "\"true\"", produced)
    let retained = @relation_evidence.advance_keys(
        Some(result.keys),
        filtered,
        caps,
      ).unwrap().keys
    let next = @relation_evidence.key_witness_at(retained, 0).unwrap()
    assert_eq(@relation_evidence.key_origin(next), origin)
    assert_eq(
      @relation.operation(@relation_evidence.key_producer(next).unwrap()),
      operation,
    )
    let exact : @relation_evidence.TransferLimits = {
      max_work: result.work,
      max_name_bytes: result.name_bytes,
    }
    assert_true(@relation_evidence.advance_keys(None, op, exact) is Ok(_))
    for
      cap in [
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_name_bytes: exact.max_name_bytes - 1, },
      ] {
      assert_true(
        @relation_evidence.advance_keys(None, op, cap)
        is Err({ kind: LimitExceeded, .. }),
      )
    }
  }
}

///|
test "generated nullable keys are retained but cannot complete non-null identities" {
  let anchor = key(rows(true), "[\"a\"]")
  let op = checked(Group, "{\"by\":[\"b\"],\"aggregates\":{}}", anchor)
  let caps : @relation_evidence.TransferLimits = {
    max_work: 1000,
    max_name_bytes: 1000,
  }
  let result = @relation_evidence.advance_keys(None, op, caps).unwrap().keys
  assert_eq(@relation_evidence.key_witness_count(result), 1)
  assert_true(
    @relation_evidence.key_field_at(
      @relation_evidence.key_witness_at(result, 0).unwrap(),
      0,
    ).unwrap().contract.unwrap().nullable,
  )
  assert_true(
    @relation_evidence.select_key(cursor("null"), result, CanonicalOrder, caps).unwrap().key
    is None,
  )
  let global = checked(Group, "{\"by\":[],\"aggregates\":{}}", anchor)
  assert_eq(
    @relation_evidence.key_witness_count(
      @relation_evidence.advance_keys(None, global, caps).unwrap().keys,
    ),
    0,
  )
  let op = checked(AssertRows, "{\"unique_by\":[\"a\"]}", anchor)
  let prior = @relation_evidence.singleton_key(anchor)
  let result = @relation_evidence.advance_keys(Some(prior), op, caps).unwrap().keys
  assert_eq(@relation_evidence.key_witness_count(result), 2)
  assert_eq(
    @relation_evidence.key_origin(
      @relation_evidence.key_witness_at(result, 0).unwrap(),
    ),
    InputDeclaration,
  )
  assert_eq(
    @relation_evidence.key_origin(
      @relation_evidence.key_witness_at(result, 1).unwrap(),
    ),
    UniqueAssertion,
  )
}
