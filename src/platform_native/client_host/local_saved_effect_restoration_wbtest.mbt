///|
test "Native saved restoration separates outer JSON text from compiler fallback" {
  // Authored sizing DATA only, not a Program, review or approval capability.
  let wire = "{\"wire\":\"" + "x".repeat(190000) + "\"}"
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 200000,
    max_nodes: 8,
    max_depth: 2,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 8,
    max_depth: 2,
    max_string_bytes: 200000,
    max_total_string_bytes: 200000,
  }).unwrap()
  let geometry = @decode.observe_subtree_construction_geometry(cursor)
  let capacity = saved_effect_restoration_capacity("{}", wire, geometry, 2).unwrap()
  let material = @local.request_model_recovery_capacity(6L, 1).unwrap()
  let metadata = @local.request_model_recovery_material_capacity(
    wire, geometry, 2, 1,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(capacity),
    @execution.execution_capacity_retained_bytes(material) +
    @execution.execution_capacity_retained_bytes(metadata) +
    native_saved_restoration_control_bytes,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) < 536870912L,
  )
  // The replaced path treated every outer Text unit as compiler syntax. That
  // exceeds the existing facility even though this actual JSON has two nodes.
  let duplicated = @local.request_model_recovery_capacity(
    (wire.length().to_int64() + 2L) * 3L,
    2,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(duplicated) > 536870912L,
  )
  assert_eq(geometry.nodes, 2)
}

///|
test "Native saved constructor placement uses pinned text and reference extents" {
  let (header, width, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
  assert_eq(
    native_saved_effect_constructor_placement(65L, 65L),
    Some(Int64::max(header + 129L * width, array_header + 129L * pointer)),
  )
  assert_eq(native_saved_effect_constructor_placement(-1L, 0L), None)
  assert_eq(native_saved_effect_constructor_placement(0L, -1L), None)
  assert_eq(native_saved_effect_constructor_placement(2147483648L, 0L), None)
}
