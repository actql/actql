///|
// Actual membership in this Model Owner, not Slot-number equality, a copied
// progress record or current dispatch permission. Stopping retains this
// custody until the original cleanup actually completes. The future window
// must extend this same membership check, not substitute its scan position.
fn model_slot_progress_owned(
  state : ModelState,
  progress : ModelSlotProgress,
) -> Bool {
  !state.reclaimed && physical_equal(state.progress, progress)
}
