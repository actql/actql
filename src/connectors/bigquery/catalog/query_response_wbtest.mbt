///|
fn qlimits() -> QueryLimits {
  {
    description: limits(),
    max_rows: 16,
    max_total_rows: 100L,
    max_value_nodes: 128,
    max_value_text_bytes: 4096,
    max_job_bytes: 1024,
    max_page_token_bytes: 128,
  }
}

///|
fn qjob() -> QueryJob {
  query_job("acme-project", "original_job-1", "EU", 1024).unwrap()
}

///|
fn qprojection(fields : Array[Json]) -> ReadProjection {
  let original = project_table_description(target(), body(fields), limits()).unwrap()
  let names = original.columns.map(column => column.name)
  prepare_read_projection(original, names, limits()).unwrap()
}

///|
fn qrow(values : Array[Json]) -> Json {
  Json::object(
    Map([("f", values.map(v => Json::object(Map([("v", v)]))).to_json())]),
  )
}

///|
fn qbody(
  fields : Array[Json],
  rows : Array[Json],
  total? : String = "1",
  token? : String? = None,
  project? : String = "acme-project",
  job? : String = "original_job-1",
  location? : String? = Some("EU"),
  complete? : Bool = true,
  errors? : Array[Json]? = None,
) -> Bytes {
  let reference = Map([
    ("projectId", project.to_json()),
    ("jobId", job.to_json()),
  ])
  if location is Some(location) {
    reference["location"] = location.to_json()
  }
  let values = Map([
    ("kind", "bigquery#getQueryResultsResponse".to_json()),
    ("jobReference", Json::object(reference)),
    ("jobComplete", complete.to_json()),
    ("schema", Json::object(Map([("fields", fields.to_json())]))),
    ("totalRows", total.to_json()),
    ("rows", rows.to_json()),
  ])
  if token is Some(token) {
    values["pageToken"] = token.to_json()
  }
  if errors is Some(errors) {
    values["errors"] = errors.to_json()
  }
  @utf8.encode(Json::object(values).stringify())
}

///|
test "query page binds original projection and exact Job without treating a page as full result" {
  let fields = [field("id", "STRING")]
  let projection = qprojection(fields)
  let job = qjob()
  let page = project_query_page(
    projection,
    job,
    qbody(
      fields,
      [qrow(["001A".to_json()])],
      total="3",
      token=Some("next/opaque+token"),
    ),
    qlimits(),
  ).unwrap()
  assert_true(query_page_matches_original(page, projection, job))
  assert_false(query_page_matches_original(page, qprojection(fields), job))
  assert_false(query_page_matches_original(page, projection, qjob()))
  assert_eq(query_page_row_count(page), 1)
  assert_eq(query_page_total_rows(page), 3L)
  assert_eq(query_page_next_token(page), Some("next/opaque+token"))
  assert_true(
    query_page_cell(page, 0, 0).unwrap().value is @admitted.Text("001A"),
  )
  assert_true(query_page_cell(page, -1, 0) is None)
  assert_true(query_page_cell(page, 1, 0) is None)
  assert_eq(query_page_response_sha256(page).length(), 64)
}

///|
test "query decimal38 preserves exact coefficient and original parameterization when result schema omits it" {
  let source = [
    field(
      "n",
      "NUMERIC",
      precision=Some("38".to_json()),
      scale=Some("9".to_json()),
    ),
  ]
  let projection = qprojection(source)
  let response = [field("n", "NUMERIC")]
  let page = project_query_page(
    projection,
    qjob(),
    qbody(response, [
      qrow(["99999999999999999999999999999.123456789".to_json()]),
    ]),
    qlimits(),
  ).unwrap()
  let value = query_page_cell(page, 0, 0).unwrap()
  assert_true(
    value.value is @admitted.Decimal(decimal) &&
    decimal.coefficient == "99999999999999999999999999999123456789" &&
    decimal.precision == 38 &&
    decimal.scale == 9,
  )
  assert_true(
    physical_equal(
      value.contract,
      projection.original.columns[0].contract.unwrap(),
    ),
  )
  assert_true(
    project_query_page(
      projection,
      qjob(),
      qbody(response, [qrow(["100000000000000000000000000000".to_json()])]),
      qlimits(),
    )
    is Err(InvalidQueryCell("n")),
  )
  assert_true(
    project_query_page(
      projection,
      qjob(),
      qbody(response, [qrow(["0.0000000001".to_json()])]),
      qlimits(),
    )
    is Err(InvalidQueryCell("n")),
  )
}

