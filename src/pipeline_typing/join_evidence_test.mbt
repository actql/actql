///|
test "join derives both unique sides from generated keys and tightens counts" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"time_series\":{\"start\":\"0000-01-01T00:00:00.000Z\",\"end\":\"9999-12-31T23:59:59.999Z\",\"step\":1},\"as\":\"grid\"},{\"join\":{\"with\":\"grid\",\"kind\":\"left\",\"on\":\"time\"}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let evidence = @pipeline_typing.join_evidence(p, 1).unwrap()
  assert_eq(evidence.cardinality, Some(@join.Cardinality::OneToOne))
  assert_true(evidence.assertion is None)
  for key in [evidence.left.unwrap(), evidence.right.unwrap()] {
    assert_eq(@evidence.key_origin(key), TimeSeriesResult)
    assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
  }
  assert_count(p, 1, 315569519999999L, true)
  assert_true(@pipeline_typing.join_evidence(p, 0) is None)
  assert_true(@pipeline_typing.join_evidence(p, -1) is None)
}

///|
test "join whole key coverage includes alternate aliases and combines assertions per side" {
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("a"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("b"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=2,
    ).unwrap(),
  )
  let key = @evidence.declare_primary_key(cursor("[\"a\",\"b\"]"), rows, {
    max_fields: 2,
    max_name_bytes: 2,
  }).unwrap()
  for complete in [false, true] {
    let on = if complete { "[\"y\",\"b\",\"y\"]" } else { "[\"y\",\"y\"]" }
    let source = cursor(
      "[{\"select\":[{\"x\":\"a\"},{\"y\":\"a\"},\"b\"],\"as\":\"aliased\"},{\"join\":{\"with\":\"aliased\",\"kind\":\"inner\",\"on\":" +
      on +
      ",\"cardinality\":\"many_to_one\"}}]",
    )
    let inputs = [("input", @pipeline_typing.KeyedInput(key))]
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let proof = @pipeline_typing.join_evidence(p, 1).unwrap()
    assert_eq(proof.assertion, Some(@join.Cardinality::ManyToOne))
    assert_eq(
      proof.cardinality,
      Some(if complete { @join.Cardinality::OneToOne } else { ManyToOne }),
    )
    if complete {
      let left = proof.left.unwrap()
      assert_eq(@evidence.key_field_at(left, 1).unwrap().name, Unqualified("y"))
      assert_eq(
        @evidence.declared_key_field_at(left, 0).unwrap().name,
        Unqualified("a"),
      )
      assert_eq(@evidence.key_pending(left), @evidence.key_pending(key))
    } else {
      assert_true(proof.left is None && proof.right is None)
    }
    let u = @pipeline_typing.usage(p)
    let cap = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
      is Ok(_),
    )
    for
      c in [
        { ..cap, max_work: cap.max_work - 1, },
        { ..cap, max_text_bytes: cap.max_text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, c)
        is Err(_),
      )
    }
  }
}
