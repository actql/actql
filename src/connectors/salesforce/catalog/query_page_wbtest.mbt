///|
fn query_test_plan() -> ReadProjection {
  let (observation, binding) = read_test_observation()
  prepare_read_projection(observation, binding, "Account", ["Id"], 100).unwrap()
}

///|
fn query_test_limits() -> QueryPageLimits {
  {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_rows: 2,
    max_locator_units: 128,
  }
}

///|
test "query page projects a bounded batch and exact continuation" {
  let body =
    #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC-2000","records":[{"attributes":{"type":"Account"},"Id":"001A"}]}
  let bytes = @utf8.encode(body)
  let page = project_query_page(
    bytes,
    query_test_plan(),
    "v62.0",
    query_test_limits(),
  ).unwrap()
  assert_eq(query_page_row_count(page), 1)
  assert_false(query_page_done(page))
  assert_eq(
    query_page_next_url(page),
    Some("/services/data/v62.0/query/01gABC-2000"),
  )
  assert_eq(query_page_total_size(page), 2L)
  assert_eq(query_page_response_sha256(page), @sha.hex(bytes))
  match page.rows[0][0] {
    Value(value) => assert_eq(@decode.text(value).unwrap(), "001A")
    Null => abort("expected a value")
  }
}

///|
test "query page accepts an empty terminal batch without a locator" {
  let body =
    #|{"totalSize":0,"done":true,"records":[]}
  let page = project_query_page(
    @utf8.encode(body),
    query_test_plan(),
    "v62.0",
    query_test_limits(),
  ).unwrap()
  assert_true(query_page_done(page))
  assert_eq(query_page_row_count(page), 0)
  assert_eq(query_page_next_url(page), None)
}

///|
test "query page rejects foreign or ambiguous locators" {
  let plan = query_test_plan()
  for
    locator in [
      "https://foreign.invalid/services/data/v62.0/query/01gABC", "/services/data/v61.0/query/01gABC",
      "/services/data/v62.0/query/../query/01gABC", "/services/data/v62.0/query/01gABC?next=1",
      "/services/data/v62.0/query/01gABC/extra",
    ] {
    let body = "{\"totalSize\":2,\"done\":false,\"nextRecordsUrl\":\"" +
      locator +
      "\",\"records\":[]}"
    assert_true(
      project_query_page(@utf8.encode(body), plan, "v62.0", query_test_limits())
      is Err(InvalidLocator),
    )
  }
  let terminal_with_locator =
    #|{"totalSize":1,"done":true,"nextRecordsUrl":"/services/data/v62.0/query/01gABC","records":[]}
  assert_true(
    project_query_page(
      @utf8.encode(terminal_with_locator),
      plan,
      "v62.0",
      query_test_limits(),
    )
    is Err(InvalidLocator),
  )
}

///|
test "query page distinguishes invalid records from budget exhaustion" {
  let plan = query_test_plan()
  let three_rows =
    #|{"totalSize":3,"done":true,"records":[{"Id":"001A"},{"Id":"001B"},{"Id":"001C"}]}
  let body = @utf8.encode(three_rows)
  assert_true(
    project_query_page(body, plan, "v62.0", query_test_limits())
    is Err(BudgetExceeded),
  )
  assert_true(
    project_query_page(body, plan, "v62.0", {
      ..query_test_limits(),
      max_bytes: 16,
    })
    is Err(BudgetExceeded),
  )
  let extra_field =
    #|{"totalSize":1,"done":true,"records":[{"Id":"001A","Unexpected":"x"}]}
  assert_true(
    project_query_page(
      @utf8.encode(extra_field),
      plan,
      "v62.0",
      query_test_limits(),
    )
    is Err(UnexpectedField("Unexpected")),
  )
  let invalid_record =
    #|{"totalSize":1,"done":true,"records":[42]}
  assert_true(
    project_query_page(
      @utf8.encode(invalid_record),
      plan,
      "v62.0",
      query_test_limits(),
    )
    is Err(InvalidResponse),
  )
  let missing_required =
    #|{"totalSize":1,"done":true,"records":[{}]}
  assert_true(
    project_query_page(
      @utf8.encode(missing_required),
      plan,
      "v62.0",
      query_test_limits(),
    )
    is Err(MissingRequiredField("Id")),
  )
  let null_required =
    #|{"totalSize":1,"done":true,"records":[{"Id":null}]}
  assert_true(
    project_query_page(
      @utf8.encode(null_required),
      plan,
      "v62.0",
      query_test_limits(),
    )
    is Err(NullRequiredField("Id")),
  )
  assert_true(
    project_query_page(body, plan, "v62.0/../", query_test_limits())
    is Err(InvalidLimits),
  )
}
