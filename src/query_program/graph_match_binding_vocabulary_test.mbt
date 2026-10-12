///|
test "uppercase Graph node binding matches an independent complete Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_script_cte_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_script_cte_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_with_graph_2"},{"from":"aql_with_graph_2","match_nodes":{"definition":"N","bindings":{"identity":"Element"},"where":{"literal":true},"fields":["Element","p"]},"as":"aql_sga_3"},{"from":"aql_sga_3","select":["Element","p"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["Element","p"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_graph_union_source(expected)
  for bindings in ["IDENTITY: `Element`", "`Identity`: `Element`"] {
    let actual = compile_with_set(
      graph_union_prefix() +
      "FROM g |> MATCH_NODES(DEFINITION: 'N', BINDINGS: {" +
      bindings +
      "}, WHERE: {literal: true}, FIELDS: [`Element`, `p`]) |> SELECT Element, p",
    )
    assert_eq(semantic(actual), semantic(expected))
    check_graph_union_source(actual)
  }
}

///|
test "uppercase Graph edge roles retain distinct typed endpoints" {
  let actual = compile_with_set(
    "WITH n AS (SELECT 2 AS node_key, 'B' AS name UNION ALL SELECT 1 AS node_key, 'A' AS name), e AS (SELECT 11 AS edge_key, 1 AS src_key, 2 AS dst_key UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 2 AS dst_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (name)) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R NO PROPERTIES))) " +
    "FROM g |> MATCH_EDGES(DEFINITION: 'E', BINDINGS: {IDENTITY: `Edge`, `Source`: `Source`, TARGET: `Target`}, FIELDS: [`Target`, `Edge`, `Source`]) |> SELECT Target, Edge, Source",
  )
  let body = semantic(actual)
  assert_true(
    body.contains(
      "\"bindings\":{\"identity\":\"Edge\",\"source\":\"Source\",\"target\":\"Target\"}",
    ),
  )
  assert_true(body.contains("\"fields\":[\"Target\",\"Edge\",\"Source\"]"))
  check_graph_union_source(actual)
}

///|
test "independent public Graph binding controls use ordinary Ref observations and selectors" {
  // Complete controls are authored in the public fixture; no compiler or
  // evaluator-produced identity, domain or result supplies expectations.
  for
    text in [
      (
        #|{"version":"actql/0.1","id":"fixture.graph_match_match_nodes_bindings","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":2,"p":10},{"node_key":1,"p":20},{"node_key":3,"p":null}]},"as":"n"},{"values":{"schema":{"edge_key":{"type":"number","nullable":false},"src_key":{"type":"number","nullable":false},"dst_key":{"type":"number","nullable":false},"weight":{"type":"number","nullable":false}},"rows":[{"edge_key":11,"src_key":1,"dst_key":2,"weight":10},{"edge_key":10,"src_key":1,"dst_key":2,"weight":20}]},"as":"e"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"node_key","to":"node_key"},{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"e","key":["edge_key"],"source":{"definition":"N","key":["src_key"],"references_key":["node_key"]},"target":{"definition":"N","key":["dst_key"],"references_key":["node_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"edge_key","to":"edge_key"},{"from":"weight","to":"weight"}]}}]}]},"as":"g"},{"from":"g","match_nodes":{"definition":"N","label":"Person","bindings":{"identity":"Element"},"where":{"literal":true},"fields":["Element","p","node_key"]},"as":"matched"},{"from":"matched","derive":{"bound":{"not":{"is_null":{"field":"Element"}}}}},{"select":["node_key","p","bound"]},{"sort":[{"field":"node_key","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"out":{"from":"ordered","fields":["node_key","p","bound"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
      ),
      (
        #|{"version":"actql/0.1","id":"fixture.graph_match_match_edges_bindings","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":2,"p":10},{"node_key":1,"p":20},{"node_key":3,"p":null}]},"as":"n"},{"values":{"schema":{"edge_key":{"type":"number","nullable":false},"src_key":{"type":"number","nullable":false},"dst_key":{"type":"number","nullable":false},"weight":{"type":"number","nullable":false}},"rows":[{"edge_key":11,"src_key":1,"dst_key":2,"weight":10},{"edge_key":10,"src_key":1,"dst_key":2,"weight":20}]},"as":"e"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"node_key","to":"node_key"},{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"e","key":["edge_key"],"source":{"definition":"N","key":["src_key"],"references_key":["node_key"]},"target":{"definition":"N","key":["dst_key"],"references_key":["node_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"edge_key","to":"edge_key"},{"from":"weight","to":"weight"}]}}]}]},"as":"g"},{"from":"g","match_edges":{"definition":"E","label":"R","bindings":{"identity":"Edge","source":"Source","target":"Target"},"fields":["Edge","Source","Target","weight","edge_key"]},"as":"matched"},{"from":"matched","derive":{"bound":{"not":{"is_null":{"field":"Edge"}}},"source_bound":{"not":{"is_null":{"field":"Source"}}},"target_bound":{"not":{"is_null":{"field":"Target"}}}}},{"select":["edge_key","weight","bound","source_bound","target_bound"]},{"sort":[{"field":"edge_key","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"out":{"from":"ordered","fields":["edge_key","weight","bound","source_bound","target_bound"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
      ),
      (
        #|{"version":"actql/0.1","id":"fixture.graph_match_binding_Source","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":2,"p":10},{"node_key":1,"p":20},{"node_key":3,"p":null}]},"as":"n"},{"values":{"schema":{"edge_key":{"type":"number","nullable":false},"src_key":{"type":"number","nullable":false},"dst_key":{"type":"number","nullable":false},"weight":{"type":"number","nullable":false}},"rows":[{"edge_key":11,"src_key":1,"dst_key":2,"weight":10},{"edge_key":10,"src_key":1,"dst_key":2,"weight":20}]},"as":"e"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"node_key","to":"node_key"},{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"e","key":["edge_key"],"source":{"definition":"N","key":["src_key"],"references_key":["node_key"]},"target":{"definition":"N","key":["dst_key"],"references_key":["node_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"edge_key","to":"edge_key"},{"from":"weight","to":"weight"}]}}]}]},"as":"g"},{"from":"g","match_edges":{"definition":"E","bindings":{"source":"Source","target":"Target"},"fields":["Source","Target"]},"as":"endpoints"},{"from":"g","subgraph":{"nodes":{"from":"endpoints","id":"Source"}},"as":"selected"},{"from":"selected","match_nodes":{"definition":"N","where":{"literal":true},"fields":["p","node_key"]}},{"select":["p","node_key"]},{"sort":[{"field":"node_key","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"out":{"from":"ordered","fields":["p","node_key"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
      ),
      (
        #|{"version":"actql/0.1","id":"fixture.graph_match_binding_Target","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":2,"p":10},{"node_key":1,"p":20},{"node_key":3,"p":null}]},"as":"n"},{"values":{"schema":{"edge_key":{"type":"number","nullable":false},"src_key":{"type":"number","nullable":false},"dst_key":{"type":"number","nullable":false},"weight":{"type":"number","nullable":false}},"rows":[{"edge_key":11,"src_key":1,"dst_key":2,"weight":10},{"edge_key":10,"src_key":1,"dst_key":2,"weight":20}]},"as":"e"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"node_key","to":"node_key"},{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"e","key":["edge_key"],"source":{"definition":"N","key":["src_key"],"references_key":["node_key"]},"target":{"definition":"N","key":["dst_key"],"references_key":["node_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"edge_key","to":"edge_key"},{"from":"weight","to":"weight"}]}}]}]},"as":"g"},{"from":"g","match_edges":{"definition":"E","bindings":{"source":"Source","target":"Target"},"fields":["Source","Target"]},"as":"endpoints"},{"from":"g","subgraph":{"nodes":{"from":"endpoints","id":"Target"}},"as":"selected"},{"from":"selected","match_nodes":{"definition":"N","where":{"literal":true},"fields":["p","node_key"]}},{"select":["p","node_key"]},{"sort":[{"field":"node_key","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"out":{"from":"ordered","fields":["p","node_key"]}}}],"results":{"matched":{"from":{"stage":"main","result":"out"}}}}
      ),
    ] {
    let program = @program.parse(
      text,
      construction_limits().program,
      format=Json,
    ).unwrap()
    check_graph_union_source(program)
  }
}
