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
    "sha256:926e2c9036cd0d0ce59d69f1b1d97c3420ebaab3af956357c7498f7c68f2aeca",
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
    #|{"base_graph_cid":"sha256:1a56f71421d48ca180e3f7479c22d61687333e6131d284ca26cb93f9a0ed0af9","edges":{"add":[],"remove":[],"update":[]},"graph_contract_cid":"sha256:926e2c9036cd0d0ce59d69f1b1d97c3420ebaab3af956357c7498f7c68f2aeca","nodes":{"add":[],"remove":[],"update":[{"after":{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":{"$json":{"é":3,"line":"a\r\nb","nil":null,"é":1}}}},"before":{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":{"$json":{"é":2,"line":"a\r\nb","nil":null,"é":1}}}}}]},"target_graph_cid":"sha256:e83bf8ee0e12c3cf90b586cea7b66a57c32281ebb57b7443e0ac01544f689a3f","version":"actql-graph-delta/0.1"}
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
      "sha256:1a56f71421d48ca180e3f7479c22d61687333e6131d284ca26cb93f9a0ed0af9",
    )
    assert_eq(
      target_cid(diff),
      "sha256:e83bf8ee0e12c3cf90b586cea7b66a57c32281ebb57b7443e0ac01544f689a3f",
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
        #|["actql-graph-snapshot/0.1","sha256:926e2c9036cd0d0ce59d69f1b1d97c3420ebaab3af956357c7498f7c68f2aeca",{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Link":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","node_definitions":[{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Other":[]},"name":"M","properties":{}},{"key_columns":[null],"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["score"]},"name":"N","properties":{"score":{"nullable":false,"type":"json"}}}],"value_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","version":"actql-graph-contract/0.1"},[{"id":{"definition":"N","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","key":[1],"key_types":[{"kind":"number"}]},"key":[1],"props":{"score":{"$json":{"é":3,"line":"a\r\nb","nil":null,"é":1}}}}],[]]
      ),
    )
    assert_true(cleanup_apply(applying))
    assert_true(cleanup(preparation))
    assert_eq(@storage.node_count(base), 1)
    assert_eq(@storage.node_count(target), 1)
  }
}
