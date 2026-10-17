///|
/// The checked Plan and approved Preview remain paired with the same live
/// captured input. A physical adapter must still supply rows from that input's
/// verified Result cursor; this owner is not an Effect apply permit.
struct CapturedEffectPlanVerifier {
  preview : CapturedEffectPreviewInputs
  preview_index : Int
  terminal : @results.EffectPlanTerminal?
  command : @results.EffectCommandInputBinding?
  published_target : CapturedEffectCommandTarget?
  input_key : CapturedEffectCommandKeyValidation?
  literals : @results.EffectMappingLiterals
  mut next_row : Int
  mut live : Bool
}

///|
/// Minted only after the complete checked Plan stream matches its captured
/// input. The proof is tied to the live Preview and physical input owner.
struct CapturedEffectPlanProof {
  preview : CapturedEffectPreviewInputs
  preview_index : Int
  input : CapturedEffectInput
  published_target : CapturedEffectCommandTarget?
  input_key : CapturedEffectCommandKeyValidation?
}

///|
/// One checked Mapping selected before the private Preview is authored.
/// This owner advances with the exact bounded Result export but does not
/// retain row payloads or authorize a physical Effect dispatch.
struct CapturedEffectProposalPlan {
  inputs : CapturedEffectInputs
  member_index : Int
  input : CapturedEffectInput
  terminal : @results.EffectPlanTerminal?
  create_terminal : @results.EffectCreateRowTerminal?
  command : @results.EffectCommandInputBinding?
  published_target : CapturedEffectCommandTarget?
  input_key : CapturedEffectCommandKeyValidation?
  literals : @results.EffectMappingLiterals
  mut next_row : Int
  mut live : Bool
}

///|
pub(all) enum CapturedEffectProposalIssue {
  InvalidMember
  NotReady
  ForeignBinding
  MissingPlan
  RowOrder
  RowCountMismatch
  Plan(@results.EffectPlanBindingIssue)
  Row(@results.EffectPlanRowIssue)
  Changes(@results.EffectPlanChangeIssue)
  Create(@results.EffectCreateRowIssue)
  Command(@results.EffectCommandRowIssue)
  SelectorEncoding
} derive(Debug)

///|
/// Select the checked Plan once for a live captured source before the private
/// Preview exists. The Host must advance this owner using the same canonical
/// Result export that seals the source Artifact.
pub fn prepare_captured_effect_proposal_plan(
  inputs : CapturedEffectInputs,
  member_index : Int,
  max_fields : Int,
  max_work : Int,
  published_target? : CapturedEffectCommandTarget? = None,
  input_key? : CapturedEffectCommandKeyValidation? = None,
) -> Result[CapturedEffectProposalPlan, CapturedEffectProposalIssue] {
  if max_fields < 0 || max_work < 0 {
    return Err(Plan(@results.EffectPlanBindingIssue::InvalidLimits))
  }
  guard captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(InvalidMember)
  }
  if !inputs.live || !captured_any_result_borrow_available(input.borrow) {
    return Err(NotReady)
  }
  let static_candidate = @effect_binding.effect_program_run_static_candidate(
    inputs.run.checked.run,
  )
  let effects = @checked.effect_program_static_effects(static_candidate)
  let rules = @results.effect_static_candidate_mapping_rules(effects)
  let command = match
    @results.effect_command_input_for_member(
      @results.effect_static_candidate_command_inputs(effects),
      member_index,
      max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  // Static field admission is no whole-input proof. Only this exact
  // captured member's completed and retired original validation can match.
  if !captured_effect_optional_command_key_current(
      input_key, inputs, member_index, command,
    ) {
    return Err(NotReady)
  }
  if command is Some(command) &&
    @results.effect_command_input_field_count(command) > max_fields {
    return Err(Plan(@results.Terminal(@results.FieldLimit)))
  }
  if published_target is Some(original) {
    guard command is Some(command) &&
      captured_effect_command_target_current(
        original, inputs, member_index, command,
      ) else {
      return Err(ForeignBinding)
    }
  }
  let terminal = if command is Some(_) {
    None
  } else {
    match
      @results.effect_plan_terminal_for_member(
        rules, member_index, max_fields, max_work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Plan(issue))
    }
  }
  let create_terminal = if terminal is None && command is None {
    match
      @results.effect_create_row_terminal_for_member(
        rules, member_index, max_fields, max_work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Plan(issue))
    }
  } else {
    None
  }
  if terminal is None && create_terminal is None && command is None {
    return Err(MissingPlan)
  }
  let source_result = if command is Some(command) {
    @syntax.effect_header_source_result(
      @results.effect_result_binding_header(
        @results.effect_command_target_effect(
          @results.effect_command_input_target(command),
        ),
      ),
    ).unwrap()
  } else {
    match terminal {
      Some(value) => @results.effect_plan_terminal_source_result(value)
      None =>
        @results.effect_create_row_terminal_source_result(
          create_terminal.unwrap(),
        )
    }
  }
  if input.source.member_index != member_index ||
    source_result !=
    @execution.managed_result_occurrence_name(input.source.occurrence) {
    return Err(ForeignBinding)
  }
  if !captured_effect_optional_command_key_current(
      input_key, inputs, member_index, command,
    ) {
    return Err(NotReady)
  }
  Ok({
    inputs,
    member_index,
    input,
    terminal,
    create_terminal,
    command,
    published_target,
    input_key,
    literals: @results.effect_static_candidate_mapping_literals(effects),
    next_row: 0,
    live: true,
  })
}

