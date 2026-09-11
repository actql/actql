///|
test "existing-input order resolution cannot use a consumer's output order" {
  for ordered in [false, true] {
    for
      operation in [
        "\"watermark_rows\":{\"time\":\"amount\",\"max_skew\":1,\"late_policy\":\"mark\"}",
        "\"pivot\":{\"index\":[],\"column\":\"id\",\"values\":[\"a\"],\"value\":\"amount\",\"aggregate\":\"first\"}",
      ] {
      let prefix = if ordered {
        "{\"values\":{\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":\"a\",\"amount\":1}]},\"as\":\"seed\"},"
      } else {
        ""
      }
      let p = @pipeline_typing.check(
        cursor("[" + prefix + "{" + operation + "}]"),
        [("rows", schema())],
        None,
        None,
        limits(),
      ).unwrap()
      let i = if ordered { 1 } else { 0 }
      let r = @pipeline_typing.resolve_existing_input_order(p, i)
      let all = @pipeline_typing.resolve_contextual_orders(
        p,
        max_steps=2,
        max_work=10000,
        max_text_bytes=10000,
      )
      assert_eq(all is Ok(_), ordered)
      if ordered {
        assert_true(
          @pipeline_typing.contextual_orders_at(all.unwrap(), i).unwrap()[0]
          is InputSequence(_),
        )
      }
      assert_eq(r is Some(_), ordered)
      guard @pipeline_typing.step_at(p, i).unwrap().operation is Unary(consumer) else {
        abort("unary consumer")
      }
      let expected = if @relation.operation(consumer) == @relation.Pivot {
        // The consumer has output order even when its required input order is absent.
        assert_true(@pipeline_typing.logical_order(p, Step(i)) is Some(_))
        @relation.StableInputOrder
      } else {
        @relation.WatermarkPrefixOrder
      }
      assert_true(@pipeline_typing.resolve_existing_input_order(p, -1) is None)
      assert_true(
        @pipeline_typing.resolve_existing_input_order(p, i + 1) is None,
      )
      if r is Some(r) {
        assert_eq(@pipeline_typing.input_order_requirement(r), expected)
        assert_eq(@pipeline_typing.input_order_target(r), Step(0))
        assert_eq(
          @pipeline_typing.order_origin(
            @pipeline_typing.input_order_evidence(r),
          ),
          Step(0),
        )
        guard @pipeline_typing.input_order_consumer(r).operation is Unary(op) else {
          abort("consumer")
        }
        assert_eq(
          @relation.existing_order_requirement(op),
          Some(@pipeline_typing.input_order_requirement(r)),
        )
      }
    }
  }
}
