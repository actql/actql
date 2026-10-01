///|
fn join_order_context() -> Context {
  let inputs : Array[Input] = []
  for
    (name, fields, body) in [
      (
        "t",
        ["x", "y"],
        (
          #|{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}
        ),
      ),
      (
        "r",
        ["k"],
        (
          #|{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}
        ),
      ),
    ] {
    let seed = @wire.admit(
      @source.parse_json(body, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    inputs.push({
      relation: [{ value: name, quoted: false, }],
      name,
      source: GeneratedValues(seed),
      visible_fields: fields,
      graph_bindings: [],
    })
  }
  { ..pair_context(), inputs, }
}

///|
fn checked_join_order(source : String) -> String raise {
  let program = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("independent Values inputs are closed")
    Rejected(error) => raise @check.diagnostic_cause(error)
  }
  semantic(program)
}

///|
test "JOIN ORDER references output aliases inside expressions" {
  for
    source in [
      "SELECT t.x AS y FROM t JOIN r ON t.x = r.k ORDER BY y + 1", "FROM t |> JOIN r ON t.x = r.k |> SELECT t.x AS y |> ORDER BY y + 1",
    ] {
    let wire = checked_join_order(source)
    // The alias denotes left.x; input left.y must never be selected for this sort.
    assert_false(wire.contains("left.y"))
    assert_true(wire.contains("\"fields\":[\"y\"]"))
    assert_true(wire.contains("\"aql_join_visible\""))
  }
}

///|
test "JOIN ORDER aliases reuse computed slots without SELECT expansion" {
  let wire = checked_join_order(
    "SELECT t.x + 1 AS score FROM t JOIN r ON t.x = r.k ORDER BY score + 1, score + 1 DESC",
  )
  // One declared SELECT expression and one shared ORDER expression.
  assert_eq(wire.split("\"add\":").length(), 3)
  assert_true(wire.contains("{\"field\":\"score\"}"))
  assert_true(wire.contains("\"fields\":[\"score\"]"))
}

///|
test "JOIN ORDER accepts several aliases of the same selected expression" {
  for distinct in ["", "DISTINCT "] {
    let wire = checked_join_order(
      "SELECT " +
      distinct +
      "t.x + 1 AS a, t.x + 1 AS b FROM t JOIN r ON t.x = r.k ORDER BY t.x + 1",
    )
    // Each SELECT occurrence is evaluated once; sorting reuses the first slot.
    assert_eq(wire.split("\"add\":").length(), 3)
    assert_true(wire.contains("\"field\":\"a\",\"nulls\":\"first\""))
    assert_false(wire.contains("aql_join_sort_"))
    assert_true(wire.contains("\"fields\":[\"a\",\"b\"]"))
  }
}

///|
test "JOIN ORDER qualified input bypasses the output alias" {
  let wire = checked_join_order(
    "SELECT t.x AS y FROM t JOIN r ON t.x = r.k ORDER BY t.y + 1",
  )
  assert_true(wire.contains("left.y"))
  assert_true(wire.contains("\"fields\":[\"y\"]"))
  assert_true(wire.contains("\"aql_join_visible\""))
}

///|
test "CTE JOIN shares alias expression and selected slot resolution" {
  for
    suffix in [
      "SELECT l.x AS y FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY y + 1",
      "SELECT l.x + 1 AS a, l.x + 1 AS b FROM seed AS l JOIN seed AS r ON l.x = r.x ORDER BY l.x + 1",
    ] {
    ignore(checked_join_order("WITH seed AS (SELECT x, y FROM t) " + suffix))
  }
}

///|
test "ORDER reuse distinguishes a reference rebound by a selected alias" {
  for
    source in [
      "SELECT -x AS x FROM t ORDER BY -x", "SELECT -t.x AS x FROM t JOIN r ON t.x = r.k ORDER BY -x",
    ] {
    let wire = checked_join_order(source)
    assert_eq(wire.split("\"negate\":").length(), 3)
  }
}
