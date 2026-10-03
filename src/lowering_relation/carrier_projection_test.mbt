///|
fn carrier_projection_owner(
  source : String,
  inputs : Array[(String, @carrier.Carrier)],
) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(cursor(source), inputs, None, None, {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "Vectors projection retains its registered typed operation" {
  let vectors = carrier_projection_owner(
    "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"product_id\",\"vector\":\"embedding\"}},{\"vectors\":true}]",
    [("rows", vector_relation())],
  )
  let vector_sequence = @lowering_relation.prepare_sequence(
    vectors,
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(vector_sequence, 1)
    is Some(@lowering_relation.CarrierProjectionStep(projected)) else {
    fail("expected vector projection")
  }
  assert_eq(
    @lowering_relation.carrier_projection_operation(projected),
    @projection.Vectors,
  )
}

///|
test "current property node rows lower as typed Bridge without reviving edge tuples" {
  let owner = carrier_projection_owner(
    "[{\"from\":\"g\",\"node_rows\":true}]",
    [("g", graph_match_carrier())],
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.CarrierProjectionStep(projected)) else {
    fail("expected node row projection")
  }
  assert_eq(
    @lowering_relation.carrier_projection_operation(projected),
    @projection.NodeRows,
  )
  assert_true(
    @lowering_relation.carrier_projection_node_rows(projected) is Some(_),
  )
  for operation in ["edge_rows"] {
    let issue = @pipeline.check_carriers(
      cursor("[{\"from\":\"g\",\"" + operation + "\":true}]"),
      [("g", graph_match_carrier())],
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
    ).unwrap_err()
    assert_true(
      issue.kind is @pipeline.Projection(@projection.UnsupportedGraphOperation),
    )
    assert_true(issue.path.contains(@source.Key(operation)))
  }
}
