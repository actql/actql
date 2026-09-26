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
fn graph_storage() -> @storage.Storage {
  let number_contract = @contract.primitive(
    @contract.NumberType,
    nullable=false,
  )
  let node = @carrier.rows(
    [
      (@schema.Unqualified("a"), Some(number_contract)),
      (
        @schema.Unqualified("z"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
  let edge = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let graph = @carrier.graph(
    number_contract,
    node,
    edge,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    label_contract=None,
  ).unwrap()
  let builder = @storage.prepare(
    graph,
    @storage.DeclaredNodes,
    storage_limits(),
  ).unwrap()
  @storage.append_node(builder, number(1.0), [number(2.0), text("last")])
  |> ignore
  @storage.append_edge(builder, number(1.0), number(1.0), None, []) |> ignore
  @storage.finish(builder).unwrap()
}

///|
test "snapshot advances canonically with quantum one" {
  let input = graph_storage()
  let preparation = prepare(
    input,
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    snapshot_limits(12),
  ).unwrap()
  let mut polls = 0
  let mut result = None
  while result is None {
    match advance(preparation, 1) {
      Ok(Continue(_)) => {
        polls += 1
        assert_true(polls < 100)
      }
      Ok(Complete(snapshot, ..)) => result = Some(snapshot)
      Err(_) => fail("snapshot failed")
    }
  }
  let snapshot = result.unwrap()
  assert_eq(
    cid(snapshot),
    "sha256:cb6e72527d57d5cc88e9144b16f985ff80a11f9939ce287bcff0314297b804f5",
  )
  assert_eq(node_count(snapshot), 1)
  assert_eq(node_at(snapshot, 0), Some(0))
  assert_true(node_key_at(snapshot, 0) is Some(_))
  assert_eq(edge_count(snapshot), 1)
  assert_eq(edge_at(snapshot, 0), Some(0))
  assert_true(edge_key_at(snapshot, 0) is Some(_))
}

///|
test "snapshot rejects workspace before incremental allocation" {
  assert_true(
    prepare(
      graph_storage(),
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      snapshot_limits(11),
    )
    is Err(WorkspaceLimit),
  )
}

///|
test "snapshot cancellation releases partial preparation" {
  let preparation = prepare(
    graph_storage(),
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    snapshot_limits(12),
  ).unwrap()
  assert_true(advance(preparation, 1) is Ok(Continue(_)))
  assert_true(cancel(preparation))
  assert_true(advance(preparation, 1) is Err(Terminal))
  assert_true(cancel(preparation))
}

///|
/// Nodes 10 and 9 and three edges are stored out of order. Snapshot identity
/// sorts them by canonical typed ID order (9 before 10, absent labels first);
/// the expected CID is the SHA-256 of the specified preimage computed
/// outside this implementation.
test "snapshot sorts numeric identities by typed value" {
  let number_contract = @contract.primitive(
    @contract.NumberType,
    nullable=false,
  )
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let graph = @carrier.graph(
    number_contract,
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    label_contract=Some(
      @contract.primitive(@contract.StringType, nullable=true),
    ),
  ).unwrap()
  let label_contract = @contract.primitive(@contract.StringType, nullable=true)
  let null_label = @value.recheck_runtime_value(
    @value.null_value(),
    label_contract,
    snapshot_limits(100).value_limits,
  )
  let builder = @storage.prepare(
    graph,
    @storage.DeclaredNodes,
    storage_limits(),
  ).unwrap()
  @storage.append_node(builder, number(10.0), []).unwrap()
  @storage.append_node(builder, number(9.0), []).unwrap()
  @storage.append_edge(builder, number(10.0), number(9.0), null_label, []).unwrap()
  @storage.append_edge(
    builder,
    number(9.0),
    number(10.0),
    @value.recheck_runtime_value(
      text("a").value,
      label_contract,
      snapshot_limits(100).value_limits,
    ),
    [],
  ).unwrap()
  @storage.append_edge(builder, number(9.0), number(10.0), null_label, []).unwrap()
  let input = @storage.finish(builder).unwrap()
  let preparation = prepare(
    input,
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    snapshot_limits(100),
  ).unwrap()
  let mut result = None
  while result is None {
    match advance(preparation, 1) {
      Ok(Continue(_)) => ()
      Ok(Complete(snapshot, ..)) => result = Some(snapshot)
      Err(issue) => {
        assert_eq(Some(issue), None)
        return
      }
    }
  }
  let snapshot = result.unwrap()
  assert_eq(
    cid(snapshot),
    "sha256:58e79d832142c356f3d84c82aaefe02107299e2c35ad0ee4ea7f9b775462e8b2",
  )
  assert_eq(node_at(snapshot, 0), Some(1))
  assert_eq(node_at(snapshot, 1), Some(0))
  assert_eq(edge_at(snapshot, 0), Some(2))
  assert_eq(edge_at(snapshot, 1), Some(1))
  assert_eq(edge_at(snapshot, 2), Some(0))
}