///|
test "query decimal P equals S uses the actual admitted contract" {
  let fields = [
    field(
      "n",
      "NUMERIC",
      precision=Some("2".to_json()),
      scale=Some("2".to_json()),
    ),
  ]
  let page = project_query_page(
    qprojection(fields),
    qjob(),
    qbody([field("n", "DECIMAL")], [qrow(["1e-2".to_json()])]),
    qlimits(),
  ).unwrap()
  assert_true(
    query_page_cell(page, 0, 0).unwrap().value is @admitted.Decimal(value) &&
    value.coefficient == "1" &&
    value.precision == 2 &&
    value.scale == 2,
  )
}

///|
test "query SQL NULL JSON null and the string null are distinct" {
  let fields = [
    field("sql", "STRING"),
    field("json", "JSON"),
    field("text", "STRING"),
  ]
  let page = project_query_page(
    qprojection(fields),
    qjob(),
    qbody(fields, [qrow([Json::null(), "null".to_json(), "null".to_json()])]),
    qlimits(),
  ).unwrap()
  assert_true(query_page_cell(page, 0, 0).unwrap().value is @admitted.Null)
  assert_true(
    query_page_cell(page, 0, 1).unwrap().value
    is @admitted.JsonData(@admitted.Null),
  )
  assert_true(
    query_page_cell(page, 0, 2).unwrap().value is @admitted.Text("null"),
  )
}

///|
test "query strings preserve Unicode combining spelling CR LF and supplementary scalars" {
  let fields = [field("name", "STRING")]
  let text = "😀é\r\n\u2028"
  let page = project_query_page(
    qprojection(fields),
    qjob(),
    qbody(fields, [qrow([text.to_json()])]),
    qlimits(),
  ).unwrap()
  assert_true(
    query_page_cell(page, 0, 0).unwrap().value is @admitted.Text(value) &&
    value == text,
  )
}

///|
test "query Boolean and finite FLOAT use typed conversion not truthiness or numeric JSON cells" {
  let fields = [field("b", "BOOL"), field("f", "FLOAT64")]
  let projection = qprojection(fields)
  let page = project_query_page(
    projection,
    qjob(),
    qbody([field("b", "BOOLEAN"), field("f", "FLOAT")], [
      qrow(["false".to_json(), "1.25e2".to_json()]),
    ]),
    qlimits(),
  ).unwrap()
  assert_true(
    query_page_cell(page, 0, 0).unwrap().value is @admitted.Boolean(false),
  )
  assert_true(
    query_page_cell(page, 0, 1).unwrap().value is @admitted.Number(125.0),
  )
  for value in [true.to_json(), "1".to_json(), "False".to_json()] {
    assert_true(
      project_query_page(
        projection,
        qjob(),
        qbody(fields, [qrow([value, "1".to_json()])]),
        qlimits(),
      )
      is Err(_),
    )
  }
  for
    value in [
      1.0.to_json(),
      "NaN".to_json(),
      "Infinity".to_json(),
      "-0".to_json(),
      "1e999".to_json(),
      "true".to_json(),
    ] {
    assert_true(
      project_query_page(
        projection,
        qjob(),
        qbody(fields, [qrow(["true".to_json(), value])]),
        qlimits(),
      )
      is Err(_),
    )
  }
}

///|
test "query DATE uses Common calendar validation" {
  let fields = [field("d", "DATE")]
  let page = project_query_page(
    qprojection(fields),
    qjob(),
    qbody(fields, [qrow(["2024-02-29".to_json()])]),
    qlimits(),
  ).unwrap()
  assert_true(
    query_page_cell(page, 0, 0).unwrap().value is @admitted.Date("2024-02-29"),
  )
  assert_true(
    project_query_page(
      qprojection(fields),
      qjob(),
      qbody(fields, [qrow(["2025-02-29".to_json()])]),
      qlimits(),
    )
    is Err(_),
  )
}

///|
test "query nested STRUCT follows returned field order but preserves original closed object contracts" {
  let a = field("a", "STRING", mode=Some("REQUIRED"))
  let b = field(
    "b",
    "NUMERIC",
    precision=Some("5".to_json()),
    scale=Some("2".to_json()),
  )
  let fields = [field("record", "RECORD", children=Some([a, b]))]
  let response = [
    field("record", "STRUCT", children=Some([field("b", "NUMERIC"), a])),
  ]
  let nested = qrow(["1.25".to_json(), "original".to_json()])
  let page = project_query_page(
    qprojection(fields),
    qjob(),
    qbody(response, [qrow([nested])]),
    qlimits(),
  ).unwrap()
  guard query_page_cell(page, 0, 0).unwrap().value is @admitted.Object(value) else {
    fail("expected object")
  }
  assert_eq(@admitted.element_at(value, 0).unwrap().0, "a")
  assert_eq(@admitted.element_at(value, 1).unwrap().0, "b")
  assert_true(
    project_query_page(
      qprojection(fields),
      qjob(),
      qbody(response, [qrow([qrow(["1.25".to_json(), Json::null()])])]),
      qlimits(),
    )
    is Err(_),
  )
}

