///|
/// Whole-input key validation retains the same captured member, checked
/// Command and Result export. It is not a KeySet, target issuer, byte-capacity
/// supplier, apply permit or acknowledgement of physical Result retirement.
struct CapturedEffectCommandKeyValidation {
  inputs : CapturedEffectInputs
  member_index : Int
  input : CapturedEffectInput
  command : @results.EffectCommandInputBinding
  exported : CapturedEffectLocalResultExport
  field : @schema.Field
  validation : @execution.CompletedResultKeyValidation
  mut terminal : Bool
  mut revoked : Bool
}

///|
pub(all) enum CapturedEffectCommandKeyIssue {
  ForeignOrigin
  MissingKey
  Plan(@results.EffectPlanBindingIssue)
  Validation(@execution.CompletedResultKeyIssue)
  Control(@bounded.Issue)
}

///|
fn captured_effect_command_key_origin(
  value : CapturedEffectCommandKeyValidation,
) -> Bool {
  if value.revoked ||
    !captured_effect_local_result_export_retained(value.inputs, value.exported) ||
    captured_effect_input_at(value.inputs, value.member_index).map(input => {
      physical_equal(input, value.input)
    }) !=
    Some(true) {
    return false
  }
  let available = captured_any_result_borrow_available(value.input.borrow)
  available &&
  !value.revoked &&
  captured_effect_local_result_export_retained(value.inputs, value.exported)
}

///|
/// The local Result export was admitted by the existing Cells/Source or
/// managed-publication bridge. Its original borrow must be the member's exact
/// occurrence. Equal names, schema, rows or CIDs cannot replace that borrow.
pub fn start_captured_effect_command_key_validation(
  engine : @bounded.Control,
  inputs : CapturedEffectInputs,
  member_index : Int,
  local_index : Int,
  exported : CapturedEffectLocalResultExport,
  max_lookup_work : Int,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
) -> Result[CapturedEffectCommandKeyValidation, CapturedEffectCommandKeyIssue] {
  guard captured_effect_local_result_export_retained(inputs, exported) &&
    captured_effect_local_result_matches_member(
      inputs, local_index, member_index,
    ) &&
    captured_effect_local_result_at(inputs, local_index).map(result => {
      physical_equal(result, exported.result)
    }) ==
    Some(true) &&
    captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(ForeignOrigin)
  }
  let candidate = @effect_binding.effect_program_run_static_candidate(
    inputs.run.checked.run,
  )
  let effects = @checked.effect_program_static_effects(candidate)
  let command = match
    @results.effect_command_input_for_member(
      @results.effect_static_candidate_command_inputs(effects),
      member_index,
      max_lookup_work,
    ) {
    Ok(Some(command)) => command
    Ok(None) => return Err(MissingKey)
    Err(issue) => return Err(Plan(issue))
  }
  guard @results.effect_command_input_key(command) is Some(field) else {
    return Err(MissingKey)
  }
  let validation = match
    @execution.start_completed_result_key_validation(
      engine,
      exported.preparation,
      field,
      max_work,
      max_frames,
      max_entries,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Validation(issue))
  }
  Ok({
    inputs,
    member_index,
    input,
    command,
    exported,
    field,
    validation,
    terminal: false,
    revoked: false,
  })
}

///|
/// Availability callbacks can retire the captured owner. Recheck its retained
/// fence after each such callback and after the bounded original traversal.
pub fn advance_captured_effect_command_key_validation(
  value : CapturedEffectCommandKeyValidation,
  quantum : Int,
) -> Result[
  @bounded.Observation[Int, @execution.CompletedResultKeyIssue],
  CapturedEffectCommandKeyIssue,
] {
  if !captured_effect_command_key_origin(value) {
    value.revoked = true
    @execution.cancel_completed_result_key_validation(value.validation)
  }
  let poll = match
    @execution.advance_completed_result_key_validation(
      value.validation,
      quantum,
    ) {
    Ok(poll) => poll
    Err(issue) => return Err(Control(issue))
  }
  if !(poll is @bounded.ContinueWith(_, ..)) {
    value.terminal = true
  }
  if !captured_effect_command_key_origin(value) {
    value.revoked = true
    @execution.cancel_completed_result_key_validation(value.validation)
  }
  Ok(poll)
}

///|
/// Cancelling private key work never releases the original Result borrow or
/// its physical reader. Their existing captured/RowRun owners retain custody.
pub fn cleanup_captured_effect_command_key_validation(
  value : CapturedEffectCommandKeyValidation,
) -> Result[Bool, CapturedEffectCommandKeyIssue] {
  if !value.terminal {
    value.revoked = true
    @execution.cancel_completed_result_key_validation(value.validation)
    match advance_captured_effect_command_key_validation(value, 1) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match @execution.cleanup_completed_result_key_validation(value.validation) {
    Ok(done) => Ok(done)
    Err(issue) => Err(Control(issue))
  }
}

///|
pub fn captured_effect_command_key_validation_matches(
  value : CapturedEffectCommandKeyValidation,
  inputs : CapturedEffectInputs,
  member_index : Int,
  command : @results.EffectCommandInputBinding,
) -> Bool {
  if !physical_equal(value.inputs, inputs) ||
    value.member_index != member_index ||
    !physical_equal(value.command, command) ||
    !captured_effect_command_key_origin(value) {
    return false
  }
  let complete = @execution.completed_result_key_validation_matches(
    value.validation,
    value.exported.preparation,
    value.field,
  )
  complete && captured_effect_command_key_origin(value)
}

///|
fn captured_effect_optional_command_key_current(
  value : CapturedEffectCommandKeyValidation?,
  inputs : CapturedEffectInputs,
  member_index : Int,
  command : @results.EffectCommandInputBinding?,
) -> Bool {
  match command {
    Some(command) =>
      match (@results.effect_command_input_key(command), value) {
        (Some(_), Some(value)) =>
          captured_effect_command_key_validation_matches(
            value, inputs, member_index, command,
          )
        (None, None) => true
        _ => false
      }
    None => value is None
  }
}
