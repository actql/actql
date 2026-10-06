///|
// The low-level control and the actual material factory use the same checked
// owner and bytes; both must apply the current Host authority on readmission.
test "Graph material snapshot reload preserves a current reference key issuer" {
  let contract = @value_contract.read_checked(
    input_cursor(
      "{\"nullable\":false,\"resource_kind\":\"Issue\",\"type\":\"resource_ref\"}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let properties = @carrier_contract.rows(
    [],
    field_set=@carrier_contract.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let definition = @carrier_contract.graph_node_definition(
    "N",
    [contract],
    properties,
    [],
    max_fields=1,
    max_name_bytes=16,
  ).unwrap()
  let graph = @carrier_contract.graph(
    "sha256:" + "0".repeat(64),
    [definition],
    [],
    max_definitions=1,
    max_contract_work=1000,
  ).unwrap()
  let pipeline = @pipeline.check_carriers(
    input_cursor("[]"),
    [("g", graph)],
    None,
    Some(input_cursor("\"g\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let issuer = @admitted.bind_reference_issuer((_, _) => true, _ => true)
  let key = @admitted.issue_reference(
    issuer,
    contract,
    "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
    "1".repeat(64) +
    "\",\"boundary_cid\":\"sha256:" +
    "2".repeat(64) +
    "\",\"identity_cid\":\"sha256:" +
    "4".repeat(64) +
    "\",\"provider_identity_cid\":\"sha256:" +
    "3".repeat(64) +
    "\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"Issue\",\"version\":\"actql-resource-ref/0.1\"}",
    { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_units: 1000, },
  ).unwrap()
  let output = @graphs.prepare_output(
    owner,
    @pipeline.Input(0),
    @graph_storage.DeclaredNodes,
    carrier_graph_storage_limits(),
    4096L,
    () => true,
  ).unwrap()
  @graphs.append_node(output, 0, [key], []).unwrap()
  let source = @graphs.finish_output(output).unwrap()
  let material = @local_bridge.completed_graph_snapshot_material(
    @bounded.control(),
    owner,
    @pipeline.Input(0),
    source,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
    100000,
    100000,
    1000000L,
    () => true,
    reference_issuer=Some(issuer),
  ).unwrap()
  let operation = @carrier_runtime.material_prepare_snapshot(material)
    .unwrap()
    .unwrap()
  let saved = StringBuilder()
  let mut saved_complete = false
  for _ in 0..<10000 {
    let advanced = (operation.advance_save)(64).unwrap()
    saved.write_string((operation.take_output)().unwrap())
    if advanced.complete {
      saved_complete = true
      break
    }
  }
  assert_true(saved_complete)
  let content = (operation.content)().unwrap()
  // Positive control: exactly these saved bytes can reload under the same
  // checked owner when the existing low-level entry receives the current issuer.
  let direct = @local_bridge.start_graph_snapshot_reload(
    @bounded.control(),
    owner,
    @pipeline.Input(0),
    input_cursor(saved.to_string()),
    content.cid,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    4096L,
    1000,
    () => true,
    () => true,
    reference_issuer=Some(issuer),
  ).unwrap()
  guard snapshot_terminal(direct, quantum=64)
    is @local_bridge.Complete(restored, ..) else {
    fail("reference-key low-level positive control must restore")
  }
  @local_bridge.cleanup_rows_to_graph(direct).unwrap() |> ignore
  @graphs.discard_completed(restored) |> ignore
  (operation.release_source)(content.cid).unwrap()
  assert_false(@graphs.completed_available(source))
  (operation.begin_reload)(saved.to_string(), () => true).unwrap()
  let mut restored_complete = false
  let mut issue : @carrier_runtime.SnapshotIssue? = None
  for _ in 0..<10000 {
    let advanced = (operation.advance_reload)(64).unwrap()
    if advanced.issue is Some(found) {
      issue = Some(found)
      break
    }
    if advanced.complete {
      restored_complete = true
      break
    }
  }
  if restored_complete {
    let restored = (operation.take_material)().unwrap()
    @carrier_runtime.reclaim_material(restored) |> ignore
  }
  @carrier_runtime.reclaim_material(material) |> ignore
  assert_true(
    issue is None,
    msg="material factory dropped the current reference issuer",
  )
  assert_true(restored_complete)
}
