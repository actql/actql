///|
test "prepared publication constructor reaches local Source sizing with genuine captured originals" {
  for table in [false, true] {
    let chain = captured_run_test_chain()
    let captured = final_test_captured(chain, table~)
    let preview = final_test_preview(chain, plan=!table, table~)
    let prepared = prepare_recovered_captured_effect_run(
      captured,
      65536,
      4096,
      32,
      _ => true,
    ).unwrap()
    assert_true(
      physical_equal(prepared_captured_effect_run_contract(prepared), captured),
    )
    assert_true(
      validate_prepared_effectful_computation_evidence_chain(
        chain.run,
        chain.invocation,
        [chain.definition],
        [chain.artifact],
        chain.manifest,
        chain.receipt,
        captured,
        prepared,
        preview,
        65536,
        4096,
        32,
      )
      is Ok(_),
    )
    let (set_wire, members, _) = final_test_receipts(preview)
    let contracts = [captured, chain.receipt]
    let receipts = [set_wire, members[0]]
    let original_wire = publication_contract_json(captured)
    let original_cid = publication_contract_identity(captured)
    for issue in [false, true] {
      let legacy = effectful_publication_construction_inventory(
        issue, contracts, receipts, 65536, 4096, 32,
      ).unwrap()
      let spent = Ref(0)
      let sized = effectful_publication_construction_inventory(
        issue,
        contracts,
        receipts,
        65536,
        4096,
        32,
        prepared=Some(prepared),
        work=Some(units => {
          if units < 0 {
            false
          } else {
            spent.val += units
            true
          }
        }),
      ).unwrap()
      // A nonzero census and a different construction packet prove this
      // reaches the prepared class, rather than testing only its legacy None.
      assert_true(spent.val > 0)
      assert_true(sized.1 != legacy.1)
      assert_eq(sized.0, legacy.0)
      assert_true(sized.1.record_headers > 0L)
      assert_true(sized.1.reference_slots > 0L)
      assert_true(sized.1.scalar_words > 0L)
      assert_true(sized.1.owned_utf16_units > 0L)
      assert_true(sized.1.owned_wire_bytes > 0L)
      let declined = Ref(0)
      assert_eq(
        effectful_publication_construction_inventory(
          issue,
          contracts,
          receipts,
          65536,
          4096,
          32,
          prepared=Some(prepared),
          work=Some(_ => {
            declined.val += 1
            false
          }),
        ),
        None,
      )
      assert_eq(declined.val, 1)
      assert_eq(
        effectful_publication_construction_inventory(
          issue,
          contracts,
          receipts,
          0,
          4096,
          32,
          prepared=Some(prepared),
        ),
        None,
      )
    }
    assert_eq(publication_contract_json(captured), original_wire)
    assert_eq(publication_contract_identity(captured), original_cid)
  }
}

///|
test "prepared publication constructor does not reuse an equal-wire foreign captured original" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let prepared = prepare_recovered_captured_effect_run(
    captured,
    65536,
    4096,
    32,
    _ => true,
  ).unwrap()
  let foreign = admit_publication_contract(
    "captured_run",
    publication_contract_json(captured),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    publication_contract_identity(foreign),
    publication_contract_identity(captured),
  )
  assert_false(physical_equal(foreign, captured))
  let (set_wire, members, _) = final_test_receipts(final_test_preview(chain))
  for issue in [false, true] {
    let contracts = [foreign, chain.receipt]
    let receipts = [set_wire, members[0]]
    let legacy = effectful_publication_construction_inventory(
      issue, contracts, receipts, 65536, 4096, 32,
    ).unwrap()
    let calls = Ref(0)
    let sized = effectful_publication_construction_inventory(
      issue,
      contracts,
      receipts,
      65536,
      4096,
      32,
      prepared=Some(prepared),
      work=Some(_ => {
        calls.val += 1
        true
      }),
    ).unwrap()
    assert_eq(sized, legacy)
    assert_eq(calls.val, 0)
  }
}
