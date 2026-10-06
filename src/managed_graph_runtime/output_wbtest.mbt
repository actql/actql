///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="managed-graph-runtime.aql",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
// Bind the current external Graph port for lifecycle tests. Public constructor
// execution is covered separately; no unsupported Graph transform is admitted.
fn producer_owner() -> @lower.BoundPrepared {
  property_view_owner()
}

///|
fn sequence_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor(
      (
        #|[{"from":"g","match_nodes":{"definition":"N","label":"Node","bindings":{"identity":"element"},"where":"true","fields":["element"]},"as":"first"},{"from":"g","match_nodes":{"definition":"N","label":"Node","bindings":{"identity":"element"},"where":"true","fields":["element"]}}]
      ),
    ),
    [("g", property_view_carrier())],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn consumer_owner(producer : @lower.BoundPrepared) -> @lower.BoundPrepared {
  property_view_receiver(producer)
}

///|
// Authored independently from storage output: the declared N/E domain and
// typed numeric key, not a scalar identity or an endpoint-derived edge tuple.
fn lifecycle_fixture_identity(
  definition : String,
  key : Int,
) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.JsonType, nullable=false),
    cursor(
      "{\"definition\":\"" +
      definition +
      "\",\"domain\":\"sha256:" +
      "0".repeat(64) +
      "\",\"key\":[" +
      key.to_string() +
      "],\"key_types\":[{\"kind\":\"number\"}]}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn graph_limits() -> @storage.Limits {
  {
    max_input_rows: 10,
    max_nodes: 10,
    max_edges: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 10000,
    max_workspace_slots: 1000,
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    cursor(value.to_string()),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap()
}

///|
fn text(value : String, nullable? : Bool = false) -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.StringType, nullable~),
    cursor("\"" + value + "\""),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 100, },
  ).unwrap()
}

