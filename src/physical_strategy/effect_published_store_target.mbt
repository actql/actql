///|
/// One installed Command target borrowed by the same captured Run occurrence.
/// Static pair DATA cannot construct this value or replace its live issuer.
pub struct CapturedEffectCommandTarget {
  inputs : CapturedEffectInputs
  member_index : Int
  target : @results.EffectPublishedStoreTarget
}

///|
fn captured_effect_command_input(
  inputs : CapturedEffectInputs,
  member_index : Int,
  max_work : Int,
) -> Result[@results.EffectCommandInputBinding?, CapturedEffectProposalIssue] {
  guard captured_effect_input_at(inputs, member_index) is Some(_) else {
    return Err(NotReady)
  }
  let effects = @checked.effect_program_static_effects(
    @effect_binding.effect_program_run_static_candidate(inputs.run.checked.run),
  )
  @results.effect_command_input_for_member(
    @results.effect_static_candidate_command_inputs(effects),
    member_index,
    max_work,
  ).map_err(issue => Plan(issue))
}

///|
/// Supply the exact pair to the trusted installed collection issuer. Reading
/// it issues no Reference, current authorization, capture, or physical I/O.
pub fn captured_effect_published_store_binding(
  inputs : CapturedEffectInputs,
  member_index : Int,
  max_work : Int,
) -> Result[@environment.StoreCommandBinding?, CapturedEffectProposalIssue] {
  captured_effect_command_input(inputs, member_index, max_work).map(command => {
    command.bind(value => {
      @results.effect_command_target_store_binding(
        @results.effect_command_input_target(value),
      )
    })
  })
}

///|
/// Keep the issuer's checked original in the existing captured-input lifetime.
/// An equal pair or target from another member cannot be substituted here.
pub fn bind_captured_effect_command_target(
  inputs : CapturedEffectInputs,
  member_index : Int,
  pair : @environment.StoreCommandBinding,
  reference : @value.CheckedValue,
  max_work : Int,
) -> Result[CapturedEffectCommandTarget, CapturedEffectProposalIssue] {
  let command = match
    captured_effect_command_input(inputs, member_index, max_work) {
    Ok(Some(value)) => value
    Ok(None) => return Err(ForeignBinding)
    Err(issue) => return Err(issue)
  }
  match @results.bind_effect_published_store_target(command, pair, reference) {
    Ok(target) => Ok({ inputs, member_index, target, })
    Err(@results.EffectPublishedStoreTargetIssue::Unavailable) => Err(NotReady)
    Err(_) => Err(ForeignBinding)
  }
}

///|
fn captured_effect_command_target_current(
  original : CapturedEffectCommandTarget,
  inputs : CapturedEffectInputs,
  member_index : Int,
  command : @results.EffectCommandInputBinding,
) -> Bool {
  physical_equal(original.inputs, inputs) &&
  original.member_index == member_index &&
  captured_effect_input_at(inputs, member_index) is Some(_) &&
  @results.effect_published_store_target_current(original.target, command)
}

///|
fn captured_effect_optional_command_target_current(
  original : CapturedEffectCommandTarget?,
  inputs : CapturedEffectInputs,
  member_index : Int,
  command : @results.EffectCommandInputBinding?,
) -> Bool {
  match original {
    None => true
    Some(original) =>
      match command {
        None => false
        Some(command) =>
          captured_effect_command_target_current(
            original, inputs, member_index, command,
          )
      }
  }
}
