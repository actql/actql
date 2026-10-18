///|
test "INT64 metadata uses the existing exact Common contract for both REST aliases" {
  for kind in ["INTEGER", "INT64"] {
    let original = describe([field("n", kind)])
    let column = description_column(original, 0).unwrap()
    assert_true(
      column_contract(column) is Some(contract) &&
      contract.shape is @contract.Signed64 &&
      contract.nullable,
    )
    let projection = prepare_read_projection(original, ["n"], limits()).unwrap()
    let (wire, _) = read_projection_schema(projection)
    assert_eq(wire, "{\"n\":{\"nullable\":true,\"type\":\"int64\"}}")
    assert_eq(column_type(column), kind)
  }
}

///|
test "INT64 page preserves full range and adjacent binary64 boundary integers" {
  let fields = [field("n", "INTEGER", mode=Some("REQUIRED"))]
  let projection = qprojection(fields)
  for (text, expected) in [
    ("-9223372036854775808", -9223372036854775808L),
    ("-9007199254740993", -9007199254740993L),
    ("-1", -1L),
    ("0", 0L),
    ("9007199254740991", 9007199254740991L),
    ("9007199254740992", 9007199254740992L),
    ("9007199254740993", 9007199254740993L),
    ("9223372036854775807", 9223372036854775807L),
  ] {
    let page = project_query_page(
      projection,
      qjob(),
      qbody([field("n", "INT64")], [qrow([text.to_json()])]),
      qlimits(),
    ).unwrap()
    let checked = query_page_cell(page, 0, 0).unwrap()
    assert_true(checked.value is @admitted.Signed64(value) && value == expected)
    assert_true(
      physical_equal(checked.contract, projection.original.columns[0].contract.unwrap()),
    )
  }
}

///|
test "INT64 cells delegate canonical spelling overflow and node kind to Common" {
  let fields = [field("n", "INT64")]
  let projection = qprojection(fields)
  for text in [
    "9223372036854775808", "-9223372036854775809", "-0", "+1", "01",
    "1.0", "1e0", " 1", "1\n", "true", "null", "", "١",
  ] {
    assert_true(
      project_query_page(projection, qjob(), qbody(fields, [qrow([text.to_json()])]), qlimits())
      is Err(QueryValueAdmission("n", _)),
    )
  }
  for cell in [1.to_json(), true.to_json(), Json::array([]), Json::object(Map([]))] {
    assert_true(
      project_query_page(projection, qjob(), qbody(fields, [qrow([cell])]), qlimits())
      is Err(InvalidQueryCell("n")),
    )
  }
}

///|
test "INT64 NULL remains distinct from absent cells and required fields" {
  let fields = [field("n", "INT64")]
  let page = project_query_page(
    qprojection(fields), qjob(), qbody(fields, [qrow([Json::null()])]), qlimits(),
  ).unwrap()
  assert_true(query_page_cell(page, 0, 0).unwrap().value is @admitted.Null)
  let required = [field("n", "INT64", mode=Some("REQUIRED"))]
  assert_true(
    project_query_page(qprojection(required), qjob(), qbody(required, [qrow([Json::null()])]), qlimits())
    is Err(InvalidQueryCell("n")),
  )
  let missing = Json::object(Map([("f", [Json::object(Map([]))].to_json())]))
  assert_true(
    project_query_page(qprojection(fields), qjob(), qbody(fields, [missing]), qlimits())
    is Err(InvalidQueryCell("n")),
  )
}

///|
test "INT64 recursive records and repeated fields retain exact element contracts" {
  let fields = [field("r", "RECORD", children=Some([
    field("n", "INTEGER", mode=Some("REQUIRED")),
    field("ns", "INT64", mode=Some("REPEATED")),
  ]))]
  let repeated = [Json::object(Map([("v", "9223372036854775807".to_json())]))].to_json()
  let record = qrow(["-9223372036854775808".to_json(), repeated])
  let page = project_query_page(qprojection(fields), qjob(), qbody(fields, [qrow([record])]), qlimits()).unwrap()
  guard! query_page_cell(page, 0, 0).unwrap().value is @admitted.Object(values)
  assert_eq(values[0].0, "n")
  assert_true(values[0].1 is @admitted.Signed64(-9223372036854775808L))
  assert_true(
    values[1].1 is @admitted.Array(items) && items.length() == 1 &&
    items[0] is @admitted.Signed64(9223372036854775807L),
  )
  let invalid = [Json::object(Map([("v", Json::null())]))].to_json()
  assert_true(
    project_query_page(qprojection(fields), qjob(), qbody(fields, [qrow([
      qrow(["1".to_json(), invalid]),
    ])]), qlimits()) is Err(InvalidQueryCell("ns")),
  )
}

///|
test "INT64 text and node budgets account for exact digits before admission" {
  let fields = [field("n", "INT64")]
  let projection = qprojection(fields)
  let raw = qbody(fields, [qrow(["-9223372036854775808".to_json()])])
  let exact = { ..qlimits(), max_value_text_bytes: 20, max_value_nodes: 1 }
  assert_true(project_query_page(projection, qjob(), raw, exact) is Ok(_))
  assert_true(
    project_query_page(projection, qjob(), raw, { ..exact, max_value_text_bytes: 19 })
    is Err(QueryLimit),
  )
  let two = qbody(fields, [qrow(["1".to_json()]), qrow(["2".to_json()])], total="2")
  assert_true(project_query_page(projection, qjob(), two, exact) is Err(QueryLimit))
}

///|
test "INT64 result metadata cannot replace the original contract with number decimal or text" {
  let original = qprojection([field("n", "INT64")])
  for kind in ["FLOAT64", "NUMERIC", "STRING", "BOOL"] {
    assert_true(
      project_query_page(original, qjob(), qbody([field("n", kind)], [qrow(["1".to_json()])]), qlimits())
      is Err(QuerySchemaMismatch("n")),
    )
  }
}