///|
/// Project one checked Result row. This proposal is not a payload proof or
/// apply permit; the later Preview binding verifies the same captured input.
pub fn project_captured_effect_proposal_row(
  value : CapturedEffectProposalPlan,
  source_row : @identity.CanonicalValue,
  source_row_index : Int,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, String), CapturedEffectProposalIssue] {
  if !value.live ||
    !captured_effect_optional_command_target_current(
      value.published_target,
      value.inputs,
      value.member_index,
      value.command,
    ) ||
    !captured_effect_optional_command_key_current(
      value.input_key,
      value.inputs,
      value.member_index,
      value.command,
    ) ||
    captured_effect_input_at(value.inputs, value.member_index).map(input => {
      physical_equal(input, value.input)
    }) !=
    Some(true) {
    value.live = false
    return Err(NotReady)
  }
  if source_row_index != value.next_row {
    value.live = false
    return Err(RowOrder)
  }
  let (selector, changes) = if value.command is Some(command) {
    match
      @results.project_effect_command_row(
        command,
        source_row,
        max_fields,
        max_work,
        max_bytes,
        max_nodes,
        max_depth,
        published_target=value.published_target.map(original => original.target),
      ) {
      Ok(projected) => projected
      Err(issue) => {
        value.live = false
        return Err(Command(issue))
      }
    }
  } else {
    match value.terminal {
      Some(terminal) => {
        let row = match
          @results.project_effect_plan_row(
            terminal, source_row, source_row_index, max_fields, max_work,
          ) {
          Ok(value) => value
          Err(issue) => {
            value.live = false
            return Err(Row(issue))
          }
        }
        let changes = match
          @results.effect_plan_row_intended_changes_wire(
            row,
            value.literals,
            max_fields,
            max_work,
            max_bytes,
            max_nodes,
            max_depth,
          ) {
          Ok(value) => value
          Err(issue) => {
            value.live = false
            return Err(Changes(issue))
          }
        }
        let selector = @identity.stringify_value(
          @results.effect_plan_row_selector(row),
          max_bytes,
          max_nodes,
          max_depth,
        ) catch {
          _ => {
            value.live = false
            return Err(SelectorEncoding)
          }
        }
        (selector, changes)
      }
      None => {
        let changes = match
          @results.effect_create_row_intended_changes_wire(
            value.create_terminal.unwrap(),
            value.literals,
            source_row,
            max_fields,
            max_work,
            max_bytes,
            max_nodes,
            max_depth,
          ) {
          Ok(value) => value
          Err(issue) => {
            value.live = false
            return Err(Create(issue))
          }
        }
        ("null", changes)
      }
    }
  }
  if !captured_effect_optional_command_key_retained(
      value.input_key,
      value.inputs,
    ) {
    value.live = false
    return Err(NotReady)
  }
  value.next_row += 1
  Ok((selector, changes))
}

