///|
pub(all) enum EffectItemProgress {
  ItemUnattempted
  ItemSending
  ItemApplied
  ItemAccepted
  ItemFailed
  ItemUnknown
} derive(Eq, Debug)

///|
pub(all) enum EffectItemFailurePolicy {
  HaltMember
  ContinueMember
} derive(Eq, Debug)

///|
pub(all) struct EffectMemberProgress {
  effect_id : String
  policy : EffectItemFailurePolicy
  rows : Array[EffectItemProgress]
}

///|
pub(all) enum EffectSetOutcome {
  SetRunning
  SetSucceeded
  SetFailed
  SetNeedsReconciliation
} derive(Eq, Debug)

///|
pub(all) enum EffectSetProgressIssue {
  InvalidLimits
  InvalidMember
  CapacityExceeded
  InvalidHistory
  ForeignLedgerEntry(Int, Int)
} derive(Eq, Debug)

///|
pub(all) struct EffectSetFrontier {
  ready : Array[(Int, Int)]
  outcome : EffectSetOutcome
}

///|
/// This is progress over already admitted and durably recorded members, not
/// permission to send. Every member is independent; halt affects only rows of
/// that member. An unsettled physical request prevents a new row of its member
/// from starting, but it does not suppress another member in the Effect Set.
pub fn effect_set_frontier(
  members : Array[EffectMemberProgress],
  max_members : Int,
  max_rows : Int,
  max_work : Int,
) -> Result[EffectSetFrontier, EffectSetProgressIssue] {
  if max_members < 1 ||
    max_members > 1000 ||
    max_rows < 0 ||
    max_work < 1 ||
    members.length() > max_members {
    return Err(InvalidLimits)
  }
  let ready : Array[(Int, Int)] = []
  let mut work = 0
  let mut rows = 0
  let mut any_sending = false
  let mut any_unknown = false
  let mut any_failed = false
  for member_index in 0..<members.length() {
    work += 1
    if work > max_work {
      return Err(CapacityExceeded)
    }
    let current = members[member_index]
    if current.effect_id.is_empty() {
      return Err(InvalidMember)
    }
    for prior in 0..<member_index {
      work += 1
      if work > max_work {
        return Err(CapacityExceeded)
      }
      if members[prior].effect_id == current.effect_id {
        return Err(InvalidMember)
      }
    }
    let mut blocked = false
    let mut sending = false
    let mut next = -1
    for row_index in 0..<current.rows.length() {
      work += 1
      rows += 1
      if work > max_work || rows > max_rows {
        return Err(CapacityExceeded)
      }
      match current.rows[row_index] {
        ItemUnattempted => if next < 0 { next = row_index }
        ItemSending => {
          if next >= 0 || sending || (current.policy is HaltMember && blocked) {
            return Err(InvalidHistory)
          }
          sending = true
          any_sending = true
        }
        ItemApplied | ItemAccepted =>
          if next >= 0 || sending || (current.policy is HaltMember && blocked) {
            return Err(InvalidHistory)
          }
        ItemFailed => {
          if next >= 0 || sending || (current.policy is HaltMember && blocked) {
            return Err(InvalidHistory)
          }
          any_failed = true
          if current.policy is HaltMember {
            blocked = true
          }
        }
        ItemUnknown => {
          if next >= 0 || sending || (current.policy is HaltMember && blocked) {
            return Err(InvalidHistory)
          }
          any_unknown = true
          if current.policy is HaltMember {
            blocked = true
          }
        }
      }
    }
    if !sending && !blocked && next >= 0 {
      ready.push((member_index, next))
    }
  }
  let sort_work = ready.length() * ready.length()
  if sort_work > max_work - work {
    return Err(CapacityExceeded)
  }
  ready.sort_by((left, right) => {
    @canonical.compare_utf16(
      members[left.0].effect_id,
      members[right.0].effect_id,
    )
  })
  let outcome = if any_sending || !ready.is_empty() {
    SetRunning
  } else if any_unknown {
    SetNeedsReconciliation
  } else if any_failed {
    SetFailed
  } else {
    SetSucceeded
  }
  Ok({ ready, outcome, })
}

