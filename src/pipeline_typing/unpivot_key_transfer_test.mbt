///|
test "unpivot keys require distinct labels and a completely retained parent" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let row = @schema.from_fields(
    [
      (Unqualified("id"), number),
      (Unqualified("code"), number),
      (Unqualified("jan"), nullable),
      (Unqualified("feb"), nullable),
    ],
    max_fields=4,
    max_name_bytes=30,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let parents = ["id", "code"].map(name => {
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
  for columns in ["[\"jan\"]", "[\"jan\",\"feb\"]", "[\"jan\",\"jan\"]"] {
    for keep in ["[]", "[\"id\"]", "[\"id\",\"code\"]"] {
      for keyed in [false, true] {
        let source = cursor(
          "[{\"unpivot\":{\"columns\":" +
          columns +
          ",\"keep\":" +
          keep +
          ",\"name_column\":\"name\",\"value_column\":\"value\"}}]",
        )
        let inputs = [
          (
            "rows",
            if keyed {
              @pipeline_typing.CandidateKeysInput(keys)
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
        let result = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
        let count = if !keyed || columns == "[\"jan\",\"jan\"]" || keep == "[]" {
          0
        } else if keep == "[\"id\"]" {
          1
        } else {
          2
        }
        assert_eq(@evidence.key_witness_count(result), count)
        for i in 0..<count {
          let witness = @evidence.key_witness_at(result, i).unwrap()
          assert_eq(@evidence.key_origin(witness), UnpivotResult)
          assert_eq(@evidence.key_field_count(witness), 2)
          assert_true(
            physical_equal(
              @evidence.key_unpivot_input(witness).unwrap(),
              parents[i],
            ),
          )
          assert_true(@evidence.key_producer(witness) is Some(_))
          assert_true(
            @evidence.key_pending(witness).contains(ValidateKeyProducer),
          )
          let label = @evidence.key_field_at(witness, 1).unwrap()
          assert_eq(label.name, Unqualified("name"))
          assert_false(label.contract.unwrap().nullable)
          assert_true(
            @evidence.key_pending(parents[i]).contains(
              ValidateWholeTupleUniquenessAfterInputNormalization,
            ),
          )
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
  // This generated id is a label, not an exact copy of the unkept parent id.
  let replacement = @pipeline_typing.check_with_evidence(
    cursor(
      "[{\"unpivot\":{\"columns\":[\"jan\"],\"name_column\":\"id\",\"value_column\":\"value\"}}]",
    ),
    [("rows", @pipeline_typing.CandidateKeysInput(keys))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @evidence.key_witness_count(
      @pipeline_typing.candidate_keys(replacement, Step(0)).unwrap(),
    ),
    0,
  )
}

///|
test "unpivot qualified labels and surviving aliases retain the exact producer" {
  let number = @contract.primitive(NumberType, nullable=false)
  let row = @schema.from_fields(
    [
      (Qualified(Left, "id"), number),
      (Qualified(Left, "amount"), number),
      (Qualified(Right, "amount"), number),
    ],
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  // Qualified input keys are produced by a join; start with a real checked join.
  let base = schema()
  let base_carrier = @carrier.relation(@carrier.typed_rows(base))
  let parent = @evidence.declare_primary_key(cursor("[\"id\"]"), base_carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let producer = @pipeline_typing.check_with_evidence(
    cursor(
      "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"on\":\"id\",\"kind\":\"inner\"}}]",
    ),
    [
      ("l", @pipeline_typing.KeyedInput(parent)),
      ("r", @pipeline_typing.KeyedInput(parent)),
    ],
    None,
    None,
    limits(),
  ).unwrap()
  for lose_label in [false, true] {
    let source = cursor(
      "[{\"unpivot\":{\"columns\":[\"left.amount\",\"right.amount\"],\"keep\":[\"left.id\"],\"name_column\":\"label\",\"value_column\":\"value\"}}," +
      "{\"select\":[{\"id\":\"left.id\"},{\"a\":\"label\"},{\"b\":\"label\"}]}," +
      "{\"drop\":[\"a\"" +
      (if lose_label { ",\"b\"" } else { "" }) +
      "]},{\"take\":1}]",
    )
    let p = @pipeline_typing.check_with_evidence(
      source,
      [
        (
          "rows",
          @pipeline_typing.ProducedInput(
            @pipeline_typing.produced_input(producer, Step(0)).unwrap(),
          ),
        ),
      ],
      None,
      None,
      limits(),
    ).unwrap()
    let output = @pipeline_typing.candidate_keys(p, Step(2)).unwrap()
    assert_eq(
      @evidence.key_witness_count(output),
      if lose_label {
        0
      } else {
        1
      },
    )
    assert_eq(@pipeline_typing.take_order(p, 3) is Some(_), !lose_label)
    if !lose_label {
      let witness = @evidence.key_witness_at(output, 0).unwrap()
      assert_eq(@evidence.key_origin(witness), UnpivotResult)
      assert_eq(
        @evidence.key_origin(@evidence.key_unpivot_input(witness).unwrap()),
        JoinResult,
      )
    }
  }
  // Equal row shapes without the producer do not carry its keys.
  let bare = @pipeline_typing.check_with_evidence(
    cursor(
      "[{\"unpivot\":{\"columns\":[\"left.amount\",\"right.amount\"],\"keep\":[\"left.id\"],\"name_column\":\"label\",\"value_column\":\"value\"}}]",
    ),
    [("rows", @pipeline_typing.CarrierInput(carrier))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @evidence.key_witness_count(
      @pipeline_typing.candidate_keys(bare, Step(0)).unwrap(),
    ),
    0,
  )
}
