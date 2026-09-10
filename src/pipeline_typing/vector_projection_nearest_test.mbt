///|
test "vector bridge sole string identity completes relation nearest without a new assertion" {
  let input = @carrier.vectors(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (
          Unqualified("embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
    ids=[Unqualified("id")],
    components=Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(
      cursor(
        "[{\"vectors\":true},{\"rename\":{\"id\":\"member\"}},{\"nearest\":{\"queries\":\"input\",\"metric\":\"l2\",\"k\":1}}]",
      ),
      [("input", input)],
      None,
      None,
      limits(),
    ),
  )
  guard @pipeline_typing.step_at(p, 2).unwrap().operation
    is Nearest(checked~, ..) else {
    abort("nearest")
  }
  let key = @vector.nearest_completed_identity(
    @vector.nearest_pair_input(@vector.nearest_pair(checked), Candidates),
  ).unwrap()
  assert_eq(@evidence.key_origin(key), VectorProjectionResult)
  assert_eq(@evidence.key_field_at(key, 0).unwrap().name, Unqualified("member"))
  assert_eq(
    @evidence.declared_key_field_at(key, 0).unwrap().name,
    Unqualified("id"),
  )
  assert_true(@evidence.key_vector_projection_producer(key) is Some(_))
  assert_true(
    @evidence.key_pending(key).contains(
      ValidateWholeTupleUniquenessAfterInputNormalization,
    ),
  )
}

///|
test "vector key factory rejects other checked carrier bridges" {
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"events\":true}]"),
    [("input", event_input())],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 0).unwrap().operation is Projection(op) else {
    abort("projection")
  }
  assert_true(
    @evidence.vector_projection_keys(op, { max_work: 100, max_name_bytes: 100, })
    is Err({ kind: InputContractMismatch, .. }),
  )
  assert_true(@pipeline_typing.candidate_keys(p, Step(0)) is None)
}
