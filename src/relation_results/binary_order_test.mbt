///|
test "join kind determines which operand orders are required" {
  let number = @contract.primitive(NumberType, nullable=false)
  let row = @schema.from_fields(
    [(Unqualified("x"), number)],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  for kind in ["inner", "left", "full", "semi", "anti"] {
    for
      (left, right) in [
        ("grid", "grid"),
        ("grid", "raw"),
        ("raw", "grid"),
        ("raw", "raw"),
      ] {
      let p = @pipeline.check(
        cursor(
          "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"source_grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[\"x\"],\"as\":\"grid\"},{\"join\":{\"with\":\"" +
          right +
          "\",\"kind\":\"" +
          kind +
          "\",\"on\":\"x\",\"select\":{\"x\":\"left.x\"}},\"from\":\"" +
          left +
          "\"},{\"take\":1,\"as\":\"out\"}]",
        ),
        [("raw", row)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      let left_only = kind == "semi" || kind == "anti"
      let ordered = left == "grid" && (left_only || right == "grid")
      assert_eq(@pipeline.logical_order(p, Step(3)) is Some(_), ordered)
      assert_eq(@pipeline.take_order(p, 4) is Some(_), ordered)
      if ordered {
        let order = @pipeline.take_order(p, 4).unwrap()
        assert_eq(@pipeline.order_origin(order), Step(3))
        assert_eq(
          @pipeline.order_dependency_count(order),
          if left_only {
            1
          } else {
            2
          },
        )
        assert_eq(@pipeline.order_dependency_at(order, 0), Some(Step(2)))
        if !left_only {
          assert_eq(@pipeline.order_dependency_at(order, 1), Some(Step(2)))
        }
        assert_true(
          @pipeline.order_producer(order).unwrap().operation is Join(..),
        )
        let r = @relation_results.check(
          p,
          cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"x\"]}}"),
          limits(),
        ).unwrap()
        assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
      }
    }
  }
}

///|
test "set multiplicity policies preserve left order without requiring right order" {
  let number = @contract.primitive(NumberType, nullable=false)
  let row = @schema.from_fields(
    [(Unqualified("x"), number)],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  for operation in ["except", "intersect"] {
    for policy in ["all", "distinct"] {
      for
        (left, right) in [
          ("grid", "grid"),
          ("grid", "raw"),
          ("raw", "grid"),
          ("raw", "raw"),
        ] {
        let p = @pipeline.check(
          cursor(
            "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"source_grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[\"x\"],\"as\":\"grid\"},{\"" +
            operation +
            "\":{\"with\":\"" +
            right +
            "\",\"duplicates\":\"" +
            policy +
            "\"},\"from\":\"" +
            left +
            "\"},{\"take\":1,\"as\":\"out\"}]",
          ),
          [("raw", row)],
          None,
          None,
          ranking_limits(),
        ).unwrap()
        assert_eq(
          @pipeline.logical_order(p, Step(3)) is Some(_),
          left == "grid",
        )
        assert_eq(
          @pipeline.take_order(p, 4) is Some(_),
          left == "grid" || policy == "distinct",
        )
        if left == "raw" && policy == "distinct" {
          let order = @pipeline.take_order(p, 4).unwrap()
          let key = @pipeline.order_key_completion(order).unwrap()
          assert_eq(@evidence.key_origin(key), SetDistinctResult)
          assert_true(@evidence.key_set_producer(key) is Some(_))
          let r = @relation_results.check(
            p,
            cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"x\"]}}"),
            limits(),
          ).unwrap()
          assert_eq(
            @relation_results.publication_strategy(resolve(r)),
            Inherited,
          )
        }
        if left == "grid" {
          let order = @pipeline.logical_order(p, Step(3)).unwrap()
          assert_eq(@pipeline.order_origin(order), Step(0))
          assert_eq(@pipeline.order_predecessor(order), Some(Step(2)))
          let r = @relation_results.check(
            p,
            cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"x\"]}}"),
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
