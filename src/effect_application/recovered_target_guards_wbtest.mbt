///|
test "recovered guards require exact durable rows and retain initial preflight" {
  let a = ledger_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let scope = prepare_logical_request_scope(a, "request-1", 32).unwrap()
  let (wire, key) = preview_apply_test_wire(scope, "halt")
  let admit_preview = fn() {
    admit_effect_preview_apply_identity(
      wire,
      a,
      authoring,
      scope,
      [[key]],
      8192,
      256,
      12,
    ).unwrap()
  }
  let preview = admit_preview()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "write", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  let make_basis = fn(request_cid) {
    prepare_effect_ledger_basis(
      scope,
      locator,
      key,
      request_cid,
      ledger_test_cid("d"),
      ledger_test_cid("e"),
      ledger_test_cid("f"),
      ledger_test_cid("0"),
      "unavailable",
      ledger_test_cid("1"),
      ledger_test_cid("2"),
    ).unwrap()
  }
  let basis = make_basis(ledger_test_cid("c"))
  let recover = fn(head) {
    recover_effect_target_guards(
      preview,
      [[scope]],
      [[locator]],
      [[key]],
      [[basis]],
      [[head]],
      [[false]],
      1,
      1,
      32,
    )
  }
  let prepared = issue_prepared_effect_ledger_entry(basis, 4096, 64, 3).unwrap()
  let sending = issue_next_effect_ledger_entry(
    prepared,
    "dispatching",
    None,
    4096,
    64,
    3,
  ).unwrap()
  let applied = issue_next_effect_ledger_entry(
    sending,
    "applied",
    Some(ledger_test_cid("8")),
    4096,
    64,
    3,
  ).unwrap()
  let unknown = issue_next_effect_ledger_entry(
    sending,
    "unknown",
    None,
    4096,
    64,
    3,
  ).unwrap()
  let changed = EffectTargetVersionObservation::{
    row_preview_cid: @publication.effect_preview_row_identity(preview, 0, 0).unwrap(),
    version_cid: ledger_test_cid("b"),
  }
  assert_true(
    check_effect_preview_target_guards(preview, [changed], 1, 2)
    is Err(StalePreview(0, 0)),
  )
  let unsent = recover(Some(prepared)).unwrap()
  assert_true(
    check_recovered_effect_target_guards(
      preview,
      scope,
      unsent,
      [changed],
      1,
      2,
    )
    is Err(StalePreview(0, 0)),
  )
  assert_true(
    check_recovered_effect_target_guards(preview, scope, unsent, [], 1, 2)
    is Err(MissingObservation(0, 0)),
  )
  for head in [applied, unknown, sending] {
    let recovered = recover(Some(head)).unwrap()
    assert_true(
      check_recovered_effect_target_guards(
        preview,
        scope,
        recovered,
        [changed],
        1,
        2,
      )
      is Ok(_),
    )
    // A guard waiver is not a send permit, including uncertain sends.
    let frontier = effect_set_frontier_from_preview_ledger_entries(
      preview,
      [[scope]],
      [[locator]],
      [[key]],
      [[basis]],
      [[Some(head)]],
      [[false]],
      1,
      1,
      32,
    ).unwrap()
    assert_eq(frontier.ready, [])
    assert_true(
      check_recovered_effect_target_guards(
        admit_preview(),
        scope,
        recovered,
        [],
        1,
        2,
      )
      is Err(ForeignRecoveryEvidence),
    )
    let foreign_scope = prepare_logical_request_scope(a, "request-2", 32).unwrap()
    assert_true(
      check_recovered_effect_target_guards(
        preview,
        foreign_scope,
        recovered,
        [],
        1,
        2,
      )
      is Err(ForeignRecoveryEvidence),
    )
  }
  assert_true(recover(None) is Err(ForeignLedgerEntry(0, 0)))
  let foreign_head = issue_prepared_effect_ledger_entry(
    make_basis(ledger_test_cid("9")),
    4096,
    64,
    3,
  ).unwrap()
  assert_true(recover(Some(foreign_head)) is Err(ForeignLedgerEntry(0, 0)))
}
