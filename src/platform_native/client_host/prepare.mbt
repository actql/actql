///|
/// The ordinary parser and checked computation own Local preparation. These
/// handles confer neither durable acceptance nor permission to dispatch.
pub enum NativeClientPreparation {
  Computation(@host.PreparedClientProgram)
  EffectComputation(@host.PreparedClientEffectComputation)
}

///|
pub(all) enum NativeClientPreparationIssue {
  Frontend(@frontend.Issue)
  Syntax(@syntax.SyntaxError)
  Computation(@host.ClientProgramPreparationIssue)
  EffectComputation(@host.ClientEffectComputationIssue)
}

///|
/// The Host supplies the audience-authorized query context and configured
/// physical write bindings. A document cannot install a provider or policy.
/// Select the Effect owner from the parsed Program before checking; never
/// retry a rejected Effect-free preparation through a different checker.
pub fn prepare_native_client_program(
  document : String,
  format : @frontend.Format,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  context : @query.Context?,
  evidence : Array[@context.StageCapacityInput],
  limits : @host.ClientEffectComputationLimits,
  source_path? : String = "<source>",
  table_writes? : Array[@query.TableWriteBinding] = [],
) -> Result[NativeClientPreparation, NativeClientPreparationIssue] {
  let lowered = match
    @frontend.lower(document, format, context, source_path~, table_writes~) {
    Ok(value) => value
    Err(issue) => return Err(Frontend(issue))
  }
  let parsed = match lowered.program {
    Some(value) => value
    None =>
      match
        @syntax.parse(
          lowered.document,
          limits.program.checking.input,
          format=lowered.format,
          source_path~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Syntax(issue))
      }
  }
  if @syntax.stages(parsed).any(stage => !@syntax.effect_names(stage).is_empty()) {
    match
      @host.prepare_parsed_client_effect_computation(
        parsed, environment, supplied, evidence, limits,
      ) {
      Ok(value) => Ok(EffectComputation(value))
      Err(issue) => Err(EffectComputation(issue))
    }
  } else {
    match
      @host.prepare_parsed_effect_free_client_program(
        parsed,
        environment,
        supplied,
        limits.program,
      ) {
      Ok(value) => Ok(Computation(value))
      Err(issue) => Err(Computation(issue))
    }
  }
}
