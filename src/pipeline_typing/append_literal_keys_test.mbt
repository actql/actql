///|
test "append considers every independent witness and retains common aliases" {
  let carrier = @carrier.relation(@carrier.typed_rows(schema()))
  let keys = ["id", "amount"].map(name => {
    @evidence.declare_primary_key(cursor("[\"" + name + "\"]"), carrier, {
      max_fields: 1,
      max_name_bytes: 10,
    }).unwrap()
  })
  for declarations in [keys, [keys[1], keys[0]]] {
    let set = @evidence.collect_keys(cursor("null"), carrier, declarations, {
      max_keys: 2,
      max_work: 100,
      max_name_bytes: 100,
    }).unwrap()
    let source = cursor(
      "[{\"derive\":{\"source\":\"'crm'\",\"saved\":\"id\"},\"as\":\"l\"}," +
      "{\"from\":\"rows\",\"derive\":{\"source\":\"'support'\",\"saved\":\"id\"},\"as\":\"r\"}," +
      "{\"from\":\"l\",\"append\":{\"with\":\"r\"}}," +
      "{\"drop\":[\"id\",\"amount\"]},{\"take\":1}]",
    )
    let p = @pipeline_typing.check_with_evidence(
      source,
      [("rows", @pipeline_typing.CandidateKeysInput(set))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(p, Step(2)).unwrap(),
      ),
      2,
    )
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(p, Step(3)).unwrap(),
      ),
      1,
    )
    assert_true(@pipeline_typing.take_order(p, 4) is Some(_))
    guard @pipeline_typing.step_at(p, 2).unwrap().operation
      is Append(checked=op, ..) else {
      fail("append")
    }
    let ld = @pipeline_typing.literal_domains(p, Step(0))
    let rd = @pipeline_typing.literal_domains(p, Step(1))
    let lk = @pipeline_typing.candidate_keys(p, Step(0))
    let rk = @pipeline_typing.candidate_keys(p, Step(1))
    let foreign = @pipeline_typing.check_with_evidence(
      source,
      [("rows", @pipeline_typing.CandidateKeysInput(set))],
      None,
      None,
      limits(),
    ).unwrap()
    let caps : @evidence.TransferLimits = {
      max_work: 100000,
      max_name_bytes: 100000,
    }
    assert_true(
      @evidence.append_keys(
        lk,
        rk,
        @pipeline_typing.literal_domains(foreign, Step(0)),
        rd,
        op,
        caps,
      )
      is Err(_),
    )
    assert_true(
      @evidence.append_keys(
        @pipeline_typing.candidate_keys(foreign, Step(0)),
        rk,
        ld,
        rd,
        op,
        caps,
      )
      is Err(_),
    )
    let exact = @evidence.append_keys(lk, rk, ld, rd, op, caps).unwrap()
    assert_true(
      @evidence.append_keys(lk, rk, ld, rd, op, {
        max_work: exact.work,
        max_name_bytes: exact.name_bytes,
      })
      is Ok(_),
    )
    assert_true(
      @evidence.append_keys(lk, rk, ld, rd, op, {
        max_work: exact.work - 1,
        max_name_bytes: exact.name_bytes,
      })
      is Err(_),
    )
  }
}

///|
test "append keys require disjoint typed literals and both local witnesses" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for
    (left, right, disjoint) in [
      ("\"'crm'\"", "{\"literal\":\"support\"}", true),
      ("{\"literal\":\"crm\"}", "\"'crm'\"", false),
      ("{\"literal\":\"é\"}", "{\"literal\":\"é\"}", false),
      ("{\"literal\":1}", "{\"literal\":1.0}", false),
      ("{\"literal\":1}", "{\"literal\":2}", true),
      ("{\"literal\":true}", "{\"literal\":false}", true),
      ("{\"literal\":\"crm\"}", "\"to_string(id)\"", false),
      (
        "{\"literal\":{\"literal\":\"crm\"}}", "{\"literal\":{\"literal\":\"support\"}}",
        false,
      ),
    ] {
    for left_keyed in [false, true] {
      for right_keyed in [false, true] {
        let source = cursor(
          "[{\"from\":\"left\",\"derive\":{\"source\":" +
          left +
          "},\"as\":\"l\"},{\"from\":\"right\",\"derive\":{\"source\":" +
          right +
          "},\"as\":\"r\"},{\"from\":\"l\",\"append\":{\"with\":\"r\"}},{\"take\":1}]",
        )
        let inputs = [
          (
            "left",
            if left_keyed {
              @pipeline_typing.KeyedInput(key)
            } else {
              @pipeline_typing.CarrierInput(carrier)
            },
          ),
          (
            "right",
            if right_keyed {
              @pipeline_typing.KeyedInput(key)
            } else {
              @pipeline_typing.CarrierInput(carrier)
            },
          ),
        ]
        let p = @pipeline_typing.check_with_evidence(
          source,
          inputs,
          None,
          None,
          limits(),
        ).unwrap()
        let keys = @pipeline_typing.candidate_keys(p, Step(2)).unwrap()
        let expected = disjoint && left_keyed && right_keyed
        assert_eq(
          @evidence.key_witness_count(keys),
          if expected {
            1
          } else {
            0
          },
        )
        assert_eq(@pipeline_typing.take_order(p, 3) is Some(_), expected)
        if expected {
          let witness = @evidence.key_witness_at(keys, 0).unwrap()
          assert_eq(@evidence.key_origin(witness), AppendResult)
          assert_eq(@evidence.key_field_count(witness), 2)
          assert_eq(
            @evidence.key_append_discriminator(witness),
            Some(Unqualified("source")),
          )
          assert_true(@evidence.key_append_producer(witness) is Some(_))
          for side in [@schema.Left, @schema.Right] {
            let parent = @evidence.key_append_input(witness, side).unwrap()
            assert_eq(@evidence.key_origin(parent), InputDeclaration)
            assert_true(
              @evidence.key_pending(parent).contains(
                ValidateWholeTupleUniquenessAfterInputNormalization,
              ),
            )
            let domain = @evidence.key_append_domain(witness, side).unwrap()
            assert_eq(@evidence.literal_value_count(domain), 1)
            assert_true(@evidence.literal_origin(domain) is Binding(_, 0))
          }
        }
        let used = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: used.work,
          max_text_bytes: used.text_bytes,
        }
        assert_true(
          @pipeline_typing.check_with_evidence(
            source,
            inputs,
            None,
            None,
            exact,
          )
          is Ok(_),
        )
        assert_true(
          @pipeline_typing.check_with_evidence(source, inputs, None, None, {
            ..exact,
            max_work: used.work - 1,
          })
          is Err(_),
        )
        assert_true(
          @pipeline_typing.check_with_evidence(source, inputs, None, None, {
            ..exact,
            max_text_bytes: used.text_bytes - 1,
          })
          is Err(_),
        )
      }
    }
  }
}

