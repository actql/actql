///|
test "publication constructor covers actual final Receipt and escaped adoption outputs" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let preview = final_test_preview(chain)
  let source = final_test_source_artifact(chain)
  let (set_wire, members, _) = final_test_receipts(preview)
  let final_receipt = issue_effectful_final_run_receipt(
    chain.run,
    chain.receipt,
    captured,
    preview,
    set_wire,
    members,
    65536,
    4096,
    32,
  ).unwrap()
  let final_wire = publication_contract_json(final_receipt)
  let (computation_bytes, computation_nodes, computation_depth) = publication_contract_wire_usage(
    chain.receipt,
  ).unwrap()
  let (final_bytes, final_nodes, final_depth) = publication_contract_wire_usage(
    final_receipt,
  ).unwrap()
  // Three new ASCII field names, three 71-character CIDs, quotes, colons
  // and commas. Existing computation fields and container depth are unchanged.
  let extra_bytes = "captured_run_cid".length() +
    "effect_preview_cid".length() +
    "effect_set_apply_receipt_cid".length() +
    3 * (71 + 6)
  assert_eq(extra_bytes, 293)
  assert_eq(final_bytes, computation_bytes + extra_bytes)
  assert_eq(final_nodes, computation_nodes + 3)
  assert_eq(final_depth, computation_depth)
  assert_eq(@utf8.encode(final_wire).length(), final_bytes)
  assert_true(
    admit_effectful_final_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      preview,
      set_wire,
      members,
      final_wire,
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  let receipts = [set_wire, members[0]]
  let contracts = [captured, chain.receipt, chain.run, source]
  let captured_wire = publication_contract_json(captured)
  let computation_wire = publication_contract_json(chain.receipt)
  let (checked_retained, checked_workspace) = effectful_publication_construction_inventory(
    false, contracts, receipts, 65536, 4096, 32,
  ).unwrap()
  assert_eq(checked_retained, {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
  let (issued_retained, issued_workspace) = effectful_publication_construction_inventory(
    true, contracts, receipts, 65536, 4096, 32,
  ).unwrap()
  let set = admit_publication_contract(
    "effect_set_apply_receipt", set_wire, 65536, 4096, 32,
  ).unwrap()
  let member_receipt = admit_publication_contract(
    "effect_apply_receipt",
    members[0],
    65536,
    4096,
    32,
  ).unwrap()
  // Two Final/Set/member_receipt views and one Source view retain their Canonical
  // trees and UTF-16 wire/text. Temporary byte/parser/hash packets are not
  // multiplied by that escaped-output count: later adoption uses one MAX.
  let mut minimum_headers = 0L
  let mut minimum_references = 0L
  let mut minimum_text = 0L
  for
    (contract, copies) in [
      (final_receipt, 2L),
      (set, 2L),
      (member_receipt, 2L),
      (source, 1L),
    ] {
    let actual = publication_contract_representation_extent(
      contract, 4096, 32, 1000000,
    ).unwrap()
    minimum_headers += copies *
      (
        actual.contract_records +
        actual.canonical.objects +
        actual.canonical.arrays
      )
    minimum_references += copies *
      (
        actual.canonical.object_backing_slots +
        actual.canonical.array_backing_slots
      )
    minimum_text += copies *
      (
        publication_contract_json(contract).length().to_int64() +
        actual.canonical.text_utf16_units
      )
  }
  assert_true(issued_retained.record_headers >= minimum_headers)
  assert_true(issued_retained.reference_slots >= minimum_references)
  assert_true(issued_retained.owned_utf16_units >= minimum_text)
  assert_true(issued_retained.scalar_words > 0L)
  assert_true(checked_workspace.record_headers > 0L)
  assert_true(
    issued_workspace.record_headers >= checked_workspace.record_headers,
  )
  assert_true(
    issued_workspace.reference_slots >= checked_workspace.reference_slots,
  )
  assert_true(issued_workspace.scalar_words >= checked_workspace.scalar_words)
  assert_true(
    issued_workspace.owned_utf16_units >= checked_workspace.owned_utf16_units,
  )
  assert_true(
    issued_workspace.owned_wire_bytes >= checked_workspace.owned_wire_bytes,
  )
  assert_eq(publication_contract_json(captured), captured_wire)
  assert_eq(publication_contract_json(chain.receipt), computation_wire)
  assert_eq(receipts, [set_wire, members[0]])
}

///|
test "publication constructor accounts independently for member_receipt and Source adoption lifetimes" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let preview = final_test_preview(chain)
  let source = final_test_source_artifact(chain)
  let (set_wire, members, _) = final_test_receipts(preview)
  let contracts = [captured, chain.receipt]
  let (set_retained, set_workspace) = effectful_publication_construction_inventory(
    true,
    contracts,
    [set_wire],
    65536,
    4096,
    32,
  ).unwrap()
  let (member_retained, member_workspace) = effectful_publication_construction_inventory(
    true,
    contracts,
    [set_wire, members[0]],
    65536,
    4096,
    32,
  ).unwrap()
  let member_receipt = admit_publication_contract(
    "effect_apply_receipt",
    members[0],
    65536,
    4096,
    32,
  ).unwrap()
  let member_extent = publication_contract_representation_extent(
    member_receipt, 4096, 32, 1000000,
  ).unwrap()
  assert_true(
    member_retained.owned_utf16_units >=
    set_retained.owned_utf16_units +
    2L *
    (members[0].length().to_int64() + member_extent.canonical.text_utf16_units),
  )
  assert_true(member_retained.record_headers > set_retained.record_headers)
  assert_true(member_retained.reference_slots > set_retained.reference_slots)
  assert_true(
    member_workspace.owned_wire_bytes >= set_workspace.owned_wire_bytes,
  )
  let (source_retained, source_workspace) = effectful_publication_construction_inventory(
    true,
    [captured, chain.receipt, source],
    [set_wire, members[0]],
    65536,
    4096,
    32,
  ).unwrap()
  let source_extent = publication_contract_representation_extent(
    source, 4096, 32, 1000000,
  ).unwrap()
  assert_true(
    source_retained.owned_utf16_units >=
    member_retained.owned_utf16_units +
    publication_contract_json(source).length().to_int64() +
    source_extent.canonical.text_utf16_units,
  )
  assert_true(source_retained.record_headers > member_retained.record_headers)
  assert_true(source_retained.reference_slots > member_retained.reference_slots)
  assert_true(
    source_workspace.owned_wire_bytes >= member_workspace.owned_wire_bytes,
  )
  // A quote for only the Set is constructor DATA; it does not establish the
  // missing member_receipt closure that the actual final Receipt issuer requires.
  assert_true(
    issue_effectful_final_run_receipt(
      chain.run,
      chain.receipt,
      captured,
      preview,
      set_wire,
      [],
      65536,
      4096,
      32,
    )
    is Err(_),
  )
}

///|
test "publication constructor retains exact Receipt codec limits and original ordering" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let preview = final_test_preview(chain)
  let (set_wire, members, _) = final_test_receipts(preview)
  let set = admit_publication_contract(
    "effect_set_apply_receipt", set_wire, 65536, 4096, 32,
  ).unwrap()
  let member_receipt = admit_publication_contract(
    "effect_apply_receipt",
    members[0],
    65536,
    4096,
    32,
  ).unwrap()
  let set_bytes = @utf8.encode(set_wire).length()
  let member_bytes = @utf8.encode(members[0]).length()
  // Set: six root fields and a five-field member_receipt object in its Array.
  // Member: seven root fields, including the empty rows Array.
  assert_eq(publication_contract_wire_usage(set), Some((set_bytes, 13, 3)))
  assert_eq(
    publication_contract_wire_usage(member_receipt),
    Some((member_bytes, 8, 2)),
  )
  let bytes = Int::max(set_bytes, member_bytes)
  let contracts = [captured, chain.receipt]
  let receipts = [set_wire, members[0]]
  for issue in [false, true] {
    assert_true(
      effectful_publication_construction_inventory(
        issue, contracts, receipts, bytes, 13, 3,
      )
      is Some(_),
    )
    for
      (limit_bytes, nodes, depth) in [
        (bytes - 1, 13, 3),
        (bytes, 12, 3),
        (bytes, 13, 2),
        (0, 13, 3),
        (bytes, 0, 3),
        (bytes, 13, 0),
      ] {
      assert_true(
        effectful_publication_construction_inventory(
          issue, contracts, receipts, limit_bytes, nodes, depth,
        )
        is None,
      )
    }
    for malformed in ["", "\"unterminated"] {
      assert_true(
        effectful_publication_construction_inventory(
          issue,
          contracts,
          [malformed],
          65536,
          4096,
          32,
        )
        is None,
      )
    }
    for
      wrong in [
        [],
        [captured],
        [chain.receipt, captured],
        [chain.run, chain.receipt],
        [captured, chain.run],
      ] {
      assert_true(
        effectful_publication_construction_inventory(
          issue, wrong, receipts, 65536, 4096, 32,
        )
        is None,
      )
    }
    assert_true(
      effectful_publication_construction_inventory(
        issue,
        contracts,
        [],
        65536,
        4096,
        32,
      )
      is None,
    )
  }
}
