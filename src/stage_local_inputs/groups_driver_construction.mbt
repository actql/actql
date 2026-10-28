///|
/// Original remaining work at MakeGroups. Index reconciliation owns its prefix;
/// do not subtract its observation from this remaining-work convention again.
pub fn local_environment_groups_work_bound(
  read : LocalEnvironmentPreparation,
) -> Int? {
  guard read.state is MakeGroups else { return None }
  Some(read.work)
}

///|
// makei closure1H and stage_at Some1H1R1W; on refusal BudgetExceeded,
// failed-phase/Some, LocalDone/Err and returned phase6H3R6W.
// Successful groups/work/phase and empty successor array belong to the body.
let local_groups_driver_units : @shape.CollectionConstructionExtent = {
  record_headers: 8L,
  reference_slots: 4L,
  scalar_words: 7L,
}

///|
pub fn local_environment_groups_driver_extent() -> @shape.CollectionConstructionExtent {
  local_groups_driver_units
}

///|
// Original inventory/Some2H1R10W. The arithmetic has no input-sized walk.
let local_groups_quote_units : @shape.CollectionConstructionExtent = {
  record_headers: 2L,
  reference_slots: 1L,
  scalar_words: 10L,
}

///|
pub fn local_environment_groups_quotation_extent() -> @shape.CollectionConstructionExtent {
  local_groups_quote_units
}
