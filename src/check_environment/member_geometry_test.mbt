///|
fn member_geometry_environment(original_member : String) -> WireEnvironment {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[" +
    original_member +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    caps(),
  ).unwrap()
}

///|
test "member access inventory includes original section index closure and both Some tags" {
  let environment = member_geometry_environment("{\"a\":{}}")
  let original_member = member_at(environment, MappingContracts, 0).unwrap()
  assert_true(physical_equal(member_environment(original_member), environment))
  assert_eq(
    (member_section(original_member), member_index(original_member)),
    (MappingContracts, 0),
  )
  // The actual member_at closure captures section and index in addition to
  // its owner reference. Its input and returned Some each own one scalar tag.
  assert_eq(member_access_construction_extent(), {
    record_headers: 3L,
    reference_slots: 3L,
    scalar_words: 4L,
  })
}

///|
test "member geometry retains actual root relative depth with the same node count" {
  for
    (body, expected_depth) in [
      ("{\"a\":{},\"b\":{}}", 2),
      ("{\"a\":{\"b\":{}}}", 3),
    ] {
    let environment = member_geometry_environment(body)
    let original_member = member_at(environment, MappingContracts, 0).unwrap()
    let expected = (@utf8.encode(body).length(), 3, expected_depth)
    assert_eq(member_emission_geometry(original_member), expected)
    assert_eq(member_emission_geometry(original_member), expected)
    assert_eq(member_usage(original_member), (expected.0, expected.1))
    assert_eq(
      member_cid(original_member),
      "sha256:" + @sha.hex(@utf8.encode(body)),
    )
    // The envelope itself has two more containers than this member root.
    assert_true(expected_depth < caps().max_depth)
  }
}

///|
test "member depth captures canonical Unicode and empty objects without sizing arrays" {
  for
    (body, nodes, depth) in [
      ("{}", 1, 1),
      ("{\"nested\":[{},{\"value\":\"東京😀\"}]}", 5, 3),
    ] {
    let environment = member_geometry_environment(body)
    let original_member = member_at(environment, MappingContracts, 0).unwrap()
    assert_eq(
      member_emission_geometry(original_member),
      (@utf8.encode(body).length(), nodes, depth),
    )
  }
  assert_eq(member_depth_capture_extent(), {
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L,
  })
  assert_eq(member_depth_retention_extent(2).unwrap(), {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 2L,
  })
  assert_true(member_depth_retention_extent(-1) is None)
}
