///|
test "admitted source emission inventory follows deep dense and failed prefixes" {
  let dense = "{\"items\":[" +
    Array::makei(32, i => i.to_string()).join(",") +
    "]}"
  let deep = Array::make(20, "[").join("") +
    "null" +
    Array::make(20, "]").join("")
  for (text, expected_nodes) in [(dense, 34), (deep, 21)] {
    let parsed = @source.parse_json_literal(text, {
      max_input_bytes: 4096,
      max_nodes: 100,
      max_depth: 40,
    }).unwrap()
    let root = @wire.admit(parsed.node, {
      max_nodes: 100,
      max_depth: 40,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    }).unwrap()
    assert_eq(
      @wire.observe_subtree_construction_geometry(root).nodes,
      expected_nodes,
    )
    let inventory = admitted_source_emission_construction_extent(expected_nodes).unwrap()
    // Independently enumerated pending Emit/Next variants and child wrappers
    // must fit beside the original Cursor tree, even on a refused prefix.
    assert_true(inventory.record_headers >= 3L * expected_nodes.to_int64())
    assert_true(inventory.reference_slots >= 2L * expected_nodes.to_int64())
    let writer = @encode.writer(text.length(), 100, 40)
    emit_admitted_source_value(root, writer)
    assert_eq(@encode.finish(writer), text)
    let short = @encode.writer(text.length() - 1, 100, 40)
    assert_true(
      try {
        emit_admitted_source_value(root, short)
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      },
    )
    assert_eq(
      @wire.observe_subtree_construction_geometry(root).nodes,
      expected_nodes,
    )
  }
  assert_true(admitted_source_emission_construction_extent(0) is None)
}
