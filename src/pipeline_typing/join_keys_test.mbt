///|
test "join keys follow the closed cardinality table and retain operand provenance" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for kind in ["inner", "left", "full", "semi", "anti"] {
    let p = @pipeline_typing.check_with_evidence(
      cursor(
        "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"" +
        kind +
        "\",\"on\":\"id\"}}]",
      ),
      [
        ("l", @pipeline_typing.KeyedInput(key)),
        ("r", @pipeline_typing.KeyedInput(key)),
      ],
      None,
      None,
      limits(),
    ).unwrap()
    let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
    let expected = if kind == "inner" {
      2
    } else if kind == "left" {
      1
    } else if kind == "full" {
      0
    } else {
      1
    }
    assert_eq(@evidence.key_witness_count(keys), expected)
    for i in 0..<expected {
      let result = @evidence.key_witness_at(keys, i).unwrap()
      assert_eq(@evidence.key_origin(result), JoinResult)
      assert_true(@evidence.key_join_producer(result) is Some(_))
      assert_true(@evidence.key_pending(result).contains(ValidateKeyProducer))
      for j in 0..<@evidence.key_join_dependency_count(result) {
        assert_true(@evidence.key_join_dependency_side(result, j) is Some(_))
        let parent = @evidence.key_join_dependency_at(result, j).unwrap()
        assert_eq(@evidence.key_origin(parent), InputDeclaration)
        assert_true(
          @evidence.key_pending(parent).contains(
            ValidateWholeTupleUniquenessAfterInputNormalization,
          ),
        )
      }
      assert_true(@evidence.key_join_dependency_at(result, -1) is None)
      assert_eq(@evidence.key_field_count(result), 1)
      assert_false(
        @evidence.key_field_at(result, 0).unwrap().contract.unwrap().nullable,
      )
    }
  }
}

///|
test "full join does not conflate nullable input keys with missing-side sentinels" {
  let row = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=true))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  for kind in ["inner", "left", "full"] {
    let p = @pipeline_typing.check(
      cursor(
        "[{\"from\":\"l\",\"group\":{\"by\":[\"id\"],\"aggregates\":{}},\"as\":\"lg\"},{\"from\":\"r\",\"group\":{\"by\":[\"id\"],\"aggregates\":{}},\"as\":\"rg\"},{\"join\":{\"left\":\"lg\",\"with\":\"rg\",\"kind\":\"" +
        kind +
        "\",\"on\":\"id\"}}]",
      ),
      [("l", row), ("r", row)],
      None,
      None,
      limits(),
    ).unwrap()
    let keys = @pipeline_typing.candidate_keys(p, Step(2)).unwrap()
    assert_eq(
      @evidence.key_witness_count(keys),
      if kind == "full" {
        0
      } else if kind == "left" {
        1
      } else {
        2
      },
    )
  }
}

///|
test "join key transfer rejects foreign operand handles and shares exact text budgets" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"amount\",\"select\":{\"left_id\":\"left.id\",\"right_id\":\"right.id\"}}",
  )
  let op = @join.check(body, row, row, None, {
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let keys = @evidence.singleton_key(key)
  let r = @evidence.transfer_join_keys(Some(keys), Some(keys), op, {
    max_work: 10000,
    max_name_bytes: 10000,
  }).unwrap()
  // Neither join tuple covers id, so only the whole pair is a valid output key.
  assert_eq(@evidence.key_witness_count(r.keys), 1)
  assert_eq(
    @evidence.key_field_count(@evidence.key_witness_at(r.keys, 0).unwrap()),
    2,
  )
  assert_true(
    @evidence.transfer_join_keys(Some(keys), Some(keys), op, {
      max_work: r.work,
      max_name_bytes: r.name_bytes,
    })
    is Ok(_),
  )
  assert_true(
    @evidence.transfer_join_keys(Some(keys), Some(keys), op, {
      max_work: r.work - 1,
      max_name_bytes: r.name_bytes,
    })
    is Err(_),
  )
  assert_true(
    @evidence.transfer_join_keys(Some(keys), Some(keys), op, {
      max_work: r.work,
      max_name_bytes: r.name_bytes - 1,
    })
    is Err(_),
  )
  let foreign = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    @carrier.relation(@carrier.typed_rows(schema())),
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  assert_eq(
    @evidence.transfer_join_keys(
      Some(keys),
      Some(@evidence.singleton_key(foreign)),
      op,
      { max_work: 10000, max_name_bytes: 10000, },
    ).unwrap_err().kind,
    InputContractMismatch,
  )
}

///|
test "join alias survival supports downstream ordering without right-side key invention" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for kind in ["inner", "left", "semi", "anti"] {
    for asserted in [false, true] {
      let assertion = if asserted {
        ",\"cardinality\":\"many_to_one\""
      } else {
        ""
      }
      let source = cursor(
        "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"" +
        kind +
        "\",\"on\":\"id\",\"select\":{\"a\":\"left.id\",\"b\":\"left.id\"}" +
        assertion +
        "}},{\"drop\":[\"a\"]},{\"sort\":[{\"b\":\"asc\"}]},{\"take\":1}]",
      )
      let p = @pipeline_typing.check_with_evidence(
        source,
        [
          ("l", @pipeline_typing.KeyedInput(key)),
          ("r", @pipeline_typing.CarrierInput(carrier)),
        ],
        None,
        None,
        limits(),
      ).unwrap()
      let survives = asserted || kind == "semi" || kind == "anti"
      assert_eq(@pipeline_typing.candidate_key(p, Step(1)) is Some(_), survives)
      assert_eq(@pipeline_typing.take_order(p, 3) is Some(_), survives)
      if survives {
        let retained = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
        assert_eq(
          @evidence.key_field_at(retained, 0).unwrap().name,
          Unqualified("b"),
        )
        assert_eq(@evidence.key_join_dependency_count(retained), 1)
        let op = @evidence.key_join_producer(retained).unwrap()
        assert_eq(@join.assertion(op) is Some(_), asserted)
      }
      let u = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: u.work,
        max_text_bytes: u.text_bytes,
        max_nodes: u.nodes,
        max_tokens: u.tokens,
      }
      assert_true(
        @pipeline_typing.check_with_evidence(
          source,
          [
            ("l", @pipeline_typing.KeyedInput(key)),
            ("r", @pipeline_typing.CarrierInput(carrier)),
          ],
          None,
          None,
          exact,
        )
        is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_with_evidence(
          source,
          [
            ("l", @pipeline_typing.KeyedInput(key)),
            ("r", @pipeline_typing.CarrierInput(carrier)),
          ],
          None,
          None,
          { ..exact, max_work: u.work - 1, },
        )
        is Err(_),
      )
    }
  }
}
