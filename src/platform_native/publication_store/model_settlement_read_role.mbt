///|
/// The existing encrypted settlement leaves used to verify a saved outcome.
/// The provider body holding is outside this selection.
pub(all) enum ModelSettlementReadRole {
  Accounting
  Outcome
  Capture
  RawDescriptor
  Invocation
  CaptureBundle(Int)
}
