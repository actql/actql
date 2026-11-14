///|
// The installed default Node driver selects this existing Request/domain
// connection. Explicitly selected limits keep their original separate entry;
// no equality test recognizes a limit packet as the default. Parameters,
// semantic/compiler policy and current Resource ownership are unchanged.
pub fn[I, T] prepare_request_default_source_computation_check(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  evidence : Array[@context.StageCapacityInput],
  values_max_rows : Int?,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  supplied? : T? = None,
  public_primary? : Bool = true,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let original_limits = match
    request_default_program_preparation_limits(owner, input) {
    Err(issue) => return Err(issue)
    Ok(limits) => limits
  }
  let program_limits = { ..original_limits, values_max_rows, }
  match
    prepare_request_native_source_computation_input(
      owner,
      input,
      captured,
      reader,
      environment,
      publication,
      program_limits,
      supplied~,
      public_primary~,
      default_json=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The SAME Source child has already reserved its observed geometry before
  // parsing/indexing and retained the original Program. Carry its selected
  // input bounds into reuse validation; resetting to the standard document
  // envelope here would reject already funded input. Query has no such child;
  // YAML retains the explicit bounds that its original parser selected.
  let program_limits = match owner.program_json {
    None =>
      match (owner.query_syntax, owner.computation_limits, owner.held_program) {
        (Some(_), Some(selected), Some(program)) => {
          // The SAME lowerer has completed and retained this exact Program.
          // Read its O(1) inventory, not text length, a second parser or an
          // inflated shared profile. The initial Request control quote backs
          // these immutable selection records before the checker is called.
          let stages = @syntax.stage_count(program)
          // This remaining legacy work policy is separately tracked for
          // replacement; do not mistake the common structural bound for its
          // former Stage32 denominator while that work correspondence is open.
          let original_stages = @publication_host.client_standard_program_preparation_limits().checking.compilation.structure.stages
          let original_work = selected.checking.compilation.work
          // The default generated representation selects bounded checking work
          // for its actual normalized Stage groups. Keep the installed work /
          // Stage envelope; do not change the shared profile or any explicit
          // caller's budget. This ceiling is not a debit or storage allocation.
          guard original_stages > 0 && original_work >= 0 else {
            return Err(Preparation(Policy))
          }
          let groups = (stages.to_int64() + original_stages.to_int64() - 1L) /
            original_stages.to_int64()
          guard @execution.checked_preparation_add_product(
              0L,
              Int64::max(1L, groups),
              original_work.to_int64(),
            )
            is Some(work) &&
            work <= 2147483647L else {
            return Err(Preparation(ProgramCheck(Overflow)))
          }
          let selected = {
            ..selected,
            checking: {
              ..selected.checking,
              compilation: {
                ..selected.checking.compilation,
                work: work.to_int(),
                structure: {
                  ..selected.checking.compilation.structure,
                  stages,
                },
              },
            },
          }
          owner.computation_limits = Some(selected)
          selected
        }
        _ => program_limits
      }
    Some(source) =>
      {
        ..program_limits,
        checking: { ..program_limits.checking, input: source.limits, },
      }
  }
  let effect_limits = {
    ..effect_limits,
    program: {
      ..effect_limits.program,
      checking: {
        ..effect_limits.program.checking,
        input: program_limits.checking.input,
      },
    },
  }
  prepare_request_original_computation_check(
    owner, input, environment, publication, evidence, program_limits, effect_limits,
  )
}

///|
// Connect the existing original Program JSON preflight, tree/index and Program
// phases. Source's original Unicode traversal supplies node/Text geometry;
// document length is never substituted for retained node demand. A failed grow
// leaves the same child/ready report on this Request for ordinary cleanup.
fn[I] prepare_request_default_json_computation_input(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  limits : @syntax.Limits,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let source = match
    prepare_request_program_json_preparation(owner, input, document, limits) {
    Err(issue) => return Err(Preparation(issue))
    Ok(original) => original
  }
  while true {
    match advance_program_json_preparation(source, 256) {
      Err(issue) => return Err(Preparation(ProgramJson(issue)))
      Ok(@source.JsonSourceContinue(..)) => continue
      Ok(@source.JsonSourceFailed(error, ..)) =>
        return Err(Preparation(ProgramJson(Syntax(@syntax.Parse(error)))))
      Ok(@source.JsonSourceReady(_, ..)) => break
    }
  }
  match finish_program_json_preparation(source) {
    Err(issue) => return Err(Preparation(ProgramJson(issue)))
    Ok(_) => ()
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
