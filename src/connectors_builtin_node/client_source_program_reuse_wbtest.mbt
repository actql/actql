///|
test "Source preparation retains the exact lowerer Program and authored span" {
  let context = @source_frontend.bind_query_context([], "visible-environment").unwrap()
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    let lowered = @source_frontend.lower(
      "/*😀*/\r\nSELECT @missing AS n",
      format,
      Some(context),
      source_path="submitted.sql",
    ).unwrap()
    let original = lowered.program.unwrap()
    let retained = client_source_program(lowered).unwrap()
    assert_true(physical_equal(retained, original))
    let body = @stage_syntax.stage_body(@stage_syntax.stages(retained)[0])
    let steps = @decode.elements(
      @decode.required(@decode.open_object(body).unwrap(), "steps").unwrap(),
    ).unwrap()
    let derived = @decode.required(
      @decode.open_object(steps[1]).unwrap(),
      "derive",
    ).unwrap()
    let expression = @decode.required(
      @decode.open_object(derived).unwrap(),
      "aql_query_expr_0",
    ).unwrap()
    let span = @decode.cursor_span(expression)
    assert_eq(span.source_path, "submitted.sql")
    assert_eq(span.start_byte, 17)
    assert_eq(span.end_byte, 25)
  }
}

///|
test "Source preparation does not reconstruct a missing admitted Program" {
  let lowered = @source_frontend.lower("{}", Json, None).unwrap()
  assert_true(
    client_source_program(lowered) is Err(SourcePreparation(Frontend(Encoding))),
  )
}

///|
test "Source reused Program keeps current input limits and canonical identity" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let lowered = client_program_lower_source(
    "SELECT 1 AS id",
    "sql",
    environment,
    publication,
    None,
  ).unwrap()
  let original = client_source_program(lowered).unwrap()
  let limits = client_program_standard_limits()
  let usage = @stage_syntax.program_usage(original)
  let short = {
    ..limits,
    checking: {
      ..limits.checking,
      input: {
        ..limits.checking.input,
        tree: { ..limits.checking.input.tree, max_nodes: usage.tree.nodes - 1, },
      },
    },
  }
  assert_true(
    @publication_host.prepare_parsed_effect_free_client_program(
      original,
      environment,
      None,
      short,
    )
    is Err(_),
  )
  let canonical = match
    client_program_prepare_effect_free_with_parameters(
      lowered.document,
      "json",
      environment,
      None,
    ) {
    Prepared(value) => value
    _ => fail("the existing explicit Program route must remain supported")
  }
  let legacy = match
    client_program_prepare_source_with_parameters(
      "SELECT 1 AS id",
      "sql",
      environment,
      publication,
      None,
      None,
    ) {
    Prepared(value) => value
    _ => fail("the legacy Source entry must prepare its original Program")
  }
  let current = match
    client_program_prepare_source_computation_with_parameters(
      "SELECT 1 AS id",
      "sql",
      environment,
      publication,
      None,
      None,
      false,
      [],
    ) {
    SourcePure(Prepared(value)) => value
    _ => fail("the ordinary Source entry must prepare its original Program")
  }
  let expected = @publication_host.prepared_client_program_semantics_cid(
    canonical,
  )
  assert_eq(
    @publication_host.prepared_client_program_semantics_cid(legacy),
    expected,
  )
  assert_eq(
    @publication_host.prepared_client_program_semantics_cid(current),
    expected,
  )
}
