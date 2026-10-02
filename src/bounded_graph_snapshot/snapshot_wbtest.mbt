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
// Historical schema bytes are rejection evidence, not executable storage.
fn legacy_snapshot_carrier() -> @carrier.Carrier raise {
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    @carrier.graph(
      @contract.primitive(NumberType, nullable=false),
      empty,
      empty,
      labels=None,
      max_labels=0,
      max_label_bytes=0,
    )
    is Err(UnsupportedGraphProfile),
  )
  @carrier.unknown_carrier(GraphKind)
}

///|
test "snapshot shared preparation uses the sole current contract" {
  for quantum in [1, 7] {
    let prepared = prepare(
      property_snapshot_storage(),
      "sha256:3e06c160155f0542561eab6a31c31422a78e7a749490ff5b24fb0ce4c7ff3321",
      snapshot_limits(100),
    ).unwrap()
    let (snapshot, bytes) = finish_property_snapshot(prepared, quantum)
    assert_eq(bytes, expected_property_snapshot())
    assert_eq(
      cid(snapshot),
      "sha256:4d6e1221c4244ab1074b836a651e7b4522fcdfefa86414121b7529a715b60b1a",
    )
    assert_eq(node_at(snapshot, 0), Some(0))
    assert_eq(edge_at(snapshot, 0), Some(1))
    assert_eq(edge_at(snapshot, 1), Some(0))
    assert_true(property_edge_key_at(snapshot, 0) is Some(_))
    assert_true(cleanup(snapshot))
  }
}

///|
test "snapshot rejects workspace before incremental allocation" {
  assert_true(
    prepare_property(property_snapshot_storage(), snapshot_limits(18))
    is Err(WorkspaceLimit),
  )
}

///|
test "snapshot cancellation releases provisional bytes without publishing" {
  let prepared = prepare_property(
    property_snapshot_storage(),
    snapshot_limits(19),
  ).unwrap()
  assert_true(advance(prepared, 1) is Ok(Continue(..)))
  assert_true(take_property_output(prepared) is Ok(_))
  assert_true(cancel(prepared))
  assert_true(advance(prepared, 1) is Err(Terminal))
  assert_true(take_property_output(prepared) is Err(Terminal))
  assert_true(cancel(prepared))
}

///|
test "historical graph cannot create an executable storage or current snapshot" {
  assert_true(
    @storage.prepare(
      legacy_snapshot_carrier(),
      @storage.DeclaredNodes,
      storage_limits(),
    )
    is Err(@storage.WrongCarrier),
  )
  assert_true(
    prepare(
      property_snapshot_storage(),
      "sha256:" + "0".repeat(64),
      snapshot_limits(100),
    )
    is Err(SnapshotContractMismatch),
  )
}
