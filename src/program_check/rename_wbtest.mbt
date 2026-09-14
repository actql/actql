///|
test "formal rename preserves imported keys and order through take and publication" {
  for
    (body, key_name) in [
      ("{}", "id"),
      ("{\"id\":\"value\",\"value\":\"id\"}", "value"),
    ] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=programs,
      second_steps="[{\"rename\":" +
        body +
        ",\"as\":\"renamed\"},{\"take\":1,\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let program = programs[0]
    let pipeline = unit_pipeline(program, 1).unwrap()
    assert_eq(@pipeline.step_count(pipeline), 2)
    let renamed = @pipeline.lookup(pipeline, "renamed").unwrap()
    let schema = @pipeline.schema_at(pipeline, renamed).unwrap()
    assert_eq(@schema.field_count(schema), 2)
    assert_true(@schema.lookup(schema, Unqualified("id")) is Some(_))
    assert_true(@schema.lookup(schema, Unqualified("value")) is Some(_))
    let key = @pipeline.candidate_key(pipeline, renamed).unwrap()
    assert_eq(@evidence.key_field_count(key), 1)
    assert_eq(
      @evidence.key_field_at(key, 0).unwrap().name,
      Unqualified(key_name),
    )
    // A simultaneous swap transfers the original id key to value, not back to id.
    let order = @pipeline.take_order(pipeline, 1).unwrap()
    assert_true(@pipeline.order_producer(order) is None)
    let upstream = @pipeline.order_input_producer(order).unwrap()
    assert_true(
      physical_equal(
        @pipeline.producer_pipeline(upstream),
        unit_pipeline(program, 0).unwrap(),
      ),
    )
    let publication = unit_publication_at(program, 1, 0).unwrap()
    let selected = @context.publication_row_limit_result(
      publication_selection(publication),
    )
    assert_eq(
      @pipeline.publication_target(@publication.port_publication(selected.port)),
      @pipeline.lookup(pipeline, "selected").unwrap(),
    )
    assert_eq(
      @publication.publication_strategy(@publication.port_order(selected.port)),
      Inherited,
    )
    assert_true(
      @publication.publication_inherited_order(
        @publication.port_order(selected.port),
      )
      is Some(_),
    )
  }
}

///|
test "formal rename retains producer bounds without erasing authored no-op identity" {
  let programs : Array[CheckedProgram] = []
  for
    steps in [
      "[]", "[{\"rename\":{},\"as\":\"selected\"}]", "[{\"rename\":{\"id\":\"value\",\"value\":\"id\"},\"as\":\"selected\"}]",
    ] {
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=programs,
      generated_rows=Some("[{\"id\":1}]"),
      generated_proofs=[keyed_sourceview_claim()],
      generated_proof_stage=0,
      second_steps=steps,
      second_result_from=if steps == "[]" { "rows" } else { "selected" },
      extra_step_budget=1,
    )
  }
  for i in 0..<programs.length() {
    let program = programs[i]
    assert_eq(
      unit_definition_cid(program, 0),
      unit_definition_cid(programs[0], 0),
    )
    if i > 0 {
      assert_true(
        unit_definition_cid(program, 1) != unit_definition_cid(programs[0], 1),
      )
    }
    let publication = unit_publication_at(program, 1, 0).unwrap()
    assert_eq(
      @context.publication_row_limit_maximum(publication_selection(publication)),
      1L,
    )
    assert_true(publication_proof_count(publication) > 0)
    for j in 0..<publication_proof_count(publication) {
      let proof = publication_proof_at(publication, j).unwrap()
      assert_eq(
        proof_source(proof).unit_definition_cid,
        unit_definition_cid(program, 0).unwrap(),
      )
      assert_true(
        physical_equal(
          proof_source(proof).pipeline,
          unit_pipeline(program, 0).unwrap(),
        ),
      )
    }
  }
}
