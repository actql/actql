///|
fn pivot_owner(body : String) -> @lowering_relation.BoundPrepared {
  let row = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("status"),
        @contract.primitive(StringType, nullable=true),
      ),
      (
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=true),
      ),
    ],
    max_fields=3,
    max_name_bytes=14,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let checked = @pipeline.check_with_evidence(
    cursor("[{\"pivot\":" + body + ",\"as\":\"out\"}]"),
    [("rows", @pipeline.KeyedInput(key))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "pivot lowers the checked axis, aggregate, and fill exactly" {
  let owner = pivot_owner(
    "{\"index\":[\"id\",\"id\"],\"column\":\"status\",\"values\":[\"won\",\"open\"],\"value\":\"amount\",\"aggregate\":\"sum\",\"fill\":0}",
  )
  let exact = { ..sequence_limits(), max_bindings: 6, max_name_bytes: 23, }
  let sequence = @lowering_relation.prepare_sequence(owner, exact).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) &&
    @lowering_relation.kernel_pivot(kernel) is Some(pivot) else {
    fail("pivot kernel")
  }
  assert_eq(@lowering_relation.pivot_index_count(pivot), 2)
  assert_eq(@lowering_relation.pivot_axis_count(pivot), 2)
  assert_eq(@lowering_relation.pivot_axis_at(pivot, 0), Some("won"))
  assert_eq(@lowering_relation.pivot_axis_at(pivot, 1), Some("open"))
  assert_eq(@lowering_relation.pivot_function(pivot), @relation.Sum)
  assert_true(
    @lowering_relation.pivot_fill(pivot)
    is Some(@lowering_relation.Value(value)) &&
    value.value is @value.Number(0),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"pivot_0\",\"in\":[\"input_0\"],\"op\":\"REL.pivot\",\"params\":{\"aggregate\":\"sum\",\"fill\":0,\"index\":[\"id\",\"id\"],\"pivot\":\"status\",\"value\":\"amount\",\"values\":[\"won\",\"open\"]}}",
  )
  for
    limited in [
      { ..exact, max_bindings: 5, },
      { ..exact, max_name_bytes: 22, },
      { ..exact, expressions: { ..exact.expressions, max_work: 5, }, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, limited)
      is Err(@lowering_relation.KernelFailure(0, _)),
    )
  }
}

///|
test "pivot retains the admitted empty global axis" {
  let owner = pivot_owner(
    "{\"index\":[],\"column\":\"status\",\"values\":[],\"value\":\"amount\",\"aggregate\":\"count\"}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, {
    ..sequence_limits(),
    max_bindings: 2,
    max_name_bytes: 12,
  }).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("pivot kernel")
  }
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"pivot_0\",\"in\":[\"input_0\"],\"op\":\"REL.pivot\",\"params\":{\"aggregate\":\"count\",\"index\":[],\"pivot\":\"status\",\"value\":\"amount\",\"values\":[]}}",
  )
}
