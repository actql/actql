///|
// Drive only the provider's original acquisition child. A later checked
// Program projection remains outside this reader's capture boundary.
fn bigquery_capture_result(
  read : @bigquery_read.Read,
) -> Result[@row_host.RowSourceCapture, @bigquery_read.ReadIssue] raise {
  match @bigquery_read.begin_result_capture(read) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let mut previous = 0L
  for _ in 0..<1000 {
    let (done, work) = match @bigquery_read.advance_result_capture(read, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    assert_true(work >= previous)
    previous = work
    if done {
      return @bigquery_read.capture_result_read(read)
    }
  }
  fail("Original bigquery capture did not finish within the fixture work bound")
}

///|
fn bigquery_description_limits() -> @bigquery_catalog.DescriptionLimits {
  {
    max_bytes: 4096,
    max_nodes: 1000,
    max_depth: 16,
    max_fields: 16,
    max_name_bytes: 4096,
    max_schema_bytes: 4096,
  }
}

///|
fn bigquery_read_limits() -> @bigquery_catalog.QueryLimits {
  {
    description: bigquery_description_limits(),
    max_rows: 2,
    max_total_rows: 2L,
    max_value_nodes: 1000,
    max_value_text_bytes: 4096,
    max_job_bytes: 1024,
    max_page_token_bytes: 256,
  }
}

///|
fn bigquery_fields() -> Array[Json] {
  [
    Json::object(
      Map([
        ("name", "ACCOUNT_ID".to_json()),
        ("type", "STRING".to_json()),
        ("mode", "REQUIRED".to_json()),
      ]),
    ),
    Json::object(
      Map([
        ("name", "ACTIVE_USERS".to_json()),
        ("type", "BIGNUMERIC".to_json()),
        ("mode", "REQUIRED".to_json()),
        ("precision", "38".to_json()),
        ("scale", "0".to_json()),
      ]),
    ),
    Json::object(
      Map([
        ("name", "TREND".to_json()),
        ("type", "STRING".to_json()),
        ("mode", "NULLABLE".to_json()),
      ]),
    ),
  ]
}

///|
fn bigquery_read_description(
  fields? : Array[Json]? = None,
) -> @bigquery_catalog.TableDescription {
  let body = Json::object(
    Map([
      ("kind", "bigquery#table".to_json()),
      ("etag", "metadata-original".to_json()),
      ("type", "TABLE".to_json()),
      (
        "tableReference",
        Json::object(
          Map([
            ("projectId", "acme-project".to_json()),
            ("datasetId", "product".to_json()),
            ("tableId", "usage".to_json()),
          ]),
        ),
      ),
      (
        "schema",
        Json::object(
          Map([("fields", fields.unwrap_or(bigquery_fields()).to_json())]),
        ),
      ),
    ]),
  )
  @bigquery_catalog.project_table_description(
    @bigquery_catalog.table_target("acme-project", "product", "usage", 1024).unwrap(),
    @utf8.encode(body.stringify()),
    bigquery_description_limits(),
  ).unwrap()
}

///|
fn bigquery_read_preparation(
  query_text? : String = "SELECT ACCOUNT_ID, ACTIVE_USERS, TREND FROM bigquery.usage_30d",
  description? : @bigquery_catalog.TableDescription? = None,
) -> Result[@bigquery_read.PreparedRead, @bigquery_read.ReadIssue] raise {
  let description = description.unwrap_or(bigquery_read_description())
  let declared = @bigquery_catalog.prepare_read_projection(
    description,
    ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"],
    bigquery_description_limits(),
  ).unwrap()
  let declaration = @bigquery_catalog.generate_read_declaration(
    declared,
    "usage_30d",
    "bigquery",
    "bigquery/0.1",
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 1,
      max_fields: 3,
    },
  ).unwrap()
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  let (wire, original_cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    [],
    host_policy="{\"capacity\":{\"max_aggregate_array_items\":10000,\"max_artifact_bytes\":10000,\"max_artifact_rows\":10000,\"max_effect_items\":10000,\"max_graph_input_edges\":10000,\"max_graph_input_nodes\":10000,\"max_graph_output_rows\":10000,\"max_graph_paths\":10000,\"max_infer_items\":10000,\"max_model_input_tokens_per_item\":10000,\"max_model_request_bytes_per_item\":10000,\"max_model_total_duration_ms\":10000,\"max_nested_value_bytes\":10000,\"max_nested_value_depth\":10000,\"max_relation_output_rows\":10000,\"max_temporal_matches_per_key\":10000,\"max_temporal_output_rows\":10000,\"version\":\"actql-capacity-host-policy/0.1\"}}",
  )
  let body = wire
    .replace(old=",\"evidence_bundle_cid\":\"" + original_cid + "\"", new="")
    .replace(
      old="\"connector_capabilities\":[]",
      new="\"connector_capabilities\":[" + capabilities.join(",") + "]",
    )
    .replace(
      old="\"schema_snapshots\":[]",
      new="\"schema_snapshots\":[" + schemas.join(",") + "]",
    )
  let cid = text_cid(body)
  let complete = body.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let catalog = query_catalog_from_wire(complete, expected=cid)
  // The ordinary query compiler owns the explicit Source capture boundary.
  // Do not repair a handwritten low-level Program by injecting a true filter.
  let lexical : @snowflake_query_syntax.LexicalLimits = {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 10000,
    max_work: 20000,
  }
  let query = @snowflake_query_syntax.parse_query(query_text, {
    lexical,
    expression: { lexical, max_nodes: 1000, max_depth: 100, max_work: 10000, },
    max_syntax_nodes: 1000,
    max_cte_count: 20,
    max_work: 20000,
  }).unwrap()
  let limits : @snowflake_query_program.Limits = {
    source: {
      source: { max_input_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 100000,
      },
      max_origin_entries: 20000,
      max_output_bytes: 100000,
    },
    program: {
      source: { max_input_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 100000,
      },
      max_stages: 20,
    },
    max_expression_work: 10000,
    max_join_output_rows: 1000L,
    max_collection_items: 1000L,
    max_collection_bytes: 10000L,
  }
  let source = @decode.admit(
    @source.parse_json(
      "{\"connector\":\"bigquery\",\"resource\":\"usage_30d\"}",
      limits.source.source,
    ).unwrap(),
    limits.source.tree,
  ).unwrap()
  let program = @snowflake_query_program.compile(
    query,
    {
      program_id: "fixture.bigquery_read",
      stage_id: "main",
      stage_result: "rows",
      result_name: "answer",
      captured_stage: Some("capture"),
      parameter_declarations: None,
      inputs: [
        {
          relation: [
            { value: "bigquery", quoted: false, },
            { value: "usage_30d", quoted: false, },
          ],
          name: "remote",
          source: Captured(source),
          visible_fields: ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"],
          graph_bindings: [],
        },
      ],
      input_schemas: [],
      source_catalog: Some(catalog),
      model_tasks: None,
      calendar_profile: None,
    },
    limits,
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @syntax.emit_program_source(program, writer)
  let checked = query_checked_program_fixture(
    catalog=Some(catalog),
    program_text=Some(@encode.finish(writer)),
    parameter_json="{}",
  )
  let sequence = query_checked_sequence(checked)
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let (query, evidence) = query_evidence_test_bodies()
  @bigquery_read.prepare_declared_read(
    description,
    declaration,
    requirement,
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
    bigquery_description_limits(),
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 1,
      max_fields: 3,
    },
  )
}

