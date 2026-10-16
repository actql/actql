///|
/// Final non-callback custody fence for one original Effect input. Physical
/// availability and current authority remain separate checks; this does not
/// allocate, acquire a new pin or revive a released consumer.
pub fn captured_effect_input_retained(
  inputs : CapturedEffectInputs,
  member_index : Int,
  input : CapturedEffectInput,
) -> Bool {
  inputs.live &&
  inputs.pins.live &&
  inputs.entries
  .get(member_index)
  .bind(value => value)
  .map(value => {
    physical_equal(value, input) &&
    captured_any_result_borrow_retained(value.borrow)
  }) ==
  Some(true)
}
