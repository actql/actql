///|
test "keyed distinct expands projection before distinct with collision-checked IDs" {
  let owner = expression_pipeline(",{\"distinct\":[\"id\"]}")
  let prepared = @lowering_relation.bound_preparation(owner)
  let usage = @lowering_relation.usage(prepared)
  assert_eq(usage.nodes, 3)
  assert_eq(usage.references, 2)
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("distinct")
  }
  let projection = @lowering_relation.kernel_distinct_projection(kernel).unwrap()
  assert_true(@lowering_relation.kernel_is_distinct(kernel))
  assert_eq(@lowering_relation.projection_field_count(projection), 1)
  let fields = @lowering_relation.projection_fields(projection)
  assert_eq(
    fields.map(field => {
      (
        @schema.reference_name(field.input),
        @schema.reference_name(field.output),
      )
    }),
    [("id", "id")],
  )
  fields.clear()
  assert_eq(@lowering_relation.projection_fields(projection).length(), 1)
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 1),
    Some(2),
  )
  for
    (index, id, operation) in [
      (0, "select_1", "REL.select"),
      (1, "distinct_1", "REL.distinct"),
    ] {
    let node = @lowering_relation.sequence_canonical_node_at(sequence, 1, index).unwrap()
    assert_eq((node.source_step, node.id, node.operation), (1, id, operation))
  }
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}},{\"id\":\"select_1\",\"in\":[\"values_0\"],\"op\":\"REL.select\",\"params\":{\"columns\":[\"id\"]}},{\"id\":\"distinct_1\",\"in\":[\"select_1\"],\"op\":\"REL.distinct\",\"params\":{}}]",
  )
  let exact : @lowering_relation.Limits = {
    max_nodes: usage.nodes,
    max_references: usage.references,
    max_work: usage.work,
    max_identifier_bytes: usage.identifier_bytes,
  }
  let pipeline = @lowering_relation.pipeline(prepared)
  assert_true(@lowering_relation.prepare(pipeline, exact) is Ok(_))
  for
    limited in [
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_references: usage.references - 1, },
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_identifier_bytes: usage.identifier_bytes - 1, },
    ] {
    assert_true(@lowering_relation.prepare(pipeline, limited) is Err(_))
  }
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 0,
    })
    is Err(
      @lowering_relation.KernelFailure(
        1,
        @lowering_relation.KernelBudgetExceeded
      )
    ),
  )
}

///|
test "authored prefix-like aliases cannot change canonical distinct identities" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(
      ",{\"derive\":{\"z\":\"id\"},\"as\":\"select_2\"},{\"from\":\"select_2\",\"distinct\":[\"z\",\"id\"],\"as\":\"distinct_2\"}",
    ),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("distinct")
  }
  let projection = @lowering_relation.kernel_distinct_projection(kernel).unwrap()
  assert_eq(
    @lowering_relation.projection_fields(projection).map(field => {
      @schema.reference_name(field.input)
    }),
    ["z", "id"],
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 2),
    Some(2),
  )
  for
    (index, id, operation) in [
      (0, "select_2", "REL.select"),
      (1, "distinct_2", "REL.distinct"),
    ] {
    let node = @lowering_relation.sequence_canonical_node_at(sequence, 2, index).unwrap()
    assert_eq((node.source_step, node.id, node.operation), (2, id, operation))
  }
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_true(
    @encode.finish(writer).contains(
      "{\"id\":\"select_2\",\"in\":[\"derive_1\"],\"op\":\"REL.select\",\"params\":{\"columns\":[\"z\",\"id\"]}},{\"id\":\"distinct_2\",\"in\":[\"select_2\"],\"op\":\"REL.distinct\",\"params\":{}}",
    ),
  )
}
