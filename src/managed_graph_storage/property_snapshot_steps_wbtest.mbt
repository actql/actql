///|
fn snapshot_test_identity(
  name : String,
  key : String,
  composite? : Bool = false,
) -> String {
  "{\"definition\":\"" +
  name +
  "\",\"domain\":\"sha256:" +
  "0".repeat(64) +
  "\",\"key\":[" +
  key +
  (if composite { ",\"a\"" } else { "" }) +
  "],\"key_types\":[{\"kind\":\"number\"}" +
  (if composite { ",{\"kind\":\"string\"}" } else { "" }) +
  "]}"
}

///|
fn snapshot_test_node(
  key : String,
  composite? : Bool = false,
) -> @decode.Cursor {
  cursor(
    "{\"id\":" +
    snapshot_test_identity("N", key, composite~) +
    ",\"key\":[" +
    key +
    (if composite { ",\"a\"" } else { "" }) +
    "],\"props\":{}}",
  )
}

///|
fn snapshot_test_edge(
  key : String,
  source : String,
  target : String,
) -> @decode.Cursor {
  cursor(
    "{\"dst\":" +
    snapshot_test_identity("N", target) +
    ",\"id\":" +
    snapshot_test_identity("E", key) +
    ",\"key\":[" +
    key +
    "],\"props\":{},\"src\":" +
    snapshot_test_identity("N", source) +
    "}",
  )
}

///|
fn complete_snapshot_append(
  state : PropertySnapshotAppend,
  quantum : Int,
) -> Result[Int, Issue] raise {
  let mut total = 0
  for _ in 0..<10000 {
    let poll = advance_property_snapshot_append(state, quantum)
    let work = match poll {
      PropertySnapshotAppendContinue(work~)
      | PropertySnapshotAppendComplete(work~)
      | PropertySnapshotAppendFailed(_, work~) => work
    }
    assert_true(work > 0 && work <= quantum)
    total += work
    match poll {
      PropertySnapshotAppendContinue(..) => ()
      PropertySnapshotAppendComplete(..) => return Ok(total)
      PropertySnapshotAppendFailed(issue, ..) => return Err(issue)
    }
  }
  abort("snapshot append did not terminate")
}

///|
test "snapshot append resumes independent identities and retains constructor accounting" {
  let mut expected_steps = None
  for quantum in [1, 7, 64] {
    let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
    let state = start_property_snapshot_append(
      builder,
      snapshot_test_node("1"),
      edge=false,
    ).unwrap()
    let steps = complete_snapshot_append(state, quantum).unwrap()
    if expected_steps is Some(previous) {
      assert_eq(steps, previous)
    } else {
      expected_steps = Some(steps)
    }
    // Independent counts: definition lookup 1, received identity 8,
    // received identity array 9, scalar key 1, identity construction 33,
    // projected identity array 9, empty payload array 1, record commit 1.
    assert_eq(builder.work, 63)
    assert_true(steps > builder.work)
    assert_eq(builder.nodes.length(), 1)
    assert_eq(
      builder.nodes[0].identity_order_key,
      "[" + snapshot_test_identity("N", "1") + "]",
    )
    cleanup_property_snapshot_append(state)
    cleanup_property_snapshot_append(state)
    assert_eq(builder.nodes[0].typed_key.length(), 1)
    let edge = start_property_snapshot_append(
      builder,
      snapshot_test_edge("10", "1", "1"),
      edge=true,
    ).unwrap()
    complete_snapshot_append(edge, quantum).unwrap() |> ignore
    assert_eq(builder.work, 244)
    cleanup_property_snapshot_append(edge)
    let storage = finish(builder).unwrap()
    assert_eq(node_count(storage), 1)
    assert_eq(edge_count(storage), 1)
    assert_eq(storage.edges[0].source, 0)
    assert_eq(storage.edges[0].target, 0)
    assert_eq(storage.edges[0].typed_key.length(), 1)
    assert_true(
      advance_property_snapshot_append(edge, 1)
      is PropertySnapshotAppendFailed(Closed, work=0),
    )
  }
  let builder = prepare(
    property_fixture(composite=true),
    DeclaredNodes,
    property_limits(),
  ).unwrap()
  let state = start_property_snapshot_append(
    builder,
    snapshot_test_node("1", composite=true),
    edge=false,
  ).unwrap()
  complete_snapshot_append(state, 1).unwrap() |> ignore
  cleanup_property_snapshot_append(state)
  let storage = finish(builder).unwrap()
  assert_eq(storage.nodes[0].typed_key.length(), 2)
  assert_true(storage.nodes[0].typed_key[0].value is @value.Number(1))
  assert_true(storage.nodes[0].typed_key[1].value is @value.Text("a"))
}

