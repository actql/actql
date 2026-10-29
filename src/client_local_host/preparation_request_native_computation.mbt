///|
/// Immutable selected compiler DATA, not an execution mode or an admission.
pub(all) enum ClientRequestComputationKind {
  Pure
  Effect
} derive(Eq, Debug)

///|
/// Read the original selected compiler branch without another checker/current.
/// A caller cannot select it by a mode argument or replace the prepared body.
pub fn[I] request_prepared_computation_kind(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[ClientRequestComputationKind, ClientRequestPreparationIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.phase == ProgramCompiled && owner.compiled_program is Some(_) {
    Ok(Pure)
  } else if owner.phase == EffectCompiled && owner.compiled_effect is Some(_) {
    Ok(Effect)
  } else {
    Err(WrongPhase)
  }
}

///|
/// The exact supplied Parameter cursor retained by this Request. Absence is
/// DATA; foreign input and concurrent construction remain typed refusals.
pub fn[I] request_preparation_parameters_original(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[@decode.Cursor?, ClientRequestPreparationIssue] {
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.phase == Selecting || !owner.native_parameters_ready {
    return Err(WrongPhase)
  }
  Ok(owner.native_parameters)
}

///|
/// Actual fixed Native Request driver: keep one original Source/index,
/// Parameter cursor, Program, Catalog, checker and compiler on this parent.
/// The returned branch is immutable DATA; the selected Plan is still required.
pub fn[I, T] prepare_request_native_computation(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  supplied? : T? = None,
) -> Result[ClientRequestComputationKind, ClientRequestTerminalIssue] {
  let source = match
    prepare_request_native_program_input(
      owner,
      input,
      captured,
      reader,
      program_limits.checking.input,
      supplied~,
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(original) => original
  }
  match construct_program_json_preparation(source) {
    Err(issue) => return Err(Preparation(ProgramJson(issue)))
    Ok(_) => ()
  }
  match reconcile_program_json_preparation_structure(source) {
    Err(issue) => return Err(Preparation(ProgramJson(issue)))
    Ok(_) => ()
  }
  // Project the SAME installed publication once. Require reuse of its Catalog;
  // no changed-limit fallback can silently construct another one at check.
  let (update, store, command, catalog) = match
    @source_publication.prepared_published_effect_parts(
      publication, environment,
    ) {
    Err(issue) => return Err(Publication(issue))
    Ok(original) => original
  }
  let child = match
    prepare_request_computation_check_preparation(
      owner,
      input,
      environment,
      None,
      evidence,
      program_limits,
      effect_limits,
      source_catalog=Some(@checked.require_source_catalog_reuse(catalog)),
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(original) => original
  }
  match prepare_program_check_input(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_prelude(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_registry(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_registry(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_contents(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_contents(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_references(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_references(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_policies(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_policies(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_values(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_values(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_views(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_views(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_carriers(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_carriers(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match prepare_program_check_requests(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match reconcile_program_check_requests(child) {
    Err(issue) => return Err(Preparation(ProgramCheck(issue)))
    Ok(_) => ()
  }
  match
    finish_request_computation_preparation(
      owner,
      input,
      update_targets=update,
      store_targets=store,
      command_targets=command,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  request_prepared_computation_kind(owner, input).map_err(issue => {
    Preparation(issue)
  })
}
