///|
test "a raw pipeline producer is not the projected named Result" {
  let p = pipeline()
  let checked = @relation_results.check(
    p,
    cursor(
      "{\"public\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"score\":\"desc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let result = @relation_results.result_at(checked, 0).unwrap()
  assert_eq(@schema.field_count(@relation_results.output_schema(result)), 1)
  let raw = @pipeline.produced_input(p, @relation_results.target(result)).unwrap()
  let downstream = @pipeline.check_with_evidence(
    cursor("[]"),
    [("raw", @pipeline.ProducedInput(raw))],
    None,
    None,
    {
      max_steps: 0,
      max_work: 10000,
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_tokens: 0,
      max_depth: 100,
    },
  ).unwrap()
  let records = @carrier.relation_rows(
    @pipeline.input_at(downstream, 0).unwrap().1,
  ).unwrap()
  let schema = @carrier.complete_schema(records).unwrap()
  assert_eq(@schema.field_count(schema), 5)
  assert_true(@pipeline.producer_order(raw) is None)
  let order = @relation_results.order_by(result).unwrap()
  assert_eq(order.length(), 1)
  assert_eq(order[0].field, "score")
  assert_eq(order[0].direction, @order.Desc)
  assert_eq(@relation_results.pending_validations(result), [
    @relation_results.TotalDeterministicOrder,
  ])
}

///|
test "Results with the same producer target and fields can have different publication semantics" {
  let checked = @relation_results.check(
    pipeline(),
    cursor(
      "{\"ascending\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}]},\"descending\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"desc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let a = @relation_results.lookup(checked, "ascending").unwrap()
  let b = @relation_results.lookup(checked, "descending").unwrap()
  assert_eq(@relation_results.target(a), @relation_results.target(b))
  assert_eq(@relation_results.fields(a), @relation_results.fields(b))
  assert_eq(@relation_results.order_by(a).unwrap()[0].direction, @order.Asc)
  assert_eq(@relation_results.order_by(b).unwrap()[0].direction, @order.Desc)
  assert_true(
    @decode.tree_index(
      @relation_results.source(checked),
      @relation_results.definition_source(a),
    ) !=
    @decode.tree_index(
      @relation_results.source(checked),
      @relation_results.definition_source(b),
    ),
  )
}
