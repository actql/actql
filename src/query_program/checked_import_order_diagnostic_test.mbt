///|
test "independent captured JOIN Program agrees under strict and check-only preparation" {
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.checked_import_sort","stages":[{"id":"capture","inputs":{"records":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id"]}}},{"id":"main","inputs":{"rows":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"rows","filter":{"eq":[{"field":"id"},{"literal":1}]},"as":"chosen"},{"from":"chosen","cross_join":{"with":"rows","max_output_rows":1000000,"select":{"left_id":"left.id","id":"right.id"}},"as":"paired"},{"select":["id"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let parameters = @stage_parameters.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let limits : @stage_results.LocalProgramLimits = {
    max_stages: 20,
    max_steps: 100,
    max_results: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }
  let strict = match @stage_results.prepare_local_program(parameters, limits) {
    Ok((wiring, _)) => wiring
    Err(Order(stage, PipelineOrder(issue))) =>
      fail(
        "strict pipeline order stage \{stage}: " + @debug.to_string(issue.kind),
      )
    Err(Order(stage, ResultOrder(issue))) =>
      fail(
        "strict Result order stage \{stage}: " + @debug.to_string(issue.kind),
      )
    Err(Pipeline(stage, issue)) =>
      fail("strict pipeline stage \{stage}: " + @debug.to_string(issue.kind))
    Err(_) => fail("strict preparation failed at another boundary")
  }
  let (checked, _) = @stage_results.check_local_program(parameters, limits).unwrap()
  assert_true(
    physical_equal(@stage_results.topology_source(checked), parameters),
  )
  let first = @stage_results.topology_stage_at(checked, 0).unwrap()
  let inputs = @stage_results.topology_stage_results(first)
  let publication = @relation_results.checked_input_publication(inputs, 0).unwrap()
  let strict_port = @relation_results.port_at(
    @stage_results.stage_port_publications(
      @stage_results.wiring_stage_at(strict, 0).unwrap(),
    ),
    0,
  ).unwrap()
  let strict_publication = @relation_results.port_publication(strict_port)
  assert_true(@pipeline.publication_strategy(publication) is CandidateKey)
  assert_eq(
    @pipeline.publication_strategy(publication),
    @pipeline.publication_strategy(strict_publication),
  )
  assert_eq(
    @pipeline.publication_target(publication),
    @pipeline.publication_target(strict_publication),
  )
  assert_eq(
    @pipeline.publication_term_count(publication),
    @pipeline.publication_term_count(strict_publication),
  )
  assert_eq(
    @pipeline.publication_term_at(publication, 0).unwrap().field,
    @pipeline.publication_term_at(strict_publication, 0).unwrap().field,
  )
  let key = @pipeline.publication_key(publication).unwrap()
  assert_eq(@evidence.key_field_count(key), 1)
  assert_eq(@evidence.key_field_at(key, 0).unwrap().name, Unqualified("id"))
  assert_eq(
    @relation.projection(@pipeline.publication_projection(publication)).length(),
    @relation_results.port_projection_count(strict_port),
  )
  assert_true(@relation_results.checked_input_order_pending(inputs, 0) is None)
  let input = @relation_results.checked_input_at(inputs, 0).unwrap()
  assert_true(
    physical_equal(
      @pipeline.producer_pipeline(input),
      @pipeline.publication_pipeline(publication),
    ),
  )
  assert_eq(
    @pipeline.producer_target(input),
    @pipeline.publication_target(publication),
  )
  assert_true(@pipeline.producer_projection(input) is Some(_))
}
