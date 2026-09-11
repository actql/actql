///|
test "analytic calculation order and object projection only preserve input order" {
  let timestamp = @contract.primitive(TimestampType, nullable=false)
  let row = @schema.from_fields(
    [(Unqualified("time"), timestamp)],
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  for ordered in [false, true] {
    let prefix = if ordered {
      "{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},"
    } else {
      ""
    }
    let p = @pipeline.check(
      cursor(
        "[" +
        prefix +
        "{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"time\":\"desc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}},{\"derive\":{\"payload\":{\"object\":{\"x\":{\"literal\":1}}}}},{\"json_pick\":{\"column\":\"payload\",\"path\":[\"x\"],\"output\":\"x\"}},{\"select\":[\"x\"]},{\"take\":1,\"as\":\"out\"}]",
      ),
      [("rows", row)],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let start = if ordered { 1 } else { 0 }
    for i in start..<(start + 5) {
      assert_eq(@pipeline.logical_order(p, Step(i)) is Some(_), ordered)
      if ordered {
        assert_eq(
          @pipeline.order_origin(@pipeline.logical_order(p, Step(i)).unwrap()),
          Step(0),
        )
      }
    }
    if ordered {
      let r = @relation_results.check(
        p,
        cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"x\"]}}"),
        limits(),
      ).unwrap()
      assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
    }
  }
}
