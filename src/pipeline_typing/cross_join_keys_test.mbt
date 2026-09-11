///|
test "cross join keys require both identities unless right singleton is asserted" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for left_keyed in [false, true] {
    for right_keyed in [false, true] {
      for singleton in [false, true] {
        for project_right in [false, true] {
          let assertion = if singleton { ",\"right_rows\":\"one\"" } else { "" }
          let right_projection = if project_right {
            ",\"c\":\"right.id\""
          } else {
            ""
          }
          let source = cursor(
            "[{\"from\":\"l\",\"cross_join\":{\"with\":\"r\",\"select\":{\"a\":\"left.id\",\"b\":\"left.id\"" +
            right_projection +
            "}" +
            assertion +
            "}},{\"drop\":[\"a\"]},{\"sort\":[{\"b\":\"asc\"}]},{\"take\":1}]",
          )
          let inputs = [
            (
              "l",
              if left_keyed {
                @pipeline_typing.KeyedInput(key)
              } else {
                @pipeline_typing.CarrierInput(carrier)
              },
            ),
            (
              "r",
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
          let keys = @pipeline_typing.candidate_keys(p, Step(1)).unwrap()
          let single = if singleton && left_keyed { 1 } else { 0 }
          let pairs = if left_keyed && right_keyed && project_right {
            1
          } else {
            0
          }
          assert_eq(@evidence.key_witness_count(keys), single + pairs)
          assert_eq(
            @pipeline_typing.take_order(p, 3) is Some(_),
            single + pairs > 0,
          )
          for i in 0..<(single + pairs) {
            let witness = @evidence.key_witness_at(keys, i).unwrap()
            assert_eq(@evidence.key_origin(witness), CrossJoinResult)
            assert_true(
              @evidence.key_pending(witness).contains(ValidateKeyProducer),
            )
            let producer = @evidence.key_cross_join_producer(witness).unwrap()
            assert_eq(@join.cross_requires_one_right_row(producer), singleton)
            assert_eq(
              @join.cross_pending_validations(producer).contains(
                ValidateExactlyOneRightRow,
              ),
              singleton,
            )
            let pair = i >= single
            assert_eq(
              @evidence.key_cross_join_dependency_count(witness),
              if pair {
                2
              } else {
                1
              },
            )
            assert_eq(
              @evidence.key_field_count(witness),
              if pair {
                2
              } else {
                1
              },
            )
            assert_eq(
              @evidence.key_cross_join_dependency_side(witness, 0),
              Some(@schema.Left),
            )
            if pair {
              assert_eq(
                @evidence.key_cross_join_dependency_side(witness, 1),
                Some(@schema.Right),
              )
            }
            for j in 0..<@evidence.key_cross_join_dependency_count(witness) {
              assert_eq(
                @evidence.key_origin(
                  @evidence.key_cross_join_dependency_at(witness, j).unwrap(),
                ),
                InputDeclaration,
              )
            }
            assert_true(
              @evidence.key_cross_join_dependency_at(witness, -1) is None,
            )
            assert_eq(
              @evidence.key_field_at(witness, 0).unwrap().name,
              Unqualified("b"),
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
          assert_true(
            @pipeline_typing.check_with_evidence(source, inputs, None, None, {
              ..exact,
              max_text_bytes: u.text_bytes - 1,
            })
            is Err(_),
          )
        }
      }
    }
  }
}

///|
test "cross join transfer rejects foreign operands and retains raw qualified pair fields" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let keys = @evidence.singleton_key(key)
  let op = @join.check_cross(cursor("{\"with\":\"r\"}"), row, row, None, {
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  let r = @evidence.transfer_cross_join_keys(Some(keys), Some(keys), op, {
    max_work: 10000,
    max_name_bytes: 10000,
  }).unwrap()
  let pair = @evidence.key_witness_at(r.keys, 0).unwrap()
  assert_eq(
    @evidence.key_field_at(pair, 0).unwrap().name,
    Qualified(Left, "id"),
  )
  assert_eq(
    @evidence.key_field_at(pair, 1).unwrap().name,
    Qualified(Right, "id"),
  )
  assert_eq(@evidence.key_witness_count(r.keys), 1)
  assert_true(
    @evidence.transfer_cross_join_keys(Some(keys), Some(keys), op, {
      max_work: r.work,
      max_name_bytes: r.name_bytes,
    })
    is Ok(_),
  )
  assert_true(
    @evidence.transfer_cross_join_keys(Some(keys), Some(keys), op, {
      max_work: r.work - 1,
      max_name_bytes: r.name_bytes,
    })
    is Err(_),
  )
  assert_true(
    @evidence.transfer_cross_join_keys(Some(keys), Some(keys), op, {
      max_work: r.work,
      max_name_bytes: r.name_bytes - 1,
    })
    is Err(_),
  )
  let foreign = @evidence.singleton_key(
    @evidence.declare_primary_key(
      cursor("[\"id\"]"),
      @carrier.relation(@carrier.typed_rows(schema())),
      { max_fields: 1, max_name_bytes: 2, },
    ).unwrap(),
  )
  for (left, right) in [(foreign, keys), (keys, foreign)] {
    assert_eq(
      @evidence.transfer_cross_join_keys(Some(left), Some(right), op, {
        max_work: 10000,
        max_name_bytes: 10000,
      }).unwrap_err().kind,
      InputContractMismatch,
    )
  }
}
