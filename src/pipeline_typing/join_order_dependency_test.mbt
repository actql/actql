///|
test "join left order uses owned cardinality without requiring right enumeration" {
  let row = schema()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let seed = "{\"values\":{\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":\"a\",\"amount\":1}]},\"as\":\"seed\"}"
  for kind in ["inner", "left", "full"] {
    for keyed in [false, true] {
      for covered in [false, true] {
        for asserted in [false, true] {
          let source = cursor(
            "[" +
            seed +
            ",{\"join\":{\"with\":\"r\",\"kind\":\"" +
            kind +
            "\",\"on\":\"" +
            (if covered { "id" } else { "amount" }) +
            "\"" +
            (if asserted { ",\"cardinality\":\"many_to_one\"" } else { "" }) +
            "}},{\"take\":1}]",
          )
          let inputs = [
            (
              "r",
              if keyed {
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
          let expected = kind != "full" && (asserted || (keyed && covered))
          let order = @pipeline_typing.logical_order(p, Step(1))
          assert_eq(order is Some(_), expected)
          if order is Some(order) {
            assert_eq(@pipeline_typing.order_dependency_count(order), 1)
            assert_eq(
              @pipeline_typing.order_dependency_at(order, 0),
              Some(Step(0)),
            )
            assert_eq(
              @pipeline_typing.input_occurrence_count(
                @pipeline_typing.order_producer(order).unwrap(),
              ),
              2,
            )
            let evidence = @pipeline_typing.join_evidence(p, 1).unwrap()
            assert_eq(evidence.right is Some(_), keyed && covered)
            assert_eq(evidence.assertion is Some(_), asserted)
            if evidence.right is Some(parent) {
              assert_true(
                @evidence.key_pending(parent).contains(
                  ValidateWholeTupleUniquenessAfterInputNormalization,
                ),
              )
            }
            assert_true(@pipeline_typing.take_order(p, 2) is Some(_))
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
        }
      }
    }
  }
  for singleton in [false, true] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        seed +
        ",{\"cross_join\":{\"with\":\"r\"" +
        (if singleton { ",\"right_rows\":\"one\"" } else { "" }) +
        "}},{\"take\":1}]",
      ),
      [("r", carrier)],
      None,
      None,
      limits(),
    ).unwrap()
    let order = @pipeline_typing.logical_order(p, Step(1))
    assert_eq(order is Some(_), singleton)
    if order is Some(order) {
      let producer = @pipeline_typing.order_producer(order).unwrap()
      assert_eq(@pipeline_typing.input_occurrence_count(producer), 2)
      guard producer.operation is CrossJoin(checked~, ..) else {
        fail("wrong producer")
      }
      assert_true(@join.cross_requires_one_right_row(checked))
      assert_true(
        @join.cross_pending_validations(checked).contains(
          ValidateExactlyOneRightRow,
        ),
      )
      assert_eq(@pipeline_typing.order_dependency_at(order, 0), Some(Step(0)))
      assert_true(@pipeline_typing.take_order(p, 2) is Some(_))
    }
  }
}
