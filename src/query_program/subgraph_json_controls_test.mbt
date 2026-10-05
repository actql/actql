///|
test "subgraph-json-nodes ordinary checker control" {
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.subgraph","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":3,"p":null},{"node_key":2,"p":20},{"node_key":1,"p":10}]},"as":"n"},{"values":{"schema":{"edge_key":{"type":"number","nullable":false},"src_key":{"type":"number","nullable":false},"dst_key":{"type":"number","nullable":false},"w":{"type":"number","nullable":false}},"rows":[{"edge_key":11,"src_key":1,"dst_key":2,"w":20},{"edge_key":10,"src_key":1,"dst_key":2,"w":10},{"edge_key":12,"src_key":2,"dst_key":3,"w":40},{"edge_key":13,"src_key":2,"dst_key":2,"w":30}]},"as":"e"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"e","key":["edge_key"],"source":{"definition":"N","key":["src_key"]},"target":{"definition":"N","key":["dst_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"w","to":"w"}]}}]}]},"as":"g"},{"from":"g","node_rows":true,"as":"all_nodes"},{"from":"all_nodes","filter":{"lte":[{"field":"node_key"},{"literal":2}]}},{"select":["id"],"as":"selected"},{"from":"g","subgraph":{"nodes":{"from":"selected","id":"id"}},"as":"slice"},{"from":"slice","node_rows":true,"as":"rows"},{"from":"rows","select":["node_key","p"]},{"sort":[{"field":"node_key","dir":"asc","nulls":"first"}],"as":"published"}],"results":{"out":{"from":"published","fields":["node_key","p"]}}}],"results":{"answer":{"from":{"stage":"main","result":"out"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("No acquisition in authored JSON")
  }
}

///|
test "subgraph-json-filtered-edges ordinary checker control" {
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.subgraph","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"node_key":{"type":"number","nullable":false},"p":{"type":"number","nullable":true}},"rows":[{"node_key":3,"p":null},{"node_key":2,"p":20},{"node_key":1,"p":10}]},"as":"n"},{"values":{"schema":{"edge_key":{"type":"number","nullable":false},"src_key":{"type":"number","nullable":false},"dst_key":{"type":"number","nullable":false},"w":{"type":"number","nullable":false}},"rows":[{"edge_key":11,"src_key":1,"dst_key":2,"w":20},{"edge_key":10,"src_key":1,"dst_key":2,"w":10},{"edge_key":12,"src_key":2,"dst_key":3,"w":40},{"edge_key":13,"src_key":2,"dst_key":2,"w":30}]},"as":"e"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"n","key":["node_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[{"name":"E","from":"e","key":["edge_key"],"source":{"definition":"N","key":["src_key"]},"target":{"definition":"N","key":["dst_key"]},"labels":[{"name":"R","properties":{"mode":"columns","columns":[{"from":"w","to":"w"}]}}]}]},"as":"g"},{"from":"g","node_rows":true,"as":"all_nodes"},{"from":"all_nodes","filter":{"lte":[{"field":"node_key"},{"literal":2}]}},{"select":["id"],"as":"selected"},{"from":"g","subgraph":{"nodes":{"from":"selected","id":"id"},"edges":{"gt":[{"field":"w"},{"literal":10}]}},"as":"slice"},{"from":"slice","edge_rows":true,"as":"rows"},{"from":"rows","select":["edge_key","w"]},{"sort":[{"field":"edge_key","dir":"asc","nulls":"first"}],"as":"published"}],"results":{"out":{"from":"published","fields":["edge_key","w"]}}}],"results":{"answer":{"from":{"stage":"main","result":"out"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("No acquisition in authored JSON")
  }
}
