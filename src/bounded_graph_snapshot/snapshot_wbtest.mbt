///|
fn snapshot_limits(workspace : Int) -> Limits {
  {
    max_workspace_slots: workspace,
    max_identity_bytes: 100000,
    max_identity_nodes: 10000,
    max_identity_depth: 100,
    value_limits: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }
}

///|
fn storage_limits() -> @storage.Limits {
  {
    max_input_rows: 100,
    max_nodes: 100,
    max_edges: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_value_nodes: 1000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  let contract = @contract.primitive(@contract.NumberType, nullable=false)
  @value.recheck_runtime_value(
    @value.number_value(value).unwrap(),
    contract,
    snapshot_limits(100).value_limits,
  ).unwrap()
}

///|
fn text(value : String) -> @value.CheckedValue {
  @value.checked_text_value(
    value,
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
}

///|
test "snapshot shared preparation uses the sole current contract" {
  for quantum in [1, 7] {
    let prepared = prepare(
      graph_snapshot_storage(),
      "sha256:df3a17807922ac2f939372e0cd59b31ecc7e6c860bc22c985aa8acf05971f166",
      snapshot_limits(100),
    ).unwrap()
    let (snapshot, bytes) = finish_graph_snapshot(prepared, quantum)
    assert_eq(bytes, expected_graph_snapshot())
    assert_eq(
      cid(snapshot),
      "sha256:336f66f7bbf93eda36dc081c1922457e3939b7d9f79577964ad06c28f8b80f0c",
    )
    assert_eq(node_at(snapshot, 0), Some(0))
    assert_eq(edge_at(snapshot, 0), Some(1))
    assert_eq(edge_at(snapshot, 1), Some(0))
    assert_true(edge_key_at(snapshot, 0) is Some(_))
    assert_true(cleanup(snapshot))
  }
}

///|
test "snapshot rejects workspace before incremental allocation" {
  assert_true(
    prepare(graph_snapshot_storage(), "", snapshot_limits(18))
    is Err(WorkspaceLimit),
  )
}

///|
test "snapshot cancellation releases provisional bytes without publishing" {
  let prepared = prepare(graph_snapshot_storage(), "", snapshot_limits(19)).unwrap()
  assert_true(advance(prepared, 1) is Ok(Continue(..)))
  assert_true(take_output(prepared) is Ok(_))
  assert_true(cancel(prepared))
  assert_true(advance(prepared, 1) is Err(Terminal))
  assert_true(take_output(prepared) is Err(Terminal))
  assert_true(cancel(prepared))
}

///|
test "incomplete Graph knowledge cannot create storage and contract mismatch cannot create a snapshot" {
  assert_true(
    @storage.prepare(
      @carrier.unknown_carrier(GraphKind),
      @storage.DeclaredNodes,
      storage_limits(),
    )
    is Err(@storage.WrongCarrier),
  )
  assert_true(
    prepare(
      graph_snapshot_storage(),
      "sha256:" + "0".repeat(64),
      snapshot_limits(100),
    )
    is Err(SnapshotContractMismatch),
  )
}
