///|
/// The checked Plan and approved Preview remain paired with the same live
/// captured input. A physical adapter must still supply rows from that input's
/// verified Result cursor; this owner is not an Effect apply permit.
struct CapturedEffectPlanVerifier {
  preview : CapturedEffectPreviewInputs
  preview_index : Int
  terminal : @results.EffectPlanTerminal
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
) -> Result[CapturedEffectProposalPlan, CapturedEffectProposalIssue] {
  guard captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(InvalidMember)
  }
  if !inputs.live || !captured_any_result_borrow_available(input.borrow) {
    return Err(NotReady)
  }
  let static_candidate = @checked.effect_program_run_static_candidate(
    inputs.run.checked.run,
  )
  let effects = @checked.effect_program_static_effects(static_candidate)
  let rules = @results.effect_static_candidate_mapping_rules(effects)
  let terminal = match
    @results.effect_plan_terminal_for_member(
      rules, member_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  let create_terminal = if terminal is None {
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
  if terminal is None && create_terminal is None {
    return Err(MissingPlan)
  }
  let source_result = match terminal {
    Some(value) => @results.effect_plan_terminal_source_result(value)
    None =>
      @results.effect_create_row_terminal_source_result(
        create_terminal.unwrap(),
      )
  }
  if input.source.member_index != member_index ||
    source_result !=
    @execution.managed_result_occurrence_name(input.source.occurrence) {
    return Err(ForeignBinding)
  }
  Ok({
    inputs,
    member_index,
    input,
    terminal,
    create_terminal,
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
  let (selector, changes) = match value.terminal {
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
  value.next_row += 1
  Ok((selector, changes))
}

///|
pub fn finish_captured_effect_proposal_plan(
  value : CapturedEffectProposalPlan,
  row_count : Int,
) -> Result[Unit, CapturedEffectProposalIssue] {
  if !value.live ||
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
}

///|
pub fn prepare_captured_effect_plan_verifier(
  preview : CapturedEffectPreviewInputs,
  preview_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[CapturedEffectPlanVerifier, CapturedEffectPlanVerifyIssue] {
  if captured_effect_preview_input_at(preview, preview_index) is None {
    return Err(InvalidMember)
  }
  let terminal = match
    captured_effect_preview_plan_terminal(
      preview, preview_index, max_fields, max_work,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(MissingPlan)
    Err(issue) => return Err(Plan(issue))
  }
  let run = @checked.effect_program_run_preview_owner(
    captured_effect_preview_owner(preview),
  )
  let static_candidate = @checked.effect_program_run_static_candidate(run)
  let effects = @checked.effect_program_static_effects(static_candidate)
  let literals = @results.effect_static_candidate_mapping_literals(effects)
  Ok({ preview, preview_index, terminal, literals, next_row: 0, live: true, })
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
    captured_effect_preview_input_at(value.preview, value.preview_index) is None {
    value.live = false
    return Err(NotReady)
  }
  if source_row_index != value.next_row {
    value.live = false
    return Err(PreviewMismatch)
  }
  let projected = match
    @results.project_effect_plan_row(
      value.terminal,
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
  let identity = @checked.effect_program_run_preview_identity(
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
  value.next_row += 1
  Ok(())
}

///|
pub fn finish_captured_effect_plan_verifier(
  value : CapturedEffectPlanVerifier,
) -> Result[CapturedEffectPlanProof, CapturedEffectPlanVerifyIssue] {
  if !value.live ||
    captured_effect_preview_input_at(value.preview, value.preview_index) is None {
    value.live = false
    return Err(NotReady)
  }
  value.live = false
  let identity = @checked.effect_program_run_preview_identity(
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
  Ok({ preview: value.preview, preview_index: value.preview_index, input, })
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
  match captured_effect_preview_input_at(preview, preview_index) {
    Some(input) => physical_equal(input, proof.input)
    None => false
  }
}

///|
/// Every member with a checked Plan must contribute exactly one proof from
/// the same captured owner. This is payload evidence, not send authority.
pub fn check_captured_effect_plan_proofs(
  preview : CapturedEffectPreviewInputs,
  proofs : Array[CapturedEffectPlanProof],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectPlanInventoryIssue] {
  if max_members < 1 || max_work < 1 {
    return Err(InvalidLimits)
  }
  let identity = @checked.effect_program_run_preview_identity(
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
      @publication.effect_preview_member_plan_cid(identity, member_index)
      is None ||
      !captured_effect_plan_proof_matches(proof, preview, member_index) {
      return Err(ForeignProof(proof_index))
    }
    if seen[member_index] {
      return Err(DuplicateProof(member_index))
    }
    seen[member_index] = true
  }
  for index in 0..<count {
    if @publication.effect_preview_member_plan_cid(identity, index) is Some(_) &&
      !seen[index] {
      return Err(MissingProof(index))
    }
  }
  Ok(())
}

///|
pub fn cancel_captured_effect_plan_verifier(
  value : CapturedEffectPlanVerifier,
) -> Unit {
  value.live = false
}
