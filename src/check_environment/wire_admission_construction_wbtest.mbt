///|
fn wire_construction_geometry() -> WireAdmissionConstructionGeometry {
  {
    bytes: 4096,
    nodes: 160,
    depth: 8,
    fields: 100,
    objects: 30,
    arrays: 12,
    root_fields: 12,
    max_fields: 20,
    key_utf16_units: 600,
    max_key_utf16_units: 28,
    members: 8,
    snapshots: 2,
    catalogs: 1,
    manifest_entries: 1,
  }
}

///|
test "wire admission separates retained originals from one synchronous construction peak" {
  let geometry = wire_construction_geometry()
  let peak = wire_admission_construction_extent(geometry).unwrap()
  let held = wire_admission_retained_extent(geometry).unwrap()
  assert_true(peak.record_headers >= held.record_headers)
  assert_true(peak.reference_slots >= held.reference_slots)
  assert_true(peak.scalar_words >= held.scalar_words)
  assert_true(peak.owned_utf16_units >= held.owned_utf16_units)
  assert_true(peak.owned_wire_bytes > held.owned_wire_bytes)
  assert_eq(held.owned_wire_bytes, 0L)
}

///|
test "wire admission normalization depends on the actual largest key not arbitrary value text" {
  let small = wire_construction_geometry()
  let wide = { ..small, max_key_utf16_units: 280, }
  let a = wire_admission_construction_extent(small).unwrap()
  let b = wire_admission_construction_extent(wide).unwrap()
  assert_true(b.scalar_words > a.scalar_words)
  assert_true(b.owned_utf16_units > a.owned_utf16_units)
  assert_eq(
    wire_admission_retained_extent(small),
    wire_admission_retained_extent(wide),
  )
  // A longer value String does not manufacture more key-normalization words.
  let text = wire_admission_construction_extent({ ..small, bytes: 8192, }).unwrap()
  assert_eq(text.scalar_words, a.scalar_words)
  assert_true(text.owned_utf16_units > a.owned_utf16_units)
}

///|
test "wire admission rejects inconsistent negative or detached scalar geometry" {
  let g = wire_construction_geometry()
  for
    invalid in [
      { ..g, nodes: 0, },
      { ..g, fields: -1, },
      { ..g, fields: g.nodes, },
      { ..g, root_fields: g.max_fields + 1, },
      { ..g, max_key_utf16_units: g.key_utf16_units + 1, },
      { ..g, snapshots: g.members + 1, },
      { ..g, manifest_entries: -1, },
    ] {
    assert_true(wire_admission_construction_extent(invalid) is None)
    assert_true(wire_admission_retained_extent(invalid) is None)
  }
}

///|
fn wire_construction_model_environment(model : String) -> WireEnvironment {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    model +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 65536, max_nodes: 4096, max_depth: 64, max_members: 256, },
  ).unwrap()
}

///|
test "empty ModelTask quote is bound to the genuine wire and never substitutes for populated tasks" {
  let empty = wire_construction_model_environment("")
  let peak = empty_model_tasks_construction_extent(empty).unwrap()
  let held = empty_model_tasks_retained_extent(empty).unwrap()
  assert_true(held.record_headers > 0L)
  assert_true(peak.record_headers > held.record_headers)
  // Outer wire admission deliberately does not validate ModelTask bodies.
  // Even an invalid supplied task must not acquire the empty-owner quotation.
  let supplied = wire_construction_model_environment("{}")
  assert_true(empty_model_tasks_construction_extent(supplied) is None)
  assert_true(empty_model_tasks_retained_extent(supplied) is None)
}
