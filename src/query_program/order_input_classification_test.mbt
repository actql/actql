///|
// Independent numeric input for the registered ORDER refusal shapes. Error
// expectations come from the adopted scope and ordinal rules, not prior output.
fn order_input_classification_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":1,"amount":20},{"id":2,"amount":10}]},"as":"records"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: GeneratedValues(seed),
        visible_fields: ["id", "amount"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "registered DISTINCT ORDER inputs cannot restore private JOIN or aggregate slots" {
  for
    source in [
      "WITH seed AS (SELECT id AS x, amount AS y FROM records) SELECT DISTINCT l.x AS x FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY l.y + 1",
      "WITH a AS (SELECT 1 AS id, 2 AS x UNION ALL SELECT 2 AS id, 1 AS x), b AS (SELECT 1 AS id, 20 AS y UNION ALL SELECT 2 AS id, 10 AS y), c AS (SELECT 1 AS id, 100 AS z UNION ALL SELECT 2 AS id, 200 AS z) SELECT DISTINCT a.x AS y FROM a JOIN b ON a.id = b.id JOIN c ON b.id = c.id ORDER BY c.z",
      "SELECT DISTINCT id FROM records GROUP BY id ORDER BY COUNT(*)",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        order_input_classification_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=source,
    )
  }
}

///|
test "registered property ORDER and ambiguous GROUP inputs are invalid queries" {
  for
    source in [
      "SELECT DISTINCT id FROM objects ORDER BY payload.score", "SELECT DISTINCT COUNT(*) AS n FROM objects GROUP BY payload.score + 1 ORDER BY objects.payload.score + 1",
      "SELECT DISTINCT -id AS id, COUNT(*) AS n FROM objects GROUP BY objects.id ORDER BY objects.id + 1",
      "SELECT payload.score, other.score, COUNT(*) AS n FROM objects GROUP BY score",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=source,
    )
  }
}

///|
test "registered ORDER positions reject invalid literals and current column bounds" {
  for
    source in [
      "SELECT amount, id FROM records ORDER BY 0", "SELECT amount, id FROM records ORDER BY -1",
      "SELECT amount, id FROM records ORDER BY 3", "SELECT amount, id FROM records ORDER BY 1.0",
      "FROM records AS original |> DROP amount |> ORDER BY 2",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        order_input_classification_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=source,
    )
  }
}

///|
test "ORDER input classification retains positions and ordinary constant expressions" {
  for
    source in [
      "SELECT amount, id FROM records ORDER BY (1), +2", "SELECT amount, id FROM records ORDER BY 1 + 0",
      "SELECT amount, id FROM records ORDER BY -(1)",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        order_input_classification_context(),
        construction_limits(),
      )
      is Ok(_),
      msg=source,
    )
  }
}

///|
test "invalid ORDER inputs do not reclassify an unimplemented analytic connection" {
  // query-text.md retains default/unordered DISTINCT analytics as a coverage
  // gap. No invalid ordinal or inaccessible DISTINCT ORDER input occurs here.
  let source = "SELECT COUNTIF(DISTINCT amount > 0) OVER () AS n FROM records"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      order_input_classification_context(),
      construction_limits(),
    )
    is Err(UnsupportedAnalytic),
  )
}
