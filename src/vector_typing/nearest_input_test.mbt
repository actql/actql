///|
test "nearest resolves explicit Relation roles without complete payload evidence" {
  let rows = @carrier.rows(
    [
      (Unqualified("id"), Some(@contract.primitive(NumberType, nullable=false))),
      (
        Unqualified("v"),
        Some(@contract.vector_contract(3, nullable=false).unwrap()),
      ),
      (Unqualified("payload"), None),
    ],
    field_set=Open,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let options = @vector_typing.read_nearest_options(
    cursor(
      "{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1,\"candidate_id\":\"id\",\"candidate_vector\":\"v\"}",
    ),
    limits(),
  ).unwrap()
  let c = @vector_typing.check_nearest_input(
    options,
    Candidates,
    @carrier.relation(rows),
    limits(),
  ).unwrap()
  let v = @vector_typing.nearest_input_vectors(c).unwrap()
  assert_eq(@carrier.vector_dimensions(v), 3.0)
  assert_true(
    @carrier.vector_identity_at(v, 0).unwrap().contract.unwrap().shape
    is @contract.Number,
  )
  assert_eq(@carrier.field_set(@carrier.vector_records(v)), Open)
  let u = @vector_typing.nearest_input_usage(c)
  assert_true(
    @vector_typing.check_nearest_input(
      options,
      Candidates,
      @carrier.relation(rows),
      { ..limits(), max_work: u.work, },
    )
    is Ok(_),
  )
  assert_true(
    @vector_typing.check_nearest_input(
      options,
      Candidates,
      @carrier.relation(rows),
      { ..limits(), max_work: u.work - 1, },
    )
    is Err({ kind: BudgetExceeded, .. }),
  )
}

///|
test "nearest completion requires a sole vector in a closed field set" {
  let fields : Array[(@row.FieldName, @contract.Contract?)] = [
    (Unqualified("id"), Some(@contract.primitive(StringType, nullable=false))),
    (
      Unqualified("v"),
      Some(@contract.vector_contract(2, nullable=false).unwrap()),
    ),
  ]
  let options = @vector_typing.read_nearest_options(
    cursor(
      "{\"queries\":\"q\",\"metric\":\"cosine\",\"k\":1,\"candidate_id\":\"id\"}",
    ),
    limits(),
  ).unwrap()
  let closed = @carrier.rows(
    fields,
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let c = @vector_typing.check_nearest_input(
    options,
    Candidates,
    @carrier.relation(closed),
    limits(),
  ).unwrap()
  assert_eq(@vector_typing.nearest_completed_vector(c), Some(Unqualified("v")))
  let open = @carrier.rows(
    fields,
    field_set=Open,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    @vector_typing.check_nearest_input(
      options,
      Candidates,
      @carrier.relation(open),
      limits(),
    )
    is Err({ kind: MissingNearestRole("candidate_vector"), .. }),
  )
  fields.push(
    (
      Unqualified("w"),
      Some(@contract.vector_contract(2, nullable=false).unwrap()),
    ),
  )
  let ambiguous = @carrier.rows(
    fields,
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    @vector_typing.check_nearest_input(
      options,
      Candidates,
      @carrier.relation(ambiguous),
      limits(),
    )
    is Err({ kind: MissingNearestRole("candidate_vector"), .. }),
  )
}

///|
test "nearest keeps composite Vectors identities and rejects role replacement" {
  let rows = @carrier.rows(
    [
      (Unqualified("a"), Some(@contract.primitive(StringType, nullable=false))),
      (Unqualified("b"), Some(@contract.primitive(NumberType, nullable=false))),
      (
        Unqualified("v"),
        Some(@contract.vector_contract(2, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let input = @carrier.vectors(
    rows,
    ids=[Unqualified("b"), Unqualified("a")],
    components=Unqualified("v"),
    max_identity_fields=2,
  ).unwrap()
  let options = @vector_typing.read_nearest_options(
    cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1}"),
    limits(),
  ).unwrap()
  let c = @vector_typing.check_nearest_input(options, Queries, input, limits()).unwrap()
  let v = @vector_typing.nearest_input_vectors(c).unwrap()
  assert_eq(@carrier.vector_identity_count(v), 2)
  assert_eq(@carrier.vector_identity_at(v, 0).unwrap().name, Unqualified("b"))
  assert_true(@carrier.vector_identity_at(v, -1) is None)
  assert_true(@carrier.vector_identity_at(v, 2) is None)
  let replaced = @vector_typing.read_nearest_options(
    cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":1,\"query_id\":\"a\"}"),
    limits(),
  ).unwrap()
  assert_true(
    @vector_typing.check_nearest_input(replaced, Queries, input, limits())
    is Err({ kind: ConflictingNearestRole("query_id"), .. }),
  )
}
