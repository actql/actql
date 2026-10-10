///|
/// The physical adapter selects a format explicitly; there is no syntax
/// fallback or transport-specific parser. These are original input documents.
pub(all) enum LocalInput {
  Program(String)
  Aql(String)
}

///|
/// Query names come from trusted Host publication configuration, not from
/// aliases supplied by the Client. A context does not grant Source access.
struct LocalInputContext {
  environment_cid : String
  query : @query.Context
}

///|
pub(all) enum LocalPreparationIssue {
  Context(@frontend.AliasIssue)
  ForeignEnvironment
  Frontend(@frontend.Issue)
  Preparation(@host.ClientProgramPreparationIssue)
  ArrayProfile(@frontend.ArrayProfileIssue)
}

///|
/// Bind the existing query lowerer to a checked publication generation. The
/// Host must first obtain each alias from the existing publication Owner.
pub fn bind_local_input_context(
  environment : @checked.CheckEnvironment,
  aliases : Array[@frontend.PublishedAlias],
  program_id : String,
  parameter_declarations? : @parameters.Declarations? = None,
  input_schemas? : Array[(String, @schema.Schema)] = [],
  source_catalog? : @environment.SourceRequestContracts? = None,
) -> Result[LocalInputContext, LocalPreparationIssue] {
  let environment_cid = @checked.checking_environment_cid(environment)
  match
    @frontend.bind_query_context(
      aliases,
      environment_cid,
      program_id~,
      parameter_declarations~,
      input_schemas~,
      source_catalog~,
    ) {
    Ok(query) => Ok({ environment_cid, query, })
    Err(issue) => Err(Context(issue))
  }
}

///|
/// Both formats enter the same Checker, checked DAG and Stage lowering Owner.
/// Query lowering's parsed Program is retained instead of reparsing generated
/// JSON, which would replace authored provenance. Preparation neither admits
/// a Run nor invokes a Source, Compute, Model or Effect adapter.
pub fn prepare_local_input(
  input : LocalInput,
  environment : @checked.CheckEnvironment,
  bindings : @decode.Cursor?,
  context : LocalInputContext?,
  limits : @host.ClientProgramPreparationLimits,
) -> Result[@host.PreparedClientProgram, LocalPreparationIssue] {
  if context is Some(context) &&
    context.environment_cid != @checked.checking_environment_cid(environment) {
    return Err(ForeignEnvironment)
  }
  let (document, format) = match input {
    Program(document) => (document, @frontend.Json)
    Aql(document) => (document, @frontend.Text)
  }
  let lowered = match
    @frontend.lower(document, format, context.map(value => value.query)) {
    Ok(value) => value
    Err(issue) => return Err(Frontend(issue))
  }
  let prepared = match lowered.program {
    Some(program) =>
      @host.prepare_parsed_effect_free_client_program(
        program, environment, bindings, limits,
      )
    None =>
      @host.prepare_effect_free_client_program(
        lowered.document,
        lowered.format,
        environment,
        bindings,
        limits,
      )
  }
  let prepared = match prepared {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  match
    @frontend.check_array_profile(
      @strategy.graph_program(@host.prepared_client_graph(prepared)),
      max_work=1000000,
      max_slots=100000,
    ) {
    Ok(_) => Ok(prepared)
    Err(issue) => Err(ArrayProfile(issue))
  }
}
