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
test "graph label domains are owned canonical sets, not graph data evidence" {
  let id = @value.primitive(StringType, nullable=false)
  let labels = ["z", "a"]
  let carrier = graph(
    id,
    unknown_rows(),
    unknown_rows(),
    labels=Some(labels),
    max_labels=2,
    max_label_bytes=2,
  ).unwrap()
  labels.clear()
  guard carrier is GraphValue(g) else { abort("graph kind") }
  assert_eq(graph_labels(g).unwrap(), ["a", "z"])
  let copy = graph_labels(g).unwrap()
  copy.clear()
  assert_eq(graph_labels(g).unwrap(), ["a", "z"])
  assert_true(complete_schema(graph_node_properties(g)) is None)
  assert_true(
    graph(
      id,
      unknown_rows(),
      unknown_rows(),
      labels=Some(["a", "a"]),
      max_labels=2,
      max_label_bytes=2,
    )
    is Err(DuplicateLabel("a")),
  )
  assert_true(
    graph(
      id,
      unknown_rows(),
      unknown_rows(),
      labels=Some(["e\u{301}"]),
      max_labels=1,
      max_label_bytes=3,
    )
    is Err(InvalidLabel(_)),
  )
  assert_true(
    graph(
      id,
      unknown_rows(),
      unknown_rows(),
      labels=Some(["a"]),
      max_labels=0,
      max_label_bytes=1,
    )
    is Err(LimitExceeded),
  )
  assert_true(
    graph(
      @value.with_nullability(id, true),
      unknown_rows(),
      unknown_rows(),
      labels=None,
      max_labels=0,
      max_label_bytes=0,
    )
    is Err(InvalidIdentity),
  )
}

///|
test "events require a known numeric clock and preserve unknown payload evidence" {
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
  assert_true(events(timestamp, id~, time=clock) is Err(InvalidRole(_)))
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