///|
test "managed Graph completion supports two exact downstream consumers" {
  let owner = producer_owner()
  let live = Ref(true)
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  append_node(output, 0, [number(2.0)], [text("b")]).unwrap()
  append_edge(output, 0, [number(10.0)], [number(1.0)], [number(2.0)], [
    number(3.0),
  ]).unwrap()
  let completed = finish_output(output).unwrap()
  assert_eq(
    completed_measure(completed),
    @lifecycle.GraphMeasure(nodes=2, edges=1),
  )
  assert_eq(completed_storage_bytes(completed), Some(4096L))
  let evidence = completed_evidence(completed).unwrap()
  assert_eq(evidence_mode(evidence), @storage.DeclaredNodes)
  assert_eq(evidence_input_rows(evidence), 3)
  assert_true(
    evidence_measured_value_bytes(evidence) >=
    evidence_retained_value_bytes(evidence),
  )
  let receiver = consumer_owner(owner)
  let first = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  let second = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  assert_false(producer_read_same(first, second))
  assert_eq(@storage.node_count(producer_read_storage(first).unwrap()), 2)
  assert_eq(@storage.edge_count(producer_read_storage(second).unwrap()), 1)
  let view = producer_read_view(first).unwrap()
  assert_eq(@lifecycle.producer_view_kind(view), @carrier.GraphKind)
  assert_eq(@lifecycle.producer_view_node_count(view), Some(2))
  assert_eq(@lifecycle.producer_view_edge_count(view), Some(1))
  let identity_equality = @value.start_complete_equality(
    @lifecycle.producer_view_node_identity(view, 1).unwrap(),
    lifecycle_fixture_identity("N", 2),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let mut identity_verified = false
  for _ in 0..<1000 {
    match @value.advance_complete_equality(identity_equality, 1) {
      @value.EqualityContinue(..) => ()
      @value.EqualityComplete(equal~, ..) => {
        identity_verified = equal
        break
      }
      @value.EqualityFailed(_, ..) => break
    }
  }
  assert_true(identity_verified)
  assert_eq(@lifecycle.producer_view_edge_endpoints(view, 0), Ok((0, 1)))
  assert_eq(
    @lifecycle.producer_view_node_index(
      view,
      lifecycle_fixture_identity("N", 2),
    ),
    Ok(Some(1)),
  )
  assert_eq(
    @lifecycle.producer_view_node_index(
      view,
      lifecycle_fixture_identity("N", 3),
    ),
    Ok(None),
  )
  assert_eq(
    @lifecycle.producer_view_edge_identity_index(
      view,
      lifecycle_fixture_identity("E", 10),
    ),
    Ok(Some(0)),
  )
  assert_eq(
    @value.compare_key_values(
      @lifecycle.producer_view_edge_property(view, 0, 0).unwrap(),
      number(3.0),
    ),
    Ok(0),
  )
  assert_true(
    @lifecycle.producer_view_matches_read(
      view,
      producer_read_carrier_reference(first),
    ),
  )
  let reference = completed_reference(completed)
  assert_true(producer_read_matches_reference(first, reference))
  assert_true(producer_read_matches_reference(second, reference))
  let material = completed_material(completed).unwrap()
  assert_eq(@lifecycle.material_kind(material), @carrier.GraphKind)
  assert_eq(@lifecycle.material_storage_bytes(material), Some(4096L))
  let material_first = @lifecycle.material_prepare_view(
    material, receiver, 0, owner,
  ).unwrap()
  let material_second = @lifecycle.material_prepare_view(
    material, receiver, 0, owner,
  ).unwrap()
  assert_false(
    @lifecycle.producer_view_matches_read(
      material_first,
      @lifecycle.producer_view_read_reference(material_second),
    ),
  )
  assert_eq(@lifecycle.producer_view_node_count(material_first), Some(2))
  live.val = false
  assert_false(completed_available(completed))
  assert_false(completed_reference_available(reference))
  assert_true(
    @lifecycle.producer_view_node_identity(view, 0)
    is Err(@lifecycle.Unavailable),
  )
  assert_true(producer_read_storage(first) is None)
  assert_true(producer_read_storage(second) is None)
}

///|
test "managed Graph material owns final reclamation" {
  let owner = producer_owner()
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  let completed = finish_output(output).unwrap()
  let material = completed_material(completed).unwrap()
  assert_true(@lifecycle.material_available(material))
  assert_true(@lifecycle.reclaim_material(material))
  assert_false(@lifecycle.material_available(material))
  assert_false(@lifecycle.reclaim_material(material))
}

///|
test "managed Graph completion failure discards unhanded storage" {
  let owner = producer_owner()
  let live = Ref(false)
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  assert_eq(@storage.builder_node_count(output.graph), 1)
  assert_true(finish_output(output) is Err(Lifecycle(@lifecycle.Unavailable)))
  assert_eq(@storage.builder_node_count(output.graph), 0)
}

///|
test "managed Graph late completion failure discards unhanded storage" {
  let owner = producer_owner()
  let checks = Ref(0)
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() {
      checks.val += 1
      checks.val == 1
    },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  assert_true(finish_output(output) is Err(Lifecycle(@lifecycle.Unavailable)))
  assert_eq(checks.val, 2)
  assert_eq(@storage.builder_node_count(output.graph), 0)
}

///|
test "managed Graph material issues exact internal operation views" {
  let owner = sequence_owner()
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  let completed = finish_output(output).unwrap()
  let material = completed_material(completed).unwrap()
  let first = @lifecycle.material_prepare_operation_view(
    material, owner, 1, 0, owner,
  ).unwrap()
  let second = @lifecycle.material_prepare_operation_view(
    material, owner, 1, 0, owner,
  ).unwrap()
  assert_false(
    @lifecycle.producer_view_matches_read(
      first,
      @lifecycle.producer_view_read_reference(second),
    ),
  )
  assert_true(
    @lifecycle.material_prepare_operation_view(material, owner, 2, 0, owner)
    is Err(@lifecycle.Unverified),
  )
  assert_true(
    @lifecycle.material_prepare_operation_view(material, owner, 1, 1, owner)
    is Err(@lifecycle.Unverified),
  )
  let foreign = producer_owner()
  assert_true(
    @lifecycle.material_prepare_operation_view(material, owner, 1, 0, foreign)
    is Err(@lifecycle.Unverified),
  )
}

///|
test "managed Graph output cancels without publishing partial material" {
  let owner = producer_owner()
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  assert_true(cancel_output(output))
  assert_false(cancel_output(output))
  assert_true(finish_output(output) is Err(Closed))
  assert_true(
    prepare_output(
      owner,
      @pipeline.Step(0),
      @storage.DeclaredNodes,
      graph_limits(),
      -1L,
      fn() { true },
    )
    is Err(InvalidStorageBytes),
  )
}

///|
test "failed managed Graph output remains reclaimable" {
  let owner = producer_owner()
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  assert_true(
    append_node(output, 0, [number(1.0)], [text("different")])
    is Err(Storage(DuplicateNodeKey)),
  )
  assert_eq(@storage.builder_node_count(output.graph), 1)
  assert_true(cancel_output(output))
  assert_eq(@storage.builder_node_count(output.graph), 0)
  assert_eq(@storage.builder_edge_count(output.graph), 0)
  assert_eq(@storage.builder_retained_value_bytes(output.graph), 0)
  assert_eq(@storage.builder_workspace_slots(output.graph), 0)
  assert_false(cancel_output(output))
  assert_true(finish_output(output) is Err(Closed))
}

///|
test "unpublished completed Graph output can be revoked and discarded" {
  let owner = producer_owner()
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  let completed = finish_output(output).unwrap()
  let storage = completed_storage(completed).unwrap()
  assert_eq(@storage.node_count(storage), 1)
  assert_true(discard_completed(completed))
  assert_eq(@storage.node_count(storage), 0)
  assert_false(completed_available(completed))
  assert_true(completed_storage(completed) is None)
  assert_false(discard_completed(completed))
}

///|
test "unavailable unpublished Graph output remains reclaimable" {
  let owner = producer_owner()
  let live = Ref(true)
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    fn() { live.val },
  ).unwrap()
  append_node(output, 0, [number(1.0)], [text("a")]).unwrap()
  let completed = finish_output(output).unwrap()
  let storage = completed_storage(completed).unwrap()
  live.val = false
  assert_false(completed_available(completed))
  assert_true(discard_completed(completed))
  assert_eq(@storage.node_count(storage), 0)
  assert_false(discard_completed(completed))
}
