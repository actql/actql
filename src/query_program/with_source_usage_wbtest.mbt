///|
fn with_usage_input(name : String) -> Input {
  {
    relation: [{ value: name, quoted: false, }],
    name,
    source: StepReference,
    visible_fields: ["id"],
    graph_bindings: [],
  }
}

///|
// This census only controls capture predicate placement. It does not admit
// selector identity, Catalog ownership, Carrier types or executable order.
test "WITH capture counts a second SGA selector consumer" {
  let input = with_usage_input("seeds")
  for
    call in [
      "reach(start: {from: seeds, id: `id`}, direction: 'out', max_depth: 2)", "traverse(start: {from: seeds, id: `id`}, direction: 'out', max_depth: 2)",
      "shortest_path(source: {from: seeds, id: `id`}, target: 2)", "subgraph(nodes: {from: seeds, id: `id`})",
    ] {
    let script = @query.parse_query_script(
      "WITH filtered AS (FROM seeds |> WHERE id = 1), selected AS (FROM g |> " +
      call +
      ") FROM filtered",
      mapping_syntax_limits(),
    ).unwrap()
    assert_eq(unshared_script_sources(script, [input]), [])
  }
}

///|
test "WITH capture does not treat SGA ID strings as producer references" {
  let script = @query.parse_query_script(
    "WITH filtered AS (FROM seeds |> WHERE id = 1), selected AS (FROM g |> reach(start: 'seeds', direction: 'out', max_depth: 2)) FROM filtered",
    mapping_syntax_limits(),
  ).unwrap()
  assert_eq(unshared_script_sources(script, [with_usage_input("seeds")]), [
    "seeds",
  ])
}

///|
test "WITH capture resolves a nearer selector binding without counting an outer input" {
  let script = @query.parse_query_script(
    "WITH filtered AS (FROM seeds |> WHERE id = 1), nested AS (WITH seeds AS (SELECT 2 AS id) FROM g |> reach(start: {from: seeds, id: `id`}, direction: 'out', max_depth: 2)) FROM filtered",
    mapping_syntax_limits(),
  ).unwrap()
  assert_eq(unshared_script_sources(script, [with_usage_input("seeds")]), [
    "seeds",
  ])
}
