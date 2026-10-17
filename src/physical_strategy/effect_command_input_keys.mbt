///|
/// Whole-input key validation retains the same captured member, checked
/// Command and Result export. It is not a KeySet, target issuer, byte-capacity
/// supplier, apply permit or acknowledgement of physical Result retirement.
struct CapturedEffectCommandKeyValidation {
  inputs : CapturedEffectInputs
  member_index : Int
  input : CapturedEffectInput
  command : @results.EffectCommandInputBinding
  local_index : Int
  original_result : CapturedEffectLocalResult
  mut exported : CapturedEffectLocalResultExport?
  mut field : @schema.Field?
  mut validation : @execution.CompletedResultKeyValidation?
  mut terminal : Bool
  mut revoked : Bool
  mut retained : Bool
  mut retaining : Bool
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
    !captured_effect_command_key_original_retained(value) ||
    captured_effect_input_at(value.inputs, value.member_index).map(input => {
      physical_equal(input, value.input)
    }) !=
    Some(true) {
    return false
  }
  let available = captured_any_result_borrow_available(value.input.borrow) &&
    captured_any_result_borrow_available(value.original_result.borrow)
  available &&
  !value.revoked &&
  captured_effect_command_key_original_retained(value)
}

///|
/// Callback-free original-capture fence. The original Result and member
/// bindings survive temporary export-view retirement; their pins do not.
fn captured_effect_command_key_original_retained(
  value : CapturedEffectCommandKeyValidation,
) -> Bool {
  if !value.inputs.live ||
    !value.inputs.pins.live ||
    !value.inputs.table_pins.live ||
    value.inputs.local_results
    .get(value.local_index)
    .map(result => physical_equal(result, value.original_result)) !=
    Some(true) ||
    !captured_any_result_borrow_retained(value.input.borrow) ||
    !captured_any_result_borrow_retained(value.original_result.borrow) {
    return false
  }
  match value.exported {
    Some(exported) =>
      captured_effect_local_result_export_retained(value.inputs, exported)
    None => value.retained
  }
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
    local_index,
    original_result: exported.result,
    exported: Some(exported),
    field: Some(field),
    validation: Some(validation),
    terminal: false,
    revoked: false,
    retained: false,
    retaining: false,
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
  guard value.validation is Some(validation) else {
    return Err(Control(@bounded.Terminal))
  }
  if !captured_effect_command_key_origin(value) {
    value.revoked = true
    @execution.cancel_completed_result_key_validation(validation)
  }
  let poll = match
    @execution.advance_completed_result_key_validation(validation, quantum) {
    Ok(poll) => poll
    Err(issue) => return Err(Control(issue))
  }
  if !(poll is @bounded.ContinueWith(_, ..)) {
    value.terminal = true
  }
  if !captured_effect_command_key_origin(value) {
    value.revoked = true
    @execution.cancel_completed_result_key_validation(validation)
  }
  Ok(poll)
}

///|
/// Cancelling private key work never releases the original Result borrow or
/// its physical reader. Their existing captured/RowRun owners retain custody.
pub fn cleanup_captured_effect_command_key_validation(
  value : CapturedEffectCommandKeyValidation,
) -> Result[Bool, CapturedEffectCommandKeyIssue] {
  guard value.validation is Some(validation) else { return Ok(value.retained) }
  if !value.terminal {
    value.revoked = true
    @execution.cancel_completed_result_key_validation(validation)
    match advance_captured_effect_command_key_validation(value, 1) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match @execution.cleanup_completed_result_key_validation(validation) {
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
  if value.retaining ||
    !physical_equal(value.inputs, inputs) ||
    value.member_index != member_index ||
    !physical_equal(value.command, command) ||
    !captured_effect_command_key_origin(value) {
    return false
  }
  let complete = if value.retained {
    value.terminal
  } else {
    match (value.validation, value.exported, value.field) {
      (Some(validation), Some(exported), Some(field)) =>
        @execution.completed_result_key_validation_matches(
          validation,
          exported.preparation,
          field,
        )
      _ => false
    }
  }
  complete && captured_effect_command_key_origin(value)
}

///|
/// Move completed immutable correspondence into the same captured Owner
/// before the temporary re-admission bridge closes. Original pins/current
/// remain mandatory. This transfers no reader, KeySet, durable receipt or
/// send authority; it drops the private traversal and its derived-view refs.
pub fn retain_captured_effect_command_key_validation(
  value : CapturedEffectCommandKeyValidation,
) -> Result[Unit, CapturedEffectCommandKeyIssue] {
  if value.retaining {
    return Err(ForeignOrigin)
  }
  value.retaining = true
  let result = retain_completed_captured_effect_command_key_validation(value)
  value.retaining = false
  result
}

///|
fn retain_completed_captured_effect_command_key_validation(
  value : CapturedEffectCommandKeyValidation,
) -> Result[Unit, CapturedEffectCommandKeyIssue] {
  guard !value.retained &&
    !value.revoked &&
    value.terminal &&
    value.validation is Some(validation) &&
    value.exported is Some(exported) &&
    value.field is Some(field) &&
    captured_effect_command_key_origin(value) else {
    return Err(ForeignOrigin)
  }
  if !@execution.completed_result_key_validation_matches(
      validation,
      exported.preparation,
      field,
    ) ||
    !captured_effect_command_key_original_retained(value) ||
    !@execution.release_completed_result_key_validation(validation) {
    return Err(ForeignOrigin)
  }
  value.retained = true
  value.validation = None
  value.exported = None
  value.field = None
  Ok(())
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

///|
/// Final callback-free fence after target/current and row projection calls.
/// It observes the same original holdings; it issues no availability or ACK.
fn captured_effect_optional_command_key_retained(
  value : CapturedEffectCommandKeyValidation?,
  inputs : CapturedEffectInputs,
) -> Bool {
  match value {
    None => true
    Some(value) =>
      !value.revoked &&
      value.terminal &&
      physical_equal(value.inputs, inputs) &&
      captured_effect_command_key_original_retained(value)
  }
}
