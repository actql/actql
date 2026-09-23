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
