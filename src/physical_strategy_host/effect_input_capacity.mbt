///|
/// A private physical borrower may use only an existing open capacity on this
/// captured Run's Ledger. This creates no allocation, borrow or permission and
/// says nothing about the adequacy of its complete simultaneous byte envelope.
pub fn captured_effect_inputs_shared_capacity_current(
  value : CapturedEffectInputs,
  capacity : @resources.SharedCapacity,
) -> Bool {
  value.live &&
  !value.run.captured.stopped &&
  @resources.shared_capacity_matches_ledger(capacity, value.run.captured.ledger)
}
