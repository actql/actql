///|
test "a halted member does not suppress independent Effect Set work" {
  let members : Array[EffectMemberProgress] = [
    {
      effect_id: "first",
      policy: HaltMember,
      rows: [ItemApplied, ItemFailed, ItemUnattempted],
    },
    {
      effect_id: "second",
      policy: HaltMember,
      rows: [ItemAccepted, ItemUnattempted],
    },
  ]
  let frontier = effect_set_frontier(members, 2, 5, 16).unwrap()
  assert_eq(frontier.outcome, SetRunning)
  assert_eq(frontier.ready.length(), 1)
  assert_eq(frontier.ready[0].0, 1)
  assert_eq(frontier.ready[0].1, 1)
  members[1].rows[1] = ItemApplied
  let settled = effect_set_frontier(members, 2, 5, 16).unwrap()
  assert_eq(settled.ready.length(), 0)
  assert_eq(settled.outcome, SetFailed)
}

///|
test "continue advances beyond unknown without resending it" {
  let members : Array[EffectMemberProgress] = [
    {
      effect_id: "first",
      policy: ContinueMember,
      rows: [ItemApplied, ItemUnknown, ItemUnattempted],
    },
    { effect_id: "second", policy: HaltMember, rows: [ItemUnattempted], },
  ]
  let frontier = effect_set_frontier(members, 2, 4, 16).unwrap()
  assert_eq(frontier.ready.length(), 2)
  assert_eq(frontier.ready[0].0, 0)
  assert_eq(frontier.ready[0].1, 2)
  assert_eq(frontier.ready[1].0, 1)
  assert_eq(frontier.ready[1].1, 0)
  members[0].rows[2] = ItemAccepted
  members[1].rows[0] = ItemApplied
  let settled = effect_set_frontier(members, 2, 4, 16).unwrap()
  assert_eq(settled.outcome, SetNeedsReconciliation)
  assert_eq(settled.ready.length(), 0)
}

///|
test "in-flight row blocks only its own member" {
  let members : Array[EffectMemberProgress] = [
    {
      effect_id: "first",
      policy: ContinueMember,
      rows: [ItemSending, ItemUnattempted],
    },
    { effect_id: "second", policy: ContinueMember, rows: [ItemUnattempted], },
  ]
  let frontier = effect_set_frontier(members, 2, 3, 16).unwrap()
  assert_eq(frontier.ready.length(), 1)
  assert_eq(frontier.ready[0].0, 1)
  assert_eq(frontier.outcome, SetRunning)
}

///|
test "an in-flight row cannot coexist with a later attempted row" {
  for later in [ItemSending, ItemApplied, ItemAccepted, ItemFailed, ItemUnknown] {
    for policy in [HaltMember, ContinueMember] {
      let members : Array[EffectMemberProgress] = [
        { effect_id: "first", policy, rows: [ItemSending, later], },
      ]
      assert_true(effect_set_frontier(members, 1, 2, 8) is Err(InvalidHistory))
    }
  }
  let valid : Array[EffectMemberProgress] = [
    {
      effect_id: "first",
      policy: ContinueMember,
      rows: [ItemUnknown, ItemSending, ItemUnattempted],
    },
  ]
  let frontier = effect_set_frontier(valid, 1, 3, 8).unwrap()
  assert_eq(frontier.ready.length(), 0)
  assert_eq(frontier.outcome, SetRunning)
}

///|
test "Effect Set frontier does not turn authored member order into dispatch order" {
  let members : Array[EffectMemberProgress] = [
    { effect_id: "zeta", policy: HaltMember, rows: [ItemUnattempted], },
    { effect_id: "alpha", policy: HaltMember, rows: [ItemUnattempted], },
  ]
  let frontier = effect_set_frontier(members, 2, 2, 12).unwrap()
  assert_eq(frontier.ready.length(), 2)
  assert_eq(frontier.ready[0].0, 1)
  assert_eq(frontier.ready[1].0, 0)
}

///|
test "Effect Set progress refuses invalid histories and uncharged scans" {
  let duplicate : Array[EffectMemberProgress] = [
    { effect_id: "same", policy: HaltMember, rows: [], },
    { effect_id: "same", policy: HaltMember, rows: [], },
  ]
  assert_true(effect_set_frontier(duplicate, 2, 0, 4) is Err(InvalidMember))
  let skipped : Array[EffectMemberProgress] = [
    {
      effect_id: "first",
      policy: HaltMember,
      rows: [ItemUnattempted, ItemApplied],
    },
  ]
  assert_true(effect_set_frontier(skipped, 1, 2, 4) is Err(InvalidHistory))
  assert_true(effect_set_frontier(skipped, 1, 1, 4) is Err(CapacityExceeded))
  assert_true(effect_set_frontier(skipped, 1, 2, 1) is Err(CapacityExceeded))
  let complete : Array[EffectMemberProgress] = [
    { effect_id: "first", policy: HaltMember, rows: [ItemApplied], },
    { effect_id: "second", policy: HaltMember, rows: [ItemAccepted], },
  ]
  assert_eq(
    effect_set_frontier(complete, 2, 2, 5).unwrap().outcome,
    SetSucceeded,
  )
}

