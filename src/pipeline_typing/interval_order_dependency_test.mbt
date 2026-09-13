///|
test "interval existence joins require left order but retain both execution inputs" {
  let row = @schema.from_fields(
    [
      (Unqualified("id"), @contract.primitive(StringType, nullable=false)),
      (Unqualified("at"), @contract.primitive(NumberType, nullable=false)),
      (Unqualified("start"), @contract.primitive(NumberType, nullable=false)),
      (Unqualified("end"), @contract.primitive(NumberType, nullable=false)),
    ],
    max_fields=4,
    max_name_bytes=20,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let seed = "{\"values\":{\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false},\"start\":{\"type\":\"number\",\"nullable\":false},\"end\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":\"a\",\"at\":1,\"start\":0,\"end\":2}]},\"as\":\"seed\"}"
  for kind in ["semi", "anti", "inner", "left"] {
    for left_ordered in [false, true] {
      let source = cursor(
        "[" +
        seed +
        ",{\"from\":\"" +
        (if left_ordered { "seed" } else { "unknown" }) +
        "\",\"interval_join\":{\"with\":\"" +
        (if left_ordered { "unknown" } else { "seed" }) +
        "\",\"kind\":\"" +
        kind +
        "\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}},{\"take\":1}]",
      )
      let p = @pipeline_typing.check_carriers(
        source,
        [("unknown", carrier)],
        None,
        None,
        limits(),
      ).unwrap()
      let expected = left_ordered && (kind == "semi" || kind == "anti")
      let order = @pipeline_typing.logical_order(p, Step(1))
      assert_eq(order is Some(_), expected)
      assert_eq(@pipeline_typing.take_order(p, 2) is Some(_), expected)
      if order is Some(order) {
        assert_eq(@pipeline_typing.order_origin(order), Step(1))
        assert_eq(@pipeline_typing.order_dependency_count(order), 1)
        assert_eq(@pipeline_typing.order_dependency_at(order, 0), Some(Step(0)))
        let producer = @pipeline_typing.order_producer(order).unwrap()
        assert_eq(@pipeline_typing.input_occurrence_count(producer), 2)
        guard producer.operation is IntervalJoin(checked~, right~) else {
          fail("wrong producer")
        }
        assert_eq(right, Input(0))
        assert_true(
          @join.interval_pending_validations(checked).contains(
            ValidateIntervalEndpoints,
          ),
        )
        let input = @pipeline_typing.produced_input(p, Step(1)).unwrap()
        let consumer = @pipeline_typing.check_with_evidence(
          cursor("[{\"take\":1}]"),
          [("rows", @pipeline_typing.ProducedInput(input))],
          None,
          None,
          limits(),
        ).unwrap()
        let imported = @pipeline_typing.take_order(consumer, 0).unwrap()
        assert_true(
          physical_equal(
            @pipeline_typing.order_input_producer(imported).unwrap(),
            input,
          ),
        )
        assert_true(
          physical_equal(@pipeline_typing.producer_pipeline(input), p),
        )
        assert_eq(@pipeline_typing.producer_target(input), Step(1))
      }
      let usage = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: usage.work,
        max_text_bytes: usage.text_bytes,
        max_nodes: usage.nodes,
        max_tokens: usage.tokens,
      }
      assert_true(
        @pipeline_typing.check_carriers(
          source,
          [("unknown", carrier)],
          None,
          None,
          exact,
        )
        is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_carriers(
          source,
          [("unknown", carrier)],
          None,
          None,
          { ..exact, max_work: exact.max_work - 1, },
        )
        is Err(_),
      )
    }
  }
}