///|
fn bigquery_job() -> @bigquery_catalog.QueryJob {
  @bigquery_catalog.query_job("acme-project", "original_job-1", "EU", 1024).unwrap()
}

///|
fn bigquery_row(account : String, users : String, trend : Json) -> Json {
  Json::object(
    Map([
      (
        "f",
        [account.to_json(), users.to_json(), trend]
        .map(v => Json::object(Map([("v", v)])))
        .to_json(),
      ),
    ]),
  )
}

///|
fn bigquery_body(
  rows : Array[Json],
  schema_fields? : Array[Json]? = None,
  token? : String? = None,
  total? : String = "2",
  job? : String = "original_job-1",
) -> Bytes {
  let fields = Map([
    ("kind", "bigquery#getQueryResultsResponse".to_json()),
    (
      "jobReference",
      Json::object(
        Map([
          ("projectId", "acme-project".to_json()),
          ("jobId", job.to_json()),
          ("location", "EU".to_json()),
        ]),
      ),
    ),
    ("jobComplete", true.to_json()),
    (
      "schema",
      Json::object(
        Map([("fields", schema_fields.unwrap_or(bigquery_fields()).to_json())]),
      ),
    ),
    ("totalRows", total.to_json()),
    ("rows", rows.to_json()),
  ])
  if token is Some(value) {
    fields["pageToken"] = value.to_json()
  }
  @utf8.encode(Json::object(fields).stringify())
}