///|
test "snapshot append refuses inconsistent records without committing a partial element" {
  let mismatch = cursor(
    "{\"id\":" + snapshot_test_identity("N", "1") + ",\"key\":[2],\"props\":{}}",
  )
  for
    (input, expected) in [
      (mismatch, InvalidIdentity),
      (snapshot_test_node("null"), InvalidIdentity),
    ] {
    let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
    let state = start_property_snapshot_append(builder, input, edge=false).unwrap()
    assert_eq(complete_snapshot_append(state, 1), Err(expected))
    assert_eq(builder.nodes.length(), 0)
    assert_eq(builder.node_keys.length(), 0)
    assert_eq(builder.retained_value_bytes, 0)
    assert_true(!builder.open && builder.owns_private)
    assert_true(
      advance_property_snapshot_append(state, 1)
      is PropertySnapshotAppendFailed(Closed, work=0),
    )
    cleanup_property_snapshot_append(state)
    assert_true(cancel(builder))
  }
  let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
  append_property_snapshot_node(builder, snapshot_test_node("1")).unwrap()
  let state = start_property_snapshot_append(
    builder,
    snapshot_test_edge("10", "1", "2"),
    edge=true,
  ).unwrap()
  assert_eq(complete_snapshot_append(state, 1), Err(MissingEndpoint))
  assert_eq(builder.edges.length(), 0)
  assert_eq(builder.edge_keys.length(), 0)
  cleanup_property_snapshot_append(state)
  assert_eq(builder.nodes.length(), 1)
  assert_true(cancel(builder))
}

///|
test "snapshot append cancellation keeps retained endpoints and clears staged child custody" {
  for
    phase in [
      OpenSnapshotRecord,
      FindSnapshotDefinition,
      ReadSnapshotIdentity,
      BeginSnapshotKeys,
      NextSnapshotKey,
      BeginSnapshotProperties,
      NextSnapshotProperty,
      ReadSnapshotSource,
      ReadSnapshotTarget,
      AdmitSnapshotValue,
      EncodeSnapshotValue,
      ProjectSnapshotIdentity,
      CommitSnapshotRecord,
    ] {
    let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
    append_property_snapshot_node(builder, snapshot_test_node("1")).unwrap()
    let retained = builder.retained_value_bytes
    let slots = builder.workspace_slots
    let state = start_property_snapshot_append(
      builder,
      snapshot_test_edge("10", "1", "1"),
      edge=true,
    ).unwrap()
    assert_true(
      advance_property_snapshot_append(state, 0)
      is PropertySnapshotAppendFailed(InvalidLimits, work=0),
    )
    assert_true(state.phase == OpenSnapshotRecord)
    for _ in 0..<10000 {
      if state.phase == phase {
        break
      }
      assert_true(
        advance_property_snapshot_append(state, 1)
        is PropertySnapshotAppendContinue(work=1),
      )
    }
    assert_true(state.phase == phase)
    assert_eq(builder.edges.length(), 0)
    cleanup_property_snapshot_append(state)
    cleanup_property_snapshot_append(state)
    assert_true(
      state.admission is None &&
      state.encoding is None &&
      state.projection is None &&
      state.record is None,
    )
    assert_true(state.keys.is_empty() && state.properties.is_empty())
    assert_eq(builder.nodes.length(), 1)
    assert_eq(builder.nodes[0].typed_key.length(), 1)
    assert_eq(builder.retained_value_bytes, retained)
    assert_eq(builder.workspace_slots, slots)
    assert_true(builder.open && builder.owns_private)
    assert_true(cancel(builder))
  }
}

