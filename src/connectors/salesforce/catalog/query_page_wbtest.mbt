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
fn query_test_typed_plan(
  names : Array[String],
) -> Result[ReadProjection, ReadProjectionIssue] {
  let listing_body =
    #|{"sobjects":[{"name":"Account","queryable":true}]}
  let listing = project_resource_listing(@utf8.encode(listing_body), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_resources: 10,
    max_selected: 10,
    max_name_units: 100,
  }).unwrap()
  let sync = begin_catalog_sync(listing)
  let describe_body =
    #|{"name":"Account","queryable":true,"fields":[{"name":"Id","type":"id","nillable":false},{"name":"Name","type":"string","nillable":true},{"name":"Active__c","type":"boolean","nillable":false},{"name":"Amount__c","type":"currency","nillable":true}]}
  catalog_sync_describe(sync, "Account", @utf8.encode(describe_body), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  finish_catalog_sync(sync).unwrap()
  let binding = observation_test_binding()
  let response_digest = match catalog_sync_outcome(sync, "Account") {
    Some(Described(resource)) => resource.response_sha256
    _ => abort("expected described Account")
  }
  let observation = prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(response_digest)],
    4096,
  ).unwrap()
  prepare_read_projection(observation, binding, "Account", names, 128)
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
  assert_true(page.rows[0][0].value is @admitted.Text("001A"))
}

///|
test "query page retains its exact projection occurrence" {
  let plan = query_test_plan()
  let same_content = query_test_plan()
  let page = project_query_page(
    @utf8.encode(
      (
        #|{"totalSize":1,"done":true,"records":[{"Id":"001A"}]}
      ),
    ),
    plan,
    "v62.0",
    query_test_limits(),
  ).unwrap()
  assert_true(query_page_matches_projection(page, plan))
  assert_false(query_page_matches_projection(page, same_content))
}

///|
test "query admission binds the exact checked output field contract" {
  let plan = query_test_plan()
  let output_contract = @contract.primitive(StringType, nullable=false)
  let bound = bind_read_projection_contracts(plan, [output_contract]).unwrap()
  assert_eq(read_projection_soql(bound), read_projection_soql(plan))
  assert_true(
    bind_read_projection_contracts(plan, [
      @contract.primitive(NumberType, nullable=false),
    ])
    is None,
  )
  let page = project_query_page(
    @utf8.encode(
      (
        #|{"totalSize":1,"done":true,"records":[{"Id":"001A"}]}
      ),
    ),
    bound,
    "v62.0",
    query_test_limits(),
  ).unwrap()
  assert_true(physical_equal(page.rows[0][0].contract, output_contract))
  assert_false(query_page_matches_projection(page, plan))
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

///|
test "query page admits typed cells and preserves nullable missing values" {
  let plan = query_test_typed_plan(["Id", "Name", "Active__c"]).unwrap()
  let body =
    #|{"totalSize":2,"done":true,"records":[{"Id":"001A","Active__c":true},{"Id":"001B","Name":null,"Active__c":false}]}
  let page = project_query_page(
    @utf8.encode(body),
    plan,
    "v62.0",
    query_test_limits(),
  ).unwrap()
  assert_true(
    query_page_cell(page, 0, 0).unwrap().value is @admitted.Text("001A"),
  )
  assert_true(query_page_cell(page, 0, 1).unwrap().value is @admitted.Null)
  assert_true(
    query_page_cell(page, 0, 2).unwrap().value is @admitted.Boolean(true),
  )
  assert_true(query_page_cell(page, 1, 1).unwrap().value is @admitted.Null)
  assert_true(
    query_page_cell(page, 1, 2).unwrap().value is @admitted.Boolean(false),
  )
  assert_true(query_page_cell(page, 2, 0) is None)
}

///|
test "query value admission rejects type changes and noncanonical text" {
  let plan = query_test_typed_plan(["Id", "Name", "Active__c"]).unwrap()
  let wrong_type =
    #|{"totalSize":1,"done":true,"records":[{"Id":"001A","Active__c":"true"}]}
  assert_true(
    project_query_page(
      @utf8.encode(wrong_type),
      plan,
      "v62.0",
      query_test_limits(),
    )
    is Err(ValueAdmission("Active__c", @admitted.Decode(_))),
  )
  let noncanonical =
    #|{"totalSize":1,"done":true,"records":[{"Id":"001A","Name":"e\u0301","Active__c":true}]}
  assert_true(
    project_query_page(
      @utf8.encode(noncanonical),
      plan,
      "v62.0",
      query_test_limits(),
    )
    is Err(
      ValueAdmission(
        "Name",
        @admitted.ValueIssue(@admitted.NonCanonicalText, ..)
      )
    ),
  )
  assert_true(
    query_test_typed_plan(["Amount__c"])
    is Err(UnsupportedReadType("Amount__c")),
  )
}
