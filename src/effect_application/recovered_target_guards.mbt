///|
/// Exact Preview/request rows selected from admitted durable ledger heads.
/// This owner is not a send permit; current authority and all other apply
/// obligations still apply. Callers cannot construct an exclusion mask.
struct RecoveredEffectTargetGuards {
  preview : @publication.EffectPreviewIdentity
  scope_cid : String
  required_rows : Map[String, Bool]
}

///|
pub fn recover_effect_target_guards(
  preview : @publication.EffectPreviewIdentity,
  scopes : Array[Array[LogicalRequestScope]],
  locators : Array[Array[LogicalItemLocator]],
  keys : Array[Array[EffectDispatchKey]],
  expected_bases : Array[Array[EffectLedgerBasis]],
  heads : Array[Array[EffectLedgerEntry?]],
  active_owners : Array[Array[Bool]],
  max_members : Int,
  max_rows : Int,
  max_work : Int,
) -> Result[RecoveredEffectTargetGuards, EffectSetProgressIssue] {
  if max_members < 1 ||
    max_rows < 0 ||
    max_work < 1 ||
    heads.length() > max_members {
    return Err(InvalidLimits)
  }
  let mut selected_work = 0
  for rows in heads {
    if rows.length() > max_rows - selected_work ||
      rows.length() >= max_work - selected_work {
      return Err(CapacityExceeded)
    }
    selected_work += rows.length()
  }
  // Reuse the full Preview/row/key/basis/history admission. Missing heads
  // are valid for a first dispatch frontier, but never a recovery waiver.
  match
    effect_set_frontier_from_preview_ledger_entries(
      preview,
      scopes,
      locators,
      keys,
      expected_bases,
      heads,
      active_owners,
      max_members,
      max_rows,
      max_work - selected_work,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let required_rows : Map[String, Bool] = Map([])
  let mut scope_cid = None
  let mut work = 0
  for member_index in 0..<heads.length() {
    for row_index in 0..<heads[member_index].length() {
      work += 1
      if work > max_work {
        return Err(CapacityExceeded)
      }
      guard heads[member_index][row_index] is Some(head) else {
        return Err(ForeignLedgerEntry(member_index, row_index))
      }
      let row_scope = logical_request_scope_cid(scopes[member_index][row_index])
      match scope_cid {
        None => scope_cid = Some(row_scope)
        Some(expected) if expected != row_scope =>
          return Err(ForeignLedgerEntry(member_index, row_index))
        _ => ()
      }
      if head.state == Prepared {
        let row = @publication.effect_preview_row_identity(
          preview, member_index, row_index,
        ).unwrap()
        required_rows[row] = true
      }
    }
  }
  guard scope_cid is Some(scope_cid) else { return Err(InvalidLimits) }
  Ok({ preview, scope_cid, required_rows, })
}

///|
pub fn check_recovered_effect_target_guards(
  preview : @publication.EffectPreviewIdentity,
  scope : LogicalRequestScope,
  recovered : RecoveredEffectTargetGuards,
  observations : Array[EffectTargetVersionObservation],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, EffectPreviewTargetGuardIssue] {
  if !physical_equal(recovered.preview, preview) ||
    recovered.scope_cid != logical_request_scope_cid(scope) {
    return Err(ForeignRecoveryEvidence)
  }
  check_effect_preview_target_guards_selected(
    preview,
    observations,
    Some(recovered.required_rows),
    max_rows,
    max_work,
  )
}
