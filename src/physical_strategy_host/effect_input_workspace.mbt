///|
/// Borrow the original supplier's preallocated workspace on this captured Run.
/// Same-Ledger correspondence is necessary, not a physical phase/installation
/// assignment, an adequate envelope or permission to read. No new reservation
/// or allocation is made here, and the parent allocation remains supplier-owned.
///
/// Retain an Ok borrower before invoking any further currentness callback. The
/// Resource admission itself may call its original Host; a late capture/Source
/// refusal must keep this exact loan for physical cleanup, not lose it in Err.
pub fn borrow_captured_effect_input_workspace(
  inputs : CapturedEffectInputs,
  capacity : @resources.SharedCapacity,
  allocation : @resources.SharedAllocation,
) -> Result[@resources.SharedBorrow, @resources.LedgerIssue] {
  if !captured_effect_inputs_shared_capacity_current(inputs, capacity) {
    return Err(@resources.ForeignOwner)
  }
  @resources.borrow_shared_capacity(capacity, allocation)
}