///|
fn bigquery_rows() -> Array[Json] {
  [
    bigquery_row(
      "a1",
      "99999999999999999999999999999999999999",
      "down".to_json(),
    ),
    bigquery_row("a2", "0", Json::null()),
  ]
}

///|
fn bigquery_read_ledger(
  prepared : @bigquery_read.PreparedRead,
  transfer : Int64,
) -> @resources.Ledger {
  let acquisition = @bigquery_read.prepared_read_acquisition(prepared)
  @resources.create_ledger({
    planning_work: 100,
    attempts: 2,
    holdings: 2,
    transfer_bytes: transfer,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition),
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    4096L,
  }).unwrap()
}

///|
fn bigquery_started_read(
  nonce : String,
  transfer : Int64,
  stopped? : Ref[Bool] = Ref(true),
  max_pages? : Int = 4,
) -> (@bigquery_read.Read, @resources.Ledger) raise {
  let prepared = bigquery_read_preparation().unwrap()
  let ledger = bigquery_read_ledger(prepared, transfer)
  guard @bigquery_read.start_accounted_read(
      prepared,
      bigquery_job(),
      nonce,
      _ => stopped.val,
      ledger,
      transfer,
      4096L,
      bigquery_read_limits(),
      max_pages,
    )
    is Ok(read) else {
    fail("BigQuery original fixture start refused")
  }
  (read, ledger)
}

///|
fn bigquery_assert_retired(
  read : @bigquery_read.Read,
  ledger : @resources.Ledger,
) -> Unit raise {
  @bigquery_read.close_result_read(read).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_true(@bigquery_read.result_read_job(read) is None)
}

///|
fn[T] bigquery_expect(value : Result[T, @bigquery_read.ReadIssue]) -> T raise {
  match value {
    Ok(value) => value
    Err(@bigquery_read.Page(issue)) =>
      fail("BigQuery page: " + @debug.to_string(issue))
    Err(@bigquery_read.Host(@row_host.Source(issue))) =>
      fail("BigQuery Source: " + @debug.to_string(issue))
    Err(@bigquery_read.Host(@row_host.Physical(issue))) =>
      fail("BigQuery physical: " + @debug.to_string(issue))
    Err(@bigquery_read.Host(_)) => fail("BigQuery other Host refusal")
    Err(_) => fail("BigQuery unexpected read refusal")
  }
}

///|
test "BigQuery original accounted pages preserve decimal38 and SQL null through Common capture" {
  let rows = bigquery_rows()
  let first = bigquery_body([rows[0]], token=Some("next/opaque+token"))
  let second = bigquery_body([rows[1]])
  let (read, ledger) = bigquery_started_read(
    "bq-two-pages",
    (first.length() + second.length()).to_int64(),
  )
  assert_eq(
    bigquery_expect(@bigquery_read.accept_query_page(read, None, first)),
    1,
  )
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  assert_eq(
    @bigquery_read.accept_query_page(read, Some("next/opaque+token"), second).unwrap(),
    1,
  )
  assert_eq(@bigquery_read.result_read_usage(read), (2, 2L))
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    (first.length() + second.length()).to_int64(),
  )
  @bigquery_read.finish_result_read(read).unwrap()
  let capture = bigquery_capture_result(read).unwrap()
  let storage = @query.captured_source_storage(
    @row_host.row_capture_source(capture).unwrap(),
    10000,
    10000,
  ).unwrap()
  assert_true(
    @execution.producer_storage_cell(storage, 0, 0)
    is Some(@execution.Text("a1")),
  )
  assert_true(
    @execution.producer_storage_cell(storage, 0, 1)
    is Some(@execution.Captured(@admitted.Decimal(decimal))) &&
    decimal.coefficient == "99999999999999999999999999999999999999" &&
    decimal.scale == 0,
  )
  assert_true(
    @execution.producer_storage_cell(storage, 1, 2) is Some(@execution.Null),
  )
  bigquery_assert_retired(read, ledger)
  assert_false(@execution.producer_storage_available(storage))
}

