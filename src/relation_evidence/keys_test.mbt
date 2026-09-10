///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn rows(nullable : Bool) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("a"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (Unqualified("b"), Some(@contract.primitive(NumberType, nullable~))),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=10,
    ).unwrap(),
  )
}

///|
test "declared keys preserve tuple order and retain conditional admission obligations" {
  let c = @relation_evidence.declare_primary_key(
    cursor("[\"b\",\"a\"]"),
    rows(false),
    { max_fields: 2, max_name_bytes: 2, },
  ).unwrap()
  assert_eq(
    @relation_evidence.key_field_at(c, 0).unwrap().name,
    Unqualified("b"),
  )
  assert_true(@relation_evidence.key_field_at(c, -1) is None)
  assert_true(@relation_evidence.key_field_at(c, 2) is None)
  assert_true(
    @relation_evidence.key_pending(c).contains(
      ValidateWholeTupleUniquenessAfterInputNormalization,
    ),
  )
  assert_eq(@relation_evidence.key_usage(c), { fields: 2, name_bytes: 2, })
  let boundaries : Array[@relation_evidence.Limits] = [
    { max_fields: 1, max_name_bytes: 2, },
    { max_fields: 2, max_name_bytes: 1, },
  ]
  for cap in boundaries {
    assert_true(
      @relation_evidence.declare_primary_key(
        cursor("[\"b\",\"a\"]"),
        rows(false),
        cap,
      )
      is Err({ kind: LimitExceeded, .. }),
    )
  }
}

///|
test "declared keys reject known violations but do not manufacture unknown types" {
  let caps : @relation_evidence.Limits = {
    max_fields: 10,
    max_name_bytes: 100,
  }
  assert_true(
    @relation_evidence.declare_primary_key(cursor("[]"), rows(false), caps)
    is Err({ kind: EmptyKey, .. }),
  )
  let duplicate = @relation_evidence.declare_primary_key(
    cursor("[\"a\",\"a\"]"),
    rows(false),
    caps,
  ).unwrap_err()
  assert_eq(duplicate.kind, DuplicateKeyField("a"))
  assert_eq(duplicate.path, [@source.Index(1)])
  assert_true(
    @relation_evidence.declare_primary_key(cursor("[\"b\"]"), rows(true), caps)
    is Err({ kind: InvalidKeyType("b"), .. }),
  )
  assert_true(
    @relation_evidence.declare_primary_key(
      cursor("[\"missing\"]"),
      rows(false),
      caps,
    )
    is Err({ kind: MissingKeyField("missing"), .. }),
  )
  let c = @relation_evidence.declare_primary_key(
    cursor("[\"missing\"]"),
    @carrier.relation(@carrier.unknown_rows()),
    caps,
  ).unwrap()
  assert_true(@relation_evidence.key_field_at(c, 0).unwrap().contract is None)
  assert_eq(@carrier.field_set(@relation_evidence.keyed_records(c)), Open)
}
