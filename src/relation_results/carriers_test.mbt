///|
test "publication selects a named Relation without requiring pipeline current" {
  let p = @pipeline.check(
    cursor("[]"),
    [
      ("a", @schema.from_object(input()).unwrap()),
      ("b", @schema.from_object(input()).unwrap()),
    ],
    None,
    None,
    {
      max_steps: 0,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 0,
      max_depth: 100,
    },
  ).unwrap()
  assert_eq(@pipeline.current(p), None)
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"b\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  assert_eq(
    @relation_results.target(@relation_results.result_at(results, 0).unwrap()),
    Input(1),
  )
}

///|
test "publication requires a Relation and does not coerce opaque Carriers" {
  let kinds : Array[@carrier.Kind] = [
    RelationKind,
    GraphKind,
    EventsKind,
    VectorsKind,
  ]
  for kind in kinds {
    let p = @pipeline.check_carriers(
      cursor("[]"),
      [("data", @carrier.unknown_carrier(kind))],
      None,
      None,
      {
        max_steps: 0,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 10000,
        max_tokens: 0,
        max_depth: 100,
      },
    ).unwrap()
    let error = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"data\",\"fields\":[\"id\"]}}"),
      limits(),
    ).unwrap_err()
    assert_eq(
      error.kind,
      if kind == RelationKind {
        IncompleteSchema
      } else {
        WrongCarrier(kind)
      },
    )
    assert_eq(error.path, [Key("out"), Key("from")])
  }
}