///|
test "BigQuery charges malformed and foreign Job replies before refusal without producing a Source" {
  for
    index, body in [
      @utf8.encode("not json"),
      bigquery_body(bigquery_rows(), job="foreign-job"),
    ] {
    let (read, ledger) = bigquery_started_read(
      "bq-refused-" + index.to_string(),
      body.length().to_int64(),
    )
    assert_true(@bigquery_read.accept_query_page(read, None, body) is Err(_))
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      body.length().to_int64(),
    )
    assert_true(@bigquery_read.capture_result_read(read) is Err(_))
    assert_true(@bigquery_read.result_read_job(read) is Some(_))
    bigquery_assert_retired(read, ledger)
  }
}

///|
test "BigQuery refuses foreign page token and changed total on the same original acquisition" {
  let first = bigquery_body([bigquery_rows()[0]], token=Some("original-token"))
  for index in 0..<2 {
    let second = bigquery_body(
      [bigquery_rows()[1]],
      total=if index == 0 { "2" } else { "1" },
    )
    let (read, ledger) = bigquery_started_read(
      "bq-cursor-" + index.to_string(),
      (first.length() + second.length()).to_int64(),
    )
    assert_eq(@bigquery_read.accept_query_page(read, None, first).unwrap(), 1)
    assert_true(
      @bigquery_read.accept_query_page(
        read,
        Some(if index == 0 { "foreign-token" } else { "original-token" }),
        second,
      )
      is Err(_),
    )
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      (first.length() + second.length()).to_int64(),
    )
    assert_true(@bigquery_read.capture_result_read(read) is Err(_))
    bigquery_assert_retired(read, ledger)
  }
}

///|
test "BigQuery does not infer complete result from an absent token or exhaust its original page bound" {
  let first = bigquery_body([bigquery_rows()[0]], token=Some("next"))
  let second = bigquery_body([bigquery_rows()[1]])
  let (read, ledger) = bigquery_started_read(
    "bq-page-bound",
    (first.length() + second.length()).to_int64(),
    max_pages=1,
  )
  assert_eq(@bigquery_read.accept_query_page(read, None, first).unwrap(), 1)
  assert_true(
    @bigquery_read.accept_query_page(read, Some("next"), second)
    is Err(@bigquery_read.WrongPage),
  )
  bigquery_assert_retired(read, ledger)
  let incomplete = bigquery_body([bigquery_rows()[0]])
  let (short, short_ledger) = bigquery_started_read(
    "bq-incomplete",
    incomplete.length().to_int64(),
  )
  assert_eq(
    @bigquery_read.accept_query_page(short, None, incomplete).unwrap(),
    1,
  )
  assert_true(
    @bigquery_read.finish_result_read(short) is Err(@bigquery_read.Incomplete),
  )
  assert_true(@bigquery_read.capture_result_read(short) is Err(_))
  bigquery_assert_retired(short, short_ledger)
}

///|
test "BigQuery unknown physical stop retains same Job and reservation until original observer confirms" {
  let body = bigquery_body(bigquery_rows())
  let stopped = Ref(false)
  let (read, ledger) = bigquery_started_read(
    "bq-cleanup",
    body.length().to_int64(),
    stopped~,
  )
  assert_eq(@bigquery_read.accept_query_page(read, None, body).unwrap(), 2)
  @bigquery_read.finish_result_read(read).unwrap()
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @bigquery_read.close_result_read(read)
    is Err(@bigquery_read.TransportUnsettled),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@bigquery_read.result_read_job(read) is Some(_))
  stopped.val = true
  bigquery_assert_retired(read, ledger)
  @bigquery_read.close_result_read(read).unwrap()
}

