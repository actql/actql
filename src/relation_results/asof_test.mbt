///|
test "as-of output retains alias types but does not discharge Result order evidence" {
  let row = @schema.from_fields(
    [
      (Unqualified("id"), @contract.primitive(NumberType, nullable=false)),
      (Unqualified("time"), @contract.primitive(TimestampType, nullable=false)),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let p = @pipeline.check(
    cursor(
      "[{\"asof_join\":{\"with\":\"rows\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"forward\",\"tolerance\":\"1d\",\"select\":{\"id\":\"left.id\",\"matched\":\"right.time\"}},\"as\":\"matched_rows\"}]",
    ),
    [("rows", row)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_tokens: 0,
      max_depth: 100,
    },
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"matched_rows\",\"fields\":[\"id\",\"matched\"]}}",
    ),
    limits(),
  ).unwrap()
  let result = @relation_results.result_at(results, 0).unwrap()
  assert_eq(@relation_results.fields(result), ["id", "matched"])
  assert_eq(@relation_results.pending_validations(result), [
    TotalDeterministicOrder,
  ])
  let output = @relation_results.output_schema(result)
  assert_true(@schema.lookup(output, Unqualified("matched")).unwrap().nullable)
  assert_true(!@schema.lookup(output, Unqualified("id")).unwrap().nullable)
  let resolved = resolve(results)
  assert_eq(@relation_results.publication_strategy(resolved), Inherited)
  let order = @relation_results.publication_inherited_order(resolved).unwrap()
  assert_eq(@pipeline.order_origin(order), Step(0))
  assert_eq(@pipeline.order_dependency_count(order), 0)
  assert_true(
    @pipeline.order_producer(order).unwrap().operation is AsOfJoin(..),
  )
}
