///|
/// Pure comparison of an existing opaque Ledger basis. Status 0 preserves
/// the original codec path; no Entry, cache, current fact or grant is issued.
#export_name("strategyEffectLedgerClaimFactsStatus")
pub fn strategy_effect_ledger_claim_facts_status(
  basis : @effect.EffectLedgerBasis,
  scope : @effect.LogicalRequestScope,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  intent_fingerprint_cid : String,
  canonical_request_cid : String,
  expected_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int {
  @effect.effect_ledger_claim_facts_status(
    basis, scope, locator, key, intent_fingerprint_cid, canonical_request_cid, expected_scope_cid,
    max_wire_bytes, max_nodes, max_depth,
  )
}
