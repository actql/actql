///|
test "Table CTAS and terminal Pipe preserve authored intent and target" {
  for
    (text, named, replace) in [
      ("CREATE TABLE analytics.report AS SELECT 1 AS id", None, false),
      (
        "CREATE OR REPLACE TABLE analytics.report AS (SELECT 1 AS id)",
        None,
        true,
      ),
      ("SELECT 1 AS id |> CREATE TABLE analytics.report", None, false),
      (
        "SELECT 1 AS id |> EFFECT save CREATE OR REPLACE TABLE analytics.report",
        Some("save"),
        true,
      ),
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    let clause = terminal_table_effect(query).unwrap()
    assert_eq(clause.name.map(part => part.value), named)
    assert_eq(clause.allow_replace, replace)
    assert_eq(clause.target, [
      { value: "analytics", quoted: false, },
      { value: "report", quoted: false, },
    ])
    assert_true(terminal_effect(query) is None)
  }
}

///|
test "Table writes are terminal and forbidden in declaration bodies" {
  for
    text in [
      "SELECT 1 AS id |> CREATE TABLE analytics.report |> SELECT id", "CREATE TABLE analytics.report AS CREATE TABLE analytics.other AS SELECT 1 AS id",
      "CREATE TABLE analytics.report AS (SELECT 1 AS id |> CREATE TABLE analytics.other)",
      "WITH t AS (SELECT 1 AS id |> CREATE TABLE analytics.report) SELECT id FROM t",
      "SELECT 1 AS id |> EFFECT", "CREATE TABLE analytics.report SELECT 1 AS id",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}