///|
test "query REPEATED cells retain typed elements empty arrays and prohibit SQL NULL elements" {
  let fields = [
    field(
      "values",
      "NUMERIC",
      mode=Some("REPEATED"),
      precision=Some("5".to_json()),
      scale=Some("2".to_json()),
    ),
  ]
  let repeated = Json::array([
    Json::object(Map([("v", "1.25".to_json())])),
    Json::object(Map([("v", "2".to_json())])),
  ])
  let page = project_query_page(
    qprojection(fields),
    qjob(),
    qbody(fields, [qrow([repeated]), qrow([Json::array([])])], total="2"),
    qlimits(),
  ).unwrap()
  guard query_page_cell(page, 0, 0).unwrap().value is @admitted.Array(values) else {
    fail("expected array")
  }
  assert_eq(@admitted.element_count(values), 2)
  for
    invalid in [
      Json::null(),
      Json::array([Json::object(Map([("v", Json::null())]))]),
      Json::array(["1.25".to_json()]),
    ] {
    assert_true(
      project_query_page(
        qprojection(fields),
        qjob(),
        qbody(fields, [qrow([invalid])]),
        qlimits(),
      )
      is Err(_),
    )
  }
}

///|
test "query repeated records preserve nested arrays and JSON values" {
  let child = field("items", "STRING", mode=Some("REPEATED"))
  let fields = [
    field(
      "records",
      "RECORD",
      mode=Some("REPEATED"),
      children=Some([child, field("j", "JSON")]),
    ),
  ]
  let record = qrow([
    Json::array([Json::object(Map([("v", "x".to_json())]))]),
    "[null,1]".to_json(),
  ])
  let rows = [qrow([Json::array([Json::object(Map([("v", record)]))])])]
  let page = project_query_page(
    qprojection(fields),
    qjob(),
    qbody(fields, rows),
    qlimits(),
  ).unwrap()
  assert_true(query_page_cell(page, 0, 0).unwrap().value is @admitted.Array(_))
}

///|
test "query absent v malformed row width and numeric decimal cell never become NULL" {
  let fields = [field("n", "NUMERIC")]
  let projection = qprojection(fields)
  for
    row in [
      Json::object(Map([("f", Json::array([Json::object(Map([]))]))])),
      qrow([]),
      qrow(["1".to_json(), "2".to_json()]),
      qrow([1.0.to_json()]),
    ] {
    assert_true(
      project_query_page(projection, qjob(), qbody(fields, [row]), qlimits())
      is Err(_),
    )
  }
}

///|
test "query foreign Job project identifier and region are refused" {
  let fields = [field("id", "STRING")]
  let projection = qprojection(fields)
  for
    bytes in [
      qbody(fields, [], total="0", project="foreign"),
      qbody(fields, [], total="0", job="another"),
      qbody(fields, [], total="0", location=Some("US")),
      qbody(fields, [], total="0", location=None),
    ] {
    assert_true(
      project_query_page(projection, qjob(), bytes, qlimits())
      is Err(ForeignQueryJob),
    )
  }
  assert_true(
    query_job("acme-project", "../foreign", "EU", 1024) is Err(InvalidQueryJob),
  )
  let us = query_job("acme-project", "original_job-1", "US", 1024).unwrap()
  assert_true(
    project_query_page(
      projection,
      us,
      qbody(fields, [], total="0", location=None),
      qlimits(),
    )
    is Ok(_),
  )
}

///|
test "query pending is not completion or failure and diagnostics do not settle a Job" {
  let projection = qprojection([field("id", "STRING")])
  let pending = @utf8.encode(
    "{\"jobReference\":{\"projectId\":\"acme-project\",\"jobId\":\"original_job-1\",\"location\":\"EU\"},\"jobComplete\":false}",
  )
  assert_true(
    project_query_page(projection, qjob(), pending, qlimits())
    is Err(QueryPending),
  )
  assert_true(
    project_query_page(
      projection,
      qjob(),
      qbody([field("id", "STRING")], [], total="0", complete=false),
      qlimits(),
    )
    is Err(InvalidQueryResponse),
  )
  let diagnostics = [Json::object(Map([("reason", "warning".to_json())]))]
  assert_true(
    project_query_page(
      projection,
      qjob(),
      qbody([field("id", "STRING")], [], total="0", errors=Some(diagnostics)),
      qlimits(),
    )
    is Err(QueryDiagnostics),
  )
}

