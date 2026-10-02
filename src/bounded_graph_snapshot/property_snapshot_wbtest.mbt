///|
// Independently authored canonical schema/records, not emitted product output.
fn property_snapshot_schema() -> String {
  (
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[{"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"R":[]},"name":"E","properties":{},"source_definition":"N","target_definition":"N"}],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_contracts":[{"nullable":false,"type":"number"}],"labels":{"Node":["name"],"Person":[]},"name":"N","properties":{"name":{"nullable":true,"type":"string"}}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
  )
}

///|
fn property_identity_body(definition : String, key : Int) -> String {
  "{\"definition\":\"" +
  definition +
  "\",\"domain\":\"sha256:" +
  "0".repeat(64) +
  "\",\"key\":[" +
  key.to_string() +
  "],\"key_types\":[{\"kind\":\"number\"}]}"
}

///|
fn expected_property_snapshot() -> String {
  let node = property_identity_body("N", 1)
  let edges = [10, 11].map(key => {
    "{\"dst\":" +
    node +
    ",\"id\":" +
    property_identity_body("E", key) +
    ",\"key\":[" +
    key.to_string() +
    "],\"props\":{},\"src\":" +
    node +
    "}"
  })
  "[\"actql-property-graph-snapshot/0.1\",\"sha256:3e06c160155f0542561eab6a31c31422a78e7a749490ff5b24fb0ce4c7ff3321\"," +
  property_snapshot_schema() +
  ",[{\"id\":" +
  node +
  ",\"key\":[1],\"props\":{\"name\":\"one\"}}],[" +
  edges.join(",") +
  "]]"
}

///|
fn property_snapshot_storage() -> @storage.Storage {
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let key_contract = @contract.primitive(@contract.NumberType, nullable=false)
  let string = @contract.primitive(@contract.StringType, nullable=true)
  let props = @carrier.rows(
    [(@schema.Unqualified("name"), Some(string))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let n = @carrier.property_node_definition(
    "N",
    [key_contract],
    props,
    ["Person", "Node"],
    label_properties=[("Person", empty), ("Node", props)],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let e = @carrier.property_node_definition(
    "E",
    [key_contract],
    empty,
    ["R"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [n],
    [@carrier.property_edge_definition(e, "N", "N").unwrap()],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  let builder = @storage.prepare(
    carrier,
    @storage.DeclaredNodes,
    storage_limits(),
  ).unwrap()
  @storage.append_property_node(builder, 0, [number(1.0)], [
    @value.recheck_runtime_value(
      text("one").value,
      string,
      snapshot_limits(100).value_limits,
    ).unwrap(),
  ]).unwrap()
  // Reverse insertion order detects accidental endpoint or input ordering.
  for key in [11.0, 10.0] {
    @storage.append_property_edge(
      builder,
      0,
      [number(key)],
      [number(1.0)],
      [number(1.0)],
      [],
    ).unwrap()
  }
  @storage.finish(builder).unwrap()
}

///|
fn finish_property_snapshot(
  preparation : Preparation,
  quantum : Int,
) -> (Snapshot, String) raise {
  let text = StringBuilder()
  let mut polls = 0
  let mut result = None
  while result is None {
    let poll = advance(preparation, quantum).unwrap()
    text.write_string(take_property_output(preparation).unwrap())
    polls += 1
    assert_true(polls < 1000)
    match poll {
      Continue(..) => ()
      Complete(snapshot, ..) => result = Some(snapshot)
    }
  }
  (result.unwrap(), text.to_string())
}

///|
test "property snapshot preserves independent parallel edges schema labels and typed key evidence" {
  for quantum in [1, 7] {
    let storage = property_snapshot_storage()
    let prepared = prepare_property(storage, snapshot_limits(100)).unwrap()
    let (snapshot, text) = finish_property_snapshot(prepared, quantum)
    assert_eq(text, expected_property_snapshot())
    // Node crypto SHA-256 of the independent preimage above, not product bytes.
    assert_eq(
      cid(snapshot),
      "sha256:4d6e1221c4244ab1074b836a651e7b4522fcdfefa86414121b7529a715b60b1a",
    )
    assert_eq(node_count(snapshot), 1)
    assert_eq(edge_count(snapshot), 2)
    assert_eq(edge_at(snapshot, 0), Some(1))
    assert_eq(edge_at(snapshot, 1), Some(0))
    assert_true(property_edge_key_at(snapshot, 0) is Some(_))
    assert_true(take_property_output(prepared) is Err(Terminal))
    assert_true(cleanup(snapshot))
    assert_eq(@storage.edge_count(storage), 2)
  }
}

///|
test "snapshot entry points share the current contract and reject historical input" {
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
  let prepared = prepare(
    property_snapshot_storage(),
    "sha256:3e06c160155f0542561eab6a31c31422a78e7a749490ff5b24fb0ce4c7ff3321",
    snapshot_limits(100),
  ).unwrap()
  let (snapshot, bytes) = finish_property_snapshot(prepared, 1)
  assert_eq(bytes, expected_property_snapshot())
  assert_eq(
    cid(snapshot),
    "sha256:4d6e1221c4244ab1074b836a651e7b4522fcdfefa86414121b7529a715b60b1a",
  )
}

///|

///|
test "property snapshot limits and cancellation expose no completed snapshot" {
  let storage = property_snapshot_storage()
  assert_true(
    prepare_property(storage, snapshot_limits(18)) is Err(WorkspaceLimit),
  )
  let prepared = prepare_property(storage, snapshot_limits(100)).unwrap()
  assert_true(advance(prepared, 1) is Ok(Continue(..)))
  assert_true(take_property_output(prepared) is Ok(_))
  assert_true(cancel(prepared))
  assert_true(prepared.builder is None)
  assert_true(advance(prepared, 1) is Err(Terminal))
  assert_true(take_property_output(prepared) is Err(Terminal))
  assert_true(cancel(prepared))
  let too_small = prepare_property(storage, {
    ..snapshot_limits(100),
    max_identity_bytes: 1000,
  }).unwrap()
  let mut failed = false
  for _ in 0..<1000 {
    match advance(too_small, 1) {
      Ok(Continue(..)) => take_property_output(too_small) |> ignore
      Ok(Complete(_, ..)) => fail("partial snapshot must not complete")
      Err(Identity(EncodingLimit)) => {
        failed = true
        break
      }
      Err(_) => fail("wrong limit failure")
    }
  }
  assert_true(failed)
  assert_true(cancel(too_small))
  assert_true(too_small.builder is None)
  assert_eq(@storage.edge_count(storage), 2)
}
