///|
fn key(
  input : @carrier.Carrier,
  text : String,
) -> @relation_evidence.KeyedRelation {
  @relation_evidence.declare_primary_key(cursor(text), input, {
    max_fields: 10,
    max_name_bytes: 100,
  }).unwrap()
}

///|
test "reference ordering and scalar identity have distinct eligibility and UTF16 order" {
  let reference = @contract.read_checked(
    cursor(
      "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
    ),
    { max_nodes: 20, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let number = @contract.primitive(NumberType, nullable=false)
  let input = @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("a"), Some(reference)),
        (Unqualified("😀"), Some(number)),
        (Unqualified("\uE000"), Some(number)),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=20,
    ).unwrap(),
  )
  let set = @relation_evidence.collect_keys(
    cursor("null"),
    input,
    [
      key(input, "[\"\uE000\"]"),
      key(input, "[\"😀\"]"),
      key(input, "[\"a\"]"),
    ],
    { max_keys: 3, max_work: 100, max_name_bytes: 100, },
  ).unwrap()
  let caps : @relation_evidence.TransferLimits = {
    max_work: 100,
    max_name_bytes: 100,
  }
  let canonical = @relation_evidence.select_key(
    cursor("null"),
    set,
    CanonicalOrder,
    caps,
  ).unwrap().key.unwrap()
  assert_eq(
    @relation_evidence.key_field_at(canonical, 0).unwrap().name,
    Unqualified("a"),
  )
  let scalar = @relation_evidence.select_key(
    cursor("null"),
    set,
    ScalarIdentity,
    caps,
  ).unwrap().key.unwrap()
  assert_eq(
    @relation_evidence.key_field_at(scalar, 0).unwrap().name,
    Unqualified("😀"),
  )
}

///|
test "canonical key selection is independent of witness and declaration order" {
  let input = rows(false)
  let ab = key(input, "[\"b\",\"a\"]")
  let a = key(input, "[\"a\"]")
  let b = key(input, "[\"b\"]")
  let caps : @relation_evidence.KeySetLimits = {
    max_keys: 10,
    max_work: 100,
    max_name_bytes: 100,
  }
  let selection_caps : @relation_evidence.TransferLimits = {
    max_work: 100,
    max_name_bytes: 100,
  }
  for witnesses in [[ab, b, a], [a, ab, b], [b, a, ab, a]] {
    let set = @relation_evidence.collect_keys(
      cursor("null"),
      input,
      witnesses,
      caps,
    ).unwrap()
    let selected = @relation_evidence.select_key(
      cursor("null"),
      set,
      CanonicalOrder,
      selection_caps,
    ).unwrap().key.unwrap()
    assert_eq(@relation_evidence.key_field_count(selected), 1)
    assert_eq(
      @relation_evidence.key_field_at(selected, 0).unwrap().name,
      Unqualified("a"),
    )
  }
  let set = @relation_evidence.collect_keys(cursor("null"), input, [ab], caps).unwrap()
  let selected = @relation_evidence.select_key(
    cursor("null"),
    set,
    ScalarIdentity,
    selection_caps,
  ).unwrap().key.unwrap()
  assert_eq(
    @relation_evidence.key_field_at(selected, 0).unwrap().name,
    Unqualified("a"),
  )
  assert_eq(
    @relation_evidence.declared_key_field_at(selected, 0).unwrap().name,
    Unqualified("b"),
  )
  assert_eq(
    @relation_evidence.key_field_at(ab, 0).unwrap().name,
    Unqualified("b"),
  )
}

