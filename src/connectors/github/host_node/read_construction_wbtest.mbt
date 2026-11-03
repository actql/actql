///|
test "GitHub Source backs initial requests then grows only actual native response geometry" {
  let initial = github_source_read_construction_capacity(
    4000000, 400000, 32, 100, 10, 100, 0, original_node_http_header_bound(),).unwrap()
  let small = github_source_read_construction_capacity(
    4000000, 400000, 32, 100, 10, 100, 512, original_node_http_header_bound(),).unwrap()
  let full = github_source_read_construction_capacity(
    4000000, 400000, 32, 100, 10, 100, 4000000, original_node_http_header_bound(),).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(initial) > 0L)
  assert_true(
    @execution.execution_capacity_retained_bytes(small) >
    @execution.execution_capacity_retained_bytes(initial),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(small) >
    @execution.execution_capacity_retained_bytes(small),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(full) >
    @execution.execution_capacity_execution_bytes(small),
  )
  assert_true(
    github_source_read_construction_capacity(
      4000000, 400000, 32, 100, 10, 100, 4000001, original_node_http_header_bound(),)
    is None,
  )
  assert_true(
    github_source_read_construction_capacity(
      4000000, 400000, 32, 100, 10, 100, -1, original_node_http_header_bound(),)
    is None,
  )
  assert_true(
    github_source_read_construction_capacity(
      4000000, 400000, 32, 100, 0, 100, 1, original_node_http_header_bound(),)
    is None,
  )
  assert_true(
    github_source_read_construction_capacity(
      2147483647, 2147483647, 32, 2147483647, 2147483647, 2147483647, 2147483647, original_node_http_header_bound(),)
    is None,
  )
}

///|
test "GitHub Source request quantity covers original escaped node cursor and all fixed document families" {
  let node = "\u{1}".repeat(256)
  let cursor = "\u{2}".repeat(1024)
  let issue = @catalog.issues_request(node, 100, Some(cursor), {
    state: "all",
    labels: [],
    since: None,
  }).unwrap()
  let pull = @catalog.pull_requests_request(node, 100, Some(cursor), {
    state: "all",
    labels: [],
  }).unwrap()
  let comment = @catalog.issue_comments_request(
    {
      node_id: node,
      number: 1L,
      native_type: "PullRequest",
      updated_at: "",
      repository: { node_id: node, database_id: 1L, name_with_owner: "o/r", },
    },
    100,
    Some(cursor),
  ).unwrap()
  let subjects = @catalog.issue_comment_subjects_request(
    node,
    "PullRequest",
    100,
    Some(cursor),
  ).unwrap()
  let quoted = github_read_request_inventory().unwrap()
  for body in [issue, pull, comment, subjects] {
    assert_true(quoted.owned_utf16_units >= body.length().to_int64())
  }
  assert_true(
    @catalog.source_read_query_units() >= @catalog.issues_query.length(),
  )
  assert_true(
    @catalog.source_read_query_units() >= @catalog.pull_requests_query.length(),
  )
}
