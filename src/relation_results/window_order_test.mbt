///|
test "Relation and Events windows retain only admitted input occurrence order" {
  let timestamp = @contract.primitive(TimestampType, nullable=false)
  let rows = @schema.from_fields(
    [(Unqualified("time"), timestamp)],
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  for kind in ["fixed", "sliding"] {
    for event in [false, true] {
      for ordered in [false, true] {
        let prefix = if ordered {
          "{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},"
        } else {
          ""
        }
        let bridge = if event {
          "{\"to_events\":{\"id\":\"time\",\"time\":\"time\"}},"
        } else {
          ""
        }
        let operation = if event { "window_events" } else { "row_window" }
        let field = if event { "" } else { "\"time\":\"time\"," }
        let after = if event { "{\"events\":true}," } else { "" }
        let p = @pipeline.check(
          cursor(
            "[" +
            prefix +
            bridge +
            "{\"" +
            operation +
            "\":{" +
            field +
            "\"kind\":\"" +
            kind +
            "\",\"size\":10,\"step\":3}}," +
            after +
            "{\"select\":[\"time\"]},{\"take\":1,\"as\":\"out\"}]",
          ),
          [("rows", rows)],
          None,
          None,
          ranking_limits(),
        ).unwrap()
        let i = (if ordered { 1 } else { 0 }) + (if event { 1 } else { 0 })
        let last = i + (if event { 3 } else { 2 })
        assert_true(
          @pipeline.window_evidence(@pipeline.step_at(p, i).unwrap()) is Some(_),
        )
        assert_eq(@pipeline.logical_order(p, Step(i)) is Some(_), ordered)
        assert_eq(@pipeline.take_order(p, last) is Some(_), ordered)
        assert_true(
          @pipeline.window_evidence(@pipeline.step_at(p, last).unwrap()) is None,
        )
        if ordered {
          let order = @pipeline.take_order(p, last).unwrap()
          assert_eq(@pipeline.order_origin(order), Step(i))
          assert_eq(@pipeline.order_dependency_count(order), 1)
          assert_eq(@pipeline.order_dependency_at(order, 0), Some(Step(i - 1)))
          assert_true(@pipeline.order_producer(order).operation is Window(_))
          let r = @relation_results.check(
            p,
            cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"time\"]}}"),
            limits(),
          ).unwrap()
          assert_eq(
            @relation_results.publication_strategy(resolve(r)),
            Inherited,
          )
        }
      }
    }
  }
}