///|
test "query schema cannot replace names type repeated mode precision or nested fields" {
  let original = [
    field(
      "n",
      "NUMERIC",
      precision=Some("5".to_json()),
      scale=Some("2".to_json()),
    ),
  ]
  for
    fields in [
      [field("other", "NUMERIC")],
      [field("n", "STRING")],
      [field("n", "NUMERIC", mode=Some("REPEATED"))],
      [
        field(
          "n",
          "NUMERIC",
          precision=Some("6".to_json()),
          scale=Some("2".to_json()),
        ),
      ],
    ] {
    assert_true(
      project_query_page(
        qprojection(original),
        qjob(),
        qbody(fields, [qrow(["1.00".to_json()])]),
        qlimits(),
      )
      is Err(QuerySchemaMismatch(_)),
    )
  }
  let record = [
    field(
      "r",
      "RECORD",
      children=Some([field("a", "STRING"), field("b", "STRING")]),
    ),
  ]
  let duplicate = [
    field(
      "r",
      "RECORD",
      children=Some([field("a", "STRING"), field("a", "STRING")]),
    ),
  ]
  assert_true(
    project_query_page(
      qprojection(record),
      qjob(),
      qbody(duplicate, [], total="0"),
      qlimits(),
    )
    is Err(QuerySchemaMismatch(_)),
  )
}

///|
test "query aggregate value node text row total and token limits fail without partial page" {
  let fields = [field("s", "STRING")]
  let projection = qprojection(fields)
  let bytes = qbody(
    fields,
    [qrow(["abc".to_json()]), qrow(["def".to_json()])],
    total="2",
  )
  assert_true(
    project_query_page(projection, qjob(), bytes, { ..qlimits(), max_rows: 1, })
    is Err(QueryLimit),
  )
  assert_true(
    project_query_page(projection, qjob(), bytes, {
      ..qlimits(),
      max_value_nodes: 1,
    })
    is Err(QueryLimit),
  )
  assert_true(
    project_query_page(projection, qjob(), bytes, {
      ..qlimits(),
      max_value_text_bytes: 5,
    })
    is Err(QueryLimit),
  )
  assert_true(
    project_query_page(projection, qjob(), bytes, {
      ..qlimits(),
      max_total_rows: 1L,
    })
    is Err(QueryLimit),
  )
  assert_true(
    project_query_page(
      projection,
      qjob(),
      qbody(fields, [], total="101"),
      qlimits(),
    )
    is Err(QueryLimit),
  )
  assert_true(
    project_query_page(
      projection,
      qjob(),
      qbody(fields, [], total="0", token=Some("😀")),
      { ..qlimits(), max_page_token_bytes: 3, },
    )
    is Err(QueryLimit),
  )
}

///|
test "query duplicate raw keys malformed Unicode and invalid JSON literal refuse" {
  let fields = [field("j", "JSON")]
  let projection = qprojection(fields)
  for value in ["{", "NaN"] {
    assert_true(
      project_query_page(
        projection,
        qjob(),
        qbody(fields, [qrow([value.to_json()])]),
        qlimits(),
      )
      is Err(_),
    )
  }
  let duplicate = @utf8.encode("{\"jobComplete\":true,\"jobComplete\":false}")
  assert_true(
    project_query_page(projection, qjob(), duplicate, qlimits())
    is Err(InvalidQueryResponse),
  )
  let invalid_unicode = @utf8.encode("{\"name\":\"\\ud800\"}")
  assert_true(
    project_query_page(projection, qjob(), invalid_unicode, qlimits())
    is Err(InvalidQueryResponse),
  )
}

///|
test "query required metadata cannot admit SQL NULL while nullable metadata never widens original required contract" {
  let nullable = [field("s", "STRING")]
  let required = [field("s", "STRING", mode=Some("REQUIRED"))]
  assert_true(
    project_query_page(
      qprojection(nullable),
      qjob(),
      qbody(required, [qrow([Json::null()])]),
      qlimits(),
    )
    is Err(_),
  )
  assert_true(
    project_query_page(
      qprojection(required),
      qjob(),
      qbody(nullable, [qrow([Json::null()])]),
      qlimits(),
    )
    is Err(_),
  )
  assert_true(
    project_query_page(
      qprojection(required),
      qjob(),
      qbody(nullable, [qrow(["x".to_json()])]),
      qlimits(),
    )
    is Ok(_),
  )
}

