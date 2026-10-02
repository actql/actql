///|
test "unconnected delta consumer refuses current Graph before snapshot allocation" {
  let current = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [],
    [],
    max_definitions=0,
    max_contract_work=100,
  ).unwrap()
  let builder = @storage.prepare(current, DeclaredNodes, storage_limits()).unwrap()
  let storage = @storage.finish(builder).unwrap()
  let contract = @graph_contract.admit(current, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  assert_true(
    prepare(
      storage,
      storage,
      @contract.primitive(NumberType, nullable=false),
      @graph_contract.cid(contract),
      diff_limits(1000),
    )
    is Err(UnsupportedGraphOperation),
  )
  assert_eq(@storage.node_count(storage), 0)
  assert_eq(@storage.edge_count(storage), 0)
  assert_eq(
    @graph_contract.cid(
      @graph_contract.admit(@storage.carrier(storage), {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 100,
      }).unwrap(),
    ),
    @graph_contract.cid(contract),
  )
}
