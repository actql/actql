///|
test "registry construction geometry reuses original member metadata and independent null envelope vector" {
  let wire = registry_wire([envelope("null", null_contract_cid())])
  let geometry = observe_registry_construction_geometry(wire)
  assert_eq(geometry, { members: 1, max_nodes: 7, max_fields: 6, })
  // Caller117H301R193W; shared emitter+hash135H328R764W;
  // hash-owned359UTF16 plus two actual self-CID71;148owned wire bytes.
  assert_eq(
    registry_construction_extent(geometry),
    Some({
      record_headers: 252L,
      reference_slots: 629L,
      scalar_words: 957L,
      owned_utf16_units: 501L,
      owned_wire_bytes: 148L,
    }),
  )
  let registry = check_contract_registry(wire, caps()).unwrap()
  assert_true(physical_equal(contract_registry_environment(registry), wire))
  assert_eq(contract_registry_usage(registry).2, 1)
  assert_eq(contract_body_node_count(contract_at(registry, 0).unwrap()), 1)
  let empty = observe_registry_construction_geometry(registry_wire([]))
  assert_eq(
    registry_construction_extent(empty),
    Some({
      record_headers: 11L,
      reference_slots: 34L,
      scalar_words: 25L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  )
  assert_true(
    registry_construction_extent({ members: -1, max_nodes: 0, max_fields: 0, })
    is None,
  )
  assert_true(
    registry_construction_extent({ members: 1, max_nodes: 1, max_fields: 2, })
    is None,
  )
}

///|
test "registry geometry keeps wide invalid envelope key path and largest finite counts" {
  let body = "[".repeat(20) + "null" + "]".repeat(20)
  let identity = "sha256:" +
    @sha.hex(
      @utf8.encode(
        "{\"body\":" +
        body +
        ",\"id\":\"example\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"external-7\"}",
      ),
    )
  let wire = registry_wire([envelope(body, identity)])
  let geometry = observe_registry_construction_geometry(wire)
  assert_eq(geometry.max_nodes, 27)
  assert_true(check_contract_registry(wire, caps()) is Ok(_))
  let invalid = envelope("null", null_contract_cid()).replace(
    old="{",
    new="{\"a\":0,\"aa\":0,\"ab\":0,",
  )
  let invalid_wire = registry_wire([invalid])
  let invalid_geometry = observe_registry_construction_geometry(invalid_wire)
  assert_eq(invalid_geometry, { members: 1, max_nodes: 10, max_fields: 9, })
  assert_true(
    check_contract_registry(invalid_wire, caps()) is Err(InvalidEnvelope(0)),
  )
  let wide = registry_construction_extent({
    members: 1,
    max_nodes: 40,
    max_fields: 9,
  }).unwrap()
  let narrow = registry_construction_extent({
    members: 1,
    max_nodes: 40,
    max_fields: 6,
  }).unwrap()
  assert_true(wide.record_headers > narrow.record_headers)
  assert_true(wide.reference_slots > narrow.reference_slots)
  assert_true(
    registry_construction_extent({
      members: 2147483647,
      max_nodes: 2147483647,
      max_fields: 2147483647,
    })
    is Some(_),
  )
}