///|
test "snapshot append keeps exact construction ceilings and bounds its transient configuration" {
  for (limit, expected) in [(63, true), (62, false)] {
    let builder = prepare(property_fixture(), DeclaredNodes, {
      ..property_limits(),
      max_work: limit,
    }).unwrap()
    let state = start_property_snapshot_append(
      builder,
      snapshot_test_node("1"),
      edge=false,
    ).unwrap()
    match complete_snapshot_append(state, 1) {
      Ok(_) => assert_true(expected)
      Err(issue) => {
        assert_true(!expected)
        assert_eq(issue, WorkLimit)
      }
    }
    assert_eq(builder.nodes.length(), if expected { 1 } else { 0 })
    cleanup_property_snapshot_append(state)
    assert_true(cancel(builder))
  }
  let builder = prepare(
    property_fixture(composite=true),
    DeclaredNodes,
    property_limits(),
  ).unwrap()
  assert_eq(
    property_snapshot_append_workspace_slots(builder.graph, {
      ..property_limits(),
      max_value_nodes: 2,
      max_value_depth: 3,
    }),
    Some(268),
  )
  assert_eq(
    property_snapshot_append_workspace_slots(builder.graph, {
      ..property_limits(),
      max_value_nodes: 2147483647,
    }),
    None,
  )
  assert_eq(
    property_snapshot_append_workspace_slots(builder.graph, {
      ..property_limits(),
      max_value_depth: -1,
    }),
    None,
  )
  assert_true(cancel(builder))
}

///|
test "snapshot append reserves each existing resource before its atomic transfer" {
  for
    (limits, expected) in [
      ({ ..property_limits(), max_input_rows: 0, }, InputRowLimit),
      ({ ..property_limits(), max_nodes: 0, }, NodeLimit),
      (
        { ..property_limits(), max_retained_value_bytes: 0, },
        RetainedValueLimit,
      ),
      ({ ..property_limits(), max_workspace_slots: 0, }, WorkspaceLimit),
      ({ ..property_limits(), max_value_bytes: 1, }, InvalidIdentity),
    ] {
    let builder = prepare(property_fixture(), DeclaredNodes, limits).unwrap()
    let state = start_property_snapshot_append(
      builder,
      snapshot_test_node("1"),
      edge=false,
    ).unwrap()
    assert_eq(complete_snapshot_append(state, 1), Err(expected))
    assert_eq(builder.nodes.length(), 0)
    assert_eq(builder.node_keys.length(), 0)
    assert_eq(builder.input_rows, 0)
    assert_eq(builder.value_bytes, 0)
    assert_eq(builder.retained_value_bytes, 0)
    assert_eq(builder.workspace_slots, 0)
    assert_true(!builder.open && builder.owns_private)
    cleanup_property_snapshot_append(state)
    assert_true(cancel(builder))
  }
  let builder = prepare(property_fixture(), DeclaredNodes, {
    ..property_limits(),
    max_edges: 0,
  }).unwrap()
  append_property_snapshot_node(builder, snapshot_test_node("1")).unwrap()
  let held = builder.retained_value_bytes
  let state = start_property_snapshot_append(
    builder,
    snapshot_test_edge("10", "1", "1"),
    edge=true,
  ).unwrap()
  assert_eq(complete_snapshot_append(state, 1), Err(EdgeLimit))
  assert_eq(builder.edges.length(), 0)
  assert_eq(builder.edge_keys.length(), 0)
  assert_eq(builder.retained_value_bytes, held)
  cleanup_property_snapshot_append(state)
  assert_true(cancel(builder))
}

