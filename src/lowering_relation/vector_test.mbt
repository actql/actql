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
fn vector_carrier() -> @carrier.Carrier {
  guard vector_relation() is @carrier.Relation(rows) else { abort("relation") }
  @carrier.vectors(
    rows,
    ids=[@schema.Unqualified("product_id")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=1,
  ).unwrap()
}

///|
fn vector_text_relation() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("product_id"),
          Some(@contract.primitive(@contract.StringType, nullable=false)),
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
test "checked vector pooling lowers canonical parameters" {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"product_id\"],\"method\":\"mean\",\"output_id\":\"group_id\"}}]",
    ),
    [("vectors", vector_carrier())],
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
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=100,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.VectorStep(pool)) else {
    fail("pool step")
  }
  assert_eq(@lowering_relation.vector_pool_group_count(pool), Some(1))
  assert_eq(
    @lowering_relation.vector_pool_group_at(pool, 0),
    Some("product_id"),
  )
  assert_eq(
    @lowering_relation.vector_pool_method(pool),
    Some(@lowering_relation.PoolMean),
  )
  assert_eq(@lowering_relation.vector_pool_output_id(pool), Some("group_id"))
  assert_eq(@lowering_relation.vector_pool_vector_role(pool), Some("embedding"))
  assert_eq(@lowering_relation.vector_pool_identity_count(pool), Some(0))
  assert_eq(
    @lowering_relation.vector_pool_encodes_member_identity(pool),
    Some(false),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"pool_vectors_0\",\"in\":[\"input_0\"],\"op\":\"VEC.pool\",\"params\":{\"by\":[\"product_id\"],\"method\":\"mean\",\"output_id\":\"group_id\",\"vector\":\"embedding\"}}]",
  )
}

///|
test "relation pooling lowers member identity and vector bridge" {
  let declaration = @evidence.declare_primary_key(
    cursor("[\"product_id\"]"),
    vector_relation(),
    { max_fields: 1, max_name_bytes: 32, },
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    cursor(
      "[{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"product_id\"],\"method\":\"sum\"}}]",
    ),
    [("rows", @pipeline.KeyedInput(declaration))],
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
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let usage = @lowering_relation.usage(prepared)
  assert_eq(usage.nodes, 4)
  assert_eq(usage.references, 3)
  assert_true(
    @lowering_relation.prepare(checked, {
      max_nodes: usage.nodes,
      max_references: usage.references,
      max_work: usage.work,
      max_identifier_bytes: usage.identifier_bytes,
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare(checked, {
      max_nodes: usage.nodes - 1,
      max_references: usage.references,
      max_work: usage.work,
      max_identifier_bytes: usage.identifier_bytes,
    })
    is Err({ kind: @lowering_relation.BudgetExceeded, .. }),
  )
  assert_true(
    @lowering_relation.prepare(checked, {
      max_nodes: usage.nodes,
      max_references: usage.references - 1,
      max_work: usage.work,
      max_identifier_bytes: usage.identifier_bytes,
    })
    is Err({ kind: @lowering_relation.BudgetExceeded, .. }),
  )
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=100,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.VectorStep(pool)) else {
    fail("pool step")
  }
  assert_eq(@lowering_relation.vector_pool_identity_count(pool), Some(1))
  assert_eq(
    @lowering_relation.vector_pool_identity_at(pool, 0),
    Some("product_id"),
  )
  assert_eq(
    @lowering_relation.vector_pool_encodes_member_identity(pool),
    Some(true),
  )
  assert_true(@lowering_relation.vector_pool_member_vectors(pool) is Some(_))
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 0),
    Some(3),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 0, 0).map(occurrence => {
      occurrence.operation
    }),
    Some("REL.derive"),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 0, 1).map(occurrence => {
      occurrence.operation
    }),
    Some("BRIDGE.rows.to_vectors"),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 0, 2).map(occurrence => {
      occurrence.operation
    }),
    Some("VEC.pool"),
  )
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let wire = @encode.finish(writer)
  assert_true(wire.contains("\"id\":\"vector_member_identity_0\""))
  assert_true(wire.contains("\"op\":\"REL.derive\""))
  assert_true(wire.contains("\"id\":\"vector_members_0\""))
  assert_true(wire.contains("\"op\":\"BRIDGE.rows.to_vectors\""))
  assert_true(wire.contains("\"id\":\"__actql_vector_record_id\""))
  assert_true(
    wire.contains(
      "\"id\":\"pool_vectors_0\",\"in\":[\"vector_members_0\"],\"op\":\"VEC.pool\"",
    ),
  )
}

///|
test "relation pooling reuses an admitted singleton string identity" {
  let relation = vector_text_relation()
  let declaration = @evidence.declare_primary_key(
    cursor("[\"product_id\"]"),
    relation,
    { max_fields: 1, max_name_bytes: 32, },
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    cursor(
      "[{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"product_id\"],\"method\":\"max\"}}]",
    ),
    [("rows", @pipeline.KeyedInput(declaration))],
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
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=100,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.VectorStep(pool)) else {
    fail("pool step")
  }
  assert_eq(@lowering_relation.vector_pool_identity_count(pool), Some(1))
  assert_eq(
    @lowering_relation.vector_pool_identity_at(pool, 0),
    Some("product_id"),
  )
  assert_eq(
    @lowering_relation.vector_pool_encodes_member_identity(pool),
    Some(false),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 0),
    Some(2),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let wire = @encode.finish(writer)
  assert_false(wire.contains("__actql_vector_record_id"))
  assert_false(wire.contains("\"op\":\"REL.derive\""))
  assert_true(wire.contains("\"id\":\"product_id\""))
  assert_true(wire.contains("\"method\":\"max\""))
}

///|
test "prepared score view exposes resolved runtime inputs" {
  let owner = vector_owner("[3,4]")
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.VectorStep(score)) else {
    fail("score step")
  }
  assert_eq(
    @lowering_relation.vector_score_metric(score),
    Some(@lowering_relation.CosineScore),
  )
  assert_eq(@lowering_relation.vector_score_query_count(score), Some(2))
  assert_eq(@lowering_relation.vector_score_query_at(score, 0), Some(3.0))
  assert_eq(@lowering_relation.vector_score_query_at(score, 1), Some(4.0))
  assert_true(
    @lowering_relation.vector_output_carrier(score) is @carrier.VectorValue(_),
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
