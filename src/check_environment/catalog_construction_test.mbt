///|
test "Catalog contents inventory follows original indexed members and actual embedded bodies" {
  let shared = envelope("null", null_contract_cid())
  let registry = catalog_environment([catalog_fixture("example", [shared])], [
    shared,
  ])
  let geometry = observe_catalog_construction_geometry(registry)
  assert_eq(geometry, {
    catalogs: 1,
    indexed_members: 1,
    body_nodes: 15,
    max_nodes: 15,
    max_fields: 7,
  })
  // Caller392H1023R915W and shared emitter/hash223H624R1044W.
  // Current indexed child and field carriers include both Option tags.
  // Actual used identity/outer hash String71 add142UTF16 beyond shared501.
  assert_eq(
    catalog_contents_construction_extent(geometry),
    Some({
      record_headers: 615L,
      reference_slots: 1647L,
      scalar_words: 1959L,
      owned_utf16_units: 643L,
      owned_wire_bytes: 148L,
    }),
  )
  let contents = check_catalog_contents(registry, caps()).unwrap()
  assert_true(physical_equal(catalog_registry(contents), registry))
  let selected = catalog_at(contents, 0).unwrap()
  assert_eq(catalog_identity(selected).0, "example")
  let reference = resolve_catalog_contract(
    selected,
    "example",
    "external-7",
    null_contract_cid(),
    "request_schema",
  ).unwrap()
  assert_true(
    physical_equal(
      member_environment(contract_member(reference)),
      contract_registry_environment(registry),
    ),
  )
}

///|
test "Catalog inventory retains real empty maps and repeated contract occurrences without multiplying hash workspace" {
  let empty = observe_catalog_construction_geometry(catalog_environment([], []))
  assert_eq(
    catalog_contents_construction_extent(empty),
    Some({
      record_headers: 72L,
      reference_slots: 206L,
      scalar_words: 201L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  let shared = envelope("null", null_contract_cid())
  let registry = catalog_environment(
    [catalog_fixture("first", [shared]), catalog_fixture("second", [shared])],
    [shared],
  )
  let geometry = observe_catalog_construction_geometry(registry)
  assert_eq(geometry.catalogs, 2)
  assert_eq(geometry.indexed_members, 1)
  assert_eq(geometry.body_nodes, 30)
  assert_eq(geometry.max_nodes, 15)
  let one = catalog_contents_construction_extent({
    ..geometry,
    catalogs: 1,
    body_nodes: 15,
  }).unwrap()
  let two = catalog_contents_construction_extent(geometry).unwrap()
  assert_true(two.record_headers > one.record_headers)
  assert_eq(two.owned_wire_bytes, one.owned_wire_bytes)
  assert_eq(two.owned_utf16_units, one.owned_utf16_units)
  assert_true(check_catalog_contents(registry, caps()) is Ok(_))
  assert_true(
    catalog_contents_construction_extent({
      catalogs: -1,
      indexed_members: 0,
      body_nodes: 0,
      max_nodes: 0,
      max_fields: 0,
    })
    is None,
  )
  assert_true(
    catalog_contents_construction_extent({
      catalogs: 1,
      indexed_members: 0,
      body_nodes: 0,
      max_nodes: 0,
      max_fields: 0,
    })
    is None,
  )
  assert_true(
    catalog_contents_construction_extent({
      catalogs: 2147483647,
      indexed_members: 2147483647,
      body_nodes: 2147483647,
      max_nodes: 2147483647,
      max_fields: 2147483647,
    })
    is Some(_),
  )
}

///|
test "shared wire emitter inventory and returned registry storage have independent boundaries" {
  assert_true(wire_hash_construction_extent(0) is None)
  assert_true(wire_hash_construction_extent(-1) is None)
  assert_eq(
    wire_hash_construction_extent(7),
    Some({
      record_headers: 135L,
      reference_slots: 328L,
      scalar_words: 764L,
      owned_utf16_units: 501L,
      owned_wire_bytes: 148L,
    }),
  )
  assert_eq(
    registry_retained_construction_extent(1),
    Some({
      record_headers: 18L,
      reference_slots: 58L,
      scalar_words: 40L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  assert_true(registry_retained_construction_extent(-1) is None)
}
