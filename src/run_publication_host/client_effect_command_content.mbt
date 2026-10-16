///|
pub(all) enum ClientEffectCommandContentIssue {
  InvalidLimits
  Limit
  ForeignInput
  MissingContentInput
  Unavailable
  Command(@stage_results.EffectPlanBindingIssue)
  Export(@execution.CompletedExportIssue)
}

///|
/// Borrow the original issued Content in one checked Command input, from the
/// same Run/member's successful immutable export. The existing captured owner
/// retains the pin, Artifact and Reference across physical preparation. This
/// read is neither byte acquisition, a reservation nor an Effect permission.
fn read_client_effect_command_content_reference(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  row : Int,
  input_name : String,
  max_fields : Int,
  max_work : Int,
) -> Result[@values.ReferenceValue, ClientEffectCommandContentIssue] {
  if row < 0 || max_fields < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !client_effect_local_artifact_matches_computation(artifact, owner) ||
    !client_effect_local_artifact_matches_member(artifact, inputs, member_index) {
    return Err(ForeignInput)
  }
  guard artifact.source is ResultSource(_, _) &&
    @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(Unavailable)
  }
  let commands = @stage_results.effect_static_candidate_command_inputs(
    @checked.effect_program_static_effects(owner.candidate),
  )
  let count = @stage_results.effect_command_input_count(commands)
  if max_work == 0 || count > max_work - 1 {
    return Err(Limit)
  }
  let command = match
    @stage_results.effect_command_input_for_member(
      commands, member_index, max_work,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(MissingContentInput)
    Err(issue) => return Err(Command(issue))
  }
  let fields = @stage_results.effect_command_input_field_count(command)
  let mut remaining = max_work - count - 1
  if fields > max_fields || fields > remaining {
    return Err(Limit)
  }
  remaining -= fields
  for index in 0..<fields {
    let field = @stage_results.effect_command_input_field_at(command, index).unwrap()
    let name = @stage_results.effect_command_input_field_name(field)
    if name.length() > remaining {
      return Err(Limit)
    }
    remaining -= name.length()
    if input_name.length() > remaining {
      return Err(Limit)
    }
    remaining -= input_name.length()
    if name != input_name {
      continue
    }
    guard @stage_results.effect_command_input_field_contract(field).shape
      is @contract.ContentRef(..) &&
      @stage_results.effect_command_input_field_value(field)
      is @stage_results.ResultField(source) else {
      return Err(MissingContentInput)
    }
    let reference = match
      @execution.completed_relation_export_content_field(
        artifact.export_receipt,
        row,
        source,
        max_fields,
        remaining,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Export(issue))
    }
    // The Reference's Host callback may release the parent input. Inspect
    // explicit retention after it, without calling that Host a second time.
    if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
      !@strategy.captured_effect_input_retained(inputs, member_index, input) {
      return Err(Unavailable)
    }
    return Ok(reference)
  }
  Err(MissingContentInput)
}

///|
/// Original binding retained by a private projection of the existing capture.
/// It owns no physical bytes, reservation, dispatch or independent cleanup.
priv struct ClientEffectCommandContentOriginal {
  mut view : ClientEffectCommandContent?
  owner : PreparedClientEffectComputation
  inputs : @strategy.CapturedEffectInputs
  member_index : Int
  artifact : ClientEffectLocalResultArtifact
  row : Int
  input_name : String
  reference : @values.ReferenceValue
  max_fields : Int
  max_work : Int
}

///|
/// The same issued Reference can legitimately occur in two Runs. This opaque
/// view additionally seals the exact Run/member/Artifact input occurrence;
/// a Reference token, equal wire or CID cannot reconstruct that binding.
struct ClientEffectCommandContent {
  mut original : ClientEffectCommandContentOriginal?
}

///|
pub fn borrow_client_effect_command_content(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  row : Int,
  input_name : String,
  max_fields : Int,
  max_work : Int,
) -> Result[ClientEffectCommandContent, ClientEffectCommandContentIssue] {
  read_client_effect_command_content_reference(
    owner, inputs, member_index, artifact, row, input_name, max_fields, max_work,
  ).map(reference => {
    let original : ClientEffectCommandContentOriginal = {
      view: None,
      owner,
      inputs,
      member_index,
      artifact,
      row,
      input_name,
      reference,
      max_fields,
      max_work,
    }
    let value : ClientEffectCommandContent = { original: Some(original), }
    original.view = Some(value)
    value
  })
}

///|
/// Recheck the captured original rather than accepting another call's tuple.
pub fn client_effect_command_content_current(
  value : ClientEffectCommandContent,
) -> Bool {
  guard value.original is Some(original) &&
    original.view.map(issued => physical_equal(issued, value)) == Some(true) else {
    return false
  }
  let current = match
    read_client_effect_command_content_reference(
      original.owner,
      original.inputs,
      original.member_index,
      original.artifact,
      original.row,
      original.input_name,
      original.max_fields,
      original.max_work,
    ) {
    Ok(current) => current
    Err(_) => return false
  }
  physical_equal(current, original.reference) &&
  value.original.map(current => physical_equal(current, original)) == Some(true)
}

///|
/// A preparation cannot substitute another Run/member's view even when that
/// other Run happens to contain the exact same original Reference object.
pub fn client_effect_command_content_matches(
  value : ClientEffectCommandContent,
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  row : Int,
  input_name : String,
) -> Bool {
  guard value.original is Some(original) else { return false }
  physical_equal(original.owner, owner) &&
  physical_equal(original.inputs, inputs) &&
  physical_equal(original.artifact, artifact) &&
  original.member_index == member_index &&
  original.row == row &&
  original.input_name == input_name &&
  client_effect_command_content_current(value)
}

///|
/// Immutable observed DATA only. Byte custody, funding and read permission
/// must still be supplied by the original selected physical Store owner.
pub fn client_effect_command_content_wire(
  value : ClientEffectCommandContent,
) -> Result[String, ClientEffectCommandContentIssue] {
  if !client_effect_command_content_current(value) {
    return Err(Unavailable)
  }
  guard value.original is Some(original) else { return Err(Unavailable) }
  Ok(@values.reference_wire(original.reference))
}

///|
/// Drop this projection's back-references only. This is not physical cleanup,
/// a parent pin release or proof that escaped DATA/byte aliases have retired.
pub fn release_client_effect_command_content(
  value : ClientEffectCommandContent,
) -> Unit {
  if value.original is Some(original) &&
    original.view.map(issued => physical_equal(issued, value)) == Some(true) {
    original.view = None
  }
  value.original = None
}
