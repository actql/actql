///|
fn original_view_values(
  invalid_bounded? : Bool = false,
  views? : Int = 1,
) -> ProtocolValueContracts raise {
  let contents = reference_fixture(
    complete_view=true,
    view_count=views,
    policy_body=Some(policy_body_fixture("unknown")),
    bodies=value_bodies("{\"nullable\":false,\"type\":\"number\"}"),
    path=if invalid_bounded {
      ["view", "acquisition", "modes", "0", "bounded"]
    } else {
      []
    },
    replacement=if invalid_bounded { Some(@json.parse("false")) } else { None },
  )
  let policies = check_source_data_policies(
    check_catalog_references(contents, reference_caps()).unwrap(),
    policy_limits(),
  ).unwrap()
  check_protocol_value_contracts(policies, protocol_value_limits()).unwrap()
}

///|
test "original populated Source shape mode demand and partial work retain their same owners" {
  let values = original_view_values()
  let inventory = observe_protocol_view_construction(values)
  assert_eq((inventory.views, inventory.modes), (1, 1L))
  assert_true(inventory.work > 0L)
  assert_true(
    inventory.work <= protocol_view_construction_inspection_bound(values),
  )
  let (result, work) = observe_source_view_shapes(values, {
    max_work: 100000,
    max_views: 10,
  })
  let shapes = result.unwrap()
  assert_true(physical_equal(source_view_shape_values(shapes), values))
  assert_eq(source_view_shape_usage(shapes), (work, 1))
  let (short, used) = observe_source_view_shapes(values, {
    max_work: work - 1,
    max_views: 10,
  })
  let original = check_source_view_shapes(values, {
    max_work: work - 1,
    max_views: 10,
  }).unwrap_err()
  assert_true(short is Err(issue) && issue.kind == original.kind)
  assert_true(used > 0 && used <= work - 1)
  let (result, work) = observe_source_read_modes(shapes, 100000)
  let modes = result.unwrap()
  assert_true(physical_equal(read_mode_shapes(modes), shapes))
  assert_eq(read_mode_usage(modes), (work, 1))
  let (short, used) = observe_source_read_modes(shapes, work - 1)
  assert_true(short is Err(issue) && issue.kind == WorkLimit)
  assert_true(used > 0 && used <= work - 1)
  let held = protocol_view_retained_extent(inventory)
  let peak = protocol_view_construction_extent(inventory)
  assert_true(held.record_headers <= peak.record_headers)
  assert_true(held.reference_slots <= peak.reference_slots)
  assert_eq((peak.owned_utf16_units, peak.owned_wire_bytes), (0L, 0L))
  let two = observe_protocol_view_construction(original_view_values(views=2))
  assert_eq((two.views, two.modes), (2, 2L))
  assert_true(
    two.mode_retained.record_headers > inventory.mode_retained.record_headers,
  )
  assert_eq(two.shape_scratch, inventory.shape_scratch)
  assert_eq(two.mode_scratch, inventory.mode_scratch)
}

///|
test "original semantic mode refusal preserves shape and exact diagnostic source with partial work" {
  let values = original_view_values(invalid_bounded=true)
  let shapes = check_source_view_shapes(values, {
    max_work: 100000,
    max_views: 10,
  }).unwrap()
  let expected = check_source_read_modes(shapes, 100000).unwrap_err()
  let (actual, work) = observe_source_read_modes(shapes, 100000)
  let actual = actual.unwrap_err()
  assert_eq(actual.kind, InvalidBoundedness(SnapshotMode))
  assert_eq(actual.kind, expected.kind)
  assert_eq(
    @decode.cursor_path(actual.source.unwrap()),
    @decode.cursor_path(expected.source.unwrap()),
  )
  assert_true(work > 0 && work < 100000)
  assert_true(physical_equal(source_view_shape_values(shapes), values))
  assert_true(
    observe_source_view_shapes(values, { max_work: -1, max_views: 1, }).0
    is Err(issue) &&
    issue.kind == InvalidLimits,
  )
  assert_true(
    observe_source_read_modes(shapes, -1).0 is Err(issue) &&
    issue.kind == InvalidLimits,
  )
}
