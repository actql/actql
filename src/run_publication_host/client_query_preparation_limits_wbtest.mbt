///|
test "Program preparation syntax projection preserves explicitly narrowed tokens and work" {
  let original = client_standard_program_preparation_limits()
  let selected = {
    ..original,
    lowering: { ..original.lowering, max_nodes: 16, max_work: 1000, },
  }
  let limits = client_program_query_syntax_limits(selected)
  assert_eq(limits.lexical.max_tokens, 16)
  assert_eq(limits.max_syntax_nodes, 16)
  assert_eq(limits.lexical.max_work, 1000)
  assert_eq(
    limits.max_cte_count,
    @source_frontend.syntax_limits().max_cte_count,
  )
  let (result, spent, complete) = @source_frontend.observe_parse_query(
    "SELECT [0,0,0,0,0,0,0,0,0,0] AS payload",
    @source_frontend.Sql,
    limits=Some(limits),
  )
  assert_true(result is Err(QuerySyntax(_)))
  assert_true(spent > 0L)
  // No parser phase follows the refused lexical prefix.
  assert_false(complete)
}

///|
test "original Source lowerer receives the selected generated-artifact bound and keeps refusal consumed" {
  let (input, publication) = source_original_input_fixture("SELECT 7 AS n")
  let profile = client_standard_program_preparation_limits()
  let query = observe_client_source_input_query(
    input,
    limits=Some(client_program_query_syntax_limits(profile)),
  ).unwrap().0.unwrap()
  let original = client_program_query_lowering_limits(profile)
  assert_eq(
    original.source.max_output_bytes,
    profile.checking.compilation.artifacts.bytes,
  )
  assert_eq(
    original.program.tree.max_nodes,
    profile.checking.compilation.artifacts.nodes,
  )
  assert_eq(
    original.max_collection_bytes,
    @source_frontend.query_limits().max_collection_bytes,
  )
  let short = {
    ..original,
    source: { ..original.source, max_output_bytes: 1, },
  }
  assert_true(
    lower_client_source_input_query(
      input,
      publication,
      input.environment,
      query,
      limits=Some(short),
    )
    is Err(_),
  )
  assert_true(input.lowering_started)
  assert_true(
    lower_client_source_input_query(
      input,
      publication,
      input.environment,
      query,
      limits=Some(original),
    )
    is Err(Input),
  )
}
