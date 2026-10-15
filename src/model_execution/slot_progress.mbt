///|
// Actual membership in this Model Owner, not Slot-number equality, a copied
// progress record or current dispatch permission. Stopping retains this
// custody until the original cleanup actually completes. Window membership
// uses the retained original frames, not the selected work cursor's position.
fn model_slot_progress_owned(
  state : ModelState,
  progress : ModelSlotProgress,
) -> Bool {
  if state.reclaimed {
    false
  } else {
    match state.slot_window {
      None => physical_equal(state.progress, progress)
      Some(window) =>
        window.frames.any(frame => {
          frame is Some(frame) && physical_equal(frame.progress, progress)
        })
    }
  }
}
