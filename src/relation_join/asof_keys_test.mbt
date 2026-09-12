///|
fn asof_key_body(extra : String) -> @decode.Cursor {
  cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"nearest\",\"tolerance\":1,\"select\":{\"l\":\"left.id\",\"r\":\"right.id\"}" +
    extra +
    "}",
  )
}

///|
test "as-of completion preserves whole keys and authored tie repetitions" {
  let relation = @carrier.relation(asof_rows(false))
  let declaration = @evidence.declare_primary_key(
    cursor("[\"other\",\"id\"]"),
    relation,
    { max_fields: 2, max_name_bytes: 100, },
  ).unwrap()
  let keys = @evidence.singleton_key(declaration)
  let body = asof_key_body(",\"right_tie_break\":[\"other\",\"other\"]")
  let c = @relation_join.check_asof_sources(
    body,
    KeySource(keys),
    KeySource(keys),
    None,
    limits(),
  ).unwrap()
  assert_eq(@relation_join.asof_identity(c), [
    Unqualified("id"),
    Unqualified("other"),
  ])
  assert_eq(
    @relation_join.asof_tie_break(c),
    Some([Unqualified("other"), Unqualified("other")]),
  )
  assert_eq(@relation_join.asof_completed_tie_break(c), [
    Unqualified("other"),
    Unqualified("other"),
    Unqualified("id"),
  ])
  let origin = @relation_join.asof_key_completion(c, Left).unwrap()
  assert_eq(
    @evidence.declared_key_field_at(origin, 0).unwrap().name,
    Unqualified("other"),
  )
  let pending = indexed_obligation_copy(
    @relation_join.asof_pending_validations(c),
    @relation_join.asof_pending_validation_count(c),
    i => @relation_join.asof_pending_validation_at(c, i),
    (a, b) => a == b,
  )
  assert_true(pending.contains(JournalAsOfKeyCompletion(Left)))
  assert_true(pending.contains(JournalAsOfKeyCompletion(Right)))
  assert_true(
    pending.contains(
      ValidateAsOfKey(
        Right,
        ValidateWholeTupleUniquenessAfterInputNormalization,
      ),
    ),
  )
  assert_true(pending.contains(RejectAsOfTies))
  let detached = @relation_join.asof_completed_tie_break(c)
  detached.clear()
  assert_eq(@relation_join.asof_completed_tie_break(c).length(), 3)
  let u = @relation_join.asof_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @relation_join.check_asof_sources(
      body,
      KeySource(keys),
      KeySource(keys),
      None,
      exact,
    )
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
    ] {
    assert_true(
      @relation_join.check_asof_sources(
        body,
        KeySource(keys),
        KeySource(keys),
        None,
        cap,
      )
      is Err(_),
    )
  }
  let explicit = @relation_join.check_asof_sources(
    asof_key_body(
      ",\"left_id\":\"other\",\"right_tie_break\":[\"other\",\"id\"]",
    ),
    KeySource(keys),
    KeySource(keys),
    None,
    limits(),
  ).unwrap()
  assert_eq(@relation_join.asof_identity(explicit), [Unqualified("other")])
  assert_true(@relation_join.asof_key_completion(explicit, Left) is None)
  assert_true(
    !indexed_obligation_copy(
      @relation_join.asof_pending_validations(explicit),
      @relation_join.asof_pending_validation_count(explicit),
      i => @relation_join.asof_pending_validation_at(explicit, i),
      (a, b) => a == b,
    ).contains(JournalAsOfKeyCompletion(Right)),
  )
  assert_true(@relation_join.asof_key_completion(explicit, Right) is Some(_))
}

///|
test "as-of internal key completion permits references without allowing authored Ref order" {
  let reference = @contract.read_checked(
    cursor(
      "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let relation = @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("id"), Some(reference)),
        (
          Unqualified("time"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
  )
  let keys = @evidence.singleton_key(
    @evidence.declare_primary_key(cursor("[\"id\"]"), relation, {
      max_fields: 1,
      max_name_bytes: 10,
    }).unwrap(),
  )
  let c = @relation_join.check_asof_sources(
    asof_key_body(""),
    KeySource(keys),
    KeySource(keys),
    None,
    limits(),
  ).unwrap()
  assert_eq(@relation_join.asof_completed_tie_break(c), [Unqualified("id")])
  assert_true(@relation_join.asof_tie_break(c) is None)
  assert_true(
    @relation_join.check_asof_sources(
      asof_key_body(",\"right_tie_break\":[\"id\"]"),
      KeySource(keys),
      KeySource(keys),
      None,
      limits(),
    )
    is Err({ kind: InvalidTieField("id"), .. }),
  )
  let c = @relation_join.check_asof_sources(
    asof_key_body(""),
    KeySource(keys),
    CarrierSource(relation),
    None,
    limits(),
  ).unwrap()
  assert_true(@relation_join.asof_completed_tie_break(c).is_empty())
  assert_true(
    indexed_obligation_copy(
      @relation_join.asof_pending_validations(c),
      @relation_join.asof_pending_validation_count(c),
      i => @relation_join.asof_pending_validation_at(c, i),
      (a, b) => a == b,
    ).contains(RejectAsOfTies),
  )
}
