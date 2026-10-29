///|
struct CapturedEffectTableInput {
  source : CheckedEffectTableInputPort
  borrow : CapturedTableInputBorrow
}

///|
pub fn captured_effect_table_input_at(
  value : CapturedEffectInputs,
  index : Int,
) -> CapturedEffectTableInput? {
  if !value.live {
    return None
  }
  value.table_entries
  .get(index)
  .bind(input => input)
  .bind(input => {
    if captured_table_input_borrow_available(input.borrow) {
      Some(input)
    } else {
      None
    }
  })
}

///|
pub fn captured_effect_table_input_borrow(
  value : CapturedEffectTableInput,
) -> CapturedTableInputBorrow {
  value.borrow
}

///|
pub fn captured_effect_table_input_occurrence(
  value : CapturedEffectTableInput,
) -> @execution.ManagedTableInputOccurrence {
  value.source.occurrence
}

///|
pub fn captured_effect_table_input_stage(
  value : CapturedEffectTableInput,
) -> Int {
  value.source.stage
}

///|
pub fn captured_effect_table_input_task(
  value : CapturedEffectTableInput,
) -> Int {
  value.source.task
}

///|
pub fn captured_effect_table_input_member(
  value : CapturedEffectTableInput,
) -> Int {
  value.source.member_index
}

///|
pub fn captured_effect_table_input_name(
  value : CapturedEffectTableInput,
) -> String {
  @ports.table_input_name(
    @execution.managed_table_input_occurrence_definition(
      value.source.occurrence,
    ),
  )
}
