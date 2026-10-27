///|
test "Carrier inventory observes original occurrences and one sequential reader without reissuing schemas" {
  for kind in ["relation", "events", "vectors"] {
    let modes = carrier_modes(role_body(kind), kind)
    let observed = observe_protocol_carrier_construction(modes)
    assert_eq(observed.schemas, 1)
    assert_eq(observed.bindings, 1)
    assert_true(
      observed.work <= protocol_carrier_construction_inspection_bound(modes),
    )
    let peak = protocol_carrier_construction_extent(observed)
    let held = protocol_carrier_retained_extent(observed)
    assert_true(peak.record_headers > held.record_headers)
    assert_true(peak.reference_slots >= held.reference_slots)
    assert_true(held.owned_utf16_units >= 71L)
    let (result, bytes, nodes, work, entries) = observe_carrier_schemas(
      modes,
      carrier_limits(),
    )
    let original = result.unwrap()
    assert_eq(carrier_schema_usage(original), (bytes, nodes, work, entries))
    assert_true(physical_equal(carrier_schema_modes(original), modes))
  }
}

///|
test "unused Carrier declarations remain distinct while opaque facts extensions are not schema workspace" {
  let body = relation_presence_body()
  let one = carrier_modes(body, "relation")
  let two = carrier_modes(body, "relation", unused=Some(body))
  let a = observe_protocol_carrier_construction(one)
  let b = observe_protocol_carrier_construction(two)
  assert_eq((a.schemas, b.schemas), (1, 2))
  assert_true(b.retained.record_headers > a.retained.record_headers)
  let facts = @json.parse(
    "{\"opaque_extension\":\"" + "x".repeat(10000) + "\"}",
  )
  let more = carrier_modes(body, "relation", facts=Some(facts))
  let c = observe_protocol_carrier_construction(more)
  assert_eq(c.scratch.owned_utf16_units, a.scratch.owned_utf16_units)
  assert_true(c.work <= protocol_carrier_construction_inspection_bound(more))
  assert_true(check_carrier_schemas(more, carrier_limits()) is Ok(_))
}

///|
test "unknown Carrier version preserves the original body refusal before role validation" {
  let body = role_body("events")
  guard body is Object(fields) else { fail("original Event fixture") }
  fields["version"] = Json::string("unknown-carrier/0.1")
  let modes = carrier_modes(body, "events")
  let (result, _, _, _, entries) = observe_carrier_schemas(
    modes,
    carrier_limits(),
  )
  assert_eq(result.unwrap_err().kind, InvalidBody)
  assert_eq(entries, 0)
}
