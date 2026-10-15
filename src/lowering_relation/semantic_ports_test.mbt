///|
test "semantic ports retain exact resolved occurrences and output schema" {
  let prepared = @lowering_relation.prepare(
    checked(
      ",{\"derive\":{},\"as\":\"identity\"},{\"from\":\"seed\",\"select\":[\"id\"]}",
    ),
    limits(),
  ).unwrap()
  assert_eq(@lowering_relation.preparation_input_count(prepared), 0)
  assert_true(@lowering_relation.preparation_input_schema(prepared, 0) is None)
  let node = @lowering_relation.node_at(prepared, 2).unwrap()
  assert_true(
    @lowering_relation.node_input_target(node, 0) is Some(@pipeline.Step(0)),
  )
  assert_true(@lowering_relation.node_input_target(node, 1) is None)
  assert_true(@lowering_relation.node_input_target(node, -1) is None)
  let schema = @lowering_relation.node_output_schema(node)
  assert_eq(
    @carrier.kind(@lowering_relation.node_output_carrier(node)),
    @carrier.RelationKind,
  )
  assert_eq(
    @carrier.kind(
      @lowering_relation.preparation_carrier_at(prepared, @pipeline.Step(2)).unwrap(),
    ),
    @carrier.RelationKind,
  )
  assert_eq(@schema.field_count(schema), 1)
  assert_eq(
    @schema.reference_name(@schema.field_at(schema, 0).unwrap().name),
    "id",
  )
  assert_eq(@lowering_relation.node_id(node), "select_2")
  assert_eq(@lowering_relation.input_ids(node), ["values_0"])
}

///|
test "source view category is false for ordinary and absent prepared inputs" {
  let schema = @pipeline.schema_at(checked(""), Step(0)).unwrap()
  let pipeline = @pipeline.check(
    cursor("[{\"select\":[\"id\"]}]"),
    [("ordinary", schema)],
    None,
    None,
    {
      max_steps: 2,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let prepared = @lowering_relation.prepare(pipeline, limits()).unwrap()
  assert_eq(@lowering_relation.preparation_input_count(prepared), 1)
  for index in [-1, 0, 1] {
    assert_false(
      @lowering_relation.preparation_input_is_source_view(prepared, index),
    )
  }
  let source_free = @lowering_relation.prepare(checked(""), limits()).unwrap()
  assert_false(
    @lowering_relation.preparation_input_is_source_view(source_free, 0),
  )
}
