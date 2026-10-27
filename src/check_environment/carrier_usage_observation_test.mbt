///|
test "Carrier observation keeps original successful counters and first typed byte and work refusals" {
  let modes = carrier_modes(relation_presence_body(), "relation")
  let limits = carrier_limits()
  let original = check_carrier_schemas(modes, limits).unwrap()
  let (observed, bytes, nodes, work, entries) = observe_carrier_schemas(
    modes, limits,
  )
  assert_true(observed is Ok(_))
  assert_eq((bytes, nodes, work, entries), carrier_schema_usage(original))
  for short_bytes in [false, true] {
    let tighter = if short_bytes {
      { ..limits, bodies: { ..limits.bodies, max_bytes: bytes - 1, }, }
    } else {
      { ..limits, max_work: work - 1, }
    }
    let expected = check_carrier_schemas(modes, tighter).unwrap_err()
    let (result, b, n, w, e) = observe_carrier_schemas(modes, tighter)
    let actual = result.unwrap_err()
    assert_eq(actual.kind, expected.kind)
    assert_eq(actual.kind, if short_bytes { BudgetExceeded } else { WorkLimit })
    assert_true(actual.source is Some(_) && expected.source is Some(_))
    assert_true(b >= 0 && b <= tighter.bodies.max_bytes)
    assert_true(n >= 0 && n <= tighter.bodies.max_nodes)
    assert_true(w > 0 && w <= tighter.max_work)
    assert_true(e >= 0 && e <= tighter.max_schemas)
  }
}

///|
test "Carrier typed invalid body retains the original successful prefix without issuing a partial schema" {
  let body = @json.parse(
    "{\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"p\":{\"nullable\":false,\"type\":\"not-a-type\"}},\"version\":\"actql-relation-schema/0.1\"}",
  )
  let modes = carrier_modes(body, "relation")
  let expected = check_carrier_schemas(modes, carrier_limits()).unwrap_err()
  let (result, bytes, nodes, work, entries) = observe_carrier_schemas(
    modes,
    carrier_limits(),
  )
  assert_eq(result.unwrap_err().kind, expected.kind)
  assert_true(expected.kind is InvalidType(_))
  assert_true(bytes > 0 && nodes > 0 && work > 0)
  assert_eq(entries, 0)
}
