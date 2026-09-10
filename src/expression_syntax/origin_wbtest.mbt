///|
test "comb origins and shared reference records grow linearly" {
  for n in [128, 256, 512, 1024] {
    let text = "{\"add\":[{\"field\":\"x\"},".repeat(n) +
      "{\"literal\":0}" +
      "]}".repeat(n)
    let e = admit(source_cursor(text), test_limits()).unwrap()
    assert_eq(origin_count(e), 4 * n + 2)
    assert_true(@map.peak_frames(e.origins) <= 4 * n + 3)
    assert_eq(e.relation_references.length(), n)
    assert_eq(e.field_indices.length(), n)
    assert_eq(e.references.length(), 0)
    // Every occurrence retains one shared Cursor, not a root-to-leaf array.
    let deepest = relation_reference_at(e, n - 1).unwrap()
    let path = location_path(deepest.location)
    assert_eq(path.length(), 2 * n)
    for i in 0..<n {
      assert_eq(path[2 * i], @source.Key("add"))
      assert_eq(path[2 * i + 1], @source.Index(if i == n - 1 { 0 } else { 1 }))
    }
    path.clear()
    assert_eq(location_path(deepest.location).length(), 2 * n)
    let detached = relation_references(e)
    detached.clear()
    assert_eq(relation_reference_count(e), n)
    assert_true(relation_reference_at(e, -1) is None)
    assert_true(relation_reference_at(e, n) is None)
    assert_true(origin(e, source_cursor("0")) is None)
  }
}
