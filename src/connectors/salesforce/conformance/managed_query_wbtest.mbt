///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 20,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn plan(
  id_type? : String = "id",
  filterable? : Bool = false,
) -> @catalog.ReadProjection {
  let list = @catalog.project_resource_listing(
    @utf8.encode(
      (
        #|{"sobjects":[{"name":"Account","queryable":true}]}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = @catalog.begin_catalog_sync(list)
  let description = "{\"name\":\"Account\",\"queryable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"" +
    id_type +
    "\",\"nillable\":false,\"filterable\":" +
    filterable.to_string() +
    "},{\"name\":\"Name\",\"type\":\"string\",\"nillable\":true}]}"
  @catalog.catalog_sync_describe(sync, "Account", @utf8.encode(description), {
    max_bytes: 1000,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 10,
    max_name_units: 100,
  }).unwrap()
  @catalog.finish_catalog_sync(sync).unwrap()
  let binding : @catalog.CatalogObservationBinding = {
    namespace_id: "namespace-a",
    principal: "principal-a",
    environment: "test",
    connection_revision: "connection-a",
    org_id: "00D000000000001EAA",
    site_key: "site-a",
    site_generation: 1,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://example.invalid",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "sync-a",
  }
  let observation = @catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [Some(@catalog.catalog_response_sha256(@utf8.encode(description)))],
    4096,
  ).unwrap()
  @catalog.prepare_read_projection(
    observation,
    binding,
    "Account",
    ["Name", "Id"],
    100,
  ).unwrap()
}

///|
fn output_values(id_type : String) -> @execution.ManagedOutputValues {
  let pipeline = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"Id\":{\"type\":\"" +
      id_type +
      "\",\"nullable\":false},\"Name\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"Id\",\"Name\"]}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 20,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  @execution.prepare_managed_output_values(
    owner,
    Step(1),
    3,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
    100,
    { max_work: 100, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
}

///|
fn query_limits() -> @catalog.QueryPageLimits {
  {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_rows: 2,
    max_locator_units: 128,
  }
}

///|
test "Salesforce pages enter common managed output in schema order" {
  let plan = plan()
  let query = @acquisition.prepare_managed_query(
    plan,
    "v62.0",
    query_limits(),
    3,
    3L,
    output_values("string"),
  ).unwrap()
  let first = @acquisition.managed_query_next_path(query).unwrap().unwrap()
  assert_eq(
    first, "/services/data/v62.0/query?q=SELECT%20Name%2CId%20FROM%20Account",
  )
  let page = @acquisition.accept_managed_query_page(
    query,
    first,
    @utf8.encode(
      (
        #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC-2000","records":[{"Id":"001A","Name":"One"}]}
      ),
    ),
  ).unwrap()
  assert_false(@catalog.query_page_matches_projection(page, plan))
  assert_eq(@acquisition.managed_query_row_count(query), 1L)
  let last = @acquisition.managed_query_next_path(query).unwrap().unwrap()
  @acquisition.accept_managed_query_page(
    query,
    last,
    @utf8.encode(
      (
        #|{"totalSize":2,"done":true,"records":[{"Id":"001B","Name":null}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@acquisition.managed_query_complete(query))
  let receipt = @acquisition.finish_managed_query(query).unwrap()
  assert_eq(@execution.managed_output_value_row_count(receipt), 2)
  assert_true(@acquisition.finish_managed_query(query) is Err(Closed))
}

///|
test "empty terminal Salesforce query produces a measured empty output" {
  let query = @acquisition.prepare_managed_query(
    plan(),
    "v62.0",
    query_limits(),
    1,
    0L,
    output_values("string"),
  ).unwrap()
  assert_false(@acquisition.managed_query_complete(query))
  @acquisition.accept_managed_query_page(
    query,
    @acquisition.managed_query_next_path(query).unwrap().unwrap(),
    @utf8.encode(
      (
        #|{"totalSize":0,"done":true,"records":[]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@acquisition.managed_query_complete(query))
  let receipt = @acquisition.finish_managed_query(query).unwrap()
  assert_eq(@execution.managed_output_value_row_count(receipt), 0)
}

///|
test "Salesforce managed read rejects schema drift before physical query" {
  assert_true(
    @acquisition.prepare_managed_query(
      plan(),
      "v62.0",
      query_limits(),
      3,
      3L,
      output_values("number"),
    )
    is Err(InvalidOutputSchema),
  )
}

///|
test "managed output cannot borrow a caller-supplied row prefilter" {
  let supplied = @catalog.with_exact_int_comparison(
    plan(id_type="int", filterable=true),
    "Id",
    @catalog.Greater,
    2,
  ).unwrap()
  assert_true(
    @acquisition.prepare_managed_query(
      supplied,
      "v62.0",
      query_limits(),
      3,
      3L,
      output_values("number"),
    )
    is Err(UnexpectedPrefilter),
  )
}

///|
test "failed later Salesforce page cancels the common output owner" {
  let query = @acquisition.prepare_managed_query(
    plan(),
    "v62.0",
    query_limits(),
    3,
    3L,
    output_values("string"),
  ).unwrap()
  @acquisition.accept_managed_query_page(
    query,
    @acquisition.managed_query_next_path(query).unwrap().unwrap(),
    @utf8.encode(
      (
        #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC-2000","records":[{"Id":"001A","Name":"One"}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(
    @acquisition.accept_managed_query_page(
      query,
      @acquisition.managed_query_next_path(query).unwrap().unwrap(),
      @utf8.encode(
        (
          #|{"totalSize":2,"done":true,"records":[{"Id":42,"Name":null}]}
        ),
      ),
    )
    is Err(Query(_)),
  )
  assert_false(@acquisition.managed_query_complete(query))
  assert_true(@acquisition.managed_query_next_path(query) is Ok(None))
  assert_true(@acquisition.finish_managed_query(query) is Err(Closed))
}

///|
test "managed Salesforce page ceiling cancels before a continuation request" {
  let query = @acquisition.prepare_managed_query(
    plan(),
    "v62.0",
    query_limits(),
    1,
    3L,
    output_values("string"),
  ).unwrap()
  let first = @acquisition.managed_query_next_path(query).unwrap().unwrap()
  @acquisition.accept_managed_query_page(
    query,
    first,
    @utf8.encode(
      (
        #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC-2000","records":[{"Id":"001A","Name":"One"}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@acquisition.managed_query_next_path(query) is Err(Query(_)))
  assert_false(@acquisition.managed_query_complete(query))
  assert_true(@acquisition.finish_managed_query(query) is Err(Closed))
}
