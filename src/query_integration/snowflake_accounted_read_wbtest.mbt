///|
// Drive only the provider's original acquisition child. A later checked
// Program projection remains outside this reader's capture boundary.
fn snowflake_capture_result(
  read : @snowflake_read.Read,
) -> Result[@row_host.RowSourceCapture, @snowflake_read.ReadIssue] raise {
  match @snowflake_read.begin_result_capture(read) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let mut previous = 0L
  for _ in 0..<1000 {
    let (done, work) = match @snowflake_read.advance_result_capture(read, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    assert_true(work >= previous)
    previous = work
    if done {
      return @snowflake_read.capture_result_read(read)
    }
  }
  fail(
    "Original snowflake capture did not finish within the fixture work bound",
  )
}

///|
fn snowflake_read_limits() -> @snowflake_response.ResponseLimits {
  {
    max_bytes: 4096,
    max_nodes: 1000,
    max_depth: 16,
    max_columns: 16,
    max_name_units: 256,
    max_handle_units: 128,
    max_partitions: 4,
    max_rows: 2,
    max_total_rows: 2L,
  }
}

///|
fn snowflake_description_limits() -> @snowflake_description.DescriptionLimits {
  {
    max_columns: 16,
    max_name_bytes: 4096,
    max_schema_bytes: 4096,
    max_nodes: 1000,
    max_depth: 16,
  }
}

///|
fn snowflake_read_description(
  precision? : Int = 38,
  temporal? : Bool = false,
) -> @snowflake_description.TableDescription {
  let headers = [
    "TABLE_CATALOG", "TABLE_SCHEMA", "TABLE_NAME", "COLUMN_NAME", "ORDINAL_POSITION",
    "IS_NULLABLE", "DATA_TYPE", "NUMERIC_PRECISION", "NUMERIC_SCALE", "CHARACTER_MAXIMUM_LENGTH",
  ]
  let metadata = []
  for index, name in headers {
    let numeric = [4, 7, 8, 9].contains(index)
    let fields : Map[String, Json] = Map([
      ("name", Json::string(name)),
      ("type", Json::string(if numeric { "FIXED" } else { "TEXT" })),
      ("nullable", Json::boolean(index >= 7)),
    ])
    if numeric {
      fields["precision"] = Json::number(38)
      fields["scale"] = Json::number(0)
    }
    metadata.push(Json::object(fields))
  }
  let data = [
    ["PRODUCT", "USAGE", "USAGE_30D", "ACCOUNT_ID", "1", "NO", "TEXT"],
    ["PRODUCT", "USAGE", "USAGE_30D", "ACTIVE_USERS", "2", "NO", "NUMBER"],
    ["PRODUCT", "USAGE", "USAGE_30D", "TREND", "3", "YES", "TEXT"],
  ]
  if temporal {
    data[1][6] = "DATE"
    data[2][6] = "TIMESTAMP_LTZ"
  }
  let rows = []
  for index, values in data {
    let row = values.map(Json::string)
    row.push(
      if index == 1 && !temporal {
        Json::string(precision.to_string())
      } else {
        Json::null()
      },
    )
    row.push(
      if index == 1 && !temporal {
        Json::string("0")
      } else {
        Json::null()
      },
    )
    row.push(if index == 1 { Json::null() } else { Json::string("256") })
    rows.push(Json::array(row))
  }
  let body = Json::object(
    Map([
      ("statementHandle", Json::string("metadata-original")),
      ("sqlState", Json::string("00000")),
      (
        "resultSetMetaData",
        Json::object(
          Map([
            ("format", Json::string("jsonv2")),
            ("numRows", Json::number(3)),
            ("rowType", Json::array(metadata)),
            (
              "partitionInfo",
              Json::array([Json::object(Map([("rowCount", Json::number(3))]))]),
            ),
          ]),
        ),
      ),
      ("data", Json::array(rows)),
    ]),
  )
  let original = @snowflake_response.project_result_set(
    @utf8.encode(body.stringify()),
    { ..snowflake_read_limits(), max_rows: 3, max_total_rows: 3L, },
  ).unwrap()
  @snowflake_description.project_table_description(
    @snowflake_description.table_target("PRODUCT", "USAGE", "USAGE_30D", 4096).unwrap(),
    original,
    [],
    snowflake_description_limits(),
  ).unwrap()
}

///|
fn snowflake_read_preparation(
  fresh_precision? : Int = 38,
  query_text? : String = "SELECT ACCOUNT_ID, ACTIVE_USERS, TREND FROM snowflake.usage_30d",
  temporal? : Bool = false,
  selected_fields? : Array[String] = ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"],
) -> Result[@snowflake_read.PreparedRead, @snowflake_read.ReadIssue] raise {
  let declared = @snowflake_description.prepare_read_projection(
    snowflake_read_description(temporal~),
    selected_fields,
    snowflake_description_limits(),
  ).unwrap()
  let declaration = @snowflake_description.generate_read_declaration(
    declared,
    "usage_30d",
    "snowflake",
    "snowflake/0.1",
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
      "{\"connector\":\"snowflake\",\"resource\":\"usage_30d\"}",
      limits.source.source,
    ).unwrap(),
    limits.source.tree,
  ).unwrap()
  let program = @snowflake_query_program.compile(
    query,
    {
      program_id: "fixture.snowflake_read",
      stage_id: "main",
      stage_result: "rows",
      result_name: "answer",
      captured_stage: Some("capture"),
      parameter_declarations: None,
      inputs: [
        {
          relation: [
            { value: "snowflake", quoted: false, },
            { value: "usage_30d", quoted: false, },
          ],
          name: "remote",
          source: Captured(source),
          visible_fields: selected_fields,
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
  @snowflake_read.prepare_declared_read(
    snowflake_read_description(precision=fresh_precision, temporal~),
    declaration,
    requirement,
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
    snowflake_description_limits(),
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
fn snowflake_result_body(
  first : Array[Json],
  total? : Int = 2,
  parts? : Array[Int] = [2],
  precision? : Int = 38,
  trend_nullable? : Bool = true,
  first_name? : String = "ACCOUNT_ID",
) -> Bytes {
  let columns = [
    Json::object(
      Map([
        ("name", Json::string(first_name)),
        ("type", Json::string("TEXT")),
        ("nullable", Json::boolean(false)),
      ]),
    ),
    Json::object(
      Map([
        ("name", Json::string("ACTIVE_USERS")),
        ("type", Json::string("FIXED")),
        ("precision", precision.to_json()),
        ("scale", Json::number(0)),
        ("nullable", Json::boolean(false)),
      ]),
    ),
    Json::object(
      Map([
        ("name", Json::string("TREND")),
        ("type", Json::string("TEXT")),
        ("nullable", Json::boolean(trend_nullable)),
      ]),
    ),
  ]
  @utf8.encode(
    Json::object(
      Map([
        ("statementHandle", Json::string("query-original")),
        ("sqlState", Json::string("00000")),
        (
          "resultSetMetaData",
          Json::object(
            Map([
              ("format", Json::string("jsonv2")),
              ("numRows", total.to_json()),
              ("rowType", Json::array(columns)),
              (
                "partitionInfo",
                Json::array(
                  parts.map(n => Json::object(Map([("rowCount", n.to_json())]))),
                ),
              ),
            ]),
          ),
        ),
        ("data", Json::array(first)),
      ]),
    ).stringify(),
  )
}

///|
fn snowflake_row(account : String, users : String, trend : Json) -> Json {
  Json::array([Json::string(account), Json::string(users), trend])
}

///|
fn snowflake_two_rows() -> Array[Json] {
  [
    snowflake_row(
      "a1",
      "99999999999999999999999999999999999999",
      Json::string("down"),
    ),
    snowflake_row("a2", "0", Json::null()),
  ]
}

///|
fn snowflake_read_ledger(
  prepared : @snowflake_read.PreparedRead,
  transfer : Int64,
  scratch? : Int64 = 4096L,
) -> @resources.Ledger {
  let acquisition = @snowflake_read.prepared_read_acquisition(prepared)
  @resources.create_ledger({
    planning_work: 100,
    attempts: 2,
    holdings: 2,
    transfer_bytes: transfer,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition),
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    scratch,
  }).unwrap()
}

///|
fn snowflake_started_read(
  nonce : String,
  transfer : Int64,
  stopped? : Ref[Bool] = Ref(true),
  checks? : Ref[Int] = Ref(0),
) -> (@snowflake_read.Read, @resources.Ledger) raise {
  let prepared = match snowflake_read_preparation() {
    Ok(value) => value
    Err(@snowflake_read.ForeignDeclaration) =>
      fail("Snowflake preparation: foreign declaration")
    Err(@snowflake_read.Host(@row_host.Source(issue))) =>
      fail("Snowflake preparation: Source " + @debug.to_string(issue))
    Err(@snowflake_read.Host(@row_host.InvalidContracts)) =>
      fail("Snowflake preparation: invalid contracts")
    Err(@snowflake_read.Host(@row_host.Candidate)) =>
      fail("Snowflake preparation: candidate")
    Err(@snowflake_read.Host(@row_host.Selection)) =>
      fail("Snowflake preparation: selection")
    Err(@snowflake_read.Description(issue)) =>
      fail("Snowflake preparation: description " + @debug.to_string(issue))
    Err(_) => fail("Snowflake preparation: unexpected issue")
  }
  let ledger = snowflake_read_ledger(prepared, transfer)
  let result = @snowflake_read.start_accounted_read(
    prepared,
    nonce,
    _ => {
      checks.val += 1
      stopped.val
    },
    ledger,
    transfer,
    4096L,
    snowflake_read_limits(),
    10,
  )
  guard result is Ok(read) else {
    abort("unexpected Snowflake fixture start failure")
  }
  (read, ledger)
}

///|
fn snowflake_assert_retired(
  read : @snowflake_read.Read,
  ledger : @resources.Ledger,
) -> Unit raise {
  @snowflake_read.close_result_read(read).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_true(@snowflake_read.result_read_original(read) is None)
}

///|
fn[T] snowflake_expect(value : Result[T, @snowflake_read.ReadIssue]) -> T raise {
  match value {
    Ok(value) => value
    Err(@snowflake_read.SchemaMismatch(name)) =>
      fail("Snowflake result schema: " + name)
    Err(@snowflake_read.Response(issue)) =>
      fail("Snowflake response: " + @debug.to_string(issue))
    Err(@snowflake_read.Host(@row_host.Source(issue))) =>
      fail("Snowflake row Source: " + @debug.to_string(issue))
    Err(@snowflake_read.Host(@row_host.Physical(issue))) =>
      fail("Snowflake physical: " + @debug.to_string(issue))
    Err(_) => fail("Snowflake read: unexpected issue")
  }
}

///|
test "Snowflake actual declared Source charges original envelope and captures exact decimal38 rows" {
  let body = snowflake_result_body(snowflake_two_rows())
  let (read, ledger) = snowflake_started_read(
    "snowflake-one-page",
    body.length().to_int64(),
  )
  assert_eq(
    snowflake_expect(@snowflake_read.accept_first_result(read, body)),
    2,
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  assert_eq(@snowflake_read.result_read_usage(read), (1, 2L))
  let original = @snowflake_read.result_read_original(read).unwrap()
  assert_eq(
    @snowflake_response.result_set_response_sha256(original),
    @sha.hex(body),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  @snowflake_read.finish_result_read(read).unwrap()
  let capture = snowflake_capture_result(read).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  let input = @query.captured_source_storage(source, 10000, 10000).unwrap()
  assert_true(
    @execution.producer_storage_cell(input, 0, 0) is Some(@execution.Text("a1")),
  )
  assert_true(
    @execution.producer_storage_cell(input, 0, 1)
    is Some(@execution.Captured(@admitted.Decimal(decimal))) &&
    decimal.coefficient == "99999999999999999999999999999999999999" &&
    decimal.scale == 0,
  )
  assert_true(
    @execution.producer_storage_cell(input, 1, 2) is Some(@execution.Null),
  )
  assert_true(@resources.ledger_usage(ledger).held_bytes > 0L)
  snowflake_assert_retired(read, ledger)
  assert_false(@execution.producer_storage_available(input))
}

///|
test "Snowflake partition admission remains one charged original and complete before finish" {
  let first = snowflake_result_body([snowflake_two_rows()[0]], parts=[1, 1])
  let next = @utf8.encode(
    Json::object(Map([("data", Json::array([snowflake_two_rows()[1]]))])).stringify(),
  )
  let (read, ledger) = snowflake_started_read(
    "snowflake-two-pages",
    (first.length() + next.length()).to_int64(),
  )
  assert_eq(@snowflake_read.accept_first_result(read, first).unwrap(), 1)
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  assert_eq(@snowflake_read.accept_result_partition(read, 1, next).unwrap(), 1)
  assert_eq(@snowflake_read.result_read_usage(read), (2, 2L))
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    (first.length() + next.length()).to_int64(),
  )
  @snowflake_read.finish_result_read(read).unwrap()
  assert_true(snowflake_capture_result(read) is Ok(_))
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake fresh metadata cannot replace the checked Source schema" {
  assert_true(
    snowflake_read_preparation(fresh_precision=37)
    is Err(@snowflake_read.ForeignDeclaration),
  )
}

///|
test "Snowflake result schema must match names precision and nullable contracts" {
  for
    index, body in [
      snowflake_result_body(snowflake_two_rows(), first_name="FOREIGN"),
      snowflake_result_body(
        [
          snowflake_row("a1", "1", Json::string("down")),
          snowflake_row("a2", "0", Json::null()),
        ],
        precision=37,
      ),
      snowflake_result_body(
        [snowflake_row("a1", "1", Json::string("down"))],
        total=1,
        parts=[1],
        trend_nullable=false,
      ),
    ] {
    let (read, ledger) = snowflake_started_read(
      "snowflake-schema-" + index.to_string(),
      body.length().to_int64(),
    )
    assert_true(
      @snowflake_read.accept_first_result(read, body)
      is Err(@snowflake_read.SchemaMismatch(field)) &&
      field == ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"][index],
    )
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      body.length().to_int64(),
    )
    assert_true(@snowflake_read.finish_result_read(read) is Err(_))
    assert_true(@snowflake_read.capture_result_read(read) is Err(_))
    snowflake_assert_retired(read, ledger)
  }
}

///|
test "Snowflake malformed physical body is charged before decoder refusal" {
  let body = @utf8.encode("{\"broken\":")
  let (read, ledger) = snowflake_started_read(
    "snowflake-malformed",
    body.length().to_int64(),
  )
  assert_true(
    @snowflake_read.accept_first_result(read, body)
    is Err(@snowflake_read.Response(_)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake incomplete duplicate and foreign partition metadata cannot capture" {
  let first = snowflake_result_body([snowflake_two_rows()[0]], parts=[1, 1])
  let next = @utf8.encode("{\"data\":[[\"a2\",\"0\",null]]}")
  for variant in 0..<3 {
    let (read, ledger) = snowflake_started_read(
      "snowflake-partition-" + variant.to_string(),
      4096L,
    )
    assert_eq(@snowflake_read.accept_first_result(read, first).unwrap(), 1)
    if variant == 0 {
      assert_true(
        @snowflake_read.finish_result_read(read)
        is Err(@snowflake_read.Incomplete),
      )
    } else if variant == 1 {
      assert_eq(
        @snowflake_read.accept_result_partition(read, 1, next).unwrap(),
        1,
      )
      assert_true(
        @snowflake_read.accept_result_partition(read, 1, next)
        is Err(@snowflake_read.WrongPartition),
      )
    } else {
      assert_true(
        @snowflake_read.accept_result_partition(read, 1, first)
        is Err(@snowflake_read.Response(_)),
      )
    }
    assert_true(@snowflake_read.capture_result_read(read) is Err(_))
    snowflake_assert_retired(read, ledger)
  }
}

///|
test "Snowflake transfer shortage refuses without another attempt or partial capture" {
  let body = snowflake_result_body(snowflake_two_rows())
  let (read, ledger) = snowflake_started_read(
    "snowflake-transfer-short",
    body.length().to_int64() - 1L,
  )
  assert_true(
    @snowflake_read.accept_first_result(read, body)
    is Err(@snowflake_read.Host(_)),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake finish is not physical stop and failed close retains the same reservation" {
  let body = snowflake_result_body(snowflake_two_rows())
  let stopped = Ref(false)
  let checks = Ref(0)
  let (read, ledger) = snowflake_started_read(
    "snowflake-stop-pending",
    body.length().to_int64(),
    stopped~,
    checks~,
  )
  assert_eq(@snowflake_read.accept_first_result(read, body).unwrap(), 2)
  @snowflake_read.finish_result_read(read).unwrap()
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @snowflake_read.close_result_read(read)
    is Err(@snowflake_read.TransportUnsettled),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(
    @snowflake_read.result_read_statement_handle(read),
    Some("query-original"),
  )
  assert_true(
    @snowflake_read.accept_first_result(read, body)
    is Err(@snowflake_read.Closed),
  )
  stopped.val = true
  snowflake_assert_retired(read, ledger)
  let after = checks.val
  @snowflake_read.close_result_read(read).unwrap()
  assert_eq(
    checks.val,
    after,
    msg="already confirmed transport is not re-observed after retirement",
  )
}

///|
test "Snowflake begin failure returns original cleanup carrier without a second reservation" {
  let prepared = snowflake_read_preparation().unwrap()
  let ledger = snowflake_read_ledger(prepared, 4096L, scratch=4095L)
  let stopped = Ref(false)
  let started = @snowflake_read.start_accounted_read(
    prepared,
    "snowflake-partial-begin",
    _ => stopped.val,
    ledger,
    4096L,
    4095L,
    snowflake_read_limits(),
    10,
  )
  guard started is Err(failure) else { abort("expected bounded begin refusal") }
  assert_true(
    @snowflake_read.read_start_failure_issue(failure) is @snowflake_read.Host(_),
  )
  let cleanup = @snowflake_read.read_start_failure_cleanup(failure).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(before.reserved_execution_bytes > 0L)
  assert_true(
    @snowflake_read.close_result_read(cleanup)
    is Err(@snowflake_read.TransportUnsettled),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  stopped.val = true
  snowflake_assert_retired(cleanup, ledger)
}

///|
test "Snowflake interrupted read never consumes late response or reopens its original attempt" {
  let body = snowflake_result_body(snowflake_two_rows())
  let (read, ledger) = snowflake_started_read(
    "snowflake-interrupted",
    body.length().to_int64(),
  )
  @snowflake_read.interrupt_result_read(read)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @snowflake_read.accept_first_result(read, body)
    is Err(@snowflake_read.Closed),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake overflow is a charged value refusal rather than a schema coercion" {
  let body = snowflake_result_body(
    [
      snowflake_row(
        "a1",
        "100000000000000000000000000000000000000",
        Json::string("down"),
      ),
    ],
    total=1,
    parts=[1],
  )
  let (read, ledger) = snowflake_started_read(
    "snowflake-decimal-overflow",
    body.length().to_int64(),
  )
  assert_true(
    @snowflake_read.accept_first_result(read, body)
    is Err(
      @snowflake_read.Response(
        @snowflake_response.ValueOutOfRange("ACTIVE_USERS")
      )
    ),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  assert_true(@snowflake_read.capture_result_read(read) is Err(_))
  snowflake_assert_retired(read, ledger)
}

///|
test "Snowflake AQL uses the same original Common compiler acquisition and cleanup" {
  let prepared = snowflake_read_preparation(
    query_text="FROM snowflake.usage_30d |> SELECT ACCOUNT_ID, ACTIVE_USERS, TREND",
  ).unwrap()
  let body = snowflake_result_body(snowflake_two_rows())
  let ledger = snowflake_read_ledger(prepared, body.length().to_int64())
  let started = @snowflake_read.start_accounted_read(
    prepared,
    "snowflake-aql-original",
    _ => true,
    ledger,
    body.length().to_int64(),
    4096L,
    snowflake_read_limits(),
    10,
  )
  guard started is Ok(read) else { abort("expected original AQL read") }
  assert_eq(
    snowflake_expect(@snowflake_read.accept_first_result(read, body)),
    2,
  )
  snowflake_expect(@snowflake_read.finish_result_read(read))
  let capture = snowflake_expect(snowflake_capture_result(read))
  let source = @row_host.row_capture_source(capture).unwrap()
  let input = @query.captured_source_storage(source, 10000, 10000).unwrap()
  assert_true(
    @execution.producer_storage_cell(input, 1, 2) is Some(@execution.Null),
  )
  snowflake_assert_retired(read, ledger)
  assert_false(@execution.producer_storage_available(input))
}

///|
test "Snowflake invalid pre-start bounds do not reserve an attempt or create cleanup custody" {
  let prepared = snowflake_read_preparation().unwrap()
  let ledger = snowflake_read_ledger(prepared, 4096L)
  let before = @resources.ledger_usage(ledger)
  let started = @snowflake_read.start_accounted_read(
    prepared,
    "snowflake-invalid-bound",
    _ => false,
    ledger,
    4096L,
    4096L,
    { ..snowflake_read_limits(), max_total_rows: 2147483648L, },
    10,
  )
  guard started is Err(failure) else { abort("expected pre-start refusal") }
  assert_true(
    @snowflake_read.read_start_failure_issue(failure)
    is @snowflake_read.InvalidLimits,
  )
  assert_true(@snowflake_read.read_start_failure_cleanup(failure) is None)
  assert_eq(@resources.ledger_usage(ledger), before)
}

///|
test "snowflake bounded capture retains the same child through stop and cleanup" {
  let body = snowflake_result_body(snowflake_two_rows())
  let stopped = Ref(false)
  let (read, ledger) = snowflake_started_read(
    "snowflake-bounded-capture-cleanup",
    body.length().to_int64(),
    stopped~,
  )
  assert_true(
    @snowflake_read.begin_result_capture(read) is Err(@snowflake_read.Closed),
  )
  assert_true(
    @snowflake_read.advance_result_capture(read, 1)
    is Err(@snowflake_read.Closed),
  )
  @snowflake_read.accept_first_result(read, body).unwrap() |> ignore
  @snowflake_read.finish_result_read(read).unwrap()
  // The original physical observer has not confirmed settlement yet.
  assert_true(@snowflake_read.begin_result_capture(read) is Err(_))
  stopped.val = true
  @snowflake_read.begin_result_capture(read).unwrap()
  assert_true(@snowflake_read.begin_result_capture(read) is Err(_))
  assert_true(@snowflake_read.advance_result_capture_cleanup(read, 1) is Err(_))
  assert_true(@snowflake_read.advance_result_capture(read, 1) is Ok((false, _)))
  let charged = @resources.ledger_usage(ledger).transferred_bytes
  @snowflake_read.interrupt_result_read(read)
  assert_true(
    @snowflake_read.advance_result_capture(read, 1)
    is Err(@snowflake_read.Closed),
  )
  assert_true(
    @snowflake_read.capture_result_read(read) is Err(@snowflake_read.Closed),
  )
  let mut closed = false
  for _ in 0..<1000 {
    match @snowflake_read.close_result_read(read) {
      Ok(_) => {
        closed = true
        break
      }
      Err(_) =>
        @snowflake_read.advance_result_capture_cleanup(read, 1).unwrap()
        |> ignore
    }
  }
  assert_true(closed)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, charged)
  snowflake_assert_retired(read, ledger)
  assert_true(
    @snowflake_read.begin_result_capture(read) is Err(@snowflake_read.Closed),
  )
}
