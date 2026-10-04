///|
fn cte_capture_context() -> Context {
  let declaration = @wire.admit(
    @source.parse_json(
      (
        #|{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..fixture_context(),
    captured_stage: Some("capture"),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: Captured(declaration),
        visible_fields: ["id"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "CTE JOIN-right consumers retain the complete shared capture" {
  // With source IDs 1 and 2, chosen contributes one row and the right input
  // contributes both rows. Its predicate belongs to chosen, not acquisition.
  for
    text in [
      "WITH chosen AS (SELECT id FROM records WHERE id = 1), pairs AS (SELECT r.id AS id FROM chosen AS l CROSS JOIN records AS r) SELECT id FROM pairs ORDER BY id",
      "WITH chosen AS (SELECT id FROM records WHERE id = 1) SELECT r.id AS id FROM chosen AS l CROSS JOIN records AS r ORDER BY id",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      cte_capture_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_true(body.contains("\"filter\":{\"literal\":true}"), msg=text)
    assert_eq(body.split("\"carrier\":\"relation\"").length(), 2)
    assert_eq(body.split("\"eq\":").length(), 2)
    assert_true(
      body.contains("\"filter\":{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]}"),
    )
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      _ => fail("one captured input must supply both consumers")
    }
  }
}

///|
test "CTE aliases shadow the outer capture in JOIN-right dependency checks" {
  let actual = compile(
    @query.parse_query(
      "WITH chosen AS (SELECT id FROM records WHERE id = 1), records AS (SELECT id FROM chosen), pairs AS (SELECT r.id AS id FROM chosen AS l CROSS JOIN records AS r) SELECT id FROM pairs ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    cte_capture_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_false(body.contains("\"filter\":{\"literal\":true}"))
  assert_true(
    body.contains("\"filter\":{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]}"),
  )
  assert_eq(body.split("\"carrier\":\"relation\"").length(), 2)
  assert_eq(body.split("\"eq\":").length(), 2)
}
