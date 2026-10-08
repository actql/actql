///|
test "BY NAME ON list is copied and SQL chain spelling comes from its first list" {
  let query = parse_query(
    "SELECT 1 AS x, 2 AS y UNION ALL BY NAME ON (`y`, x) SELECT 3 AS y, 4 AS x UNION ALL BY NAME ON (Y, X) SELECT 5 AS x, 6 AS y",
    query_limits(),
  ).unwrap()
  for index in 0..<2 {
    let part = set_part_at(query, index).unwrap()
    let columns = part.by_name_columns.unwrap()
    assert_eq(columns, [
      { value: "y", quoted: true, },
      { value: "x", quoted: false, },
    ])
    columns.clear()
    assert_eq(
      set_part_at(query, index).unwrap().by_name_columns.unwrap().length(),
      2,
    )
  }
}

///|
test "BY NAME ON rejects non-identifier empty and mixed lists" {
  for
    text in [
      "SELECT 1 AS x UNION ALL BY NAME ON () SELECT 2 AS x", "SELECT 1 AS x UNION ALL BY NAME ON ('x') SELECT 2 AS x",
      "SELECT 1 AS x UNION ALL BY NAME ON (t.x) SELECT 2 AS x", "SELECT 1 AS x UNION ALL ON (x) SELECT 2 AS x",
      "SELECT 1 AS x UNION ALL BY NAME ON (x) SELECT 2 AS x UNION ALL BY NAME SELECT 3 AS x",
      "SELECT 1 AS x, 2 AS y UNION ALL BY NAME ON (x,y) SELECT 3 AS x,4 AS y UNION ALL BY NAME ON (y,x) SELECT 5 AS x,6 AS y",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}
