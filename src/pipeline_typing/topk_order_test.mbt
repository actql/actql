///|
test "top-k ranking completes keys instead of reusing unrelated input order" {
  for operation in ["top_k", "top_k_by"] {
    let partition = if operation == "top_k_by" {
      "\"partition_by\":[\"x\",\"x\"],"
    } else {
      ""
    }
    for key in ["x", "b"] {
      let source = cursor(
        "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[{\"a\":\"time\"},{\"b\":\"time\"},\"x\"]},{\"" +
        operation +
        "\":{" +
        partition +
        "\"k\":2,\"by\":[{\"" +
        key +
        "\":\"desc\"}]}},{\"drop\":[\"a\",\"b\"]},{\"take\":1}]",
      )
      let p = @pipeline_typing.check_carriers(source, [], None, None, limits()).unwrap()
      let order = @pipeline_typing.take_order(p, 5).unwrap()
      assert_eq(@pipeline_typing.order_origin(order), Step(3))
      let c = @pipeline_typing.order_sort_completion(order).unwrap()
      assert_eq(
        @pipeline_typing.sort_completion_count(c),
        if key == "x" {
          1
        } else {
          0
        },
      )
      if key == "x" {
        assert_eq(
          @pipeline_typing.sort_completion_field(c, 0),
          Some(Unqualified("a")),
        )
      }
      guard @pipeline_typing.order_producer(order).operation is Unary(op) else {
        abort("ranking")
      }
      assert_eq(@relation.ranking_term_count(op), 1)
      assert_eq(@relation.ranking_term_at(op, 0).unwrap().direction, Desc)
      let u = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: u.work,
        max_text_bytes: u.text_bytes,
        max_nodes: u.nodes,
      }
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, exact) is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, {
          ..exact,
          max_work: u.work - 1,
        })
        is Err(_),
      )
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, {
          ..exact,
          max_text_bytes: u.text_bytes - 1,
        })
        is Err(_),
      )
    }
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1},{\"x\":1}]},\"as\":\"seed\"},{\"" +
        operation +
        "\":{" +
        partition +
        "\"k\":1,\"by\":[{\"x\":\"desc\"}]}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.logical_order(p, Step(0)) is Some(_))
    assert_true(@pipeline_typing.logical_order(p, Step(1)) is None)
  }
}