///|
test "key sets own their witness list and enforce exact collection and selection budgets" {
  let input = rows(false)
  let a = key(input, "[\"a\"]")
  let witnesses = [a]
  let caps : @relation_evidence.KeySetLimits = {
    max_keys: 1,
    max_work: 3,
    max_name_bytes: 1,
  }
  let set = @relation_evidence.collect_keys(
    cursor("null"),
    input,
    witnesses,
    caps,
  ).unwrap()
  witnesses.clear()
  assert_eq(@relation_evidence.key_witness_count(set), 1)
  assert_eq(@relation_evidence.key_set_usage(set), (3, 1))
  assert_true(@relation_evidence.key_witness_at(set, -1) is None)
  assert_true(@relation_evidence.key_witness_at(set, 1) is None)
  for
    limit in [
      { ..caps, max_keys: 0, },
      { ..caps, max_work: 2, },
      { ..caps, max_name_bytes: 0, },
    ] {
    assert_true(
      @relation_evidence.collect_keys(cursor("null"), input, [a], limit)
      is Err({ kind: LimitExceeded, .. }),
    )
  }
  assert_true(
    @relation_evidence.collect_keys(cursor("null"), rows(false), [a], caps)
    is Err({ kind: InputContractMismatch, .. }),
  )
  let exact : @relation_evidence.TransferLimits = {
    max_work: 4,
    max_name_bytes: 1,
  }
  let selected = @relation_evidence.select_key(
    cursor("null"),
    set,
    CanonicalOrder,
    exact,
  ).unwrap()
  assert_eq((selected.work, selected.name_bytes), (4, 1))
  for limit in [{ ..exact, max_work: 3, }, { ..exact, max_name_bytes: 0, }] {
    assert_true(
      @relation_evidence.select_key(cursor("null"), set, CanonicalOrder, limit)
      is Err({ kind: LimitExceeded, .. }),
    )
  }
}

///|
test "empty and unknown candidate collections cannot supply typed completion" {
  let input = @carrier.relation(@carrier.unknown_rows())
  let caps : @relation_evidence.KeySetLimits = {
    max_keys: 1,
    max_work: 100,
    max_name_bytes: 100,
  }
  for witnesses in [[], [key(input, "[\"missing\"]")]] {
    let set = @relation_evidence.collect_keys(
      cursor("null"),
      input,
      witnesses,
      caps,
    ).unwrap()
    let uses : Array[@relation_evidence.KeyUse] = [
      CanonicalOrder,
      ScalarIdentity,
    ]
    for usage in uses {
      assert_true(
        @relation_evidence.select_key(cursor("null"), set, usage, {
          max_work: 100,
          max_name_bytes: 100,
        }).unwrap().key
        is None,
      )
    }
  }
}

///|
test "completion chooses canonical alias without expanding combinations or losing alternatives" {
  let original = key(rows(false), "[\"b\",\"a\"]")
  let op = checked(
    Select,
    "[{\"z\":\"b\"},{\"y\":\"b\"},{\"q\":\"a\"},{\"p\":\"a\"}]",
    original,
  )
  let transferred = @relation_evidence.transfer_unary(original, op, {
    max_work: 1000,
    max_name_bytes: 1000,
  }).unwrap().key.unwrap()
  let input = @carrier.relation(@relation_evidence.keyed_records(transferred))
  let set = @relation_evidence.collect_keys(
    cursor("null"),
    input,
    [transferred],
    { max_keys: 1, max_work: 100, max_name_bytes: 100, },
  ).unwrap()
  let selected = @relation_evidence.select_key(
    cursor("null"),
    set,
    CanonicalOrder,
    { max_work: 100, max_name_bytes: 100, },
  ).unwrap().key.unwrap()
  assert_eq(
    @relation_evidence.key_field_at(selected, 0).unwrap().name,
    Unqualified("p"),
  )
  assert_eq(
    @relation_evidence.key_field_at(selected, 1).unwrap().name,
    Unqualified("y"),
  )
  assert_eq(@relation_evidence.key_alias_count(selected, 0), 2)
  assert_eq(@relation_evidence.key_alias_count(selected, 1), 2)
  assert_eq(
    @relation_evidence.declared_key_field_at(selected, 0).unwrap().name,
    Unqualified("b"),
  )
}
