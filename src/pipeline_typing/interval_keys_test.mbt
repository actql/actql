///|
test "interval joins transfer keys from equality coverage, not time predicates" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for mode in ["point_in_interval", "overlap"] {
    for kind in ["inner", "left", "semi", "anti"] {
      for covered in [false, true] {
        for right_keyed in [false, true] {
          for right_projection in [false, true] {
            let left_time = if mode == "overlap" {
              "\"start\":\"amount\",\"end\":\"amount\""
            } else {
              "\"time\":\"amount\""
            }
            let on = if covered {
              "{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}"
            } else {
              ""
            }
            let project = right_projection &&
              (kind == "inner" || kind == "left")
            let extra = if project { ",\"c\":\"right.id\"" } else { "" }
            let source = cursor(
              "[{\"from\":\"l\",\"interval_join\":{\"with\":\"r\",\"kind\":\"" +
              kind +
              "\",\"mode\":\"" +
              mode +
              "\",\"on\":[" +
              on +
              "],\"left\":{" +
              left_time +
              "},\"right\":{\"start\":\"amount\",\"end\":\"amount\"},\"select\":{\"a\":\"left.id\",\"b\":\"left.id\"" +
              extra +
              "}}},{\"drop\":[\"a\"]},{\"sort\":[{\"b\":\"asc\"}]},{\"take\":1}]",
            )
            let inputs = [
              ("l", @pipeline_typing.KeyedInput(key)),
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
            let left_count = if kind == "semi" ||
              kind == "anti" ||
              (right_keyed && covered) {
              1
            } else {
              0
            }
            let right_count = if kind == "inner" &&
              right_keyed &&
              covered &&
              project {
              1
            } else {
              0
            }
            let pair_count = if project && right_keyed { 1 } else { 0 }
            assert_eq(
              @evidence.key_witness_count(keys),
              left_count + right_count + pair_count,
            )
            let ordered = left_count > 0 ||
              right_count > 0 ||
              (pair_count > 0 && kind == "inner")
            assert_eq(@pipeline_typing.take_order(p, 3) is Some(_), ordered)
            for i in 0..<@evidence.key_witness_count(keys) {
              let witness = @evidence.key_witness_at(keys, i).unwrap()
              assert_eq(@evidence.key_origin(witness), IntervalJoinResult)
              for component in 0..<@evidence.key_field_count(witness) {
                let field = @evidence.key_field_at(witness, component).unwrap()
                assert_true(
                  field.name == Unqualified("b") ||
                  field.name == Unqualified("c"),
                )
                assert_eq(
                  field.contract.unwrap().nullable,
                  kind == "left" && field.name == Unqualified("c"),
                )
              }
              let op = @evidence.key_interval_join_producer(witness).unwrap()
              assert_true(
                @join.interval_pending_validations(op).contains(
                  ValidateIntervalEndpoints,
                ),
              )
              assert_true(
                @evidence.key_pending(witness).contains(ValidateKeyProducer),
              )
              assert_eq(
                @join.interval_key_count(op),
                if covered {
                  2
                } else {
                  0
                },
              )
              assert_true(@join.interval_key_at(op, -1) is None)
              for j in 0..<@evidence.key_interval_join_dependency_count(witness) {
                assert_true(
                  @evidence.key_interval_join_dependency_side(witness, j)
                  is Some(_),
                )
                let original = @evidence.key_interval_join_dependency_at(
                  witness, j,
                ).unwrap()
                assert_eq(@evidence.key_origin(original), InputDeclaration)
              }
              assert_true(
                @evidence.key_interval_join_dependency_at(witness, -1) is None,
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
}

///|
test "interval key transfer retains actual operand schemas and rejects substitutions" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let keys = @evidence.singleton_key(key)
  let op = @join.check_interval(
    cursor(
      "{\"with\":\"r\",\"kind\":\"inner\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"amount\"},\"right\":{\"start\":\"amount\",\"end\":\"amount\"}}",
    ),
    row,
    row,
    None,
    {
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let result = @evidence.transfer_interval_join_keys(
    Some(keys),
    Some(keys),
    op,
    { max_work: 10000, max_name_bytes: 10000, },
  ).unwrap()
  assert_eq(@evidence.key_witness_count(result.keys), 1)
  let foreign = @evidence.singleton_key(
    @evidence.declare_primary_key(
      cursor("[\"id\"]"),
      @carrier.relation(@carrier.typed_rows(schema())),
      { max_fields: 1, max_name_bytes: 2, },
    ).unwrap(),
  )
  assert_eq(
    @evidence.transfer_interval_join_keys(Some(keys), Some(foreign), op, {
      max_work: 10000,
      max_name_bytes: 10000,
    }).unwrap_err().kind,
    InputContractMismatch,
  )
  assert_true(
    @evidence.transfer_interval_join_keys(Some(keys), Some(keys), op, {
      max_work: result.work,
      max_name_bytes: result.name_bytes,
    })
    is Ok(_),
  )
  assert_true(
    @evidence.transfer_interval_join_keys(Some(keys), Some(keys), op, {
      max_work: result.work - 1,
      max_name_bytes: result.name_bytes,
    })
    is Err(_),
  )
  assert_true(
    @evidence.transfer_interval_join_keys(Some(keys), Some(keys), op, {
      max_work: result.work,
      max_name_bytes: result.name_bytes - 1,
    })
    is Err(_),
  )
}
