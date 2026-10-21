///|
test "public Source main and historical answer remain separate original Programs" {
  let environment = store_source_preparation_environment()
  let publication = store_public_bridge_publication(environment)
  for format in ["sql", "aql-text"] {
    let original = client_program_prepare_source_computation_with_parameters(
      "SELECT 1 AS id",
      format,
      environment,
      publication,
      None,
      None,
      false,
      [],
    )
    let public = client_program_prepare_public_source_computation_with_parameters(
      "SELECT 1 AS id",
      format,
      environment,
      publication,
      None,
      None,
      false,
      [],
    )
    guard original is SourcePure(Prepared(answer)) else {
      fail("historical preparation")
    }
    guard public is SourcePure(Prepared(main)) else {
      fail("public preparation")
    }
    assert_eq(client_program_result_name(answer, 0), Some("answer"))
    assert_eq(client_program_result_name(main, 0), Some("main"))
    assert_true(
      client_program_definition_cid(answer) !=
      client_program_definition_cid(main),
    )
  }
}

///|
test "public Source keeps explicit names and original terminal STORE output" {
  let environment = store_source_preparation_environment()
  let publication = store_public_bridge_publication(environment)
  for name in ["answer", "main", "MiXeD"] {
    let outcome = client_program_prepare_public_source_computation_with_parameters(
      "SELECT 1 AS id |> RESULT " + name,
      "aql-text",
      environment,
      publication,
      None,
      None,
      false,
      [],
    )
    guard outcome is SourcePure(Prepared(value)) else {
      fail("explicit preparation")
    }
    assert_eq(client_program_result_name(value, 0), Some(name))
  }
  let old = client_program_lower_source(
    store_source_preparation_text(),
    "sql",
    environment,
    publication,
    None,
  ).unwrap()
  let public = client_program_lower_source(
    store_source_preparation_text(),
    "sql",
    environment,
    publication,
    None,
    public_primary=true,
  ).unwrap()
  assert_eq(public.document, old.document)
  assert_eq(@stage_syntax.export_count(public.program.unwrap()), 0)
}