///|
test "query explicit default numeric result parameters equal the original effective default" {
  let original = [field("n", "NUMERIC")]
  let response = [
    field(
      "n",
      "NUMERIC",
      precision=Some("38".to_json()),
      scale=Some("9".to_json()),
    ),
  ]
  assert_true(
    project_query_page(
      qprojection(original),
      qjob(),
      qbody(response, [qrow(["1.25".to_json()])]),
      qlimits(),
    )
    is Ok(_),
  )
}

///|
test "query JSON data uses the existing first-key law while bounding discarded duplicate values" {
  let fields = [field("j", "JSON")]
  let projection = qprojection(fields)
  let page = project_query_page(
    projection,
    qjob(),
    qbody(fields, [qrow(["{\"a\":1,\"a\":2}".to_json()])]),
    qlimits(),
  ).unwrap()
  guard query_page_cell(page, 0, 0).unwrap().value
    is @admitted.JsonData(@admitted.Object(entries)) else {
    fail("expected JSON object")
  }
  assert_eq(@admitted.element_count(entries), 1)
  assert_eq(@admitted.element_at(entries, 0).unwrap().0, "a")
  assert_true(
    @admitted.element_at(entries, 0).unwrap().1 is @admitted.Number(1.0),
  )
  assert_true(
    project_query_page(
      projection,
      qjob(),
      qbody(fields, [qrow(["{\"a\":1,\"a\":[1,2]}".to_json()])]),
      { ..qlimits(), max_value_nodes: 4, },
    )
    is Err(_),
  )
}

///|
test "query result column order is correlated before any positional cell is admitted" {
  let fields = [field("a", "STRING"), field("b", "NUMERIC")]
  let reversed = [field("b", "NUMERIC"), field("a", "STRING")]
  assert_true(
    project_query_page(
      qprojection(fields),
      qjob(),
      qbody(reversed, [qrow(["1".to_json(), "a".to_json()])]),
      qlimits(),
    )
    is Err(QuerySchemaMismatch("a")),
  )
}

///|
test "query JSON and float budget failures remain limits rather than malformed value failures" {
  let fields = [field("j", "JSON")]
  assert_true(
    project_query_page(
      qprojection(fields),
      qjob(),
      qbody(fields, [qrow(["[1,2]".to_json()])]),
      { ..qlimits(), max_value_nodes: 2, },
    )
    is Err(QueryLimit),
  )
  let floats = [field("f", "FLOAT64")]
  assert_true(
    project_query_page(
      qprojection(floats),
      qjob(),
      qbody(floats, [qrow(["1.25".to_json()])]),
      { ..qlimits(), max_value_text_bytes: 3, },
    )
    is Err(QueryLimit),
  )
}

///|
test "query original Job obeys a later tighter byte ceiling without changing its identity" {
  let fields = [field("s", "STRING")]
  assert_true(
    project_query_page(
      qprojection(fields),
      qjob(),
      qbody(fields, [], total="0"),
      { ..qlimits(), max_job_bytes: 1, },
    )
    is Err(QueryLimit),
  )
  assert_true(
    project_query_page(
      qprojection(fields),
      qjob(),
      qbody(fields, [], total="0"),
      qlimits(),
    )
    is Ok(_),
  )
}

///|
test "query totals are exact bounded integers and zero omitted rows remain distinct from missing nonzero rows" {
  let fields = [field("s", "STRING")]
  let projection = qprojection(fields)
  for total in ["9007199254740993", "18446744073709551615", "-1", "1.5"] {
    assert_true(
      project_query_page(
        projection,
        qjob(),
        qbody(fields, [], total~),
        qlimits(),
      )
      is Err(QueryLimit),
    )
  }
  let empty = @utf8.encode(
    "{\"jobReference\":{\"projectId\":\"acme-project\",\"jobId\":\"original_job-1\",\"location\":\"EU\"},\"jobComplete\":true,\"totalRows\":\"0\",\"schema\":{\"fields\":[{\"name\":\"s\",\"type\":\"STRING\"}]}}",
  )
  let page = project_query_page(projection, qjob(), empty, qlimits()).unwrap()
  assert_eq(query_page_row_count(page), 0)
  assert_eq(query_page_next_token(page), None)
  let missing = @utf8.encode(
    @utf8.decode(empty).replace(
      old="\"totalRows\":\"0\"",
      new="\"totalRows\":\"1\"",
    ),
  )
  assert_true(
    project_query_page(projection, qjob(), missing, qlimits())
    is Err(InvalidQueryResponse),
  )
}
