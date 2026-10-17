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
  mut step_work : Int64
  mut workspace : @resources.SharedBorrow?
}

///|
pub(all) enum CapturedEffectCommandKeyIssue {
  ForeignOrigin
  MissingKey
  Plan(@results.EffectPlanBindingIssue)
  Validation(@execution.CompletedResultKeyIssue)
  Control(@bounded.Issue)
  Stopped(@bounded.StopReason)
}

///|
/// Inspect the same checked member binding. This is neither whole-input
/// evidence nor a caller-selected field name.
pub fn captured_effect_command_requires_input_key(
  inputs : CapturedEffectInputs,
  member_index : Int,
  max_work : Int,
) -> Result[Bool, CapturedEffectCommandKeyIssue] {
  guard captured_effect_input_at(inputs, member_index) is Some(_) else {
    return Err(ForeignOrigin)
  }
  let effects = @checked.effect_program_static_effects(
    @effect_binding.effect_program_run_static_candidate(inputs.run.checked.run),
  )
  guard @results.effect_result_binding_at(
      @results.effect_static_candidate_results(effects),
      member_index,
    )
    is Some(binding) else {
    return Err(ForeignOrigin)
  }
  if @syntax.effect_header_kind(@results.effect_result_binding_header(binding)) !=
    "command" {
    return Ok(false)
  }
  match
    @results.effect_command_input_for_member(
      @results.effect_static_candidate_command_inputs(effects),
      member_index,
      max_work,
    ) {
    Ok(Some(command)) =>
      Ok(@results.effect_command_input_key(command) is Some(_))
    Ok(None) => Ok(false)
    Err(issue) => Err(Plan(issue))
  }
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
    !captured_effect_command_key_workspace_current(value) ||
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
      captured_effect_local_result_export_retained(value.inputs, exported) &&
      captured_effect_local_result_export_derived_retained(exported)
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
    step_work: 0L,
    workspace: None,
  })
}

///|
fn captured_effect_command_key_workspace_current(
  value : CapturedEffectCommandKeyValidation,
) -> Bool {
  match value.workspace {
    None => true
    Some(workspace) =>
      @resources.shared_borrow_matches_ledger(
        workspace,
        value.inputs.run.captured.ledger,
      )
  }
}

///|
/// The private original Host supplier selects and retains its allocation
/// before key construction. Bind the exact outstanding borrower before the
/// first step. This Ledger check is consistency, not a phase/adequacy proof.
pub fn bind_captured_effect_command_key_workspace(
  value : CapturedEffectCommandKeyValidation,
  workspace : @resources.SharedBorrow,
) -> Bool {
  if value.workspace is Some(_) ||
    value.terminal ||
    value.revoked ||
    value.retained ||
    value.step_work != 0L ||
    !captured_effect_command_key_origin(value) ||
    !@resources.shared_borrow_matches_ledger(
      workspace,
      value.inputs.run.captured.ledger,
    ) {
    return false
  }
  value.workspace = Some(workspace)
  true
}

///|
/// One bounded validation or private-retirement transition for a Host caller.
/// No row is projected until whole completion, workspace cleanup and the
/// one-time original-capture transfer all succeed. The second result reports
/// continuation progress (including terminal/cleanup transitions), not a new
/// charge or an override of the original cursor's semantic work accounting.
pub fn step_captured_effect_command_key_validation(
  value : CapturedEffectCommandKeyValidation,
  quantum : Int,
) -> Result[(Bool, Int), CapturedEffectCommandKeyIssue] {
  if quantum <= 0 {
    return Err(Control(@bounded.InvalidQuantum))
  }
  if value.retaining {
    return Err(ForeignOrigin)
  }
  if value.retained {
    return if captured_effect_command_key_origin(value) {
      Ok((true, 0))
    } else {
      Err(ForeignOrigin)
    }
  }
  if value.terminal {
    match cleanup_captured_effect_command_key_validation(value) {
      Err(issue) => return Err(issue)
      Ok(true) =>
        return retain_captured_effect_command_key_validation(value).map(_ => {
          (true, 1)
        })
      Ok(false) => return Ok((false, 1))
    }
  }
  let poll = match
    advance_captured_effect_command_key_validation(value, quantum) {
    Ok(poll) => poll
    Err(issue) => return Err(issue)
  }
  match poll {
    @bounded.ContinueWith(_, work~, ..) | @bounded.Completed(_, work~, ..) => {
      let used = work - value.step_work
      value.step_work = work
      Ok((false, Int::max(1, used.to_int())))
    }
    @bounded.FailedWith(issue, ..) => Err(Validation(issue))
    @bounded.StoppedWith(reason, ..) => Err(Stopped(reason))
  }
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
