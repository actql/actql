///|
test "Source request quantities preserve repeated view roles and shared facts" {
  let carriers = request_carriers(
    record_body(),
    record_body(),
    Some(correlation_fixture()),
    view_count=2,
  )
  let g = observe_source_request_construction_geometry(carriers)
  assert_eq((g.views, g.request_references, g.correlated_views), (2, 2, 2))
  assert_eq((g.pairs, g.identity_roles), (4L, 4L))
  assert_eq((g.batching_views, g.listing_views, g.content_views), (0, 0, 0))
  assert_eq(g.distinct_facts, 1)
  assert_true(g.inspection_work > 0L && g.diagnostic_path_segments > 0)
}

///|
test "Source request quantities retain actual listing and Content declarations" {
  let listing = observe_source_request_construction_geometry(
    file_listing_fixture_carriers(Some(file_listing_fixture_profile())),
  )
  assert_eq(
    (listing.views, listing.listing_views, listing.content_views),
    (1, 1, 0),
  )
  assert_eq(listing.listing_limits, 3L)
  let content = observe_source_request_construction_geometry(
    content_fixture_carriers(),
  )
  assert_eq(
    (content.views, content.listing_views, content.content_views),
    (1, 0, 1),
  )
  assert_eq((content.pairs, content.identity_roles), (2L, 2L))
  assert_eq(content.listing_limits, 0L)
  assert_true(content.max_view_map_fields > 0L)
}

///|
test "Source request owned extents use independent repeated-role and empty-view vectors" {
  let g = observe_source_request_construction_geometry(
    request_carriers(
      record_body(),
      record_body(),
      Some(correlation_fixture()),
      view_count=2,
    ),
  )
  // Two view/schema wrappers, four pairs/twelve role+Cursor owners, two
  // Correlation records, five growable arrays and one by-view alias Map.
  assert_eq(source_request_retained_construction_extent(g).unwrap(), {
    record_headers: 72L,
    reference_slots: 233L,
    scalar_words: 92L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
  let whole = source_request_construction_extent(g).unwrap()
  assert_true(whole.record_headers > 72L && whole.reference_slots > 233L)
  assert_eq((whole.owned_utf16_units, whole.owned_wire_bytes), (0L, 0L))
  assert_true(source_request_construction_extent({ ..g, pairs: -1L, }) is None)
  assert_true(
    source_request_construction_extent({ ..g, pairs: 9223372036854775807L, })
    is None,
  )
  let empty : SourceRequestConstructionGeometry = {
    views: 0,
    request_references: 0,
    correlated_views: 0,
    pairs: 0L,
    identity_roles: 0L,
    batching_views: 0,
    listing_views: 0,
    listing_limits: 0L,
    content_views: 0,
    max_view_map_fields: 0L,
    distinct_facts: 0,
    diagnostic_path_segments: 2147483647,
    inspection_work: 0L,
  }
  // No view can invoke a decoder/path or file-profile constructor. A deep
  // unrelated input must not turn those absent roles into a huge reservation.
  assert_eq(source_request_construction_extent(empty).unwrap(), {
    record_headers: 33L,
    reference_slots: 87L,
    scalar_words: 63L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
test "Content request quantity includes the original nested lookup live scalar packet" {
  let g = observe_source_request_construction_geometry(
    content_fixture_carriers(),
  )
  let content = source_request_construction_extent(g).unwrap()
  let without = source_request_construction_extent({ ..g, content_views: 0, }).unwrap()
  // One retained Content/Some/Cursor3H8R1W plus the nested interpreter's
  // original budget, four scalar options and result6H1R13W. All same outer
  // cursor/Map/path quantities stay fixed; this is DATA inventory, not a
  // substituted accepted Catalog or physical allocation measurement.
  assert_eq(content.record_headers - without.record_headers, 9L)
  assert_eq(content.reference_slots - without.reference_slots, 9L)
  assert_eq(content.scalar_words - without.scalar_words, 14L)
}
