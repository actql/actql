///|
fn capture_construction_profile_fixture() -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
] {
  effect_construction_profile(
    { max_bytes: 128, max_nodes: 32, max_depth: 8, },
    { max_path_bytes: 256, max_target_bytes: 64, max_body_bytes: 128, },
    { max_bytes: 128, max_nodes: 32, max_depth: 8, max_identity_bytes: 128, },
    { max_bytes: 128, max_nodes: 32, max_depth: 8, max_rows: 1, },
    {
      max_bytes: 256,
      max_nodes: 64,
      max_depth: 8,
      max_fields: 4,
      max_name_units: 64,
    },
    1024,
    128,
    2,
    12,
    5,
    7,
  ).unwrap()
}

///|
test "Salesforce capture folds the same constructor quartet without making a request inventory" {
  let profile = capture_construction_profile_fixture()
  assert_eq(profile.length(), 4)
  assert_true(profile[0].1 is None)
  assert_true(profile[0].2 is Some(_))
  let list : @catalog.ListLimits = {
    max_bytes: 256,
    max_nodes: 64,
    max_depth: 8,
    max_resources: 4,
    max_selected: 2,
    max_name_units: 64,
  }
  let describe : @catalog.DescribeLimits = {
    max_bytes: 256,
    max_nodes: 64,
    max_depth: 8,
    max_fields: 4,
    max_name_units: 64,
  }
  let preview : @source.ParseLimits = {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }
  let capture = effect_capture_construction_profile(
    Some(profile),
    preview,
    list,
    describe,
    1024,
    512,
    4096,
    128,
    2,
    12,
    5,
    7,
  ).unwrap()
  assert_eq(capture.length(), 3)
  assert_true(@execution.execution_capacity_retained_bytes(capture[0]) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(capture[0]) >
    @execution.execution_capacity_retained_bytes(capture[0]),
  )
  assert_eq(@execution.execution_capacity_retained_bytes(capture[2]), 0L)
  assert_eq(@execution.execution_capacity_execution_bytes(capture[2]), 0L)
  // The outer Store limit bounds parsing, independently of the decoded raw
  // metadata limit. Tightening raw does not silently shrink that parse peak.
  let raw = effect_capture_construction_profile(
    Some(profile),
    preview,
    list,
    describe,
    1024,
    128,
    4096,
    128,
    2,
    12,
    5,
    7,
  ).unwrap()
  let wire = effect_capture_construction_profile(
    Some(profile),
    preview,
    list,
    describe,
    1024,
    128,
    8192,
    128,
    2,
    12,
    5,
    7,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(wire[0]) >
    @execution.execution_capacity_execution_bytes(raw[0]),
  )
  // Absence is refusal, never a zero profile or a forged ordinary fallback.
  assert_true(
    effect_capture_construction_profile(
      None,
      preview,
      list,
      describe,
      1024,
      128,
      4096,
      128,
      2,
      12,
      5,
      7,
    )
    is None,
  )
}

///|
test "Salesforce whole Catalog recovery counts cumulative raw metadata not one full body per Resource" {
  let list : @catalog.ListLimits = {
    max_bytes: 256,
    max_nodes: 64,
    max_depth: 8,
    max_resources: 4,
    max_selected: 2,
    max_name_units: 64,
  }
  let describe : @catalog.DescribeLimits = {
    max_bytes: 256,
    max_nodes: 64,
    max_depth: 8,
    max_fields: 1000,
    max_name_units: 64,
  }
  let bounded = sf_effect_catalog_recovery_capacity(
    list, describe, 128, 1024, 128,
  ).unwrap()
  let many_fields = sf_effect_catalog_recovery_capacity(
    list,
    { ..describe, max_fields: 1000000, },
    128,
    1024,
    128,
  ).unwrap()
  // Every complete field spends original bytes; growing an unused ceiling
  // cannot multiply those same128 raw bytes by a million metadata records.
  assert_eq(
    @execution.execution_capacity_retained_bytes(bounded),
    @execution.execution_capacity_retained_bytes(many_fields),
  )
}

///|
test "named cold recovery funds preflight then actual Source geometry under unchanged 512MiB" {
  let profile = capture_construction_profile_fixture()
  let list : @catalog.ListLimits = {
    max_bytes: 4000000,
    max_nodes: 100000,
    max_depth: 32,
    max_resources: 2000,
    max_selected: 200,
    max_name_units: 100000,
  }
  let describe : @catalog.DescribeLimits = {
    max_bytes: 4000000,
    max_nodes: 400000,
    max_depth: 32,
    max_fields: 1000,
    max_name_units: 200000,
  }
  let preview : @source.ParseLimits = {
    max_input_bytes: 3454,
    max_nodes: 3454,
    max_depth: 64,
  }
  // Public large-text/small-forest shape: the Source owner measures the SAME
  // actual body, rather than inheriting one parser node per Base64 wire byte.
  let text = "{\"name\":\"Account\",\"fields\":[],\"description\":\"" +
    "x".repeat(251000) +
    "\"}"
  let body = @utf8.encode(text)
  let geometry = named_describe_response_geometry(body, describe).unwrap()
  let select = (preflight, geometry) => {
    effect_capture_construction_profile(
      Some(profile),
      preview,
      list,
      describe,
      8000000,
      8000000,
      1000000,
      1024,
      1,
      4,
      5,
      7,
      recovery_input_bytes=336591,
      recovery_source_nodes=Some(4096),
      recovery_preflight=preflight,
      named_source_geometry=geometry,
    ).unwrap()
  }
  let prelude = select(true, None)
  let actual = select(false, Some(geometry))
  let old = select(false, None)
  let retained = @execution.execution_capacity_retained_bytes(actual[0])
  assert_eq(@execution.execution_capacity_retained_bytes(prelude[0]), retained)
  assert_eq(@execution.execution_capacity_retained_bytes(old[0]), retained)
  assert_true(
    @execution.execution_capacity_execution_bytes(prelude[0]) < 536870912L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(actual[0]) < 536870912L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(actual[0]) >=
    @execution.execution_capacity_execution_bytes(prelude[0]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(old[0]) > 536870912L,
  )
  // Measuring the source is not Catalog validation or an observation proof.
  assert_true(geometry.node_upper < 32)
}
