///|
test "event clock encoding preserves timestamp payload without fabricating a numeric field" {
  for
    (kind, encoding) in [
      (@value.NumberType, @carrier_contract.Milliseconds),
      (@value.TimestampType, @carrier_contract.UtcTimestamp),
    ] {
    let clock = @value.primitive(kind, nullable=false)
    let records = rows(
      [
        (
          @row.Unqualified("id"),
          Some(@value.primitive(NumberType, nullable=false)),
        ),
        (@row.Unqualified("occurred_at"), Some(clock)),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap()
    guard events(records, id=Unqualified("id"), time=Unqualified("occurred_at")).unwrap()
      is EventValue(e) else {
      abort("events")
    }
    assert_eq(event_clock_encoding(e), encoding)
    assert_true(@value.type_equal(event_time(e).contract.unwrap(), clock, 10))
    assert_eq(event_identity(e).name, Unqualified("id"))
    assert_true(
      lookup(event_records(e), Unqualified("event_time_ms")) is Absent,
    )
    assert_eq(field_count(event_records(e)), 2)
  }
}

///|
test "event identities preserve non-null comparable semantic domains" {
  let domains = [
    @value.primitive(StringType, nullable=false),
    @value.primitive(NumberType, nullable=false),
    @value.primitive(BooleanType, nullable=false),
    @value.primitive(DateType, nullable=false),
    @value.primitive(TimestampType, nullable=false),
    @value.decimal_contract(38, 19, nullable=false).unwrap(),
    @value.primitive(JsonType, nullable=false),
    @value.vector_contract(3, nullable=false).unwrap(),
    @value.array_contract(
      @value.primitive(NumberType, nullable=false),
      nullable=false,
    ).unwrap(),
    @value.object_contract([], nullable=false, max_fields=0, max_name_bytes=0).unwrap(),
  ]
  for i in 0..<domains.length() {
    let domain = domains[i]
    for nullable in [false, true] {
      let contract = @value.with_nullability(domain, nullable)
      let id = @row.Unqualified("id")
      let time = @row.Unqualified("at")
      let records = rows(
        [
          (id, Some(contract)),
          (time, Some(@value.primitive(NumberType, nullable=false))),
        ],
        field_set=Closed,
        max_fields=2,
        max_name_bytes=4,
      ).unwrap()
      let result = events(records, id~, time~)
      if !nullable && i < 6 {
        guard result.unwrap() is EventValue(e) else { fail("expected events") }
        assert_true(
          @value.type_equal(e.identity.contract.unwrap(), contract, 100),
        )
      } else {
        assert_eq(result.unwrap_err(), InvalidRole(id))
      }
    }
  }
}

///|
test "unknown carriers retain kind and are not coerced into relation schemas" {
  let kinds : Array[Kind] = [RelationKind, GraphKind, EventsKind, VectorsKind]
  for k in kinds {
    let carrier = unknown_carrier(k)
    assert_eq(kind(carrier), k)
    assert_eq(relation_rows(carrier) is Some(_), k == RelationKind)
  }
}

///|
test "definition label domains are owned canonical sets, not graph data evidence" {
  let id = @value.primitive(StringType, nullable=false)
  let empty = rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  let labels = ["z", "a"]
  let definition = property_node_definition(
    "N",
    [id],
    empty,
    labels,
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  labels.clear()
  assert_eq(property_definition_labels(definition), ["a", "z"])
  let copy = property_definition_labels(definition)
  copy.clear()
  assert_eq(property_definition_labels(definition), ["a", "z"])
  assert_true(
    property_node_definition(
      "N",
      [id],
      empty,
      ["a", "a"],
      max_fields=2,
      max_name_bytes=3,
    )
    is Err(DuplicateLabel),
  )
  assert_true(
    property_node_definition(
      "N",
      [id],
      empty,
      ["e\u{301}"],
      max_fields=1,
      max_name_bytes=4,
    )
    is Err(InvalidLabel),
  )
  assert_true(
    property_node_definition(
      "N",
      [id],
      empty,
      ["a"],
      max_fields=0,
      max_name_bytes=2,
    )
    is Err(LimitExceeded),
  )
}

///|
test "events require a known clock encoding and preserve unknown payload evidence" {
  let id = @row.Unqualified("id")
  let clock = @row.Unqualified("time")
  let fields = rows(
    [
      (id, Some(@value.primitive(StringType, nullable=false))),
      (clock, Some(@value.primitive(NumberType, nullable=false))),
    ],
    field_set=Open,
    max_fields=2,
    max_name_bytes=6,
  ).unwrap()
  guard events(fields, id~, time=clock).unwrap() is EventValue(e) else {
    abort("event kind")
  }
  assert_true(lookup(e.records, @row.Unqualified("payload")) is Unknown)
  assert_true(events(unknown_rows(), id~, time=clock) is Err(UnknownRole(_)))
  let timestamp = rows(
    [
      (id, Some(@value.primitive(StringType, nullable=false))),
      (clock, Some(@value.primitive(TimestampType, nullable=false))),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=6,
  ).unwrap()
  guard events(timestamp, id~, time=clock).unwrap() is EventValue(t) else {
    abort("event kind")
  }
  assert_eq(t.clock_encoding, @carrier_contract.UtcTimestamp)
}

///|
test "vector contracts retain ordered tuple identity and checked dimension" {
  let a = @row.Unqualified("a")
  let b = @row.Unqualified("b")
  let v = @row.Unqualified("v")
  let rows = rows(
    [
      (a, Some(@value.primitive(StringType, nullable=false))),
      (b, Some(@value.primitive(NumberType, nullable=false))),
      (v, Some(@value.vector_contract(3, nullable=false).unwrap())),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=3,
  ).unwrap()
  let ids = [b, a]
  guard vectors(rows, ids~, components=v, max_identity_fields=2).unwrap()
    is VectorValue(vector) else {
    abort("vector kind")
  }
  ids.clear()
  assert_eq(vector_dimensions(vector), 3)
  assert_eq(vector_identities(vector).map(f => f.name), [b, a])
  let copy = vector_identities(vector)
  copy.clear()
  assert_eq(vector_identities(vector).length(), 2)
  assert_true(
    vectors(rows, ids=[a, a], components=v, max_identity_fields=2)
    is Err(DuplicateRole(_)),
  )
  assert_true(
    vectors(rows, ids=[], components=v, max_identity_fields=2)
    is Err(InvalidIdentity),
  )
  assert_true(
    vectors(rows, ids=[a], components=v, max_identity_fields=0)
    is Err(LimitExceeded),
  )
}
