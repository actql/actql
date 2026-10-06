///|
fn exact_json_delta_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
test "Graph Delta retains exact nested JSON keys through snapshot diff and apply" {
  // Complete graph/schema/Delta bodies and CIDs are independently authored;
  // neither graph_diff nor snapshot output supplies an expected identity.
  let schema =
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Link":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Other":[]},"name":"M","properties":{}},{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["score"]},"name":"N","properties":{"score":{"nullable":false,"type":"json"}}}],"value_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","version":"actql-graph-contract/0.1"}
  let contract = @graph_contract.read_cursor(delta_cursor(schema), {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  assert_eq(
    @graph_contract.cid(contract),
    "sha256:5bdd4b9e031d7dc5852e2afc1381d1d68a4b0834b58359c28da29d95a29c03ce",
  )
  let graph = @graph_contract.graph(contract)
  let input = (payload : String) => {
    let builder = @storage.prepare(
      @carrier.graph_carrier(graph),
      DeclaredNodes,
      storage_limits(),
    ).unwrap()
    let value = @value.admit_json_literal(
        payload,
        delta_fixture_limits().value_limits,
      ).unwrap().0
    @storage.append_node(builder, 1, [delta_number(1.0)], [value]).unwrap()
    @storage.finish(builder).unwrap()
  }
  let base = input(
    (
      #|{"é":2,"line":"a\r\nb","nil":null,"é":1}
    ),
  )
  let target = input(
    (
      #|{"é":3,"line":"a\r\nb","nil":null,"é":1}
    ),
  )
  let expected =
    #|{"base_graph_cid":"sha256:75bc8803e85fb2c261a3a12bb99e873741900b679a0e3cfd745d8c8439f67535","edges":{"add":[],"remove":[],"update":[]},"graph_contract_cid":"sha256:5bdd4b9e031d7dc5852e2afc1381d1d68a4b0834b58359c28da29d95a29c03ce","nodes":{"add":[],"remove":[],"update":[{"after":{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":{"$json":{"é":3,"line":"a\r\nb","nil":null,"é":1}}}},"before":{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":{"$json":{"é":2,"line":"a\r\nb","nil":null,"é":1}}}}}]},"target_graph_cid":"sha256:7389cc1cdbcf147a6d85bfe8c88148fd226d188c1d52faa476053bcefacc375d","version":"actql-graph-delta/0.1"}
  for quantum in [1, 64] {
    let preparation = prepare(
      base,
      target,
      json_contract(),
      @graph_contract.cid(contract),
      delta_fixture_limits(),
    ).unwrap()
    let diff = complete_diff(preparation, quantum)
    assert_eq(
      base_cid(diff),
      "sha256:75bc8803e85fb2c261a3a12bb99e873741900b679a0e3cfd745d8c8439f67535",
    )
    assert_eq(
      target_cid(diff),
      "sha256:7389cc1cdbcf147a6d85bfe8c88148fd226d188c1d52faa476053bcefacc375d",
    )
    assert_eq(delta_wire(value(diff)), expected)
    let applying = prepare_apply(
      base,
      exact_json_delta_cursor(expected),
      delta_fixture_limits(),
      storage_limits(),
    ).unwrap()
    let applied = complete_apply(applying, quantum)
    assert_eq(
      delta_snapshot_wire(applied),
      (
        #|["actql-graph-snapshot/0.1","sha256:5bdd4b9e031d7dc5852e2afc1381d1d68a4b0834b58359c28da29d95a29c03ce",{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Link":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Other":[]},"name":"M","properties":{}},{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["score"]},"name":"N","properties":{"score":{"nullable":false,"type":"json"}}}],"value_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","version":"actql-graph-contract/0.1"},[{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":{"$json":{"é":3,"line":"a\r\nb","nil":null,"é":1}}}}],[]]
      ),
    )
    assert_true(cleanup_apply(applying))
    assert_true(cleanup(preparation))
    assert_eq(@storage.node_count(base), 1)
    assert_eq(@storage.node_count(target), 1)
  }
}
