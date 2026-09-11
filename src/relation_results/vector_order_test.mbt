///|
test "vector scoring establishes order while bridges and normalization only preserve it" {
  let row = @schema.from_fields(
    [
      (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
      (
        Unqualified("embedding"),
        @contract.vector_contract(2, nullable=false).unwrap(),
      ),
    ],
    max_fields=2,
    max_name_bytes=20,
  ).unwrap()
  for ordered in [false, true] {
    for metric in ["none", "dot", "cosine", "l2"] {
      let prefix = if ordered {
        "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}},\"rows\":[{\"id\":2,\"embedding\":[1,2]},{\"id\":10,\"embedding\":[1,2]}]},\"as\":\"seed\"},"
      } else {
        ""
      }
      let scoring = if metric == "none" {
        ""
      } else {
        "{\"score_vectors\":{\"query\":[1,2],\"metric\":\"" +
        metric +
        "\"}},{\"normalize_vectors\":true},"
      }
      let p = @pipeline.check(
        cursor(
          "[" +
          prefix +
          "{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"normalize_vectors\":true}," +
          scoring +
          "{\"vectors\":true},{\"select\":[\"embedding\"]},{\"take\":1,\"as\":\"out\"}]",
        ),
        [("rows", row)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      let start = if ordered { 1 } else { 0 }
      assert_eq(@pipeline.logical_order(p, Step(start + 1)) is Some(_), ordered)
      let scored = metric != "none"
      let last = start + (if scored { 6 } else { 4 })
      assert_eq(@pipeline.take_order(p, last) is Some(_), ordered || scored)
      if ordered || scored {
        let order = @pipeline.take_order(p, last).unwrap()
        assert_eq(
          @pipeline.order_origin(order),
          Step(if scored { start + 2 } else { 0 }),
        )
        if scored {
          match @pipeline.order_producer(order).operation {
            Vector(op) => {
              assert_eq(@vector.operation(op), ScoreVectors)
              assert_true(@vector.pending_validations(op).contains(ScoreOrder))
              assert_true(
                @vector.pending_validations(op).contains(ResolveVecaProfile),
              )
            }
            _ => fail("expected score origin")
          }
        }
        let r = @relation_results.check(
          p,
          cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"embedding\"]}}"),
          limits(),
        ).unwrap()
        assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
      }
    }
  }
}