///|
pub fn finish_captured_effect_proposal_plan(
  value : CapturedEffectProposalPlan,
  row_count : Int,
) -> Result[Unit, CapturedEffectProposalIssue] {
  if !value.live ||
    !captured_effect_optional_command_target_current(
      value.published_target,
      value.inputs,
      value.member_index,
      value.command,
    ) ||
    !captured_effect_optional_command_key_current(
      value.input_key,
      value.inputs,
      value.member_index,
      value.command,
    ) ||
    captured_effect_input_at(value.inputs, value.member_index).map(input => {
      physical_equal(input, value.input)
    }) !=
    Some(true) {
    value.live = false
    return Err(NotReady)
  }
  value.live = false
  if row_count != value.next_row {
    return Err(RowCountMismatch)
  }
  Ok(())
}

///|
pub fn cancel_captured_effect_proposal_plan(
  value : CapturedEffectProposalPlan,
) -> Unit {
  value.live = false
}

///|
pub(all) enum CapturedEffectPlanInventoryIssue {
  InvalidLimits
  CapacityExceeded
  ForeignProof(Int)
  DuplicateProof(Int)
  MissingProof(Int)
} derive(Debug)

///|
pub(all) enum CapturedEffectPlanVerifyIssue {
  InvalidMember
  MissingPlan
  NotReady
  PreviewMismatch
  SelectorEncoding
  Plan(CapturedEffectPlanIssue)
  Row(@results.EffectPlanRowIssue)
  Changes(@results.EffectPlanChangeIssue)
  Command(@results.EffectCommandRowIssue)
}

///|
pub fn prepare_captured_effect_plan_verifier(
  preview : CapturedEffectPreviewInputs,
  preview_index : Int,
  max_fields : Int,
  max_work : Int,
  published_target? : CapturedEffectCommandTarget? = None,
  input_key? : CapturedEffectCommandKeyValidation? = None,
) -> Result[CapturedEffectPlanVerifier, CapturedEffectPlanVerifyIssue] {
  guard captured_effect_preview_input_at(preview, preview_index) is Some(input) else {
    return Err(InvalidMember)
  }
  let terminal = match
    captured_effect_preview_plan_terminal(
      preview, preview_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  let run = @effect_binding.effect_program_run_preview_owner(
    captured_effect_preview_owner(preview),
  )
  let static_candidate = @effect_binding.effect_program_run_static_candidate(
    run,
  )
  let effects = @checked.effect_program_static_effects(static_candidate)
  // Mapping members keep their original preparation bound: unrelated Command
  // entries must not increase their required lookup budget.
  let command = if @publication.effect_preview_member_kind(
      @effect_binding.effect_program_run_preview_identity(
        captured_effect_preview_owner(preview),
      ),
      preview_index,
    ) ==
    Some("command") {
    match
      @results.effect_command_input_for_member(
        @results.effect_static_candidate_command_inputs(effects),
        input.source.member_index,
        max_work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Plan(Plan(issue)))
    }
  } else {
    None
  }
  if command is Some(command) {
    if terminal is Some(_) ||
      @results.effect_command_input_field_count(command) > max_fields {
      return Err(Plan(Plan(@results.Terminal(@results.FieldLimit))))
    }
    let source_result = @syntax.effect_header_source_result(
      @results.effect_result_binding_header(
        @results.effect_command_target_effect(
          @results.effect_command_input_target(command),
        ),
      ),
    )
    if source_result !=
      Some(@execution.managed_result_occurrence_name(input.source.occurrence)) {
      return Err(Plan(ForeignBinding))
    }
  } else if terminal is None {
    return Err(MissingPlan)
  }
  if published_target is Some(original) {
    guard command is Some(command) &&
      captured_effect_command_target_current(
        original,
        preview.inputs,
        input.source.member_index,
        command,
      ) else {
      return Err(Plan(ForeignBinding))
    }
  }
  if !captured_effect_optional_command_key_current(
      input_key,
      preview.inputs,
      input.source.member_index,
      command,
    ) {
    return Err(NotReady)
  }
  let literals = @results.effect_static_candidate_mapping_literals(effects)
  Ok({
    preview,
    preview_index,
    terminal,
    command,
    published_target,
    input_key,
    literals,
    next_row: 0,
    live: true,
  })
}

