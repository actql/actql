///|
fn key_vectors(composite : Bool) -> @carrier.Carrier {
  let rows = @carrier.rows(
    [
      (Unqualified("a"), Some(@contract.primitive(NumberType, nullable=false))),
      (
        Unqualified("b"),
        Some(@contract.decimal_contract(38, 9, nullable=false).unwrap()),
      ),
      (
        Unqualified("v"),
        Some(@contract.vector_contract(2, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=3,
  ).unwrap()
  @carrier.vectors(
    rows,
    ids=if composite {
      [Unqualified("b"), Unqualified("a")]
    } else {
      [Unqualified("a")]
    },
    components=Unqualified("v"),
    max_identity_fields=2,
  ).unwrap()
}

///|
test "nearest output keys retain both identity domains and their checked producer" {
  for query_composite in [false, true] {
    for candidate_composite in [false, true] {
      let candidates = key_vectors(candidate_composite)
      let queries = key_vectors(query_composite)
      let source = cursor(
        "[{\"from\":\"c\",\"nearest\":{\"queries\":\"q\",\"metric\":\"dot\",\"k\":2}}]",
      )
      let p = @pipeline_typing.check_carriers(
        source,
        [("c", candidates), ("q", queries)],
        None,
        None,
        limits(),
      ).unwrap()
      let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
      assert_eq(@evidence.key_witness_count(keys), 1)
      let key = @evidence.key_witness_at(keys, 0).unwrap()
      assert_eq(@evidence.key_origin(key), NearestResult)
      assert_eq(@evidence.key_field_count(key), 2)
      let producer = @evidence.key_nearest_producer(key).unwrap()
      guard @pipeline_typing.step_at(p, 0).unwrap().operation
        is Nearest(checked~, ..) else {
        abort("nearest")
      }
      assert_true(physical_equal(checked, producer))
      assert_true(
        @vector.nearest_pending(producer).contains(ValidateBothUniqueIdentities),
      )
      for (i, composite) in [(0, query_composite), (1, candidate_composite)] {
        let field = @evidence.key_field_at(key, i).unwrap()
        assert_eq(
          field.name,
          Unqualified(if i == 0 { "query_id" } else { "candidate_id" }),
        )
        assert_eq(field.positional_identity is Some(_), composite)
        if field.positional_identity is Some(v) {
          assert_eq(
            @carrier.vector_identity_at(v, 0).unwrap().name,
            Unqualified("b"),
          )
          assert_eq(
            @carrier.vector_identity_at(v, 1).unwrap().name,
            Unqualified("a"),
          )
        }
      }
      let caps : @evidence.TransferLimits = {
        max_work: 100,
        max_name_bytes: 100,
      }
      assert_true(
        @evidence.select_key(source, keys, CanonicalOrder, caps).unwrap().key
        is Some(_),
      )
      assert_eq(
        @evidence.select_key(source, keys, ScalarIdentity, caps).unwrap().key
        is Some(_),
        !query_composite && !candidate_composite,
      )
      let transfer = @evidence.nearest_keys(producer, {
        max_work: 3,
        max_name_bytes: 20,
      }).unwrap()
      assert_eq(transfer.work, 3)
      assert_eq(transfer.name_bytes, 20)
      let lows : Array[@evidence.TransferLimits] = [
        { max_work: 2, max_name_bytes: 20, },
        { max_work: 3, max_name_bytes: 19, },
      ]
      for low in lows {
        assert_true(
          @evidence.nearest_keys(producer, low)
          is Err({ kind: LimitExceeded, .. }),
        )
      }
      let u = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: u.work,
        max_nodes: u.nodes,
        max_text_bytes: u.text_bytes,
      }
      assert_true(
        @pipeline_typing.check_carriers(
          source,
          [("c", candidates), ("q", queries)],
          None,
          None,
          exact,
        )
        is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_carriers(
          source,
          [("c", candidates), ("q", queries)],
          None,
          None,
          { ..exact, max_work: u.work - 1, },
        )
        is Err(_),
      )
    }
  }
}

///|
test "nearest tuple keys survive every exact alias but not overwritten or missing components" {
  let vector = key_vectors(true)
  let prefix = "{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":2}}"
  for
    (suffix, survives) in [
      (
        ",{\"select\":[{\"a\":\"candidate_id\"},{\"b\":\"candidate_id\"},\"query_id\"]},{\"drop\":[\"a\"]}",
        true,
      ),
      (
        ",{\"derive\":[{\"b\":\"candidate_id\"},{\"candidate_id\":\"1\"}]},{\"drop\":[\"candidate_id\"]}",
        true,
      ),
      (",{\"derive\":[{\"candidate_id\":\"1\"}]}", false),
      (",{\"drop\":[\"query_id\"]}", false),
      (",{\"distinct\":true}", true),
    ] {
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(
        cursor("[" + prefix + suffix + "]"),
        [("v", vector)],
        None,
        None,
        limits(),
      ),
    )
    let keys = @pipeline_typing.candidate_keys(
      p,
      @pipeline_typing.current(p).unwrap(),
    ).unwrap()
    let mut nearest_count = 0
    for i in 0..<@evidence.key_witness_count(keys) {
      if @evidence.key_nearest_producer(
          @evidence.key_witness_at(keys, i).unwrap(),
        )
        is Some(_) {
        nearest_count += 1
      }
    }
    assert_eq(nearest_count, if survives { 1 } else { 0 })
    if survives {
      let key = @evidence.select_key(cursor("null"), keys, CanonicalOrder, {
        max_work: 1000,
        max_name_bytes: 1000,
      }).unwrap().key.unwrap()
      assert_true(@evidence.key_nearest_producer(key) is Some(_))
      for i in 0..<2 {
        assert_true(
          @evidence.key_field_at(key, i).unwrap().positional_identity is Some(_),
        )
      }
      // The same row shape is insufficient to declare a positional identity.
      assert_true(
        @evidence.declare_primary_key(
          cursor("[\"query_id\"]"),
          @carrier.relation(@evidence.key_set_records(keys)),
          { max_fields: 1, max_name_bytes: 100, },
        )
        is Err({ kind: InvalidKeyType("query_id"), .. }),
      )
    }
  }
}

///|
test "nearest does not turn opaque identity roles into candidate keys" {
  let typed = key_vectors(true)
  let unknown = @carrier.unknown_carrier(VectorsKind)
  for (c, q) in [(typed, unknown), (unknown, typed), (unknown, unknown)] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"from\":\"c\",\"nearest\":{\"queries\":\"q\",\"metric\":\"dot\",\"k\":2}}]",
      ),
      [("c", c), ("q", q)],
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(p, Step(0)).unwrap(),
      ),
      0,
    )
  }
}