///|
test "literal lineage follows ordered copies but not computed or Parameter replacements" {
  let carrier = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let parameters = @parameter.read_declarations(
    Some(cursor("{\"p\":{\"type\":\"string\",\"default\":\"support\"}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
  for replacement in ["\"source\"", "\"to_string(id)\"", "\"$p\""] {
    let source = cursor(
      "[{\"derive\":{\"source\":\"'crm'\"},\"as\":\"l\"}," +
      "{\"derive\":[{\"saved\":\"source\"},{\"source\":" +
      replacement +
      "},{\"again\":\"saved\"}]}," +
      "{\"select\":[\"id\",\"amount\",\"flag\",{\"source\":\"again\"}],\"as\":\"copied\"}," +
      "{\"from\":\"rows\",\"derive\":{\"source\":\"'support'\"},\"as\":\"r\"}," +
      "{\"from\":\"copied\",\"append\":{\"with\":\"r\"}}]",
    )
    let result = @pipeline_typing.check_with_evidence(
      source,
      [("rows", @pipeline_typing.KeyedInput(key))],
      Some(parameters),
      None,
      limits(),
    )
    let p = match result {
      Ok(p) => p
      Err(e) =>
        fail(
          replacement +
          ": " +
          @debug.to_string(e.kind) +
          " " +
          @debug.to_string(e.path),
        )
    }
    let overwritten = @evidence.literal_domain(
      @pipeline_typing.literal_domains(p, Step(1)).unwrap(),
      Unqualified("source"),
    )
    assert_eq(overwritten is Some(_), replacement == "\"source\"")
    let saved = @evidence.literal_domain(
      @pipeline_typing.literal_domains(p, Step(2)).unwrap(),
      Unqualified("source"),
    ).unwrap()
    assert_eq(
      @evidence.literal_value_at(saved, 0),
      Some(@evidence.LiteralValue::Text("crm")),
    )
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(p, Step(4)).unwrap(),
      ),
      1,
    )
  }
}

///|
test "finite literal unions preserve identity through three branches and surviving aliases" {
  let carrier = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for third in ["crm", "other"] {
    for drop_source in [false, true] {
      let source = cursor(
        "[{\"from\":\"rows\",\"derive\":{\"source\":\"'crm'\"},\"as\":\"l\"}," +
        "{\"from\":\"rows\",\"derive\":{\"source\":\"'support'\"},\"as\":\"r\"}," +
        "{\"from\":\"l\",\"append\":{\"with\":\"r\"},\"as\":\"both\"}," +
        "{\"from\":\"rows\",\"derive\":{\"source\":{\"literal\":\"" +
        third +
        "\"}},\"as\":\"third\"}," +
        "{\"from\":\"both\",\"append\":{\"with\":\"third\"}}," +
        "{\"select\":[\"id\",{\"a\":\"source\"},{\"b\":\"source\"}]},{\"drop\":[\"a\"" +
        (if drop_source { ",\"b\"" } else { "" }) +
        "]},{\"take\":1}]",
      )
      let p = @pipeline_typing.check_with_evidence(
        source,
        [("rows", @pipeline_typing.KeyedInput(key))],
        None,
        None,
        limits(),
      ).unwrap()
      let domain = @evidence.literal_domain(
        @pipeline_typing.literal_domains(p, Step(4)).unwrap(),
        Unqualified("source"),
      ).unwrap()
      assert_eq(
        @evidence.literal_value_count(domain),
        if third == "crm" {
          2
        } else {
          3
        },
      )
      let keys = @pipeline_typing.candidate_keys(p, Step(6)).unwrap()
      let expected = third == "other" && !drop_source
      assert_eq(@evidence.key_witness_count(keys), if expected { 1 } else { 0 })
      assert_eq(@pipeline_typing.take_order(p, 7) is Some(_), expected)
      if expected {
        let witness = @evidence.key_witness_at(keys, 0).unwrap()
        assert_eq(
          @evidence.key_origin(
            @evidence.key_append_input(witness, Left).unwrap(),
          ),
          AppendResult,
        )
        assert_eq(
          @evidence.key_origin(
            @evidence.key_append_input(witness, Right).unwrap(),
          ),
          InputDeclaration,
        )
        let input = @pipeline_typing.produced_input(p, Step(6)).unwrap()
        let consumer = @pipeline_typing.check_with_evidence(
          cursor("[{\"take\":1}]"),
          [("rows", @pipeline_typing.ProducedInput(input))],
          None,
          None,
          limits(),
        ).unwrap()
        assert_true(@pipeline_typing.take_order(consumer, 0) is Some(_))
      }
    }
  }
}
