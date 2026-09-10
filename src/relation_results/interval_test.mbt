///|
test "interval join aliases flow to Results without proving total order" {
  let row = @schema.from_fields(
    [(Unqualified("time"), @contract.primitive(TimestampType, nullable=false))],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let p = @pipeline.check(
    cursor(
      "[{\"interval_join\":{\"with\":\"rows\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"time\",\"end\":\"time\"},\"select\":{\"matched\":\"right.time\",\"time\":\"left.time\"}},\"as\":\"joined\"}]",
    ),
    [("rows", row)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 100000,
      max_tokens: 0,
      max_depth: 100,
    },
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"joined\",\"fields\":[\"time\",\"matched\"]}}"),
    limits(),
  ).unwrap()
  let result = @relation_results.result_at(results, 0).unwrap()
  assert_eq(@relation_results.fields(result), ["time", "matched"])
  assert_eq(@relation_results.pending_validations(result), [
    TotalDeterministicOrder,
  ])
  let output = @relation_results.output_schema(result)
  assert_true(@schema.lookup(output, Unqualified("matched")).unwrap().nullable)
  assert_true(!@schema.lookup(output, Unqualified("time")).unwrap().nullable)
}
