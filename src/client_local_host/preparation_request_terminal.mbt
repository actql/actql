///|
/// The typed Request entry selects its existing checker from the SAME retained
/// Program inventory. The two immutable compiler configurations are supplied
/// by the installed Host, not resource grants or public request knobs.
pub fn[I] prepare_request_computation_check_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  source_catalog? : @checked.PreparedSourceCatalog? = None,
  source_preparation? : @stages.Source? = None,
) -> Result[
  ClientProgramCheckPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  prepare_request_check_preparation_owned(
    owner,
    input,
    environment,
    supplied,
    evidence,
    program_limits.checking,
    source_catalog~,
    source_preparation~,
    computation_limits=Some((program_limits, effect_limits)),
  )
}

///|
/// Preserve the original nominal verdict; a rejected/missing-input check is
/// neither a compiler WrongPhase nor a generic Host/Unknown classification.
pub suberror ClientRequestTerminalIssue {
  Preparation(ClientRequestPreparationIssue)
  CheckOutcome(@checked.CheckOutcome)
  Publication(@source_publication.PreparedPublicationIssue)
  QuerySyntax(ClientRequestQuerySyntaxIssue)
  QueryLowering(ClientRequestQueryLoweringIssue)
}

///|
/// Complete only the original semantic checker. The original Request remains
/// on its Unit reservation before Pure/Effect body selection, so a trusted
/// installation can inspect its checked request subjects before compilation.
/// This issues no Prepared body, Plan, Run, permission or cleanup witness.
pub fn[I] finish_request_computation_check(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestTerminalIssue] {
  guard owner.phase == ProgramCheck &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.policy_subject_work is None &&
    owner.computation_limits is Some(_) else {
    return Err(Preparation(WrongPhase))
  }
  if child.phase == RequestsPrepared ||
    child.phase == RequestsRetained ||
    child.phase == SemanticCheckQuoted {
    if child.effect_limits is Some(_) {
      match finish_effect_program_check_preparation(child) {
        Err(issue) => return Err(Preparation(ProgramCheck(issue)))
        Ok(_) => ()
      }
    } else {
      match finish_program_check_preparation(child) {
        Err(issue) => return Err(Preparation(ProgramCheck(issue)))
        Ok(_) => ()
      }
    }
  }
  if child.effect_limits is None {
    guard child.check_outcome is Some(outcome) else {
      return Err(Preparation(WrongPhase))
    }
    if !(outcome is @checked.Checked(_)) {
      return Err(CheckOutcome(outcome))
    }
  }
  if child.phase != SemanticCheckComplete &&
    child.phase != CompilationQuoted &&
    child.phase != CompilationComplete {
    return Err(Preparation(WrongPhase))
  }
  Ok(())
}

///|
/// Complete the retained remaining checker and compiler once, then continue
/// the SAME capacity to its real Pure/Effect body type. Unit is intentional:
/// the normal Node caller receives no raw Prepared. A separate same-reservation
/// constructor-input borrow can retain immutable DATA before Plan completion,
/// but cannot replace the actual Plan/body or admit a Run. No second parse/check,
/// no-plan preparation, caller
/// mode/Bool, new Resource owner or per-operation current callback is used.
pub fn[I] finish_request_computation_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
) -> Result[Unit, ClientRequestTerminalIssue] {
  match finish_request_computation_check(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let child = owner.program_check.unwrap()
  let limits = owner.computation_limits.unwrap()
  if child.effect_limits is Some(_) {
    if child.phase != CompilationComplete {
      match
        compile_effect_program_check_preparation(
          child,
          update_targets~,
          store_targets~,
          command_targets~,
          source_input=request_source_input_original(owner),
        ) {
        Err(issue) => return Err(Preparation(ProgramCheck(issue)))
        Ok(_) => ()
      }
    }
    match continue_request_effect_preparation(owner, input) {
      Err(issue) => return Err(Preparation(issue))
      Ok(_) => ()
    }
  } else {
    if child.phase != CompilationComplete {
      match compile_program_check_preparation(child, limits) {
        Err(issue) => return Err(Preparation(ProgramCheck(issue)))
        Ok(_) => ()
      }
    }
    match continue_request_program_preparation(owner, input) {
      Err(issue) => return Err(Preparation(issue))
      Ok(_) => ()
    }
  }
  if owner.source_input is Some(_) {
    // Finish the SAME retained Source's existing checked profile/association
    // under its original handoff quote. Keep the cached original, not a second
    // check/compiler or a syntax-based ARRAY classifier in this caller.
    let original = match borrow_request_source_preparation(owner, input) {
      Err(issue) => return Err(Preparation(issue))
      Ok(value) => value
    }
    match @resources.return_preparation_body_borrow(original) {
      Err(issue) => return Err(Preparation(Capacity(issue)))
      Ok(_) => ()
    }
  } else if owner.query_syntax is Some(_) {
    // Native's existing typed Query entrance retains its parser on this same
    // Request, rather than the submitted Source envelope. JSON/YAML Program
    // inputs have neither Source original and keep recursive ARRAY support.
    let profile = if owner.compiled_effect is Some(prepared) && owner.effect_capacity is Some(capacity) {
      match reserve_request_query_profile_scratch(owner, input, capacity) {
        Err(issue) => return Err(Preparation(issue))
        Ok(_) => ()
      }
      @publication_host.check_client_source_array_profile(
        @checked.effect_program_static_checked_computation(
          @publication_host.prepared_client_effect_computation_candidate(prepared),
        ),
      )
    } else if owner.compiled_program is Some(prepared) && owner.program_capacity is Some(capacity) {
      match reserve_request_query_profile_scratch(owner, input, capacity) {
        Err(issue) => return Err(Preparation(issue))
        Ok(_) => ()
      }
      @publication_host.check_client_source_array_profile(
        @strategy.graph_program(@publication_host.prepared_client_graph(prepared)),
      )
    } else {
      return Err(Preparation(WrongPhase))
    }
    if profile is Err(issue) {
      return Err(Preparation(SourceInput(Source(issue))))
    }
  }
  Ok(())
}
