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
  match
    prepare_request_native_computation_input(
      owner,
      input,
      captured,
      reader,
      program_limits.checking.input,
      supplied~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  finish_request_original_computation(
    owner, input, environment, publication, evidence, program_limits, effect_limits,
  )
}

///|
/// Same original native input/Program construction; stop on the existing
/// semantic boundary so the trusted Host can supplement before compilation.
pub fn[I, T] prepare_request_native_computation_check(
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
) -> Result[Unit, ClientRequestTerminalIssue] {
  match
    prepare_request_native_computation_input(
      owner,
      input,
      captured,
      reader,
      program_limits.checking.input,
      supplied~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_request_original_computation_check(
    owner, input, environment, publication, evidence, program_limits, effect_limits,
  )
}

///|
fn[I, T] prepare_request_native_computation_input(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
  limits : @syntax.Limits,
  supplied? : T? = None,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let source = match
    prepare_request_native_program_input(
      owner,
      input,
      captured,
      reader,
      limits,
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
  Ok(())
}

///|
fn[I] finish_request_original_computation(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
) -> Result[ClientRequestComputationKind, ClientRequestTerminalIssue] {
  let (program_limits, effect_limits) = request_original_query_check_limits(
    owner, program_limits, effect_limits,
  )
  // Project the SAME installed publication once. Require reuse of its Catalog;
  // no changed-limit fallback can silently construct another one at check.
  let (update, store, command, catalog) = match
    @source_publication.prepared_published_effect_parts(
      publication, environment,
    ) {
    Err(issue) => return Err(Publication(issue))
    Ok(original) => original
  }
  match
    prepare_request_original_computation_check_owned(
      owner, input, environment, catalog, evidence, program_limits, effect_limits,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  finish_request_checked_computation_targets(
    owner, input, update, store, command,
  )
}

///|
// Only the ordinary input driver consumes its just-completed Query lowerer's
// selected generated-Program envelope. Explicit generic check/reuse APIs keep
// the caller's original restrictions. This reads the existing parent slot;
// no new controller, traversal, parse or physical/resource authority is issued.
fn[I] request_original_query_check_limits(
  owner : ClientRequestPreparation[I],
  program : @publication_host.ClientProgramPreparationLimits,
  effect : @publication_host.ClientEffectComputationLimits,
) -> (
  @publication_host.ClientProgramPreparationLimits,
  @publication_host.ClientEffectComputationLimits,
) {
  guard owner.phase == QueryLowered &&
    owner.query_syntax is Some(_) &&
    owner.computation_limits is Some(selected) else {
    return (program, effect)
  }
  (
    selected,
    {
      ..effect,
      program: {
        ..effect.program,
        checking: { ..effect.program.checking, input: selected.checking.input, },
      },
    },
  )
}

///|
/// Complete the already checked SAME Request using the original installed
/// publication's target handles. Policy supplementation changes no Catalog or
/// target declaration; its selected checking Environment stays on the child.
pub fn[I] finish_request_checked_computation(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Result[ClientRequestComputationKind, ClientRequestTerminalIssue] {
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_check is Some(child) &&
    child.arguments is Some(arguments) &&
    arguments.source_catalog is Some(original_catalog) else {
    return Err(Preparation(ForeignOriginal))
  }
  let (update, store, command, catalog) = match
    @source_publication.prepared_published_effect_parts(
      publication, environment,
    ) {
    Err(issue) => return Err(Publication(issue))
    Ok(original) => original
  }
  // The policy-selected child Environment may differ, but its immutable
  // installation Catalog must still be the original one used before checking.
  guard @checked.source_catalog_same_original(original_catalog, catalog) else {
    return Err(Preparation(ForeignOriginal))
  }
  finish_request_checked_computation_targets(
    owner, input, update, store, command,
  )
}

///|
fn[I] finish_request_checked_computation_targets(
  owner : ClientRequestPreparation[I],
  input : I,
  update : @update_targets.UpdateTargetPublication?,
  store : @update_targets.StoreTargetPublication?,
  command : @update_targets.CommandTargetPublication?,
) -> Result[ClientRequestComputationKind, ClientRequestTerminalIssue] {
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

///|
/// Continue the same constructed native/query Program through its checker,
/// retaining the original Source/index/Parameters and Unit working capacity.
/// Later trusted Host policy verification must not force another SDK capture
/// or choose an eventual body before its final checking Environment is known.
pub fn[I] prepare_request_original_computation_check(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let catalog = match
    @source_publication.prepared_published_query_catalog(
      publication, environment,
    ) {
    Err(issue) => return Err(Publication(issue))
    Ok(original) => original
  }
  prepare_request_original_computation_check_owned(
    owner, input, environment, catalog, evidence, program_limits, effect_limits,
  )
}

///|
fn[I] prepare_request_original_computation_check_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  catalog : @checked.PreparedSourceCatalog,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  static_check? : Bool = false,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let selected = if static_check {
    // Existing Local check observes the ordinary semantic verdict, including
    // unsupported authored Effects. It does not demand an execution candidate
    // or reject that same report at a later compiler-only Effect header read.
    owner.computation_limits = Some(program_limits)
    prepare_request_program_check_preparation(
      owner,
      input,
      environment,
      None,
      evidence,
      program_limits.checking,
      source_catalog=Some(@checked.require_source_catalog_reuse(catalog)),
    )
  } else {
    prepare_request_computation_check_preparation(
      owner,
      input,
      environment,
      None,
      evidence,
      program_limits,
      effect_limits,
      source_catalog=Some(@checked.require_source_catalog_reuse(catalog)),
    )
  }
  let child = match selected {
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
  finish_request_computation_check(owner, input)
}