///|
pub fn effect_set_frontier_from_codes(
  effect_ids : Array[String],
  policies : Array[Int],
  row_states : Array[Array[Int]],
  max_members : Int,
  max_rows : Int,
  max_work : Int,
) -> Result[EffectSetFrontier, EffectSetProgressIssue] {
  if max_members < 1 ||
    max_rows < 0 ||
    max_work < 1 ||
    effect_ids.length() != policies.length() ||
    effect_ids.length() != row_states.length() ||
    effect_ids.length() > max_members {
    return Err(InvalidLimits)
  }
  let mut used = 0
  let mut total_rows = 0
  let members : Array[EffectMemberProgress] = []
  for index in 0..<effect_ids.length() {
    used += 1
    if used >= max_work {
      return Err(CapacityExceeded)
    }
    let policy = match policies[index] {
      0 => HaltMember
      1 => ContinueMember
      _ => return Err(InvalidMember)
    }
    let states : Array[EffectItemProgress] = []
    for code in row_states[index] {
      used += 1
      total_rows += 1
      if used >= max_work || total_rows > max_rows {
        return Err(CapacityExceeded)
      }
      let state = match code {
        0 => ItemUnattempted
        1 => ItemSending
        2 => ItemApplied
        3 => ItemAccepted
        4 => ItemFailed
        5 => ItemUnknown
        _ => return Err(InvalidHistory)
      }
      states.push(state)
    }
    members.push({ effect_id: effect_ids[index], policy, rows: states, })
  }
  effect_set_frontier(members, max_members, max_rows, max_work - used)
}

///|
/// Derive progress from exact durable row heads, not caller-supplied state
/// codes. The expected bases must come from the admitted checked Preview and
/// physical request. A dispatching head remains in flight/uncertain until a
/// separate reconciliation transition establishes its outcome; this function
/// never authorizes another physical send.
pub fn effect_set_frontier_from_ledger_entries(
  effect_ids : Array[String],
  policies : Array[Int],
  locators : Array[Array[LogicalItemLocator]],
  expected_bases : Array[Array[EffectLedgerBasis]],
  heads : Array[Array[EffectLedgerEntry?]],
  max_members : Int,
  max_rows : Int,
  max_work : Int,
) -> Result[EffectSetFrontier, EffectSetProgressIssue] {
  if max_members < 1 ||
    max_rows < 0 ||
    max_work < 1 ||
    effect_ids.length() != policies.length() ||
    effect_ids.length() != locators.length() ||
    effect_ids.length() != expected_bases.length() ||
    effect_ids.length() != heads.length() ||
    effect_ids.length() > max_members {
    return Err(InvalidLimits)
  }
  let members : Array[EffectMemberProgress] = []
  let mut work = 0
  let mut total_rows = 0
  for member_index in 0..<effect_ids.length() {
    work += 1
    if work >= max_work {
      return Err(CapacityExceeded)
    }
    let policy = match policies[member_index] {
      0 => HaltMember
      1 => ContinueMember
      _ => return Err(InvalidMember)
    }
    let bases = expected_bases[member_index]
    let member_locators = locators[member_index]
    let current = heads[member_index]
    if bases.length() != current.length() ||
      bases.length() != member_locators.length() ||
      bases.length() > max_rows - total_rows {
      return Err(InvalidLimits)
    }
    total_rows += bases.length()
    let rows : Array[EffectItemProgress] = []
    for row_index in 0..<bases.length() {
      work += 1
      if work >= max_work {
        return Err(CapacityExceeded)
      }
      let locator = member_locators[row_index]
      if locator.effect_id != effect_ids[member_index] ||
        locator.cid != bases[row_index].logical_item_locator_cid {
        return Err(ForeignLedgerEntry(member_index, row_index))
      }
      let state = match current[row_index] {
        None => ItemUnattempted
        Some(entry) => {
          if !effect_ledger_entry_matches_basis(entry, bases[row_index]) {
            return Err(ForeignLedgerEntry(member_index, row_index))
          }
          match entry.state {
            Prepared => ItemUnattempted
            Dispatching => ItemSending
            Applied => ItemApplied
            Accepted => ItemAccepted
            Failed => ItemFailed
            Unknown => ItemUnknown
          }
        }
      }
      rows.push(state)
    }
    members.push({ effect_id: effect_ids[member_index], policy, rows, })
  }
  effect_set_frontier(members, max_members, max_rows, max_work - work)
}

///|
pub fn effect_set_frontier_outcome_code(frontier : EffectSetFrontier) -> Int {
  match frontier.outcome {
    SetRunning => 0
    SetSucceeded => 1
    SetFailed => 2
    SetNeedsReconciliation => 3
  }
}

///|
pub fn effect_set_frontier_ready_count(frontier : EffectSetFrontier) -> Int {
  frontier.ready.length()
}

///|
pub fn effect_set_frontier_ready_member(
  frontier : EffectSetFrontier,
  index : Int,
) -> Int {
  if index < 0 || index >= frontier.ready.length() {
    return -1
  }
  frontier.ready[index].0
}

///|
pub fn effect_set_frontier_ready_row(
  frontier : EffectSetFrontier,
  index : Int,
) -> Int {
  if index < 0 || index >= frontier.ready.length() {
    return -1
  }
  frontier.ready[index].1
}