///|
/// Check a single Result row in source order. Any mismatch revokes this
/// verifier, so a later row or empty tail cannot turn partial validation into
/// a completed proof. The caller must separately protect row provenance.
pub fn check_captured_effect_plan_row(
  value : CapturedEffectPlanVerifier,
  source_row : @identity.CanonicalValue,
  source_row_index : Int,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, CapturedEffectPlanVerifyIssue] {
  if !value.live ||
    !captured_effect_optional_command_target_current(
      value.published_target,
      value.preview.inputs,
      value.published_target
      .map(original => original.member_index)
      .unwrap_or(-1),
      value.command,
    ) ||
    !captured_effect_optional_command_key_current(
      value.input_key,
      value.preview.inputs,
      value.input_key.map(key => key.member_index).unwrap_or(-1),
      value.command,
    ) ||
    captured_effect_preview_input_at(value.preview, value.preview_index) is None {
    value.live = false
    return Err(NotReady)
  }
  if source_row_index != value.next_row {
    value.live = false
    return Err(PreviewMismatch)
  }
  let (selector, changes) = if value.command is Some(command) {
    match
      @results.project_effect_command_row(
        command,
        source_row,
        max_fields,
        max_work,
        max_bytes,
        max_nodes,
        max_depth,
        published_target=value.published_target.map(original => original.target),
      ) {
      Ok(value) => value
      Err(issue) => {
        value.live = false
        return Err(Command(issue))
      }
    }
  } else {
    let projected = match
      @results.project_effect_plan_row(
        value.terminal.unwrap(),
        source_row,
        source_row_index,
        max_fields,
        max_work,
      ) {
      Ok(value) => value
      Err(issue) => {
        value.live = false
        return Err(Row(issue))
      }
    }
    let changes = match
      @results.effect_plan_row_intended_changes_wire(
        projected,
        value.literals,
        max_fields,
        max_work,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => {
        value.live = false
        return Err(Changes(issue))
      }
    }
    let selector = @identity.stringify_value(
      @results.effect_plan_row_selector(projected),
      max_bytes,
      max_nodes,
      max_depth,
    ) catch {
      _ => {
        value.live = false
        return Err(SelectorEncoding)
      }
    }
    (selector, changes)
  }
  let identity = @effect_binding.effect_program_run_preview_identity(
    captured_effect_preview_owner(value.preview),
  )
  if @publication.effect_preview_row_correlation_wire(
      identity,
      value.preview_index,
      source_row_index,
    ) !=
    Some(selector) ||
    @publication.effect_preview_row_intended_changes_wire(
      identity,
      value.preview_index,
      source_row_index,
    ) !=
    Some(changes) {
    value.live = false
    return Err(PreviewMismatch)
  }
  if !captured_effect_optional_command_key_retained(
      value.input_key,
      value.preview.inputs,
    ) {
    value.live = false
    return Err(NotReady)
  }
  value.next_row += 1
  Ok(())
}