///|
fn snapshot_reference_fixture() -> (@carrier.Carrier, String, String) {
  let contract = @contract.read_checked(
    cursor(
      "{\"nullable\":false,\"resource_kind\":\"Issue\",\"type\":\"resource_ref\"}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let properties = @carrier.rows(
    [
      (
        @schema.Unqualified("p"),
        Some(@contract.primitive(@contract.JsonType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=16,
  ).unwrap()
  let definition = @carrier.property_node_definition(
    "N",
    [contract],
    properties,
    ["Node"],
    max_fields=1,
    max_name_bytes=16,
  ).unwrap()
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [definition],
    [],
    max_definitions=1,
    max_contract_work=1000,
  ).unwrap()
  let envelope = "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
    "1".repeat(64) +
    "\",\"boundary_cid\":\"sha256:" +
    "2".repeat(64) +
    "\",\"identity_cid\":\"sha256:" +
    "4".repeat(64) +
    "\",\"provider_identity_cid\":\"sha256:" +
    "3".repeat(64) +
    "\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"Issue\",\"version\":\"actql-resource-ref/0.1\"}"
  let identity = "{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[{\"identity\":\"sha256:" +
    "4".repeat(64) +
    "\"}],\"key_types\":[{\"kind\":\"resource_ref\",\"resource_kind\":\"Issue\"}]}"
  (
    graph,
    "{\"id\":" +
    identity +
    ",\"key\":[" +
    envelope +
    "],\"props\":{\"p\":{\"$json\":{\"a\":[null,3],\"z\":false}}}}",
    identity,
  )
}

///|
test "snapshot append retains reference key authority and nested properties across resumed admission" {
  let (graph, record, identity) = snapshot_reference_fixture()
  let authorized = Ref(true)
  let issuer = @value.bind_reference_issuer((_, _) => true, _ => authorized.val)
  let builder = prepare(graph, DeclaredNodes, property_limits()).unwrap()
  let state = start_property_snapshot_append(
    builder,
    cursor(record),
    edge=false,
    reference_issuer=Some(issuer),
  ).unwrap()
  complete_snapshot_append(state, 1).unwrap() |> ignore
  cleanup_property_snapshot_append(state)
  let storage = finish(builder).unwrap()
  assert_eq(storage.nodes[0].identity_order_key, "[" + identity + "]")
  let out = @encode.writer(1000, 100, 10)
  @value.emit_checked_wire_value(storage.nodes[0].properties[0], out)
  assert_eq(@encode.finish(out), "{\"$json\":{\"a\":[null,3],\"z\":false}}")
  guard storage.nodes[0].typed_key[0].value is @value.Reference(reference) else {
    abort("reference key was replaced by plain identity JSON")
  }
  assert_true(@value.reference_available(reference))
  authorized.val = false
  assert_true(!@value.reference_available(reference))
  let no_authority = prepare(graph, DeclaredNodes, property_limits()).unwrap()
  let rejected = start_property_snapshot_append(
    no_authority,
    cursor(record),
    edge=false,
  ).unwrap()
  assert_eq(complete_snapshot_append(rejected, 1), Err(InvalidIdentity))
  cleanup_property_snapshot_append(rejected)
  assert_true(cancel(no_authority))
  authorized.val = true
  let revoked = prepare(graph, DeclaredNodes, property_limits()).unwrap()
  let state = start_property_snapshot_append(
    revoked,
    cursor(record),
    edge=false,
    reference_issuer=Some(issuer),
  ).unwrap()
  for _ in 0..<10000 {
    if state.phase == ProjectSnapshotIdentity {
      break
    }
    assert_true(
      advance_property_snapshot_append(state, 1)
      is PropertySnapshotAppendContinue(work=1),
    )
  }
  assert_true(state.phase == ProjectSnapshotIdentity)
  authorized.val = false
  assert_eq(complete_snapshot_append(state, 1), Err(InvalidIdentity))
  assert_eq(revoked.nodes.length(), 0)
  cleanup_property_snapshot_append(state)
  assert_true(cancel(revoked))
}
