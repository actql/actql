///|
// Default JSON input has no independent document-size support policy. These
// are the existing Int representation ceilings, not a reservation or node
// estimate. The same original Source preflight observes actual wire geometry
// before tree/index acquisition. Depth and stage policy stay independent.
// This immutable recipe is shared runtime DATA, never copied per document.
let request_default_json_input_limits : @syntax.Limits = {
  source: {
    // Existing Source offset/lookahead validation requires strictly below Int max.
    max_input_bytes: 2147483646,
    max_nodes: 2147483647,
    max_depth: @publication_host.client_standard_program_preparation_limits().checking.input.source.max_depth,
  },
  tree: {
    max_nodes: 2147483647,
    max_depth: @publication_host.client_standard_program_preparation_limits().checking.input.tree.max_depth,
    max_string_bytes: 2147483647,
    max_total_string_bytes: 2147483647,
  },
  max_stages: @publication_host.client_standard_program_preparation_limits().checking.input.max_stages,
}

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
) -> Result[Unit, ClientRequestTerminalIssue] {
  let program_limits = {
    ..@publication_host.client_standard_program_preparation_limits(),
    values_max_rows,
  }
  match
    prepare_request_native_source_computation_input(
      owner,
      input,
      captured,
      reader,
      environment,
      publication,
      program_limits.checking,
      supplied~,
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
    None => program_limits
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
) -> Result[Unit, ClientRequestTerminalIssue] {
  let source = match
    prepare_request_program_json_preparation(
      owner, input, document, request_default_json_input_limits,
    ) {
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
