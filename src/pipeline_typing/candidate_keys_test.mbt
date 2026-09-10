///|
test "pipeline retains independent keys and pools with a surviving canonical candidate" {
  let relation = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("a"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("b"),
          Some(@contract.primitive(StringType, nullable=false)),
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
  )
  let a = @evidence.declare_primary_key(cursor("[\"a\"]"), relation, {
    max_fields: 1,
    max_name_bytes: 1,
  }).unwrap()
  let b = @evidence.declare_primary_key(cursor("[\"b\"]"), relation, {
    max_fields: 1,
    max_name_bytes: 1,
  }).unwrap()
  for keys in [[a, b], [b, a]] {
    let set = @evidence.collect_keys(cursor("null"), relation, keys, {
      max_keys: 2,
      max_work: 100,
      max_name_bytes: 100,
    }).unwrap()
    let inputs = [("rows", @pipeline_typing.CandidateKeysInput(set))]
    let source = cursor(
      "[{\"select\":[\"b\",\"embedding\"]},{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"b\"],\"method\":\"sum\"}}]",
    )
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.input_key(p, 0) is None)
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(p, Input(0)).unwrap(),
      ),
      2,
    )
    let surviving = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
    assert_eq(@evidence.key_witness_count(surviving), 1)
    assert_eq(
      @evidence.key_field_at(
        @pipeline_typing.candidate_key(p, Step(0)).unwrap(),
        0,
      ).unwrap().name,
      Unqualified("b"),
    )
    guard @pipeline_typing.step_at(p, 1).unwrap().operation is Pool(c) else {
      abort("pool")
    }
    assert_true(!@vector.pool_encodes_member_key(c))
    assert_eq(
      @evidence.declared_key_field_at(
        @vector.pool_key_declaration(c).unwrap(),
        0,
      ).unwrap().name,
      Unqualified("b"),
    )
    let usage = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: usage.work,
      max_nodes: usage.nodes,
      max_text_bytes: usage.text_bytes,
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
    // No string-key preference: a sorts first and is encoded even though b is direct.
    let p = @pipeline_typing.check_with_evidence(
      cursor(
        "[{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"b\"],\"method\":\"sum\"}}]",
      ),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    guard @pipeline_typing.step_at(p, 0).unwrap().operation is Pool(c) else {
      abort("pool")
    }
    assert_true(@vector.pool_encodes_member_key(c))
    assert_eq(
      @evidence.key_field_at(@vector.pool_key_declaration(c).unwrap(), 0).unwrap().name,
      Unqualified("a"),
    )
  }
}
