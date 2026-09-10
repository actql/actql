///|
test "appended raw join outputs remain available to Result selection and order checking" {
  let p = joined_pipeline(
    "left",
    suffix=",{\"append\":{\"with\":\"joined\"},\"as\":\"combined\"}",
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
  assert_eq(@relation_results.target(result), @pipeline.Step(1))
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
  let output = @pipeline.output_schema(p)
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