///|
pub fn finish_captured_effect_plan_verifier(
  value : CapturedEffectPlanVerifier,
) -> Result[CapturedEffectPlanProof, CapturedEffectPlanVerifyIssue] {
  if !value.live ||
    !captured_effect_optional_command_target_current(
      value.published_target,
      value.preview.inputs,
      value.published_target
      .map(original => original.member_index)
      .unwrap_or(-1),
      value.command,
    ) ||
    !captured_effect_optional_command_key_current(
      value.input_key,
      value.preview.inputs,
      value.input_key.map(key => key.member_index).unwrap_or(-1),
      value.command,
    ) ||
    captured_effect_preview_input_at(value.preview, value.preview_index) is None {
    value.live = false
    return Err(NotReady)
  }
  value.live = false
  let identity = @effect_binding.effect_program_run_preview_identity(
    captured_effect_preview_owner(value.preview),
  )
  if @publication.effect_preview_row_count(identity, value.preview_index) !=
    Some(value.next_row) {
    return Err(PreviewMismatch)
  }
  guard captured_effect_preview_input_at(value.preview, value.preview_index)
    is Some(input) else {
    return Err(NotReady)
  }
  Ok({
    preview: value.preview,
    preview_index: value.preview_index,
    input,
    published_target: value.published_target,
    input_key: value.input_key,
  })
}

///|
pub fn captured_effect_plan_proof_matches(
  proof : CapturedEffectPlanProof,
  preview : CapturedEffectPreviewInputs,
  preview_index : Int,
) -> Bool {
  if !physical_equal(proof.preview, preview) ||
    proof.preview_index != preview_index {
    return false
  }
  if proof.published_target is Some(original) {
    guard physical_equal(original.inputs, preview.inputs) &&
      original.member_index == proof.input.source.member_index &&
      @results.effect_published_store_target_current(
        original.target,
        original.target.binding,
      ) else {
      return false
    }
  }
  if proof.input_key is Some(key) &&
    !captured_effect_command_key_validation_matches(
      key,
      preview.inputs,
      proof.input.source.member_index,
      key.command,
    ) {
    return false
  }
  match captured_effect_preview_input_at(preview, preview_index) {
    Some(input) =>
      physical_equal(input, proof.input) &&
      captured_effect_optional_command_key_retained(
        proof.input_key,
        preview.inputs,
      )
    None => false
  }
}

///|
/// Every checked row Plan or Command must contribute exactly one proof from
/// the same captured owner. Commands have no Mapping Plan CID, but their
/// target and payload still require input evidence. This is not send authority.
pub fn check_captured_effect_plan_proofs(
  preview : CapturedEffectPreviewInputs,
  proofs : Array[CapturedEffectPlanProof],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectPlanInventoryIssue] {
  if max_members < 1 || max_work < 1 {
    return Err(InvalidLimits)
  }
  let identity = @effect_binding.effect_program_run_preview_identity(
    captured_effect_preview_owner(preview),
  )
  let count = @publication.effect_preview_member_count(identity)
  if count < 1 ||
    count > max_members ||
    proofs.length() > count ||
    count > max_work ||
    proofs.length() > max_work - count {
    return Err(CapacityExceeded)
  }
  let seen = Array::make(count, false)
  for proof_index in 0..<proofs.length() {
    let proof = proofs[proof_index]
    let member_index = proof.preview_index
    if member_index < 0 ||
      member_index >= count ||
      !captured_effect_member_requires_plan_proof(identity, member_index) ||
      !captured_effect_plan_proof_matches(proof, preview, member_index) {
      return Err(ForeignProof(proof_index))
    }
    if seen[member_index] {
      return Err(DuplicateProof(member_index))
    }
    seen[member_index] = true
  }
  for index in 0..<count {
    if captured_effect_member_requires_plan_proof(identity, index) &&
      !seen[index] {
      return Err(MissingProof(index))
    }
  }
  Ok(())
}

///|
fn captured_effect_member_requires_plan_proof(
  identity : @publication.EffectPreviewIdentity,
  index : Int,
) -> Bool {
  @publication.effect_preview_member_plan_cid(identity, index) is Some(_) ||
  @publication.effect_preview_member_kind(identity, index) == Some("command")
}

///|
pub fn cancel_captured_effect_plan_verifier(
  value : CapturedEffectPlanVerifier,
) -> Unit {
  value.live = false
}