///|
test "BigQuery transfer exhaustion cannot be replaced with a fresh charge or partial capture" {
  let body = bigquery_body(bigquery_rows())
  let (read, ledger) = bigquery_started_read(
    "bq-transfer",
    body.length().to_int64() - 1L,
  )
  assert_true(@bigquery_read.accept_query_page(read, None, body) is Err(_))
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  bigquery_assert_retired(read, ledger)
}

///|
test "BigQuery zero-row complete response still requires original envelope and confirmed cleanup" {
  let body = bigquery_body([], total="0")
  let (read, ledger) = bigquery_started_read(
    "bq-empty",
    body.length().to_int64(),
  )
  assert_eq(@bigquery_read.accept_query_page(read, None, body).unwrap(), 0)
  @bigquery_read.finish_result_read(read).unwrap()
  assert_true(bigquery_capture_result(read) is Ok(_))
  bigquery_assert_retired(read, ledger)
}

///|
test "BigQuery installed response borrow cannot replace Host finish capture or uncertain cleanup" {
  let prepared = bigquery_read_preparation().unwrap()
  let body = bigquery_body(bigquery_rows())
  let ledger = bigquery_read_ledger(prepared, body.length().to_int64())
  let stopped = Ref(false)
  let acquisition = @bigquery_read.prepared_read_acquisition(prepared)
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    "bq-host-borrow",
    _ => stopped.val,
    ledger,
    body.length().to_int64(),
    4096L,
  ).unwrap()
  @row_host.begin_row_run(run, 4096, 2, 2).unwrap()
  let foreign = bigquery_read_preparation().unwrap()
  assert_true(
    @bigquery_read.borrow_accounted_read(
      foreign,
      run,
      bigquery_job(),
      bigquery_read_limits(),
      4,
    )
    is Err(_),
  )
  let read = @bigquery_read.borrow_accounted_read(
    prepared,
    run,
    bigquery_job(),
    bigquery_read_limits(),
    4,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @bigquery_read.accept_query_page(read, None, body)
    is Err(@bigquery_read.Closed),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @bigquery_read.bind_borrowed_read_transport(read, () => stopped.val).unwrap()
  assert_true(
    @bigquery_read.bind_borrowed_read_transport(read, () => true) is Err(_),
  )
  assert_true(
    @bigquery_read.borrow_accounted_read(
      prepared,
      run,
      bigquery_job(),
      bigquery_read_limits(),
      4,
    )
    is Err(_),
  )
  assert_eq(@bigquery_read.accept_query_page(read, None, body).unwrap(), 2)
  assert_true(
    @bigquery_read.finish_result_read(read) is Err(@bigquery_read.BorrowedRun),
  )
  assert_true(
    @bigquery_read.capture_result_read(read) is Err(@bigquery_read.BorrowedRun),
  )
  assert_true(
    @bigquery_read.close_result_read(read) is Err(@bigquery_read.BorrowedRun),
  )
  @row_host.finish_row_run(run).unwrap()
  assert_true(@row_host.capture_row_run(run) is Err(_))
  let before_cleanup = @resources.ledger_usage(ledger)
  // No captured allocation was issued: uncertainty retains the original
  // reservation rather than fabricating a held-output allocation.
  assert_true(before_cleanup.reserved_retention_bytes > 0L)
  assert_true(before_cleanup.reserved_execution_bytes > 0L)
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), before_cleanup)
  assert_true(@bigquery_read.result_read_job(read) is Some(_))
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_true(@bigquery_read.result_read_job(read) is None)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  @bigquery_read.retire_borrowed_read(read).unwrap()
}