///|
test "durable ledger heads own Effect Set progress after restart" {
  let scope = prepare_logical_request_scope(
    ledger_test_cid("a"),
    "request-1",
    32,
  ).unwrap()
  let preview = ledger_test_cid("b")
  let make_basis = (effect_id : String, row : String) => {
    let key = prepare_effect_dispatch_key(
      scope,
      preview,
      "\"" + row + "\"",
      32,
      8,
      3,
    ).unwrap()
    let locator = prepare_logical_item_locator(
      scope,
      "program-1",
      "node-1",
      effect_id,
      "{\"row\":\"" + row + "\"}",
      64,
      128,
      8,
      3,
    ).unwrap()
    let basis = prepare_effect_ledger_basis(
      scope,
      locator,
      key,
      ledger_test_cid("c"),
      ledger_test_cid("d"),
      ledger_test_cid("e"),
      ledger_test_cid("f"),
      ledger_test_cid("0"),
      "unavailable",
      ledger_test_cid("1"),
      ledger_test_cid("2"),
    ).unwrap()
    (locator, basis)
  }
  let (first_locator, first) = make_basis("first", "row-1")
  let (second_locator, second) = make_basis("first", "row-2")
  let (third_locator, third) = make_basis("second", "row-3")
  let prepared = issue_prepared_effect_ledger_entry(first, 4096, 64, 3).unwrap()
  let sending = issue_next_effect_ledger_entry(
    prepared,
    "dispatching",
    None,
    4096,
    64,
    3,
  ).unwrap()
  let pending = effect_set_frontier_from_ledger_entries(
    ["first", "second"],
    [0, 1],
    [[first_locator, second_locator], [third_locator]],
    [[first, second], [third]],
    [[Some(sending), None], [None]],
    2,
    3,
    24,
  ).unwrap()
  assert_eq(pending.outcome, SetRunning)
  assert_eq(pending.ready, [(1, 0)])
  let unknown = issue_next_effect_ledger_entry(
    sending,
    "unknown",
    None,
    4096,
    64,
    3,
  ).unwrap()
  let halted = effect_set_frontier_from_ledger_entries(
    ["first", "second"],
    [0, 1],
    [[first_locator, second_locator], [third_locator]],
    [[first, second], [third]],
    [[Some(unknown), None], [None]],
    2,
    3,
    24,
  ).unwrap()
  assert_eq(halted.ready, [(1, 0)])
  let continued = effect_set_frontier_from_ledger_entries(
    ["first", "second"],
    [1, 1],
    [[first_locator, second_locator], [third_locator]],
    [[first, second], [third]],
    [[Some(unknown), None], [None]],
    2,
    3,
    24,
  ).unwrap()
  assert_eq(continued.ready, [(0, 1), (1, 0)])
  assert_true(
    effect_set_frontier_from_ledger_entries(
      ["first", "second"],
      [1, 1],
      [[first_locator, second_locator], [third_locator]],
      [[first, second], [third]],
      [[Some(unknown), None], [Some(sending)]],
      2,
      3,
      24,
    )
    is Err(ForeignLedgerEntry(1, 0)),
  )
  assert_true(
    effect_set_frontier_from_ledger_entries(
      ["foreign", "second"],
      [1, 1],
      [[first_locator, second_locator], [third_locator]],
      [[first, second], [third]],
      [[Some(unknown), None], [None]],
      2,
      3,
      24,
    )
    is Err(ForeignLedgerEntry(0, 0)),
  )
}

///|
test "admitted Preview fixes durable frontier member and row identity" {
  let a = ledger_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let scope = prepare_logical_request_scope(a, "request-1", 32).unwrap()
  let (wire, key) = preview_apply_test_wire(scope, "halt")
  let preview = admit_effect_preview_apply_identity(
    wire,
    a,
    authoring,
    scope,
    [[key]],
    8192,
    256,
    12,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "write", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  let basis = prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    ledger_test_cid("c"),
    ledger_test_cid("d"),
    ledger_test_cid("e"),
    ledger_test_cid("f"),
    ledger_test_cid("0"),
    "unavailable",
    ledger_test_cid("1"),
    ledger_test_cid("2"),
  ).unwrap()
  let frontier = effect_set_frontier_from_preview_ledger_entries(
    preview,
    [[scope]],
    [[locator]],
    [[key]],
    [[basis]],
    [[None]],
    1,
    1,
    12,
  ).unwrap()
  assert_eq(frontier.ready, [(0, 0)])
  let foreign = prepare_logical_item_locator(
    scope, "program-1", "node-1", "foreign", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  assert_true(
    effect_set_frontier_from_preview_ledger_entries(
      preview,
      [[scope]],
      [[foreign]],
      [[key]],
      [[basis]],
      [[None]],
      1,
      1,
      12,
    )
    is Err(ForeignPreviewRow(0, 0)),
  )
  assert_true(
    effect_set_frontier_from_preview_ledger_entries(
      preview,
      [[scope]],
      [[locator]],
      [[key]],
      [[basis]],
      [[None]],
      1,
      1,
      2,
    )
    is Err(CapacityExceeded),
  )
}
