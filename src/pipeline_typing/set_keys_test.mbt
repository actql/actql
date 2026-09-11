///|
test "set operators retain left keys and distinct establishes whole-row uniqueness" {
  let number = @contract.primitive(NumberType, nullable=false)
  let left_schema = @schema.from_fields(
    [(Unqualified("id"), number)],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let left = @carrier.relation(@carrier.typed_rows(left_schema))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), left, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for op in ["except", "intersect"] {
    for duplicates in ["all", "distinct"] {
      for wider in [false, true] {
        let right_schema = @schema.from_fields(
          [(Unqualified("id"), @contract.with_nullability(number, wider))],
          max_fields=1,
          max_name_bytes=2,
        ).unwrap()
        for keyed in [false, true] {
          let inputs = [
            (
              "l",
              if keyed {
                @pipeline_typing.KeyedInput(key)
              } else {
                @pipeline_typing.CarrierInput(left)
              },
            ),
            (
              "r",
              if wider {
                @pipeline_typing.CarrierInput(
                  @carrier.relation(@carrier.typed_rows(right_schema)),
                )
              } else {
                @pipeline_typing.KeyedInput(key)
              },
            ),
          ]
          let source = cursor(
            "[{\"" +
            op +
            "\":{\"with\":\"r\",\"duplicates\":\"" +
            duplicates +
            "\"},\"from\":\"l\"},{\"sort\":[{\"id\":\"desc\"}]}]",
          )
          let p = @pipeline_typing.check_with_evidence(
            source,
            inputs,
            None,
            None,
            limits(),
          ).unwrap()
          let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
          assert_eq(
            @evidence.key_witness_count(keys),
            (if keyed { 1 } else { 0 }) +
            (if duplicates == "distinct" { 1 } else { 0 }),
          )
          assert_eq(
            @pipeline_typing.logical_order(p, Step(1)) is Some(_),
            keyed || (duplicates == "distinct" && !wider),
          )
          assert_eq(
            @schema.lookup(
              @pipeline_typing.schema_at(p, Step(0)).unwrap(),
              Unqualified("id"),
            ).unwrap().nullable,
            wider,
          )
          if keyed {
            let retained = @evidence.key_witness_at(keys, 0).unwrap()
            assert_eq(
              @evidence.key_pending(retained),
              @evidence.key_pending(key),
            )
            assert_true(
              !@evidence.key_field_at(retained, 0).unwrap().contract.unwrap().nullable,
            )
            let completion = @pipeline_typing.order_sort_completion(
              @pipeline_typing.logical_order(p, Step(1)).unwrap(),
            ).unwrap()
            assert_eq(@pipeline_typing.sort_completion_count(completion), 0)
          }
          if duplicates == "distinct" {
            let generated = @evidence.key_witness_at(
              keys,
              if keyed {
                1
              } else {
                0
              },
            ).unwrap()
            assert_eq(@evidence.key_origin(generated), SetDistinctResult)
            assert_eq(@evidence.key_pending(generated), [
              @evidence.KeyObligation::ValidateKeyProducer,
            ])
            guard @pipeline_typing.step_at(p, 0).unwrap().operation
              is @pipeline_typing.Set(checked~, ..) else {
              abort("expected set")
            }
            assert_true(
              physical_equal(
                @evidence.key_set_producer(generated).unwrap(),
                checked,
              ),
            )
            assert_eq(
              @evidence.key_field_at(generated, 0).unwrap().contract.unwrap().nullable,
              wider,
            )
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
              max_work: u.work - 1,
            })
            is Err(_),
          )
        }
      }
    }
  }
}