///|
test "BigQuery invalid logical bounds refuse before original reservation" {
  let prepared = bigquery_read_preparation().unwrap()
  let ledger = bigquery_read_ledger(prepared, 4096L)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @bigquery_read.start_accounted_read(
      prepared,
      bigquery_job(),
      "bq-invalid",
      _ => true,
      ledger,
      4096L,
      4096L,
      bigquery_read_limits(),
      0,
    )
    is Err(failure) &&
    @bigquery_read.read_start_failure_issue(failure)
    is @bigquery_read.InvalidLimits &&
    @bigquery_read.read_start_failure_cleanup(failure) is None,
  )
  assert_eq(@resources.ledger_usage(ledger), before)
}

///|
test "BigQuery metadata CheckedValues cannot substitute the original acquisition Contract" {
  let prepared = bigquery_read_preparation().unwrap()
  let projection = @bigquery_read.prepared_read_projection(prepared)
  let job = bigquery_job()
  let body = bigquery_body(bigquery_rows())
  let page = @bigquery_catalog.project_query_page(
    projection,
    job,
    body,
    bigquery_read_limits(),
  ).unwrap()
  let cell = @bigquery_catalog.query_page_cell(page, 0, 0).unwrap()
  let acquisition = @bigquery_read.prepared_read_acquisition(prepared)
  let original_contract = @row_host.row_acquisition_column_contract(
    acquisition, 0,
  ).unwrap()
  assert_false(physical_equal(cell.contract, original_contract))
  let ledger = bigquery_read_ledger(prepared, body.length().to_int64())
  guard @bigquery_read.start_accounted_read(
      prepared,
      job,
      "bq-original-contract",
      _ => true,
      ledger,
      body.length().to_int64(),
      4096L,
      bigquery_read_limits(),
      4,
    )
    is Ok(read) else {
    fail("original contract fixture start refused")
  }
  assert_eq(
    bigquery_expect(@bigquery_read.accept_query_page(read, None, body)),
    2,
  )
  assert_true(@bigquery_read.result_read_complete(read))
  @bigquery_read.finish_result_read(read).unwrap()
  assert_true(bigquery_capture_result(read) is Ok(_))
  bigquery_assert_retired(read, ledger)
}

///|
test "bigquery bounded capture retains the same child through stop and cleanup" {
  let body = bigquery_body(bigquery_rows())
  let stopped = Ref(false)
  let (read, ledger) = bigquery_started_read(
    "bigquery-bounded-capture-cleanup",
    body.length().to_int64(),
    stopped~,
  )
  assert_true(
    @bigquery_read.begin_result_capture(read) is Err(@bigquery_read.Closed),
  )
  assert_true(
    @bigquery_read.advance_result_capture(read, 1) is Err(@bigquery_read.Closed),
  )
  @bigquery_read.accept_query_page(read, None, body).unwrap() |> ignore
  @bigquery_read.finish_result_read(read).unwrap()
  // The original physical observer has not confirmed settlement yet.
  assert_true(@bigquery_read.begin_result_capture(read) is Err(_))
  stopped.val = true
  @bigquery_read.begin_result_capture(read).unwrap()
  assert_true(@bigquery_read.begin_result_capture(read) is Err(_))
  assert_true(@bigquery_read.advance_result_capture_cleanup(read, 1) is Err(_))
  assert_true(@bigquery_read.advance_result_capture(read, 1) is Ok((false, _)))
  let charged = @resources.ledger_usage(ledger).transferred_bytes
  @bigquery_read.interrupt_result_read(read)
  assert_true(
    @bigquery_read.advance_result_capture(read, 1) is Err(@bigquery_read.Closed),
  )
  assert_true(
    @bigquery_read.capture_result_read(read) is Err(@bigquery_read.Closed),
  )
  let mut closed = false
  for _ in 0..<1000 {
    match @bigquery_read.close_result_read(read) {
      Ok(_) => {
        closed = true
        break
      }
      Err(_) =>
        @bigquery_read.advance_result_capture_cleanup(read, 1).unwrap()
        |> ignore
    }
  }
  assert_true(closed)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, charged)
  bigquery_assert_retired(read, ledger)
  assert_true(
    @bigquery_read.begin_result_capture(read) is Err(@bigquery_read.Closed),
  )
}
