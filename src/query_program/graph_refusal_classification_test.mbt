///|
fn classified_graph_source(text : String) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  )
}

///|
test "Graph argument selector and Carrier violations are distinct from support gaps" {
  for
    tail in [
      "FROM n |> node_rows() |> SELECT node_key", ", `rows` AS (FROM n |> node_rows()) FROM rows |> SELECT node_key",
      ", `rows` AS (WITH g AS (SELECT 1 AS id) FROM g |> node_rows()) FROM rows |> SELECT id",
      "FROM g |> node_rows(definition: 'missing') |> SELECT id", "FROM g |> node_rows(definition: 'E') |> SELECT id",
      "FROM g |> node_rows(label: 'missing') |> SELECT id", "FROM g |> node_rows(definition: 'N', label: 'Node') |> SELECT id",
      "FROM g |> node_rows(label: 1) |> SELECT id", "FROM g |> graphs_equal() |> SELECT equal",
      "FROM g |> graphs_equal(with: g, extra: true) |> SELECT equal", "FROM g |> graph_diff() |> SELECT delta",
      "FROM g |> graph_diff(with: g, extra: true) |> SELECT delta", "FROM g |> node_rows() |> subgraph(nodes: {ids: []}) |> SELECT node_key",
      "FROM g |> degree(direction: 'both') |> edge_rows() |> SELECT id", "FROM g |> graph_diff(with: g) |> node_rows()",
      "FROM g |> graphs_equal(with: g) |> node_rows() |> SELECT equal", "FROM g |> node_rows() |> union_graphs(with: g) |> SELECT name",
      "FROM g |> node_rows() |> subtract_graphs(with: g) |> SELECT name", "FROM n |> match_nodes(definition: 'N', where: {literal: true}, fields: [`name`])",
    ] {
    assert_true(
      classified_graph_source(graph_rows_prefix() + tail) is Err(InvalidQuery),
      msg=tail,
    )
  }
}

///|
test "Graph projection keeps unresolved producer support refusal distinct" {
  for
    tail in [
      "FROM missing |> node_rows() |> SELECT id", ", `rows` AS (FROM missing |> node_rows()) FROM rows |> SELECT id",
    ] {
    assert_true(
      classified_graph_source(graph_rows_prefix() + tail)
      is Err(UnsupportedGraph),
      msg=tail,
    )
  }
}

///|
test "Shortest retains two explicit Relation selectors through public source compilation" {
  let prefix = graph_rows_prefix() +
    ", seeds AS (FROM g |> node_rows() |> SELECT id) "
  for
    tail in [
      ", paths AS (FROM g |> shortest_path(source: {from: seeds, id: `id`}, target: {from: seeds, id: `id`}, selection: 'each_pair', direction: 'out', max_hops: 1)) FROM paths |> SELECT hop_count",
    ] {
    assert_true(classified_graph_source(prefix + tail) is Ok(_), msg=tail)
  }
}

///|
test "mean required arguments are invalid while the explicit complete generator lowers" {
  let prefix = "WITH n AS (SELECT 1 AS id, 'Company' AS entity_type), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id, entity_type)))) "
  let suffix = ") FROM GRAPH combined |> MATCH WALK (a:Person) |> SELECT a.id"
  let complete = "with: [g, g], weights: [1, 1], support: {nodes: 1, edges: 1}, properties: {nodes: {id: 'exact_equal', entity_type: 'exact_equal'}, edges: {}}"
  for
    body in [
      "with: [g, g]",
      "with: [g, g], support: {nodes: 1, edges: 1}, properties: {nodes: {id: 'exact_equal', entity_type: 'exact_equal'}, edges: {}}",
      "with: [g, g], weights: [1, 1], properties: {nodes: {id: 'exact_equal', entity_type: 'exact_equal'}, edges: {}}",
      "with: [g, g], weights: [1, 1], support: {nodes: 1, edges: 1}",
      complete + ", extra: true",
    ] {
    assert_true(
      classified_graph_source(
        prefix + ", combined AS (mean_graphs(" + body + ")" + suffix,
      )
      is Err(InvalidQuery),
      msg=body,
    )
  }
  assert_true(
    classified_graph_source(
      prefix + ", combined AS (mean_graphs(" + complete + ")" + suffix,
    )
    is Ok(_),
  )
  // Duplicate names remain the existing syntax owner's diagnostic.
  assert_true(
    @query.parse_query_script(
      prefix +
      ", combined AS (mean_graphs(" +
      complete +
      ", weights: [1, 1])" +
      suffix,
      syntax_limits(),
    )
    is Err(_),
  )
}

///|
test "heterogeneous direct Graph projection checks every candidate without admitting the shared schema" {
  let relations = "WITH p AS (SELECT 1 AS id, 'Person' AS tag), c AS (SELECT 1 AS id, 'Firmxx' AS tag), d AS (SELECT 1 AS id, 'Thirdx' AS tag, 1 AS extra) "
  let person = "p AS P KEY (id) LABEL Node PROPERTIES (id, tag)"
  let company = "c AS C KEY (id) LABEL Company PROPERTIES (id)"
  let third = "d AS D KEY (id) LABEL Other PROPERTIES (id, tag, extra)"
  for
    definitions in [
      person + ", " + company,
      company + ", " + person,
      person + ", " + third + ", " + company,
    ] {
    let prefix = relations +
      ", g AS (GRAPH (NODE TABLES (" +
      definitions +
      "))) FROM GRAPH g |> MATCH WALK (a)"
    for projection in ["a.tag", "`a`.`TAG`"] {
      assert_true(
        classified_graph_source(prefix + " |> SELECT " + projection)
        is Err(InvalidQuery),
        msg=definitions + " / " + projection,
      )
    }
    // Shared id is valid in all candidates, but heterogeneous binding itself
    // remains unconnected. A later scope is not guessed by an early probe.
    for
      tail in [
        " |> SELECT a.id", " |> SELECT a.id |> SELECT missing", " |> WHERE a.id = 1 |> SELECT a.tag",
      ] {
      assert_true(
        classified_graph_source(prefix + tail) is Err(UnsupportedGraph),
        msg=definitions + tail,
      )
    }
  }
}

///|
test "Graph star implicit exports named edges and endpoint predicates retain their support limits" {
  let node = "WITH n AS (SELECT 1 AS id), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id)))) "
  for
    tail in [
      "FROM GRAPH g |> MATCH WALK (a)", "FROM GRAPH g |> MATCH WALK (a) |> SELECT *",
    ] {
    assert_true(
      classified_graph_source(node + tail) is Err(UnsupportedProjection),
    )
  }
  let prefix = "WITH n AS (SELECT 1 AS id), e AS (SELECT 10 AS key, 1 AS src, 1 AS dst, 20 AS weight), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id)) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R PROPERTIES (weight)))) "
  for
    pattern in [
      "(:Node)-[edge:R WHERE edge.weight > 10]->(:Node)", "(:Node)-[:R]->{2,2}(:Node WHERE id > 0)",
    ] {
    assert_true(
      classified_graph_source(
        prefix +
        "FROM GRAPH g |> MATCH p = WALK " +
        pattern +
        " |> SELECT PATH_LENGTH(p) AS depth",
      )
      is Err(UnsupportedGraph),
      msg=pattern,
    )
  }
}
