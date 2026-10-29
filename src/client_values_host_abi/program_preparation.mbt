///|
/// One parser-owned Program selects its existing semantic preparation Owner.
/// This selection performs no acquisition, dispatch, approval or apply.
pub enum ClientValuesHostProgramPreparation {
  EffectFree(@host.PreparedClientProgram)
  Effect(@host.PreparedClientEffectComputation)
}

///|
pub(all) enum ClientValuesHostProgramPreparationIssue {
  Input(ClientValuesHostPreparationIssue)
  Syntax(@syntax.SyntaxError)
  EffectFree(@host.ClientProgramPreparationIssue)
  Effect(@host.ClientEffectComputationIssue)
}

///|
#export_name("clientValuesHostPrepareProgram")
pub fn client_values_host_prepare_program(
  document : String,
  format : String,
  environment : @checked.CheckEnvironment,
  parameters : String?,
  publication_environment : @source_publication.PreparedPublishedQueryEnvironment?,
) -> Result[
  ClientValuesHostProgramPreparation,
  ClientValuesHostProgramPreparationIssue,
] {
  let (update_targets, store_targets, command_targets, catalog) = match
    client_values_host_published_effect_parts(
      publication_environment, environment,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(Publication(issue)))
  }
  let (selected, supplied) = match
    client_values_host_program_input(format, parameters) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let limits = @host.client_standard_program_preparation_limits()
  let parsed = match
    @syntax.parse(document, limits.checking.input, format=selected) {
    Ok(value) => value
    Err(issue) => return Err(Syntax(issue))
  }
  // Select before semantic checking. A failed Pure preparation must never
  // be retried as an Effectful Program under a second semantic Owner.
  for stage in @syntax.stages(parsed) {
    if !@syntax.effect_names(stage).is_empty() {
      return @host.prepare_parsed_client_effect_computation(
          parsed,
          environment,
          supplied,
          [],
          client_values_host_effect_limits(),
          update_targets~,
          store_targets~,
          command_targets~,
          source_catalog=catalog,
        )
        .map(value => ClientValuesHostProgramPreparation::Effect(value))
        .map_err(issue => ClientValuesHostProgramPreparationIssue::Effect(issue))
    }
  }
  @host.prepare_parsed_effect_free_client_program(
    parsed,
    environment,
    supplied,
    limits,
    source_catalog=catalog,
  )
  .map(value => ClientValuesHostProgramPreparation::EffectFree(value))
  .map_err(issue => ClientValuesHostProgramPreparationIssue::EffectFree(issue))
}

///|
#export_name("clientValuesHostProgramPreparationKind")
pub fn client_values_host_program_preparation_kind(
  value : ClientValuesHostProgramPreparation,
) -> String {
  match value {
    EffectFree(_) => "effect_free"
    Effect(_) => "effect"
  }
}

///|
#export_name("clientValuesHostProgramPreparationEffectFree")
pub fn client_values_host_program_preparation_effect_free(
  value : ClientValuesHostProgramPreparation,
) -> @host.PreparedClientProgram? {
  match value {
    EffectFree(prepared) => Some(prepared)
    Effect(_) => None
  }
}

///|
#export_name("clientValuesHostProgramPreparationEffect")
pub fn client_values_host_program_preparation_effect(
  value : ClientValuesHostProgramPreparation,
) -> @host.PreparedClientEffectComputation? {
  match value {
    Effect(prepared) => Some(prepared)
    EffectFree(_) => None
  }
}
