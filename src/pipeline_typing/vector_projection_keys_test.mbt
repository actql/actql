///|
fn composite_key_vectors() -> @carrier.Carrier {
  @carrier.vectors(
    @carrier.rows(
      [
        (
          Unqualified("group"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=100,
    ).unwrap(),
    ids=[Unqualified("group"), Unqualified("id")],
    components=Unqualified("embedding"),
    max_identity_fields=2,
  ).unwrap()
}

///|
test "vector bridge identity survives aliases and feeds canonical key selection" {
  let source = cursor(
    "[{\"vectors\":true,\"from\":\"rows\"},{\"select\":[\"group\",{\"a\":\"id\"},{\"b\":\"id\"},\"embedding\"]},{\"drop\":[\"a\"]}]",
  )
  let inputs = [("rows", composite_key_vectors()), ("queries", vector_input())]
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(source, inputs, None, None, limits()),
  )
  let projected = @pipeline_typing.candidate_key(p, Step(0)).unwrap()
  assert_eq(@evidence.key_origin(projected), VectorProjectionResult)
  assert_eq(@evidence.key_field_count(projected), 2)
  assert_eq(
    @evidence.declared_key_field_at(projected, 0).unwrap().name,
    Unqualified("group"),
  )
  assert_eq(
    @evidence.declared_key_field_at(projected, 1).unwrap().name,
    Unqualified("id"),
  )
  let key = @pipeline_typing.candidate_key(p, Step(2)).unwrap()
  assert_eq(@evidence.key_origin(key), VectorProjectionResult)
  assert_true(@evidence.key_vector_projection_producer(key) is Some(_))
  assert_eq(@evidence.key_pending(key), [
    ValidateKeyProducer,
    AdmitPresentNonNullComparableComponents,
    ValidateWholeTupleUniquenessAfterInputNormalization,
    RevalidateReferenceComponents,
  ])
  let selected = @evidence.select_key(
    source,
    @pipeline_typing.candidate_keys(p, Step(2)).unwrap(),
    CanonicalOrder,
    { max_work: 100, max_name_bytes: 100, },
  ).unwrap().key.unwrap()
  assert_eq(@evidence.key_field_at(selected, 0).unwrap().name, Unqualified("b"))
  assert_eq(
    @evidence.key_field_at(selected, 1).unwrap().name,
    Unqualified("group"),
  )
  assert_eq(@evidence.key_origin(selected), VectorProjectionResult)
  let usage = @pipeline_typing.usage(p)
  let cap = {
    ..limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Ok(_),
  )
  for
    smaller in [
      { ..cap, max_work: cap.max_work - 1, },
      { ..cap, max_text_bytes: cap.max_text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, smaller)
      is Err(_),
    )
  }
}

///|
test "vector bridge keys require the whole tuple and do not invent opaque identity" {
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"vectors\":true},{\"drop\":[\"id\"]}]"),
    [("rows", composite_key_vectors())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @evidence.key_witness_count(
      @pipeline_typing.candidate_keys(p, Step(1)).unwrap(),
    ),
    0,
  )
  let unknown = @pipeline_typing.check_carriers(
    cursor("[{\"vectors\":true}]"),
    [("rows", @carrier.unknown_carrier(VectorsKind))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @evidence.key_witness_count(
      @pipeline_typing.candidate_keys(unknown, Step(0)).unwrap(),
    ),
    0,
  )
  let producer = @evidence.key_vector_projection_producer(
    @pipeline_typing.candidate_key(p, Step(0)).unwrap(),
  ).unwrap()
  let cap : @evidence.TransferLimits = { max_work: 3, max_name_bytes: 7, }
  assert_true(@evidence.vector_projection_keys(producer, cap) is Ok(_))
  assert_true(
    @evidence.vector_projection_keys(producer, { ..cap, max_work: 2, })
    is Err({ kind: LimitExceeded, .. }),
  )
  assert_true(
    @evidence.vector_projection_keys(producer, { ..cap, max_name_bytes: 6, })
    is Err({ kind: LimitExceeded, .. }),
  )
}
