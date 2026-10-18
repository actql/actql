///|
fn composite_bridge_owner(ids : String) -> @lowering_relation.BoundPrepared {
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("tenant"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (
          @schema.Unqualified("product_id"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=25,
    ).unwrap(),
  )
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_vectors\":{\"id\":" +
      ids +
      ",\"vector\":\"embedding\"}}]",
    ),
    [("rows", rows)],
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
    max_name_bytes=100,
  ).unwrap()
}

///|
test "composite bridge lowering preserves ordered field roles in the ordinary Bridge node" {
  let owner = composite_bridge_owner("[\"product_id\",\"tenant\"]")
  let exact = { ..sequence_limits(), max_bindings: 3, max_name_bytes: 25, }
  let sequence = @lowering_relation.prepare_sequence(owner, exact).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"to_vectors_0\",\"in\":[\"input_0\"],\"op\":\"BRIDGE.rows.to_vectors\",\"params\":{\"id\":[\"product_id\",\"tenant\"],\"vector\":\"embedding\"}}]",
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..exact, max_bindings: 2, })
    is Err(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..exact, max_name_bytes: 24, })
    is Err(_),
  )
}

///|
test "singleton bridge list and scalar retain the same canonical prior Bridge spelling" {
  let scalar = vector_wire(composite_bridge_owner("\"tenant\""))
  let singleton = vector_wire(composite_bridge_owner("[\"tenant\"]"))
  assert_eq(scalar, singleton)
  assert_eq(
    scalar, "[{\"id\":\"to_vectors_0\",\"in\":[\"input_0\"],\"op\":\"BRIDGE.rows.to_vectors\",\"params\":{\"id\":\"tenant\",\"vector\":\"embedding\"}}]",
  )
}
