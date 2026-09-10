///|
test "nearest resolves independently retained candidate and query key completions" {
  let relation = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (
          Unqualified("v"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap(),
  )
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), relation, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let inputs = [
    ("rows", @pipeline_typing.KeyedInput(key)),
    ("q", @pipeline_typing.KeyedInput(key)),
  ]
  for
    source in [
      cursor(
        "[{\"from\":\"rows\",\"select\":[{\"a\":\"id\"},{\"b\":\"id\"},\"v\"]},{\"drop\":[\"a\"]},{\"nearest\":{\"queries\":\"q\",\"metric\":\"l2\",\"k\":1}}]",
      ),
      cursor(
        "[{\"from\":\"rows\",\"derive\":[{\"b\":\"id\"},{\"id\":\"'changed'\"}]},{\"drop\":[\"id\"]},{\"nearest\":{\"queries\":\"q\",\"metric\":\"l2\",\"k\":1}}]",
      ),
    ] {
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(p, 2).unwrap()
    guard step.operation is Nearest(checked~, ..) else { abort("nearest") }
    let pair = @vector.nearest_pair(checked)
    let candidate = @vector.nearest_completed_identity(
      @vector.nearest_pair_input(pair, Candidates),
    ).unwrap()
    assert_eq(
      @evidence.key_field_at(candidate, 0).unwrap().name,
      Unqualified("b"),
    )
    assert_eq(
      @evidence.declared_key_field_at(candidate, 0).unwrap().name,
      Unqualified("id"),
    )
    let query = @vector.nearest_completed_identity(
      @vector.nearest_pair_input(pair, Queries),
    ).unwrap()
    assert_eq(@evidence.key_field_at(query, 0).unwrap().name, Unqualified("id"))
    let edges = @pipeline_typing.input_occurrences(step)
    assert_eq(edges[0].target, Step(1))
    assert_eq(edges[1].target, Input(1))
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
        is Err(_),
      )
    }
  }
  let ambiguous = cursor(
    "[{\"from\":\"rows\",\"select\":[{\"a\":\"id\"},{\"b\":\"id\"},\"v\"]},{\"nearest\":{\"queries\":\"q\",\"metric\":\"l2\",\"k\":1}}]",
  )
  assert_true(
    @pipeline_typing.check_with_evidence(
      ambiguous,
      inputs,
      None,
      None,
      limits(),
    )
    is Err({ kind: Vector(MissingNearestRole("candidate_id")), .. }),
  )
}
