///|
pub fn Journal::claim_effect_ledger_dispatch(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _scope : @request_scope.LogicalRequestScope,
  _locator : @effect.LogicalItemLocator,
  _key : @effect.EffectDispatchKey,
  _basis : @effect.EffectLedgerBasis,
  _limits : @checkpoint.WireLimits,
  _checkpoint_limits : @checkpoint.WireLimits,
) -> Result[(Bool, @effect.EffectLedgerEntry), NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::record_effect_ledger_response(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _dispatching : @effect.EffectLedgerEntry,
  _scope : @request_scope.LogicalRequestScope,
  _locator : @effect.LogicalItemLocator,
  _key : @effect.EffectDispatchKey,
  _canonical_request_cid : String,
  _response : NativeEffectSavedResponse,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::effect_ledger_response(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _dispatching : @effect.EffectLedgerEntry,
) -> Result[NativeEffectSavedResponse?, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}
