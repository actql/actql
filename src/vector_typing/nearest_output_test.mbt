///|
test "opaque vector sides preserve unknown identity contracts and deferred dimensions" {
  let source = cursor("{\"queries\":\"q\",\"k\":1,\"metric\":\"dot\"}")
  let unknown = @carrier.unknown_carrier(VectorsKind)
  let c = @vector_typing.check_nearest(source, unknown, unknown, limits()).unwrap()
  let rows = @carrier.relation_rows(@vector_typing.nearest_output(c)).unwrap()
  assert_eq(@carrier.field_set(rows), Closed)
  assert_eq(@carrier.field_count(rows), 4)
  assert_true(
    @carrier.lookup(rows, Unqualified("query_id"))
    is Present({ contract: None, .. }),
  )
  assert_true(
    @carrier.lookup(rows, Unqualified("candidate_id"))
    is Present({ contract: None, .. }),
  )
  assert_true(
    @carrier.lookup(rows, Unqualified("score"))
    is Present({ contract: Some(_), .. }),
  )
  assert_true(@carrier.complete_schema(rows) is None)
  let pending = indexed_obligation_copy(
    @vector_typing.nearest_pending(c),
    @vector_typing.nearest_pending_count(c),
    i => @vector_typing.nearest_pending_at(c, i),
    (a, b) => a == b,
  )
  assert_true(pending.contains(MatchNearestDimensions))
  assert_true(pending.contains(ValidateNearestRoleBindings(Candidates)))
  assert_true(pending.contains(ValidateNearestRoleBindings(Queries)))
  assert_true(
    @vector_typing.check_nearest(
      source,
      unknown,
      @carrier.unknown_carrier(GraphKind),
      limits(),
    )
    is Err({ kind: WrongCarrier(GraphKind), .. }),
  )
}

///|
test "nearest output keeps scalar IDs and typed positional composite IDs" {
  let number = @contract.primitive(NumberType, nullable=false)
  let decimal = @contract.decimal_contract(38, 9, nullable=false).unwrap()
  let fields = @carrier.rows(
    [
      (Unqualified("a"), Some(number)),
      (Unqualified("b"), Some(decimal)),
      (
        Unqualified("v"),
        Some(@contract.vector_contract(3, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=10,
  ).unwrap()
  let candidate = @carrier.vectors(
    fields,
    ids=[Unqualified("b"), Unqualified("a")],
    components=Unqualified("v"),
    max_identity_fields=2,
  ).unwrap()
  let query = @carrier.vectors(
    fields,
    ids=[Unqualified("a")],
    components=Unqualified("v"),
    max_identity_fields=1,
  ).unwrap()
  let source = cursor("{\"queries\":\"q\",\"k\":1,\"metric\":\"l2\"}")
  let c = @vector_typing.check_nearest(source, candidate, query, limits()).unwrap()
  let rows = @carrier.relation_rows(@vector_typing.nearest_output(c)).unwrap()
  assert_eq(@carrier.field_count(rows), 4)
  guard @carrier.lookup(rows, Unqualified("query_id"))
    is Present({ contract: Some(q), .. }) else {
    abort("query")
  }
  assert_true(q.shape is @contract.Number)
  guard @carrier.lookup(rows, Unqualified("candidate_id"))
    is Present({ contract: Some(id), .. }) else {
    abort("candidate")
  }
  let expected = @contract.object_contract(
    [("0", decimal), ("1", number)],
    nullable=false,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  assert_true(@contract.type_equal(id, expected, 100))
  let u = @vector_typing.nearest_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @vector_typing.check_nearest(source, candidate, query, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.check_nearest(source, candidate, query, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  assert_true(
    indexed_obligation_copy(
      @vector_typing.nearest_pending(c),
      @vector_typing.nearest_pending_count(c),
      i => @vector_typing.nearest_pending_at(c, i),
      (a, b) => a == b,
    ).contains(AssignContiguousOneBasedRanks),
  )
}
