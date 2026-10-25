///|
test "closed Values empty normalization has fixed original tree and wire extent" {
  let body = "{\"entries\":[],\"rule_catalog_cid\":\"sha256:f93d91b468d850cbc63a8c8350578af8431a2256eb2b1ef3f60586fdc640561d\",\"version\":\"actql-normalization-journal/0.1\"}"
  assert_eq(body.length(), 151)
  let evidence = seal_run_evidence_value(
    "normalization_journal", body, 1024, 32, 8,
  ).unwrap()
  assert_eq(
    evidence.identity,
    "sha256:e245b445e5014e5764dab4bf1b9ddc3b3abdf821ddf75950f9bee9df29007164",
  )
  assert_eq(evidence.wire.length(), 239)
  let extent = @json.representation_extent(evidence.value, 5, 2, 214).unwrap()
  let layout = empty_normalization_journal_retained_layout()
  assert_eq(layout.body_wire_units, body.length().to_int64())
  assert_eq(layout.sealed_wire_units, evidence.wire.length().to_int64())
  assert_eq(
    layout.owned_utf16_units,
    extent.text_utf16_units - 11L + evidence.wire.length().to_int64(),
  )
  assert_eq(layout.record_headers, 23L)
  assert_eq(layout.scalar_words, 9L)
  assert_true(
    layout.reference_slots >=
    21L + extent.array_backing_slots + extent.object_backing_slots,
  )

  assert_eq(extent.nodes, 5L)
  assert_eq(extent.strings, 7L)
  assert_eq(extent.text_utf16_units, 214L)
  assert_eq(extent.arrays, 1L)
  assert_eq(extent.objects, 1L)
  assert_eq(extent.array_backing_slots, 0L)
  // Copy three fields, append one: JS reports four live slots; the portable
  // growable backing ceiling retains six. This is a bound, not an RSS claim.
  assert_true(extent.object_backing_slots <= 6L)
  assert_true(@json.representation_extent(evidence.value, 4, 2, 214) is Err(_))
  assert_true(@json.representation_extent(evidence.value, 5, 2, 213) is Err(_))
  // The CID string is one owner shared by the evidence and canonical tree.
  guard @json.object_field(evidence.value, "journal_cid")
    is Some(@json.String(identity)) else {
    fail("missing identity")
  }
  assert_true(physical_equal(identity, evidence.identity))
}

///|
test "closed Values normalization schema validation has two-frame frontier" {
  let body = "{\"entries\":[],\"rule_catalog_cid\":\"sha256:f93d91b468d850cbc63a8c8350578af8431a2256eb2b1ef3f60586fdc640561d\",\"version\":\"actql-normalization-journal/0.1\"}"
  let evidence = seal_run_evidence_value(
    "normalization_journal", body, 1024, 32, 8,
  ).unwrap()
  let before = parse_contract_wire(body, 1024, 32, 8).unwrap()
  let layout = empty_normalization_validation_layout()
  let nodes = protocol_schema_nodes()
  assert_true(physical_equal(nodes, protocol_schema_nodes()))
  for complete in [false, true] {
    let root = generated_protocol_schema_root("normalization_journal", complete).unwrap()
    guard nodes[root] is ObjectRule(properties, _, -1, 0, None, 0) else {
      fail("changed normalization object schema")
    }
    assert_eq(properties.length(), if complete { 4 } else { 3 })
    for (name, child) in properties {
      if name == "entries" {
        guard nodes[child] is ArrayRule(_, 0, false, -1) else {
          fail("changed empty entries schema")
        }
      } else {
        guard nodes[child] is StringRule(_, _, _, _) else {
          fail("changed normalization scalar schema")
        }
      }
    }
    let cursor = start_protocol_validation(
      if complete {
        evidence.value
      } else {
        before
      },
      root,
      nodes,
      { remaining: 256, max_wire_bytes: 1024, max_nodes: 32, max_depth: 8, },
    )
    let mut peak = cursor.pending.length()
    while !cursor.pending.is_empty() {
      cursor.step()
      peak = Int::max(peak, cursor.pending.length())
    }
    assert_true(cursor.result)
    assert_eq(peak, layout.pending_frames_upper)
    cursor.cancel()
    assert_true(cursor.pending.is_empty())
  }
}