///|
test "distinct set keys retain every component and alias with exact budgets" {
  let rows = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_fields(
        [
          (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
          (Unqualified("name"), @contract.primitive(StringType, nullable=false)),
        ],
        max_fields=2,
        max_name_bytes=6,
      ).unwrap(),
    ),
  )
  for op in ["except", "intersect"] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"" +
        op +
        "\":{\"with\":\"rows\",\"duplicates\":\"distinct\"}}," +
        "{\"select\":[{\"a\":\"id\"},{\"b\":\"id\"},\"name\"]},{\"drop\":[\"a\"]},{\"drop\":[\"name\"]}]",
      ),
      [("rows", rows)],
      None,
      None,
      limits(),
    ).unwrap()
    guard @pipeline_typing.step_at(p, 0).unwrap().operation
      is @pipeline_typing.Set(checked~, ..) else {
      abort("expected set")
    }
    let transfer = @evidence.advance_set_keys(None, checked, {
      max_work: 3,
      max_name_bytes: 6,
    }).unwrap()
    assert_eq(transfer.work, 3)
    assert_eq(transfer.name_bytes, 6)
    let insufficient : Array[@evidence.TransferLimits] = [
      { max_work: 2, max_name_bytes: 6, },
      { max_work: 3, max_name_bytes: 5, },
    ]
    for caps in insufficient {
      assert_eq(
        @evidence.advance_set_keys(None, checked, caps).unwrap_err().kind,
        LimitExceeded,
      )
    }
    let retained = @pipeline_typing.candidate_key(p, Step(2)).unwrap()
    assert_eq(
      @evidence.key_field_at(retained, 0).unwrap().name,
      Unqualified("b"),
    )
    assert_true(
      physical_equal(@evidence.key_set_producer(retained).unwrap(), checked),
    )
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(p, Step(3)).unwrap(),
      ),
      0,
    )
  }
}

///|
test "set distinct does not invent empty identities or scalar structural keys" {
  let structure = @contract.read_checked(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{}}",
    ),
    { max_nodes: 10, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for empty in [false, true] {
    let fields : Array[(@schema.FieldName, @contract.Contract)] = if empty {
      []
    } else {
      [(Unqualified("obj"), structure)]
    }
    let rows = @carrier.relation(
      @carrier.typed_rows(
        @schema.from_fields(fields, max_fields=1, max_name_bytes=3).unwrap(),
      ),
    )
    for op in ["except", "intersect"] {
      let source = cursor(
        "[{\"" + op + "\":{\"with\":\"rows\",\"duplicates\":\"distinct\"}}]",
      )
      let p = @pipeline_typing.check_carriers(
        source,
        [("rows", rows)],
        None,
        None,
        limits(),
      ).unwrap()
      let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
      assert_eq(@evidence.key_witness_count(keys), if empty { 0 } else { 1 })
      for
        purpose in [
          @evidence.KeyUse::CanonicalOrder,
          @evidence.KeyUse::ScalarIdentity,
        ] {
        assert_true(
          @evidence.select_key(source, keys, purpose, {
            max_work: 100,
            max_name_bytes: 100,
          }).unwrap().key
          is None,
        )
      }
    }
  }
}

///|
test "set key transfer rejects keys attached to a different left schema" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline_typing.check_carriers(
    cursor("[{\"except\":{\"with\":\"rows\",\"duplicates\":\"all\"}}]"),
    [("rows", rows)],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 0).unwrap().operation
    is @pipeline_typing.Set(checked~, ..) else {
    abort("expected set")
  }
  let set = @evidence.singleton_key(key)
  assert_eq(
    @evidence.transfer_set_keys(set, checked, {
      max_work: 2,
      max_name_bytes: 0,
    }).unwrap().work,
    2,
  )
  assert_eq(
    @evidence.transfer_set_keys(set, checked, {
      max_work: 1,
      max_name_bytes: 0,
    }).unwrap_err().kind,
    LimitExceeded,
  )
  let other = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    @carrier.relation(@carrier.typed_rows(schema())),
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  assert_eq(
    @evidence.transfer_set_keys(@evidence.singleton_key(other), checked, {
      max_work: 2,
      max_name_bytes: 0,
    }).unwrap_err().kind,
    InputContractMismatch,
  )
}
