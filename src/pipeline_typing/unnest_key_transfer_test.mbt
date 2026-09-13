///|
test "unnest identity uses parent and index or an admitted singleton array bound" {
  for bound in [None, Some(0L), Some(1L), Some(2L)] {
    let row = @schema.from_fields(
      [
        (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
        (
          Unqualified("items"),
          @contract.array_contract(
            @contract.primitive(NumberType, nullable=true),
            nullable=true,
            max_items=bound,
          ).unwrap(),
        ),
      ],
      max_fields=2,
      max_name_bytes=20,
    ).unwrap()
    let carrier = @carrier.relation(@carrier.typed_rows(row))
    let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
      max_fields: 1,
      max_name_bytes: 2,
    }).unwrap()
    for outer in [false, true] {
      for index in ["", ",\"with_index\":true", ",\"with_index\":\"ix\""] {
        let source = cursor(
          "[{\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"outer\":" +
          outer.to_string() +
          index +
          "}}]",
        )
        let inputs = [("rows", @pipeline_typing.KeyedInput(key))]
        let p = @pipeline_typing.check_with_evidence(
          source,
          inputs,
          None,
          None,
          limits(),
        ).unwrap()
        let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
        let extended = !outer && index != ""
        let singleton = outer && bound is Some(0L | 1L)
        assert_eq(
          @evidence.key_witness_count(keys),
          if extended || singleton {
            1
          } else {
            0
          },
        )
        if extended || singleton {
          let witness = @evidence.key_witness_at(keys, 0).unwrap()
          assert_eq(@evidence.key_origin(witness), UnnestResult)
          assert_eq(
            @evidence.key_field_count(witness),
            if extended {
              2
            } else {
              1
            },
          )
          assert_true(
            physical_equal(@evidence.key_unnest_input(witness).unwrap(), key),
          )
          assert_true(
            @evidence.key_pending(witness).contains(ValidateKeyProducer),
          )
          assert_true(
            @evidence.key_pending(@evidence.key_unnest_input(witness).unwrap()).contains(
              ValidateWholeTupleUniquenessAfterInputNormalization,
            ),
          )
          assert_true(@evidence.key_producer(witness) is Some(_))
          if extended {
            let field = @evidence.key_field_at(witness, 1).unwrap()
            assert_false(field.contract.unwrap().nullable)
            assert_eq(
              field.name,
              Unqualified(
                if index.contains("true") {
                  "item_index"
                } else {
                  "ix"
                },
              ),
            )
          }
          let owned = @pipeline_typing.produced_input(p, Step(0)).unwrap()
          let consumer = @pipeline_typing.check_with_evidence(
            cursor("[{\"take\":1}]"),
            [("rows", @pipeline_typing.ProducedInput(owned))],
            None,
            None,
            limits(),
          ).unwrap()
          assert_true(@pipeline_typing.take_order(consumer, 0) is Some(_))
        }
        let used = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: used.work,
          max_text_bytes: used.text_bytes,
          max_nodes: used.nodes,
          max_tokens: used.tokens,
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
test "unnest transfers independent keys through aliases without inventing a parent" {
  let row = @schema.from_fields(
    [
      (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
      (Unqualified("other"), @contract.primitive(NumberType, nullable=false)),
      (
        Unqualified("items"),
        @contract.array_contract(
          @contract.primitive(NumberType, nullable=true),
          nullable=true,
        ).unwrap(),
      ),
    ],
    max_fields=3,
    max_name_bytes=30,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let parents = ["id", "other"].map(name => {
    @evidence.declare_primary_key(cursor("[\"" + name + "\"]"), carrier, {
      max_fields: 1,
      max_name_bytes: 10,
    }).unwrap()
  })
  let keys = @evidence.collect_keys(cursor("{}"), carrier, parents, {
    max_keys: 2,
    max_work: 100,
    max_name_bytes: 100,
  }).unwrap()
  for keyed in [false, true] {
    for lose_index in [false, true] {
      let p = @pipeline_typing.check_with_evidence(
        cursor(
          "[{\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"with_index\":true}}," +
          "{\"select\":[\"id\",\"other\",{\"a\":\"item_index\"},{\"b\":\"item_index\"}]}," +
          "{\"drop\":[\"a\",\"other\"" +
          (if lose_index { ",\"b\"" } else { "" }) +
          "]},{\"take\":1}]",
        ),
        [
          (
            "rows",
            if keyed {
              @pipeline_typing.CandidateKeysInput(keys)
            } else {
              @pipeline_typing.CarrierInput(carrier)
            },
          ),
        ],
        None,
        None,
        limits(),
      ).unwrap()
      assert_eq(
        @evidence.key_witness_count(
          @pipeline_typing.candidate_keys(p, Step(0)).unwrap(),
        ),
        if keyed {
          2
        } else {
          0
        },
      )
      let surviving = @pipeline_typing.candidate_keys(p, Step(2)).unwrap()
      assert_eq(
        @evidence.key_witness_count(surviving),
        if keyed && !lose_index {
          1
        } else {
          0
        },
      )
      assert_eq(
        @pipeline_typing.take_order(p, 3) is Some(_),
        keyed && !lose_index,
      )
      if keyed && !lose_index {
        let witness = @evidence.key_witness_at(surviving, 0).unwrap()
        assert_true(
          physical_equal(
            @evidence.key_unnest_input(witness).unwrap(),
            parents[0],
          ),
        )
        assert_eq(
          @evidence.key_field_at(witness, 1).unwrap().name,
          Unqualified("b"),
        )
      }
    }
  }
}
