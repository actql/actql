///|
fn property_snapshot_caps() -> @snapshot.Limits {
  {
    max_workspace_slots: 1000,
    max_identity_bytes: 100000,
    max_identity_nodes: 10000,
    max_identity_depth: 100,
    value_limits: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }
}

///|
fn capture_property_snapshot(
  preparation : @snapshot.Preparation,
) -> (String, String) raise {
  let text = StringBuilder()
  let mut result = None
  let mut polls = 0
  while result is None {
    let poll = @snapshot.advance(preparation, 1).unwrap()
    text.write_string(@snapshot.take_property_output(preparation).unwrap())
    polls += 1
    assert_true(polls < 1000)
    match poll {
      @snapshot.Continue(..) => ()
      @snapshot.Complete(value, ..) => result = Some(value)
    }
  }
  let snapshot = result.unwrap()
  let cid = @snapshot.cid(snapshot)
  assert_true(@snapshot.cleanup(snapshot))
  (cid, text.to_string())
}

///|
test "property snapshot reference keys require existing Host authority rather than identity JSON" {
  let wire = "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"boundary_cid\":\"sha256:" +
    "c".repeat(64) +
    "\",\"identity_cid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"provider_identity_cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"provider_namespace\":\"mail\",\"resource_kind\":\"mail/message\",\"version\":\"actql-resource-ref/0.1\"}"
  let contract = @contract.read_checked(
    cursor(
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
    ),
    { max_nodes: 64, max_depth: 8, max_text_bytes: 4096, },
  ).unwrap()
  let live = Ref(true)
  let issuer = @value.bind_reference_issuer(
    (_, candidate) => candidate == wire,
    _ => live.val,
  )
  let key = @value.issue_reference(issuer, contract, wire, {
    max_bytes: 4096,
    max_nodes: 64,
    max_depth: 8,
    max_text_units: 4096,
  }).unwrap()
  guard key.value is @value.Reference(original) else { fail("reference") }
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let definition = @carrier.property_node_definition(
    "N",
    [contract],
    empty,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [definition],
    [],
    max_definitions=1,
    max_contract_work=1000,
  ).unwrap()
  guard carrier is @carrier.GraphValue(graph) else { fail("graph") }
  let limits = { ..graph_limits(), max_work: 10000, max_value_bytes: 10000, }
  let builder = @storage.prepare(carrier, @storage.DeclaredNodes, limits).unwrap()
  @storage.append_property_node(builder, 0, [key], []).unwrap()
  let stored = @storage.finish(builder).unwrap()
  let (cid, body) = capture_property_snapshot(
    @snapshot.prepare_property(stored, property_snapshot_caps()).unwrap(),
  )
  let header = @snapshot.read_property_header(
    cursor(body),
    graph,
    property_snapshot_caps(),
  ).unwrap()
  let record = @snapshot.property_header_node_at(header, 0).unwrap()
  let denied = @storage.prepare(carrier, @storage.DeclaredNodes, limits).unwrap()
  assert_true(@storage.append_property_snapshot_node(denied, record) is Err(_))
  assert_true(@storage.finish(denied) is Err(_))
  @storage.cancel(denied) |> ignore
  let reissuer = @value.bind_reference_reissuer((required, candidate) => {
    if candidate == wire &&
      @value.reference_compatible(original, required) &&
      @value.reference_available(original) {
      Some(original)
    } else {
      None
    }
  })
  let restored = @storage.prepare(carrier, @storage.DeclaredNodes, limits).unwrap()
  @storage.append_property_snapshot_node(
    restored,
    record,
    reference_issuer=Some(reissuer),
  ).unwrap()
  let restored = @storage.finish(restored).unwrap()
  let restored_key = @storage.node_typed_key_at(restored, 0, 0).unwrap()
  guard restored_key.value is @value.Reference(reference) else {
    fail("retained reference")
  }
  assert_true(@value.reference_same_issuer(original, reference))
  assert_eq(
    @value.reference_identity_cid(reference),
    "sha256:" + "d".repeat(64),
  )
  assert_eq(
    capture_property_snapshot(
      @snapshot.prepare_property(restored, property_snapshot_caps()).unwrap(),
    ),
    (cid, body),
  )
  live.val = false
  assert_false(@value.reference_available(reference))
  let revoked = @storage.prepare(carrier, @storage.DeclaredNodes, limits).unwrap()
  assert_true(
    @storage.append_property_snapshot_node(
      revoked,
      record,
      reference_issuer=Some(reissuer),
    )
    is Err(_),
  )
  assert_true(@storage.finish(revoked) is Err(_))
  @storage.cancel(revoked) |> ignore
  @storage.discard(stored)
  @storage.discard(restored)
}

///|
test "property snapshot uses the exact managed read schema and preserves handoff custody" {
  let owner = property_view_owner()
  let live = Ref(true)
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    { ..graph_limits(), max_work: 10000, },
    4096L,
    () => live.val,
  ).unwrap()
  append_property_node(output, 0, [number(1.0)], [text("one")]).unwrap()
  append_property_node(output, 1, [number(1.0)], []).unwrap()
  for key in [11.0, 10.0] {
    append_property_edge(
      output,
      0,
      [number(key)],
      [number(1.0)],
      [number(1.0)],
      [number(key)],
    ).unwrap()
  }
  let completed = finish_output(output).unwrap()
  let receiver = property_view_receiver(owner)
  let read = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  let storage = producer_read_storage(read).unwrap()
  let view = producer_read_view(read).unwrap()
  guard property_view_carrier() is @carrier.GraphValue(graph) else {
    fail("graph")
  }
  let stored = capture_property_snapshot(
    @snapshot.prepare_property(storage, property_snapshot_caps()).unwrap(),
  )
  let viewed = capture_property_snapshot(
    @snapshot.prepare_property_view(view, graph, property_snapshot_caps()).unwrap(),
  )
  assert_eq(viewed, stored)
  assert_true(
    @snapshot.prepare_property_view(view, graph, {
      ..property_snapshot_caps(),
      max_identity_bytes: -1,
    })
    is Err(@snapshot.InvalidLimits),
  )
  assert_true(producer_read_available(read))
  assert_eq(@storage.edge_count(storage), 2)
  let profile = @carrier.graph_property_definition(graph)
  let foreign = @carrier.property_graph(
    "sha256:" + "1".repeat(64),
    @carrier.property_graph_node_definitions(profile),
    @carrier.property_graph_edge_definitions(profile),
    max_definitions=3,
    max_contract_work=1000,
  ).unwrap()
  guard foreign is @carrier.GraphValue(foreign_graph) else { fail("graph") }
  assert_true(
    @snapshot.prepare_property_view(
      view,
      foreign_graph,
      property_snapshot_caps(),
    )
    is Err(@snapshot.InvalidGraph),
  )
  assert_true(producer_read_available(read))
  let interrupted = @snapshot.prepare_property_view(
    view,
    graph,
    property_snapshot_caps(),
  ).unwrap()
  assert_true(@snapshot.advance(interrupted, 1) is Ok(@snapshot.Continue(..)))
  live.val = false
  assert_true(@snapshot.advance(interrupted, 1) is Err(@snapshot.InvalidGraph))
  assert_true(@snapshot.cancel(interrupted))
  assert_true(
    @snapshot.take_property_output(interrupted) is Err(@snapshot.Terminal),
  )
  assert_true(
    @snapshot.prepare_property_view(view, graph, property_snapshot_caps())
    is Err(@snapshot.InvalidGraph),
  )
}
