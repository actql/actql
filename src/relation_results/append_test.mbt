///|
test "append and cross join order require both operands through take and publication" {
  let number = @contract.primitive(NumberType, nullable=false)
  let row = @schema.from_fields(
    [(Unqualified("x"), number)],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  for operation in ["append", "cross_join"] {
    let selection = if operation == "cross_join" {
      ",\"select\":{\"x\":\"left.x\"}"
    } else {
      ""
    }
    for
      (left, right, ordered) in [
        ("grid", "grid", true),
        ("grid", "raw", false),
        ("raw", "grid", false),
        ("raw", "raw", false),
      ] {
      let p = @pipeline.check(
        cursor(
          "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"source_grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[\"x\"],\"as\":\"grid\"},{\"" +
          operation +
          "\":{\"with\":\"" +
          right +
          "\"" +
          selection +
          "},\"from\":\"" +
          left +
          "\"},{\"take\":1,\"as\":\"out\"}]",
        ),
        [("raw", row)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      let evidence = @pipeline.logical_order(p, Step(3))
      assert_eq(evidence is Some(_), ordered)
      assert_eq(@pipeline.take_order(p, 4) is Some(_), ordered)
      if ordered {
        let order = @pipeline.take_order(p, 4).unwrap()
        assert_eq(@pipeline.order_origin(order), Step(3))
        assert_eq(@pipeline.order_predecessor(order), Some(Step(3)))
        assert_eq(@pipeline.order_dependency_count(order), 2)
        assert_eq(@pipeline.order_dependency_at(order, 0), Some(Step(2)))
        assert_eq(@pipeline.order_dependency_at(order, 1), Some(Step(2)))
        assert_eq(@pipeline.order_dependency_at(order, -1), None)
        assert_eq(@pipeline.order_dependency_at(order, 2), None)
        let r = @relation_results.check(
          p,
          cursor("{\"result\":{\"from\":\"out\",\"fields\":[\"x\"]}}"),
          limits(),
        ).unwrap()
        assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
      }
    }
  }
}

///|
test "appended raw join outputs remain available to Result selection and order checking" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"assert_rows\":{\"unique_by\":[\"right.id\"]}},{\"append\":{\"with\":\"joined\"},\"as\":\"combined\"}",
  )
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"combined\",\"fields\":[\"left.id\",\"right.score\"],\"order_by\":[{\"left.id\":\"asc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let result = @relation_results.lookup(results, "out").unwrap()
  assert_eq(@relation_results.fields(result), ["left.id", "right.score"])
  assert_true(
    @schema.lookup(
      @relation_results.output_schema(result),
      Qualified(Right, "score"),
    ).unwrap().nullable,
  )
  assert_true(!@relation_results.pending_validations(result).is_empty())
  assert_eq(@relation_results.target(result), @pipeline.Step(2))
}

///|
test "join reshape and append compose without losing qualified array inputs or obligations" {
  let number = @contract.primitive(NumberType, nullable=false)
  let array = @contract.array_contract(
    number,
    nullable=false,
    max_items=Some(3L),
  ).unwrap()
  let payload = @contract.object_contract(
    [("amount", number)],
    nullable=false,
    max_fields=1,
    max_name_bytes=20,
  ).unwrap()
  let row = @schema.from_fields(
    [
      (@schema.Unqualified("id"), number),
      (@schema.Unqualified("items"), array),
      (@schema.Unqualified("payload"), payload),
    ],
    max_fields=3,
    max_name_bytes=50,
  ).unwrap()
  let p = @pipeline.check(
    cursor(
      "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"left\",\"on\":\"id\"}},{\"json_pick\":{\"column\":\"right.payload\",\"path\":[\"amount\"],\"output\":\"amount\"}},{\"unnest\":{\"column\":\"right.items\",\"as\":\"item\",\"with_index\":true},\"as\":\"expanded\"},{\"append\":{\"with\":\"expanded\"},\"as\":\"combined\"}]",
    ),
    [("l", row), ("r", row)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 1000,
      max_depth: 20,
      max_tokens: 0,
    },
  ).unwrap()
  let output = @pipeline.output_schema(p).unwrap()
  assert_true(@schema.lookup(output, Unqualified("amount")).unwrap().nullable)
  assert_true(!@schema.lookup(output, Unqualified("item")).unwrap().nullable)
  assert_true(
    @schema.lookup(output, Qualified(Right, "items")).unwrap().nullable,
  )
  assert_true(
    @pipeline.step_at(p, 3).unwrap().operation is Append(right=Step(2), ..),
  )
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"combined\",\"fields\":[\"amount\",\"item\",\"item_index\"]}}",
    ),
    limits(),
  ).unwrap()
  assert_eq(
    @relation_results.fields(@relation_results.lookup(results, "out").unwrap()),
    ["amount", "item", "item_index"],
  )
}
