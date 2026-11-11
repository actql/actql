///|
fn saved_effect_observed_fixture(
  wire : String,
  limits : @checkpoint.WireLimits,
) -> (@source.JsonSourcePreflight, @source.JsonSourceGeometry) raise {
  let preflight = @source.start_json_source_preflight(
    wire,
    {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    },
    data_keys=true,
  ).unwrap()
  while true {
    match @source.advance_json_source_preflight(preflight, 64).unwrap() {
      @source.JsonSourceContinue(..) => continue
      @source.JsonSourceReady(geometry, ..) => return (preflight, geometry)
      @source.JsonSourceFailed(_, ..) => fail("fixture preflight")
    }
  } nobreak {
    fail("fixture preflight terminal")
  }
}

///|
test "Native saved wire observed construction preserves DATA and consumes original parser once" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 64,
  }
  let wire = "{\"e\\u0301\":\"日😀\\n\",\"rows\":[1,null,true]}"
  let (preflight, geometry) = saved_effect_observed_fixture(wire, limits)
  defer @source.cancel_json_source_preflight(preflight)
  let (retained, peak, raw) = saved_effect_wire_construction(geometry).unwrap()
  assert_true(retained > 0L && peak >= retained && raw > 0L)
  let cursor = saved_effect_admit_preflight(preflight, limits).unwrap()
  let fields = @decode.closed_object(cursor, ["é", "rows"]).unwrap()
  assert_eq(
    @decode.text(@decode.lookup(fields, "é").unwrap()).unwrap(),
    "日😀\n",
  )
  assert_eq(
    @decode.elements(@decode.lookup(fields, "rows").unwrap()).unwrap().length(),
    3,
  )
  assert_true(saved_effect_admit_preflight(preflight, limits) is Err(_))
  // Large policy ceilings do not become a demand for this observed packet.
  assert_true(retained < 8388608L)
  assert_true(peak < 110100480L)
  assert_true(
    saved_effect_wire_construction({ ..geometry, fields: -1, }) is None,
  )
}

///|
test "Native saved wire same parser keeps duplicate and original limit refusals" {
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 64,
  }
  for
    (wire, selected) in [
      ("{\"x\":1,\"x\":2}", limits),
      ("[null]", { ..limits, max_nodes: 1, }),
      ("[[]]", { ..limits, max_depth: 1, }),
    ] {
    let (preflight, geometry) = saved_effect_observed_fixture(wire, selected)
    defer @source.cancel_json_source_preflight(preflight)
    assert_true(saved_effect_wire_construction(geometry) is Some(_))
    assert_true(saved_effect_admit_preflight(preflight, selected) is Err(_))
  }
}
