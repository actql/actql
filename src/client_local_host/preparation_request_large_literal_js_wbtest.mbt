///|
test "funded Request parses and lowers a large literal under its existing Program preparation profile" {
  let (environment, publication) = request_query_publication_fixture()
  let document = "SELECT [" + "0,".repeat(19999) + "0] AS payload"
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
  let query = parse_request_query_syntax(parent, input, document, @frontend.Sql).unwrap()
  assert_true(
    @query_syntax.token_count(@query_syntax.query_source(query)) > 40000,
  )
  let lowered = lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    None,
    public_primary=true,
  ).unwrap()
  assert_true(lowered.0.program is Some(_))
  assert_true(
    physical_equal(parent.held_program.unwrap(), lowered.0.program.unwrap()),
  )
  assert_eq(parent._observed_query_parse_calls, 1L)
  assert_eq(parent._observed_query_lower_calls, 1L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
