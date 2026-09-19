///|
fn vector_relation() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("product_id"),
          Some(@contract.primitive(@contract.NumberType, nullable=false)),
        ),
        (
          @schema.Unqualified("embedding"),
          Some(@contract.vector_contract(2.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=2,
      max_name_bytes=19,
    ).unwrap(),
  )
}

///|
fn vector_owner(
  query : String,
  declarations? : @parameter.Declarations? = None,
  bindings? : @parameter.BoundValues? = None,
) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"product_id\",\"vector\":\"embedding\"}},{\"normalize_vectors\":true},{\"score_vectors\":{\"query\":" +
      query +
      ",\"metric\":\"cosine\"}}]",
    ),
    [("rows", vector_relation())],
    declarations,
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
    bindings,
    max_parameters=1,
    max_name_bytes=100,
  ).unwrap()
}

///|
fn vector_wire(owner : @lowering_relation.BoundPrepared) -> String raise {
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  @encode.finish(writer)
}

///|
test "checked vector operations lower without source rediscovery" {
  assert_eq(
    vector_wire(vector_owner("[3,4]")),
    "[{\"id\":\"to_vectors_0\",\"in\":[\"input_0\"],\"op\":\"BRIDGE.rows.to_vectors\",\"params\":{\"id\":\"product_id\",\"vector\":\"embedding\"}},{\"id\":\"normalize_vectors_1\",\"in\":[\"to_vectors_0\"],\"op\":\"VEC.normalize_l2\",\"params\":{}},{\"id\":\"score_vectors_2\",\"in\":[\"normalize_vectors_1\"],\"op\":\"VEC.score_sort\",\"params\":{\"metric\":\"cosine\",\"query\":[3,4]}}]",
  )
}

///|
test "vector query parameters resolve before canonical emission" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"q\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"length\":2}}",
      ),
    ),
    { max_parameters: 1, max_nodes: 20, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let values = match
    @parameter.bind(declarations, Some(cursor("{\"q\":[6,8]}")), {
      max_nodes: 20,
      max_depth: 10,
      max_text_bytes: 100,
    }).unwrap() {
    @parameter.Ready(values) => values
    @parameter.NeedsBindings(_) => abort("complete vector binding")
  }
  let wire = vector_wire(
    vector_owner(
      "{\"$param\":\"q\"}",
      declarations=Some(declarations),
      bindings=Some(values),
    ),
  )
  assert_true(wire.contains("\"query\":[6,8]"))
  assert_false(wire.contains("$param"))
}

///|
test "vector lowering admits parameter preparation before emission" {
  let exact = { ..sequence_limits(), max_bindings: 2, max_name_bytes: 19, }
  assert_true(
    @lowering_relation.prepare_sequence(vector_owner("[3,4]"), exact) is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(vector_owner("[3,4]"), {
      ..exact,
      max_bindings: 1,
    })
    is Err(
      @lowering_relation.VectorFailure(
        0,
        @lowering_relation.VectorPreparationLimit
      )
    ),
  )
}
