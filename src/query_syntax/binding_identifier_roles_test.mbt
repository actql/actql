///|
test "ordinary WITH and explicit AS roles reject bare reserved names at their authored position" {
  let cases = [
    ("WITH ROWS AS (SELECT 1 AS id) SELECT id FROM ROWS", 5),
    ("WITH rOwS AS (SELECT 1 AS id) SELECT id FROM rOwS", 5),
    ("SELECT 1 AS ROWS", 12),
    ("SELECT id FROM records AS ROWS", 26),
  ]
  for (source, position) in cases {
    guard parse_query(source, query_limits(), source_path="roles.sql")
      is Err(
        {
          issue: Syntax("Reserved identifier requires backticks"),
          span: Some(span),
        }
      ) else {
      fail(source)
    }
    // Independently counted ASCII offsets; QueryAbort retains a point origin.
    assert_eq(span.source_path, "roles.sql")
    assert_eq(span.start_byte, position)
    assert_eq(span.end_byte, position)
  }
}

///|
test "quoted reserved and ordinary names retain binding alias and later path roles" {
  for
    source in [
      "WITH `ROWS` AS (SELECT 1 AS id) SELECT id FROM `ROWS`", "WITH result_rows AS (SELECT 1 AS id) SELECT id FROM result_rows",
      "SELECT 1 AS `ROWS`", "SELECT `ROWS`.id FROM records AS `ROWS`", "SELECT result_rows.id FROM records AS result_rows",
      "SELECT r.ROWS FROM records AS r",
    ] {
    assert_true(parse_query(source, query_limits()) is Ok(_), msg=source)
  }
  let query = parse_query("SELECT 1 AS `ROWS`", query_limits()).unwrap()
  guard operation_at(query, 0) is Some(Select([projection], false)) else {
    fail("the ordinary SELECT projection remains present")
  }
  assert_eq(projection.name, Some({ value: "ROWS", quoted: true, }))
}

///|
test "fixed signature keys and literal object keys do not become ordinary binding names" {
  let call = parse_sga_call(
    "sequence(by: [], id: id, time: occurred_ms, pattern: [{as: first, where: kind = 1}, {as: second, where: kind = 2}], within: 20, overlap: 'allow', contiguity: 'adjacent')",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments[0], ("by", ListValue([])))
  guard call.arguments[3].1 is ListValue([ObjectValue(first), _]) else {
    fail("the existing typed pattern object remains present")
  }
  assert_eq(first[0], ("as", OutputName({ value: "first", quoted: false, })))
  assert_true(first[1] is ("where", ExpressionValue(_)))
  assert_true(
    parse_sga_call(
      "match_edges(bindings: {source: src, target: dst}, where: {literal: {SELECT: 'exact', NULL: null}}, fields: [src, dst])",
      query_limits(),
    )
    is Ok(_),
  )
}

///|
fn assert_reserved_row_alias(source : String, position : Int) -> Unit raise {
  guard parse_query(source, query_limits(), source_path="row-alias.aql")
    is Err({ issue: Syntax("Reserved identifier requires backticks"), span: Some(span) }) else {
    fail(source)
  }
  assert_eq(span.source_path, "row-alias.aql")
  assert_eq(span.start_byte, position)
  assert_eq(span.end_byte, position)
}

///|
test "UNNEST element AS shares ordinary row alias admission" {
  assert_reserved_row_alias("SELECT 1 AS id FROM UNNEST([1]) AS ROWS", 33)
}

///|
test "UNNEST OFFSET AS shares ordinary row alias admission" {
  assert_reserved_row_alias(
    "SELECT 1 AS id FROM UNNEST([1]) AS item WITH OFFSET AS ROWS",
    53,
  )
}

///|
test "Pipe AS shares ordinary row alias admission" {
  assert_reserved_row_alias("FROM records |> AS ROWS |> SELECT id", 19)
}

///|
test "Pipe UNPIVOT AS shares ordinary row alias admission" {
  assert_reserved_row_alias(
    "FROM records |> UNPIVOT(v FOR k IN(x)) AS ROWS |> SELECT v",
    40,
  )
}

///|
test "quoted reserved names remain available to each existing row alias entry" {
  for source in [
    "SELECT `ROWS` FROM UNNEST([1]) AS `ROWS`",
    "SELECT item, `ROWS` FROM UNNEST([1]) AS item WITH OFFSET AS `ROWS`",
    "FROM records |> AS `ROWS` |> SELECT `ROWS`.id",
    "FROM records |> UNPIVOT(v FOR k IN(x)) AS `ROWS` |> SELECT `ROWS`.v",
  ] {
    assert_true(parse_query(source, query_limits()) is Ok(_), msg=source)
  }
}
